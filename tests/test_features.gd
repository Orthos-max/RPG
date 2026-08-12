extends SceneTree
## Tests headless des features ajoutées (P0 → Solo).
## Lancer : godot --headless --path . --script res://tests/test_features.gd
##
## Couvre la logique pure : validation des commandes CielAI, IA locale,
## croissances de classe, promotions embranchées, armes efficaces, objets,
## objectifs de chapitre, sauvegarde de campagne, difficulté et session.

const CMD = preload("res://data/models/world/ai/ciel_command.gd")
const BRAIN = preload("res://data/models/world/ai/local_ai.gd")
const DIFF = preload("res://data/models/world/ai/difficulty.gd")
const CDB = preload("res://data/models/world/stats/class_data.gd")
const WT = preload("res://data/models/world/stats/weapon_type.gd")
const ITEMS = preload("res://data/models/world/stats/item_db.gd")
const WEAPONS = preload("res://data/models/world/stats/weapon_db.gd")
const CMAP = preload("res://data/models/campaign/chapter_map.gd")
const MAP_DATA = preload("res://data/models/world/map/map_data.gd")
const OBJ = preload("res://data/models/campaign/objective.gd")
const SKILLS = preload("res://data/models/world/stats/skill_db.gd")
const GLOSSARY = preload("res://data/models/world/stats/stat_glossary.gd")
const CAMPAIGN_DB = preload("res://data/models/campaign/campaign_db.gd")
const StatsRes = preload("res://data/models/world/stats/stats_res.gd")
const CharStats = preload("res://data/modules/stats/stats.gd")
const Calc = preload("res://data/services/combat/fe_combat.gd")
const SPLIT = preload("res://data/models/world/combat/team/army_split.gd")
const HISTORY = preload("res://data/modules/ui/battle_history.gd")
const SPEED = preload("res://data/modules/ui/battle_speed.gd")
const BattleLogRef = preload("res://data/services/combat/battle_log.gd")

var _passed: int = 0
var _failed: int = 0
var _lines: Array = []


func _init() -> void:
	print("\n========================================")
	print("  TESTS FEATURES — Ciel Emblem")
	print("========================================\n")

	await create_timer(0.3).timeout

	_test_command_validation()
	_test_local_ai()
	_test_growths()
	_test_promotion()
	_test_effectiveness()
	_test_items_and_buffs()
	_test_objectives()
	_test_campaign_save()
	_test_difficulty()
	_test_session()
	await _test_skills()
	_test_economy()
	await _test_item_buttons()
	_test_network_codes()
	_test_three_way()
	_test_reconnection()
	_test_deployment()
	_test_ux_polish()
	_test_comfort()
	_test_audio()
	_test_map_editor()
	_test_map_history()
	_test_battle_grid()
	_test_path_field()
	_test_traversal_rules()
	_test_charter()

	print("\n========================================")
	print("  RÉSULTATS: %d OK / %d ÉCHECS" % [_passed, _failed])
	print("========================================\n")
	for l in _lines:
		print(l)

	await create_timer(0.2).timeout
	quit(0 if _failed == 0 else 1)


#region Helpers
func _ok(label: String) -> void:
	_passed += 1
	_lines.append("  ✅ %s" % label)


func _ko(label: String, detail: String = "") -> void:
	_failed += 1
	_lines.append("  ❌ %s — %s" % [label, detail])


