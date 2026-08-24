class_name TacticsParticipantCombatService
extends RefCounted
## Service class for handling combat-related actions
## 
## Parent: [TacticsParticipantService]

## Resource containing participant data and configurations
var res: TacticsParticipantResource
const SkillUseRef = preload("res://data/services/combat/skill_use.gd")
## Resource for camera-related data and configurations
var camera: TacticsCameraResource
## Resource for control-related data and configurations
var controls: TacticsControlsResource


## Initializes the TacticsParticipantCombatService
##
## @param _res: The TacticsParticipantResource to use
## @param _camera: The TacticsCameraResource to use
## @param _controls: The TacticsControlsResource to use
func _init(_res: TacticsParticipantResource, _camera: TacticsCameraResource, _controls: TacticsControlsResource) -> void:
	res = _res
	camera = _camera
	controls = _controls


## Handles the attack action of a pawn
##
## @param delta: Time elapsed since the last frame
## @param is_player: Whether the attacking pawn belongs to the player
func attack_pawn(delta: float, is_player: bool) -> void:
	# L'assaillant peut être tombé sous une riposte à la frame précédente, et
	# avoir quitté la scène. Sans cette garde, l'étape d'attaque écrivait sur un
	# nœud disparu — invisible en debug, fatal dans une build exportée.
	if not is_instance_valid(res.curr_pawn):
		res.attackable_pawn = null
		res.stage = res.STAGE_SELECT_PAWN
		return

	# Handle case when no attackable pawn is available
	if not is_instance_valid(res.attackable_pawn):
		res.curr_pawn.res.can_attack = false
	else:
		# Compétence utilisable armée (bouton « Compétence ») : la résolution ne
		# passe pas par l'échange d'armes mais par le service des compétences.
		if not res.pending_skill.is_empty():
			_resolve_pending_skill()
		else:
			# Attempt to attack the target pawn
			if not res.curr_pawn.attack_target_pawn(res.attackable_pawn, delta):
				return
		# Hide actions menu and focus camera on attacking pawn
		controls.set_actions_menu_visibility(false, res.attackable_pawn)
		# Depuis la riposte, l'assaillant peut ne pas survivre à son propre assaut :
		# la caméra ne se cale sur lui que s'il est encore debout.
		if is_instance_valid(res.curr_pawn) and res.curr_pawn.is_alive():
			camera.target = res.curr_pawn
			# Frapper ou soigner clôt le tour de l'unité, comme dans Fire Emblem :
			# on se déplace puis on agit, jamais l'inverse. Sans cela, `can_attack`
			# tombait bien à faux mais `can_move` restait vrai — l'unité repartait
			# se promener après son coup.
			res.curr_pawn.end_pawn_turn()

	# Reset attackable pawn
	res.attackable_pawn = null
	# Reset opponent stats display
	if res.display_opponent_stats:
		res.display_opponent_stats = false

	# Determine next stage based on current pawn's ability to act and whether it's a player pawn
	var still_standing: bool = is_instance_valid(res.curr_pawn) and res.curr_pawn.is_alive()
	if not still_standing or not res.curr_pawn.can_act() or not is_player:
		res.stage = res.STAGE_SELECT_PAWN
	else:
		res.stage = res.STAGE_SHOW_ACTIONS


## Résout la compétence utilisable armée ([member TacticsParticipantResource.pending_skill])
## sur la cible sélectionnée. Le service [SkillUse] applique l'effet (soin,
## dégâts, affliction) ; le journal et l'écran suivent. L'action est consommée
## par l'appelant ([code]end_pawn_turn[/code] dans [method attack_pawn]).
func _resolve_pending_skill() -> void:
	var skill_id: String = res.pending_skill
	res.pending_skill = ""
	var user: TacticsPawn = res.curr_pawn
	var target: TacticsPawn = res.attackable_pawn
	if not is_instance_valid(user) or not is_instance_valid(target) \
			or not user.stats or not target.stats:
		return
	var report: Dictionary = SkillUseRef.resolve(skill_id, user.stats, target.stats)
	var line: String = SkillUseRef.describe(user.display_name(), target.display_name(), report)
	print(line)
	var recorder: Node = user.get_node_or_null("/root/BattleRecorder")
	if recorder:
		if str(report.get("effect", "")) == "heal":
			recorder.record_heal(user.display_name(), target.display_name(),
				int(report.get("amount", 0)), target.stats.hp)
		else:
			recorder.record_attack(user.display_name(), target.display_name(),
				int(report.get("amount", 0)), true, false, false, target.stats.hp)
