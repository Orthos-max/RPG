class_name TacticsPawnCombatService
extends RefCounted
## Fire Emblem combat service — handles attack resolution between pawns
## Uses FECombatCalculator for full FE formula (hit/crit/damage/double/weapon triangle)
## Integrates support bonuses and EXP/level-up system.

const CombatCalc = preload("res://data/services/combat/fe_combat.gd")
const WT = preload("res://data/models/world/stats/weapon_type.gd")
const MapDataRef = preload("res://data/models/world/map/map_data.gd")
const SkillDBRef = preload("res://data/models/world/stats/skill_db.gd")
const ForecastRef = preload("res://data/services/combat/battle_forecast.gd")
const BattleLog = preload("res://data/services/combat/battle_log.gd")

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
	# Soigner est l'affaire du bâton seul : un grimoire est magique, pas curatif.
	var is_healer := WT.is_healing(pawn.stats.weapon_type)
	
	if is_same_team and is_healer:
		_resolve_heal(pawn, target_pawn)
		return
	
	if not CombatCalc:
		push_error("FECombatCalculator not loaded! Falling back to flat damage.")
		target_pawn.stats.apply_to_curr_health(-pawn.stats.attack_power)
		_check_death(target_pawn)
		return
	
	# --- L'échange : assaut, riposte, et second coup du plus rapide ---
	var exchange: Dictionary = CombatCalc.calculate_exchange(pawn.stats, target_pawn.stats, {
		"attacker_support": collect_support_bonuses(pawn),
		"defender_support": collect_support_bonuses(target_pawn),
		"attacker_terrain": terrain_defense_of(pawn),
		"defender_terrain": terrain_defense_of(target_pawn),
		"distance": grid_distance(pawn, target_pawn),
	})
	var rolled: Dictionary = CombatCalc.roll_exchange(exchange, pawn.stats.hp, target_pawn.stats.hp)
	_apply_exchange(pawn, target_pawn, exchange, rolled)


## Reporte un échange déjà tiré sur les deux pions : PV, journal, XP, morts.
##
## Les deux sens sont traités symétriquement : le défenseur gagne son XP, ses
## alliés leurs points de soutien, et il peut tuer l'assaillant.
##
## Les morts sont constatées une fois l'échange entièrement tiré : c'est
## [method FECombatCalculator.roll_exchange] qui a déjà refusé les coups portés
## après la chute de l'un des deux. Ici, on ne fait que retirer les pions.
func _apply_exchange(pawn: TacticsPawn, target_pawn: TacticsPawn,
		exchange: Dictionary, rolled: Dictionary) -> void:
	var attacker_name: String = _get_name(pawn)
	var defender_name: String = _get_name(target_pawn)
	var attack: CombatCalc.CombatResult = exchange["attack"]
	var counter: Variant = exchange["counter"]

	var dealt: int = int(rolled["defender_damage_taken"])
	var taken: int = int(rolled["attacker_damage_taken"])
	if dealt > 0:
		target_pawn.stats.apply_to_curr_health(-dealt)
	if taken > 0:
		pawn.stats.apply_to_curr_health(-taken)

	var atk_side: Dictionary = _side_summary(rolled, "attack")
	var def_side: Dictionary = _side_summary(rolled, "counter")

	# --- Journal de l'assaut ---
	if bool(atk_side["hit"]):
		print(_blow_line(attacker_name, defender_name, dealt, atk_side, attack,
			terrain_defense_of(target_pawn)))
		print_rich("[color=pink]%s → %s: %d %s dmg [Hit: %d%% | Crit: %d%%] | %s HP: %d/%d[/color]" % [
			attacker_name, defender_name, dealt,
			"magical" if attack.is_magical else "physical",
			attack.hit_rate, attack.crit_rate,
			defender_name, target_pawn.stats.hp, target_pawn.stats.max_hp,
		])
	else:
		print("%s missed! (%d%% hit)" % [attacker_name, attack.hit_rate])
	_record(&"record_attack", [attacker_name, defender_name, dealt,
		bool(atk_side["hit"]), bool(atk_side["crit"]), int(atk_side["strikes"]) > 1,
		target_pawn.stats.hp])

	# --- Journal de la riposte ---
	if bool(rolled["countered"]) and counter:
		var counter_result: CombatCalc.CombatResult = counter
		if bool(def_side["hit"]):
			print_rich("[color=orange]↩ %s riposte → %s : %d dégâts | %s PV %d/%d[/color]" % [
				defender_name, attacker_name, taken,
				attacker_name, pawn.stats.hp, pawn.stats.max_hp,
			])
		else:
			print("↩ %s riposte et manque son coup (%d%%)" % [defender_name, counter_result.hit_rate])
		_record(&"record_attack", [defender_name, attacker_name, taken,
			bool(def_side["hit"]), bool(def_side["crit"]), int(def_side["strikes"]) > 1,
			pawn.stats.hp])
	elif not str(exchange["counter_reason"]).is_empty():
		print("↩ pas de riposte de %s : %s" % [defender_name, exchange["counter_reason"]])

	# --- XP et soutiens, dans les deux sens ---
	var defender_fell: bool = not target_pawn.is_alive()
	var attacker_fell: bool = not pawn.is_alive()
	if bool(atk_side["hit"]):
		award_exp(pawn, target_pawn, defender_fell)
		_award_support_points(pawn)
	if bool(def_side["hit"]):
		award_exp(target_pawn, pawn, attacker_fell)
		_award_support_points(target_pawn)

	# --- Morts ---
	if defender_fell:
		_check_death(target_pawn)
	if attacker_fell:
		_check_death(pawn)


