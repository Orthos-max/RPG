extends Node
## Ciel AI Controller — Pont Godot ↔ Ciel.
##
## Quand activé, Ciel contrôle l'adversaire via fichiers.
## - Exporte l'état du jeu dans ai_state.json (lisible par Ciel)
## - Lit les commandes depuis ai_command.json (écrites par Ciel)
## - Prend le relais dans handle_opponent_turn() au lieu de l'IA basique.
##
## Commandes supportées :
##   { "action": "select_pawn", "name": "Skeleton" }
##   { "action": "move",        "col": 5, "row": 3 }
##   { "action": "attack",      "name": "Lord" }
##   { "action": "wait" }
##   { "action": "end_pawn" }
##   { "action": "end_turn" }

static var enabled: bool = true  # Activé par défaut

const STATE_FILE: String = "user://ai_state.json"
const CMD_FILE: String  = "user://ai_command.json"
const MAX_WAIT_FRAMES: int = 240  # ~4s avant auto-end-turn
const WAIT_BETWEEN_COMMANDS: int = 10  # Frames entre commandes

var _level_ref: WeakRef = weakref(null)
var _frame: int = 0
var _wait_frames: int = 0
var _last_state_hash: int = 0

# Cache pour le gestionnaire d'opponent
var _opponent: TacticsOpponent = null
var _participant: TacticsParticipant = null

# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------
func _ready() -> void:
	var f = FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"turn": "waiting",
			"stage": 0,
			"stage_name": "waiting",
			"current_pawn": "",
			"pawns": [],
			"message": "CielAI ready."
		}, "\t"))
		f.close()
	
	# Affiche le chemin user:// pour debug
	print("[CielAI] Ready — state path: ", ProjectSettings.globalize_path(STATE_FILE))


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	
	var level: TacticsLevel = _resolve_level()
	if not level:
		return
	if level.turn_stage != 1:
		return
	
	_frame += 1
	if _frame % 3 == 0:
		_export_state(level)


# ---------------------------------------------------------------------------
# Appelé par TacticsParticipantTurnService — remplace l'IA basique
# ---------------------------------------------------------------------------
func handle_opponent_turn(delta: float, opponent: TacticsOpponent, participant: TacticsParticipant) -> void:
	# Cache references
	_opponent = opponent
	_participant = participant
	
	var pr = participant.res
	var arena = _resolve_level().arena if _resolve_level() else null
	if not arena:
		return
	
	# Reset stage if out of bounds
	if pr.stage > 4:
		pr.stage = 0
	
	# Export state on stage transitions
	_export_state(_resolve_level())
	
	# Check for global commands (toggle, etc.)
	_check_global_commands()
	if not enabled:
		# Disabled — let normal AI take over by clearing this function and returning
		_opponent = null
		_participant = null
		return
	
	# Safety: if no pawns can act, end turn
	if _all_pawns_done(opponent) and pr.stage <= pr.STAGE_SELECT_PAWN:
		_wait_frames += 1
		if _wait_frames >= 30:  # 0.5s grace period
			_do_end_turn(pr)
		return
	
	match pr.stage:
		pr.STAGE_SELECT_PAWN:
			_handle_select_pawn_stage(opponent, pr)
		
		pr.STAGE_SHOW_ACTIONS:
			_handle_show_actions_stage(opponent, pr, arena)
		
		pr.STAGE_SHOW_MOVEMENTS:
			_handle_show_movements_stage(opponent, pr)
		
		pr.STAGE_SELECT_LOCATION:
			_handle_select_location_stage(opponent, pr, arena)
		
		pr.STAGE_MOVE_PAWN:
			_handle_move_pawn_stage(delta, opponent, participant, pr)
		
		_:
			# Unknown stage — reset for safety
			pr.stage = pr.STAGE_SELECT_PAWN


# ---------------------------------------------------------------------------
# Stage handlers
# ---------------------------------------------------------------------------
func _handle_select_pawn_stage(opponent: TacticsOpponent, pr: TacticsParticipantResource) -> void:
	# Si plus aucun pion adverse ne peut agir, on skip
	var _any_can_act := false
	for p in opponent.get_children():
		if p is TacticsPawn and is_instance_valid(p) and p.can_act():
			_any_can_act = true
			break
	if not _any_can_act:
		_wait_frames += 1
		if _wait_frames >= MAX_WAIT_FRAMES:
			_do_end_turn(pr)
		return
	
	# Reset wait counter when we have pawns that can act
	_wait_frames = 0
	
	# Process a command if available
	if not _check_command_file():
		return
	
	_wait_frames = 0
	var cmd = _cmd
	if cmd.get("action") == "select_pawn":
		var name: String = cmd.get("name", "")
		if name == "":
			return
		for p in opponent.get_children():
			if not p is TacticsPawn or not is_instance_valid(p):
				continue
			if _pawn_name(p) == name and p.stats.curr_health > 0:
				pr.curr_pawn = p
				pr.stage = pr.STAGE_SHOW_ACTIONS
				if _resolve_level() and _resolve_level().arena:
					_resolve_level().arena.res.reset_all_tile_markers()
					_resolve_level().arena.res.mark_hover_tile(p.get_tile())


