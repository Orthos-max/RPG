class_name ClassDataDB
## Fire Emblem class database
## Defines all character classes, their base stats, growth rates,
## usable weapons, and promotion paths.

const WT = preload("res://data/models/world/stats/weapon_type.gd")

#region Class Enums
enum Id {
	LORD = 0,
	GREAT_LORD = 1,
	CAVALIER = 2,
	PALADIN = 3,
	ARCHER = 4,
	SNIPER = 5,
	CLERIC = 6,
	WAR_CLERIC = 7,
	TACTICIAN = 8,
	GRANDMASTER = 9,
	BRIGAND = 10,
	BERSERKER = 11,
	DARK_MAGE = 12,
	SORCERER = 13,
	KNIGHT = 14,
	GREAT_KNIGHT = 15,
}
#endregion

#region Class Definitions
## Each class: { name, base_stats, growths, usable_weapons, promotes_to, promo_level }
static var DATA: Dictionary = {
	Id.LORD: {
		"name": "Lord",
		"base": {"hp": 18, "str": 6, "mag": 1, "skl": 7, "spd": 7, "lck": 4, "def": 6, "res": 1, "mov": 5},
		"growth": {"hp": 80, "str": 60, "mag": 10, "skl": 60, "spd": 60, "lck": 70, "def": 50, "res": 20},
		"weapons": [WT.Type.SWORD],
		"promotes_to": Id.GREAT_LORD,
		"promo_level": 10,
		"is_promoted": false,
	},
	Id.GREAT_LORD: {
		"name": "Great Lord",
		"base": {"hp": 22, "str": 8, "mag": 2, "skl": 9, "spd": 9, "lck": 5, "def": 8, "res": 3, "mov": 6},
		"growth": {"hp": 90, "str": 65, "mag": 10, "skl": 65, "spd": 65, "lck": 70, "def": 55, "res": 25},
		"weapons": [WT.Type.SWORD, WT.Type.LANCE],
		"promotes_to": -1,
		"promo_level": -1,
		"is_promoted": true,
	},
	Id.CAVALIER: {
		"name": "Cavalier",
		"base": {"hp": 20, "str": 7, "mag": 0, "skl": 5, "spd": 6, "lck": 4, "def": 7, "res": 0, "mov": 7},
		"growth": {"hp": 80, "str": 55, "mag": 0, "skl": 50, "spd": 50, "lck": 45, "def": 50, "res": 10},
		"weapons": [WT.Type.SWORD, WT.Type.LANCE],
		"promotes_to": Id.PALADIN,
		"promo_level": 10,
		"is_promoted": false,
	},
	Id.PALADIN: {
		"name": "Paladin",
		"base": {"hp": 25, "str": 9, "mag": 1, "skl": 7, "spd": 8, "lck": 5, "def": 9, "res": 2, "mov": 8},
		"growth": {"hp": 90, "str": 60, "mag": 5, "skl": 55, "spd": 55, "lck": 50, "def": 55, "res": 15},
		"weapons": [WT.Type.SWORD, WT.Type.LANCE, WT.Type.AXE],
		"promotes_to": -1,
		"promo_level": -1,
		"is_promoted": true,
	},
	Id.ARCHER: {
		"name": "Archer",
		"base": {"hp": 18, "str": 5, "mag": 0, "skl": 8, "spd": 5, "lck": 5, "def": 5, "res": 2, "mov": 5},
		"growth": {"hp": 75, "str": 50, "mag": 0, "skl": 65, "spd": 45, "lck": 45, "def": 40, "res": 15},
		"weapons": [WT.Type.BOW],
		"promotes_to": Id.SNIPER,
		"promo_level": 10,
		"is_promoted": false,
	},
	Id.SNIPER: {
		"name": "Sniper",
		"base": {"hp": 22, "str": 7, "mag": 0, "skl": 11, "spd": 7, "lck": 6, "def": 7, "res": 3, "mov": 6},
		"growth": {"hp": 80, "str": 55, "mag": 0, "skl": 70, "spd": 50, "lck": 50, "def": 45, "res": 20},
		"weapons": [WT.Type.BOW],
		"promotes_to": -1,
		"promo_level": -1,
		"is_promoted": true,
	},
	Id.CLERIC: {
		"name": "Cleric",
		"base": {"hp": 16, "str": 0, "mag": 4, "skl": 3, "spd": 4, "lck": 7, "def": 2, "res": 5, "mov": 5},
		"growth": {"hp": 65, "str": 10, "mag": 55, "skl": 40, "spd": 45, "lck": 65, "def": 25, "res": 50},
		"weapons": [WT.Type.STAFF],
		"promotes_to": Id.WAR_CLERIC,
		"promo_level": 10,
		"is_promoted": false,
	},
	Id.WAR_CLERIC: {
		"name": "War Cleric",
		"base": {"hp": 20, "str": 5, "mag": 7, "skl": 5, "spd": 6, "lck": 8, "def": 5, "res": 7, "mov": 6},
		"growth": {"hp": 75, "str": 35, "mag": 60, "skl": 45, "spd": 50, "lck": 65, "def": 35, "res": 55},
		"weapons": [WT.Type.STAFF, WT.Type.AXE],
		"promotes_to": -1,
		"promo_level": -1,
		"is_promoted": true,
	},
	Id.TACTICIAN: {
		"name": "Tactician",
		"base": {"hp": 18, "str": 5, "mag": 5, "skl": 5, "spd": 6, "lck": 5, "def": 5, "res": 4, "mov": 5},
		"growth": {"hp": 80, "str": 55, "mag": 55, "skl": 55, "spd": 55, "lck": 60, "def": 45, "res": 40},
		"weapons": [WT.Type.SWORD, WT.Type.TOME],
		"promotes_to": Id.GRANDMASTER,
		"promo_level": 10,
		"is_promoted": false,
	},
	Id.GRANDMASTER: {
		"name": "Grandmaster",
		"base": {"hp": 22, "str": 7, "mag": 7, "skl": 7, "spd": 8, "lck": 6, "def": 7, "res": 6, "mov": 6},
		"growth": {"hp": 85, "str": 60, "mag": 60, "skl": 60, "spd": 60, "lck": 60, "def": 50, "res": 45},
		"weapons": [WT.Type.SWORD, WT.Type.TOME],
		"promotes_to": -1,
		"promo_level": -1,
		"is_promoted": true,
	},
	Id.BRIGAND: {
		"name": "Brigand",
		"base": {"hp": 18, "str": 5, "mag": 0, "skl": 2, "spd": 3, "lck": 1, "def": 3, "res": 0, "mov": 5},
		"growth": {"hp": 60, "str": 45, "mag": 0, "skl": 30, "spd": 25, "lck": 15, "def": 30, "res": 5},
		"weapons": [WT.Type.AXE],
		"promotes_to": Id.BERSERKER,
		"promo_level": 10,
		"is_promoted": false,
	},
	Id.BERSERKER: {
		"name": "Berserker",
		"base": {"hp": 24, "str": 9, "mag": 0, "skl": 4, "spd": 6, "lck": 2, "def": 5, "res": 1, "mov": 6},
		"growth": {"hp": 75, "str": 60, "mag": 0, "skl": 35, "spd": 40, "lck": 20, "def": 35, "res": 10},
		"weapons": [WT.Type.AXE],
		"promotes_to": -1,
		"promo_level": -1,
		"is_promoted": true,
	},
	Id.DARK_MAGE: {
		"name": "Dark Mage",
		"base": {"hp": 16, "str": 0, "mag": 5, "skl": 3, "spd": 3, "lck": 2, "def": 2, "res": 4, "mov": 5},
		"growth": {"hp": 55, "str": 0, "mag": 55, "skl": 35, "spd": 30, "lck": 20, "def": 20, "res": 40},
		"weapons": [WT.Type.TOME],
		"promotes_to": Id.SORCERER,
		"promo_level": 10,
		"is_promoted": false,
	},
	Id.SORCERER: {
		"name": "Sorcerer",
		"base": {"hp": 20, "str": 0, "mag": 8, "skl": 5, "spd": 5, "lck": 3, "def": 4, "res": 7, "mov": 6},
		"growth": {"hp": 60, "str": 0, "mag": 65, "skl": 40, "spd": 35, "lck": 25, "def": 25, "res": 50},
		"weapons": [WT.Type.TOME],
		"promotes_to": -1,
		"promo_level": -1,
		"is_promoted": true,
	},
	Id.KNIGHT: {
		"name": "Knight",
		"base": {"hp": 22, "str": 8, "mag": 0, "skl": 4, "spd": 2, "lck": 3, "def": 10, "res": 0, "mov": 4},
		"growth": {"hp": 90, "str": 60, "mag": 0, "skl": 45, "spd": 25, "lck": 35, "def": 60, "res": 10},
		"weapons": [WT.Type.LANCE],
		"promotes_to": Id.GREAT_KNIGHT,
		"promo_level": 10,
		"is_promoted": false,
	},
	Id.GREAT_KNIGHT: {
		"name": "Great Knight",
		"base": {"hp": 26, "str": 10, "mag": 0, "skl": 6, "spd": 4, "lck": 4, "def": 13, "res": 2, "mov": 7},
		"growth": {"hp": 95, "str": 65, "mag": 0, "skl": 50, "spd": 30, "lck": 40, "def": 65, "res": 15},
		"weapons": [WT.Type.LANCE, WT.Type.AXE],
		"promotes_to": -1,
		"promo_level": -1,
		"is_promoted": true,
	},
}
#endregion


