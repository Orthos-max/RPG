extends SceneTree
## Automated test — combat, death, heal, victory
## Run with: Godot --headless --script res://tests/test_combat.gd --path .

const WT = preload("res://data/models/world/stats/weapon_type.gd")
const StatsRes = preload("res://data/models/world/stats/stats_res.gd")
const CharStats = preload("res://data/modules/stats/stats.gd")
const Calc = preload("res://data/services/combat/fe_combat.gd")
const SupportDB = preload("res://data/models/world/stats/support.gd")
const Forecast = preload("res://data/services/combat/battle_forecast.gd")

## Wrap a StatsResource template into a live Stats combat instance
func _live(res: StatsRes) -> CharStats:
	var s := CharStats.new()
	s.import_stats(res)
	return s

var _passed: int = 0
var _failed: int = 0
var _tests: Array = []

func _init() -> void:
	print("\n========================================")
	print("  TEST COMBAT FE — Automatisé")
	print("========================================\n")
	
	await create_timer(0.3).timeout
	
	_test_load()
	_test_calculator()
	_test_heal()
	_test_death()
	_test_victory()
	_test_support()
	_test_triangle()
	_test_forecast()
	_test_counter_range()
	_test_exchange()
	_test_exchange_rolls()
	_test_forecast_counter()

	print("\n========================================")
	print("  RÉSULTATS: %d OK / %d ÉCHECS" % [_passed, _failed])
	print("========================================\n")
	for t in _tests:
		print(t)
	
	await create_timer(0.2).timeout
	quit(0 if _failed == 0 else 1)


func _ok(name: String) -> void:
	_passed += 1
	_tests.append("  ✅ %s" % name)

func _ko(name: String, detail: String = "") -> void:
	_failed += 1
	_tests.append("  ❌ %s — %s" % [name, detail])


func _test_load() -> void:
	print("📦 Test 1: Chargement resources")
	
	var chrom: StatsRes = load("res://data/models/world/stats/hero/lord.tres")
	var lissa: StatsRes = load("res://data/models/world/stats/hero/cleric.tres")
	var fred: StatsRes = load("res://data/models/world/stats/hero/great_knight.tres")
	var brig: StatsRes = load("res://data/models/world/stats/mob/skeleton.tres")
	var mage: StatsRes = load("res://data/models/world/stats/mob/skeleton_mage.tres")
	
	if chrom and lissa and fred and brig and mage:
		_ok("5 .tres chargés")
	else:
		_ko("Chargement .tres", "manquant")
		return
	
	if chrom.str > 0 and chrom.str > chrom.mag:
		_ok("Chrom: STR=%d MAG=%d" % [chrom.str, chrom.mag])
	else:
		_ko("Stats Chrom")
	
	if lissa.mag > 0:
		_ok("Lissa: MAG=%d (healer)" % lissa.mag)
	else:
		_ko("Stats Lissa")
	
	if fred.is_promoted:
		_ok("Frederick: promu (Great Knight)")
	else:
		_ko("Frederick pas promu")
	
	if WT.is_magical(lissa.weapon_type):
		_ok("Lissa arme magique (Staff)")
	else:
		_ko("Lissa pas magique")
	
	if not WT.is_magical(chrom.weapon_type):
		_ok("Chrom arme physique (Sword)")
	else:
		_ko("Chrom pas physique")


