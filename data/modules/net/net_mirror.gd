class_name NetMirror
extends Node
## Côté invité : reflète la bataille de l'hôte et transforme les clics en ordres.
##
## L'hôte fait autorité — l'invité ne simule rien. Ce nœud :
##   1. neutralise la boucle de tour locale (sinon deux simulations divergeraient) ;
##   2. applique les instantanés reçus (positions, PV, morts) ;
##   3. traduit les clics en commandes du protocole (select_pawn / move / attack)
##      et les envoie à l'hôte, qui les valide comme celles de Ciel.

const EXECUTOR = preload("res://data/models/world/ai/ai_executor.gd")
const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

## Niveau local, simple reflet de celui de l'hôte
var level: TacticsLevel = null

var _hud: Label = null
var _tiles: Dictionary = {}     ## "col,row" → TacticsTile
var _last_seq: int = -1
var _selected: String = ""
## Liaison coupée : la barre affiche le décompte au lieu de l'état de la partie
var _offline: bool = false


func _ready() -> void:
	var net: Node = _net()
	if net:
		net.state_received.connect(_on_state)
		net.command_feedback.connect(_on_feedback)
		net.reconnecting.connect(_on_reconnecting)
		net.seat_restored.connect(_on_seat_restored)
		net.connection_failed.connect(_on_connection_lost)
	_build_hud()
	# La simulation locale est coupée : seul l'hôte décide.
	if level:
		level.set_physics_process(false)
	call_deferred("_index_tiles")


func _exit_tree() -> void:
	var net: Node = _net()
	if not net:
		return
	for pair in [
		[net.state_received, _on_state], [net.command_feedback, _on_feedback],
		[net.reconnecting, _on_reconnecting], [net.seat_restored, _on_seat_restored],
		[net.connection_failed, _on_connection_lost],
	]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


## Nœud de camp correspondant à une étiquette d'équipe de `ai_state.json`.
func _camp_for_team(team: String) -> Node:
	for camp in level.camps:
		if is_instance_valid(camp) and TeamDataClass.state_team_name(
				TeamDataClass.side_for_camp_node(camp)) == team:
			return camp
	# Repli sur l'ancien découpage à deux camps.
	return level.player if team == "player" else level.opponent


#region Réception de l'état
func _on_state(state: Dictionary) -> void:
	if not level or not is_instance_valid(level):
		return
	var seq: int = int(state.get("seq", 0))
	if seq <= _last_seq:
		return
	_last_seq = seq

	if _tiles.is_empty():
		_index_tiles()

	for entry in state.get("pawns", []):
		_apply_pawn(entry)

	_update_hud(state)


func _apply_pawn(entry: Dictionary) -> void:
	# Le camp est retrouvé par son étiquette d'équipe : à trois camps (M5), il
	# faut savoir distinguer « guest » de « opponent ».
	var team_node: Node = _camp_for_team(str(entry.get("team", "")))
	if not team_node:
		return
	var pawn: Node = EXECUTOR.find_pawn_by_name(team_node, str(entry.get("name", "")))
	if not pawn:
		return

	# Position : on suit l'hôte, sans rejouer le pathfinding.
	var key: String = "%d,%d" % [int(entry.get("grid_col", -1)), int(entry.get("grid_row", -1))]
	if _tiles.has(key):
		var tile: Node3D = _tiles[key]
		pawn.res.pathfinding_tilestack = []
		pawn.global_position = tile.global_position + Vector3(0, 0.5, 0)

	# PV et état
	pawn.stats.hp = int(entry.get("hp", pawn.stats.hp))
	pawn.res.can_move = bool(entry.get("can_move", true))
	pawn.res.can_attack = bool(entry.get("can_attack", true))
	if not bool(entry.get("alive", true)) and pawn.visible:
		pawn.visible = false
#endregion


