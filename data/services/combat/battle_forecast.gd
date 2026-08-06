class_name BattleForecast
extends RefCounted
## Prévision de combat — ce que le joueur voit avant d'engager.
##
## Le calculateur `FECombatCalculator` produit déjà hit/crit/dégâts/double avant
## le moindre jet de dés : cette classe se contente de le mettre en forme pour
## l'affichage (nombre de coups, total, PV restants, létalité). Logique pure,
## sans le moindre nœud, donc testable en headless.
##
## Les deux camps sont affichés : depuis que le moteur résout un échange complet
## ([method FECombatCalculator.calculate_exchange]), la riposte de la cible est
## une donnée d'avant-combat comme une autre — et c'est elle qui dit si engager
## coûte quelque chose.

const CombatCalc = preload("res://data/services/combat/fe_combat.gd")
const WT = preload("res://data/models/world/stats/weapon_type.gd")
const SkillDBRef = preload("res://data/models/world/stats/skill_db.gd")

## Soin de base d'un bâton, aligné sur `TacticsPawnCombatService._resolve_heal`.
const HEAL_BASE: int = 10
const HEAL_MAG_DIVIDER: float = 3.0


## Construit la prévision d'une action de `attacker` sur `defender`.
##
## @param attacker: Stats de l'unité qui engage
## @param defender: Stats de la cible
## @param opts: {"support": Dictionary (assaillant), "terrain_defense": int (cible),
##               "defender_support": Dictionary, "attacker_terrain": int,
##               "distance": int, "is_heal": bool}
## @return: dictionnaire d'affichage (voir `_empty()` pour les clés)
static func build(attacker: Stats, defender: Stats, opts: Dictionary = {}) -> Dictionary:
	var out: Dictionary = _empty()
	if not attacker or not defender:
		return out

	out["attacker_name"] = _name_of(attacker)
	out["defender_name"] = _name_of(defender)
	out["target_hp"] = defender.hp
	out["target_max_hp"] = defender.max_hp
	out["target_hp_after"] = defender.hp
	out["attacker_hp"] = attacker.hp
	out["attacker_max_hp"] = attacker.max_hp
	out["attacker_hp_after"] = attacker.hp

	# Un soigneur qui vise un allié ne calcule pas de dégâts.
	if bool(opts.get("is_heal", false)):
		return _build_heal(attacker, defender, out)

	var support: Dictionary = opts.get("support", {})
	var terrain: int = int(opts.get("terrain_defense", 0))
	var exchange: Dictionary = CombatCalc.calculate_exchange(attacker, defender, {
		"attacker_support": support,
		"defender_support": opts.get("defender_support", {}),
		"attacker_terrain": int(opts.get("attacker_terrain", 0)),
		"defender_terrain": terrain,
		"distance": int(opts.get("distance", 1)),
	})
	var result: CombatCalc.CombatResult = exchange["attack"]

	out["kind"] = "attack"
	out["hit"] = result.hit_rate
	out["crit"] = result.crit_rate
	out["damage"] = result.damage
	out["hits"] = 2 if result.can_double else 1
	out["double"] = result.can_double
	out["total"] = result.damage * out["hits"]
	# Pire cas pour la cible : le premier coup critique, le second (s'il existe)
	# reste normal — exactement ce que fait `roll_combat`.
	out["crit_total"] = result.crit_damage + (result.damage if result.can_double else 0)
	out["magical"] = result.is_magical
	out["effective"] = result.is_effective
	out["effective_mult"] = result.effective_mult
	out["triangle"] = result.triangle_bonus
	out["triangle_hit"] = result.triangle_hit
	out["terrain"] = result.terrain_defense
	out["defense_used"] = result.defense_used
	out["support_hit"] = int(support.get("hit", 0))
	out["support_crit"] = int(support.get("crit", 0))

	out["target_hp_after"] = maxi(0, defender.hp - int(out["total"]))
	out["lethal"] = int(out["total"]) >= defender.hp
	out["crit_lethal"] = int(out["crit_total"]) >= defender.hp

	for proc: Dictionary in result.procs:
		out["procs"].append({
			"id": str(proc["id"]),
			"name": SkillDBRef.get_skill_name(str(proc["id"])),
			"chance": int(proc["chance"]),
		})

	_fill_counter(exchange, attacker, out)
	return out


