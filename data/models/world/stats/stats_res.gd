class_name StatsResource
extends Resource
## Fire Emblem-style character stats
## 8 core stats: HP, Str, Mag, Skl, Spd, Lck, Def, Res
## Plus movement, weapon type, attack range, class, and growth rates

const WT = preload("res://data/models/world/stats/weapon_type.gd")

#region Identity
@export var override_name: String = ""
@export var expertise: String = ""
@export_enum("Tank", "Flank", "Physical", "Distance", "Support") var strategy: int
@export var character_class: int = 0  # ClassDB.Id enum
@export var level: int = 1
@export var exp: int = 0  # Current EXP toward next level
@export_file("*.png") var sprite: String = "res://assets/textures/actor/"
@export var is_promoted: bool = false
#endregion

#region FE Core Stats
@export_category("FE Core Stats")
## Maximum health points
@export var hp: int = 20
## Strength — contributes to physical attack damage
@export var str: int = 5
## Magic — contributes to magical attack damage
@export var mag: int = 0
## Skill — affects hit rate and critical hit chance
@export var skl: int = 5
## Speed — determines double attacks and avoid
@export var spd: int = 5
## Luck — small influence on hit, avoid, and crit evade
@export var lck: int = 0
## Defense — reduces physical damage taken
@export var def: int = 3
## Resistance — reduces magical damage taken
@export var res: int = 0
#endregion

#region Mobility & Range
@export_category("Mobility & Range")
## Movement points (tiles the unit can traverse per turn)
@export var movement: int = 5
## Jump height, computed as floor(movement / 2)
@export var jump: float = 2.5
## Attack range in tiles (1 = melee, 2 = bows/magic, etc.)
@export var attack_range: int = 1
#endregion

#region Weapon
@export_category("Weapon")
## Weapon type from WeaponType.Type enum
@export var weapon_type: int = 0
## Weapon might (base damage added to Str or Mag)
@export var weapon_might: int = 5
#endregion

#region Growth Rates
@export_category("Growth Rates (%)")
## Chance (0-100) to gain HP on level up
@export var hp_growth: int = 50
## Chance (0-100) to gain Str on level up
@export var str_growth: int = 50
## Chance (0-100) to gain Mag on level up
@export var mag_growth: int = 50
## Chance (0-100) to gain Skl on level up
@export var skl_growth: int = 50
## Chance (0-100) to gain Spd on level up
@export var spd_growth: int = 50
## Chance (0-100) to gain Lck on level up
@export var lck_growth: int = 50
## Chance (0-100) to gain Def on level up
@export var def_growth: int = 50
## Chance (0-100) to gain Res on level up
@export var res_growth: int = 50
#endregion

#region Legacy aliases (for template compatibility)
## Legacy: alias for hp. Use hp instead.
@export_category("Legacy")
@export var max_health: int = 20
## Legacy: flat attack power, replaced by Str/Mag + weapon_might
@export var attack_power: int = 5
#endregion


#region Methods
## Calculates and sets jump height based on movement
func set_jump() -> void:
	jump = floor(movement / 2.0)

## Get the effective attack stat (Str for physical, Mag for magical)
func get_attack_stat() -> int:
	if WT.is_magical(weapon_type):
		return mag
	return str

## Get total attack power (stat + weapon might)
func get_total_attack() -> int:
	return get_attack_stat() + weapon_might

## Get hit rate (before weapon triangle)
func get_base_hit() -> int:
	return skl * 2 + int(lck / 2.0)

## Get avoid rate
func get_avoid() -> int:
	return spd * 2 + lck

## Get critical hit rate
func get_crit() -> int:
	return int(skl / 2.0)

## Get critical evade (dodge)
func get_crit_evade() -> int:
	return lck

## Get attack speed (determines double attacks)
func get_attack_speed() -> int:
	return spd
#endregion
