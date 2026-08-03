class_name TacticsParticipantTurnService
extends RefCounted
## Service class for handling turn-related actions
##
## Parent: [TacticsParticipantService]

# Les autoloads sont résolus à l'exécution (via l'arbre) et non par leur nom
# global : ce service est compilé pendant l'initialisation des autoloads, où
# ces noms ne sont pas encore utilisables.
const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

## Resource containing participant data and configurations
var res: TacticsParticipantResource
## Resource for camera-related data and configurations
var camera: TacticsCameraResource
## Resource for control-related data and configurations
var controls: TacticsControlsResource


## Initializes the TacticsParticipantTurnService
##
## @param _res: The TacticsParticipantResource to use
## @param _camera: The TacticsCameraResource to use
## @param _controls: The TacticsControlsResource to use
func _init(_res: TacticsParticipantResource, _camera: TacticsCameraResource, _controls: TacticsControlsResource) -> void:
	res = _res
	camera = _camera
	controls = _controls


## Handles the player's turn
##
## @param delta: Time elapsed since the last frame
## @param player: The TacticsPlayer node
## @param participant: The TacticsParticipant node
func handle_player_turn(delta: float, player: TacticsPlayer, participant: TacticsParticipant) -> void:
	if res.turn_just_started:
		camera.target = player.get_children().front()
		res.turn_just_started = false
	
	controls.move_camera(delta)
	controls.set_actions_menu_visibility(res.stage in [res.STAGE_SHOW_ACTIONS, res.STAGE_SHOW_MOVEMENTS, res.STAGE_SELECT_LOCATION, res.STAGE_DISPLAY_TARGETS, res.STAGE_SELECT_ATTACK_TARGET], res.curr_pawn if is_instance_valid(res.curr_pawn) else null)
	
	match res.stage:
		res.STAGE_SELECT_PAWN: controls.select_pawn(player)
		res.STAGE_SHOW_ACTIONS: player.show_available_pawn_actions()
		res.STAGE_SHOW_MOVEMENTS: player.show_available_movements()
		res.STAGE_SELECT_LOCATION: controls.select_new_location()
		res.STAGE_MOVE_PAWN: player.move_pawn()
		res.STAGE_DISPLAY_TARGETS: player.display_attackable_targets()
		res.STAGE_SELECT_ATTACK_TARGET: controls.select_pawn_to_attack()
		res.STAGE_ATTACK: participant.serv.combat_service.attack_pawn(delta, true)


## Handles the opponent's turn
##
## @param delta: Time elapsed since the last frame
## @param opponent: The TacticsOpponent node
## @param participant: The TacticsParticipant node
func handle_opponent_turn(delta: float, opponent: TacticsOpponent, participant: TacticsParticipant) -> void:
	res.targets = participant.get_node("%TacticsPlayer")
	controls.set_actions_menu_visibility(false, null)

	# Qui pilote ce camp ? La réponse vient de GameSession (M1), pas d'un test en dur.
	# REMOTE_PLAYER retombe volontairement sur l'IA locale tant que le réseau (M3)
	# n'est pas branché : mieux vaut un tour joué qu'une partie figée.
	match _opponent_controller():
		TeamDataClass.Controller.CIEL_AI:
			var ciel: Node = _autoload("CielAI")
			if ciel:
				ciel.handle_opponent_turn(delta, opponent, participant)
				return
		TeamDataClass.Controller.LOCAL_PLAYER:
			# Hotseat (M2) : les contrôles partagés ne sont pas encore branchés.
			# L'IA locale assure l'intérim plutôt que de figer la partie.
			DebugLog.debug_nospam("hotseat_pending", "Hotseat (M2) non implémenté — IA locale")

	if res.stage > 4:
		res.stage = 0
		DebugLog.debug_nospam("turn_stage", res.stage)
	match res.stage:
		res.STAGE_SELECT_PAWN: opponent.choose_pawn()
		res.STAGE_SHOW_ACTIONS: opponent.chase_nearest_enemy()
		res.STAGE_SHOW_MOVEMENTS: opponent.is_pawn_done_moving()
		res.STAGE_SELECT_LOCATION: opponent.choose_pawn_to_attack()
		res.STAGE_MOVE_PAWN: participant.serv.combat_service.attack_pawn(delta, false)


## Contrôleur du camp adverse, d'après GameSession (IA locale par défaut).
func _opponent_controller() -> int:
	var session: Node = _autoload("GameSession")
	if not session:
		return TeamDataClass.Controller.LOCAL_AI
	return int(session.controller_for(TeamDataClass.Side.OPPONENT))


## Récupère un autoload par son nom, sans dépendre de l'identifiant global.
func _autoload(autoload_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(autoload_name)
	return null


## Checks if the participant can perform an action
##
## @param parent: The parent node of the participant
## @return: Whether the participant can act
func can_act(parent: Node3D) -> bool:
	for p: TacticsPawn in parent.get_children():
		if p.can_act():
			return true
	return false


## Resets the participant's turn
##
## @param parent: The parent node of the participant
func reset_turn(parent: Node3D) -> void:
	res.turn_just_started = true
	for p: TacticsPawn in parent.get_children():
		p.reset_turn()


## Skips the participant's turn
##
## @param player: The TacticsPlayer node
func skip_turn(player: TacticsPlayer) -> void:
	for pawn: TacticsPawn in player.get_children():
		pawn.end_pawn_turn()
	res.stage = res.STAGE_SELECT_PAWN