func _handle_show_actions_stage(opponent: TacticsOpponent, pr: TacticsParticipantResource, arena: TacticsArena) -> void:
	var pawn = pr.curr_pawn
	if not pawn or not is_instance_valid(pawn):
		pr.stage = pr.STAGE_SELECT_PAWN
		return
	
	# Auto-skip si le pion ne peut plus rien faire
	if not pawn.res.can_move and not pawn.res.can_attack:
		_do_end_pawn(pawn, pr)
		return
	
	if not _check_command_file():
		return
	
	var cmd = _cmd
	match cmd.get("action", ""):
		"move":
			var col = cmd.get("col", -1)
			var row = cmd.get("row", -1)
			if not _do_move(pawn, pr, arena, col, row):
				return
		"attack":
			var name = cmd.get("name", "")
			if not _do_attack_setup(opponent, pawn, pr, arena, name):
				return
		"end_pawn":
			_do_end_pawn(pawn, pr)
		"end_turn":
			_do_end_turn(pr)


func _handle_show_movements_stage(opponent: TacticsOpponent, pr: TacticsParticipantResource) -> void:
	var pawn = pr.curr_pawn
	if not pawn or not is_instance_valid(pawn):
		pr.stage = pr.STAGE_SELECT_PAWN
		return
	
	# Wait for movement animation to complete
	if pawn.res and not pawn.res.pathfinding_tilestack.is_empty():
		return  # Still moving, wait
		
	# Movement is done — advance to location selection
	pr.stage = pr.STAGE_SELECT_LOCATION
	pr.turn_just_started = true


func _handle_select_location_stage(opponent: TacticsOpponent, pr: TacticsParticipantResource, arena: TacticsArena) -> void:
	var pawn = pr.curr_pawn
	if not pawn or not is_instance_valid(pawn):
		pr.stage = pr.STAGE_SELECT_PAWN
		return
	
	# Auto-skip si le pion ne peut plus attaquer
	if not pawn.res.can_attack:
		_do_end_pawn(pawn, pr)
		return
	
	if not _check_command_file():
		return
	
	var cmd = _cmd
	match cmd.get("action", ""):
		"attack":
			var name = cmd.get("name", "")
			# Set up attack targets
			var target = _find_attack_target(opponent, arena, name)
			if target:
				pr.attackable_pawn = target
				
				# Advance to MOVE_PAWN which triggers combat in the next stage
				arena.res.reset_all_tile_markers()
				pr.stage = pr.STAGE_MOVE_PAWN
				pr.turn_just_started = true
				
				# Mark target tile as hovered
				if target.get_tile():
					arena.res.mark_hover_tile(target.get_tile())
		"end_pawn":
			_do_end_pawn(pawn, pr)
		"end_turn":
			_do_end_turn(pr)


func _handle_move_pawn_stage(delta: float, opponent: TacticsOpponent, participant: TacticsParticipant, pr: TacticsParticipantResource) -> void:
	# Execute combat (same as normal flow)
	participant.serv.combat_service.attack_pawn(delta, false)


# ---------------------------------------------------------------------------
# Background export (called from _physics_process and handle_opponent_turn)
# ---------------------------------------------------------------------------
func _export_state(level: TacticsLevel) -> void:
	if not level or not is_instance_valid(level):
		return
	var part = _participant
	var opponent = _opponent
	
	if not part or not opponent:
		part = level.participant
		if level.player:
			for c in level.player.get_children():
				if c is TacticsParticipant:
					part = c
					break
		if level.opponent:
			for c in level.opponent.get_children():
				if c is TacticsOpponent:
					opponent = c
					break
		if not part or not opponent:
			return
	
	var arena = level.arena
	var pr = part.res if is_instance_valid(part) else null
	if not pr:
		return
	
	# Determine whose turn it is
	var whose_turn: String = "unknown"
	if level.participant and is_instance_valid(level.participant):
		if level.participant.can_act(level.player if level.player else null):
			whose_turn = "player"
		elif level.participant.can_act(opponent):
			whose_turn = "opponent"
	
	var state = {
		"turn": whose_turn,
		"stage": pr.stage,
		"stage_name": _stage_name(pr.stage),
		"current_pawn": "",
		"pawns": []
	}
	
	var cp = pr.curr_pawn
	if cp and is_instance_valid(cp):
		state["current_pawn"] = _pawn_name(cp)
	
	if level.player and is_instance_valid(level.player):
		for p in level.player.get_children():
			if p is TacticsPawn and is_instance_valid(p):
				state["pawns"].append(_pawn_dict(p, "player"))
	
	if opponent and is_instance_valid(opponent):
		for p in opponent.get_children():
			if p is TacticsPawn and is_instance_valid(p):
				state["pawns"].append(_pawn_dict(p, "opponent"))
	
	# Add grid info
	if arena and is_instance_valid(arena) and arena.res and arena.res.map_data:
		var md = arena.res.map_data
		state["tile_size"] = md.tile_size
		state["grid_size"] = {"x": md.grid_size.x, "y": md.grid_size.y}
	
	var json_str = JSON.stringify(state, "\t")
	var h = hash(json_str)
	if h == _last_state_hash:
		return
	_last_state_hash = h
	
	var f = FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(json_str)
		f.close()