func _check(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		_ok(label)
	else:
		_ko(label, detail)


func _live(path: String) -> CharStats:
	var s := CharStats.new()
	s.import_stats(load(path))
	return s
#endregion


#region 1. Validation des commandes CielAI
func _test_command_validation() -> void:
	print("🔐 Test 1: validation des commandes CielAI")

	var ctx: Dictionary = {"stage": CMD.STAGE_SHOW_ACTIONS, "turn": "opponent",
		"grid_size": {"x": 16, "y": 10}}

	var ok: Dictionary = CMD.parse('{"action": "move", "col": 5, "row": 3}', ctx)
	_check(bool(ok["ok"]) and ok["args"]["col"] == 5, "move (5,3) acceptée", str(ok))

	var bad_json: Dictionary = CMD.parse('{"action": ', ctx)
	_check(int(bad_json["code"]) == CMD.Err.MALFORMED_JSON, "JSON malformé rejeté", str(bad_json))

	var not_dict: Dictionary = CMD.parse('[1, 2, 3]', ctx)
	_check(int(not_dict["code"]) == CMD.Err.NOT_A_DICT, "JSON non-objet rejeté", str(not_dict))

	var unknown: Dictionary = CMD.parse('{"action": "teleport"}', ctx)
	_check(int(unknown["code"]) == CMD.Err.UNKNOWN_ACTION, "action inconnue rejetée", str(unknown))

	var missing: Dictionary = CMD.parse('{"action": "move", "col": 2}', ctx)
	_check(int(missing["code"]) == CMD.Err.MISSING_ARG, "argument manquant rejeté", str(missing))

	var bad_type: Dictionary = CMD.parse('{"action": "move", "col": "cinq", "row": 3}', ctx)
	_check(int(bad_type["code"]) == CMD.Err.BAD_ARG_TYPE, "argument mal typé rejeté", str(bad_type))

	var out_of_grid: Dictionary = CMD.parse('{"action": "move", "col": 99, "row": 3}', ctx)
	_check(int(out_of_grid["code"]) == CMD.Err.OUT_OF_RANGE, "case hors grille rejetée", str(out_of_grid))

	var wrong_stage: Dictionary = CMD.parse('{"action": "select_pawn", "name": "Skeleton"}', ctx)
	_check(int(wrong_stage["code"]) == CMD.Err.WRONG_STAGE, "action hors étape rejetée", str(wrong_stage))

	var off_turn: Dictionary = CMD.parse('{"action": "end_turn"}',
		{"stage": CMD.STAGE_SELECT_PAWN, "turn": "player"})
	_check(int(off_turn["code"]) == CMD.Err.OUT_OF_TURN, "commande hors tour rejetée", str(off_turn))

	var toggle: Dictionary = CMD.parse('{"action": "toggle", "enabled": false}', {"turn": "player"})
	_check(bool(toggle["ok"]) and bool(toggle["global"]), "toggle accepté hors tour", str(toggle))

	# JSON ne distingue pas int et float : 5.0 doit passer, 5.4 non.
	var float_int: Dictionary = CMD.parse('{"action": "move", "col": 5.0, "row": 3.0}', ctx)
	_check(bool(float_int["ok"]), "5.0 accepté comme entier", str(float_int))

	var empty_name: Dictionary = CMD.parse('{"action": "attack", "name": "  "}', ctx)
	_check(int(empty_name["code"]) == CMD.Err.MISSING_ARG, "nom vide rejeté", str(empty_name))

	_check(CMD.supported_actions().size() >= 12, "12+ actions documentées",
		str(CMD.supported_actions().size()))
#endregion


#region 2. IA locale
func _test_local_ai() -> void:
	print("\n🧠 Test 2: IA locale heuristique")

	var actor: Dictionary = BRAIN.make_unit({"name": "Skeleton", "col": 5, "row": 5,
		"hp": 20, "max_hp": 20, "atk": 10, "def": 3, "movement": 4, "attack_range": 1})

	var healthy: Dictionary = BRAIN.make_unit({"name": "Tank", "team": "player",
		"col": 6, "row": 5, "hp": 30, "max_hp": 30, "atk": 8, "def": 8})
	var wounded: Dictionary = BRAIN.make_unit({"name": "Cleric", "team": "player",
		"col": 4, "row": 5, "hp": 4, "max_hp": 20, "atk": 3, "def": 1})

	var decision: Dictionary = BRAIN.decide(actor, [], [healthy, wounded], [], DIFF.Level.NORMAL)
	_check(decision["action"] == "attack" and decision["target"] == "Cleric",
		"achève la cible à portée de mort (%s)" % str(decision.get("reason", "")), str(decision))

	# Sans ennemi à portée, l'IA se rapproche.
	var far: Dictionary = BRAIN.make_unit({"name": "Lord", "team": "player",
		"col": 12, "row": 5, "hp": 25, "max_hp": 25, "atk": 9, "def": 5})
	var reachable: Array = [
		{"col": 6, "row": 5, "def_bonus": 0},
		{"col": 8, "row": 5, "def_bonus": 0},
	]
	var approach: Dictionary = BRAIN.decide(actor, [], [far], reachable, DIFF.Level.NORMAL)
	_check(approach["action"] == "move" and int(approach["col"]) == 8,
		"se rapproche par la case la plus avancée", str(approach))

	# À valeur égale, le terrain défensif l'emporte.
	var forest: Array = [
		{"col": 6, "row": 5, "def_bonus": 0},
		{"col": 5, "row": 6, "def_bonus": 3},
	]
	var target_adj: Dictionary = BRAIN.make_unit({"name": "Foe", "team": "player",
		"col": 5, "row": 7, "hp": 30, "max_hp": 30, "atk": 5, "def": 2})
	var terrain_choice: Dictionary = BRAIN.decide(actor, [], [target_adj], forest, DIFF.Level.NORMAL)
	_check(int(terrain_choice["col"]) == 5 and int(terrain_choice["row"]) == 6,
		"préfère la case défensive adjacente à la cible", str(terrain_choice))

	# Dégâts attendus : magie vs RES, physique vs DEF, terrain compris.
	var mage: Dictionary = BRAIN.make_unit({"atk": 10, "is_magical": true})
	var armored: Dictionary = BRAIN.make_unit({"def": 9, "res": 1, "terrain_def": 1})
	_check(BRAIN.expected_damage(mage, armored) == 8.0, "magie vise la RÉS (10-1-1=8)",
		str(BRAIN.expected_damage(mage, armored)))

	_check(BRAIN.exposure({"col": 0, "row": 0}, [
		BRAIN.make_unit({"col": 2, "row": 0, "movement": 3}),
		BRAIN.make_unit({"col": 15, "row": 9, "movement": 3}),
	]) == 1, "exposition : 1 menace sur 2 à portée")

	# Case occupée par un allié : écartée des destinations.
	var ally: Dictionary = BRAIN.make_unit({"name": "Ally", "col": 8, "row": 5})
	var blocked: Dictionary = BRAIN.decide(actor, [ally], [far], reachable, DIFF.Level.NORMAL)
	_check(int(blocked["col"]) != 8 or int(blocked["row"]) != 5,
		"n'empile pas deux alliés sur une case", str(blocked))

	# Un archer collé à sa cible ne tire plus : la portée a un plancher autant
	# qu'un plafond. Sans cela, Virion tirait à bout portant.
	var bowman_actor: Dictionary = BRAIN.make_unit({"name": "Virion", "col": 5, "row": 5,
		"hp": 20, "max_hp": 20, "atk": 12, "attack_range": 2, "min_range": 2})
	var prey: Dictionary = BRAIN.make_unit({"name": "Proie", "team": "player",
		"col": 6, "row": 5, "hp": 20, "max_hp": 20, "atk": 5, "def": 2})
	var adjacent_only: Array = [{"col": 5, "row": 5, "def_bonus": 0}]
	var stuck: Dictionary = BRAIN.decide(bowman_actor, [], [prey], adjacent_only, DIFF.Level.NORMAL)
	_check(str(stuck["action"]) != "attack",
		"l'archer au contact ne tire pas (%s)" % str(stuck["action"]), str(stuck))

	var far_prey: Dictionary = BRAIN.make_unit({"name": "Proie", "team": "player",
		"col": 7, "row": 5, "hp": 20, "max_hp": 20, "atk": 5, "def": 2})
	var shot: Dictionary = BRAIN.decide(bowman_actor, [], [far_prey], adjacent_only, DIFF.Level.NORMAL)
	_check(str(shot["action"]) == "attack", "mais il tire à deux cases", str(shot))

	# Portées : l'IA doit lire la riposte comme le moteur la résout.
	var archer: Dictionary = BRAIN.make_unit({"attack_range": 2, "min_range": 2})
	var swordsman: Dictionary = BRAIN.make_unit({"attack_range": 1, "min_range": 1})
	_check(not BRAIN.can_strike(archer, 1) and BRAIN.can_strike(archer, 2),
		"l'arc ne frappe qu'à 2 cases")
	_check(BRAIN.can_strike(swordsman, 1) and not BRAIN.can_strike(swordsman, 2),
		"la lame ne frappe qu'au contact")

	# Charger un archer coûte moins cher que l'aborder à sa portée : sa riposte
	# ne compte que dans le second cas.
	var bowman: Dictionary = BRAIN.make_unit({"name": "Virion", "team": "player",
		"col": 6, "row": 5, "hp": 20, "max_hp": 20, "atk": 12, "def": 2,
		"attack_range": 2, "min_range": 2})
	var at_range: float = BRAIN.score_target(actor, bowman, DIFF.Level.NORMAL, 2)
	var in_melee: float = BRAIN.score_target(actor, bowman, DIFF.Level.NORMAL, 1)
	_check(in_melee > at_range, "préfère charger l'archer que le tenir à distance",
		"contact %.1f vs distance %.1f" % [in_melee, at_range])
#endregion


#region 3. Croissances par classe
func _test_growths() -> void:
	print("\n📈 Test 3: croissances par classe")

	var lord: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	var expected: Dictionary = CDB.get_growths(lord.character_class)
	_check(lord.hp_growth == int(expected["hp"]) and lord.spd_growth == int(expected["spd"]),
		"croissances importées depuis class_data (%d HP / %d SPD)" % [lord.hp_growth, lord.spd_growth],
		"attendu %s" % str(expected))

	# Montée de niveau déterministe : même graine → même résultat.
	var a: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	var b: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 4242
	rng_b.seed = 4242
	var gains_a: Dictionary = a.level_up(rng_a)
	var gains_b: Dictionary = b.level_up(rng_b)
	_check(gains_a == gains_b and a.level == 2, "montée de niveau reproductible (graine fixe)",
		"%s vs %s" % [str(gains_a), str(gains_b)])

	# Croissance à 0% ne donne jamais de gain, à 100% en donne toujours.
	var c: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	c.hp_growth = 100
	c.str_growth = 0
	c.mag_growth = 0
	c.skl_growth = 0
	c.spd_growth = 0
	c.lck_growth = 0
	c.def_growth = 0
	c.res_growth = 0
	var hp_before: int = c.max_hp
	var gains: Dictionary = c.level_up()
	_check(c.max_hp == hp_before + 1 and int(gains.get("str", 0)) == 0,
		"croissance 0% jamais / 100% toujours", str(gains))

	# EXP : le passage de niveau consomme le palier.
	var d: CharStats = _live("res://data/models/world/stats/hero/archer.tres")
	var result: Dictionary = d.gain_exp(200)
	_check(bool(result["leveled_up"]) and int(result["new_level"]) > 1,
		"200 EXP → niveau %d" % int(result["new_level"]), str(result))
#endregion


#region 4. Promotion embranchée
func _test_promotion() -> void:
	print("\n🎖 Test 4: promotion embranchée")

	var branches: Array = CDB.get_promotions(CDB.Id.LORD)
	_check(branches.size() == 2 and CDB.Id.MASTER_LORD in branches,
		"Lord → Great Lord / Master Lord", str(branches))
	_check(CDB.has_branching_promotion(CDB.Id.LORD), "embranchement détecté")
	_check(not CDB.has_branching_promotion(CDB.Id.KNIGHT), "Knight → une seule branche")

	_check(CDB.resolve_promotion(CDB.Id.LORD, "Master Lord") == CDB.Id.MASTER_LORD,
		"résolution par nom de classe")
	_check(CDB.resolve_promotion(CDB.Id.LORD, "Berserker") == -1,
		"branche illégale refusée")
	_check(CDB.resolve_promotion(CDB.Id.LORD, null) == CDB.Id.GREAT_LORD,
		"branche par défaut = première")

	var lord: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	var too_early: Dictionary = lord.promote_to("Master Lord")
	_check(not bool(too_early["promoted"]), "promotion refusée avant le niveau requis",
		str(too_early))

	lord.level = 10
	var def_before: int = lord.def
	var promoted: Dictionary = lord.promote_to("Master Lord")
	_check(bool(promoted["promoted"]) and lord.character_class == CDB.Id.MASTER_LORD,
		"promotion Master Lord appliquée", str(promoted))
	_check(lord.is_promoted and lord.def >= def_before,
		"bonus de promotion appliqués (DÉF %d → %d)" % [def_before, lord.def])
	_check(lord.spd_growth == int(CDB.get_growths(CDB.Id.MASTER_LORD)["spd"]),
		"croissances de la classe promue reprises")
	_check(not bool(lord.promote_to("Great Lord")["promoted"]),
		"pas de double promotion")

	# Classe sans embranchement : promotion automatique à la montée de niveau.
	var knight: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	knight.character_class = CDB.Id.KNIGHT
	knight.apply_class_growths(CDB.Id.KNIGHT)
	knight.is_promoted = false
	knight.level = 9
	knight.exp = 0
	var _r: Dictionary = knight.gain_exp(100)
	_check(knight.character_class == CDB.Id.GREAT_KNIGHT and knight.is_promoted,
		"promotion automatique sans embranchement (%s)" % CDB.get_class_name(knight.character_class))
#endregion


#region 5. Armes efficaces
func _test_effectiveness() -> void:
	print("\n🏹 Test 5: efficacité des armes")

	_check(WT.get_effective_multiplier(WT.Type.BOW, true) == 3, "arc x3 contre volant")
	_check(WT.get_effective_multiplier(WT.Type.BOW, false) == 1, "arc neutre au sol")
	_check(WT.get_effective_multiplier(WT.Type.SWORD, true) == 1, "épée neutre contre volant")
	_check(CDB.is_flying(CDB.Id.PEGASUS_KNIGHT) and CDB.is_flying(CDB.Id.WYVERN_LORD),
		"classes volantes déclarées")
	_check(not CDB.is_flying(CDB.Id.KNIGHT), "Knight n'est pas volant")

	var archer: CharStats = _live("res://data/models/world/stats/hero/archer.tres")
	var flyer: CharStats = _live("res://data/models/world/stats/mob/skeleton.tres")
	flyer.character_class = CDB.Id.PEGASUS_KNIGHT

	var ground: CharStats = _live("res://data/models/world/stats/mob/skeleton.tres")
	ground.character_class = CDB.Id.BRIGAND
	ground.def = flyer.def
	ground.res = flyer.res
	ground.weapon_type = flyer.weapon_type

	var vs_flyer = Calc.calculate(archer, flyer)
	var vs_ground = Calc.calculate(archer, ground)
	_check(vs_flyer.is_effective and not vs_ground.is_effective,
		"efficacité détectée uniquement contre le volant")
	_check(vs_flyer.damage > vs_ground.damage,
		"dégâts accrus : %d vs %d" % [vs_flyer.damage, vs_ground.damage])

	# Le terrain est bien répercuté dans le résultat.
	var with_terrain = Calc.calculate(archer, ground, {}, 3)
	_check(with_terrain.terrain_defense == 3 and with_terrain.damage == maxi(0, vs_ground.damage - 3),
		"bonus de terrain retranché (%d → %d)" % [vs_ground.damage, with_terrain.damage])
#endregion


#region 6. Objets & bonus temporaires
func _test_items_and_buffs() -> void:
	print("\n🧪 Test 6: objets et bonus temporaires")

	var hero: CharStats = _live("res://data/models/world/stats/hero/great_knight.tres")
	_check(hero.items.size() > 0, "inventaire importé depuis le .tres (%s)" % str(hero.items))

	hero.apply_to_curr_health(-15)
	var hp_before: int = hero.hp
	var used: Dictionary = hero.use_item("vulnerary")
	_check(bool(used["ok"]) and hero.hp == hp_before + 10, "Vulnerary soigne 10 PV", str(used))
	_check(not hero.has_item("Vulnerary"), "objet consommé")

	var again: Dictionary = hero.use_item("Vulnerary")
	_check(not bool(again["ok"]), "objet absent refusé", str(again))

	var unknown: Dictionary = hero.use_item("Excalibur")
	_check(not bool(unknown["ok"]), "objet inconnu refusé", str(unknown))

	_check(hero.add_item("Elixir") and hero.has_item("Elixir"), "ajout d'objet")

	# Garde : +2 DÉF pendant 2 tours, puis retour à la normale.
	var def_base: int = hero.def
	hero.apply_buff("def", 2, 2)
	_check(hero.def == def_base + 2, "buff appliqué (+2 DÉF)")
	hero.tick_buffs()
	_check(hero.def == def_base + 2, "buff encore actif au tour suivant")
	hero.tick_buffs()
	_check(hero.def == def_base, "buff expiré, stat restaurée")
	_check(hero.active_buffs().is_empty(), "aucun buff résiduel")

	_check(ITEMS.exists("elixir") and not ITEMS.exists("nope"), "catalogue d'objets")
#endregion


#region 7. Objectifs de chapitre
func _test_objectives() -> void:
	print("\n🎯 Test 7: objectifs de chapitre")

	var alive_players: Array = [{"name": "Lord", "hp": 10}, {"name": "Cleric", "hp": 8}]
	var dead_enemies: Array = [{"name": "Skeleton", "hp": 0}]
	var alive_enemies: Array = [{"name": "Skeleton", "hp": 5},
		{"name": "Skeleton Captain", "hp": 12}]

	var rout: Dictionary = OBJ.evaluate({"kind": OBJ.Kind.ROUT},
		{"turn": 3, "player_units": alive_players, "enemy_units": dead_enemies})
	_check(int(rout["status"]) == OBJ.Status.VICTORY, "ROUT : victoire quand tout est vaincu", str(rout))

	var in_progress: Dictionary = OBJ.evaluate({"kind": OBJ.Kind.ROUT},
		{"turn": 3, "player_units": alive_players, "enemy_units": alive_enemies})
	_check(int(in_progress["status"]) == OBJ.Status.IN_PROGRESS, "ROUT : en cours sinon")

	var defeat: Dictionary = OBJ.evaluate({"kind": OBJ.Kind.ROUT},
		{"turn": 3, "player_units": [{"name": "Lord", "hp": 0}], "enemy_units": alive_enemies})
	_check(int(defeat["status"]) == OBJ.Status.DEFEAT, "défaite si toute l'armée tombe")

	var boss_alive: Dictionary = OBJ.evaluate(
		{"kind": OBJ.Kind.DEFEAT_BOSS, "target": "Skeleton Captain"},
		{"turn": 2, "player_units": alive_players, "enemy_units": alive_enemies})
	_check(int(boss_alive["status"]) == OBJ.Status.IN_PROGRESS, "BOSS : en cours tant qu'il vit")

	var boss_dead: Dictionary = OBJ.evaluate(
		{"kind": OBJ.Kind.DEFEAT_BOSS, "target": "Skeleton Captain"},
		{"turn": 2, "player_units": alive_players,
		"enemy_units": [{"name": "Skeleton", "hp": 5}, {"name": "Skeleton Captain", "hp": 0}]})
	_check(int(boss_dead["status"]) == OBJ.Status.VICTORY, "BOSS : victoire à sa mort")

	var survive: Dictionary = OBJ.evaluate({"kind": OBJ.Kind.SURVIVE, "turns": 8},
		{"turn": 9, "player_units": alive_players, "enemy_units": alive_enemies})
	_check(int(survive["status"]) == OBJ.Status.VICTORY, "SURVIVE : victoire au tour 9/8")

	var protect_lost: Dictionary = OBJ.evaluate({"kind": OBJ.Kind.PROTECT, "target": "Cleric"},
		{"turn": 2, "player_units": [{"name": "Lord", "hp": 10}, {"name": "Cleric", "hp": 0}],
		"enemy_units": alive_enemies})
	_check(int(protect_lost["status"]) == OBJ.Status.DEFEAT, "PROTECT : défaite si la cible tombe")

	# Le pion mort est retiré de la scène : disparaître vaut tomber.
	var protect_gone: Dictionary = OBJ.evaluate({"kind": OBJ.Kind.PROTECT, "target": "Cleric"},
		{"turn": 2, "player_units": [{"name": "Lord", "hp": 10}], "enemy_units": alive_enemies})
	_check(int(protect_gone["status"]) == OBJ.Status.DEFEAT,
		"PROTECT : défaite si la cible a quitté le champ de bataille")

	# Au premier frame, le camp n'est pas encore peuplé : ne rien conclure.
	var protect_early: Dictionary = OBJ.evaluate({"kind": OBJ.Kind.PROTECT, "target": "Cleric"},
		{"turn": 1, "player_units": [], "enemy_units": alive_enemies})
	_check(int(protect_early["status"]) == OBJ.Status.IN_PROGRESS,
		"PROTECT : rien à juger tant que personne n'est en scène")

	var protect_held: Dictionary = OBJ.evaluate(
		{"kind": OBJ.Kind.PROTECT, "target": "Cleric", "turns": 3},
		{"turn": 4, "player_units": alive_players, "enemy_units": alive_enemies})
	_check(int(protect_held["status"]) == OBJ.Status.VICTORY,
		"PROTECT : victoire quand la cible a tenu le nombre de tours")
	_check(OBJ.protected_target({"kind": OBJ.Kind.PROTECT, "target": "Cleric"}) == "Cleric"
			and OBJ.protected_target({"kind": OBJ.Kind.ROUT}).is_empty(),
		"la protégée d'un chapitre est exposée")

	var bonuses: Array = OBJ.evaluate_bonuses(
		[{"kind": OBJ.Bonus.NO_LOSSES}, {"kind": OBJ.Bonus.SPEED_RUN, "turns": 5}],
		{"turn": 4, "player_units": alive_players, "enemy_units": dead_enemies})
	_check(bonuses.size() == 2 and bool(bonuses[0]["achieved"]) and bool(bonuses[1]["achieved"]),
		"objectifs secondaires validés", str(bonuses))

	# --- Prise de point : l'objectif longtemps resté sans carte ---
	var point: Dictionary = {"kind": OBJ.Kind.SEIZE, "col": 3, "row": 8}
	var away: Array = [{"name": "Lord", "hp": 10, "col": 8, "row": 2}]
	var onto: Array = [{"name": "Lord", "hp": 10, "col": 3, "row": 8}]

	_check(OBJ.seize_target(point) == Vector2i(3, 8), "case à prendre exposée")
	_check(OBJ.seize_target({"kind": OBJ.Kind.ROUT}) == Vector2i(-1, -1),
		"pas de case à prendre hors objectif SEIZE")
	_check(not OBJ.is_seized(point, away), "point non tenu tant que personne n'y est")
	_check(OBJ.is_seized(point, onto), "point tenu dès qu'une unité s'y pose")
	_check(not OBJ.is_seized(point, [{"name": "Lord", "hp": 0, "col": 3, "row": 8}]),
		"un mort ne tient pas le point")

	var seize_evaluated: Dictionary = OBJ.evaluate(point,
		{"turn": 5, "seized": true, "player_units": onto, "enemy_units": alive_enemies})
	_check(int(seize_evaluated["status"]) == OBJ.Status.VICTORY,
		"SEIZE : victoire même avec des ennemis debout")

	# Chapitre nommant son preneur : les autres unités ne comptent pas.
	var lord_only: Dictionary = {"kind": OBJ.Kind.SEIZE, "col": 3, "row": 8, "seizer": "Lord"}
	_check(not OBJ.is_seized(lord_only, [{"name": "Cleric", "hp": 8, "col": 3, "row": 8}]),
		"point réservé au seigneur : le clerc ne le prend pas")
	_check(OBJ.is_seized(lord_only, onto), "le seigneur désigné prend le point")
	_check(OBJ.describe(lord_only).contains("Lord"), "l'objectif annonce qui doit prendre le point",
		OBJ.describe(lord_only))

	# Contenu de campagne
	_check(CAMPAIGN_DB.count() >= 5, "au moins 5 chapitres définis (%d)" % CAMPAIGN_DB.count())
	var ch1 = CAMPAIGN_DB.get_chapter(0)
	_check(ch1 != null and ch1.id == "ch01" and not ch1.intro_lines.is_empty(),
		"chapitre 1 complet (%s)" % (ch1.title if ch1 else "?"))
	_check(CAMPAIGN_DB.index_of("ch02") == 1 and CAMPAIGN_DB.get_chapter(99) == null,
		"index de chapitre robuste")

	# Chaque chapitre doit être jouable : index cohérent, carte existante, et une
	# case à prendre qui tombe bien dans la grille quand l'objectif l'exige.
	for i: int in CAMPAIGN_DB.count():
		var ch = CAMPAIGN_DB.get_chapter(i)
		_check(ch != null and ch.index == i and ResourceLoader.exists(ch.scene_path),
			"chapitre %d cohérent (%s)" % [i, ch.title if ch else "?"],
			ch.scene_path if ch else "manquant")
		var target: Vector2i = OBJ.seize_target(ch.objective)
		if target.x >= 0:
			_check(target.x < 16 and target.y < 10,
				"%s : point de commandement dans la grille %s" % [ch.id, str(target)])
#endregion


#region 8. Sauvegarde de campagne
func _test_campaign_save() -> void:
	print("\n💾 Test 8: sauvegarde de campagne")

	var campaign: Node = root.get_node_or_null("Campaign")
	if not campaign:
		_ko("Autoload Campaign", "introuvable")
		return
	_ok("Autoload Campaign disponible")

	const SLOT: int = 9  # Slot de test, jamais celui du joueur
	campaign.new_game(DIFF.Level.BRUTAL, true)
	_check(campaign.roster.size() == CAMPAIGN_DB.STARTING_ROSTER.size(),
		"roster de départ : %d unités" % campaign.roster.size())
	_check(campaign.deployment.size() <= campaign.current_chapter().deploy_slots,
		"déploiement par défaut dans la limite des places")

	# Limite de déploiement respectée même si on demande tout le monde.
	var all_ids: Array = []
	for u: Dictionary in campaign.roster:
		all_ids.append(str(u["id"]))
	campaign.set_deployment(all_ids)
	_check(campaign.deployment.size() == campaign.current_chapter().deploy_slots,
		"places de déploiement plafonnées (%d)" % campaign.deployment.size())

	# Progression + XP reportés puis relus depuis le disque.
	var first_id: String = str(campaign.roster[0]["id"])
	campaign.apply_battle_result({"id": first_id, "hp": 12, "exp": 45, "level": 3,
		"str": 99, "class_id": campaign.roster[0]["class_id"]})
	campaign.gold = 777
	_check(campaign.save_game(SLOT), "sauvegarde écrite")
	_check(campaign.has_save(SLOT), "fichier de sauvegarde présent")

	campaign.new_game(DIFF.Level.EASY, false)  # On écrase l'état en mémoire
	_check(campaign.load_game(SLOT), "sauvegarde relue")
	var reloaded: Dictionary = campaign.get_unit(first_id)
	_check(int(reloaded["level"]) == 3 and int(reloaded["exp"]) == 45 and int(reloaded["str"]) == 99,
		"stats/XP/niveau persistés", str(reloaded))
	_check(campaign.gold == 777 and campaign.difficulty == DIFF.Level.BRUTAL,
		"or et difficulté persistés (%d / %d)" % [campaign.gold, campaign.difficulty])

	# Mort permanente : l'unité disparaît du roster déployable.
	campaign.permadeath = true
	campaign.apply_battle_result({"id": first_id, "hp": 0})
	var fallen: Dictionary = campaign.get_unit(first_id)
	_check(not bool(fallen["alive"]), "mort permanente enregistrée")
	var available_ids: Array = []
	for u: Dictionary in campaign.available_units():
		available_ids.append(str(u["id"]))
	_check(not first_id in available_ids, "unité tombée retirée du déploiement")

	# Sans mort permanente, l'unité revient à 1 PV.
	campaign.permadeath = false
	var second_id: String = str(campaign.roster[1]["id"])
	campaign.apply_battle_result({"id": second_id, "hp": 0})
	_check(bool(campaign.get_unit(second_id)["alive"]), "sans permadeath : unité conservée")

	# Progression de chapitre
	var before_index: int = campaign.chapter_index
	campaign.complete_chapter([{"kind": OBJ.Bonus.NO_LOSSES, "achieved": true, "label": "Aucune perte"}])
	_check(campaign.chapter_index == before_index + 1, "chapitre suivant débloqué")

	campaign.delete_save(SLOT)
	_check(not campaign.has_save(SLOT), "sauvegarde de test supprimée")

	_test_required_units(campaign)


## Unités imposées par un chapitre : elles doivent survivre à toute sélection.
func _test_required_units(campaign: Node) -> void:
	var index: int = CAMPAIGN_DB.index_of("ch06")
	if index < 0:
		_ko("Chapitre à protection", "aucun chapitre PROTECT dans CampaignDB")
		return

	campaign.new_game(DIFF.Level.NORMAL, true)
	campaign.chapter_index = index
	var chapter = campaign.current_chapter()
	_check(not chapter.required_units.is_empty(),
		"le chapitre %s impose des unités (%s)" % [chapter.id, str(chapter.required_units)])

	var protected_name: String = OBJ.protected_target(chapter.objective)
	var protected_id: String = protected_name.to_lower().replace(" ", "_")
	_check(protected_id in chapter.required_units,
		"la protégée (%s) fait partie des unités imposées" % protected_name)

	# Sélection qui l'oublie volontairement : elle doit revenir d'elle-même.
	var others: Array = []
	for u: Dictionary in campaign.available_units():
		if not str(u["id"]) in chapter.required_units:
			others.append(str(u["id"]))
	campaign.set_deployment(others)
	_check(protected_id in campaign.deployment,
		"une sélection qui oublie la protégée la remet en place", str(campaign.deployment))
	for id: String in chapter.required_units:
		_check(id in campaign.deployment, "unité imposée déployée : %s" % id)
	_check(campaign.deployment.size() <= chapter.deploy_slots,
		"les unités imposées comptent dans les places (%d/%d)" % [
			campaign.deployment.size(), chapter.deploy_slots])

	# Aucun doublon, même si la sélection la nomme aussi.
	campaign.set_deployment([protected_id, protected_id] + others)
	var seen: Array = []
	var duplicated: bool = false
	for id: String in campaign.deployment:
		if id in seen:
			duplicated = true
		seen.append(id)
	_check(not duplicated, "aucun doublon dans le déploiement", str(campaign.deployment))

	# Déploiement par défaut : la protégée y est aussi.
	campaign.set_deployment([])
	_check(protected_id in campaign.deployment,
		"même une sélection vide déploie les unités imposées")

	# Tombée en mort permanente, elle ne peut plus être exigée : le chapitre
	# resterait sinon bloqué sur une unité qui n'existe plus.
	campaign.permadeath = true
	campaign.apply_battle_result({"id": protected_id, "hp": 0})
	_check(not protected_id in campaign.required_deployment(),
		"une unité imposée mais tombée n'est plus exigée")
	campaign.new_game(DIFF.Level.NORMAL, true)
#endregion


#region 9. Difficulté
func _test_difficulty() -> void:
	print("\n⚖️ Test 9: difficulté")

	_check(DIFF.stat_handicap(DIFF.Level.EASY, 0) < DIFF.stat_handicap(DIFF.Level.BRUTAL, 0),
		"Facile plus tendre que Brutal")
	_check(DIFF.stat_handicap(DIFF.Level.NORMAL, 0) == 0, "Normal neutre au chapitre 1")
	_check(DIFF.stat_handicap(DIFF.Level.BRUTAL, 20) <= 2 + int(DIFF.DATA[DIFF.Level.BRUTAL]["max_scaling"]),
		"progression plafonnée",
		str(DIFF.stat_handicap(DIFF.Level.BRUTAL, 20)))
	_check(DIFF.stat_handicap(DIFF.Level.BRUTAL, 8) > DIFF.stat_handicap(DIFF.Level.BRUTAL, 0),
		"handicap progressif au fil des chapitres")

	var mob: CharStats = _live("res://data/models/world/stats/mob/skeleton.tres")
	var str_before: int = mob.str
	var hp_before: int = mob.max_hp
	var applied: Dictionary = DIFF.apply_to_stats(mob, DIFF.Level.BRUTAL, 0)
	_check(mob.str == str_before + int(applied["stat_bonus"])
			and mob.max_hp == hp_before + int(applied["hp_bonus"]),
		"handicap appliqué aux stats (%+d / %+d PV)" % [
			int(applied["stat_bonus"]), int(applied["hp_bonus"])])
	_check(mob.hp <= mob.max_hp, "PV courants bornés au maximum")

	_check(DIFF.get_level_name(DIFF.Level.EASY) == "Facile", "libellés de difficulté")
#endregion


#region 10. Session & équipes
func _test_session() -> void:
	print("\n🤝 Test 10: session, équipes et contrôleurs")

	var session: Node = root.get_node_or_null("GameSession")
	if not session:
		_ko("Autoload GameSession", "introuvable")
		return
	_ok("Autoload GameSession disponible")

	session.set_mode(session.Mode.CIEL)
	_check(session.is_ciel_controlled(), "mode CIEL → camp adverse à Ciel")

	session.set_ciel_enabled(false)
	_check(session.controller_for(TeamData.Side.OPPONENT) == TeamData.Controller.LOCAL_AI,
		"toggle off → IA locale")

	session.set_mode(session.Mode.NETWORK)
	_check(session.controller_for(TeamData.Side.OPPONENT) == TeamData.Controller.REMOTE_PLAYER,
		"mode réseau → joueur distant")
	_check(session.get_team(TeamData.Side.PLAYER).is_human(), "camp joueur = humain")

	var code: String = session.generate_join_code()
	_check(code.length() == 6 and not code.contains("O") and not code.contains("I"),
		"code d'invitation lisible : %s" % code)

	session.set_mode(session.Mode.SOLO)
	_check(session.controller_for(TeamData.Side.OPPONENT) == TeamData.Controller.LOCAL_AI,
		"mode solo → IA locale")

	var team: TeamData = TeamData.create(TeamData.Side.OPPONENT, TeamData.Controller.CIEL_AI)
	_check(team.is_ai() and team.is_local_authority(), "TeamData : CielAI est une IA locale")
	_check(TeamData.controller_name(TeamData.Controller.REMOTE_PLAYER) == "Joueur distant",
		"libellés de contrôleur")
#endregion


#region 11. Compétences
func _test_skills() -> void:
	print("\n✨ Test 11: arbre de compétences")

	# Déblocage par niveau de classe
	_check(CDB.unlocked_skills(CDB.Id.LORD, 1) == ["duelist"],
		"Lord Lv.1 : duelist seulement", str(CDB.unlocked_skills(CDB.Id.LORD, 1)))
	_check("focus" in CDB.unlocked_skills(CDB.Id.LORD, 5),
		"Lord Lv.5 : focus débloqué")
	var upcoming: Array = CDB.upcoming_skills(CDB.Id.LORD, 1)
	_check(upcoming.size() == 1 and str(upcoming[0]["id"]) == "focus",
		"compétences à venir listées", str(upcoming))

	# Conditions de déclenchement
	_check(SKILLS.is_active("duelist", {"attacking": true}), "duelist actif en attaque")
	_check(not SKILLS.is_active("duelist", {"attacking": false}), "duelist inactif en défense")
	_check(SKILLS.is_active("wrath", {"hp_ratio": 0.3}), "fureur active à 30% PV")
	_check(not SKILLS.is_active("wrath", {"hp_ratio": 0.9}), "fureur inactive à 90% PV")
	_check(SKILLS.is_active("terrain_affinity", {"terrain_def": 2}), "affinité terrain sur forêt")
	_check(not SKILLS.is_active("terrain_affinity", {"terrain_def": 0}), "affinité terrain hors couvert")
	_check(SKILLS.is_active("falcon_eye", {"attacking": true, "vs_flying": true}),
		"œil de faucon contre un volant")
	_check(not SKILLS.is_active("falcon_eye", {"attacking": true, "vs_flying": false}),
		"œil de faucon inactif au sol")

	# Agrégation
	var mods: Dictionary = SKILLS.aggregate(["duelist", "charge", "wrath"],
		{"attacking": true, "hp_ratio": 0.2})
	_check(int(mods["hit"]) == 10 and int(mods["damage"]) == 2 and int(mods["crit"]) == 20,
		"agrégat : +10 hit, +2 dmg, +20 crit", str(mods))
	var none: Dictionary = SKILLS.aggregate(["duelist"], {"attacking": false})
	_check(int(none["hit"]) == 0, "agrégat vide hors condition")

	# Compétences à déclenchement
	var procs: Array = SKILLS.active_procs(["luna", "astra", "duelist"], {"attacking": true}, 20)
	_check(procs.size() == 2, "2 procs disponibles", str(procs))
	var by_id: Dictionary = {}
	for p: Dictionary in procs:
		by_id[str(p["id"])] = p
	_check(int(by_id["luna"]["chance"]) == 20 and int(by_id["astra"]["chance"]) == 10,
		"chances calculées sur la Skl (20 / 10)", str(procs))

	# Effet réel sur un combat
	var lord: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	var mob: CharStats = _live("res://data/models/world/stats/mob/skeleton.tres")
	_check("duelist" in lord.get_skills(), "Chrom connaît duelliste (%s)" % str(lord.get_skills()))

	var with_skill = Calc.calculate(lord, mob)
	var stripped: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	stripped.character_class = CDB.Id.CAVALIER  # Classe sans compétence au Lv.1
	var without = Calc.calculate(stripped, mob)
	_check(with_skill.skill_hit == 10 and without.skill_hit == 0,
		"duelliste ajoute +10 de précision (%d vs %d)" % [with_skill.skill_hit, without.skill_hit])
	_check(with_skill.hit_rate == mini(100, without.hit_rate + 10) or with_skill.hit_rate == 100,
		"précision répercutée dans le jet")

	# Défense : le gardien encaisse mieux
	var brute: CharStats = _live("res://data/models/world/stats/mob/skeleton.tres")
	brute.str = 40  # Frappe assez fort pour que la réduction soit visible
	var knight: CharStats = _live("res://data/models/world/stats/hero/great_knight.tres")
	knight.character_class = CDB.Id.KNIGHT
	knight.level = 5
	var vs_knight = Calc.calculate(brute, knight)
	knight.character_class = CDB.Id.CAVALIER
	var vs_plain = Calc.calculate(brute, knight)
	_check(vs_knight.damage < vs_plain.damage,
		"rempart + gardien réduisent les dégâts (%d vs %d)" % [vs_knight.damage, vs_plain.damage])

	# Compétence hors classe
	var learner: CharStats = _live("res://data/models/world/stats/hero/cleric.tres")
	_check(learner.learn_skill("wrath") and "wrath" in learner.get_skills(),
		"compétence hors classe apprise")
	_check(not learner.learn_skill("wrath"), "pas de doublon")
	_check(not learner.learn_skill("inexistante"), "compétence inconnue refusée")

	# Retrait d'une compétence de classe : sans lui, une compétence donnée par la
	# classe serait indéracinable depuis l'éditeur de personnages.
	var forgetful: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	forgetful.character_class = CDB.Id.LORD
	forgetful.level = 5
	_check("duelist" in forgetful.get_skills() and "focus" in forgetful.get_skills(),
		"Lord Lv.5 part avec duelliste et concentration", str(forgetful.get_skills()))
	_check(forgetful.forget_skill("duelist") and not "duelist" in forgetful.get_skills(),
		"compétence de classe retirée", str(forgetful.get_skills()))
	_check(not forgetful.forget_skill("duelist"), "retirer deux fois ne rend rien")
	_check(forgetful.learn_skill("duelist") and "duelist" in forgetful.get_skills(),
		"la rendre après l'avoir retirée la réactive")

	# Le combat suit vraiment le retrait : c'est le seul test qui prouve que la
	# liste sert à autre chose qu'à s'afficher.
	var stripped_lord: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	stripped_lord.character_class = CDB.Id.LORD
	var before_strip = Calc.calculate(stripped_lord, mob)
	stripped_lord.forget_skill("duelist")
	var after_strip = Calc.calculate(stripped_lord, mob)
	_check(before_strip.skill_hit == 10 and after_strip.skill_hit == 0,
		"duelliste retiré ne compte plus en combat (%d → %d)" % [
			before_strip.skill_hit, after_strip.skill_hit])

	# Liste imposée : ce que l'éditeur écrit sur une fiche
	var imposed: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	imposed.character_class = CDB.Id.LORD
	imposed.level = 5
	imposed.set_skills(["focus", "luna"])
	_check(imposed.get_skills() == ["focus", "luna"],
		"liste imposée respectée à la lettre", str(imposed.get_skills()))
	_check("duelist" in imposed.removed_skills and "luna" in imposed.extra_skills,
		"traduite en retraits et en acquis",
		"retirés %s / acquis %s" % [str(imposed.removed_skills), str(imposed.extra_skills)])
	imposed.set_skills(["focus", "inexistante"])
	_check(imposed.get_skills() == ["focus"], "compétence inconnue écartée de la liste",
		str(imposed.get_skills()))
	imposed.set_skills([])
	_check(imposed.get_skills().is_empty(), "liste vide : plus aucune compétence",
		str(imposed.get_skills()))

	# La fiche de personnage porte ses compétences
	var doc: UnitDocument = UnitDocument.from_class(CDB.Id.LORD)
	_check(doc.skills == ["duelist"],
		"fiche neuve : les compétences de la classe", str(doc.skills))
	doc.skills = ["luna"]
	var round_trip: UnitDocument = UnitDocument.from_dict(doc.to_dict())
	_check(round_trip.skills == ["luna"],
		"compétences conservées à l'écriture et à la relecture", str(round_trip.skills))
	_check(round_trip.to_roster_unit().get("skills") == ["luna"],
		"compétences versées dans le roster", str(round_trip.to_roster_unit().get("skills")))
	doc.skills = ["inexistante"]
	_check(not doc.validate().is_empty(), "fiche à compétence inconnue refusée")

	# Une fiche écrite avant que les compétences soient réglables n'a pas la clé :
	# elle doit retrouver celles de sa classe, pas se retrouver sans rien.
	var old_file: Dictionary = doc.to_dict()
	old_file.erase("skills")
	var legacy: UnitDocument = UnitDocument.from_dict(old_file)
	_check(legacy.skills == ["duelist"],
		"fiche d'avant : compétences de classe rendues", str(legacy.skills))

	# Le glossaire des statistiques : toutes les stats réglables y sont
	var missing: Array[String] = []
	for key: String in UnitDocument.STATS:
		if GLOSSARY.tooltip(key).is_empty():
			missing.append(key)
	_check(missing.is_empty(), "chaque statistique a son explication", str(missing))
	_check(not GLOSSARY.tooltip("hit").is_empty(), "les valeurs dérivées aussi")
	_check(GLOSSARY.tooltip("inexistante").is_empty(),
		"clé inconnue : pas d'info-bulle vide et muette")
	_check(not SKILLS.tooltip("luna").is_empty() and SKILLS.tooltip("inexistante").is_empty(),
		"info-bulle de compétence, et rien pour une inconnue")
	_check(SKILLS.all_ids().size() == SKILLS.DATA.size(),
		"le catalogue de compétences s'énumère en entier")

	await _test_editor_tooltips()
#endregion


## L'éditeur monté pour de vrai, et ses info-bulles interrogées.
##
## Aucune autre suite ne charge cet écran : une faute de frappe y passait donc
## inaperçue jusqu'à ce qu'on l'ouvre à la main. C'est arrivé le 2026-08-09 —
## un champ déclaré `HFlowContainer` recevait un `VBoxContainer`, 620 tests
## restaient verts, et l'écran ne s'ouvrait plus du tout.
##
## On vérifie aussi `mouse_filter` : un Label l'a à `IGNORE` par défaut, et une
## info-bulle posée dessus ne s'afficherait jamais — le texte serait juste, et
## invisible.
func _test_editor_tooltips() -> void:
	print("\n🖱  Test 11bis: info-bulles de l'éditeur de personnages")

	var editor: Control = load("res://data/modules/menu/character_editor.gd").new()
	root.add_child(editor)
	await process_frame
	await process_frame

	var explained: int = 0
	var mute: Array[String] = []
	for node: Node in _walk(editor):
		if not node is Control:
			continue
		var control: Control = node
		if control.tooltip_text.is_empty():
			continue
		explained += 1
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			mute.append("%s (%s)" % [control.name, control.get_class()])

	_check(explained >= 15, "l'éditeur explique au moins 15 champs (%d)" % explained)
	_check(mute.is_empty(), "aucune info-bulle rendue muette par mouse_filter", str(mute))

	# Les compétences sont bien proposées à cocher, toutes, avec leur explication.
	var boxes: Array[CheckBox] = []
	for node: Node in _walk(editor):
		if node is CheckBox and str((node as CheckBox).tooltip_text).begins_with("✨"):
			boxes.append(node)
	_check(boxes.size() == SKILLS.DATA.size(),
		"une case par compétence du catalogue (%d)" % boxes.size())

	editor.queue_free()
	await process_frame


## Tous les nœuds sous `node`, lui compris.
func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
#endregion


#region 12. Économie entre chapitres
func _test_economy() -> void:
	print("\n🛒 Test 12: intendance (boutique, soins, recrutement)")

	var campaign: Node = root.get_node_or_null("Campaign")
	if not campaign:
		_ko("Autoload Campaign", "introuvable")
		return

	campaign.new_game(DIFF.Level.NORMAL, true)
	campaign.gold = 1000
	var id: String = str(campaign.roster[0]["id"])

	# Prix et catalogue
	_check(ITEMS.price("Vulnerary") > 0 and ITEMS.resale_price("Vulnerary") == ITEMS.price("Vulnerary") / 2,
		"prix d'achat et de revente")
	_check(ITEMS.shop_stock().size() >= 8, "catalogue de boutique (%d articles)" % ITEMS.shop_stock().size())
	_check(ITEMS.is_boost("Energy Drop") and not ITEMS.is_boost("Vulnerary"),
		"objets à effet permanent identifiés")

	# Achat
	var gold_before: int = campaign.gold
	var items_before: int = campaign.get_unit(id).get("items", []).size()
	var bought: Dictionary = campaign.buy_item(id, "Vulnerary")
	_check(bool(bought["ok"]) and campaign.gold == gold_before - ITEMS.price("Vulnerary"),
		"achat débité (%d → %d or)" % [gold_before, campaign.gold], str(bought))
	_check(campaign.get_unit(id).get("items", []).size() == items_before + 1,
		"objet remis à l'unité")

	# Revente
	var gold_mid: int = campaign.gold
	var sold: Dictionary = campaign.sell_item(id, "Vulnerary")
	_check(bool(sold["ok"]) and campaign.gold == gold_mid + ITEMS.resale_price("Vulnerary"),
		"revente créditée à moitié prix")
	_check(not bool(campaign.sell_item(id, "Elixir")["ok"]), "revente d'un objet absent refusée")

	# Or insuffisant
	campaign.gold = 10
	_check(not bool(campaign.buy_item(id, "Elixir")["ok"]), "achat refusé sans or")

	# Inventaire plein
	campaign.gold = 5000
	var unit: Dictionary = campaign.get_unit(id)
	unit["items"] = []
	for i in ITEMS.MAX_ITEMS:
		campaign.buy_item(id, "Vulnerary")
	var overflow: Dictionary = campaign.buy_item(id, "Vulnerary")
	_check(not bool(overflow["ok"]) and campaign.get_unit(id)["items"].size() == ITEMS.MAX_ITEMS,
		"inventaire plafonné à %d objets" % ITEMS.MAX_ITEMS)

	# Booster permanent
	unit["items"] = ["Energy Drop"]
	var str_before: int = int(campaign.get_unit(id)["str"])
	var boosted: Dictionary = campaign.use_booster(id, "Energy Drop")
	_check(bool(boosted["ok"]) and int(campaign.get_unit(id)["str"]) == str_before + 2,
		"potion de force : +2 FOR définitif (%d → %d)" % [str_before, int(campaign.get_unit(id)["str"])])
	_check(not bool(campaign.use_booster(id, "Vulnerary")["ok"]),
		"objet de combat refusé à l'intendance")

	# --- Consommer un objet hors bataille ---
	# Une potion achetée à l'intendance doit pouvoir s'y boire : sans cela on
	# achetait un objet que rien, nulle part, ne savait utiliser.
	unit["items"] = ["Vulnerary", "Def Tonic", "Seraph Robe"]
	var full_hp: int = int(unit["max_hp"])
	unit["hp"] = full_hp - 3
	var healed: Dictionary = campaign.use_item(id, "Vulnerary")
	_check(bool(healed["ok"]) and int(campaign.get_unit(id)["hp"]) == full_hp,
		"potion : soigne sans dépasser les PV max (%d/%d, +%d rendus sur %d)" % [
			int(campaign.get_unit(id)["hp"]), full_hp, int(healed.get("amount", 0)),
			int(ITEMS.get_item("Vulnerary").get("amount", 0))])
	_check(not "Vulnerary" in campaign.get_unit(id)["items"], "potion consommée du sac")
	_check(not bool(campaign.use_item(id, "Vulnerary")["ok"]),
		"objet absent du sac refusé")

	# À pleine santé la potion est refusée plutôt que gâchée.
	unit["items"].append("Vulnerary")
	var wasted: Dictionary = campaign.use_item(id, "Vulnerary")
	_check(not bool(wasted["ok"]) and "Vulnerary" in campaign.get_unit(id)["items"],
		"potion refusée (et gardée) à pleine santé")

	# Tonique : pas de tours entre deux chapitres, le bonus attend la bataille.
	var tonic: Dictionary = campaign.use_item(id, "Def Tonic")
	var pending: Array = campaign.get_unit(id).get("buffs", [])
	_check(bool(tonic["ok"]) and pending.size() == 1
			and str(pending[0]["stat"]) == "def" and int(pending[0]["turns"]) == 2,
		"tonique : bonus en réserve pour la prochaine bataille (%s)" % str(pending))
	_check(not "Def Tonic" in campaign.get_unit(id)["items"], "tonique consommé du sac")

	# La réserve se verse sur le pion à l'entrée en lice, et le sac se vide.
	var carrier: CharStats = CharStats.new()
	ChapterRunner.apply_roster_unit(carrier, campaign.get_unit(id))
	_check(carrier.def == int(campaign.get_unit(id)["def"]) + 2,
		"tonique versé sur le pion au déploiement (DÉF %d)" % carrier.def)
	_check(not campaign.get_unit(id).has("buffs"), "réserve de toniques vidée une fois versée")
	carrier.tick_buffs()
	carrier.tick_buffs()
	_check(carrier.def == int(campaign.get_unit(id)["def"]), "bonus expiré après ses 2 tours")
	carrier.free()

	# Gain permanent par la même porte : les PV max gagnés sont des PV gagnés.
	var hp_before: int = int(campaign.get_unit(id)["hp"])
	var max_before: int = int(campaign.get_unit(id)["max_hp"])
	var robed: Dictionary = campaign.use_item(id, "Seraph Robe")
	_check(bool(robed["ok"]) and int(campaign.get_unit(id)["max_hp"]) == max_before + 5
			and int(campaign.get_unit(id)["hp"]) == hp_before + 5,
		"robe séraphique : +5 PV max et courants (%d/%d)" % [
			int(campaign.get_unit(id)["hp"]), int(campaign.get_unit(id)["max_hp"])])

	# --- Le repos entre deux batailles ---
	# Il n'y a plus de soin payant : l'armée se repose toute seule, victoire ou
	# défaite. Faire payer tirait la difficulté dans le mauvais sens — l'or
	# manque justement quand la campagne va mal.
	campaign.gold = 1000
	var purse: int = campaign.gold
	campaign.apply_battle_result({"id": id, "hp": 2})
	_check(int(campaign.get_unit(id)["hp"]) == 2, "blessures conservées après la bataille")

	# Une unité tombée ne doit pas se relever pour autant.
	var fallen: Dictionary = {}
	for u: Dictionary in campaign.roster:
		if str(u.get("id", "")) != id:
			fallen = u
			break
	if not fallen.is_empty():
		fallen["alive"] = false
		fallen["hp"] = 0

	_check(campaign.rest_army() >= 1, "le repos soigne qui en a besoin")
	_check(int(campaign.get_unit(id)["hp"]) == int(campaign.get_unit(id)["max_hp"]),
		"l'unité blessée retrouve tous ses PV",
		"%d PV" % int(campaign.get_unit(id)["hp"]))
	_check(campaign.gold == purse, "et ce repos ne coûte rien")
	if not fallen.is_empty():
		_check(not bool(fallen.get("alive", true)) and int(fallen.get("hp", 1)) == 0,
			"la mort permanente reste permanente : personne ne se relève")
	_check(campaign.rest_army() == 0,
		"l'armée déjà d'aplomb, le repos n'a plus rien à soigner")

	# Le repos ne dépend plus d'un chapitre gagné : c'est la fin de bataille qui
	# l'appelle, dans les deux branches ([Main._on_chapter_finished]).
	campaign.apply_battle_result({"id": id, "hp": 4})
	campaign.complete_chapter([])
	_check(int(campaign.get_unit(id)["hp"]) == 4,
		"gagner un chapitre ne soigne pas de lui-même : c'est le repos qui le fait",
		"%d PV" % int(campaign.get_unit(id)["hp"]))
	campaign.rest_army()

	# --- L'apparence voyage avec l'unité ---
	# Sully et Cordelia entraient en bataille sous les traits du pion de la scène
	# qu'elles occupaient : leur `sprite` ne sortait jamais de leur fiche.
	var sully: Dictionary = campaign.unit_from_resource(
		"res://data/models/world/stats/hero/cavalier.tres")
	_check(not str(sully.get("sprite", "")).is_empty(),
		"une recrue emporte son apparence au roster", str(sully.get("sprite", "aucune")))

	# On applique une fiche d'archer sur un pion de seigneur : les deux figurines
	# diffèrent, donc le report se voit. (Sully, elle, partage la figurine du
	# seigneur — voir plus bas.)
	var virion: Dictionary = campaign.unit_from_resource(
		"res://data/models/world/stats/hero/archer.tres")
	var carried := CharStats.new()
	carried.import_stats(load("res://data/models/world/stats/hero/lord.tres"))
	var before_look: String = carried.sprite
	ChapterRunner.apply_roster_unit(carried, virion)
	_check(carried.sprite == str(virion["sprite"]) and carried.sprite != before_look,
		"et le roster la repose sur le pion (%s → %s)" % [
			before_look.get_file(), carried.sprite.get_file()])
	_check(carried.override_name == str(virion["name"]),
		"le nom suit l'apparence : le pion s'appelle %s" % carried.override_name)

	# Ce que le report ne peut pas régler : plusieurs classes se partagent la même
	# figurine, faute d'en avoir d'autres. Sully porte celle du seigneur, Cordelia
	# celle de la clerc. Ce test le constate pour que ça ne se découvre pas en jeu.
	var shared: Dictionary = {}
	for path: String in ["hero/lord", "hero/cleric", "hero/archer", "hero/great_knight",
			"hero/cavalier", "hero/pegasus_knight"]:
		var u: Dictionary = campaign.unit_from_resource(
			"res://data/models/world/stats/%s.tres" % path)
		var look: String = str(u.get("sprite", ""))
		shared[look] = shared.get(look, 0) + 1
	var distinct: int = shared.size()
	_check(distinct < 6,
		"figurines distinctes : %d pour 6 classes de héros — deux paires se ressemblent"
			% distinct)

	# --- Enrôler un personnage écrit par le joueur ---
	# L'éditeur savait créer et enregistrer, mais rien ne faisait entrer la
	# créature dans une campagne : `enlist_custom` existait sans appelant.
	var made := UnitDocument.from_class(CDB.Id.ARCHER)
	made.name = "Essai Recrue"
	var written: Dictionary = UnitLibrary.save(made)
	_check(bool(written["ok"]), "personnage d'essai écrit sur le disque",
		str(written.get("error", "")))

	var offered: Array = campaign.custom_recruits()
	var listed: bool = false
	for entry: Dictionary in offered:
		if str(entry["slug"]) == made.slug():
			listed = true
			_check(int(entry["cost"]) == campaign.CUSTOM_RECRUIT_COST,
				"il est proposé à son prix (%d or)" % int(entry["cost"]))
	_check(listed, "un personnage écrit est proposé à l'intendance",
		"%d proposition(s)" % offered.size())

	var purse_before: int = campaign.gold
	var enlisted: Dictionary = campaign.hire_custom(made.slug())
	_check(bool(enlisted["ok"]), "il s'enrôle", str(enlisted.get("reason", "")))
	_check(not campaign.get_unit(made.slug()).is_empty(),
		"et il est bien dans l'armée")
	_check(campaign.gold == purse_before - campaign.CUSTOM_RECRUIT_COST,
		"le prix est déduit (gratuit pour l'instant : %d or)" % campaign.CUSTOM_RECRUIT_COST)

	# Une fois enrôlé, il ne doit plus être proposé.
	var still_offered: bool = false
	for entry: Dictionary in campaign.custom_recruits():
		if str(entry["slug"]) == made.slug():
			still_offered = true
	_check(not still_offered, "il disparaît des propositions une fois dans l'armée")
	_check(not bool(campaign.hire_custom(made.slug())["ok"]),
		"et on ne peut pas l'enrôler deux fois")
	_check(not bool(campaign.hire_custom("personne_de_ce_nom")["ok"]),
		"un personnage inexistant se refuse proprement")
	UnitLibrary.delete_unit(made.slug())

	# Recrutement
	campaign.gold = 2000
	var recruits: Array = campaign.available_recruits()
	_check(recruits.size() >= 2, "unités recrutables proposées (%d)" % recruits.size())
	if recruits.is_empty():
		return
	var roster_before: int = campaign.roster.size()
	var hired: Dictionary = campaign.hire(str(recruits[0]["path"]))
	_check(bool(hired["ok"]) and campaign.roster.size() == roster_before + 1,
		"%s recruté pour %d or" % [str(recruits[0]["name"]), int(hired.get("cost", 0))])
	_check(not bool(campaign.hire(str(recruits[0]["path"]))["ok"]), "pas de recrutement en double")
	campaign.gold = 0
	if campaign.available_recruits().size() > 0:
		_check(not bool(campaign.hire(str(campaign.available_recruits()[0]["path"]))["ok"]),
			"recrutement refusé sans or")

	_test_weapons()
	_test_weapon_economy(campaign)
	_test_save_slots(campaign)
	_test_character_editor(campaign)


## Les boutons d'objet pressés pour de vrai, sur l'écran monté.
##
## Le joueur ne signalait pas une règle fausse mais des boutons qui « ne
## servaient à rien » : `Campaign.use_item()` pouvait être juste sans
## qu'aucun clic ne l'atteigne jamais. Les tests d'économie ci-dessus appellent
## la campagne directement et resteraient donc verts avec une interface morte.
## Celui-ci monte l'écran de préparation, presse, et regarde le roster bouger.
func _test_item_buttons() -> void:
	print("\n🖱  Test 12septies: boutons d'objet de l'intendance et des fiches")

	var campaign: Node = root.get_node_or_null("Campaign")
	if not campaign:
		_ko("Autoload Campaign", "introuvable")
		return

	campaign.new_game(DIFF.Level.NORMAL, true)
	campaign.gold = 5000
	var unit: Dictionary = campaign.available_units()[0]
	var id: String = str(unit["id"])

	var screen: Control = load("res://data/modules/menu/prep_screen.gd").new()
	screen.chapter = campaign.current_chapter()
	root.add_child(screen)
	await process_frame

	# --- Intendance : « Utiliser » et « Revendre » sur tout le catalogue ---
	# Ils ne valaient que pour les gains permanents et pour les armes : une potion
	# achetée ici ne pouvait ni se boire ni se revendre.
	unit["items"] = ["Vulnerary"]
	unit["hp"] = int(unit["max_hp"]) - 5
	screen._toggle_shop()
	await process_frame

	var slot: int = ITEMS.shop_stock().find("Vulnerary")
	var use: Button = _item_row_button(screen._shop_panel, slot, "Utiliser")
	_check(use != null, "l'intendance porte un bouton « Utiliser » sur la potion")
	if use:
		use.pressed.emit()
		await process_frame
		_check(int(campaign.get_unit(id)["hp"]) == int(campaign.get_unit(id)["max_hp"])
				and not "Vulnerary" in campaign.get_unit(id)["items"],
			"le presser soigne l'unité et vide le sac (%d/%d, sac %s)" % [
				int(campaign.get_unit(id)["hp"]), int(campaign.get_unit(id)["max_hp"]),
				str(campaign.get_unit(id)["items"])])

	unit["items"] = ["Vulnerary"]
	var purse: int = campaign.gold
	var sell: Button = _item_row_button(screen._shop_panel, slot, "Revendre")
	_check(sell != null, "et un bouton « Revendre »")
	if sell:
		sell.pressed.emit()
		await process_frame
		_check(campaign.gold == purse + ITEMS.resale_price("Vulnerary")
				and campaign.get_unit(id)["items"].is_empty(),
			"le presser rend l'objet contre la moitié de son prix (%d → %d or)" % [
				purse, campaign.gold])

	# --- Fiches : un bouton par objet du sac ---
	# C'est l'écran où l'on lit les PV : c'est donc là qu'on décide de faire boire
	# une potion, sans repasser par la boutique.
	screen._toggle_shop()
	unit["items"] = ["Vulnerary", "Def Tonic"]
	unit["hp"] = 1
	screen._toggle_detail()
	await process_frame

	var sheet_use: Button = _item_row_button(screen._detail_panel, 0, "Utiliser")
	_check(sheet_use != null, "la fiche porte un bouton « Utiliser » par objet du sac")
	if sheet_use:
		sheet_use.pressed.emit()
		await process_frame
		_check(int(campaign.get_unit(id)["hp"]) > 1
				and campaign.get_unit(id)["items"] == ["Def Tonic"],
			"le presser fait boire la potion (%d PV, sac %s)" % [
				int(campaign.get_unit(id)["hp"]), str(campaign.get_unit(id)["items"])])
		_check(screen._detail_message.contains("PV"),
			"et la fiche dit ce que ça a fait : « %s »" % screen._detail_message)

	# Le tonique reste, et son bouton sait le mettre en réserve pour la bataille.
	var tonic_use: Button = _item_row_button(screen._detail_panel, 0, "Utiliser")
	if tonic_use:
		tonic_use.pressed.emit()
		await process_frame
		_check(campaign.get_unit(id).get("buffs", []).size() == 1
				and campaign.get_unit(id)["items"].is_empty(),
			"le tonique passe en réserve depuis la fiche (%s)" % str(
				campaign.get_unit(id).get("buffs", [])))

	screen.queue_free()


## Le bouton d'intitulé [param text] de la [param index]-ième ligne d'objet.
##
## Une ligne d'objet est celle qui porte un « Utiliser » : à l'intendance elles
## suivent l'ordre de [method ItemDB.shop_stock] (les lignes d'arme et de recrue
## n'en ont pas), sur une fiche celui du sac.
func _item_row_button(panel: Node, index: int, text: String) -> Button:
	var rows: Array[Node] = []
	for node: Node in _walk(panel):
		if node is HBoxContainer and _row_button(node, "Utiliser"):
			rows.append(node)
	if index < 0 or index >= rows.size():
		return null
	return _row_button(rows[index], text)


## Le bouton d'intitulé [param text] porté directement par une ligne.
func _row_button(row: Node, text: String) -> Button:
	for child in row.get_children():
		if child is Button and (child as Button).text == text:
			return child
	return null


#region 12quater. Emplacements de sauvegarde
## Décrire un emplacement ne doit jamais coûter la partie en cours : c'est tout
## l'intérêt de relire l'en-tête du JSON au lieu de charger.
func _test_save_slots(campaign: Node) -> void:
	print("\n💾 Test 12quater: emplacements de sauvegarde")

	for slot: int in range(campaign.SAVE_SLOTS):
		campaign.delete_save(slot)

	campaign.new_game(DIFF.Level.BRUTAL, false)
	campaign.gold = 777
	campaign.chapter_index = 2
	_check(campaign.save_game(1), "écriture dans l'emplacement 2")

	var info: Dictionary = campaign.slot_info(1)
	_check(bool(info["exists"]) and int(info["gold"]) == 777,
		"emplacement décrit sans être chargé (%d or)" % int(info["gold"]))
	_check(int(info["chapter_index"]) == 2 and not str(info["chapter_title"]).is_empty(),
		"chapitre nommé : %s" % str(info["chapter_title"]))
	_check(int(info["difficulty"]) == DIFF.Level.BRUTAL and not bool(info["permadeath"]),
		"difficulté et mort permanente relues")
	_check(int(info["units"]) == campaign.roster.size(),
		"effectif compté (%d)" % int(info["units"]))
	_check(not str(info["saved_at"]).is_empty(), "date de sauvegarde renseignée")

	# Décrire ne charge pas : l'or courant doit être resté intact.
	campaign.gold = 5
	var _again: Dictionary = campaign.slot_info(1)
	_check(campaign.gold == 5, "décrire un emplacement ne recharge pas la partie")

	var empty: Dictionary = campaign.slot_info(3)
	_check(not bool(empty["exists"]) and int(empty["gold"]) == 0,
		"un emplacement vide se décrit sans mentir")

	var slots: Array = campaign.all_slots()
	_check(slots.size() == campaign.SAVE_SLOTS,
		"%d emplacements proposés" % slots.size())
	_check(bool(slots[campaign.AUTO_SLOT]["auto"]) and not bool(slots[1]["auto"]),
		"l'emplacement automatique est signalé comme tel")

	campaign.delete_save(1)
	_check(not campaign.slot_info(1)["exists"], "emplacement supprimé")

#endregion
	_test_chapter_map()
	_test_deployment_tiles(campaign)


#region 12bis. Armes — catalogue, fourreau, équipement
func _test_weapons() -> void:
	print("\n⚔ Test 12bis: catalogue d'armes et équipement")

	# --- Catalogue ---
	var malformed: String = ""
	for id: String in WEAPONS.all_weapons():
		var w: Dictionary = WEAPONS.get_weapon(id)
		for key: String in ["label", "type", "might", "range", "hit", "crit", "weight", "price"]:
			if not w.has(key):
				malformed = "%s manque %s" % [id, key]
		if int(w.get("price", 0)) <= 0 or int(w.get("range", 0)) < 1:
			malformed = "%s : prix ou portée invalide" % id
	_check(malformed.is_empty(), "catalogue bien formé (%d armes)" % WEAPONS.all_weapons().size(),
		malformed)
	_check(WEAPONS.resale_price("iron_sword") == WEAPONS.price("iron_sword") / 2,
		"revente d'une arme à moitié prix")
	_check(WEAPONS.canonical_id("Iron_Sword") == "iron_sword" and WEAPONS.canonical_id("bidule").is_empty(),
		"identifiants insensibles à la casse, inconnus rejetés")
	_check(WEAPONS.is_staff("heal_staff") and not WEAPONS.is_staff("iron_axe"),
		"le bâton est reconnu comme tel")
	_check(WEAPONS.describe("iron_bow").contains("portée 2 uniquement"),
		"la description d'un arc annonce qu'il ne sert pas au contact",
		WEAPONS.describe("iron_bow"))
	_check(WEAPONS.describe("javelin").contains("portée 1-2"),
		"le javelot annonce ses deux portées", WEAPONS.describe("javelin"))

	# --- Fourreau ---
	var chrom: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	_check(chrom.equipped_weapon == "rapier" and chrom.weapons.size() == 2,
		"la fiche de Chrom arrive rapière en main", chrom.equipped_weapon)
	_check(chrom.weapon_might == 5 and chrom.weapon_crit == 5 and chrom.weapon_hit == 10,
		"l'arme équipée impose puissance, précision et critique")
	_check(chrom.attack_power == chrom.str + 5, "la puissance d'attaque suit l'arme en main")

	var swap: Dictionary = chrom.equip("iron_sword")
	_check(bool(swap["ok"]) and chrom.equipped_weapon == "iron_sword" and chrom.weapon_crit == 0,
		"changer d'arme change les chiffres", str(swap))
	_check(not bool(chrom.equip("steel_axe")["ok"]), "on n'équipe pas une arme qu'on ne porte pas")
	_check(not bool(chrom.equip("bidule")["ok"]), "arme inconnue refusée")

	# Plafond du fourreau
	var mule: CharStats = _live("res://data/models/world/stats/hero/cleric.tres")
	mule.weapons = []
	mule.equipped_weapon = ""
	_check(mule.add_weapon("iron_sword") and mule.equipped_weapon == "iron_sword",
		"la première arme rangée est mise en main d'office")
	_check(not mule.add_weapon("iron_sword"), "pas deux fois la même arme")
	mule.add_weapon("iron_axe")
	mule.add_weapon("iron_lance")
	_check(not mule.add_weapon("fire") and mule.weapons.size() == WEAPONS.MAX_WEAPONS,
		"fourreau plafonné à %d armes" % WEAPONS.MAX_WEAPONS)

	# Reposer l'arme en main : la suivante prend le relais, puis les poings.
	_check(mule.drop_weapon("iron_sword") and mule.equipped_weapon == "iron_axe",
		"l'arme suivante prend le relais", mule.equipped_weapon)
	mule.drop_weapon("iron_axe")
	mule.drop_weapon("iron_lance")
	_check(mule.equipped_weapon.is_empty() and mule.weapon_might == 0
			and mule.weapon_type == WT.Type.NONE,
		"fourreau vidé : l'unité se retrouve à mains nues")
	_check(not mule.drop_weapon("iron_sword"), "on ne repose pas une arme absente")

	# --- Poids et vitesse d'attaque ---
	var brawn: CharStats = _live("res://data/models/world/stats/hero/great_knight.tres")
	var frail: CharStats = _live("res://data/models/world/stats/hero/cleric.tres")
	frail.weapons = []
	frail.equipped_weapon = ""
	frail.add_weapon("steel_axe")
	frail.equip("steel_axe")
	_check(brawn.speed_penalty() == 0,
		"un bras solide porte l'acier sans ralentir (FOR %d)" % brawn.str)
	_check(frail.speed_penalty() > 0 and frail.get_attack_speed() == frail.spd - frail.speed_penalty(),
		"une hache d'acier ralentit qui n'a pas les bras (−%d)" % frail.speed_penalty())

	# --- Portée : c'est l'arme qui la donne, et elle décide de la riposte ---
	var lancer: CharStats = _live("res://data/models/world/stats/hero/cavalier.tres")
	lancer.equip("javelin")
	_check(lancer.attack_range == 2, "le javelot porte à deux cases")
	var brig: CharStats = _live("res://data/models/world/stats/mob/skeleton.tres")
	var duel: Dictionary = Calc.calculate_exchange(lancer, brig, {"distance": 2})
	_check(not bool(duel["can_counter"]),
		"frappé au javelot, le porteur de hache ne rend rien", str(duel["counter_reason"]))
	lancer.equip("iron_lance")
	_check(lancer.attack_range == 1, "la lance de fer ramène l'unité au contact")

	# --- La fiche montre l'arme réellement tenue, en français ---
	var sheet: Dictionary = UnitSheet.build(lancer)
	_check(str(sheet["weapon"]) == "Lance de fer",
		"la fiche nomme l'arme en main", str(sheet["weapon"]))
	var bare: CharStats = _live("res://data/models/world/stats/mob/skeleton.tres")
	_check(str(UnitSheet.build(bare)["weapon"]) == "Hache",
		"sans arsenal, la fiche montre le type d'arme traduit",
		str(UnitSheet.build(bare)["weapon"]))


## L'armurerie : acheter, équiper, revendre, et que ça survive à la sauvegarde.
func _test_weapon_economy(campaign: Node) -> void:
	campaign.new_game(DIFF.Level.NORMAL, true)
	campaign.gold = 5000
	var id: String = str(campaign.roster[0]["id"])

	_check(campaign.get_unit(id).get("weapons", []).size() == 2
			and str(campaign.get_unit(id).get("weapon", "")) == "rapier",
		"le roster hérite du fourreau de la fiche")

	# Achat : débité, rangé, et mis en main si les mains étaient vides.
	var gold_before: int = campaign.gold
	var bought: Dictionary = campaign.buy_weapon(id, "killing_edge")
	_check(bool(bought["ok"]) and campaign.gold == gold_before - WEAPONS.price("killing_edge"),
		"arme achetée et débitée", str(bought))
	_check("killing_edge" in campaign.get_unit(id)["weapons"], "arme rangée au fourreau")
	_check(not bool(campaign.buy_weapon(id, "killing_edge")["ok"]), "pas deux fois la même arme")
	_check(not bool(campaign.buy_weapon(id, "iron_axe")["ok"]),
		"fourreau plein : achat refusé")

	# Équiper
	var equipped: Dictionary = campaign.equip_weapon(id, "killing_edge")
	_check(bool(equipped["ok"]) and str(campaign.get_unit(id)["weapon"]) == "killing_edge",
		"arme mise en main", str(equipped))
	_check(not bool(campaign.equip_weapon(id, "steel_axe")["ok"]),
		"on n'équipe pas une arme absente du fourreau")

	var listed: Array = campaign.unit_arsenal(id)
	var marked: int = 0
	for w: Dictionary in listed:
		if bool(w["equipped"]):
			marked += 1
	_check(listed.size() == 3 and marked == 1, "le menu voit 3 armes, une seule en main")

	# Revendre celle qui est en main : une autre la remplace, jamais les poings nus
	# tant qu'il reste quelque chose au fourreau.
	var gold_mid: int = campaign.gold
	var sold: Dictionary = campaign.sell_weapon(id, "killing_edge")
	_check(bool(sold["ok"]) and campaign.gold == gold_mid + WEAPONS.resale_price("killing_edge"),
		"revente créditée à moitié prix")
	_check(not str(campaign.get_unit(id)["weapon"]).is_empty(),
		"l'unité ne se retrouve pas désarmée sans le savoir",
		str(campaign.get_unit(id)["weapon"]))
	_check(not bool(campaign.sell_weapon(id, "steel_bow")["ok"]), "revente d'une arme absente refusée")

	# Tout revendre doit vraiment désarmer : sans le marqueur `uses_arsenal`, un
	# fourreau vide passait pour « fiche d'avant le catalogue » et le pion
	# repartait au combat avec l'arme de son `.tres` — l'or était gratuit.
	var stripped: Dictionary = campaign.get_unit(id)
	for w in stripped["weapons"].duplicate():
		campaign.sell_weapon(id, str(w))
	_check(campaign.get_unit(id)["weapons"].is_empty()
			and str(campaign.get_unit(id)["weapon"]).is_empty(),
		"fourreau vidé par la revente")
	_check(bool(campaign.get_unit(id).get("uses_arsenal", false)),
		"l'unité reste marquée comme gérée par le catalogue")

	var bare: CharStats = _live(str(campaign.get_unit(id)["source"]))
	var runner := ChapterRunner.new()
	runner._apply_arsenal(bare, campaign.get_unit(id))
	_check(bare.equipped_weapon.is_empty() and bare.weapon_might == 0
			and bare.weapon_type == WT.Type.NONE and bare.attack_range == 1,
		"tout revendre envoie vraiment l'unité au combat à mains nues",
		"arme : %s, puissance %d" % [bare.equipped_weapon, bare.weapon_might])

	# Une unité d'avant le catalogue, elle, garde les valeurs brutes de sa fiche.
	var legacy: CharStats = _live("res://data/models/world/stats/mob/skeleton.tres")
	var might_before: int = legacy.weapon_might
	runner._apply_arsenal(legacy, {"weapons": [], "weapon": ""})
	_check(legacy.weapon_might == might_before,
		"une fiche sans arsenal conserve son arme d'origine")
	runner.free()

	campaign.buy_weapon(id, "iron_sword")

	campaign.gold = 10
	_check(not bool(campaign.buy_weapon(id, "steel_bow")["ok"]), "achat refusé sans or")

	# --- Sauvegarde ---
	campaign.gold = 3000
	campaign.equip_weapon(id, "iron_sword")
	var expected: Array = campaign.get_unit(id)["weapons"].duplicate()
	_check(campaign.save_game(99), "partie sauvegardée")
	campaign.new_game(DIFF.Level.NORMAL, true)
	_check(campaign.load_game(99), "partie rechargée")
	_check(campaign.get_unit(id)["weapons"] == expected
			and str(campaign.get_unit(id)["weapon"]) == "iron_sword",
		"le fourreau et l'arme en main survivent à la sauvegarde",
		str(campaign.get_unit(id).get("weapons", [])))

	# Une arme disparue du catalogue ne doit pas ressusciter par le JSON : on
	# sauvegarde un fourreau trafiqué et on vérifie ce qui en revient.
	var tampered: Dictionary = campaign.get_unit(id)
	tampered["weapons"] = ["iron_sword", "arme_fantome"]
	tampered["weapon"] = "arme_fantome"
	campaign.save_game(99)
	campaign.load_game(99)
	var restored: Dictionary = campaign.get_unit(id)
	_check(restored["weapons"] == ["iron_sword"] and str(restored["weapon"]).is_empty(),
		"une arme inconnue de la sauvegarde est écartée", str(restored.get("weapons", [])))
	campaign.delete_save(99)
#endregion



#region 12quinquies. Personnages écrits par le joueur
## La fiche, sa validation, son rangement, et son entrée dans l'armée.
func _test_character_editor(campaign: Node) -> void:
	print("\n🧑 Test 12quinquies: éditeur de personnages")

	# Une fiche neuve part des bases de sa classe : elle doit être jouable telle
	# quelle, pas être une coquille à 0 partout.
	var doc: UnitDocument = UnitDocument.from_class(CDB.Id.ARCHER)
	_check(doc.validate().is_empty(), "une fiche neuve est valide",
		str(doc.validate()))
	_check(doc.max_hp > 0 and int(doc.stats["str"]) > 0,
		"elle hérite des bases de sa classe (PV %d, FOR %d)" % [
			doc.max_hp, int(doc.stats["str"])])
	_check(not doc.weapons.is_empty(), "et d'une arme que sa classe sait manier")

	# La validation dit non plutôt que de corriger en silence.
	doc.name = ""
	_check(not doc.validate().is_empty(), "un personnage sans nom est refusé")
	doc.name = "Aurèle le Bref"
	doc.stats["str"] = 300
	_check(not doc.validate().is_empty(), "une statistique hors bornes est refusée")
	doc.stats["str"] = 9
	_check(doc.validate().is_empty(), "corrigée, la fiche repasse")

	# Une classe ne manie pas n'importe quelle arme.
	var mage: UnitDocument = UnitDocument.from_class(CDB.Id.DARK_MAGE)
	mage.name = "Sombre"
	mage.weapons = ["iron_axe"]
	_check(not mage.validate().is_empty(),
		"une arme que la classe ignore est refusée", str(mage.validate()))

	# L'identifiant de fichier se déduit du nom, sans caractère hasardeux.
	doc.name = "Aurèle le Bref"
	_check(not doc.slug().is_empty() and not doc.slug().contains(" "),
		"identifiant de fichier dérivé du nom : %s" % doc.slug())

	# Aller-retour disque : ce qu'on relit doit valoir ce qu'on a écrit.
	UnitLibrary.delete_unit(doc.slug())
	var saved: Dictionary = UnitLibrary.save(doc)
	_check(bool(saved["ok"]), "fiche enregistrée", str(saved.get("error", "")))
	var back: UnitDocument = UnitLibrary.load_unit(doc.slug())
	_check(back != null and back.name == doc.name and back.class_id == doc.class_id,
		"fiche relue à l'identique")
	_check(back != null and int(back.stats["str"]) == 9, "ses statistiques survivent")

	var listed: Array = UnitLibrary.list_units()
	var found: bool = false
	for entry: Dictionary in listed:
		if str(entry["slug"]) == doc.slug():
			found = true
	_check(found, "elle apparaît dans la bibliothèque (%d fiche(s))" % listed.size())

	# Une fiche invalide n'est pas enregistrée : le dire à l'écriture vaut mieux
	# qu'au moment où le personnage entre en bataille.
	var broken: UnitDocument = UnitDocument.from_class(CDB.Id.LORD)
	broken.name = ""
	_check(not bool(UnitLibrary.save(broken)["ok"]), "une fiche invalide est refusée")

	# Entrée dans l'armée.
	campaign.new_game(DIFF.Level.NORMAL, true)
	var before: int = campaign.roster.size()
	var enlisted: Dictionary = campaign.enlist_custom(doc)
	_check(bool(enlisted["ok"]) and campaign.roster.size() == before + 1,
		"le personnage rejoint l'armée", str(enlisted))
	_check(not bool(campaign.enlist_custom(doc)["ok"]),
		"mais pas deux fois")

	var unit: Dictionary = campaign.get_unit(doc.slug())
	_check(bool(unit.get("custom", false)) and str(unit.get("source", "x")).is_empty(),
		"il est marqué comme écrit à la main, sans .tres derrière lui")
	_check(int(unit.get("attack_range", 0)) == 2,
		"sa portée suit l'arme en main (arc : %d)" % int(unit.get("attack_range", 0)))

	# Il doit survivre à la sauvegarde comme les autres.
	_check(campaign.save_game(97) and campaign.load_game(97),
		"partie sauvegardée et relue")
	_check(not campaign.get_unit(doc.slug()).is_empty(),
		"le personnage écrit à la main survit à la sauvegarde")
	campaign.delete_save(97)
	UnitLibrary.delete_unit(doc.slug())
	_check(UnitLibrary.load_unit(doc.slug()) == null, "fiche supprimée")
#endregion

#region 12ter. Lecture de carte et choix du terrain en préparation
func _test_chapter_map() -> void:
	print("\n🗺 Test 12ter: lecture de la carte d'un chapitre")

	var chapter: ChapterData = CAMPAIGN_DB.get_chapter(0)
	var map: Dictionary = CMAP.read(chapter)
	_check(bool(map["ok"]), "carte du chapitre 1 lue sans monter la bataille",
		str(map.get("reason", "")))
	if not bool(map["ok"]):
		return

	_check(map["grid_size"] == Vector2i(16, 10), "grille de la carte (%s)" % str(map["grid_size"]))
	_check(map["terrain"].size() == 16 * 10, "terrain complet (%d cases)" % map["terrain"].size())

	# Le piège qui a coûté une réécriture : hors de l'arbre, `global_position`
	# rend l'identité, et les quatre pions de départ tombaient sur la même case.
	_check(map["starts"].size() >= 3,
		"les unités de départ occupent des cases distinctes (%d)" % map["starts"].size(),
		str(map["starts"]))

	# Aucune case ouverte ne doit être infranchissable : on ne déploie pas dans un lac.
	var walkable: bool = true
	var forest_slots: int = 0
	for pos: Vector2i in map["slots"]:
		if not MAP_DATA.is_walkable(CMAP.terrain_at(map, pos)):
			walkable = false
		if CMAP.defense_at(map, pos) > 0:
			forest_slots += 1
	_check(walkable, "toutes les cases ouvertes sont praticables (%d)" % map["slots"].size())
	_check(forest_slots > 0,
		"la zone contient des cases défensives — il y a donc un choix à faire (%d)" % forest_slots)

	# Le bonus lu ici doit être celui que le combat appliquera.
	var forest: int = MAP_DATA.get_defense_bonus(MAP_DATA.TerrainType.FOREST)
	var found: bool = false
	for pos: Vector2i in map["slots"]:
		if CMAP.terrain_at(map, pos) == MAP_DATA.TerrainType.FOREST:
			found = CMAP.defense_at(map, pos) == forest
			break
	_check(found, "le bonus annoncé est celui du calculateur (+%d en forêt)" % forest)

	# Les cases annoncées à Ciel doivent respecter le plancher de portée : sans
	# quoi il croirait pouvoir tirer au contact avec un arc.
	var reach_bow: Array = TacticsGrid.tiles_in_range(null, Vector2i(5, 5), 2, 2)
	var touches_neighbour: bool = false
	for cell: Dictionary in reach_bow:
		if absi(int(cell["col"]) - 5) + absi(int(cell["row"]) - 5) < 2:
			touches_neighbour = true
	_check(not touches_neighbour and not reach_bow.is_empty(),
		"portée d'arc exportée sans les cases adjacentes (%d cases)" % reach_bow.size())
	var reach_sword: Array = TacticsGrid.tiles_in_range(null, Vector2i(5, 5), 1, 1)
	_check(reach_sword.size() == 4, "portée de lame : les quatre voisines")

	# Hors bornes : la lecture ne doit pas exploser, juste répondre platement.
	_check(CMAP.defense_at(map, Vector2i(-5, -5)) == 0
			and CMAP.defense_at(map, Vector2i(999, 999)) == 0,
		"une case hors carte ne rapporte rien plutôt que de faire dérailler la lecture")

	# --- Le chapitre 2 : une carte d'un seul tenant ---
	# Son relief coupait la bataille en morceaux, chaque camp coincé de son côté
	# (remonté par Aurèle le 2026-08-06). Sa carte est désormais décrite par un
	# [MapData] : ces vérifications empêchent qu'un mur ou une marche la
	# recoupent sans qu'on s'en aperçoive.
	var chapter2: ChapterData = CAMPAIGN_DB.get_chapter(1)
	var outpost: Dictionary = CMAP.read(chapter2)
	_check(bool(outpost["ok"]),
		"la carte du chapitre 2 se lit avant la bataille", str(outpost["reason"]))
	_check(outpost["grid_size"] == Vector2i(10, 20),
		"chapitre 2 : une grille de 10 × 20", str(outpost["grid_size"]))

	var passable: Dictionary = CMAP.walkable_cells(outpost)
	_check(passable.size() < 200 and passable.size() > 140,
		"chapitre 2 : de l'infranchissable, mais pas au point d'étouffer la carte",
		"%d cases praticables sur 200" % passable.size())

	# Le saut le plus faible du jeu vaut 2 (`jump = floor(mouvement / 2)`) : c'est
	# à cette tolérance-là que la carte doit tenir d'un seul tenant. Un rempart
	# tiré en travers la couperait aussi, la praticabilité comptant avant le
	# relief.
	_check(CMAP.walkable_zones(outpost, 2.0) == 1,
		"chapitre 2 : une seule zone, les deux camps peuvent se rejoindre",
		"%d zones" % CMAP.walkable_zones(outpost, 2.0))

	# La marche la plus haute doit rester loin sous ce saut. Compter les zones
	# ne le dirait pas : une falaise franchissable de justesse passerait, jusqu'au
	# jour où une unité plus lourde s'y présenterait.
	# Depuis le 2026-08-12 la montagne est franchissable (coût 2) : ses marches
	# peuvent dépasser 0.5 sans couper la carte — c'est le saut qui décide, et
	# la vérification « une seule zone » au-dessus le garantit déjà.
	var steepest: float = 0.0
	for cell: Vector2i in passable:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if passable.has(cell + step):
				steepest = maxf(steepest,
					absf(float(passable[cell + step]) - float(passable[cell])))
	_check(steepest > 0.0 and steepest <= 1.0,
		"chapitre 2 : du relief, et aucune marche hors de portée du saut (marche la plus haute : %.2f)"
			% steepest)

	# Les terrains ne servent à rien si personne ne les distingue : une carte
	# entièrement en herbe repasserait toutes les vérifications ci-dessus.
	var kinds: Dictionary = {}
	for value: Variant in outpost["terrain"]:
		kinds[int(value)] = true
	_check(kinds.size() >= 5,
		"chapitre 2 : la carte parle plusieurs terrains", "%d types" % kinds.size())
	_check(kinds.has(MAP_DATA.TerrainType.FOREST) and kinds.has(MAP_DATA.TerrainType.WALL),
		"chapitre 2 : un bois où s'abriter, un rempart à contourner")

	# Le poste avancé se voit : sa porte, ses tours, sa brèche jonchée de pierres,
	# et les hameaux que Garrick est venu piller. Sans quoi « ruines du poste
	# avancé » ne serait qu'un sous-titre.
	var outpost_kinds: Array[int] = [
		MAP_DATA.TerrainType.GATE, MAP_DATA.TerrainType.TOWER,
		MAP_DATA.TerrainType.RUINS, MAP_DATA.TerrainType.VILLAGE,
		MAP_DATA.TerrainType.FORT, MAP_DATA.TerrainType.SWAMP,
	]
	var missing: Array[String] = []
	for kind: int in outpost_kinds:
		if not kinds.has(kind):
			missing.append(MAP_DATA.type_label(kind))
	_check(missing.is_empty(),
		"chapitre 2 : porte, tours, brèche, hameaux, redoute et roselière sont là",
		"manque : %s" % ", ".join(missing))

	# Les pions de la carte doivent tenir debout là où la scène les pose : sur du
	# praticable, et de plain-pied — un pion posé à zéro sur une case surélevée
	# tomberait à travers son plateau.
	var starts: Array = outpost["starts"]
	_check(starts.size() == 4, "chapitre 2 : quatre pions du joueur en place",
		"%d" % starts.size())
	var footing: bool = not starts.is_empty()
	for cell: Vector2i in starts:
		if not MAP_DATA.is_walkable(CMAP.terrain_at(outpost, cell)) \
				or not is_zero_approx(CMAP.height_at(outpost, cell)):
			footing = false
	_check(footing, "chapitre 2 : chaque départ est praticable et de plain-pied")

	_check(outpost["slots"].size() >= chapter2.deploy_slots,
		"chapitre 2 : assez de cases ouvertes pour les %d places" % chapter2.deploy_slots,
		"%d cases" % outpost["slots"].size())

	# Le côté de case déduit d'une carte posée à la main. Les abscisses ci-dessous
	# sont celles du chapitre 2 : un écart de 0,996 au lieu de 1,0, invisible à
	# l'œil. Retenu comme côté de case, il décalait le calcul des coordonnées
	# jusqu'à faire sauter une colonne entière — 160 cases indexées pour 200
	# tuiles, et un plateau percé en son milieu.
	var crooked: Array[float] = [-4.504, -3.508, -2.508, -1.508, -0.508,
		0.492, 1.492, 2.492, 3.492, 4.496]
	_check(is_equal_approx(BattleGrid.tile_size_from_columns(crooked), 1.0),
		"une colonne de travers ne fausse plus le côté de case",
		str(BattleGrid.tile_size_from_columns(crooked)))

	var regular: Array[float] = [-1.5, -0.5, 0.5, 1.5]
	_check(is_equal_approx(BattleGrid.tile_size_from_columns(regular), 1.0),
		"une trame régulière donne son pas")
	var wide: Array[float] = [0.0, 2.0, 4.0, 6.0]
	_check(is_equal_approx(BattleGrid.tile_size_from_columns(wide), 2.0),
		"une carte à grandes cases est reconnue comme telle")
	var lonely: Array[float] = [3.0]
	_check(is_equal_approx(BattleGrid.tile_size_from_columns(lonely), 1.0),
		"une seule colonne : on retombe sur 1")

	# Le compteur de zones doit savoir compter : une case isolée par une falaise.
	var split: Dictionary = {
		Vector2i(0, 0): 0.0, Vector2i(1, 0): 0.0,
		Vector2i(2, 0): 9.0, Vector2i(3, 0): 9.0,
	}
	_check(CMAP.zone_count(split, 2.0) == 2 and CMAP.zone_count(split, 9.0) == 1,
		"une falaise sépare bien deux zones, un saut suffisant les réunit")

	# Une carte sans terrain déclaré doit le dire, pas se taire. `test_level.tscn`
	# est restée dans le dépôt exactement pour ça : c'est la dernière arène posée
	# tuile par tuile, donc le seul cas d'essai honnête pour cette lecture-là.
	var sculpted := ChapterData.new()
	sculpted.scene_path = "res://assets/maps/level/test_level.tscn"
	var handmade: Dictionary = CMAP.read(sculpted)
	_check(not bool(handmade["ok"]) and not str(handmade["reason"]).is_empty(),
		"une carte écrite à la main annonce qu'elle ne se lit pas d'avance",
		str(handmade["reason"]))

	# Elle reste aussi le cas d'essai de la lecture tuile par tuile, qui n'a plus
	# de chapitre à qui s'appliquer mais sert encore à toute carte sculptée.
	var sculpted_tiles: Dictionary = CMAP.scene_tiles(sculpted.scene_path)
	_check(sculpted_tiles.size() == 200,
		"une arène sculptée se lit tuile par tuile (%d cases)" % sculpted_tiles.size())
	_check(CMAP.zone_count(sculpted_tiles, 0.0) == 1,
		"arène sculptée : un seul tenant")
	_check(not CMAP.read(null)["ok"], "aucun chapitre : lecture refusée proprement")


func _test_deployment_tiles(campaign: Node) -> void:
	campaign.new_game(DIFF.Level.NORMAL, true)
	var ids: Array = campaign.deployment.duplicate()
	if ids.size() < 2:
		_ko("Cases de départ", "pas assez d'unités déployées")
		return
	var first: String = str(ids[0])
	var second: String = str(ids[1])

	_check(campaign.deployment_tile(first) == Vector2i(-1, -1),
		"aucune case choisie au départ")

	campaign.set_deployment_tile(first, Vector2i(5, 2))
	_check(campaign.deployment_tile(first) == Vector2i(5, 2), "case retenue pour l'unité")

	# Deux unités sur la même case échangent, comme au déploiement en jeu.
	campaign.set_deployment_tile(second, Vector2i(7, 3))
	campaign.set_deployment_tile(second, Vector2i(5, 2))
	_check(campaign.deployment_tile(second) == Vector2i(5, 2)
			and campaign.deployment_tile(first) == Vector2i(7, 3),
		"poser sur une case prise fait échanger les deux unités",
		"%s / %s" % [campaign.deployment_tile(first), campaign.deployment_tile(second)])

	# Une unité qui n'était pas encore posée chasse l'occupante au lieu d'échanger.
	var third: String = str(ids[2]) if ids.size() > 2 else ""
	if not third.is_empty():
		campaign.set_deployment_tile(third, Vector2i(5, 2))
		_check(campaign.deployment_tile(third) == Vector2i(5, 2)
				and campaign.deployment_tile(second) == Vector2i(-1, -1),
			"l'unité délogée par une nouvelle venue perd sa case")
		campaign.set_deployment_tile(second, Vector2i(9, 4))

	# Sauvegarde : le JSON ne connaît pas Vector2i.
	var expected: Vector2i = campaign.deployment_tile(first)
	_check(campaign.save_game(98), "partie sauvegardée avec ses positions")
	campaign.new_game(DIFF.Level.NORMAL, true)
	_check(campaign.deployment_tiles.is_empty(), "une nouvelle partie repart sans positions")
	_check(campaign.load_game(98), "partie rechargée")
	_check(campaign.deployment_tile(first) == expected,
		"les cases de départ survivent à la sauvegarde (%s)" % campaign.deployment_tile(first))

	# Une entrée corrompue est écartée au chargement, pas propagée : on trafique
	# le fichier lui-même plutôt que d'appeler la conversion en douce.
	var corrupt := FileAccess.open(campaign.save_path(98), FileAccess.WRITE)
	corrupt.store_string(JSON.stringify({
		"version": campaign.SAVE_VERSION,
		"chapter_index": 0, "gold": 0, "difficulty": DIFF.Level.NORMAL,
		"permadeath": true, "deployment": [first, second], "roster": campaign.roster,
		"deployment_tiles": {first: [3, 4], second: "pas une case", "vide": [1]},
	}, "\t"))
	corrupt.close()
	_check(campaign.load_game(98), "sauvegarde aux positions douteuses tout de même lue")
	_check(campaign.deployment_tile(first) == Vector2i(3, 4)
			and campaign.deployment_tile(second) == Vector2i(-1, -1)
			and campaign.deployment_tile("vide") == Vector2i(-1, -1),
		"les positions mal formées sont écartées au chargement",
		str(campaign.deployment_tiles))
	campaign.save_game(98)

	# Écarter une unité du déploiement doit lui retirer sa case.
	campaign.load_game(98)
	campaign.set_deployment([second])
	_check(campaign.deployment_tile(first) == Vector2i(-1, -1),
		"une unité retirée du déploiement perd sa case")

	# Changer de chapitre remet les positions à zéro : elles parlaient d'une
	# carte qu'on ne joue plus.
	campaign.set_deployment_tile(second, Vector2i(6, 6))
	campaign.complete_chapter([])
	_check(campaign.deployment_tiles.is_empty(),
		"le chapitre suivant repart sans positions héritées")
	campaign.delete_save(98)
#endregion


#region 13. Codes d'accès réseau
func _test_network_codes() -> void:
	print("\n🌐 Test 13: codes d'accès (M3/M4)")

	var net: Node = root.get_node_or_null("Network")
	if not net:
		_ko("Autoload Network", "introuvable")
		return
	_ok("Autoload Network disponible")

	# Aller-retour sur des adresses typiques d'un réseau domestique
	for ip: String in ["192.168.1.42", "10.0.0.1", "127.0.0.1", "172.20.10.3", "255.255.255.255"]:
		var code: String = net.encode_code(ip)
		_check(code.length() == net.CODE_LENGTH and net.decode_code(code) == ip,
			"%s ↔ %s" % [ip, code], "décodé : %s" % net.decode_code(code))

	# Plusieurs écritures d'un même chemin : sept caractères de cinq bits font 35
	# bits pour 32 bits d'adresse, et les trois qui restent servent à présenter un
	# code d'allure neuve. Toutes doivent mener au même hôte.
	var host_ip: String = "192.168.1.42"
	var seen_codes: Array[String] = []
	var all_decode: bool = true
	for variant: int in range(net.CODE_VARIANTS):
		var code: String = net.encode_code(host_ip, variant)
		if net.decode_code(code) != host_ip or code.length() != net.CODE_LENGTH:
			all_decode = false
		if not code in seen_codes:
			seen_codes.append(code)
	_check(seen_codes.size() == net.CODE_VARIANTS,
		"%d écritures distinctes du même code" % seen_codes.size())
	_check(all_decode, "toutes mènent à la même machine")
	_check(net.encode_code(host_ip, net.CODE_VARIANTS) == net.encode_code(host_ip, 0),
		"le compteur d'écritures boucle")
	_check(net.encode_code(host_ip, -1) == net.encode_code(host_ip, net.CODE_VARIANTS - 1),
		"un compteur négatif ne casse pas le code")

	# Le code est lisible à l'oral : ni I, ni O, ni 0, ni 1
	var sample: String = net.encode_code("192.168.1.42")
	var ambiguous: bool = sample.contains("I") or sample.contains("O") \
		or sample.contains("0") or sample.contains("1")
	_check(not ambiguous, "alphabet sans caractères ambigus (%s)" % sample)

	# Saisie tolérante
	_check(net.decode_code(sample.to_lower()) == "192.168.1.42", "minuscules acceptées")
	_check(net.decode_code(" " + sample + " ") == "192.168.1.42", "espaces ignorés")

	# Codes invalides
	_check(net.decode_code("TROPCOURT") == "", "code de mauvaise longueur refusé")
	_check(net.decode_code("AAAAAA!") == "", "caractère hors alphabet refusé")
	_check(net.encode_code("pas.une.ip") == "", "adresse invalide refusée")
	_check(net.encode_code("192.168.1.999") == "", "octet hors bornes refusé")

	# État initial
	_check(not net.is_online() and net.is_authority(),
		"hors ligne : cette instance fait autorité par défaut")
	_check(net.local_side() == TeamData.Side.PLAYER, "camp local par défaut : joueur 1")
#endregion


#region 14. Trois camps (M5)
func _test_three_way() -> void:
	print("\n⚑ Test 14: trois camps dans une même bataille (M5)")

	# --- Partage d'armée : déterministe, sinon les deux machines divergent ---
	var half: Array[int] = SPLIT.guest_indices(6)
	_check(half == [1, 3, 5], "6 pions → moitié alternée %s" % str(half))
	_check(SPLIT.guest_indices(6) == half, "partage reproductible d'un appel à l'autre")
	_check(SPLIT.guest_indices(1).is_empty(), "armée d'un seul pion : pas de partage")
	_check(SPLIT.guest_indices(0).is_empty(), "armée vide : pas de partage")

	var lopsided: Array[int] = SPLIT.guest_indices(5, 1.0)
	_check(lopsided.size() == 4, "part de 100 %% : le camp d'origine garde un pion (%s)" % str(lopsided))
	_check(SPLIT.guest_indices(4, 0.0).is_empty(), "part nulle : aucun pion cédé")
	for count: int in [2, 3, 5, 8, 13]:
		var picked: Array[int] = SPLIT.guest_indices(count)
		var valid: bool = picked.size() < count
		for i: int in picked:
			if i < 0 or i >= count:
				valid = false
		_check(valid, "%d pions → indices valides et camp d'origine non vidé" % count)

	# --- Camps et étiquettes ---
	var guest_node: Node = _named_node("TacticsGuest")
	var stray_node: Node = _named_node("Autre")
	_check(TeamData.side_for_camp_node(guest_node) == TeamData.Side.GUEST,
		"nœud TacticsGuest → camp invité")
	_check(TeamData.camp_node_name(TeamData.Side.GUEST) == "TacticsGuest",
		"camp invité → nœud TacticsGuest")
	_check(TeamData.state_team_name(TeamData.Side.GUEST) == "guest",
		"étiquette d'équipe exportée à Ciel")
	_check(TeamData.side_for_camp_node(stray_node) == -1,
		"nœud inconnu → aucun camp")
	guest_node.free()
	stray_node.free()

	# --- Session à trois camps ---
	var session: Node = root.get_node_or_null("GameSession")
	if not session:
		_ko("Autoload GameSession", "introuvable")
		return

	session.set_mode(session.Mode.NETWORK)
	session.set_three_way(true)
	_check(session.battle_sides() == [TeamData.Side.PLAYER, TeamData.Side.GUEST, TeamData.Side.OPPONENT],
		"ordre de jeu : joueur, invité, Ciel")
	_check(session.controller_for(TeamData.Side.OPPONENT) == TeamData.Controller.CIEL_AI,
		"le camp rouge revient à Ciel")
	_check(session.controller_for(TeamData.Side.GUEST) == TeamData.Controller.REMOTE_PLAYER,
		"le troisième camp revient à l'invité distant")
	_check(session.hostiles_of(TeamData.Side.PLAYER).size() == 2,
		"chacun pour soi : le joueur a deux camps ennemis")
	_check(session.hostiles_of(TeamData.Side.GUEST).has(TeamData.Side.OPPONENT)
		and session.hostiles_of(TeamData.Side.GUEST).has(TeamData.Side.PLAYER),
		"l'invité affronte Ciel et le joueur")
	_check(not session.hostiles_of(TeamData.Side.GUEST).has(TeamData.Side.GUEST),
		"personne n'est son propre ennemi")

	var net: Node = root.get_node_or_null("Network")
	if net:
		net.three_way = true
		_check(net.guest_side() == TeamData.Side.GUEST, "réseau : l'invité prend le troisième camp")
		net.three_way = false
		_check(net.guest_side() == TeamData.Side.OPPONENT, "à deux camps, l'invité garde le camp rouge")

	# --- Validation des ordres : le pont sert le camp qui joue ---
	var guest_ctx: Dictionary = {"stage": 0, "turn": "guest", "acting_team": "guest"}
	var ok_cmd: Dictionary = CMD.validate({"action": "select_pawn", "name": "Brigand"}, guest_ctx)
	_check(bool(ok_cmd["ok"]), "ordre de l'invité accepté pendant son tour",
		str(ok_cmd.get("error", "")))

	var wrong_turn: Dictionary = CMD.validate({"action": "select_pawn", "name": "Brigand"},
		{"stage": 0, "turn": "opponent", "acting_team": "guest"})
	_check(not bool(wrong_turn["ok"]) and int(wrong_turn["code"]) == CMD.Err.OUT_OF_TURN,
		"ordre de l'invité refusé pendant le tour de Ciel")

	var ciel_default: Dictionary = CMD.validate({"action": "select_pawn", "name": "Brigand"},
		{"stage": 0, "turn": "guest"})
	_check(not bool(ciel_default["ok"]) and int(ciel_default["code"]) == CMD.Err.OUT_OF_TURN,
		"sans camp précisé, le contrat reste celui de Ciel (« opponent »)")

	# --- Retour à deux camps : rien ne doit rester du troisième ---
	session.set_three_way(false)
	_check(session.battle_sides() == [TeamData.Side.PLAYER, TeamData.Side.OPPONENT],
		"retour à deux camps")
	_check(session.get_team(TeamData.Side.GUEST) == null, "le camp invité a bien disparu")
	_check(session.hostiles_of(TeamData.Side.PLAYER) == [TeamData.Side.OPPONENT],
		"à deux camps, un seul ennemi")
	session.set_mode(session.Mode.SOLO)


## Petit nœud nommé, pour tester la correspondance nom ↔ camp sans scène.
func _named_node(node_name: String) -> Node:
	var n := Node.new()
	n.name = node_name
	return n
#endregion


#region 15. Reconnexion en cours de partie
## L'horloge est injectée : la règle se vérifie sans attendre 90 secondes.
func _test_reconnection() -> void:
	print("\n🔌 Test 15: reconnexion en cours de partie")

	# --- Côté hôte : la place gardée ---
	var seats := SeatRegistry.new()
	var t0: float = 1000.0
	_check(seats.is_empty() and not seats.has_seat(TeamData.Side.GUEST),
		"aucune place gardée au départ")

	seats.reserve(TeamData.Side.GUEST, t0, 90.0, TeamData.Controller.REMOTE_PLAYER)
	_check(seats.has_seat(TeamData.Side.GUEST), "place gardée après une coupure")
	_check(is_equal_approx(seats.remaining(TeamData.Side.GUEST, t0 + 30.0), 60.0),
		"décompte du délai de grâce", str(seats.remaining(TeamData.Side.GUEST, t0 + 30.0)))
	_check(seats.remaining(TeamData.Side.PLAYER, t0) == 0.0,
		"un camp sans réservation n'a rien à décompter")
	_check(seats.take_expired(t0 + 30.0) == -1, "rien n'expire avant la fin du délai")

	# Retour dans les temps : le contrôleur d'origine est rendu tel quel.
	var restored: int = seats.claim(TeamData.Side.GUEST, t0 + 30.0)
	_check(restored == TeamData.Controller.REMOTE_PLAYER,
		"retour dans les temps : l'invité récupère son camp", str(restored))
	_check(seats.is_empty(), "la place est libérée une fois reprise")
	_check(seats.claim(TeamData.Side.GUEST, t0 + 31.0) == -1,
		"une place déjà reprise ne se reprend pas deux fois")

	# Retour trop tard : la place est perdue, signalée une seule fois.
	seats.reserve(TeamData.Side.GUEST, t0, 90.0, TeamData.Controller.REMOTE_PLAYER)
	_check(seats.claim(TeamData.Side.GUEST, t0 + 91.0) == -1,
		"retour hors délai : la place n'est plus rendue")
	_check(seats.take_expired(t0 + 91.0) == TeamData.Side.GUEST,
		"la place échue est signalée")
	_check(seats.take_expired(t0 + 91.0) == -1, "une expiration n'est signalée qu'une fois")

	# --- Côté invité : le plan de reconnexion ---
	var plan := ReconnectPlan.new()
	_check(not plan.is_active(), "aucune reconnexion en cours au départ")

	plan.start("ABCDEFG", t0, 90.0, 3.0)
	_check(plan.is_active() and plan.code == "ABCDEFG", "le code d'accès est conservé pour revenir")
	_check(plan.consume_attempt(t0), "première tentative immédiate")
	_check(plan.attempt == 1, "tentative comptée", str(plan.attempt))
	_check(not plan.consume_attempt(t0 + 1.0), "pas de tentative avant l'intervalle")
	_check(plan.consume_attempt(t0 + 3.0), "tentative suivante après l'intervalle")
	_check(is_equal_approx(plan.remaining(t0 + 30.0), 60.0), "décompte du délai de retour")

	_check(not plan.is_expired(t0 + 89.0), "toujours dans les temps")
	_check(plan.is_expired(t0 + 90.0), "délai de retour écoulé")
	_check(not plan.consume_attempt(t0 + 95.0), "plus aucune tentative après le délai")

	plan.cancel()
	_check(not plan.is_active() and plan.attempt == 0, "abandon : le plan est vidé")

	# --- Autoload : l'état par défaut ne doit rien réserver ---
	var net: Node = root.get_node_or_null("Network")
	if net:
		_check(not net.is_reconnecting(), "réseau au repos : aucune reconnexion")
		_check(net.reserved_seats().is_empty(), "réseau au repos : aucune place gardée")
		_check(not net.in_battle, "réseau au repos : aucune bataille en cours")
#endregion


#region 16. Cases de déploiement
func _test_deployment() -> void:
	print("\n🪧 Test 16: choix des cases de déploiement")

	var plan := DeploymentPlan.new()
	plan.configure([Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(3, 2)])
	_check(plan.slots.size() == 3, "cases dédoublonnées (%d)" % plan.slots.size())
	_check(plan.is_slot(Vector2i(4, 2)) and not plan.is_slot(Vector2i(9, 9)),
		"une case hors zone reste fermée")

	# Pose simple
	_check(bool(plan.place("Lord", Vector2i(3, 2))["ok"]), "une unité se pose sur une case ouverte")
	_check(plan.position_of("Lord") == Vector2i(3, 2), "la position est retenue")
	_check(plan.occupant(Vector2i(3, 2)) == "Lord", "la case connaît son occupante")
	_check(plan.free_slots().size() == 2, "les cases libres se comptent")

	var closed: Dictionary = plan.place("Lord", Vector2i(9, 9))
	_check(not bool(closed["ok"]) and plan.position_of("Lord") == Vector2i(3, 2),
		"case fermée refusée, sans déplacer l'unité")

	# Déplacement vers une case libre
	plan.place("Lord", Vector2i(5, 2))
	_check(plan.position_of("Lord") == Vector2i(5, 2) and plan.occupant(Vector2i(3, 2)).is_empty(),
		"l'ancienne case est libérée")

	# Échange : le geste courant quand on réarrange la ligne de départ
	plan.place("Cleric", Vector2i(4, 2))
	var swap: Dictionary = plan.place("Cleric", Vector2i(5, 2))
	_check(str(swap["swapped"]) == "Lord", "poser sur une case prise échange les deux unités")
	_check(plan.position_of("Cleric") == Vector2i(5, 2)
			and plan.position_of("Lord") == Vector2i(4, 2),
		"les deux unités ont bien permuté")
	_check(plan.placed_count() == 2, "aucune unité perdue dans l'échange")

	plan.place("Cleric", Vector2i(5, 2))
	_check(plan.position_of("Cleric") == Vector2i(5, 2), "reposer une unité sur sa case ne change rien")

	plan.remove("Cleric")
	_check(plan.position_of("Cleric").x == -1 and plan.occupant(Vector2i(5, 2)).is_empty(),
		"une unité retirée libère sa case")

	# Zone par défaut : le voisinage de la ligne de départ, dans les bornes
	var slots: Array[Vector2i] = DeploymentPlan.default_slots(
		[Vector2i(0, 0), Vector2i(1, 0)], Vector2i(16, 10), 1)
	_check(slots.has(Vector2i(0, 0)) and slots.has(Vector2i(1, 1)),
		"la zone par défaut couvre le voisinage")
	_check(not slots.has(Vector2i(-1, 0)) and not slots.has(Vector2i(0, -1)),
		"la zone par défaut reste dans la grille")
	# (0,0) et (1,0) sont dans un coin : la moitié du losange tombe hors grille.
	_check(slots.size() == 5, "voisinage de rayon 1 sur deux cases de bord (%d)" % slots.size())

	var wide: Array[Vector2i] = DeploymentPlan.default_slots([Vector2i(8, 5)], Vector2i(16, 10), 2)
	_check(wide.size() == 13, "rayon 2 en plein champ : losange de 13 cases (%d)" % wide.size())
	_check(DeploymentPlan.default_slots([], Vector2i(16, 10)).is_empty(),
		"sans ligne de départ, aucune case ouverte")

	# Le chapitre peut imposer sa zone
	var ch = CAMPAIGN_DB.get_chapter(0)
	_check(ch != null and ch.deploy_tiles is Array,
		"les chapitres portent une zone de déploiement (vide = voisinage)")
#endregion


#region 17. Polissage UX — annulation d'un déplacement, fiche d'unité
func _test_ux_polish() -> void:
	print("\n🖱 Test 17: annulation d'un déplacement et fiche d'unité")

	# --- Mémoire de déplacement ---
	var memory := PawnMoveMemory.new()
	_check(not memory.has_moved and not memory.can_undo(true),
		"rien à annuler tant que le pion n'a pas bougé")

	var start := Vector3(2.0, 0.5, -3.0)
	memory.record(start)
	_check(memory.has_moved and memory.can_undo(true), "un déplacement s'annule juste après")
	_check(not memory.can_undo(false),
		"un pion qui a déjà agi ne revient plus en arrière")
	_check(not memory.can_undo(true, false), "un pion tombé ne revient pas non plus")
	_check(memory.consume() == start, "l'annulation rend la position de départ")
	_check(not memory.can_undo(true), "on n'annule pas deux fois le même déplacement")

	memory.record(start)
	memory.clear()
	_check(not memory.can_undo(true), "fin de tour : le déplacement devient définitif")

	# --- Fiche d'unité ---
	var lord: CharStats = _live("res://data/models/world/stats/hero/lord.tres")
	var sheet: Dictionary = UnitSheet.build(lord, {"terrain": "Forêt", "terrain_def": 1})
	_check(not sheet.is_empty() and str(sheet["name"]) == lord.override_name,
		"fiche construite pour %s" % str(sheet.get("name", "?")))
	_check(str(sheet["title"]).contains("Niv. %d" % lord.level), "la fiche annonce le niveau",
		str(sheet["title"]))
	_check(int(sheet["hp"]) == lord.hp and is_equal_approx(float(sheet["hp_ratio"]), 1.0),
		"PV et ratio corrects")

	# Le bonus de terrain doit être visible AVANT d'engager : c'est tout l'intérêt.
	var def_shown: int = 0
	for entry: Dictionary in sheet["stats"]:
		if str(entry["label"]) == "DÉF":
			def_shown = int(entry["value"])
	_check(def_shown == lord.def + 1, "la défense affichée inclut le terrain (%d)" % def_shown)
	_check(UnitSheet.context_line(sheet).contains("🛡+1"), "le terrain est annoncé avec son bonus",
		UnitSheet.context_line(sheet))

	# Valeurs de combat dérivées : ce sont elles qui décident d'un échange.
	var combat: String = UnitSheet.combat_line(sheet)
	_check(combat.contains("Esq %d" % lord.get_avoid()) and combat.contains("Crit %d" % lord.get_crit()),
		"esquive et critique affichés", combat)
	_check(UnitSheet.stats_line(sheet).begins_with("FOR %d" % lord.str),
		"les stats principales ouvrent la ligne", UnitSheet.stats_line(sheet))

	# Unité blessée : la fiche doit refléter l'état, pas les stats de base.
	lord.hp = 5
	var hurt: Dictionary = UnitSheet.build(lord)
	_check(float(hurt["hp_ratio"]) < 0.3, "un pion à 5 PV est en état critique")
	_check(UnitSheet.context_line(hurt).contains("Mvt %d" % lord.movement),
		"sans terrain, la ligne de contexte reste lisible", UnitSheet.context_line(hurt))

	_check(UnitSheet.build(null).is_empty(), "aucune fiche sans stats")
	_check(UnitSheet.terrain_label("forest") == "Forêt"
			and UnitSheet.terrain_label("inconnu").is_empty(),
		"terrains traduits, inconnu ignoré")

	_test_action_labels()
	_test_menu_layout()
	_test_range_highlight()



## Le menu principal : deux colonnes quand il y a la place, une sinon.
func _test_menu_layout() -> void:
	# Le projet est en `stretch/mode="canvas_items"` : la largeur logique ne bouge
	# pas avec la fenêtre. Se fier à elle seule ne déclencherait jamais rien —
	# c'est la forme de la fenêtre qui décide.
	const Title = preload("res://data/modules/menu/title_screen.gd")
	_check(Title.is_wide(Vector2(1280, 720)), "16:9 → deux colonnes")
	_check(not Title.is_wide(Vector2(1280, 1646)),
		"fenêtre en portrait → une seule colonne")
	_check(not Title.is_wide(Vector2(600, 400)),
		"fenêtre minuscule → une seule colonne")
	_check(Title.is_wide(Vector2(1920, 1080)), "plein écran → deux colonnes")


## Le surlignage de portée doit teinter le terrain, pas l'effacer.
func _test_range_highlight() -> void:
	const SCENERY = preload("res://data/models/view/scenery/tactics_scenery.gd")
	const MAPD = preload("res://data/models/world/map/map_data.gd")

	var grass: StandardMaterial3D = SCENERY.terrain_material(MAPD.TerrainType.GRASS)
	var reachable: StandardMaterial3D = SCENERY.highlight_material(
		MAPD.TerrainType.GRASS, "reachable")

	_check(reachable != null and reachable.albedo_texture != null,
		"une case surlignée garde le grain du terrain")
	_check(reachable.uv1_world_triplanar,
		"le motif reste projeté en coordonnées monde (il traverse les cases)")
	_check(reachable.albedo_color != grass.albedo_color,
		"mais sa teinte a changé")
	_check(reachable.emission_enabled,
		"elle porte une lueur propre, lisible dans une ombre portée")

	# Deux terrains différents ne se surlignent pas à l'identique : une forêt
	# reste reconnaissable même à portée.
	var forest: StandardMaterial3D = SCENERY.highlight_material(
		MAPD.TerrainType.FOREST, "reachable")
	_check(forest.albedo_color != reachable.albedo_color,
		"la forêt surlignée se distingue de la plaine surlignée")

	# Les états se distinguent entre eux.
	var attackable: StandardMaterial3D = SCENERY.highlight_material(
		MAPD.TerrainType.GRASS, "attackable")
	_check(attackable.albedo_color != reachable.albedo_color,
		"attaquable et atteignable ne se confondent pas")

	# Le cache rend bien le même objet : 200 tuiles ne construisent pas 200 fois.
	_check(SCENERY.highlight_material(MAPD.TerrainType.GRASS, "reachable") == reachable,
		"les matériaux de surlignage sont mis en cache")

## Le menu d'actions : une clé qui branche, un libellé qui s'affiche.
##
## Le piège que ce test ferme : la clé d'action est le **nom du nœud** bouton.
## Tant que le libellé servait de clé, traduire « Move » en « Déplacer » aurait
## débranché le bouton de sa méthode sans que rien ne le signale.
func _test_action_labels() -> void:
	var controls: TacticsControlsResource = load("res://data/models/view/control/tactics/control.tres")
	if not controls:
		_check(false, "ressource de contrôles chargée")
		return

	var scene: PackedScene = load("res://data/modules/tactics/controls/controls.tscn")
	var node: Node = scene.instantiate() if scene else null
	if not node:
		_check(false, "scène des contrôles instanciée")
		return

	var missing_label: String = ""
	var missing_button: String = ""
	var english: String = ""
	for action: String in controls.actions.keys():
		if not controls.action_labels.has(action):
			missing_label = action
		if not node.get_node_or_null("HBox/Actions/%s" % action):
			missing_button = action
		var button: Button = node.get_node_or_null("HBox/Actions/%s" % action) as Button
		if button and button.text == action:
			english = action

	_check(missing_label.is_empty(), "chaque action a son libellé", missing_label)
	_check(missing_button.is_empty(),
		"chaque clé d'action désigne un bouton existant", missing_button)
	_check(english.is_empty(), "aucun bouton ne montre encore sa clé au joueur", english)
	_check(controls.label_for("Move") == "Déplacer"
			and controls.label_for("Attack") == "Attaquer"
			and controls.label_for("Wait") == "Attendre"
			and controls.label_for("Cancel") == "Retour",
		"menu d'actions en français")
	_check(controls.LABEL_HEAL == "Soigner", "le porteur de bâton soigne, il n'attaque pas")
	_check(controls.label_for("Inconnu") == "Inconnu",
		"une action sans libellé reste lisible au lieu de disparaître")

	node.free()
#endregion


#region 17bis. Confort de jeu — accélérateur, historique, reprise de chapitre
## Les quatre commodités ajoutées le 2026-08-11. Ce qui se vérifie ici est ce qui
## n'a pas besoin d'écran : les constantes des raccourcis, la traduction d'un
## événement du journal en ligne lisible, l'échelle de temps, et l'instantané de
## début de chapitre. Le dessin des panneaux, lui, n'a pas lieu en `--headless`.
func _test_comfort() -> void:
	print("\n🛋 Test 17bis: confort de jeu (X, H, reprise, sauvegarde auto)")

	# --- 1. Accélérateur d'animations (X maintenue) ---
	_check(not SPEED.available(),
		"sans écran, l'accélérateur ne se monte pas — rien à accélérer en headless")
	_check(SPEED.HOLD_KEY == KEY_X and SPEED.SCALE >= 2.0,
		"X accélère, et d'un facteur qui se voit (×%s)" % str(SPEED.SCALE))

	var before_scale: float = Engine.time_scale
	var speed: CanvasLayer = SPEED.new()
	speed.engage()
	_check(speed.is_engaged() and is_equal_approx(Engine.time_scale, SPEED.SCALE),
		"touche enfoncée : le temps court ×%s" % str(SPEED.SCALE), str(Engine.time_scale))
	speed.engage()  # Répétition clavier : elle ne doit rien réapprendre.
	speed.release()
	_check(not speed.is_engaged() and is_equal_approx(Engine.time_scale, before_scale),
		"touche relâchée : le temps reprend son cours", str(Engine.time_scale))
	speed.release()
	_check(is_equal_approx(Engine.time_scale, before_scale),
		"un second relâchement ne fait rien", str(Engine.time_scale))

	# Le vrai danger : une bataille qui se décharge pendant l'accélération. Sans
	# le rattrapage de sortie d'arbre, tous les écrans suivants resteraient à ×3.
	speed.engage()
	speed.free()
	_check(is_equal_approx(Engine.time_scale, before_scale),
		"un accélérateur libéré en pleine accélération rend le temps", str(Engine.time_scale))

	# --- 2. Historique de combat (H) ---
	_check(not HISTORY.available(), "sans écran, l'historique ne se monte pas")
	_check(HISTORY.TOGGLE_KEY == KEY_H and HISTORY.MAX_LINES >= 20,
		"H ouvre l'historique, qui garde %d lignes" % HISTORY.MAX_LINES)

	var crit: String = HISTORY.describe({"kind_name": "attack", "attacker": "Chrom",
		"defender": "Brigand", "damage": 12, "hit": true, "crit": true,
		"double": false, "defender_hp": 8})
	_check(crit.contains("Chrom") and crit.contains("Brigand") and crit.contains("12")
			and crit.contains("critique") and crit.contains("8"),
		"un critique se relit en entier : qui, sur qui, combien, et ce qu'il reste", crit)

	var missed: String = HISTORY.describe({"kind_name": "attack", "attacker": "Virion",
		"defender": "Brigand", "damage": 0, "hit": false})
	_check(missed.contains("manque") and not missed.contains("dégâts"),
		"un coup manqué ne raconte pas de dégâts", missed)

	var doubled: String = HISTORY.describe({"kind_name": "attack", "attacker": "Sully",
		"defender": "Brigand", "damage": 14, "hit": true, "crit": false,
		"double": true, "defender_hp": 3})
	_check(doubled.contains("×2") and not doubled.contains("critique"),
		"l'attaque redoublée se distingue du critique", doubled)

	_check(HISTORY.describe({"kind_name": "death", "pawn": "Brigand",
		"team": "opponent"}).contains("Adversaire"),
		"les camps sont traduits pour le joueur, pas laissés en « opponent »")
	_check(HISTORY.describe({"kind_name": "turn_start", "team": "player",
		"turn": 3}).contains("Tour 3"),
		"le début de tour ouvre une section lisible")
	_check(HISTORY.describe({"kind_name": "heal", "healer": "Lissa", "target": "Chrom",
		"amount": 10, "target_hp": 28}).contains("soigne"), "le soin est journalisé")
	_check(HISTORY.describe({"kind_name": "level_up", "pawn": "Chrom",
		"level": 5}).contains("niveau 5"), "la montée de niveau est journalisée")
	_check(HISTORY.describe({}).is_empty(),
		"un événement inconnu ne produit pas de ligne vide à l'écran")
	_check(HISTORY.tint({"kind_name": "attack", "crit": true})
			!= HISTORY.tint({"kind_name": "attack", "crit": false}),
		"un critique ne se lit pas de la même couleur qu'un coup ordinaire")

	# Tous les genres d'événements que le journal sait écrire doivent avoir une
	# traduction : en ajouter un sans ligne le rendrait invisible au joueur.
	var untranslated: Array = []
	for kind: int in [BattleLogRef.Kind.TURN_START, BattleLogRef.Kind.MOVE,
			BattleLogRef.Kind.ATTACK, BattleLogRef.Kind.HEAL, BattleLogRef.Kind.DEATH,
			BattleLogRef.Kind.LEVEL_UP, BattleLogRef.Kind.PROMOTION,
			BattleLogRef.Kind.COMMAND_REJECTED, BattleLogRef.Kind.OBJECTIVE]:
		var kind_label: String = BattleLogRef.kind_name(kind)
		if HISTORY.describe({"kind_name": kind_label, "hit": true}).is_empty():
			untranslated.append(kind_label)
	_check(untranslated.is_empty(),
		"chaque genre d'événement du journal a sa ligne", str(untranslated))

	# --- 3 & 4. Sauvegarde de début de chapitre, et reprise après défaite ---
	var campaign: Node = root.get_node_or_null("Campaign")
	if not campaign:
		_ko("Autoload Campaign", "introuvable")
		return

	campaign.new_game(DIFF.Level.NORMAL, true)
	_check(not campaign.has_chapter_autosave(),
		"une partie neuve n'hérite pas de l'instantané de la précédente")

	campaign.gold = 500
	var protege: String = str(campaign.roster[0]["id"])
	_check(campaign.autosave_chapter(), "instantané de début de chapitre écrit")
	_check(campaign.has_chapter_autosave(campaign.chapter_index),
		"l'instantané est bien celui du chapitre en cours")
	_check(not campaign.has_chapter_autosave(campaign.chapter_index + 9),
		"il ne se fait pas passer pour celui d'un autre chapitre")

	# La bataille tourne mal : une unité tombe pour de bon, la bourse se vide.
	campaign.apply_battle_result({"id": protege, "hp": 0})
	campaign.gold = 0
	_check(not bool(campaign.get_unit(protege)["alive"]),
		"l'unité est tombée en mort permanente")

	# « Recommencer le chapitre » : l'armée d'avant le premier coup.
	_check(campaign.restore_chapter(), "instantané relu")
	_check(bool(campaign.get_unit(protege)["alive"]) and campaign.gold == 500,
		"recommencer rend l'armée et la bourse d'avant la bataille",
		"%s / %d or" % [str(campaign.get_unit(protege)["alive"]), campaign.gold])

	# L'emplacement dédié ne prend la place d'aucun de ceux du joueur.
	var player_slots: Array = []
	for info: Dictionary in campaign.all_slots():
		player_slots.append(int(info["slot"]))
	_check(player_slots.size() == campaign.SAVE_SLOTS
			and not campaign.CHAPTER_SLOT in player_slots,
		"les 4 emplacements du joueur restent les siens", str(player_slots))

	var auto_info: Dictionary = campaign.chapter_slot_info()
	_check(bool(auto_info["exists"]) and bool(auto_info["chapter_start"]),
		"l'écran de chargement sait le décrire à part", str(auto_info))
	_check(not bool(campaign.slot_info(0).get("chapter_start", true)),
		"un emplacement ordinaire n'est pas confondu avec lui")

	# On ne laisse pas une campagne de test se faire passer pour une vraie.
	campaign.delete_save(campaign.CHAPTER_SLOT)
	_check(not campaign.has_chapter_autosave(), "instantané de test retiré")
#endregion


#region 18. Audio — catalogue et branchement
## Aucun fichier n'est encore fourni : ce qu'on vérifie ici, c'est que le
## système est prêt à les recevoir et qu'il reste muet sans eux.
func _test_audio() -> void:
	print("\n🔊 Test 18: catalogue sonore et service audio")

	# --- Catalogue ---
	_check(SoundDB.keys().size() >= 15, "catalogue fourni (%d sons)" % SoundDB.keys().size())
	var buses: Array = [SoundDB.BUS_SFX, SoundDB.BUS_MUSIC, SoundDB.BUS_UI]
	var well_formed: bool = true
	var bad: String = ""
	for key: String in SoundDB.keys():
		var entry: Dictionary = SoundDB.cue(key)
		if not entry.has("file") or not str(entry["bus"]) in buses \
				or float(entry["pitch_min"]) > float(entry["pitch_max"]):
			well_formed = false
			bad = key
	_check(well_formed, "chaque son déclare un fichier, un bus connu et une hauteur valide", bad)
	_check(SoundDB.path_of("hit").begins_with(SoundDB.AUDIO_DIR),
		"les chemins pointent dans assets/audio", SoundDB.path_of("hit"))
	_check(SoundDB.cue("inexistant").is_empty() and SoundDB.path_of("inexistant").is_empty(),
		"clé inconnue : catalogue muet plutôt qu'en erreur")
	_check(SoundDB.is_music("music_battle") and not SoundDB.is_music("hit"),
		"musiques et bruitages distingués")

	# --- Traduction des événements de bataille ---
	_check(SoundDB.cue_for_event({"kind_name": "attack", "hit": true, "crit": false}) == "hit",
		"un coup qui touche")
	_check(SoundDB.cue_for_event({"kind_name": "attack", "hit": true, "crit": true}) == "hit_crit",
		"un critique ne sonne pas comme un coup normal")
	_check(SoundDB.cue_for_event({"kind_name": "attack", "hit": false, "crit": false}) == "miss",
		"une attaque ratée a son propre bruit")
	_check(SoundDB.cue_for_event({"kind_name": "death", "team": "player"}) == "death_ally"
			and SoundDB.cue_for_event({"kind_name": "death", "team": "opponent"}) == "death_enemy",
		"perdre une unité et en abattre une ne s'entendent pas pareil")
	_check(SoundDB.cue_for_event({"kind_name": "turn_start", "team": "player"}) == "turn_player",
		"début de tour du joueur")
	_check(SoundDB.cue_for_event({"kind_name": "objective", "status": "victory"}) == "victory"
			and SoundDB.cue_for_event({"kind_name": "objective", "status": "defeat"}) == "defeat",
		"fin de chapitre sonorisée")
	_check(SoundDB.cue_for_event({"kind_name": "command_rejected"}).is_empty(),
		"un ordre rejeté de Ciel ne fait pas de bruit au joueur")
	_check(SoundDB.cue_for_event({}).is_empty(), "événement vide : aucun son")

	# --- Service ---
	var audio: Node = root.get_node_or_null("Audio")
	if not audio:
		_ko("Autoload Audio", "introuvable")
		return
	_ok("Autoload Audio disponible")

	for bus: String in buses:
		_check(AudioServer.get_bus_index(bus) != -1, "bus %s créé au démarrage" % bus)

	# Avec les fichiers fournis, jouer fonctionne — et une clé inconnue ou vide
	# ne doit rien casser.
	_check(audio.play("hit"), "un son fourni se joue")
	_check(not audio.play("inexistant"), "une clé inconnue ne se joue pas")
	_check(not audio.play(""), "une clé vide ne se joue pas")
	_check(audio.missing_cues().is_empty(),
		"tous les sons du catalogue sont fournis (%d restants)" % audio.missing_cues().size())

	# --- Réglages de volume ---
	var before: float = audio.get_volume(SoundDB.BUS_MUSIC)
	audio.set_volume(SoundDB.BUS_MUSIC, 0.42)
	_check(is_equal_approx(audio.get_volume(SoundDB.BUS_MUSIC), 0.42), "volume réglé")
	_check(audio.save_settings(), "réglages enregistrés")
	audio.set_volume(SoundDB.BUS_MUSIC, 1.0)
	audio.load_settings()
	_check(is_equal_approx(audio.get_volume(SoundDB.BUS_MUSIC), 0.42), "réglages relus du disque")
	audio.set_volume(SoundDB.BUS_MUSIC, 2.5)
	_check(is_equal_approx(audio.get_volume(SoundDB.BUS_MUSIC), 1.0), "volume borné à 1.0")
	audio.set_volume(SoundDB.BUS_MUSIC, before)
	audio.save_settings()
#endregion


#region 19. Éditeur de cartes — document, validation, bibliothèque
func _test_map_editor() -> void:
	print("\n🗺 Test 19: cartes du joueur")

	const LORD: String = "res://data/models/world/stats/hero/lord.tres"
	const CLERIC: String = "res://data/models/world/stats/hero/cleric.tres"
	const SKELETON: String = "res://data/models/world/stats/mob/skeleton.tres"

	# --- Création et terrain ---
	var doc := MapDocument.create_empty("Col de l'aube", Vector2i(12, 8))
	_check(doc.grid_size == Vector2i(12, 8) and doc.terrain.size() == 96,
		"carte vierge : grille cohérente (%d cases)" % doc.terrain.size())
	_check(doc.terrain_at(Vector2i(0, 0)) == MapData.TerrainType.GRASS, "tout en herbe au départ")
	_check(MapDocument.create_empty("Minuscule", Vector2i(2, 2)).grid_size == MapDocument.MIN_SIZE,
		"une taille trop petite est ramenée au minimum")

	doc.set_terrain_at(Vector2i(3, 3), MapData.TerrainType.FOREST)
	_check(doc.terrain_at(Vector2i(3, 3)) == MapData.TerrainType.FOREST, "terrain peint")
	doc.set_height_at(Vector2i(3, 3), 0.5)
	_check(is_equal_approx(doc.height_at(Vector2i(3, 3)), 0.5), "hauteur appliquée")
	doc.set_height_at(Vector2i(3, 3), 99.0)
	_check(doc.height_at(Vector2i(3, 3)) <= 3.0, "hauteur bornée (%.2f)" % doc.height_at(Vector2i(3, 3)))
	_check(doc.terrain_at(Vector2i(99, 99)) == MapData.TerrainType.GRASS,
		"une case hors carte ne fait pas planter la lecture")

	# --- Pinceau large et remplissage ---
	_check(doc.brush_cells(Vector2i(5, 5), 1).size() == 1, "pinceau 1×1 : une case")
	_check(doc.brush_cells(Vector2i(5, 5), 3).size() == 9, "pinceau 3×3 : neuf cases")
	_check(doc.brush_cells(Vector2i(5, 5), 5).size() == 25, "pinceau 5×5 : vingt-cinq cases")
	_check(doc.brush_cells(Vector2i(0, 0), 5).size() == 9,
		"au coin, le pinceau peint moins large au lieu de déborder (%d cases)"
			% doc.brush_cells(Vector2i(0, 0), 5).size())
	_check(doc.brush_cells(Vector2i(5, 5), 99).size() == 25,
		"un pinceau démesuré est ramené au plus large proposé")
	var brush_inside: bool = true
	for cell: Vector2i in doc.brush_cells(Vector2i(0, 7), 5):
		brush_inside = brush_inside and doc.in_bounds(cell)
	_check(brush_inside, "toutes les cases d'un pinceau tiennent dans la grille")

	# Une carte vierge est d'un seul tenant : le remplissage la prend entière.
	var blank := MapDocument.create_empty("Plaine", Vector2i(8, 6))
	_check(blank.region_of(Vector2i(0, 0)).size() == 48,
		"remplissage : toute la plaine d'un coup (%d cases)"
			% blank.region_of(Vector2i(0, 0)).size())

	# Une barrière la coupe en deux, et le remplissage s'arrête au bord.
	for row: int in 6:
		blank.set_terrain_at(Vector2i(4, row), MapData.TerrainType.WALL)
	_check(blank.region_of(Vector2i(0, 0)).size() == 24,
		"un mur arrête le remplissage (%d cases à l'ouest)"
			% blank.region_of(Vector2i(0, 0)).size())
	_check(blank.region_of(Vector2i(7, 0)).size() == 18,
		"et l'autre côté est une zone à part (%d cases à l'est)"
			% blank.region_of(Vector2i(7, 0)).size())
	_check(blank.region_of(Vector2i(4, 2)).size() == 6,
		"le mur lui-même est une zone d'un seul tenant")

	# Voisinage à quatre : deux étendues qui ne se touchent que par un coin
	# restent deux étendues — c'est aussi ce que dit le déplacement.
	var diagonal := MapDocument.create_empty("Sablier", Vector2i(6, 6))
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 1)]:
		diagonal.set_terrain_at(cell, MapData.TerrainType.SNOW)
	_check(diagonal.region_of(Vector2i(0, 0)).size() == 1,
		"deux cases en diagonale ne forment pas une zone")
	_check(diagonal.region_of(Vector2i(99, 99)).is_empty(),
		"remplir hors de la carte ne rend rien")

	# --- Unités ---
	_check(bool(doc.place_unit(LORD, Vector2i(1, 1), MapDocument.TEAM_PLAYER)["ok"]),
		"unité du joueur posée")
	_check(bool(doc.place_unit(SKELETON, Vector2i(9, 6), MapDocument.TEAM_OPPONENT)["ok"]),
		"adversaire posé")
	_check(doc.units.size() == 2 and doc.units_of(MapDocument.TEAM_PLAYER).size() == 1,
		"les camps sont distingués")

	doc.set_terrain_at(Vector2i(5, 5), MapData.TerrainType.WATER)
	var on_water: Dictionary = doc.place_unit(LORD, Vector2i(5, 5), MapDocument.TEAM_PLAYER)
	_check(not bool(on_water["ok"]), "pas d'unité sur un terrain infranchissable")

	# Poser sur une case occupée remplace : deux unités ne peuvent pas se superposer.
	doc.place_unit(CLERIC, Vector2i(1, 1), MapDocument.TEAM_PLAYER)
	_check(doc.units.size() == 2, "poser sur une case occupée remplace l'occupante")
	_check(str(doc.unit_at(Vector2i(1, 1))["path"]) == CLERIC, "la nouvelle unité est en place")
	_check(doc.remove_unit(Vector2i(1, 1)) and doc.unit_at(Vector2i(1, 1)).is_empty(),
		"unité effacée")
	doc.place_unit(LORD, Vector2i(1, 1), MapDocument.TEAM_PLAYER)

	# --- Zone de déploiement et objectif ---
	_check(doc.toggle_deploy_tile(Vector2i(2, 2)) and doc.is_deploy_tile(Vector2i(2, 2)),
		"case de départ ouverte")
	_check(not doc.toggle_deploy_tile(Vector2i(2, 2)) and not doc.is_deploy_tile(Vector2i(2, 2)),
		"un second clic la referme")
	_check(not doc.toggle_deploy_tile(Vector2i(5, 5)), "pas de case de départ dans l'eau")

	_check(doc.set_seize_point(Vector2i(8, 4)) and doc.seize_point() == Vector2i(8, 4),
		"point de commandement posé")
	_check(not doc.set_seize_point(Vector2i(5, 5)), "pas de point de commandement dans l'eau")

	# --- Validation : c'est elle qui empêche de livrer une carte injouable ---
	_check(doc.validate().is_empty(), "carte complète jugée jouable", str(doc.validate()))

	var no_enemy := MapDocument.create_empty("Sans adversaire")
	no_enemy.place_unit(LORD, Vector2i(1, 1), MapDocument.TEAM_PLAYER)
	_check(no_enemy.validate().size() >= 1, "carte sans adversaire refusée")

	var bad_boss := MapDocument.create_empty("Commandant fantôme")
	bad_boss.place_unit(LORD, Vector2i(1, 1), MapDocument.TEAM_PLAYER)
	bad_boss.place_unit(SKELETON, Vector2i(5, 5), MapDocument.TEAM_OPPONENT)
	bad_boss.set_objective({"kind": OBJ.Kind.DEFEAT_BOSS, "target": "Personne"})
	_check(not bad_boss.validate().is_empty(),
		"objectif visant un commandant absent : carte refusée")
	bad_boss.set_objective({"kind": OBJ.Kind.DEFEAT_BOSS,
		"target": MapDocument.unit_display_name(SKELETON)})
	_check(bad_boss.validate().is_empty(), "le nom d'un adversaire réel est accepté",
		str(bad_boss.validate()))

	var bad_protect := MapDocument.create_empty("Protection impossible")
	bad_protect.place_unit(LORD, Vector2i(1, 1), MapDocument.TEAM_PLAYER)
	bad_protect.place_unit(SKELETON, Vector2i(5, 5), MapDocument.TEAM_OPPONENT)
	bad_protect.set_objective({"kind": OBJ.Kind.PROTECT,
		"target": MapDocument.unit_display_name(CLERIC), "turns": 5})
	_check(not bad_protect.validate().is_empty(),
		"protéger une unité absente de la carte : refusé")

	# --- Redimensionnement : ce qui sort de la grille est oublié ---
	var shrink := MapDocument.create_empty("Rétrécie", Vector2i(16, 12))
	shrink.place_unit(LORD, Vector2i(14, 10), MapDocument.TEAM_PLAYER)
	shrink.toggle_deploy_tile(Vector2i(15, 11))
	shrink.set_seize_point(Vector2i(12, 9))
	var report: Dictionary = shrink.resize(Vector2i(8, 8))
	_check(shrink.units.is_empty() and shrink.deploy_tiles.is_empty(),
		"les unités et cases hors de la nouvelle grille disparaissent")
	_check(shrink.terrain.size() == 64, "la grille est bien redimensionnée")
	_check(int(report["units_removed"]) == 1 and int(report["deploy_removed"]) == 1,
		"le redimensionnement dit ce qu'il a fallu jeter : %s" % str(report))
	_check(bool(report["objective_reset"])
			and int(shrink.objective["kind"]) == OBJ.Kind.ROUT,
		"un point de commandement hors grille ne laisse pas une carte injouable")

	# Agrandir ne détruit rien et complète en herbe.
	var grown := MapDocument.create_empty("Agrandie", Vector2i(8, 8))
	grown.set_terrain_at(Vector2i(1, 1), MapData.TerrainType.MOUNTAIN)
	grown.place_unit(LORD, Vector2i(2, 2), MapDocument.TEAM_PLAYER)
	var grow_report: Dictionary = grown.resize(Vector2i(20, 14))
	_check(grown.terrain.size() == 280 and grown.units.size() == 1
			and grown.terrain_at(Vector2i(1, 1)) == MapData.TerrainType.MOUNTAIN,
		"agrandir garde le terrain peint et les unités posées")
	_check(grown.terrain_at(Vector2i(19, 13)) == MapData.TerrainType.GRASS,
		"les bords ajoutés sont en herbe")
	_check(int(grow_report["units_removed"]) == 0, "agrandir ne perd rien")

	_check(MapDocument.create_empty("Démesurée", Vector2i(99, 99)).grid_size
			== MapDocument.MAX_SIZE,
		"une taille trop grande est ramenée au maximum")

	# --- Chapitre jouable ---
	var chapter: ChapterData = doc.to_chapter()
	_check(chapter.title == doc.name and not chapter.use_roster,
		"la carte devient un chapitre qui n'emprunte pas le roster")
	_check(int(chapter.objective.get("kind", -1)) == OBJ.Kind.SEIZE,
		"l'objectif suit la carte")
	_check(chapter.deploy_tiles.size() == doc.deploy_tiles.size(),
		"la zone de déploiement suit la carte")

	# --- Aller-retour disque ---
	var restored: MapDocument = MapDocument.from_dict(doc.to_dict())
	_check(restored != null and restored.name == doc.name
			and restored.units.size() == doc.units.size()
			and restored.seize_point() == doc.seize_point(),
		"sérialisation fidèle")
	_check(restored.terrain_at(Vector2i(3, 3)) == MapData.TerrainType.FOREST,
		"le terrain survit à l'aller-retour")

	var truncated: Dictionary = doc.to_dict()
	truncated["terrain"] = [0, 0, 0]
	var repaired: MapDocument = MapDocument.from_dict(truncated)
	_check(repaired != null and repaired.terrain.size() == 96,
		"un fichier tronqué est complété plutôt que refusé")

	var future: Dictionary = doc.to_dict()
	future["format_version"] = MapDocument.FORMAT_VERSION + 1
	_check(MapDocument.from_dict(future) == null,
		"une carte d'une version plus récente est refusée")

	# --- Bibliothèque sur disque ---
	var saved: Dictionary = MapLibrary.save(doc)
	_check(bool(saved["ok"]), "carte enregistrée dans user://maps", str(saved.get("error", "")))
	var reread: MapDocument = MapLibrary.load_map(str(saved["path"]))
	_check(reread != null and reread.units.size() == doc.units.size(), "carte relue du disque")

	var listed: Array = MapLibrary.list_maps()
	var found: bool = false
	for entry: Dictionary in listed:
		if str(entry["name"]) == doc.name:
			found = true
			_check(bool(entry["playable"]), "la bibliothèque annonce la carte comme jouable")
	_check(found, "la carte apparaît dans la bibliothèque")

	var broken := MapDocument.create_empty("Injouable")
	_check(not bool(MapLibrary.save(broken)["ok"]),
		"une carte injouable n'est pas enregistrée")

	_check(MapLibrary.delete(str(saved["path"])), "carte de test supprimée")
	_check(MapLibrary.load_map(str(saved["path"])) == null, "le fichier a bien disparu")
	_check(doc.slug() == "col_de_laube", "nom de fichier lisible : %s" % doc.slug())

	# --- Niveau des unités posées ---
	# Une carte ne proposait que des unités de niveau 1 : impossible d'écrire un
	# adversaire redoutable sans en poser dix.
	var levelled := MapDocument.create_empty("Embuscade", Vector2i(10, 8))
	levelled.place_unit(LORD, Vector2i(1, 1), MapDocument.TEAM_PLAYER)
	levelled.place_unit(SKELETON, Vector2i(6, 6), MapDocument.TEAM_OPPONENT, 12)
	_check(int(levelled.unit_at(Vector2i(6, 6)).get("level", 0)) == 12,
		"une unité se pose au niveau demandé")
	_check(int(levelled.unit_at(Vector2i(1, 1)).get("level", 0)) == 1,
		"sans précision, elle vaut 1 — ce qu'elle valait avant")

	levelled.place_unit(SKELETON, Vector2i(5, 5), MapDocument.TEAM_OPPONENT, 999)
	_check(int(levelled.unit_at(Vector2i(5, 5))["level"]) == MapDocument.MAX_LEVEL,
		"un niveau démesuré est ramené au plafond")
	_check(levelled.validate().is_empty(), "la carte reste jouable",
		", ".join(levelled.validate()))

	var out_of_range: Dictionary = levelled.to_dict()
	out_of_range["units"][0]["level"] = 99
	var reloaded: MapDocument = MapDocument.from_dict(out_of_range)
	_check(int(reloaded.units[0]["level"]) <= MapDocument.MAX_LEVEL,
		"un fichier bricolé à la main est ramené dans les bornes")

	# Une carte d'avant les niveaux ne les déclare pas : elle doit rester lisible.
	var legacy: Dictionary = levelled.to_dict()
	for u: Dictionary in legacy["units"]:
		u.erase("level")
	var old_map: MapDocument = MapDocument.from_dict(legacy)
	_check(old_map != null and int(old_map.units[0]["level"]) == 1,
		"une carte d'avant les niveaux se relit, ses unités au niveau 1")

	# --- Une unité posée au niveau N y monte vraiment ---
	# Écrire `level = 8` sur une recrue lui donnerait l'étiquette d'une vétérane
	# et les statistiques d'une bleue. Elle gravit donc les échelons.
	var rookie: CharStats = _live(SKELETON)
	var base_hp: int = rookie.max_hp
	var veteran: CharStats = _live(SKELETON)
	_check(veteran.raise_to_level(8) == 8, "l'unité atteint le niveau demandé",
		"niveau %d" % veteran.level)
	_check(veteran.max_hp >= base_hp,
		"et ses statistiques ont grandi avec elle (%d → %d PV)" % [base_hp, veteran.max_hp])

	# Graine fixe : deux machines d'une partie en réseau doivent voir la même
	# adversaire, et rouvrir une carte ne doit pas la redessiner.
	var twin: CharStats = _live(SKELETON)
	twin.raise_to_level(8)
	_check(twin.max_hp == veteran.max_hp and twin.str == veteran.str
			and twin.spd == veteran.spd,
		"deux montées au même niveau donnent la même unité",
		"%d/%d PV" % [twin.max_hp, veteran.max_hp])

	var untouched: CharStats = _live(SKELETON)
	_check(untouched.raise_to_level(1) == 1 and untouched.max_hp == base_hp,
		"demander un niveau déjà atteint ne change rien")

	# --- Roster lu sur le disque ---
	# Il était écrit en dur dans l'interface : neuf chemins, et rien d'autre ne
	# pouvait être posé.
	var heroes: Array = MapEditorUI.roster_of(MapDocument.TEAM_PLAYER)
	var mobs: Array = MapEditorUI.roster_of(MapDocument.TEAM_OPPONENT)
	_check(heroes.size() >= 6 and mobs.size() >= 3,
		"le roster se lit sur le disque (%d héros, %d créatures)" % [heroes.size(), mobs.size()])
	var named: bool = not heroes.is_empty()
	for entry: Dictionary in heroes:
		if str(entry["name"]).is_empty() or not MapDocument.unit_exists(str(entry["path"])):
			named = false
	_check(named, "chaque unité proposée a un nom et une fiche qui existe")

	# --- Échange de cartes ---
	var text: String = MapLibrary.to_json(levelled)
	var back: Dictionary = MapLibrary.from_json(text)
	_check(bool(back["ok"]) and back["doc"].name == levelled.name
			and back["doc"].units.size() == levelled.units.size(),
		"une carte passe par du texte et revient entière", str(back["error"]))
	_check(int(back["doc"].unit_at(Vector2i(6, 6))["level"]) == 12,
		"le niveau des unités fait le voyage")

	_check(not bool(MapLibrary.from_json("")["ok"]),
		"coller du vide ne casse rien, ça se dit")
	_check(not bool(MapLibrary.from_json("bonjour")["ok"]),
		"coller n'importe quel texte se refuse proprement")
	_check(not bool(MapLibrary.from_json('{"nom": "pas une carte"}')["ok"]),
		"du JSON qui n'est pas une carte se refuse aussi")

	var exported: Dictionary = MapLibrary.export_to(levelled, "user://maps/essai_export")
	_check(bool(exported["ok"]) and str(exported["path"]).ends_with(".json"),
		"l'extension est ajoutée si on l'oublie", str(exported["error"]))
	var imported: Dictionary = MapLibrary.import_from(str(exported["path"]))
	_check(bool(imported["ok"]) and imported["doc"].name == levelled.name,
		"le fichier exporté se réimporte", str(imported["error"]))
	_check(not bool(MapLibrary.import_from("user://maps/rien_du_tout.json")["ok"]),
		"importer un fichier absent se dit au lieu de se taire")
	MapLibrary.delete(str(exported["path"]))

	# Exporter accepte un brouillon, là où enregistrer le refuse : on doit pouvoir
	# envoyer une carte inachevée à quelqu'un pour qu'il la finisse.
	var draft: Dictionary = MapLibrary.export_to(broken, "user://maps/essai_brouillon.json")
	_check(bool(draft["ok"]), "un brouillon injouable s'exporte quand même",
		str(draft["error"]))
	MapLibrary.delete(str(draft["path"]))


