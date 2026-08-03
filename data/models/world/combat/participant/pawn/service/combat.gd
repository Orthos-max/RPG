class_name TacticsPawnCombatService
extends RefCounted
## Fire Emblem combat service — handles attack resolution between pawns
## Uses FECombatCalculator for full FE formula (hit/crit/damage/double/weapon triangle)
## Integrates support bonuses and EXP/level-up system.

const CombatCalc = preload("res://data/services/combat/fe_combat.gd")
const WT = preload("res://data/models/world/stats/weapon_type.gd")
const MapDataRef = preload("res://data/models/world/map/map_data.gd")
const SkillDBRef = preload("res://data/models/world/stats/skill_db.gd")

var _victory_checked: bool = false  ## Prevents duplicate victory/defeat triggers


## Executes an attack from one pawn to another using Fire Emblem combat formula
##
## @param pawn: The attacking TacticsPawn
## @param target_pawn: The TacticsPawn being attacked
## @param delta: Time elapsed since the last frame
## @return: Whether the attack was completed (animation finished)
func attack_target_pawn(pawn: TacticsPawn, target_pawn: TacticsPawn, delta: float) -> bool:
	# Make the attacking pawn face the target
	pawn.serv.movement.look_at_direction(pawn, target_pawn.global_position - pawn.global_position)
	
	# --- Attack animation timing ---
	# Wait for the attack animation "wind-up" period (0.25s) before resolving combat
	if pawn.res.can_attack and pawn.res.wait_delay > TacticsPawnResource.MIN_TIME_FOR_ATTACK / 4.0:
		_resolve_combat(pawn, target_pawn)
		pawn.res.set_attacking(false)
		pawn.res.wait_delay = 0.0
		return true  # Combat resolved, animation complete
	
	# Increment wait delay during anticipation phase
	if pawn.res.wait_delay < TacticsPawnResource.MIN_TIME_FOR_ATTACK:
		pawn.res.wait_delay += delta
		return false
	
	# Safety: reset if we somehow exceeded the timer without combat
	pawn.res.wait_delay = 0.0
	return true


## Resolves the actual combat using FECombatCalculator with support bonuses
## Also handles healing (same-team staff targeting) and death cleanup
func _resolve_combat(pawn: TacticsPawn, target_pawn: TacticsPawn) -> void:
	# --- Check if this is healing (same team + staff/magic weapon) ---
	var is_same_team := pawn.get_parent() == target_pawn.get_parent()
	var is_healer := WT.is_magical(pawn.stats.weapon_type)
	
	if is_same_team and is_healer:
		_resolve_heal(pawn, target_pawn)
		return
	
	if not CombatCalc:
		push_error("FECombatCalculator not loaded! Falling back to flat damage.")
		target_pawn.stats.apply_to_curr_health(-pawn.stats.attack_power)
		_check_death(target_pawn)
		return
	
	var attacker_name = _get_name(pawn)
	var defender_name = _get_name(target_pawn)
	
	# --- Support bonuses ---
	var support_bonuses := _get_support_bonuses(pawn, target_pawn)
	
	# --- Terrain defense bonus ---
	var terrain_def: int = 0
	var target_tile = target_pawn.get_tile()
	if target_tile and target_tile.get("terrain_type") != null:
		terrain_def = MapDataRef.get_defense_bonus(target_tile.terrain_type)
	
	# --- Run combat calculation ---
	var preview: CombatCalc.CombatResult = CombatCalc.calculate(pawn.stats, target_pawn.stats, support_bonuses, terrain_def)
	var outcome: Dictionary = CombatCalc.roll_combat(preview)
	
	if outcome["hit"]:
		var total_damage: int = outcome["total_damage"]
		target_pawn.stats.apply_to_curr_health(-total_damage)
		
		var log_msg = "%s → %s | %d dmg" % [attacker_name, defender_name, total_damage]
		if outcome["crit"]:
			log_msg += " 💥CRITICAL!"
		if outcome["double"]:
			log_msg += " ⚔️×2"
		if preview.triangle_bonus != 0:
			log_msg += " | Triangle %+d" % preview.triangle_bonus
		if support_bonuses.get("hit", 0) > 0:
			log_msg += " | Support 💬"
		if terrain_def > 0:
			log_msg += " | Terrain 🛡️+%d" % terrain_def
		if not preview.triggered.is_empty():
			var names: Array = []
			for skill_id in preview.triggered:
				names.append(SkillDBRef.get_skill_name(str(skill_id)))
			log_msg += " | ✨ %s" % ", ".join(names)
		
		print(log_msg)
		
		_record(&"record_attack", [attacker_name, defender_name, total_damage,
			true, bool(outcome["crit"]), bool(outcome["double"]), target_pawn.stats.hp])

		var dmg_type: String = "magical" if preview.is_magical else "physical"
		print_rich("[color=pink]%s → %s: %d %s dmg [Hit: %d%% | Crit: %d%% | Double: %s] | %s HP: %d/%d[/color]" % [
			attacker_name, defender_name,
			total_damage, dmg_type,
			preview.hit_rate, preview.crit_rate,
			"Yes" if outcome["double"] else "No",
			defender_name, target_pawn.stats.hp, target_pawn.stats.max_hp
		])
		
		# --- Check death ---
		if not target_pawn.is_alive():
			award_exp(pawn, target_pawn, true)
			_check_death(target_pawn)
		else:
			award_exp(pawn, target_pawn, false)
		
		# --- Support Point Gains ---
		_award_support_points(pawn)
	else:
		_record(&"record_attack", [attacker_name, defender_name, 0, false, false, false,
			target_pawn.stats.hp])
		print(attacker_name, " missed! (roll avg: ", outcome["hit_rate"], " vs ", preview.hit_rate, "% hit)")


