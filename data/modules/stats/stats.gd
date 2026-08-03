class_name Stats
extends Node
## Fire Emblem stats container for a character instance
## Imports data from StatsResource and tracks current HP, EXP, level-ups, etc.

const WT = preload("res://data/models/world/stats/weapon_type.gd")
const ClassDataDB = preload("res://data/models/world/stats/class_data.gd")
const ITEMS = preload("res://data/models/world/stats/item_db.gd")

#region Identity
var override_name: String
var expertise: String
var character_class: int = 0  ## ClassDB.Id
var level: int = 1
var exp: int = 0              ## Current EXP
var is_promoted: bool = false
var sprite: String
#endregion

#region FE Core Stats
var hp: int           ## Current HP
var max_hp: int       ## Maximum HP
var str: int          ## Strength
var mag: int          ## Magic
var skl: int          ## Skill
var spd: int          ## Speed
var lck: int          ## Luck
var def: int          ## Defense
var res: int          ## Resistance
#endregion

#region Mobility & Weapon
var movement: int     ## Movement points
var jump: int         ## Jump height
var attack_range: int ## Attack range
var weapon_type: int  ## WT.Type enum
var weapon_might: int ## Base weapon damage
#endregion

#region Legacy (for template compatibility)
var attack_power: int ## Flat attack power (computed in FE)
var max_health: int:  ## Alias for max_hp
	get: return max_hp
var curr_health: int: ## Alias for hp
	get: return hp
#endregion

#region Inventaire & états temporaires
## Consommables transportés (noms connus de [ItemDB])
var items: Array = []
## Bonus temporaires en cours : [{stat, amount, turns}]
var _active_buffs: Array = []
#endregion

#region Growth Rates
var hp_growth: int
var str_growth: int
var mag_growth: int
var skl_growth: int
var spd_growth: int
var lck_growth: int
var def_growth: int
var res_growth: int
#endregion


## Initialize stats from a StatsResource
func import_stats(stats: StatsResource) -> void:
	# Identity
	override_name = stats.override_name
	expertise = stats.expertise
	character_class = stats.character_class
	level = stats.level
	exp = stats.exp
	is_promoted = stats.is_promoted
	sprite = stats.sprite
	
	# Core FE stats
	max_hp = stats.hp
	hp = max_hp
	str = stats.str
	mag = stats.mag
	skl = stats.skl
	spd = stats.spd
	lck = stats.lck
	def = stats.def
	res = stats.res
	
	# Mobility & weapon
	movement = stats.movement
	stats.set_jump()
	jump = stats.jump
	attack_range = stats.attack_range
	weapon_type = stats.weapon_type
	weapon_might = stats.weapon_might
	
	# Growth rates
	hp_growth = stats.hp_growth
	str_growth = stats.str_growth
	mag_growth = stats.mag_growth
	skl_growth = stats.skl_growth
	spd_growth = stats.spd_growth
	lck_growth = stats.lck_growth
	def_growth = stats.def_growth
	res_growth = stats.res_growth

	# Inventaire
	items = []
	var res_items: Variant = stats.get("items")
	if res_items is Array:
		for i in res_items:
			if items.size() < ITEMS.MAX_ITEMS:
				items.append(str(i))

	# Croissances de classe : par défaut, class_data.gd fait autorité (P1).
	if stats.get("use_class_growths") == null or bool(stats.use_class_growths):
		apply_class_growths(character_class)

	# Legacy compat
	attack_power = stats.get_total_attack()


## Aligne les taux de croissance sur ceux de la classe donnée.
## Sans effet si la classe est inconnue de [ClassDataDB].
func apply_class_growths(class_id: int) -> bool:
	var growths: Dictionary = ClassDataDB.get_growths(class_id)
	if growths.is_empty():
		return false
	hp_growth = int(growths.get("hp", hp_growth))
	str_growth = int(growths.get("str", str_growth))
	mag_growth = int(growths.get("mag", mag_growth))
	skl_growth = int(growths.get("skl", skl_growth))
	spd_growth = int(growths.get("spd", spd_growth))
	lck_growth = int(growths.get("lck", lck_growth))
	def_growth = int(growths.get("def", def_growth))
	res_growth = int(growths.get("res", res_growth))
	return true


## Taux de croissance effectifs, sous forme de dictionnaire.
func get_growths() -> Dictionary:
	return {
		"hp": hp_growth, "str": str_growth, "mag": mag_growth, "skl": skl_growth,
		"spd": spd_growth, "lck": lck_growth, "def": def_growth, "res": res_growth,
	}