## Annuler / rétablir : la pile d'instantanés de l'éditeur.
func _test_map_history() -> void:
	print("\n↶ Test 20: annulation dans l'éditeur")

	const LORD: String = "res://data/models/world/stats/hero/lord.tres"

	var doc := MapDocument.create_empty("Brouillon", Vector2i(10, 8))
	var history := MapHistory.started_on(doc.to_dict())
	_check(not history.can_undo() and not history.can_redo(),
		"une carte neuve n'a rien à annuler")

	# Un coup de pinceau, puis un autre.
	doc.set_terrain_at(Vector2i(2, 2), MapData.TerrainType.FOREST)
	_check(history.record(doc.to_dict()), "premier coup retenu")
	doc.set_terrain_at(Vector2i(3, 3), MapData.TerrainType.WATER)
	_check(history.record(doc.to_dict()), "deuxième coup retenu")
	_check(history.undo_steps() == 2, "deux coups annulables")

	# Un clic sans effet n'encombre pas la pile.
	_check(not history.record(doc.to_dict()), "un état identique n'est pas retenu")
	_check(history.undo_steps() == 2, "la pile n'a pas bougé")

	# Annuler ramène l'état précédent — sur le même document.
	_check(doc.apply_dict(history.undo()), "annulation appliquée")
	_check(doc.terrain_at(Vector2i(3, 3)) == MapData.TerrainType.GRASS,
		"le dernier coup de pinceau est défait")
	_check(doc.terrain_at(Vector2i(2, 2)) == MapData.TerrainType.FOREST,
		"l'avant-dernier tient toujours")

	# Rétablir le remet.
	_check(history.can_redo() and doc.apply_dict(history.redo()), "rétablissement appliqué")
	_check(doc.terrain_at(Vector2i(3, 3)) == MapData.TerrainType.WATER,
		"le coup rétabli est de retour")

	# Repartir dans une autre direction rend le futur caduc.
	doc.apply_dict(history.undo())
	doc.set_terrain_at(Vector2i(4, 4), MapData.TerrainType.WALL)
	history.record(doc.to_dict())
	_check(not history.can_redo(), "un nouveau coup efface ce qu'on pouvait rétablir")

	# Tout l'état revient, pas seulement le terrain.
	doc.place_unit(LORD, Vector2i(1, 1), MapDocument.TEAM_PLAYER)
	doc.toggle_deploy_tile(Vector2i(1, 1))
	doc.set_seize_point(Vector2i(5, 5))
	doc.deploy_slots = 7
	doc.name = "Brouillon abouti"
	history.record(doc.to_dict())
	doc.apply_dict(history.undo())
	_check(doc.units.is_empty() and doc.deploy_tiles.is_empty()
			and doc.deploy_slots == 4 and doc.name == "Brouillon"
			and int(doc.objective["kind"]) == OBJ.Kind.ROUT,
		"unités, zone de départ, places, nom et objectif reviennent ensemble")

	# Un redimensionnement s'annule comme le reste.
	var resized := MapDocument.create_empty("Taille", Vector2i(16, 12))
	resized.place_unit(LORD, Vector2i(14, 10), MapDocument.TEAM_PLAYER)
	var sizes := MapHistory.started_on(resized.to_dict())
	resized.resize(Vector2i(8, 8))
	sizes.record(resized.to_dict())
	resized.apply_dict(sizes.undo())
	_check(resized.grid_size == Vector2i(16, 12) and resized.units.size() == 1,
		"annuler un rétrécissement rend la grille et l'unité qu'elle portait")

	# Rien à annuler : la pile le dit au lieu de rendre un état bancal.
	var empty := MapHistory.started_on(MapDocument.create_empty("Vide").to_dict())
	_check(empty.undo().is_empty() and empty.redo().is_empty(),
		"annuler sans historique ne rend rien")

	# La profondeur borne la mémoire : les coups les plus vieux tombent.
	var deep := MapHistory.started_on(MapDocument.create_empty("Profonde").to_dict(), 3)
	var counted := MapDocument.create_empty("Profonde")
	for i: int in 10:
		counted.set_height_at(Vector2i(i % 6, 0), 0.25 * float(i + 1))
		deep.record(counted.to_dict())
	_check(deep.undo_steps() == 3, "la pile est bornée à sa profondeur (%d)" % deep.undo_steps())
	for _i in 5:
		deep.undo()
	_check(not deep.can_undo() and deep.redo_steps() == 3,
		"annuler jusqu'au bout laisse tout à rétablir")