## Résumé d'un camp dans un échange : a-t-il touché, critiqué, combien de coups.
func _side_summary(rolled: Dictionary, side: String) -> Dictionary:
	var out: Dictionary = {"strikes": 0, "hit": false, "crit": false, "skills": []}
	for blow: Dictionary in rolled["strikes"]:
		if str(blow["side"]) != side:
			continue
		out["strikes"] = int(out["strikes"]) + 1
		if bool(blow["hit"]):
			out["hit"] = true
		if bool(blow["crit"]):
			out["crit"] = true
		for skill_id in blow["skills"]:
			out["skills"].append(skill_id)
	return out


## Ligne de journal d'un assaut réussi (triangle, soutien, terrain, compétences).
func _blow_line(attacker_name: String, defender_name: String, damage: int,
		side: Dictionary, result: CombatCalc.CombatResult, terrain_def: int) -> String:
	var line: String = "%s → %s | %d dmg" % [attacker_name, defender_name, damage]
	if bool(side["crit"]):
		line += " 💥CRITICAL!"
	if int(side["strikes"]) > 1:
		line += " ⚔️×%d" % int(side["strikes"])
	if result.triangle_bonus != 0:
		line += " | Triangle %+d" % result.triangle_bonus
	if terrain_def > 0:
		line += " | Terrain 🛡️+%d" % terrain_def
	if not side["skills"].is_empty():
		var names: Array = []
		for skill_id in side["skills"]:
			names.append(SkillDBRef.get_skill_name(str(skill_id)))
		line += " | ✨ %s" % ", ".join(names)
	return line


## Distance de grille (Manhattan) entre deux pions.
##
## L'index de bataille répond sans rayon ni tuile ; sans lui (scène isolée,
## test headless), les positions monde suffisent — les cases font une unité.
static func grid_distance(a: TacticsPawn, b: TacticsPawn) -> int:
	if not a or not b or not is_instance_valid(a) or not is_instance_valid(b):
		return 1
	var grid: BattleGrid = BattleGrid.current
	if grid and grid.size() > 0:
		var ca: Vector2i = grid.coord_at_position(a.global_position)
		var cb: Vector2i = grid.coord_at_position(b.global_position)
		return absi(ca.x - cb.x) + absi(ca.y - cb.y)
	var delta: Vector3 = a.global_position - b.global_position
	return int(round(absf(delta.x))) + int(round(absf(delta.z)))


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


## Une unité peut-elle viser cette cible ?
##
## Un soigneur ne vise que ses alliés, un combattant que ses ennemis — et c'est
## bien **soigner** qui décide, pas « être magique ». Confondre les deux rendait
## tout porteur de grimoire incapable d'attaquer : son bouton d'attaque devenait
## « Soigner », ses ennemis cessaient d'être ciblables, et aucune prévision de
## combat ne s'affichait plus.
##
## Règle unique, partagée par la prévision, le ciblage à la souris et le menu
## d'actions : la laisser recopiée à trois endroits est ce qui a permis au bug
## d'y survivre.
static func can_target(weapon_type: int, same_team: bool) -> bool:
	return WT.is_healing(weapon_type) == same_team


## Bonus de soutien apportés à `attacker` par ses alliés proches.
## Statique : la prévision d'avant-combat s'en sert sans instancier le service.
static func collect_support_bonuses(attacker: TacticsPawn) -> Dictionary:
	var tracker := SupportTracker.instance
	if not tracker or not attacker:
		return {}

	# Find all allies on the same team within support range
	var all_allies: Array = []
	var parent_node = attacker.get_parent()
	if parent_node:
		all_allies = parent_node.get_children()

	var nearby := tracker.get_nearby_support_allies(attacker, all_allies)
	return tracker.get_combined_bonuses(attacker.display_name(), nearby)


## Bonus de DÉF/RÉS apporté par la tuile qu'occupe `pawn`.
static func terrain_defense_of(pawn: TacticsPawn) -> int:
	if not pawn:
		return 0
	var tile = pawn.get_tile()
	if tile and tile.get("terrain_type") != null:
		return MapDataRef.get_defense_bonus(tile.terrain_type)
	return 0


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
		# Les messages sont déjà imprimés par gain_exp() ; le journal, lui,
		# manquait la montée de niveau — elle n'apparaissait ni dans les replays
		# ni pour l'audio, qui écoute justement ce journal.
		_record(&"record", [BattleLog.Kind.LEVEL_UP, {
			"pawn": a_name, "level": attacker.stats.level, "exp": attacker.stats.exp,
		}])
		if bool(result.get("promoted", false)):
			_record(&"record", [BattleLog.Kind.PROMOTION, {
				"pawn": a_name, "class_id": attacker.stats.character_class,
			}])


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


## Prévision affichable de l'action de `attacker` sur `target`, telle qu'elle
## sera réellement résolue : mêmes bonus de soutien, même terrain, même
## distinction soin/attaque que `_resolve_combat`.
##
## @return: dictionnaire [BattleForecast] ; vide si l'action est impossible.
static func build_forecast(attacker: TacticsPawn, target: TacticsPawn) -> Dictionary:
	if not attacker or not target or not attacker.stats or not target.stats:
		return {}
	if not target.is_alive():
		return {}

	var same_team: bool = attacker.get_parent() == target.get_parent()
	if not can_target(attacker.stats.weapon_type, same_team):
		return {}

	return ForecastRef.build(attacker.stats, target.stats, {
		"support": collect_support_bonuses(attacker),
		"defender_support": collect_support_bonuses(target),
		"terrain_defense": terrain_defense_of(target),
		"attacker_terrain": terrain_defense_of(attacker),
		"distance": grid_distance(attacker, target),
		# `can_target` a déjà tranché : une cible alliée ne peut être qu'un soin.
		"is_heal": same_team,
	})
