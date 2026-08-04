extends Node
## Network (autoload) — parties privées entre amis, par code d'accès (M3/M4).
##
## Pas de matchmaking ni de serveur : l'hôte ouvre un port, son adresse est
## encodée dans un code court que les amis saisissent. L'hôte fait autorité —
## il simule la bataille et valide chaque ordre reçu, exactement comme pour Ciel
## (même vocabulaire de commandes, même validation).
##
## Répartition : l'hôte joue le camp bleu, l'invité le camp rouge.

signal lobby_updated()
signal hosted(code: String)
signal joined()
signal connection_failed(reason: String)
signal peer_left(id: int)
signal battle_started(scene_path: String)
## La place d'un invité déconnecté lui reste réservée pendant `seconds`
signal seat_reserved(side: int, seconds: float)
## L'invité est revenu et a repris sa place
signal seat_restored(side: int)
## Le délai de grâce est écoulé : la place est perdue
signal seat_expired(side: int)
## L'invité tente de se reconnecter (numéro de tentative)
signal reconnecting(attempt: int)
signal state_received(state: Dictionary)
signal command_feedback(feedback: Dictionary)

const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

## Port fixe : le code d'accès n'a ainsi qu'à transporter l'adresse
const PORT: int = 24710
## Une seule autre personne par partie (duel privé)
const MAX_CLIENTS: int = 1
## Alphabet sans caractères ambigus (ni I, ni O, ni 0, ni 1)
const ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
## 7 caractères de 5 bits couvrent les 32 bits d'une adresse IPv4
const CODE_LENGTH: int = 7
## Durée pendant laquelle la place d'un invité déconnecté lui est gardée
const SEAT_GRACE_SECONDS: float = 90.0
## Intervalle entre deux tentatives de reconnexion automatique (invité)
const RECONNECT_INTERVAL: float = 3.0
## Délai avant de renvoyer carte et état à un pair qui vient de (re)venir
const RESYNC_DELAY: float = 0.5

enum Role { NONE = 0, HOST = 1, CLIENT = 2 }

var role: int = Role.NONE
## Code d'accès de la partie courante (hôte) ou saisi (client)
var join_code: String = ""
## Pairs connus : id → {name, side, ready}
var players: Dictionary = {}
## Dernier état reçu de l'hôte (client uniquement)
var last_state: Dictionary = {}
## Carte choisie par l'hôte
var scene_path: String = "res://assets/maps/level/map_level.tscn"
## Ciel s'invite comme troisième camp (M5) — décidé par l'hôte, propagé à l'invité
var three_way: bool = false

## Une bataille est-elle en cours ? (sert à remettre un revenant dans la carte)
var in_battle: bool = false

var _peer: ENetMultiplayerPeer = null
## Hôte : places gardées pour un invité tombé
var _seats := SeatRegistry.new()
## Invité : quand retenter la connexion après une coupure
var _reconnect := ReconnectPlan.new()
## Hôte : dernier état diffusé, renvoyé tel quel à un invité qui revient
var _last_broadcast: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Fait avancer les deux horloges de la reconnexion (hôte et invité).
##
## Rien de coûteux : deux comparaisons de dates tant que personne n'est tombé.
func _process(_delta: float) -> void:
	var now: float = Time.get_unix_time_from_system()

	if role == Role.HOST:
		if _seats.is_empty():
			return
		var lost: int = _seats.take_expired(now)
		if lost != -1:
			print_rich("[color=orange]⌛ Place perdue : %s ne revient plus, l'IA locale garde le camp.[/color]"
				% TeamDataClass.side_name(lost))
			seat_expired.emit(lost)
		return

	if not _reconnect.is_active():
		return

	if _reconnect.is_expired(now):
		_reconnect.cancel()
		leave()
		connection_failed.emit("impossible de retrouver l'hôte")
		return

	# Une tentative en cours occupe déjà le pair : on attend son verdict.
	if role == Role.NONE and _reconnect.consume_attempt(now):
		reconnecting.emit(_reconnect.attempt)
		print_rich("[color=cyan]↻ Reconnexion — tentative %d (%.0f s restantes)[/color]"
			% [_reconnect.attempt, _reconnect.remaining(now)])
		_open_client(_reconnect.code)


#region Code d'accès
## Encode une adresse IPv4 en code court lisible à l'oral.
static func encode_code(ip: String) -> String:
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return ""
	var value: int = 0
	for part in parts:
		var octet: int = int(part)
		if octet < 0 or octet > 255:
			return ""
		value = (value << 8) | octet

	var code: String = ""
	for i in CODE_LENGTH:
		code = ALPHABET[value & 31] + code
		value >>= 5
	return code