#endregion


#region 21. Grille de bataille en données
## Ce que ces tests prouvent : l'adjacence et l'occupation se calculent sans
## scène montée ni moteur physique. C'était impossible tant que les réponses
## venaient de rayons 3D.
func _test_battle_grid() -> void:
	print("\n🗺️ Test 21: grille de bataille (adjacence & occupation)")

	# Une grille 4×3 posée comme l'arène les génère : centrée sur l'origine,
	# donc à des positions en .5 — le cas qui piégeait un arrondi naïf.
	var grid := BattleGrid.new()
	var tiles: Dictionary = {}
	for row: int in 3:
		for col: int in 4:
			var node := Node3D.new()
			var pos := Vector3(float(col) - 2.0 + 0.5, 0.0, float(row) - 1.5 + 0.5)
			node.position = pos  # lue par _infer_tile_size
			grid.add_tile(node, pos)
			tiles[Vector2i(col, row)] = node

	_check(grid.size() == 12, "12 cases inscrites, aucune collision de coordonnées",
		"taille = %d" % grid.size())

	# Le piège : de part et d'autre de zéro, deux tuiles voisines doivent rester
	# voisines. round() les aurait séparées d'une case fantôme.
	var left: Vector2i = grid.coord_at_position(Vector3(-0.5, 0, 0))
	var right: Vector2i = grid.coord_at_position(Vector3(0.5, 0, 0))
	_check(right.x - left.x == 1, "les cases restent contiguës en traversant zéro",
		"%s puis %s" % [str(left), str(right)])

	# Un pion ne s'arrête jamais pile au centre de sa case : la grille doit lui
	# rendre la **plus proche**, pas la précédente. C'est ce qui manquait le
	# 2026-08-07 — arrêté à 0,14 en deçà du centre, il était rattaché à la case
	# d'avant, et le recentrage le renvoyait une case en arrière. Un déplacement
	# de cinq cases en valait quatre.
	var target_tile: Node3D = tiles[Vector2i(2, 1)]
	var target_coord: Vector2i = grid.coord_of(target_tile)
	var always_nearest: bool = true
	for nudge: float in [-0.4, -0.14, 0.0, 0.14, 0.4]:
		if grid.coord_at_position(target_tile.position + Vector3(nudge, 0, nudge)) != target_coord:
			always_nearest = false
	_check(always_nearest,
		"une position décalée dans sa case rend quand même cette case-là")

	# Et cela quelle que soit la parité de la carte : une largeur paire pose ses
	# centres sur les demis, une largeur impaire sur les entiers. L'ancienne
	# formule n'était juste que pour l'une des deux.
	var odd := BattleGrid.new()
	var odd_tiles: Array[Node3D] = []
	for col: int in 3:
		var node := Node3D.new()
		node.position = Vector3(float(col) - 1.0, 0.0, 0.0)
		odd.add_tile(node, node.position)
		odd_tiles.append(node)
	var odd_middle: Vector2i = odd.coord_of(odd_tiles[1])
	_check(odd.coord_at_position(Vector3(-0.3, 0, 0)) == odd_middle
			and odd.coord_at_position(Vector3(0.3, 0, 0)) == odd_middle,
		"une carte de largeur impaire se lit avec la même justesse")
	for node: Node3D in odd_tiles:
		node.free()

	var middle: Node3D = tiles[Vector2i(1, 1)]
	_check(grid.neighbors_of(middle, 1.0).size() == 4, "une case au centre a 4 voisines")

	var corner: Node3D = tiles[Vector2i(0, 0)]
	_check(grid.neighbors_of(corner, 1.0).size() == 2, "une case au coin n'en a que 2")

	# Dénivellation : une falaise coupe l'adjacence.
	var cliff := Node3D.new()
	grid.add_tile(cliff, Vector3(0.5 + 1.0, 3.0, -0.5))  # voisine de (2,1), 3 m plus haut
	var below: Node3D = tiles[Vector2i(2, 1)]
	var reachable_neighbors: Array = grid.neighbors_of(below, 1.0)
	_check(not reachable_neighbors.has(cliff), "une falaise de 3 m n'est pas adjacente")
	_check(grid.neighbors_of(below, 4.0).has(cliff), "elle le redevient si l'on saute 4 m")

	# Occupation : posée en donnée, lue sans rayon.
	var pawn := RefCounted.new()
	_check(not grid.is_taken(middle), "une case vide n'est pas occupée")
	grid.place_occupant(grid.coord_of(middle), pawn)
	_check(grid.is_taken(middle), "la case porte son pion")
	_check(grid.occupant_of(middle) == pawn, "et rend bien celui-là")
	_check(not grid.is_taken(corner), "sans contaminer la voisine")

	grid.place_occupant(grid.coord_of(middle), null)
	_check(not grid.is_taken(middle), "le pion parti, la case se libère")

	# Une tuile inconnue de l'index ne doit rien affirmer.
	var stranger := Node3D.new()
	_check(not grid.has_tile(stranger) and grid.neighbors_of(stranger, 1.0).is_empty(),
		"une tuile hors index n'invente pas de voisines")

	_check(is_equal_approx(BattleGrid._infer_tile_size(tiles.values()), 1.0),
		"le côté d'une case se déduit des positions")

	for node: Node3D in tiles.values():
		node.free()
	cliff.free()
	stranger.free()