## Apply damage or healing. Negative value = damage, positive = healing.
func apply_to_curr_health(amount: int) -> void:
	print("Target initial health: ", hp, " - Applying: ", amount)
	hp = clamp(hp + amount, 0, max_hp)
	print("Target final health: ", hp)


## Get the effective attack stat (Str for physical, Mag for magical)
func get_attack_stat() -> int:
	if WT.is_magical(weapon_type):
		return mag
	return str


## Get total attack power (stat + weapon might)
func get_total_attack() -> int:
	return get_attack_stat() + weapon_might


## Get base hit rate
func get_base_hit() -> int:
	return skl * 2 + int(lck / 2.0)


## Get avoid rate
func get_avoid() -> int:
	return spd * 2 + lck


## Get critical hit rate
func get_crit() -> int:
	return int(skl / 2.0)


## Get critical evade (reduces enemy crit rate)
func get_crit_evade() -> int:
	return lck


## Get attack speed
func get_attack_speed() -> int:
	return spd


#region Inventaire
## Ajoute un consommable (refusé si inconnu ou inventaire plein).
func add_item(item_name: String) -> bool:
	var key: String = ITEMS.canonical_name(item_name)
	if key.is_empty() or items.size() >= ITEMS.MAX_ITEMS:
		return false
	items.append(key)
	return true


## L'unité transporte-t-elle cet objet ?
func has_item(item_name: String) -> bool:
	var key: String = ITEMS.canonical_name(item_name)
	return not key.is_empty() and key in items


## Consomme un objet de l'inventaire.
## [returns] {ok: bool, item: String, effect: String, amount: int, reason: String}
func use_item(item_name: String) -> Dictionary:
	var key: String = ITEMS.canonical_name(item_name)
	if key.is_empty():
		return {"ok": false, "reason": "objet inconnu : %s" % item_name}
	if not key in items:
		return {"ok": false, "reason": "%s ne transporte pas de %s" % [
			override_name if override_name else expertise, key
		]}

	var item: Dictionary = ITEMS.get_item(key)
	items.erase(key)

	match int(item.get("kind", ITEMS.Kind.HEAL)):
		ITEMS.Kind.HEAL:
			var before: int = hp
			apply_to_curr_health(int(item.get("amount", 10)))
			return {"ok": true, "item": key, "effect": "heal",
				"amount": hp - before, "reason": ""}
		ITEMS.Kind.BUFF:
			var stat: String = str(item.get("stat", "def"))
			var amount: int = int(item.get("amount", 2))
			apply_buff(stat, amount, int(item.get("turns", 2)))
			return {"ok": true, "item": key, "effect": "buff",
				"amount": amount, "stat": stat, "reason": ""}

	return {"ok": false, "reason": "effet non supporté"}
#endregion


#region Bonus temporaires
## Applique un bonus de stat pour un nombre de tours donné (garde, tonique…).
func apply_buff(stat: String, amount: int, turns: int = 1) -> void:
	if not stat in ["str", "mag", "skl", "spd", "lck", "def", "res"]:
		return
	set(stat, int(get(stat)) + amount)
	_active_buffs.append({"stat": stat, "amount": amount, "turns": turns})
	attack_power = get_total_attack()


## Fait vieillir les bonus d'un tour et retire ceux qui expirent.
func tick_buffs() -> void:
	var still_active: Array = []
	for buff: Dictionary in _active_buffs:
		buff["turns"] = int(buff["turns"]) - 1
		if int(buff["turns"]) > 0:
			still_active.append(buff)
		else:
			set(str(buff["stat"]), int(get(str(buff["stat"]))) - int(buff["amount"]))
	_active_buffs = still_active
	attack_power = get_total_attack()


## Bonus temporaires en cours (lecture seule, pour l'UI et l'export CielAI).
func active_buffs() -> Array:
	return _active_buffs.duplicate(true)
#endregion