## Décode un code d'accès en adresse IPv4 ("" si le code est invalide).
static func decode_code(code: String) -> String:
	var clean: String = code.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if clean.length() != CODE_LENGTH:
		return ""

	var value: int = 0
	for i in clean.length():
		var index: int = ALPHABET.find(clean[i])
		if index == -1:
			return ""
		value = (value << 5) | index

	return "%d.%d.%d.%d" % [
		(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255
	]


## Adresse IPv4 locale de cette machine (celle que les amis doivent joindre).
##
## Les machines ont souvent plusieurs interfaces (Wi-Fi, VPN, VM…) : on privilégie
## les plages privées d'un réseau domestique, dans l'ordre où un ami a le plus de
## chances de nous joindre. `CIEL_HOST_IP` permet de trancher à la main.
static func local_ip() -> String:
	var forced: String = OS.get_environment("CIEL_HOST_IP")
	if not forced.is_empty():
		return forced

	var candidates: Array[String] = []
	for address in IP.get_local_addresses():
		var ip: String = str(address)
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		candidates.append(ip)

	for prefix in ["192.168.", "10."]:
		for ip in candidates:
			if ip.begins_with(prefix):
				return ip
	# 172.16.0.0 – 172.31.255.255
	for ip in candidates:
		if ip.begins_with("172."):
			var second: int = int(ip.split(".")[1])
			if second >= 16 and second <= 31:
				return ip
	# Reste : adresses de VPN/CGNAT (100.64/10) ou publiques, faute de mieux.
	if not candidates.is_empty():
		return candidates[0]
	return "127.0.0.1"
#endregion


#region Hébergement / connexion
## Ouvre une partie. [returns] {ok, code, ip, reason}
func host_game(map_path: String = "") -> Dictionary:
	leave()
	if not map_path.is_empty():
		scene_path = map_path

	_peer = ENetMultiplayerPeer.new()
	var err: int = _peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		_peer = null
		return {"ok": false, "reason": "port %d indisponible (erreur %d)" % [PORT, err]}

	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	var ip: String = local_ip()
	join_code = encode_code(ip)
	players = {1: {"name": "Hôte", "side": TeamDataClass.Side.PLAYER, "ready": true}}

	_apply_session_roles()
	hosted.emit(join_code)
	lobby_updated.emit()
	return {"ok": true, "code": join_code, "ip": ip, "reason": ""}


## Rejoint une partie à partir d'un code. [returns] {ok, ip, reason}
func join_game(code: String) -> Dictionary:
	leave()
	return _open_client(code)


## Ouvre le pair client vers l'hôte désigné par un code (première tentative ou retour).
func _open_client(code: String) -> Dictionary:
	var ip: String = decode_code(code)
	if ip.is_empty():
		return {"ok": false, "reason": "code invalide (%d caractères attendus)" % CODE_LENGTH}

	_peer = ENetMultiplayerPeer.new()
	var err: int = _peer.create_client(ip, PORT)
	if err != OK:
		_peer = null
		return {"ok": false, "reason": "connexion impossible vers %s (erreur %d)" % [ip, err]}

	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	join_code = code.strip_edges().to_upper()
	return {"ok": true, "ip": ip, "reason": ""}


## Quitte la partie et remet la session en local.
##
## [param keep_reconnect] laisse en place ce qu'il faut pour retenter la
## connexion : sans cela, une coupure effacerait le code et la configuration
## des camps, et l'invité ne pourrait plus revenir.
func leave(keep_reconnect: bool = false) -> void:
	# Un départ volontaire de l'hôte n'est pas une coupure : on le dit avant de
	# fermer, sinon l'invité passerait 90 s à retenter une partie qui n'existe plus.
	if role == Role.HOST and _peer and multiplayer.multiplayer_peer == _peer and not players.is_empty():
		_rpc_host_closing.rpc()
		if _peer.host:
			_peer.host.flush()

	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	players.clear()
	last_state.clear()
	join_code = ""
	_seats.clear()
	_last_broadcast.clear()
	if not keep_reconnect:
		three_way = false
		in_battle = false
		_reconnect.cancel()


## Une reconnexion est-elle en cours (invité) ?
func is_reconnecting() -> bool:
	return _reconnect.is_active()


## Secondes restantes à l'invité pour revenir (0 hors reconnexion).
func reconnect_remaining() -> float:
	return _reconnect.remaining(Time.get_unix_time_from_system())


## Numéro de la tentative de reconnexion en cours (0 si aucune).
func reconnect_attempt() -> int:
	return _reconnect.attempt


## Places gardées pour un invité absent : camp → secondes restantes.
func reserved_seats() -> Dictionary:
	return _seats.remaining_all(Time.get_unix_time_from_system())


## Hôte : coupe la liaison d'un pair.
##
## Sa place lui reste gardée comme pour n'importe quelle coupure — c'est ce qui
## permet de vérifier tout le chemin de reconnexion à deux processus
## (`scripts/test_net.sh`), et ce qui servirait d'exclusion le jour venu.
func drop_peer(id: int) -> void:
	if role == Role.HOST and _peer:
		_peer.disconnect_peer(id)


## Sommes-nous connectés à une partie (hôte ou invité) ?
func is_online() -> bool:
	return role != Role.NONE and multiplayer.multiplayer_peer != null


## Cette instance fait-elle autorité sur la simulation ?
func is_authority() -> bool:
	return role != Role.CLIENT


## Le camp jouable par cette instance.
##
## À trois camps (M5), l'invité prend le troisième camp : le camp rouge revient
## à Ciel, qui joue contre les deux humains.
func local_side() -> int:
	if role != Role.CLIENT:
		return TeamDataClass.Side.PLAYER
	return TeamDataClass.Side.GUEST if three_way else TeamDataClass.Side.OPPONENT


## Camp confié à l'invité distant.
func guest_side() -> int:
	return TeamDataClass.Side.GUEST if three_way else TeamDataClass.Side.OPPONENT


## L'hôte choisit d'inviter Ciel dans la partie (M5).
func set_three_way(enabled: bool) -> void:
	if role == Role.CLIENT:
		return
	three_way = enabled
	_apply_session_roles()
	lobby_updated.emit()
#endregion


#region Déroulé de la partie
## L'hôte lance la bataille : tout le monde charge la même carte.
func start_battle(map_path: String = "") -> void:
	if role != Role.HOST:
		return
	if not map_path.is_empty():
		scene_path = map_path
	_rpc_start_battle.rpc(scene_path, three_way)
	_rpc_start_battle(scene_path, three_way)


## Client → hôte : proposer un ordre (même vocabulaire que CielAI).
func send_command(command: Dictionary) -> void:
	if role == Role.CLIENT:
		_rpc_submit_command.rpc_id(1, command)
	elif role == Role.HOST:
		_apply_command(1, command)


## Hôte → clients : diffuser l'état de la bataille.
##
## Le dernier état est conservé : c'est lui qu'on renvoie à un invité qui revient.
func broadcast_state(state: Dictionary) -> void:
	if role != Role.HOST:
		return
	_last_broadcast = state
	_rpc_push_state.rpc(state)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_command(command: Dictionary) -> void:
	if role != Role.HOST:
		return
	_apply_command(multiplayer.get_remote_sender_id(), command)


## Applique un ordre distant via le même chemin validé que Ciel.
func _apply_command(sender_id: int, command: Dictionary) -> void:
	var ciel: Node = get_node_or_null("/root/CielAI")
	if not ciel:
		return
	var result: Dictionary = ciel.push_command(command)
	if sender_id != 1:
		_rpc_command_feedback.rpc_id(sender_id, {
			"ok": bool(result.get("ok", false)),
			"action": str(result.get("action", "")),
			"error": str(result.get("error", "")),
		})


@rpc("authority", "call_remote", "reliable")
func _rpc_command_feedback(feedback: Dictionary) -> void:
	command_feedback.emit(feedback)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_push_state(state: Dictionary) -> void:
	last_state = state
	state_received.emit(state)


## État complet renvoyé à un invité qui revient.
##
## Diffusion courante et resynchronisation ne voyagent pas pareil : la première
## est un flux qu'un paquet perdu n'abîme pas (le suivant corrige), la seconde
## est l'unique instantané qui remet le revenant dans la bataille — elle part
## donc en fiable, quitte à arriver un poil plus tard.
@rpc("authority", "call_remote", "reliable")
func _rpc_resync_state(state: Dictionary) -> void:
	last_state = state
	state_received.emit(state)


## L'hôte referme la partie de son plein gré (par opposition à une coupure).
@rpc("authority", "call_remote", "reliable")
func _rpc_host_closing() -> void:
	in_battle = false
	_reconnect.cancel()


@rpc("authority", "call_local", "reliable")
func _rpc_start_battle(map_path: String, with_ciel: bool = false) -> void:
	scene_path = map_path
	three_way = with_ciel
	in_battle = true
	_apply_session_roles()
	battle_started.emit(map_path)
#endregion


#region Signaux de connexion
func _on_peer_connected(id: int) -> void:
	if role != Role.HOST:
		return

	var side: int = guest_side()
	players[id] = {"name": "Invité", "side": side, "ready": true}

	# Une place gardée signifie que c'est un retour, pas une première connexion :
	# on lui rend son camp et son contrôleur d'origine plutôt que de tout rejouer.
	var restored: int = _seats.claim(side, Time.get_unix_time_from_system())
	if restored == -1:
		_apply_session_roles()
		lobby_updated.emit()
		return

	var session: Node = get_node_or_null("/root/GameSession")
	if session:
		session.set_controller(side, restored, "Invité")
	print_rich("[color=green]↺ %s a repris sa place.[/color]" % TeamDataClass.side_name(side))
	seat_restored.emit(side)
	lobby_updated.emit()
	_resync_peer(id)


## Renvoie à un revenant tout ce qu'il a manqué : la carte, puis l'état complet.
##
## L'ordre compte — il doit recharger la bataille avant d'y appliquer un
## instantané, sinon son miroir n'a rien à mettre à jour.
##
## L'envoi attend quelques frames : émis depuis le signal de connexion lui-même,
## il partirait avant que le pair soit prêt à recevoir des RPC, et se perdrait
## silencieusement (constaté à deux processus).
func _resync_peer(id: int) -> void:
	if not in_battle:
		return
	await get_tree().create_timer(RESYNC_DELAY).timeout
	if role != Role.HOST or not players.has(id):
		return  # Reparti entre-temps.
	_rpc_start_battle.rpc_id(id, scene_path, three_way)
	if not _last_broadcast.is_empty():
		_rpc_resync_state.rpc_id(id, _last_broadcast)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peer_left.emit(id)
	lobby_updated.emit()
	if role != Role.HOST:
		return

	# L'invité est parti : l'IA locale reprend son camp pour ne pas figer la
	# partie, mais la place lui reste gardée le temps qu'il revienne.
	var side: int = guest_side()
	var session: Node = get_node_or_null("/root/GameSession")
	var previous: int = session.controller_for(side) if session else TeamDataClass.Controller.REMOTE_PLAYER
	if session:
		session.set_controller(side, TeamDataClass.Controller.LOCAL_AI)

	if not in_battle:
		return  # Hors bataille, rien à garder : il n'a qu'à rejoindre le salon.
	_seats.reserve(side, Time.get_unix_time_from_system(), SEAT_GRACE_SECONDS, previous)
	print_rich("[color=orange]⏳ %s a été coupé — place gardée %d s.[/color]"
		% [TeamDataClass.side_name(side), int(SEAT_GRACE_SECONDS)])
	seat_reserved.emit(side, SEAT_GRACE_SECONDS)


func _on_connected_to_server() -> void:
	players[multiplayer.get_unique_id()] = {
		"name": "Invité", "side": guest_side(), "ready": true,
	}
	_apply_session_roles()

	if _reconnect.is_active():
		_reconnect.cancel()
		print_rich("[color=green]↺ Reconnecté à l'hôte.[/color]")
		seat_restored.emit(local_side())
	else:
		joined.emit()
	lobby_updated.emit()


func _on_connection_failed() -> void:
	# En reconnexion, un échec n'est qu'une tentative de plus : on garde le plan
	# et `_process` réessaiera jusqu'à la fin du délai de grâce.
	if _reconnect.is_active():
		leave(true)
		return
	leave()
	connection_failed.emit("l'hôte n'a pas répondu")


func _on_server_disconnected() -> void:
	# En pleine bataille, une coupure n'est pas un abandon : on garde le code et
	# on retente en boucle. Hors bataille (salon), l'hôte est simplement parti.
	if in_battle and not _reconnect.is_active():
		_reconnect.start(join_code, Time.get_unix_time_from_system(),
			SEAT_GRACE_SECONDS, RECONNECT_INTERVAL)
		leave(true)
		reconnecting.emit(0)
		return
	leave()
	connection_failed.emit("l'hôte a quitté la partie")


## Aligne GameSession sur la répartition réseau.
##
## À deux camps : l'hôte tient le bleu, l'invité le rouge.
## À trois camps (M5) : l'hôte le bleu, l'invité le vert, Ciel le rouge.
func _apply_session_roles() -> void:
	var session: Node = get_node_or_null("/root/GameSession")
	if not session:
		return
	session.set_mode(session.Mode.NETWORK)
	session.join_code = join_code
	session.set_three_way(three_way)
	session.set_controller(TeamDataClass.Side.PLAYER, TeamDataClass.Controller.LOCAL_PLAYER,
		"Hôte" if role == Role.HOST else "Adversaire distant")
	session.set_controller(guest_side(), TeamDataClass.Controller.REMOTE_PLAYER,
		"Invité" if role == Role.HOST else "Vous")
	if three_way:
		session.set_controller(TeamDataClass.Side.OPPONENT, TeamDataClass.Controller.CIEL_AI)
#endregion
