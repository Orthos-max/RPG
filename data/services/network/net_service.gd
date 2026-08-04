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

var _peer: ENetMultiplayerPeer = null


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


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
func leave() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	players.clear()
	last_state.clear()
	join_code = ""
	three_way = false


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
func broadcast_state(state: Dictionary) -> void:
	if role != Role.HOST:
		return
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


@rpc("authority", "call_local", "reliable")
func _rpc_start_battle(map_path: String, with_ciel: bool = false) -> void:
	scene_path = map_path
	three_way = with_ciel
	_apply_session_roles()
	battle_started.emit(map_path)
#endregion


#region Signaux de connexion
func _on_peer_connected(id: int) -> void:
	if role == Role.HOST:
		players[id] = {"name": "Invité", "side": TeamDataClass.Side.OPPONENT, "ready": true}
		_apply_session_roles()
		lobby_updated.emit()


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peer_left.emit(id)
	lobby_updated.emit()
	# L'invité est parti : l'IA locale reprend son camp pour ne pas figer la partie.
	if role == Role.HOST:
		var session: Node = get_node_or_null("/root/GameSession")
		if session:
			session.set_controller(TeamDataClass.Side.OPPONENT, TeamDataClass.Controller.LOCAL_AI)


func _on_connected_to_server() -> void:
	players[multiplayer.get_unique_id()] = {
		"name": "Invité", "side": TeamDataClass.Side.OPPONENT, "ready": true,
	}
	_apply_session_roles()
	joined.emit()
	lobby_updated.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit("l'hôte n'a pas répondu")


func _on_server_disconnected() -> void:
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