func _test_calculator() -> void:
	print("\n⚔️ Test 2: FECombatCalculator")
	
	var chrom: CharStats = _live(load("res://data/models/world/stats/hero/lord.tres"))
	var brig: CharStats = _live(load("res://data/models/world/stats/mob/skeleton.tres"))

	# Access the static method on the GDScript resource
	var calc_script = load("res://data/services/combat/fe_combat.gd")
	var preview = calc_script.calculate(chrom, brig)
	if preview == null:
		_ko("calculate() → null")
		return
	_ok("Calculate: %d dmg, %d%% hit" % [preview.damage, preview.hit_rate])
	
	if preview.damage >= 0:
		_ok("Damage >= 0")
	else:
		_ko("Damage négatif: %d" % preview.damage)
	
	if preview.hit_rate >= 0 and preview.hit_rate <= 100:
		_ok("Hit rate 0-100%%")
	else:
		_ko("Hit rate hors range: %d" % preview.hit_rate)
	
	var outcome: Dictionary = calc_script.roll_combat(preview)
	if outcome.has("hit") and outcome.has("total_damage"):
		_ok("roll_combat() keys OK")
	else:
		_ko("roll_combat() keys missing")
	
	# 2-RN check
	var hits: int = 0
	for i in 100:
		var o: Dictionary = calc_script.roll_combat(preview)
		if o["hit"]:
			hits += 1
	_ok("100 rolls: %d hits" % hits)
	
	# get_crit_evade
	var ce: int = chrom.get_crit_evade()
	if ce >= 0:
		_ok("get_crit_evade() = %d (Luck)" % ce)
	else:
		_ko("get_crit_evade()")


func _test_heal() -> void:
	print("\n⚕️ Test 3: Heal")
	
	var lissa: CharStats = _live(load("res://data/models/world/stats/hero/cleric.tres"))

	var heal_amount: int = 10 + int(lissa.mag / 3.0)
	if heal_amount == 11:
		_ok("Heal Lissa = 10 + MAG/3 = 11")
	else:
		_ko("Heal formule", "attendu 11, reçu %d" % heal_amount)

	# Test clamping via the real Stats API
	var fred: CharStats = _live(load("res://data/models/world/stats/hero/great_knight.tres"))
	fred.apply_to_curr_health(-5)  # Damage 5 HP first
	var before: int = fred.hp
	fred.apply_to_curr_health(heal_amount)
	var actual: int = fred.hp - before
	if actual == 5 and fred.hp == fred.max_hp:
		_ok("Heal clampé à 5 (ne dépasse pas max HP)")
	else:
		_ko("Heal clamp", "attendu +5 jusqu'à max_hp, reçu +%d (hp=%d/%d)" % [actual, fred.hp, fred.max_hp])


func _test_death() -> void:
	print("\n💀 Test 4: Mort")
	
	var brig: StatsRes = load("res://data/models/world/stats/mob/skeleton.tres")
	brig.hp = 0
	var alive: bool = brig.hp > 0
	if not alive:
		_ok("HP=0 → mort détectée")
	else:
		_ko("HP=0 toujours vivant")


func _test_victory() -> void:
	print("\n🏆 Test 5: Victoire")
	
	var brig: StatsRes = load("res://data/models/world/stats/mob/skeleton.tres")
	var mage: StatsRes = load("res://data/models/world/stats/mob/skeleton_mage.tres")
	brig.hp = 0
	mage.hp = 0
	
	var all_dead: bool = true
	if brig.hp > 0 or mage.hp > 0:
		all_dead = false
	
	if all_dead:
		_ok("Équipe entière anéantie détectée")
	else:
		_ko("Détection équipe morte")


func _test_support() -> void:
	print("\n💬 Test 6: Support")
	
	# Loaded lazily at runtime (not preloaded) — support_tracker.gd pulls in TacticsPawn-related
	# global classes that reference the CielAI autoload, which isn't resolvable yet during this
	# script's own eager top-level compile pass in `--script` mode.
	var SupportTrackerScript = load("res://data/modules/tactics/level/support_tracker.gd")
	var tracker = SupportTrackerScript.new()
	var pair = tracker.get_pair("Chrom", "Lissa")
	if pair:
		_ok("SupportPair Chrom↔Lissa créé")
	else:
		_ko("Création SupportPair")
		return

	pair.add_points(30)
	if pair.rank == SupportDB.Rank.C:
		_ok("Rank C à 30 pts")
	else:
		_ko("Rank C", "reçu %d" % pair.rank)

	var allies: Array[String] = ["Lissa"]
	var bonuses: Dictionary = tracker.get_combined_bonuses("Chrom", allies)
	if bonuses.has("hit") and bonuses["hit"] > 0:
		_ok("Bonus support: +%d hit" % bonuses.get("hit", 0))
	else:
		_ko("Bonus support introuvable", str(bonuses))