#region Envoi des ordres
func _unhandled_input(event: InputEvent) -> void:
	if not level or not _net() or not _net().is_online():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				_send({"action": "end_pawn"})
			KEY_T:
				_send({"action": "end_turn"})
			KEY_G:
				_send({"action": "guard"})
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var pawn: Node = _pawn_under_mouse()
	if pawn:
		var pawn_name: String = EXECUTOR.display_name(pawn)
		if pawn.get_parent() == level.opponent:
			# Un de mes pions : je le sélectionne.
			_selected = pawn_name
			_send({"action": "select_pawn", "name": pawn_name})
		else:
			# Un pion adverse : j'attaque.
			_send({"action": "attack", "name": pawn_name})
		return

	var tile: Node = _tile_under_mouse()
	if tile:
		var grid: Vector2i = TacticsGrid.tile_to_grid(level.arena, tile)
		_send({"action": "move", "col": grid.x, "row": grid.y})


func _send(command: Dictionary) -> void:
	var net: Node = _net()
	if net:
		net.send_command(command)
		_set_hud_line("→ %s envoyé" % str(command.get("action", "")))


## Décompte de reconnexion — n'affiche quelque chose que liaison coupée.
func _process(_delta: float) -> void:
	if not _offline:
		return
	var net: Node = _net()
	if not net:
		return
	_set_hud_line("⚠ Liaison perdue — reconnexion (tentative %d, %d s restantes)" % [
		maxi(1, int(net.reconnect_attempt())), int(ceilf(net.reconnect_remaining()))
	])


func _on_reconnecting(_attempt: int) -> void:
	_offline = true


func _on_seat_restored(_side: int) -> void:
	_offline = false
	# La carte est rechargée par [Main] : ce miroir-ci va disparaître, le message
	# ne sert qu'au cas où l'hôte renvoie l'état sans redemander la scène.
	_last_seq = -1
	_set_hud_line("✔ Reconnecté — la bataille reprend")


func _on_connection_lost(reason: String) -> void:
	_offline = false
	_set_hud_line("⛔ Partie interrompue : %s" % reason)


func _on_feedback(feedback: Dictionary) -> void:
	if bool(feedback.get("ok", false)):
		_set_hud_line("✔ %s accepté" % str(feedback.get("action", "")))
	else:
		_set_hud_line("⛔ %s refusé : %s" % [
			str(feedback.get("action", "")), str(feedback.get("error", ""))
		])
#endregion


#region Interne
func _index_tiles() -> void:
	if not level or not level.arena:
		return
	for tile in TacticsGrid.tiles(level.arena):
		var grid: Vector2i = TacticsGrid.tile_to_grid(level.arena, tile)
		_tiles["%d,%d" % [grid.x, grid.y]] = tile


func _pawn_under_mouse() -> Node:
	var hit: Object = _raycast(2)
	return hit if hit is TacticsPawn else null


func _tile_under_mouse() -> Node:
	var hit: Object = _raycast(1)
	return hit if hit is TacticsTile else null


## Raycast depuis la caméra vers le curseur, sur un masque de collision donné.
func _raycast(mask: int) -> Object:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	if not camera:
		return null
	var mouse: Vector2 = viewport.get_mouse_position()
	var params := PhysicsRayQueryParameters3D.create(
		camera.project_ray_origin(mouse),
		camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * 1000.0
	)
	params.collision_mask = mask
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(params)
	return hit.get("collider", null)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11
	add_child(layer)

	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hud.offset_top = -78
	_hud.offset_bottom = -12
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color("#f5c842"))
	_hud.text = "Invité — clic sur ton pion, puis sur une case ou un ennemi.  E : finir le pion  ·  T : finir le tour"
	layer.add_child(_hud)


func _update_hud(state: Dictionary) -> void:
	var turn: String = str(state.get("turn", "?"))
	var mine: bool = turn == "opponent"
	_set_hud_line("%s — %s%s" % [
		"À toi de jouer" if mine else "Tour de l'hôte",
		str(state.get("stage_name", "")),
		("  ·  pion actif : " + str(state.get("current_pawn", ""))) if state.get("current_pawn", "") != "" else "",
	])


func _set_hud_line(text: String) -> void:
	if _hud:
		_hud.text = "%s\nE : finir le pion  ·  T : finir le tour  ·  G : garde" % text


func _net() -> Node:
	return get_node_or_null("/root/Network")
#endregion