func _test_path_field() -> void:
	print("\n🧭 Test 22: le parcours en données (PathField)")

	# Une grille 5×5 plate, un mur vertical percé d'un passage : le cas qui dit
	# tout. Rien de tout ceci n'exigeait de scène 3D avant le 2026-08-07 — c'est
	# précisément ce que ce refactor rend possible.
	var grid := BattleGrid.new()
	var nodes: Array[Node3D] = []
	for row: int in 5:
		for col: int in 5:
			var node := Node3D.new()
			node.position = Vector3(float(col) - 2.5 + 0.5, 0.0, float(row) - 2.5 + 0.5)
			grid.add_tile(node, node.position)
			nodes.append(node)

	var origin: Vector2i = grid.coord_at_position(Vector3(-2.0, 0.0, -2.0))  # case (0, 0)
	var open_everything: Callable = func(_c: Vector2i) -> bool: return true

	var field := PathField.new()
	field.expand(grid, origin, 1.0, open_everything)

	_check(is_zero_approx(field.distance_at(origin)) and not field.has_root(origin),
		"l'origine est à zéro pas et ne vient de nulle part")
	_check(is_equal_approx(field.distance_at(origin + Vector2i(2, 0)), 2.0),
		"deux cases plus loin, deux pas",
		str(field.distance_at(origin + Vector2i(2, 0))))
	_check(is_equal_approx(field.distance_at(origin + Vector2i(2, 2)), 4.0),
		"en diagonale, on contourne : quatre pas pour deux et deux")
	_check(field.reached().size() == 24, "les 24 autres cases sont atteintes",
		"%d" % field.reached().size())

	# Le chemin rendu part de l'origine et arrive à la case demandée.
	var route: Array[Vector2i] = field.path_to(origin + Vector2i(2, 2))
	_check(route.size() == 5 and route[0] == origin and route[-1] == origin + Vector2i(2, 2),
		"le chemin va de l'origine à la case visée, celle-ci comprise",
		"%d étapes : %s" % [route.size(), str(route)])

	# Une case hors du parcours ne rend qu'elle-même — c'est ce qui empêche un
	# pion de partir vers une case qu'il ne peut pas rejoindre.
	var walled := PathField.new()
	# Un mur sur toute la colonne 2, sauf la case la plus au sud.
	var barrier: Callable = func(c: Vector2i) -> bool:
		return c.x - origin.x != 2 or c.y - origin.y == 4
	walled.expand(grid, origin, 1.0, barrier)

	_check(is_equal_approx(walled.distance_at(origin + Vector2i(2, 4)), 6.0),
		"le passage est emprunté : six pas pour longer le mur",
		str(walled.distance_at(origin + Vector2i(2, 4))))
	_check(is_equal_approx(walled.distance_at(origin + Vector2i(2, 0)), 0.0)
			and not walled.has_root(origin + Vector2i(2, 0)),
		"une case murée reste hors du parcours")
	_check(walled.path_to(origin + Vector2i(2, 0)).size() == 1,
		"et son « chemin » ne mène nulle part : elle seule")

	# Oublier le parcours le vide vraiment.
	walled.clear()
	_check(walled.reached().is_empty() and not walled.has_root(origin + Vector2i(1, 0)),
		"remettre à zéro efface tout le parcours")

	for node: Node3D in nodes:
		node.free()