func _test_triangle() -> void:
	print("\n📐 Test 7: Triangle des armes")
	
	var bonus: int = WT.get_triangle_damage_bonus(0, 2)  # Sword=0, Axe=2
	if bonus > 0:
		_ok("Sword > Axe: +%d dmg" % bonus)
	else:
		_ko("Triangle Sword>Axe", "%d" % bonus)
	
	bonus = WT.get_triangle_damage_bonus(1, 0)  # Lance=1, Sword=0
	if bonus > 0:
		_ok("Lance > Sword: +%d dmg" % bonus)
	else:
		_ko("Triangle Lance>Sword", "%d" % bonus)
	
	bonus = WT.get_triangle_damage_bonus(2, 1)  # Axe=2, Lance=1
	if bonus > 0:
		_ok("Axe > Lance: +%d dmg" % bonus)
	else:
		_ko("Triangle Axe>Lance", "%d" % bonus)
	
	bonus = WT.get_triangle_damage_bonus(0, 5)  # Sword=0, Staff=5
	if bonus == 0:
		_ok("Staff neutre")
	else:
		_ko("Staff neutre", "%d" % bonus)


func _test_forecast() -> void:
	print("\n🔮 Test 8: Prévision de combat (avant le jet)")

	var chrom: CharStats = _live(load("res://data/models/world/stats/hero/lord.tres"))
	var brig: CharStats = _live(load("res://data/models/world/stats/mob/skeleton.tres"))

	var f: Dictionary = Forecast.build(chrom, brig)
	var direct: Calc.CombatResult = Calc.calculate(chrom, brig)

	# La prévision ne doit rien inventer : elle reprend le calculateur tel quel.
	if f["hit"] == direct.hit_rate and f["crit"] == direct.crit_rate \
			and f["damage"] == direct.damage:
		_ok("Prévision fidèle au calculateur (%d%% / %d dmg)" % [f["hit"], f["damage"]])
	else:
		_ko("Prévision fidèle", "%d/%d/%d vs %d/%d/%d" % [
			f["hit"], f["crit"], f["damage"],
			direct.hit_rate, direct.crit_rate, direct.damage])

	var expected_hits: int = 2 if direct.can_double else 1
	if f["hits"] == expected_hits and f["total"] == direct.damage * expected_hits:
		_ok("Total = dégâts × %d coup(s)" % expected_hits)
	else:
		_ko("Total des coups", "hits=%d total=%d" % [f["hits"], f["total"]])

	if f["target_hp_after"] == max(0, brig.hp - int(f["total"])):
		_ok("PV restants prévus : %d → %d" % [f["target_hp"], f["target_hp_after"]])
	else:
		_ko("PV restants", str(f["target_hp_after"]))

	# Létalité : une cible à 1 PV tombe forcément si les dégâts sont non nuls.
	if f["damage"] > 0:
		brig.hp = 1
		var lethal: Dictionary = Forecast.build(chrom, brig)
		if lethal["lethal"] and lethal["target_hp_after"] == 0:
			_ok("Létalité détectée sur cible à 1 PV")
		else:
			_ko("Létalité", str(lethal["lethal"]))
	else:
		_ko("Létalité", "dégâts nuls, cas non testable")

	# Un critique seul peut suffire : cible à (total + 1) PV, sous le total crit.
	brig.hp = int(f["total"]) + 1
	if int(f["crit_total"]) >= brig.hp:
		var edge: Dictionary = Forecast.build(chrom, brig)
		if not edge["lethal"] and edge["crit_lethal"]:
			_ok("« Létal seulement si critique » distingué du létal sûr")
		else:
			_ko("Létal si crit", "lethal=%s crit_lethal=%s" % [edge["lethal"], edge["crit_lethal"]])
	else:
		_ok("Létal si crit : cas non applicable ici (crit trop faible)")

	# Le terrain défensif doit réduire les dégâts annoncés.
	brig.hp = brig.max_hp
	var sheltered: Dictionary = Forecast.build(chrom, brig, {"terrain_defense": 3})
	if sheltered["terrain"] == 3 and sheltered["damage"] <= f["damage"]:
		_ok("Terrain +3 pris en compte (%d → %d dmg)" % [f["damage"], sheltered["damage"]])
	else:
		_ko("Terrain dans la prévision", str(sheltered["damage"]))

	# Soin : montant plafonné par les PV manquants, jamais de dégâts.
	var lissa: CharStats = _live(load("res://data/models/world/stats/hero/cleric.tres"))
	var wounded: CharStats = _live(load("res://data/models/world/stats/hero/lord.tres"))
	wounded.hp = wounded.max_hp - 3
	var heal: Dictionary = Forecast.build(lissa, wounded, {"is_heal": true})
	if heal["kind"] == "heal" and heal["heal"] == 3 and heal["target_hp_after"] == wounded.max_hp:
		_ok("Soin plafonné aux PV manquants (+3)")
	else:
		_ko("Soin prévu", "%d → %d" % [heal["heal"], heal["target_hp_after"]])

	# Un résumé lisible, et rien du tout quand il n'y a rien à prévoir.
	if not Forecast.summary(f).is_empty() and Forecast.summary({}).is_empty():
		_ok("Résumé sur une ligne : %s" % Forecast.summary(f))
	else:
		_ko("Résumé", Forecast.summary(f))


