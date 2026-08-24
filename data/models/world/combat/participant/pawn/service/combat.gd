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
const TeamDataRef = preload("res://data/models/world/combat/team/team_data.gd")
const KnockbackRef = preload("res://data/services/combat/knockback.gd")

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

	# Le pas en avant part avec l'élan, pas avec le coup : il occupe la seconde
	# quart d'attente ci-dessous, et l'assaillant est revenu sur sa case avant
	# que l'étape suivante ne s'ouvre.
	if is_zero_approx(pawn.res.wait_delay):
		BattleVFX.lunge(pawn, target_pawn)
		# Le geste part avec l'élan, pas avec les dégâts : la résolution tombe un
		# quart de seconde plus tard, en plein milieu du coup. C'est ce décalage
		# qui fait que l'éclat semble venir de la lame.
		play_figure(pawn, &"attack")

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
		_check_death(target_pawn, _get_name(pawn))
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

	# --- Effets visuels ---
	# L'échange entier est déjà tiré et appliqué : ce qui suit ne fait
	# qu'illustrer un résultat acquis. La riposte est décalée d'un tiers de
	# seconde, sans quoi les deux camps s'éclairent sur la même image.
	_show_blows(target_pawn, atk_side, attack.is_magical, 0.0)
	if bool(rolled["countered"]) and counter:
		_show_blows(pawn, def_side, (counter as CombatCalc.CombatResult).is_magical, 0.35)

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

	# --- Afflictions, dans les deux sens ---
	# Après les dégâts, avant les morts : une arme venimeuse n'empoisonne que ce
	# qui respire encore, et le survivant du tour doit repartir avec son poison.
	if bool(atk_side["hit"]):
		_try_afflict(pawn, target_pawn, atk_side["skills"])
	if bool(def_side["hit"]):
		_try_afflict(target_pawn, pawn, def_side["skills"])

	# --- Drain et repoussement, dans les deux sens ---
	# Après les dégâts et les afflictions, avant les morts : c'est la fenêtre où
	# la victime est encore debout et sa case encore la sienne. Les deux sens,
	# comme pour les afflictions — rien n'interdit à un pion du joueur d'apprendre
	# l'Onde de choc, et une riposte souffle aussi bien qu'un assaut.
	if bool(atk_side["hit"]):
		_drain_life(pawn, atk_side["skills"], dealt)
		_try_knockback(pawn, target_pawn, atk_side["skills"])
	if bool(def_side["hit"]):
		_drain_life(target_pawn, def_side["skills"], taken)
		_try_knockback(target_pawn, pawn, def_side["skills"])

	# --- Bascules de phase, dans les deux sens ---
	# Après les afflictions (une phase peut les lever) et avant les morts : un
	# boss encore debout doit rugir pendant qu'il est encore là. Les deux camps,
	# parce que rien n'interdit à un boss d'être du côté du joueur, et que
	# l'appel ne coûte rien à qui n'en est pas un.
	check_boss_phases(target_pawn)
	check_boss_phases(pawn)

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
	# Le tueur est nommé : c'est l'autre bout de l'échange qu'on vient de résoudre,
	# et personne d'autre ne le saura après coup. Le bilan détaillé
	# ([BattleReport]) en fait sa colonne « Kills ».
	if defender_fell:
		_check_death(target_pawn, attacker_name)
	if attacker_fell:
		_check_death(pawn, defender_name)


#region Passes de figurine
## Demande une passe d'animation à la figurine d'un pion.
##
## Peu de personnages ont un coup, une blessure et une chute dessinés : le pack
## Tiny Swords ne connaît que le repos et la course, une planche de fiche ne
## bouge pas du tout. L'appel est donc **toujours** facultatif — figurine absente,
## méthode absente, planche absente, il rend 0.0 et le combat continue comme
## avant. C'est ce qui permet de brancher l'animation une fois pour toutes ici,
## sans conditionner chaque site d'appel à qui la possède.
##
## [returns] la durée de la passe en secondes, 0.0 s'il ne s'est rien passé.
static func play_figure(p: TacticsPawn, clip: StringName) -> float:
	if not p or not is_instance_valid(p):
		return 0.0
	var figure: Node = p.get_node_or_null("Character")
	if not figure or not figure.has_method(&"play_clip"):
		return 0.0
	return float(figure.play_clip(clip))


