class_name Stats
extends Node
## Fire Emblem stats container for a character instance
## Imports data from StatsResource and tracks current HP, EXP, level-ups, etc.

const WT = preload("res://data/models/world/stats/weapon_type.gd")
const ClassDataDB = preload("res://data/models/world/stats/class_data.gd")

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
	
	# Legacy compat
	attack_power = stats.get_total_attack()


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


## Grant EXP to this character. Automatically checks for level up.
## Returns: { gained_exp, leveled_up, new_level, stat_gains }
func gain_exp(amount: int) -> Dictionary:
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
		var gains: Dictionary = _perform_level_up()
		result["leveled_up"] = true
		result["new_level"] = level
		# Merge stat gains across multiple levels
		for stat in gains:
			result["stat_gains"][stat] = result["stat_gains"].get(stat, 0) + gains[stat]
	
	return result


## Internal level up using RNG growth rates
func _perform_level_up() -> Dictionary:
	level += 1
	var gains: Dictionary = {}
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var growths = {
		"hp": hp_growth, "str": str_growth, "mag": mag_growth,
		"skl": skl_growth, "spd": spd_growth, "lck": lck_growth,
		"def": def_growth, "res": res_growth
	}
	
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
	
	# Check for promotion eligibility
	if not is_promoted and ClassDataDB.can_promote(character_class) and level >= ClassDataDB.get_promo_level(character_class):
		_promote()
	
	return gains


## Promote to the advanced class
func _promote() -> void:
	var new_class: int = ClassDataDB.get_promotion(character_class)
	if new_class == -1:
		return
	
	var old_name: String = ClassDataDB.get_class_name(character_class)
	character_class = new_class
	is_promoted = true
	
	var promo_data: Dictionary = ClassDataDB.DATA[new_class]
	var base: Dictionary = promo_data["base"]
	var growth: Dictionary = promo_data["growth"]
	
	# Apply promotion bonuses (difference between new base and old base)
	var old_base: Dictionary = ClassDataDB.get_base_stats(character_class)
	
	# Simply add promotion bonuses: +stat bonuses are (new_base - old_base) minimum
	# But since we're already leveled, just use the new growth rates and add flat bonuses
	movement = base.get("mov", movement)
	
	# Override growth rates with promoted class growths
	hp_growth = growth.get("hp", hp_growth)
	str_growth = growth.get("str", str_growth)
	mag_growth = growth.get("mag", mag_growth)
	skl_growth = growth.get("skl", skl_growth)
	spd_growth = growth.get("spd", spd_growth)
	lck_growth = growth.get("lck", lck_growth)
	def_growth = growth.get("def", def_growth)
	res_growth = growth.get("res", res_growth)
	
	var char_name: String = override_name if override_name else expertise
	print_rich("[color=lime]🎖 PROMOTION! %s: %s → %s![/color]" % [char_name, old_name, ClassDataDB.get_class_name(new_class)])


## Deprecated: direct level up without EXP. Use gain_exp() instead.
func level_up() -> Dictionary:
	return _perform_level_up()