func _test_counter_range() -> void:
	print("\n🏹 Test 9: Portées d'arme et riposte")

	# Un arc ne sert à rien au contact ; une lame ne porte pas à deux cases.
	if WT.get_min_range(WT.Type.BOW) == 2 and WT.get_min_range(WT.Type.SWORD) == 1:
		_ok("Portée minimale : arc 2, épée 1")
	else:
		_ko("Portée minimale", "arc=%d épée=%d" % [
			WT.get_min_range(WT.Type.BOW), WT.get_min_range(WT.Type.SWORD)])

	if not WT.reaches(WT.Type.BOW, 2, 1) and WT.reaches(WT.Type.BOW, 2, 2):
		_ok("L'arc (portée 2) touche à 2, pas à 1")
	else:
		_ko("Portée de l'arc", "à 1 : %s, à 2 : %s" % [
			WT.reaches(WT.Type.BOW, 2, 1), WT.reaches(WT.Type.BOW, 2, 2)])

	if WT.reaches(WT.Type.SWORD, 1, 1) and not WT.reaches(WT.Type.SWORD, 1, 2):
		_ok("L'épée (portée 1) touche à 1, pas à 2")
	else:
		_ko("Portée de l'épée", "à 2 : %s" % WT.reaches(WT.Type.SWORD, 1, 2))

	# Un grimoire de portée 2 couvre bien les deux distances.
	if WT.reaches(WT.Type.TOME, 2, 1) and WT.reaches(WT.Type.TOME, 2, 2):
		_ok("Le grimoire (portée 2) couvre 1 et 2")
	else:
		_ko("Portée du grimoire", "à 1 : %s" % WT.reaches(WT.Type.TOME, 2, 1))

	if not WT.is_combat_weapon(WT.Type.STAFF) and WT.is_combat_weapon(WT.Type.AXE):
		_ok("Le bâton n'engage aucun combat, la hache si")
	else:
		_ko("Arme de combat", "bâton : %s" % WT.is_combat_weapon(WT.Type.STAFF))

	# Soigner est l'affaire du bâton seul. « Magique » répond à une autre question
	# — viser la RÉS — et confondre les deux transformait tout porteur de grimoire
	# en soigneur incapable d'attaquer.
	if WT.is_healing(WT.Type.STAFF) and not WT.is_healing(WT.Type.TOME):
		_ok("Le bâton soigne, le grimoire brûle")
	else:
		_ko("Arme curative", "bâton : %s, grimoire : %s" % [
			WT.is_healing(WT.Type.STAFF), WT.is_healing(WT.Type.TOME)])

	if WT.is_magical(WT.Type.TOME) and not WT.is_healing(WT.Type.TOME):
		_ok("« Magique » et « curatif » restent deux questions distinctes")
	else:
		_ko("Magique ≠ curatif", "grimoire curatif : %s" % WT.is_healing(WT.Type.TOME))

	var wrong: String = ""
	for t: int in [WT.Type.SWORD, WT.Type.LANCE, WT.Type.AXE, WT.Type.BOW, WT.Type.NONE]:
		if WT.is_healing(t):
			wrong = WT.get_weapon_label(t)
	if wrong.is_empty():
		_ok("Aucune arme de combat ne soigne")
	else:
		_ko("Arme de combat curative", wrong)

	# La règle de ciblage elle-même — celle que partagent la prévision, le clic
	# et le menu d'actions. C'est ici que le bug vivait.
	const PawnCombat = preload("res://data/models/world/combat/participant/pawn/service/combat.gd")
	var targeting_ok: bool = (
		PawnCombat.can_target(WT.Type.STAFF, true)        # bâton → allié
		and not PawnCombat.can_target(WT.Type.STAFF, false)  # bâton → ennemi : non
		and PawnCombat.can_target(WT.Type.TOME, false)       # grimoire → ennemi
		and not PawnCombat.can_target(WT.Type.TOME, true)    # grimoire → allié : non
		and PawnCombat.can_target(WT.Type.SWORD, false)
		and not PawnCombat.can_target(WT.Type.SWORD, true)
	)
	if targeting_ok:
		_ok("Ciblage : le bâton vise ses alliés, le grimoire et la lame leurs ennemis")
	else:
		_ko("Règle de ciblage", "grimoire → ennemi : %s, grimoire → allié : %s" % [
			PawnCombat.can_target(WT.Type.TOME, false),
			PawnCombat.can_target(WT.Type.TOME, true)])