## La même passe, dans [param delay] secondes.
static func _play_figure_later(p: TacticsPawn, clip: StringName, delay: float) -> void:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return
	# Le pion peut tomber avant l'échéance : la validité se revérifie à l'arrivée.
	(loop as SceneTree).create_timer(delay).timeout.connect(func() -> void:
		play_figure(p, clip))
#endregion


## Les coups portés par un camp, mis en images ([BattleVFX] s'occupe du reste).
##
## Un coup manqué ne montre rien : l'oreille l'apprend déjà (`miss`), et un
## éclat sur une esquive ferait croire à un dégât.
func _show_blows(victim: TacticsPawn, side: Dictionary, magical: bool, delay: float) -> void:
	if not bool(side["hit"]):
		return
	BattleVFX.play_strike(victim, magical, bool(side["crit"]), int(side["hits"]), delay)
	# La blessure suit l'éclat, riposte comprise : jouée tout de suite, elle
	# précéderait de trois dixièmes le coup censé l'avoir causée.
	if is_zero_approx(delay):
		play_figure(victim, &"hurt")
	else:
		_play_figure_later(victim, &"hurt", delay)


## Résumé d'un camp dans un échange : a-t-il touché, critiqué, combien de coups.
func _side_summary(rolled: Dictionary, side: String) -> Dictionary:
	var out: Dictionary = {"strikes": 0, "hits": 0, "hit": false, "crit": false, "skills": []}
	for blow: Dictionary in rolled["strikes"]:
		if str(blow["side"]) != side:
			continue
		out["strikes"] = int(out["strikes"]) + 1
		if bool(blow["hit"]):
			out["hit"] = true
			out["hits"] = int(out["hits"]) + 1
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
	BattleVFX.play_heal(target)

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
##
## [param killer] Nom affiché de qui l'a mis à terre, quand on le connaît.
func _check_death(p: TacticsPawn, killer: String = "") -> void:
	# Only process if dead
	if p.is_alive():
		return

	# La gerbe est posée avant que le pion ne disparaisse : elle vit sous
	# [BattleVFX], pas sous lui, et lui survit donc de quelques dixièmes.
	# Le son, lui, part du journal ci-dessous — [Audio] l'écoute déjà.
	BattleVFX.play_death(p)

	# La chute dessinée, quand le personnage en a une : elle décide de combien de
	# temps le pion reste à l'écran. Sans elle (le pack, une planche de fiche),
	# `fall` vaut 0 et le retrait garde exactement le rythme qu'il a toujours eu.
	var fall: float = play_figure(p, &"die")

	# Journal de bataille : la mort est l'événement le plus utile à Ciel.
	_record(&"record_death", [_get_name(p), team_name_for_camp(p.get_parent()), killer])

	# Non-interactive immediately: la case est libre dès la mort constatée, même si
	# le corps met encore une demi-seconde à finir de tomber.
	p.res.can_move = false
	p.res.can_attack = false

	# Disable collision so tile raycast stops detecting the pawn
	for child in p.get_children():
		if child is CollisionShape3D:
			child.disabled = true

	var tree := p.get_tree()
	if fall <= 0.0:
		p.visible = false
		if tree:
			tree.create_timer(0.5).timeout.connect(p.queue_free)
	elif tree:
		# Le corps tient sa dernière pose avant de s'effacer — la faire disparaître
		# à la première image de la chute reviendrait à ne pas l'avoir dessinée.
		tree.create_timer(fall).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.visible = false)
		tree.create_timer(fall + 0.5).timeout.connect(p.queue_free)
	else:
		p.visible = false

	# Check victory condition
	_check_victory(p)


## Camp d'un nœud de camp, tel que le journal de bataille l'écrit ("player",
## "opponent", "guest") — "unknown" si le nœud n'est aucun camp connu.
##
## Le camp se lit sur le **nom du nœud**, via [TeamData], et non sur les méthodes
## qu'il expose. Le test précédent — « ce camp sait-il montrer un menu d'actions ? »
## — était vrai des deux : `show_available_pawn_actions()` vit sur
## [TacticsParticipant], dont [TacticsOpponent] hérite tout autant que
## [TacticsPlayer]. Toutes les morts partaient donc au crédit du joueur : le bilan
## de fin de bataille annonçait zéro ennemi vaincu quel qu'ait été le carnage, et
## la mort d'un brigand jouait la plainte réservée aux alliés ([SoundDB.cue_for_event]).
static func team_name_for_camp(camp: Node) -> String:
	return TeamDataRef.state_team_name(TeamDataRef.side_for_camp_node(camp))


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

	# Un chapitre a son propre arbitre : [ChapterRunner] évalue l'objectif, écrit
	# le résultat dans la campagne et enchaîne. Ce chemin-ci date d'avant lui, et
	# les laisser courir ensemble **détruisait la partie suivante** : deux
	# secondes et huit dixièmes après le dernier mort, il déchargeait le niveau et
	# rentrait au menu — c'est-à-dire en plein chargement du chapitre suivant si
	# le joueur avait cliqué entre-temps. Écran figé, puis fermeture.
	#
	# On garde donc l'annonce (escarmouche, duel local : personne d'autre ne la
	# fait), mais on ne touche plus à la scène quand un runner est aux commandes.
	var runner_owns_outcome: bool = chapter_runner(killed_pawn) != null

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

	# Le runner enchaîne lui-même : on s'arrête à l'annonce.
	if runner_owns_outcome:
		return

	_show_victory_screen(tree)