## Grant EXP to this character. Automatically checks for level up.
## [param rng] RNG optionnel : passer un générateur graine fixe rend la montée
## de niveau déterministe (utilisé par les tests headless).
## Returns: { gained_exp, leveled_up, new_level, stat_gains }
func gain_exp(amount: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var gained: int = amount
	exp += gained
	
	var result: Dictionary = {
		"gained_exp": gained,
		"leveled_up": false,
		"new_level": level,
		"stat_gains": {},
		"promoted": false,
	}
	
	# Check for level up (may trigger multiple if enough EXP)
	while EXPCalculator.can_level_up(level, exp):
		var needed: int = EXPCalculator.exp_for_next_level(level)
		exp -= needed
		var gains: Dictionary = _perform_level_up(rng)
		result["leveled_up"] = true
		result["new_level"] = level
		# Merge stat gains across multiple levels
		for stat in gains:
			result["stat_gains"][stat] = result["stat_gains"].get(stat, 0) + gains[stat]
	
	return result


## Internal level up using RNG growth rates
## [param rng] Générateur optionnel (graine fixe = résultat reproductible)
func _perform_level_up(rng: RandomNumberGenerator = null) -> Dictionary:
	level += 1
	var gains: Dictionary = {}
	if not rng:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var growths = get_growths()

	var stat_count: int = 0
	for stat in growths:
		var roll = rng.randi_range(1, 100)
		if roll <= growths[stat]:
			gains[stat] = 1
			stat_count += 1
			match stat:
				"hp":  max_hp += 1; hp += 1
				"str": str += 1
				"mag": mag += 1
				"skl": skl += 1
				"spd": spd += 1
				"lck": lck += 1
				"def": def += 1
				"res": res += 1
		else:
			gains[stat] = 0
	
	# Update attack_power alias
	attack_power = get_total_attack()
	
	var char_name: String = override_name if override_name else expertise
	print_rich("[color=gold]⬆ LEVEL UP! %s → Lv.%d [+%d stats][/color]" % [char_name, level, stat_count])
	for s in gains:
		if gains[s] > 0:
			print("  +1 ", s.to_upper())
	
	# Promotion : automatique seulement s'il n'y a pas d'embranchement.
	# Sinon le choix revient au joueur (ou à Ciel via la commande `promote`).
	if can_promote_now() and not ClassDataDB.has_branching_promotion(character_class):
		promote_to(ClassDataDB.get_promotion(character_class))

	return gains


## L'unité remplit-elle les conditions de promotion ?
func can_promote_now() -> bool:
	return not is_promoted \
		and ClassDataDB.can_promote(character_class) \
		and level >= ClassDataDB.get_promo_level(character_class)


## Branches de promotion disponibles : [{id, name}]
func promotion_options() -> Array:
	var options: Array = []
	for id in ClassDataDB.get_promotions(character_class):
		options.append({"id": id, "name": ClassDataDB.get_class_name(id)})
	return options


## Promeut l'unité vers une classe avancée.
## [param choice] Id de classe, nom de classe, ou null pour la branche par défaut.
## [returns] { promoted: bool, from, to, bonuses, reason }
func promote_to(choice: Variant = null) -> Dictionary:
	var result: Dictionary = {"promoted": false, "from": character_class, "to": -1,
		"bonuses": {}, "reason": ""}

	if is_promoted:
		result["reason"] = "déjà promue"
		return result
	if not ClassDataDB.can_promote(character_class):
		result["reason"] = "classe sans promotion"
		return result
	if level < ClassDataDB.get_promo_level(character_class):
		result["reason"] = "niveau %d requis" % ClassDataDB.get_promo_level(character_class)
		return result

	var new_class: int = ClassDataDB.resolve_promotion(character_class, choice)
	if new_class == -1:
		result["reason"] = "promotion invalide pour %s" % ClassDataDB.get_class_name(character_class)
		return result

	var old_class: int = character_class
	var old_name: String = ClassDataDB.get_class_name(old_class)

	# Bonus de promotion = écart de stats de base entre l'ancienne et la nouvelle classe.
	var bonuses: Dictionary = ClassDataDB.promotion_bonuses(old_class, new_class)
	max_hp += int(bonuses.get("hp", 0))
	hp = mini(hp + int(bonuses.get("hp", 0)), max_hp)
	str += int(bonuses.get("str", 0))
	mag += int(bonuses.get("mag", 0))
	skl += int(bonuses.get("skl", 0))
	spd += int(bonuses.get("spd", 0))
	lck += int(bonuses.get("lck", 0))
	def += int(bonuses.get("def", 0))
	res += int(bonuses.get("res", 0))
	movement = int(ClassDataDB.get_base_stats(new_class).get("mov", movement))

	character_class = new_class
	is_promoted = true
	# La classe promue impose ses propres croissances.
	apply_class_growths(new_class)
	attack_power = get_total_attack()

	result["promoted"] = true
	result["to"] = new_class
	result["bonuses"] = bonuses

	var char_name: String = override_name if override_name else expertise
	print_rich("[color=lime]🎖 PROMOTION! %s: %s → %s![/color]" % [
		char_name, old_name, ClassDataDB.get_class_name(new_class)
	])
	return result


## Deprecated: direct level up without EXP. Use gain_exp() instead.
func level_up(rng: RandomNumberGenerator = null) -> Dictionary:
	return _perform_level_up(rng)