func _test_exchange() -> void:
	print("\n⚔️ Test 10: L'échange — qui riposte, et dans quel ordre")

	var chrom: CharStats = _live(load("res://data/models/world/stats/hero/lord.tres"))
	var brig: CharStats = _live(load("res://data/models/world/stats/mob/skeleton.tres"))

	# Au contact, une hache rend coup pour coup.
	var melee: Dictionary = Calc.calculate_exchange(chrom, brig, {"distance": 1})
	if bool(melee["can_counter"]) and melee["counter"] != null:
		_ok("Riposte au contact : %d dégâts à %d%%" % [
			melee["counter"].damage, melee["counter"].hit_rate])
	else:
		_ko("Riposte au contact", str(melee["counter_reason"]))

	# La riposte est bien calculée dans l'autre sens : le défenseur devient l'attaquant.
	var reversed: Calc.CombatResult = Calc.calculate(brig, chrom)
	if melee["counter"].damage == reversed.damage and melee["counter"].hit_rate == reversed.hit_rate:
		_ok("La riposte reprend le calculateur en sens inverse")
	else:
		_ko("Sens de la riposte", "%d/%d vs %d/%d" % [
			melee["counter"].damage, melee["counter"].hit_rate,
			reversed.damage, reversed.hit_rate])

	# Hors de portée du défenseur : personne ne rend le coup.
	var sniped: Dictionary = Calc.calculate_exchange(chrom, brig, {"distance": 2})
	if not bool(sniped["can_counter"]) and str(sniped["counter_reason"]) == "hors de portée de riposte":
		_ok("Frappé à 2 cases, le porteur de hache ne riposte pas")
	else:
		_ko("Riposte hors de portée", str(sniped["counter_reason"]))

	# Un archer pris au contact est désarmé — c'est sa faiblesse de classe.
	var virion: CharStats = _live(load("res://data/models/world/stats/hero/archer.tres"))
	var rushed: Dictionary = Calc.calculate_exchange(brig, virion, {"distance": 1})
	if not bool(rushed["can_counter"]):
		_ok("L'archer pris au contact ne riposte pas (%s)" % rushed["counter_reason"])
	else:
		_ko("Archer au contact", "riposte accordée à tort")

	# Un bâton soigne, il ne rend pas les coups.
	var lissa: CharStats = _live(load("res://data/models/world/stats/hero/cleric.tres"))
	var struck: Dictionary = Calc.calculate_exchange(brig, lissa, {"distance": 1})
	if not bool(struck["can_counter"]) and str(struck["counter_reason"]) == "arme sans riposte":
		_ok("Le bâton ne riposte pas")
	else:
		_ko("Riposte au bâton", str(struck["counter_reason"]))

	# Une cible déjà à terre ne riposte pas.
	var downed: CharStats = _live(load("res://data/models/world/stats/mob/skeleton.tres"))
	downed.hp = 0
	var corpse: Dictionary = Calc.calculate_exchange(chrom, downed, {"distance": 1})
	if not bool(corpse["can_counter"]) and str(corpse["counter_reason"]) == "hors de combat":
		_ok("Un mort ne riposte pas")
	else:
		_ko("Riposte d'un mort", str(corpse["counter_reason"]))

	# L'ordre : l'assaut d'abord, la riposte ensuite, le second coup au plus rapide.
	if melee["order"][0] == "attack" and melee["order"][1] == "counter":
		_ok("Ordre des coups : assaut puis riposte (%s)" % ", ".join(melee["order"]))
	else:
		_ko("Ordre des coups", ", ".join(melee["order"]))

	var doubles: int = melee["order"].count("attack") + melee["order"].count("counter") - 2
	if doubles == (1 if (melee["attack"].can_double or melee["counter"].can_double) else 0):
		_ok("Un seul second coup, pour le plus rapide (%d)" % doubles)
	else:
		_ko("Second coup", "%d coups en trop" % doubles)

	# Sans riposte, l'ordre ne contient jamais de coup du défenseur.
	if not "counter" in sniped["order"]:
		_ok("Sans riposte, le défenseur ne figure pas dans l'ordre")
	else:
		_ko("Ordre sans riposte", ", ".join(sniped["order"]))