## Le chapitre en cours a-t-il un arbitre ?
##
## On remonte depuis le pion jusqu'au niveau : c'est lui qui porte le
## [ChapterRunner] quand la bataille appartient à une campagne ou à une carte
## d'essai. Une escarmouche ou un duel local n'en a pas — et c'est là que le
## chemin hérité ci-dessus garde toute son utilité.
func chapter_runner(pawn: Node) -> Node:
	var node: Node = pawn
	while node:
		var runner: Node = node.get_node_or_null("ChapterRunner")
		if runner:
			return runner
		node = node.get_parent()
	return null


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
		# Les gains voyagent avec l'événement : l'écran de montée de niveau les
		# affiche, le replay les garde. Les recalculer à l'arrivée serait
		# impossible — le tirage est déjà consommé.
		_record(&"record", [BattleLog.Kind.LEVEL_UP, {
			"pawn": a_name, "level": attacker.stats.level, "exp": attacker.stats.exp,
			"gains": Stats.positive_gains(result.get("stat_gains", {})),
		}])
		if bool(result.get("promoted", false)):
			_record(&"record", [BattleLog.Kind.PROMOTION, {
				"pawn": a_name, "class_id": attacker.stats.character_class,
			}])


#region Afflictions
## L'affliction qu'un coup porté par cette arme pose, ou {} s'il n'en pose aucune.
##
## Le tirage est [b]passé en argument[/b] et non tiré ici : c'est ce qui rend la
## règle vérifiable en headless — on peut demander « et si le dé donnait 44 ? »
## sans jamais monter de bataille. [method _try_afflict] est le seul à tirer.
##
## [param roll] Tirage de 1 à 100. L'affliction tombe quand il ne dépasse pas la
## chance de l'arme : à 45 %, les tirages 1 à 45 affligent.
## [returns] {status: String, turns: int} — vide si l'arme est inoffensive ou si
## le dé a été clément.
static func status_from_weapon(weapon_id: String, roll: int) -> Dictionary:
	var spec: Dictionary = WeaponDB.inflicts(weapon_id)
	if spec.is_empty() or not StatusDB.exists(str(spec["status"])):
		return {}
	if roll > int(spec["chance"]):
		return {}
	return {"status": str(spec["status"]), "turns": int(spec["turns"])}


## Les afflictions que les compétences déclenchées pendant l'échange posent.
##
## Le pendant « compétence » de [method status_from_weapon], et la même règle de
## pureté — mais poussée plus loin : rien n'est tiré ici du tout. Le dé a déjà
## roulé dans [method FECombatCalculator.roll_strike], qui rend les identifiants
## des compétences ayant pris ; cette fonction ne fait que les traduire en
## afflictions. Elle se vérifie donc sans RNG, sans pion et sans bataille.
##
## [param skill_ids] Compétences réellement déclenchées par un camp.
## [returns] [{status, turns}] — vide si aucune n'afflige.
static func statuses_from_skills(skill_ids: Array) -> Array:
	var out: Array = []
	for id: Variant in skill_ids:
		var skill: Dictionary = SkillDBRef.get_skill(str(id))
		if str(skill.get("proc", "")) != "inflict":
			continue
		var status: String = str(skill.get("status", ""))
		if not StatusDB.exists(status):
			continue
		out.append({"status": status, "turns": int(skill.get("status_turns", 0))})
	return out