## Ce que le parcours accepte de traverser : terrain, alliés, adversaires.
##
## Éprouvé sur le service réel, pas sur une règle recopiée — c'est le service qui
## s'est trompé. Et c'est possible sans fenêtre depuis le 2026-08-07 seulement :
## avant, l'occupation se lisait par un rayon.
func _test_traversal_rules() -> void:
	print("\n🚶 Test 23: ce qu'une unité traverse")

	var arena_res: Resource = load("res://data/models/world/combat/arena/arena.tres")
	var service := TacticsArenaService.new(arena_res)
	var grid := BattleGrid.new()
	service.grid = grid

	# Une ligne de cinq cases, toutes praticables.
	var tiles: Array[TacticsTile] = []
	for col: int in 5:
		var tile := TacticsTile.new()
		tile.terrain_type = MAP_DATA.TerrainType.GRASS
		tile.position = Vector3(float(col) - 2.5 + 0.5, 0.0, 0.0)
		grid.add_tile(tile, tile.position)
		tiles.append(tile)

	var origin: TacticsTile = tiles[0]
	var far: Vector2i = grid.coord_of(tiles[4])
	var ally := RefCounted.new()
	var foe := RefCounted.new()

	# Rien sur la route : on va au bout.
	service.process_surrounding_tiles(origin, 2.0, true)
	_check(is_equal_approx(service.field.distance_at(far), 4.0),
		"une ligne dégagée se parcourt de bout en bout",
		str(service.field.distance_at(far)))

	# Un allié au milieu : la route est coupée aussi. Règle demandée par le
	# joueur le 2026-08-12 : les pions bloquent le passage quel que soit leur
	# camp — une ligne tenue est une ligne tenue, et c'est ce qui donne aux
	# couloirs et aux ponts leur poids tactique.
	grid.place_occupant(grid.coord_of(tiles[2]), ally)
	service.field.clear()
	service.process_surrounding_tiles(origin, 2.0, true)
	_check(is_zero_approx(service.field.distance_at(far))
			and not service.field.has_root(far),
		"on ne traverse pas ses camarades : l'allié au milieu barre la route",
		str(service.field.distance_at(far)))

	# Et on ne s'y arrête jamais : une case occupée n'est pas une destination.
	# (`mark_reachable_tiles` s'en charge, et il faut une arène pour l'appeler —
	# on vérifie ici la règle qu'il consulte.)
	_check(grid.is_taken(tiles[2]),
		"la case de l'allié reste occupée, donc refusée comme destination")

	# Un adversaire au milieu : la route est coupée, comme pour un allié.
	grid.place_occupant(grid.coord_of(tiles[2]), foe)
	service.field.clear()
	service.process_surrounding_tiles(origin, 2.0, true)
	_check(is_zero_approx(service.field.distance_at(far))
			and not service.field.has_root(far),
		"on ne traverse pas l'adversaire : le bout devient inatteignable",
		str(service.field.distance_at(far)))

	# Sans blocage par unités, ce n'est plus un déplacement mais une portée
	# d'arme : l'occupation ne compte pas, un arc tire par-dessus les têtes.
	service.field.clear()
	service.process_surrounding_tiles(origin, 2.0, false)
	_check(is_equal_approx(service.field.distance_at(far), 4.0),
		"une portée d'arme ignore qui se tient sur le chemin")

	# Le terrain, lui, arrête tout le monde.
	grid.place_occupant(grid.coord_of(tiles[2]), null)
	tiles[2].terrain_type = MAP_DATA.TerrainType.WATER
	service.field.clear()
	service.process_surrounding_tiles(origin, 2.0, true)
	_check(not service.field.has_root(far), "un lac coupe la route à tous")

	# Le dénivelé aussi — et c'est le **saut** qui en décide, pas le mouvement.
	# Le joueur passait son mouvement (5) là où l'IA passe son saut (2) : il
	# escaladait des falaises que l'adversaire ne pouvait pas suivre.
	tiles[2].terrain_type = MAP_DATA.TerrainType.GRASS
	var cliff := BattleGrid.new()
	var ledges: Array[TacticsTile] = []
	for col: int in 3:
		var tile := TacticsTile.new()
		tile.terrain_type = MAP_DATA.TerrainType.GRASS
		# La case du milieu est perchée trois unités plus haut.
		tile.position = Vector3(float(col) - 1.0, 3.0 if col == 1 else 0.0, 0.0)
		cliff.add_tile(tile, tile.position)
		ledges.append(tile)
	service.grid = cliff

	service.field.clear()
	service.process_surrounding_tiles(ledges[0], 2.0, true)
	_check(not service.field.has_root(cliff.coord_of(ledges[1])),
		"un saut de 2 ne franchit pas une marche de 3")
	service.field.clear()
	service.process_surrounding_tiles(ledges[0], 5.0, true)
	_check(service.field.has_root(cliff.coord_of(ledges[1])),
		"un saut de 5 la franchirait — d'où l'écart entre les deux camps")

	for tile: TacticsTile in tiles:
		tile.free()
	for tile: TacticsTile in ledges:
		tile.free()