# ---------------------------------------------------------------------------
# Action helpers
# ---------------------------------------------------------------------------
func _do_move(pawn: TacticsPawn, pr: TacticsParticipantResource, arena: TacticsArena, col: int, row: int) -> bool:
	if not pawn.res.can_move:
		return false
	
	var target_tile = _find_tile_at(arena, col, row)
	if not target_tile:
		return false
	
	var allies = []
	if _opponent and is_instance_valid(_opponent):
		allies = _opponent.get_children()
	
	arena.res.reset_all_tile_markers()
	arena.process_surrounding_tiles(pawn.get_tile(), pawn.stats.jump, allies)
	arena.mark_reachable_tiles(pawn.get_tile(), pawn.stats.movement)
	
	var path = arena.get_pathfinding_tilestack(target_tile)
	pawn.res.pathfinding_tilestack = path if not path.is_empty() else []
	
	pr.stage = pr.STAGE_SHOW_MOVEMENTS
	pr.turn_just_started = true
	return true


func _do_attack_setup(opponent: TacticsOpponent, pawn: TacticsPawn, pr: TacticsParticipantResource, arena: TacticsArena, name: String) -> bool:
	if not pawn.res.can_attack:
		return false
	
	var target = _find_pawn_by_name(opponent.get_parent(), name)  # Look in level's children (player side)
	if not target:
		# Try all pawns that are not opponent
		var level = _resolve_level()
		if level and level.player:
			for c in level.player.get_children():
				if c is TacticsPawn and _pawn_name(c) == name and c.stats.curr_health > 0:
					target = c
					break
	
	if not target or not is_instance_valid(target):
		return false
	
	pr.attackable_pawn = target
	arena.res.reset_all_tile_markers()
	arena.res.mark_hover_tile(target.get_tile())
	pr.stage = pr.STAGE_SELECT_LOCATION
	pr.turn_just_started = true
	return true


func _find_attack_target(opponent: TacticsOpponent, arena: TacticsArena, name: String) -> TacticsPawn:
	var level = _resolve_level()
	if not level:
		return null
	# Search player children and all pawns under level
	var search_nodes = []
	if level.player:
		search_nodes.append(level.player)
	
	for node in search_nodes:
		if not is_instance_valid(node):
			continue
		for c in node.get_children():
			if c is TacticsPawn and is_instance_valid(c):
				if _pawn_name(c) == name and c.stats.curr_health > 0:
					return c
	return null


func _do_end_pawn(pawn: TacticsPawn, pr: TacticsParticipantResource) -> void:
	if pawn and is_instance_valid(pawn):
		pawn.res.can_move = false
		pawn.res.can_attack = false
		pawn.end_pawn_turn()
	pr.stage = pr.STAGE_SELECT_PAWN
	pr.curr_pawn = null


func _do_end_turn(pr: TacticsParticipantResource) -> void:
	var level = _resolve_level()
	if level and level.opponent and is_instance_valid(level.opponent):
		for p in level.opponent.get_children():
			if p is TacticsPawn and is_instance_valid(p):
				p.end_pawn_turn()
	pr.stage = pr.STAGE_SELECT_PAWN
	pr.curr_pawn = null


func _skip_turn() -> void:
	if _opponent and is_instance_valid(_opponent) and _participant and is_instance_valid(_participant):
		_do_end_turn(_participant.res)


func _all_pawns_done(opponent: TacticsOpponent) -> bool:
	for p in opponent.get_children():
		if p is TacticsPawn and is_instance_valid(p) and p.can_act():
			return false
	return true


