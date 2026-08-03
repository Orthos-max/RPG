extends SceneTree
## Tests headless des features ajoutées (P0 → Solo).
## Lancer : godot --headless --path . --script test_features.gd
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
const OBJ = preload("res://data/models/campaign/objective.gd")
const CAMPAIGN_DB = preload("res://data/models/campaign/campaign_db.gd")
const StatsRes = preload("res://data/models/world/stats/stats_res.gd")
const CharStats = preload("res://data/modules/stats/stats.gd")
const Calc = preload("res://data/services/combat/fe_combat.gd")

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

	var bonuses: Array = OBJ.evaluate_bonuses(
		[{"kind": OBJ.Bonus.NO_LOSSES}, {"kind": OBJ.Bonus.SPEED_RUN, "turns": 5}],
		{"turn": 4, "player_units": alive_players, "enemy_units": dead_enemies})
	_check(bonuses.size() == 2 and bool(bonuses[0]["achieved"]) and bool(bonuses[1]["achieved"]),
		"objectifs secondaires validés", str(bonuses))

	# Contenu de campagne
	_check(CAMPAIGN_DB.count() >= 3, "au moins 3 chapitres définis")
	var ch1 = CAMPAIGN_DB.get_chapter(0)
	_check(ch1 != null and ch1.id == "ch01" and not ch1.intro_lines.is_empty(),
		"chapitre 1 complet (%s)" % (ch1.title if ch1 else "?"))
	_check(CAMPAIGN_DB.index_of("ch02") == 1 and CAMPAIGN_DB.get_chapter(99) == null,
		"index de chapitre robuste")
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