## Tente de poser sur [param victim] les afflictions du coup que vient de porter
## [param attacker] : celle de son arme, puis celles de ses compétences.
##
## Sans effet si l'assaillant n'afflige par aucune des deux voies, ou si la
## victime est déjà tombée — on n'empoisonne pas un mort.
##
## [param skill_ids] Compétences déclenchées par l'assaillant pendant l'échange,
## telles que [method _side_summary] les a collectées.
func _try_afflict(attacker: TacticsPawn, victim: TacticsPawn, skill_ids: Array = []) -> void:
	if not attacker or not victim or not attacker.stats or not victim.stats:
		return
	if not victim.is_alive():
		return

	# L'arme d'abord, les compétences ensuite. Les deux voies peuvent porter la
	# même affliction sans que rien ne double : [StatusEffects.apply] ne les
	# empile pas, il garde la plus longue des deux durées.
	var afflictions: Array = []
	var from_weapon: Dictionary = status_from_weapon(
		str(attacker.stats.equipped_weapon), randi_range(1, 100))
	if not from_weapon.is_empty():
		afflictions.append(from_weapon)
	afflictions.append_array(statuses_from_skills(skill_ids))

	for affliction: Dictionary in afflictions:
		_afflict(attacker, victim, str(affliction["status"]), int(affliction["turns"]))


## Pose une affliction et la journalise — ou dit qu'elle a été repoussée.
##
## Le passage obligé par [method Stats.suffer_status] est ce qui donne leur mot à
## dire aux compétences défensives : c'est là, et nulle part ailleurs, que le
## sang-froid raccourcit ce qu'il subit.
func _afflict(attacker: TacticsPawn, victim: TacticsPawn, status: String, turns: int) -> void:
	var applied: Dictionary = victim.stats.suffer_status(status, turns)
	var victim_name: String = _get_name(victim)

	if not bool(applied["ok"]):
		# Une affliction repoussée est un fait de combat, pas un non-événement :
		# sans cette ligne, le joueur croit que le dé a simplement été clément.
		if bool(applied.get("warded", false)):
			print("🛡 %s résiste : %s ne prend pas" % [victim_name, StatusDB.label(status)])
		return

	print("%s %s : %s pour %d tour(s)%s" % [
		StatusDB.glyph(str(applied["status"])), victim_name,
		str(applied["label"]), int(applied["turns"]),
		" (écourté)" if bool(applied.get("warded", false)) else "",
	])
	_record(&"record_status_applied", [
		_get_name(attacker), victim_name, str(applied["status"]), int(applied["turns"]),
	])
#endregion


#region Repoussement et drain
## Le recul que les compétences déclenchées demandent, ou {} si aucune.
##
## Le pendant « souffle » de [method statuses_from_skills], et la même pureté :
## le dé a déjà roulé dans [method FECombatCalculator.roll_strike], on ne fait
## ici que traduire des identifiants en cases de recul. Aucun tirage, aucun pion,
## aucune grille — la règle se vérifie sur une simple liste de chaînes.
##
## Deux ondes de choc dans le même échange ne s'additionnent pas : on garde la
## plus longue portée. Un pion ne recule qu'une fois par échange, si loin qu'on
## l'ait soufflé — additionner reviendrait à faire dépendre la distance du nombre
## de coups portés, c'est-à-dire de la vitesse, qui n'a rien à voir ici.
##
## [returns] {id: String, tiles: int} — vide si aucune compétence ne repousse.
static func knockback_from_skills(skill_ids: Array) -> Dictionary:
	var best: Dictionary = {}
	for id: Variant in skill_ids:
		var skill_id: String = str(id)
		if str(SkillDBRef.get_skill(skill_id).get("proc", "")) != "knockback":
			continue
		var tiles: int = SkillDBRef.push_tiles(skill_id)
		if tiles <= 0:
			continue
		if best.is_empty() or tiles > int(best["tiles"]):
			best = {"id": skill_id, "tiles": tiles}
	return best


## PV rendus à qui vient de frapper, par ses compétences de drain.
##
## Comptés sur les dégâts [b]réellement encaissés[/b] — ceux que
## [method FECombatCalculator.roll_exchange] a déjà plafonnés aux PV de la
## victime — et non sur ceux que le coup promettait : achever une cible à 2 PV
## avec une frappe qui en annonçait quarante ne rend qu'un point. Sans ce
## plafond, le drain récompenserait le surtuage.
static func drain_from_skills(skill_ids: Array, damage: int) -> int:
	if damage <= 0:
		return 0
	var total: int = 0
	for id: Variant in skill_ids:
		var skill_id: String = str(id)
		if str(SkillDBRef.get_skill(skill_id).get("proc", "")) != "drain":
			continue
		total += int(floor(float(damage) * SkillDBRef.heal_ratio(skill_id)))
	return total