#endregion


#region 24. La charte graphique
func _test_charter() -> void:
	print("🎨 Test 24: la charte graphique")

	var theme: Theme = CielTheme.build()
	_check(theme != null and CielTheme.build() == theme,
		"le thème n'est bâti qu'une fois")

	# Ce qui manquait : le jeu n'habillait que ses boutons. Un type oublié ici
	# retombe sur le thème de Godot, et se voit immédiatement à l'écran.
	for type: String in ["Button", "OptionButton", "LineEdit", "PopupMenu",
			"Panel", "PanelContainer", "VScrollBar"]:
		_check(theme.get_stylebox_list(type).size() > 0,
			"« %s » est habillé par la charte" % type)
	for icon: Array in [["updown", "SpinBox"], ["arrow", "OptionButton"],
			["checked", "CheckBox"]]:
		_check(theme.get_icon(icon[0], icon[1]) != null,
			"l'icône « %s » de %s est dessinée, pas empruntée" % [icon[0], icon[1]])

	# Le piège des polices variables : `variation_opentype` n'accepte que le tag
	# entier de l'axe. Avec la clé texte, Godot n'échoue pas — il ignore, et le
	# titre reste en Regular sans que rien ne le signale. Seule une mesure le
	# dit, donc on mesure : du 700 doit être plus large que du 400.
	var title_font: Font = theme.get_font("font", "TitreEmbleme")
	var light := FontVariation.new()
	light.base_font = Palette.FONT_TITLE
	var axis: int = TextServerManager.get_primary_interface().name_to_tag("weight")
	light.variation_opentype = {axis: 400}
	_check(title_font.get_string_size("CIEL EMBLEM", 0, -1, 48).x
			> light.get_string_size("CIEL EMBLEM", 0, -1, 48).x,
		"le titre est réellement en gras (la graisse variable a pris)")

	# Même piège en miroir : les chiffres elzéviriens d'Alegreya Sans sont
	# illisibles dans un tableau de statistiques. `lnum`/`tnum` les redressent,
	# et là c'est bien la clé texte qui marche.
	var plain := FontVariation.new()
	plain.base_font = Palette.FONT_BODY
	_check(theme.default_font.get_string_size("11 16 3", 0, -1, 17).x
			!= plain.get_string_size("11 16 3", 0, -1, 17).x,
		"les chiffres du corps de texte sont redressés et tabulaires")

	# La charte ne sert à rien si un écran peut encore inventer sa couleur :
	# l'or de la palette doit être celui que les écrans utilisaient en dur.
	_check(Palette.GOLD == Color("#f5c842"), "l'or de la charte est celui du jeu")
	_check(Palette.shade(Palette.GOLD, -0.2).v < Palette.GOLD.v,
		"assombrir une couleur de la charte l'assombrit")
