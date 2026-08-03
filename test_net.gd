extends SceneTree
## Test réseau à deux processus (M3/M4).
##
## Hôte  : godot --headless --path . --script test_net.gd -- host
## Invité: godot --headless --path . --script test_net.gd -- client <CODE>
##
## Le script `scripts/test_net.sh` enchaîne les deux et vérifie les sorties.
## Ce test couvre le transport : code d'accès, connexion, diffusion d'état,
## relais d'ordre et acquittement. Le déroulé d'une bataille en réseau demande
## un rendu (collisions de tuiles) et se vérifie fenêtre ouverte.

const TIMEOUT_SECONDS: float = 15.0

var _net: Node = null
var _state_seen: bool = false
var _feedback: Dictionary = {}
var _peer_seen: bool = false
## Variable membre et non locale : les lambdas GDScript capturent par valeur.
var _joined: bool = false


func _init() -> void:
	await process_frame
	_net = root.get_node_or_null("Network")
	if not _net:
		print("NET_FAIL autoload Network introuvable")
		quit(1)
		return

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var role: String = args[0] if args.size() > 0 else "host"

	if role == "host":
		await _run_host()
	else:
		await _run_client(args[1] if args.size() > 1 else "")


#region Hôte
func _run_host() -> void:
	var result: Dictionary = _net.host_game()
	if not bool(result["ok"]):
		print("NET_FAIL hébergement : ", result["reason"])
		quit(1)
		return

	print("NET_CODE=", result["code"])
	print("NET_IP=", result["ip"])
	# Aller-retour du code : il doit redonner l'adresse de départ.
	var decoded: String = _net.decode_code(str(result["code"]))
	print("NET_DECODE_OK=", decoded == str(result["ip"]))

	_net.peer_left.connect(func(_id: int) -> void: _peer_seen = true)
	_net.lobby_updated.connect(func() -> void:
		if _net.players.size() >= 2:
			_peer_seen = true)

	# Attente de l'invité
	if not await _wait_for(func() -> bool: return _peer_seen):
		print("NET_FAIL aucun invité connecté")
		quit(1)
		return
	print("NET_PEER_CONNECTED=true")

	# Diffusion d'un état de test
	_net.broadcast_state({"seq": 1, "turn": "opponent", "stage_name": "select_pawn", "pawns": []})

	# Attente d'un ordre relayé : il doit atteindre la validation (et être
	# rejeté ici, puisqu'aucune bataille ne tourne dans ce test).
	var recorder: Node = root.get_node_or_null("BattleRecorder")
	var got_command := func() -> bool:
		if not recorder:
			return false
		for e in recorder.events:
			if str(e.get("kind_name", "")) == "command_rejected":
				return true
		return false

	if not await _wait_for(got_command):
		print("NET_FAIL aucun ordre relayé reçu")
		quit(1)
		return

	print("NET_COMMAND_RELAYED=true")
	await create_timer(1.0).timeout  # laisse l'invité recevoir son acquittement
	_net.leave()
	print("NET_HOST_DONE")
	quit(0)
#endregion


#region Invité
func _run_client(code: String) -> void:
	if code.is_empty():
		print("NET_FAIL code manquant")
		quit(1)
		return

	_net.state_received.connect(func(_s: Dictionary) -> void: _state_seen = true)
	_net.command_feedback.connect(func(f: Dictionary) -> void: _feedback = f)

	_net.joined.connect(func() -> void: _joined = true)
	_net.connection_failed.connect(func(reason: String) -> void:
		print("NET_FAIL connexion : ", reason))

	var result: Dictionary = _net.join_game(code)
	if not bool(result["ok"]):
		print("NET_FAIL jointure : ", result["reason"])
		quit(1)
		return

	if not await _wait_for(func() -> bool: return _joined):
		print("NET_FAIL pas de connexion à l'hôte")
		quit(1)
		return
	print("NET_JOINED=true")

	if not await _wait_for(func() -> bool: return _state_seen):
		print("NET_FAIL aucun état reçu")
		quit(1)
		return
	print("NET_STATE_RECEIVED=true")

	# Ordre volontairement inapplicable ici : on teste le relais et l'acquittement.
	_net.send_command({"action": "select_pawn", "name": "Brigand#1"})

	if not await _wait_for(func() -> bool: return not _feedback.is_empty()):
		print("NET_FAIL aucun acquittement")
		quit(1)
		return

	print("NET_FEEDBACK_OK=", bool(_feedback.get("ok", false)))
	print("NET_FEEDBACK_ERROR=", str(_feedback.get("error", "")))
	_net.leave()
	print("NET_CLIENT_DONE")
	quit(0)
#endregion


## Attend qu'une condition devienne vraie, dans la limite du délai imparti.
func _wait_for(condition: Callable) -> bool:
	var elapsed: float = 0.0
	while elapsed < TIMEOUT_SECONDS:
		if condition.call():
			return true
		await create_timer(0.2).timeout
		elapsed += 0.2
	return false
