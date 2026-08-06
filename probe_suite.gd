extends SceneTree
## Sonde : poursuivre le tour au-delà du déplacement — attaque, fin de tour, IA.

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

var _main: Node
var _level: Node
var _cam: Camera3D
var _part: Node
var _log: Array = []


func _init() -> void:
	await create_timer(0.2).timeout
	_main = load("res://assets/scene/main.tscn").instantiate()
	root.add_child(_main)
	await physics_frame
	_main._on_new_game(DIFF.Level.NORMAL, true)
	await physics_frame
	_main._on_battle_requested()
	for _i in 90:
		await physics_frame
	_level = _find(_main, "TacticsLevel")
	_cam = root.get_camera_3d()
	_part = _level.participant
	var runner: Node = _level.get_node_or_null("ChapterRunner")
	var phase: Node = runner.get_node_or_null("DeploymentPhase") if runner else null
	if phase and phase.has_method("confirm"):
		phase.confirm()
	for _i in 60:
		await physics_frame

	# --- 1. Amener une unité au contact d'un ennemi ---
	var pawn: Node3D = _first_actable()
	var foe: Node3D = _nearest_foe(pawn)
	_note("pion %s @ %s   ennemi %s @ %s   distance %.1f" % [
		pawn.name, _cell(pawn), foe.name, _cell(foe),
		pawn.global_position.distance_to(foe.global_position)])

	await _click_on(pawn.global_position + Vector3(0, 0.6, 0))
	_press("Move")
	for _i in 20: await physics_frame
	var dest: Node3D = _closest_reachable_to(foe)
	if not dest:
		_note("ÉCHEC : aucune case atteignable"); _finish(); return
	await _click_on(dest.global_position + Vector3(0, 0.2, 0))
	for _i in 150: await physics_frame
	_note("après déplacement : pion en %s, distance à l'ennemi %.1f, stage=%d" % [
		_cell(pawn), pawn.global_position.distance_to(foe.global_position), _part.res.stage])

	# --- 2. Attaquer ---
	var hp_before: int = foe.stats.curr_health
	_press("Attack")
	for _i in 25: await physics_frame
	_note("après « Attack » : stage=%d, cases attaquables=%d" % [
		_part.res.stage, _attackable_count()])
	await _click_on(foe.global_position + Vector3(0, 0.6, 0))
	for _i in 200: await physics_frame
	_note("après clic sur l'ennemi : stage=%d, PV %d → %d" % [
		_part.res.stage, hp_before, foe.stats.curr_health])
	_note("le pion a-t-il fini son tour : %s" % str(not pawn.can_act()))

	# --- 3. Finir le tour et laisser jouer l'IA ---
	var turn_before: int = _level.turn_stage
	_press("Debug: End Turn")
	for _i in 400: await physics_frame
	_note("après fin de tour : turn_stage %d → %d, joueur peut agir : %s" % [
		turn_before, _level.turn_stage, str(_part.can_act(_level.player))])
	var still: int = 0
	for p in _level.player.get_children():
		if p is TacticsPawn and p.can_act(): still += 1
	_note("pions du joueur encore actifs : %d" % still)
	_finish()


func _finish() -> void:
	print("\n===== JOURNAL =====")
	for l in _log: print("  " + str(l))
	quit(0)

func _note(t: String) -> void: _log.append(t)

func _cell(n: Node3D) -> String:
	var t: Node = n.get_tile() if n.has_method("get_tile") else null
	return str(TacticsGrid.tile_to_grid(_level.arena, t)) if t else "?"

func _first_actable() -> Node3D:
	for p in _level.player.get_children():
		if p is TacticsPawn and p.can_act(): return p
	return null

func _nearest_foe(from: Node3D) -> Node3D:
	var best: Node3D = null
	var d: float = INF
	for p in _level.opponent.get_children():
		if not (p is TacticsPawn): continue
		var dd: float = p.global_position.distance_to(from.global_position)
		if dd < d: d = dd; best = p
	return best

func _closest_reachable_to(foe: Node3D) -> Node3D:
	var best: Node3D = null
	var d: float = INF
	for t in TacticsGrid.tiles(_level.arena):
		if not t.get("reachable"): continue
		var dd: float = t.global_position.distance_to(foe.global_position)
		if dd < d: d = dd; best = t
	return best

func _attackable_count() -> int:
	var n: int = 0
	for t in TacticsGrid.tiles(_level.arena):
		if t.get("attackable"): n += 1
	return n

func _press(label: String) -> void:
	var b: Node = _find_button(_main, label)
	if b: b.emit_signal("pressed")
	else: _note("ÉCHEC : bouton « %s » introuvable" % label)

func _click_on(world: Vector3) -> void:
	var s: Vector2 = _cam.unproject_position(world)
	Input.warp_mouse(s)
	for _i in 6: await physics_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = s
		e.global_position = s
		Input.parse_input_event(e)
		for _i in 6: await physics_frame

func _find(n: Node, w: String) -> Node:
	if n.get_script() and str(n.get_script().get_global_name()) == w: return n
	for c in n.get_children():
		var f: Node = _find(c, w)
		if f: return f
	return null

func _find_button(n: Node, label: String) -> Node:
	if n is Button and n.text == label: return n
	for c in n.get_children():
		var f: Node = _find_button(c, label)
		if f: return f
	return null