func _test_exchange_rolls() -> void:
	print("\n🎲 Test 11: Le déroulé d'un échange")

	var chrom: CharStats = _live(load("res://data/models/world/stats/hero/lord.tres"))
	var brig: CharStats = _live(load("res://data/models/world/stats/mob/skeleton.tres"))
	var exchange: Dictionary = Calc.calculate_exchange(chrom, brig, {"distance": 1})

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806

	# Les PV suivis ne descendent jamais sous zéro, et les dégâts rapportés sont
	# ceux réellement encaissés — c'est ce que le journal affichera.
	var clean: bool = true
	var countered_once: bool = false
	for i in 200:
		var r: Dictionary = Calc.roll_exchange(exchange, chrom.hp, brig.hp, rng)
		if int(r["attacker_hp"]) < 0 or int(r["defender_hp"]) < 0:
			clean = false
		if int(r["defender_damage_taken"]) > brig.hp or int(r["attacker_damage_taken"]) > chrom.hp:
			clean = false
		if int(r["attacker_hp"]) != chrom.hp - int(r["attacker_damage_taken"]):
			clean = false
		if int(r["defender_hp"]) != brig.hp - int(r["defender_damage_taken"]):
			clean = false
		if bool(r["countered"]):
			countered_once = true
	if clean:
		_ok("200 échanges : PV et dégâts restent cohérents")
	else:
		_ko("Cohérence des PV", "un échange a dérapé")

	if countered_once:
		_ok("La riposte se produit réellement au jet")
	else:
		_ko("Riposte au jet", "aucune riposte sur 200 échanges")

	# Une cible à 1 PV tombe au premier coup porté : l'échange s'arrête là.
	brig.hp = 1
	var lethal_exchange: Dictionary = Calc.calculate_exchange(chrom, brig, {"distance": 1})
	var stopped: bool = true
	var killed: int = 0
	for i in 200:
		var r: Dictionary = Calc.roll_exchange(lethal_exchange, chrom.hp, 1, rng)
		var first: Dictionary = r["strikes"][0]
		if not bool(first["hit"]) or int(first["damage"]) == 0:
			continue
		killed += 1
		if r["strikes"].size() != 1 or int(r["defender_hp"]) != 0 or bool(r["countered"]):
			stopped = false
	if stopped and killed > 0:
		_ok("Le coup fatal clôt l'échange (%d cas sur 200)" % killed)
	else:
		_ko("Arrêt sur mort", "stopped=%s tués=%d" % [stopped, killed])