func _check_global_commands() -> void:
	if not FileAccess.file_exists(CMD_FILE):
		return
	var f = FileAccess.open(CMD_FILE, FileAccess.READ)
	if not f:
		return
	var content = f.get_as_text()
	f.close()
	
	var json = JSON.new()
	if json.parse(content) != OK:
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		return
	
	var cmd = json.data
	if cmd.get("action") == "toggle":
		DirAccess.remove_absolute(CMD_FILE)
		var val = cmd.get("enabled", true)
		if val is bool:
			enabled = val
		_print_status()


# ---------------------------------------------------------------------------
# Command file management
# ---------------------------------------------------------------------------
var _cmd: Dictionary = {}

func _check_command_file() -> bool:
	if not FileAccess.file_exists(CMD_FILE):
		return false
	
	var f = FileAccess.open(CMD_FILE, FileAccess.READ)
	if not f:
		return false
	var content = f.get_as_text()
	f.close()
	
	DirAccess.remove_absolute(CMD_FILE)
	
	var json = JSON.new()
	var err = json.parse(content)
	if err != OK:
		return false
	if typeof(json.data) != TYPE_DICTIONARY:
		return false
	
	_cmd = json.data
	return true


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------
func _pawn_name(p: TacticsPawn) -> String:
	if p.stats and p.stats.override_name != "":
		return p.stats.override_name
	return p.expertise


func _pawn_dict(p: TacticsPawn, team: String) -> Dictionary:
	var tile = p.get_tile()
	var grid = {"col": -1, "row": -1}
	if tile:
		grid = _tile_to_grid(tile)
	
	return {
		"name": _pawn_name(p),
		"team": team,
		"grid_col": grid["col"],
		"grid_row": grid["row"],
		"hp": p.stats.curr_health,
		"max_hp": p.stats.hp,
		"str": p.stats.str,
		"mag": p.stats.mag,
		"skl": p.stats.skl,
		"spd": p.stats.spd,
		"lck": p.stats.lck,
		"def": p.stats.def,
		"res": p.stats.res,
		"movement": p.stats.movement,
		"attack_range": p.stats.attack_range,
		"weapon_type": p.stats.weapon_type,
		"can_move": p.res.can_move,
		"can_attack": p.res.can_attack,
		"alive": p.stats.curr_health > 0,
	}


func _tile_to_grid(tile: TacticsTile) -> Dictionary:
	if not tile or not is_instance_valid(tile):
		return {"col": -1, "row": -1}
	
	var level = _resolve_level()
	var arena = level.arena if level else null
	if not arena or not is_instance_valid(arena) or not arena.res or not arena.res.map_data:
		var pos = tile.global_position
		return {"col": int(round(pos.x + 8.0 - 0.5)), "row": int(round(pos.z + 5.0 - 0.5))}
	
	var md = arena.res.map_data
	var ts = md.tile_size
	var gs = md.grid_size
	var pos = tile.global_position
	
	var col = int(round((pos.x / ts) + (gs.x / 2.0) - 0.5))
	var row = int(round((pos.z / ts) + (gs.y / 2.0) - 0.5))
	
	return {
		"col": clampi(col, 0, gs.x - 1),
		"row": clampi(row, 0, gs.y - 1)
	}


func _find_tile_at(arena: TacticsArena, col: int, row: int) -> TacticsTile:
	if not arena or not is_instance_valid(arena):
		return null
	var tiles_node = arena.get_node_or_null("Tiles")
	if not tiles_node:
		return null
	for child in tiles_node.get_children():
		if child is TacticsTile:
			var g = _tile_to_grid(child)
			if g["col"] == col and g["row"] == row:
				return child
	return null


func _find_pawn_by_name(parent: Node, name: String) -> TacticsPawn:
	if not parent or not is_instance_valid(parent):
		return null
	for c in parent.get_children():
		if c is TacticsPawn and is_instance_valid(c):
			if _pawn_name(c) == name:
				return c
	return null


func _stage_name(stage: int) -> String:
	match stage:
		0: return "select_pawn"
		1: return "show_actions"
		2: return "show_movements"
		3: return "select_location"
		4: return "move_pawn"
		_: return "stage_%d" % stage


func _resolve_level() -> TacticsLevel:
	var ref = _level_ref.get_ref()
	if ref:
		return ref as TacticsLevel
	var tree = get_tree()
	if not tree:
		return null
	for child in tree.root.get_children():
		if child is TacticsLevel:
			_level_ref = weakref(child)
			return child
	return null


# ---------------------------------------------------------------------------
# Public static API
# ---------------------------------------------------------------------------
static func toggle(val: bool = true) -> void:
	enabled = val
	_print_status()


static func _print_status() -> void:
	var msg = "CielAI: enabled" if enabled else "CielAI: disabled"
	print(msg)
	var f = FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"turn": "waiting", "stage": 0, "message": msg}, "\t"))
		f.close()



