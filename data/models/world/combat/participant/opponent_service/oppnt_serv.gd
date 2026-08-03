class_name TacticsOpponentService
extends RefCounted
## Service class for TacticsOpponent
##
## Les décisions viennent de [LocalAIBrain] via [TacticsAIExecutor] : ciblage
## pondéré (achèvement, menace, riposte), terrain défensif et prise en compte du
## risque d'encerclement, le tout modulé par la difficulté choisie.

const EXECUTOR = preload("res://data/models/world/ai/ai_executor.gd")

## Resource containing participant data and configurations
var res: TacticsParticipantResource
## Resource for camera-related data and configurations
var camera: TacticsCameraResource
## Resource for control-related data and configurations
var controls: TacticsControlsResource
## Reference to the TacticsArena node
var arena: TacticsArena
## Nom de la cible retenue par l'heuristique pendant la phase de déplacement
var _planned_target: String = ""


## Initializes the TacticsOpponentService
##
## @param _res: The TacticsParticipantResource to use
## @param _camera: The TacticsCameraResource to use
## @param _controls: The TacticsControlsResource to use
## @param _arena: The TacticsArena node to use
func _init(_res: TacticsParticipantResource, _camera: TacticsCameraResource, _controls: TacticsControlsResource, _arena: TacticsArena) -> void:
	res = _res
	camera = _camera
	controls = _controls
	arena = _arena


## Checks if all opponent pawns are properly configured
##
## @param opponent: The TacticsOpponent node to check
## @return: Whether all pawns are configured
func is_pawn_configured(opponent: TacticsOpponent) -> bool:
	for pawn: TacticsPawn in opponent.get_children():
		if not pawn.center():
			return false
	return true


## Selects a pawn for the opponent to control
##
## @param opponent: The TacticsOpponent node
func choose_pawn(opponent: TacticsOpponent) -> void:
	arena.reset_all_tile_markers()
	for p: TacticsPawn in opponent.get_children():
		if p.can_act() and p.is_alive():
			res.curr_pawn = p
			res.stage = res.STAGE_SHOW_ACTIONS
			return


## Décide du déplacement du pion actif (et mémorise la cible visée).
##
## @param opponent: The TacticsOpponent node
## @param player_node: The player's node
func chase_nearest_enemy(opponent: TacticsOpponent, player_node: Node) -> void:
	if not res.curr_pawn:
		return
	if not res.curr_pawn.res.can_move:
		res.stage = res.STAGE_SELECT_PAWN
		push_error("Tried to make a pawn that cannot move chase nearest enemy: ", res.curr_pawn)
		return

	var plan: Dictionary = EXECUTOR.plan(arena, res.curr_pawn, opponent, player_node, _difficulty())
	_planned_target = str(plan.get("decision", {}).get("target", ""))

	var to: TacticsTile = plan.get("tile") as TacticsTile
	if not to:
		# Aucune case retenue (déjà en position, ou plan vide) : on reste sur place
		# et on laisse l'étape de ciblage décider.
		to = res.curr_pawn.get_tile()

	res.curr_pawn.res.pathfinding_tilestack = arena.get_pathfinding_tilestack(to)
	camera.target = to
	if DebugLog.debug_enabled:
		print_rich("[color=orange]", res.curr_pawn, " → [i]", to, "[/i] (",
			str(plan.get("decision", {}).get("reason", "?")), ")[/color]")
	res.stage = res.STAGE_SHOW_MOVEMENTS


## Checks if the opponent's pawn has finished moving
func is_pawn_done_moving() -> void:
	if res.curr_pawn.res.pathfinding_tilestack.is_empty():
		if DebugLog.debug_enabled:
			print_rich("[color=orange]Pawn is done moving.[/color]")
		res.stage = res.STAGE_SELECT_LOCATION


## Selects a pawn for the opponent to attack
func choose_pawn_to_attack() -> void:
	if not res.curr_pawn:
		return
	arena.reset_all_tile_markers()
	# Don't filter by allies — enemy tiles must be reachable for attack targeting
	arena.process_surrounding_tiles(res.curr_pawn.get_tile(), res.curr_pawn.stats.attack_range)
	arena.mark_attackable_tiles(res.curr_pawn.get_tile(), res.curr_pawn.stats.attack_range)

	# On honore d'abord la cible choisie par l'heuristique, si elle est à portée.
	res.attackable_pawn = _resolve_planned_target()
	if not res.attackable_pawn:
		res.attackable_pawn = arena.get_weakest_attackable_pawn(res.targets.get_children())
	if res.attackable_pawn:
		if DebugLog.debug_enabled:
			print_rich("[color=orange]Weakest target detected:", res.attackable_pawn, "[/color]")
		controls.set_actions_menu_visibility(true, res.attackable_pawn)
		camera.target = res.attackable_pawn
	else:
		if DebugLog.debug_enabled:
			print_rich("[color=orange]No target detected.[/color]")

	_planned_target = ""
	res.stage = res.STAGE_MOVE_PAWN


## Retrouve la cible planifiée si elle est encore vivante et à portée d'attaque.
func _resolve_planned_target() -> TacticsPawn:
	if _planned_target.is_empty() or not res.targets:
		return null
	var pawn: Node = EXECUTOR.find_pawn_by_name(res.targets, _planned_target)
	if not pawn:
		return null
	var tile: TacticsTile = pawn.get_tile()
	if not tile or not tile.attackable:
		return null
	return pawn


## Difficulté courante, lue depuis GameSession (Normal par défaut).
func _difficulty() -> int:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var session: Node = (loop as SceneTree).root.get_node_or_null("GameSession")
		if session:
			return int(session.difficulty)
	return DifficultyDB.Level.NORMAL