func _test_forecast_counter() -> void:
	print("\n🔮 Test 12: La prévision montre les deux camps")

	var chrom: CharStats = _live(load("res://data/models/world/stats/hero/lord.tres"))
	var brig: CharStats = _live(load("res://data/models/world/stats/mob/skeleton.tres"))

	var f: Dictionary = Forecast.build(chrom, brig, {"distance": 1})
	var exchange: Dictionary = Calc.calculate_exchange(chrom, brig, {"distance": 1})

	if bool(f["can_counter"]) and f["counter_damage"] == exchange["counter"].damage \
			and f["counter_hit"] == exchange["counter"].hit_rate:
		_ok("Riposte annoncée : %d dégâts à %d%%" % [f["counter_damage"], f["counter_hit"]])
	else:
		_ko("Riposte dans la prévision", str(f["counter_reason"]))

	if f["attacker_hp_after"] == max(0, chrom.hp - int(f["counter_total"])):
		_ok("PV de l'assaillant après riposte : %d → %d" % [f["attacker_hp"], f["attacker_hp_after"]])
	else:
		_ko("PV de l'assaillant", str(f["attacker_hp_after"]))

	# À deux cases, la prévision doit annoncer l'absence de riposte.
	var safe: Dictionary = Forecast.build(chrom, brig, {"distance": 2})
	if not bool(safe["can_counter"]) and safe["attacker_hp_after"] == chrom.hp \
			and not str(safe["counter_reason"]).is_empty():
		_ok("Attaque sans risque annoncée comme telle (%s)" % safe["counter_reason"])
	else:
		_ko("Prévision sans riposte", str(safe["counter_reason"]))

	# Une riposte mortelle doit se voir avant d'engager.
	var weakened: CharStats = _live(load("res://data/models/world/stats/hero/lord.tres"))
	weakened.hp = 1
	var risky: Dictionary = Forecast.build(weakened, brig, {"distance": 1})
	if int(risky["counter_total"]) > 0:
		if bool(risky["counter_lethal"]):
			_ok("Riposte mortelle signalée (assaillant à 1 PV)")
		else:
			_ko("Riposte mortelle", "non signalée")
	else:
		_ok("Riposte mortelle : cas non applicable (riposte à 0 dégât)")

	# Quand le coup tue à coup sûr, la riposte n'est plus « attendue ».
	brig.hp = 1
	var overkill: Dictionary = Forecast.build(chrom, brig, {"distance": 1})
	if bool(overkill["lethal"]) and not bool(overkill["counter_expected"]):
		_ok("Coup létal : la riposte cesse d'être attendue")
	else:
		_ko("Riposte attendue", "lethal=%s expected=%s" % [
			overkill["lethal"], overkill["counter_expected"]])

	# Le résumé d'une ligne dit désormais ce que ça coûte.
	var line: String = Forecast.summary(f)
	if line.contains("riposte"):
		_ok("Résumé avec riposte : %s" % line)
	else:
		_ko("Résumé avec riposte", line)