## Volet « riposte » de la prévision : ce que l'engagement coûte à l'assaillant.
##
## `counter_expected` distingue deux silences : la cible ne peut pas riposter
## (portée, bâton), ou elle ne devrait pas en avoir l'occasion parce que le coup
## la tue à coup sûr. Le second reste une prévision, pas une garantie — un coup
## manqué lui rend sa riposte.
static func _fill_counter(exchange: Dictionary, attacker: Stats, out: Dictionary) -> Dictionary:
	out["counter_reason"] = str(exchange.get("counter_reason", ""))
	if not bool(exchange.get("can_counter", false)):
		return out

	var counter: CombatCalc.CombatResult = exchange["counter"]
	var hits: int = 2 if counter.can_double else 1
	var total: int = counter.damage * hits

	out["can_counter"] = true
	out["counter_expected"] = not bool(out["lethal"])
	out["counter_hit"] = counter.hit_rate
	out["counter_crit"] = counter.crit_rate
	out["counter_damage"] = counter.damage
	out["counter_hits"] = hits
	out["counter_double"] = counter.can_double
	out["counter_total"] = total
	out["counter_crit_total"] = counter.crit_damage + (counter.damage if counter.can_double else 0)
	out["attacker_hp_after"] = maxi(0, attacker.hp - total)
	out["counter_lethal"] = total >= attacker.hp
	out["counter_crit_lethal"] = int(out["counter_crit_total"]) >= attacker.hp
	return out


## Prévision d'un soin : montant réel (plafonné par les PV manquants).
static func _build_heal(healer: Stats, target: Stats, out: Dictionary) -> Dictionary:
	var raw: int = HEAL_BASE + int(healer.mag / HEAL_MAG_DIVIDER)
	var actual: int = mini(raw, maxi(0, target.max_hp - target.hp))
	out["kind"] = "heal"
	out["heal"] = actual
	out["hit"] = 100
	out["target_hp_after"] = mini(target.max_hp, target.hp + actual)
	return out


## Résumé sur une ligne — utilisé par l'UI compacte, les logs et les tests.
static func summary(forecast: Dictionary) -> String:
	if forecast.is_empty() or str(forecast.get("kind", "")) == "none":
		return ""
	if str(forecast["kind"]) == "heal":
		return "Soin +%d PV → %d/%d" % [
			forecast["heal"], forecast["target_hp_after"], forecast["target_max_hp"]
		]

	var line: String = "%d dmg" % forecast["total"]
	if bool(forecast["double"]):
		line += " (%d ×2)" % forecast["damage"]
	line += " | %d%% | crit %d%%" % [forecast["hit"], forecast["crit"]]
	if bool(forecast["lethal"]):
		line += " | ☠ LÉTAL"
	elif bool(forecast["crit_lethal"]):
		line += " | ☠ si crit"

	if bool(forecast.get("can_counter", false)):
		line += " | riposte %d" % forecast["counter_total"]
		if bool(forecast["counter_double"]):
			line += " (%d ×2)" % forecast["counter_damage"]
		line += " à %d%%" % forecast["counter_hit"]
		if bool(forecast["counter_lethal"]):
			line += " ☠"
	else:
		line += " | sans riposte"
	return line


## Squelette de prévision — toutes les clés existent toujours, l'UI n'a jamais
## à tester leur présence.
static func _empty() -> Dictionary:
	return {
		"kind": "none",
		"attacker_name": "",
		"defender_name": "",
		"hit": 0,
		"crit": 0,
		"damage": 0,
		"hits": 0,
		"total": 0,
		"crit_total": 0,
		"double": false,
		"magical": false,
		"effective": false,
		"effective_mult": 1,
		"triangle": 0,
		"triangle_hit": 0,
		"terrain": 0,
		"defense_used": 0,
		"support_hit": 0,
		"support_crit": 0,
		"heal": 0,
		"target_hp": 0,
		"target_max_hp": 0,
		"target_hp_after": 0,
		"lethal": false,
		"crit_lethal": false,
		"procs": [],
		# --- Riposte de la cible ---
		"attacker_hp": 0,
		"attacker_max_hp": 0,
		"attacker_hp_after": 0,
		"can_counter": false,
		"counter_expected": false,
		"counter_reason": "",
		"counter_hit": 0,
		"counter_crit": 0,
		"counter_damage": 0,
		"counter_hits": 0,
		"counter_double": false,
		"counter_total": 0,
		"counter_crit_total": 0,
		"counter_lethal": false,
		"counter_crit_lethal": false,
	}


static func _name_of(s: Stats) -> String:
	if not s:
		return ""
	return s.override_name if s.override_name != "" else s.expertise