## Rend à [param drainer] les PV que ses compétences de drain lui ont volés.
##
## Sans effet s'il est tombé entre-temps : un mort ne boit pas. Le soin est
## plafonné par [method Stats.apply_to_curr_health], qui ne dépasse pas les PV
## maximum — un drain sur une unité intacte ne rend donc rien, et c'est voulu.
##
## [returns] les PV réellement rendus.
func _drain_life(drainer: TacticsPawn, skill_ids: Array, damage: int) -> int:
	if not drainer or not is_instance_valid(drainer) or not drainer.stats:
		return 0
	if not drainer.is_alive():
		return 0
	var wanted: int = drain_from_skills(skill_ids, damage)
	if wanted <= 0:
		return 0

	var before: int = drainer.stats.hp
	drainer.stats.apply_to_curr_health(wanted)
	var gained: int = drainer.stats.hp - before
	if gained <= 0:
		return 0

	BattleVFX.play_heal(drainer)
	var drainer_name: String = _get_name(drainer)
	print_rich("[color=purple]🩸 Drain du Puits : %s reprend %d PV (%d/%d)[/color]" % [
		drainer_name, gained, drainer.stats.hp, drainer.stats.max_hp,
	])
	# Journalisé comme un soin : c'en est un, et le bilan de fin de bataille
	# comme l'historique savent déjà lire cet événement-là. Le drainer se soigne
	# lui-même, d'où le même nom des deux côtés.
	_record(&"record_heal", [drainer_name, drainer_name, gained, drainer.stats.hp])
	return gained


## Repousse [param victim] du coup que [param attacker] vient de porter.
##
## [b]Trois décisions, toutes délibérées.[/b]
##
## [i]Une cible tuée ne recule pas.[/i] Le corps tombe là où il se tenait. Le
## déplacer servirait le spectacle et desservirait la lecture : une case libérée
## une case plus loin que là où le joueur l'attend ouvre un chemin que personne
## n'a vu s'ouvrir. C'est aussi ce qui rend l'ordre d'appel important — le recul
## se joue avant que [method _check_death] ne retire le pion.
##
## [i]Une cible acculée encaisse quand même.[/i] Les dégâts du souffle sont déjà
## dans le coup ([method FECombatCalculator.roll_strike]) ; ce qui se décide ici
## n'est que le déplacement, et un mur n'a jamais amorti une onde de choc. Le
## contraire ferait de chaque muraille une armure.
##
## [i]Le recul est partiel plutôt que tout ou rien.[/i] La règle vit dans
## [method Knockback.resolve], qui la documente.
##
## [returns] le compte rendu de [Knockback], {} si rien n'a été tenté.
func _try_knockback(attacker: TacticsPawn, victim: TacticsPawn, skill_ids: Array) -> Dictionary:
	var spec: Dictionary = knockback_from_skills(skill_ids)
	if spec.is_empty():
		return {}
	if not attacker or not victim or not is_instance_valid(attacker) or not is_instance_valid(victim):
		return {}
	if not victim.is_alive():
		return {}

	# Hors bataille montée (test headless d'un simple échange), il n'y a pas de
	# cases où reculer : le coup reste porté, le recul n'a simplement pas lieu.
	var grid: BattleGrid = BattleGrid.current
	if not grid:
		return {}

	var from: Vector2i = grid.coord_at_position(attacker.global_position)
	var at: Vector2i = grid.coord_at_position(victim.global_position)
	var push: Dictionary = KnockbackRef.push_from(grid, from, at, int(spec["tiles"]))

	var skill_name: String = SkillDBRef.get_skill_name(str(spec["id"]))
	var victim_name: String = _get_name(victim)
	if int(push["tiles"]) <= 0:
		# Un recul empêché est un fait de combat, pas un non-événement : sans
		# cette ligne, le joueur croit que la compétence n'a pas pris.
		print("↦ %s : %s ne recule pas, la voie est barrée" % [skill_name, victim_name])
		return push

	apply_push(victim, grid, push["to"])
	print_rich("[color=aqua]↦ %s : %s est repoussé de %d case%s%s[/color]" % [
		skill_name, victim_name, int(push["tiles"]),
		"" if int(push["tiles"]) <= 1 else "s",
		" (arrêté net)" if bool(push["blocked"]) else "",
	])

	var from_cell: Vector2i = _cell_of(grid, push["from"])
	var to_cell: Vector2i = _cell_of(grid, push["to"])
	_record(&"record_knockback", [
		_get_name(attacker), victim_name, str(spec["id"]), int(push["tiles"]),
		from_cell.x, from_cell.y, to_cell.x, to_cell.y, bool(push["blocked"]),
	])
	return push