## Get the name of a class by its ID
static func get_class_name(class_id: int) -> String:
	return DATA[class_id].get("name", "Unknown") if DATA.has(class_id) else "Unknown"


## Get base stats for a class
static func get_base_stats(class_id: int) -> Dictionary:
	return DATA[class_id].get("base", {}) if DATA.has(class_id) else {}


## Get growth rates for a class
static func get_growths(class_id: int) -> Dictionary:
	return DATA[class_id].get("growth", {}) if DATA.has(class_id) else {}


## Get usable weapons for a class
static func get_weapons(class_id: int) -> Array:
	return DATA[class_id].get("weapons", []) if DATA.has(class_id) else []


## Check if a class can use a specific weapon type
static func can_use_weapon(class_id: int, weapon_type: int) -> bool:
	return weapon_type in get_weapons(class_id)


## Get the promotion class (or -1 if none)
static func get_promotion(class_id: int) -> int:
	return DATA[class_id].get("promotes_to", -1) if DATA.has(class_id) else -1


## Check if a class is already promoted
static func is_promoted(class_id: int) -> bool:
	return DATA[class_id].get("is_promoted", false) if DATA.has(class_id) else false


## Check if a class can promote
static func can_promote(class_id: int) -> bool:
	return get_promotion(class_id) != -1


## Get the promotion level requirement
static func get_promo_level(class_id: int) -> int:
	return DATA[class_id].get("promo_level", 10) if DATA.has(class_id) else 10