## Resolve healing on an ally (staff users only)
func _resolve_heal(healer: TacticsPawn, target: TacticsPawn) -> void:
	var heal_amount: int = 10 + int(healer.stats.mag / 3.0)
	var actual_heal: int = min(heal_amount, target.stats.max_hp - target.stats.hp)
	
	target.stats.apply_to_curr_health(actual_heal)
	
	var h_name := _get_name(healer)
	var t_name := _get_name(target)
	_record(&"record_heal", [h_name, t_name, actual_heal, target.stats.hp])
	print("%s soigne %s de %d HP → %d/%d" % [h_name, t_name, actual_heal, target.stats.hp, target.stats.max_hp])
	print_rich("[color=green]%s ⚕ Heal → %s: +%d HP (%d/%d)[/color]" % [h_name, t_name, actual_heal, target.stats.hp, target.stats.max_hp])
	
	# EXP for healing: 10 + (target level - healer level) × 2, min 1
	var heal_exp: int = max(1, 10 + (target.stats.level - healer.stats.level) * 2)
	var _result: Dictionary = healer.stats.gain_exp(heal_exp)
	print("+%d EXP (heal) (%s)" % [heal_exp, h_name])
	
	# Award support points for healing
	_award_support_points(healer)
	
	# Also award heal-specific points for the healer-target pair
	var tracker := SupportTracker.instance
	if tracker:
		var healer_name := _get_name(healer)
		var target_name := _get_name(target)
		tracker.award_heal(healer_name, target_name)


## Handle a pawn's death — remove from scene after a brief delay
func _check_death(p: TacticsPawn) -> void:
	# Only process if dead
	if p.is_alive():
		return

	# Journal de bataille : la mort est l'événement le plus utile à Ciel.
	var team_name: String = "player" if p.get_parent() and p.get_parent().has_method("show_available_pawn_actions") else "opponent"
	_record(&"record_death", [_get_name(p), team_name, ""])

	# Make invisible and non-interactive
	p.visible = false
	p.res.can_move = false
	p.res.can_attack = false
	
	# Disable collision so tile raycast stops detecting the pawn
	for child in p.get_children():
		if child is CollisionShape3D:
			child.disabled = true
	
	var tree := p.get_tree()
	if tree:
		tree.create_timer(0.5).timeout.connect(p.queue_free)
	
	# Check victory condition
	_check_victory(p)


## Check if all enemies are defeated and show victory
func _check_victory(killed_pawn: TacticsPawn) -> void:
	if _victory_checked:
		return
	
	# Capture tree early — the pawn may be freed before the async delay completes
	var tree := killed_pawn.get_tree()
	if not tree:
		return
	
	# Check if everyone on the killed pawn's team is now dead
	var killed_team = killed_pawn.get_parent()
	if not killed_team:
		return
	
	var all_dead := true
	for p: TacticsPawn in killed_team.get_children():
		if p.is_alive():
			all_dead = false
			break
	
	if not all_dead:
		return
	
	_victory_checked = true
	
	# Determine if this is the player team or opponent team
	# TacticsPlayer has show_available_pawn_actions, TacticsOpponent doesn't
	var is_player_team := killed_team.has_method("show_available_pawn_actions")
	
	await tree.create_timer(0.8).timeout

	if is_player_team:
		print_rich("[color=red][b]💀 DÉFAITE ! Toute l'armée est tombée...[/b][/color]")
	else:
		print_rich("[color=gold][b]⚔️ VICTOIRE ! Tous les ennemis sont vaincus ![/b][/color]")

	# Replay persisté : sert à relire après coup les décisions de Ciel.
	var recorder: Node = tree.root.get_node_or_null("BattleRecorder")
	if recorder:
		var path: String = recorder.save_replay("defeat" if is_player_team else "victory")
		if not path.is_empty():
			print("[Replay] ", ProjectSettings.globalize_path(path))

	_show_victory_screen(tree)