## Pose un pion repoussé sur sa case d'arrivée.
##
## Le déplacement forcé [b]ne passe pas par la pile de cheminement[/b]
## ([TacticsPawnMovementService.move_along_path]). Celle-ci est le trajet que le
## pion a choisi : elle se consomme à son tour, sous son contrôle, et coûte son
## déplacement. Un recul n'est ni choisi, ni payé, ni annulable — il se pose.
## Passer par la pile rendrait en prime le pion « en mouvement » pendant qu'un
## autre camp joue, ce dont aucun tour ne sait quoi faire.
##
## La position dans le monde suffit à tout : c'est elle que l'index relit
## ([method BattleGrid.coord_at_position]), donc poser le pion au centre de sa
## nouvelle case le fait changer de case pour l'occupation, la portée et le
## cheminement d'un seul geste. L'index est corrigé dans la foulée, sans attendre
## l'image suivante : le second coup de l'échange s'appuie dessus.
static func apply_push(victim: TacticsPawn, grid: BattleGrid, coord: Vector2i) -> bool:
	if not victim or not is_instance_valid(victim) or grid == null:
		return false
	var tile: Node3D = grid.tile_at(coord) as Node3D
	if not tile:
		return false

	var was: Vector2i = grid.coord_at_position(victim.global_position)
	victim.global_position = tile.global_position
	grid.place_occupant(was, null)
	grid.place_occupant(coord, victim)
	return true


## Coordonnée (colonne, ligne) d'une case, telle que le journal l'écrit.
## Rend (-1, -1) hors plateau — la même convention que [method BattleGrid.cell_of].
static func _cell_of(grid: BattleGrid, coord: Vector2i) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	return grid.cell_of(grid.tile_at(coord))
#endregion


#region Phases de boss
## Fait basculer [param p] dans les phases que ses PV viennent de franchir, et
## raconte ce qui vient d'arriver.
##
## [b]Statique et sans condition à l'appel[/b], comme [method play_figure] : le
## site d'appel n'a pas à savoir si le pion est un boss. Les deux endroits qui
## retirent des PV l'appellent — l'échange de coups
## ([method _apply_exchange]) et les afflictions de début de tour
## ([method TacticsPawn._resolve_statuses]) — et un poison qui pousse un boss sous
## son seuil le fait rugir tout autant qu'un coup d'épée. Ne rien brancher sur la
## seconde voie laisserait une bascule silencieuse : le boss gagnerait ses
## statistiques au coup [i]suivant[/i], ou jamais si personne ne le frappe plus.
##
## La décision revient entièrement à [method Stats.advance_boss_phases] ; ici on
## ne fait que la mettre en mots et en son.
##
## [returns] les phases déclenchées (vide dans l'immense majorité des appels).
static func check_boss_phases(p: TacticsPawn) -> Array:
	if not p or not is_instance_valid(p) or not p.stats:
		return []

	var fired: Array = p.stats.advance_boss_phases()
	if fired.is_empty():
		return []

	var boss_name: String = p.display_name()
	for phase: Dictionary in fired:
		var message: String = str(phase["message"])
		if message.is_empty():
			message = "%s change de posture." % boss_name
		print_rich("[color=gold][b]👑 %s[/b][/color]  (%s : %d/%d PV)" % [
			message, boss_name, int(phase["hp"]), int(phase["max_hp"]),
		])
		var detail: String = BossPhases.effects_summary(phase)
		if not detail.is_empty():
			print("   ↳ %s" % detail)
		_record(&"record_boss_phase", [boss_name, phase])
	return fired
#endregion


## Journalise un événement via l'autoload BattleRecorder, s'il est présent.
## Reste silencieux hors runtime complet (tests unitaires headless).
static func _record(method: StringName, args: Array) -> void:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return
	var recorder: Node = (loop as SceneTree).root.get_node_or_null("BattleRecorder")
	if recorder and recorder.has_method(method):
		recorder.callv(method, args)


## Helper: get display name of a pawn (unique au sein du camp)
func _get_name(p: TacticsPawn) -> String:
	return p.display_name()


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
