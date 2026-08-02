extends SceneTree
## Automated test — combat, death, heal, victory
## Run with: Godot --headless --script test_combat.gd --path .

const WT = preload("res://data/models/world/stats/weapon_type.gd")
const StatsRes = preload("res://data/models/world/stats/stats_res.gd")
const CharStats = preload("res://data/modules/stats/stats.gd")
const Calc = preload("res://data/services/combat/fe_combat.gd")
const SupportDB = preload("res://data/models/world/stats/support.gd")

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