## Display victory/defeat screen and return to menu
func _show_victory_screen(tree: SceneTree) -> void:
	if not tree:
		return
	
	await tree.create_timer(2.0).timeout
	
	# Look for the main controller to call back to menu
	var root := tree.root
	var main_node: Node = null
	for child in root.get_children():
		if child is Node and child.has_method("_show_menu"):
			main_node = child
			break
	
	if main_node and main_node.has_method("unload_level"):
		main_node.unload_level()
		main_node._show_menu()
	else:
		print("Appuyez sur ESC pour revenir au menu.")


## Get support bonuses for the attacker from nearby allies
func _get_support_bonuses(attacker: TacticsPawn, _defender: TacticsPawn) -> Dictionary:
	var tracker := SupportTracker.instance
	if not tracker:
		return {}
	
	var attacker_name := _get_name(attacker)
	
	# Find all allies on the same team within support range
	var all_allies: Array = []
	var parent_node = attacker.get_parent()
	if parent_node:
		all_allies = parent_node.get_children()
	
	var nearby := tracker.get_nearby_support_allies(attacker, all_allies)
	return tracker.get_combined_bonuses(attacker_name, nearby)


## Award support points to nearby allies after combat
func _award_support_points(attacker: TacticsPawn) -> void:
	var tracker := SupportTracker.instance
	if not tracker:
		return
	
	var attacker_name := _get_name(attacker)
	
	# Get all allies on the same team
	var all_allies: Array = []
	var parent_node = attacker.get_parent()
	if parent_node:
		all_allies = parent_node.get_children()
	
	# Award nearby combat points to allies within support range
	var nearby := tracker.get_nearby_support_allies(attacker, all_allies)
	for ally_name in nearby:
		tracker.award_nearby_combat(attacker_name, ally_name)


## Grant EXP to the attacker after combat
func award_exp(attacker: TacticsPawn, defender: TacticsPawn, is_kill: bool) -> void:
	var exp_amount: int
	if is_kill:
		exp_amount = EXPCalculator.exp_for_kill(
			attacker.stats.level,
			defender.stats.level,
			defender.stats.is_promoted
		)
	else:
		exp_amount = EXPCalculator.exp_for_damage(
			attacker.stats.level,
			defender.stats.level
		)
	
	var result: Dictionary = attacker.stats.gain_exp(exp_amount)
	
	var a_name: String = attacker.stats.override_name if attacker.stats.override_name else attacker.stats.expertise
	var kill_text: String = " KILL!" if is_kill else ""
	print("+%d EXP%s (%s)" % [exp_amount, kill_text, a_name])
	
	if result["leveled_up"]:
		# Level up and promotion messages are already printed in gain_exp()
		pass


## Journalise un événement via l'autoload BattleRecorder, s'il est présent.
## Reste silencieux hors runtime complet (tests unitaires headless).
func _record(method: StringName, args: Array) -> void:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return
	var recorder: Node = (loop as SceneTree).root.get_node_or_null("BattleRecorder")
	if recorder and recorder.has_method(method):
		recorder.callv(method, args)


## Helper: get display name of a pawn (unique au sein du camp)
func _get_name(p: TacticsPawn) -> String:
	return p.display_name()


## Get a combat preview (before committing to attack) for UI display
##
## @param attacker: The attacking pawn's Stats
## @param defender: The defending pawn's Stats
## @param support_bonuses: Optional support bonuses
## @return: FECombatCalculator.CombatResult with hit/dmg/crit/double info
static func preview_combat(attacker: Stats, defender: Stats, support_bonuses: Dictionary = {}, terrain_defense: int = 0) -> CombatCalc.CombatResult:
	return CombatCalc.calculate(attacker, defender, support_bonuses, terrain_defense)