#endregion


#region 25. Bilan de bataille — les pertes ont deux camps
## Le bilan comptait bien deux lignes, mais il les remplissait avec le même
## chiffre : le journal notait « player » pour toutes les morts.
func _test_battle_summary() -> void:
	print("\n📜 Test 25: le bilan de bataille distingue les camps")

	# --- Le piège, à la source : qui est mort, et de quel côté ---
	# Le camp était deviné en demandant au nœud parent s'il savait montrer un menu
	# d'actions. Les deux camps savent : la méthode vit sur leur classe commune.
	var player_camp := TacticsPlayer.new()
	player_camp.name = "TacticsPlayer"
	var enemy_camp := TacticsOpponent.new()
	enemy_camp.name = "TacticsOpponent"

	_check(player_camp.has_method("show_available_pawn_actions")
			and enemy_camp.has_method("show_available_pawn_actions"),
		"les deux camps exposent les mêmes méthodes — deviner par là était perdu d'avance")
	_check(TacticsPawnCombatService.team_name_for_camp(player_camp) == "player",
		"une unité du joueur meurt du côté du joueur",
		TacticsPawnCombatService.team_name_for_camp(player_camp))
	_check(TacticsPawnCombatService.team_name_for_camp(enemy_camp) == "opponent",
		"une unité adverse meurt du côté adverse",
		TacticsPawnCombatService.team_name_for_camp(enemy_camp))

	# Le même champ décide du son : abattre un brigand ne doit pas sonner comme
	# perdre un allié.
	_check(SoundDB.cue_for_event({"kind_name": "death", "team": "opponent"}) == "death_enemy"
			and SoundDB.cue_for_event({"kind_name": "death", "team": "player"}) == "death_ally",
		"la mort d'un ennemi et celle d'un allié ne s'entendent pas pareil")

	player_camp.free()
	enemy_camp.free()

	# --- Le compte, ensuite ---
	var events: Array = [
		{"kind_name": "turn_start", "team": "player", "turn": 3},
		{"kind_name": "attack", "attacker": "Elyan", "defender": "Brigand",
			"damage": 12, "hit": true, "crit": true},
		{"kind_name": "attack", "attacker": "Brigand", "defender": "Elyan",
			"damage": 5, "hit": true, "crit": false},
		{"kind_name": "death", "pawn": "Brigand", "team": "opponent"},
		{"kind_name": "death", "pawn": "Archer", "team": "opponent"},
		{"kind_name": "death", "pawn": "Elyan", "team": "player"},
	]
	var summary: Dictionary = BattleStats.from_events(events, ["Elyan"])

	_check(int(summary["enemies_defeated"]) == 2,
		"deux ennemis vaincus", str(summary["enemies_defeated"]))
	_check(int(summary["allies_fallen"]) == 1,
		"un allié tombé", str(summary["allies_fallen"]))
	_check(int(summary["damage_dealt"]) == 12 and int(summary["damage_taken"]) == 5,
		"les dégâts restent attribués au bon camp")

	# --- L'affichage : deux lignes, et chacune dit de quel camp elle parle ---
	var rows: Array = BattleStats.rows(summary)
	var labels: Array = []
	var by_label: Dictionary = {}
	for row: Array in rows:
		labels.append(str(row[0]))
		by_label[str(row[0])] = str(row[1])

	_check(by_label.get("Ennemis vaincus", "") == "2"
			and by_label.get("Alliés tombés", "") == "1",
		"le bilan affiche les deux comptes séparément", str(labels))
	_check(not "Unités tombées" in labels,
		"plus de ligne « Unités tombées » : elle ne disait pas de quel camp")

	# Une bataille sans perte doit afficher zéro, pas rien : c'est le chiffre
	# qu'un joueur vient chercher.
	var clean: Array = BattleStats.rows(BattleStats.empty())
	var clean_labels: Array = []
	for row: Array in clean:
		clean_labels.append(str(row[0]))
	_check("Ennemis vaincus" in clean_labels and "Alliés tombés" in clean_labels,
		"les deux lignes existent même à zéro", str(clean_labels))
#endregion
