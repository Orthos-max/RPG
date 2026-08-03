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
	# --- Pyramide de promotion embranchée & unités volantes ---
	MASTER_LORD = 16,
	BOW_KNIGHT = 17,
	SAGE = 18,
	PEGASUS_KNIGHT = 19,
	FALCON_KNIGHT = 20,
	WYVERN_RIDER = 21,
	WYVERN_LORD = 22,
}
#endregion

#region Class Definitions
## Chaque classe : { name, base, growth, weapons, promotions, promo_level, is_promoted, flying }
## `promotions` liste les classes avancées possibles (embranchement) : la première
## est la promotion par défaut, les suivantes sont proposées au joueur (ou à Ciel
## via la commande `promote`).
static var DATA: Dictionary = {
	Id.LORD: {
		"name": "Lord",
		"base": {"hp": 18, "str": 6, "mag": 1, "skl": 7, "spd": 7, "lck": 4, "def": 6, "res": 1, "mov": 5},
		"growth": {"hp": 80, "str": 60, "mag": 10, "skl": 60, "spd": 60, "lck": 70, "def": 50, "res": 20},
		"weapons": [WT.Type.SWORD],
		"promotions": [Id.GREAT_LORD, Id.MASTER_LORD],
		"promo_level": 10,
		"is_promoted": false,
		"flying": false,
	},
	Id.GREAT_LORD: {
		"name": "Great Lord",
		"base": {"hp": 22, "str": 8, "mag": 2, "skl": 9, "spd": 9, "lck": 5, "def": 8, "res": 3, "mov": 6},
		"growth": {"hp": 90, "str": 65, "mag": 10, "skl": 65, "spd": 65, "lck": 70, "def": 55, "res": 25},
		"weapons": [WT.Type.SWORD, WT.Type.LANCE],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.MASTER_LORD: {
		"name": "Master Lord",
		"base": {"hp": 21, "str": 7, "mag": 4, "skl": 11, "spd": 11, "lck": 7, "def": 7, "res": 6, "mov": 6},
		"growth": {"hp": 85, "str": 60, "mag": 30, "skl": 75, "spd": 75, "lck": 75, "def": 45, "res": 45},
		"weapons": [WT.Type.SWORD, WT.Type.TOME],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.CAVALIER: {
		"name": "Cavalier",
		"base": {"hp": 20, "str": 7, "mag": 0, "skl": 5, "spd": 6, "lck": 4, "def": 7, "res": 0, "mov": 7},
		"growth": {"hp": 80, "str": 55, "mag": 0, "skl": 50, "spd": 50, "lck": 45, "def": 50, "res": 10},
		"weapons": [WT.Type.SWORD, WT.Type.LANCE],
		"promotions": [Id.PALADIN, Id.GREAT_KNIGHT],
		"promo_level": 10,
		"is_promoted": false,
		"flying": false,
	},
	Id.PALADIN: {
		"name": "Paladin",
		"base": {"hp": 25, "str": 9, "mag": 1, "skl": 7, "spd": 8, "lck": 5, "def": 9, "res": 2, "mov": 8},
		"growth": {"hp": 90, "str": 60, "mag": 5, "skl": 55, "spd": 55, "lck": 50, "def": 55, "res": 15},
		"weapons": [WT.Type.SWORD, WT.Type.LANCE, WT.Type.AXE],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.ARCHER: {
		"name": "Archer",
		"base": {"hp": 18, "str": 5, "mag": 0, "skl": 8, "spd": 5, "lck": 5, "def": 5, "res": 2, "mov": 5},
		"growth": {"hp": 75, "str": 50, "mag": 0, "skl": 65, "spd": 45, "lck": 45, "def": 40, "res": 15},
		"weapons": [WT.Type.BOW],
		"promotions": [Id.SNIPER, Id.BOW_KNIGHT],
		"promo_level": 10,
		"is_promoted": false,
		"flying": false,
	},
	Id.SNIPER: {
		"name": "Sniper",
		"base": {"hp": 22, "str": 7, "mag": 0, "skl": 11, "spd": 7, "lck": 6, "def": 7, "res": 3, "mov": 6},
		"growth": {"hp": 80, "str": 55, "mag": 0, "skl": 70, "spd": 50, "lck": 50, "def": 45, "res": 20},
		"weapons": [WT.Type.BOW],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.BOW_KNIGHT: {
		"name": "Bow Knight",
		"base": {"hp": 23, "str": 7, "mag": 0, "skl": 9, "spd": 8, "lck": 6, "def": 7, "res": 3, "mov": 8},
		"growth": {"hp": 80, "str": 55, "mag": 0, "skl": 60, "spd": 60, "lck": 50, "def": 45, "res": 20},
		"weapons": [WT.Type.BOW, WT.Type.SWORD],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.CLERIC: {
		"name": "Cleric",
		"base": {"hp": 16, "str": 0, "mag": 4, "skl": 3, "spd": 4, "lck": 7, "def": 2, "res": 5, "mov": 5},
		"growth": {"hp": 65, "str": 10, "mag": 55, "skl": 40, "spd": 45, "lck": 65, "def": 25, "res": 50},
		"weapons": [WT.Type.STAFF],
		"promotions": [Id.WAR_CLERIC, Id.SAGE],
		"promo_level": 10,
		"is_promoted": false,
		"flying": false,
	},
	Id.WAR_CLERIC: {
		"name": "War Cleric",
		"base": {"hp": 20, "str": 5, "mag": 7, "skl": 5, "spd": 6, "lck": 8, "def": 5, "res": 7, "mov": 6},
		"growth": {"hp": 75, "str": 35, "mag": 60, "skl": 45, "spd": 50, "lck": 65, "def": 35, "res": 55},
		"weapons": [WT.Type.STAFF, WT.Type.AXE],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.SAGE: {
		"name": "Sage",
		"base": {"hp": 19, "str": 2, "mag": 9, "skl": 7, "spd": 7, "lck": 7, "def": 4, "res": 8, "mov": 6},
		"growth": {"hp": 70, "str": 15, "mag": 70, "skl": 55, "spd": 55, "lck": 60, "def": 30, "res": 60},
		"weapons": [WT.Type.TOME, WT.Type.STAFF],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.TACTICIAN: {
		"name": "Tactician",
		"base": {"hp": 18, "str": 5, "mag": 5, "skl": 5, "spd": 6, "lck": 5, "def": 5, "res": 4, "mov": 5},
		"growth": {"hp": 80, "str": 55, "mag": 55, "skl": 55, "spd": 55, "lck": 60, "def": 45, "res": 40},
		"weapons": [WT.Type.SWORD, WT.Type.TOME],
		"promotions": [Id.GRANDMASTER, Id.SAGE],
		"promo_level": 10,
		"is_promoted": false,
		"flying": false,
	},
	Id.GRANDMASTER: {
		"name": "Grandmaster",
		"base": {"hp": 22, "str": 7, "mag": 7, "skl": 7, "spd": 8, "lck": 6, "def": 7, "res": 6, "mov": 6},
		"growth": {"hp": 85, "str": 60, "mag": 60, "skl": 60, "spd": 60, "lck": 60, "def": 50, "res": 45},
		"weapons": [WT.Type.SWORD, WT.Type.TOME],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.BRIGAND: {
		"name": "Brigand",
		"base": {"hp": 18, "str": 5, "mag": 0, "skl": 2, "spd": 3, "lck": 1, "def": 3, "res": 0, "mov": 5},
		"growth": {"hp": 60, "str": 45, "mag": 0, "skl": 30, "spd": 25, "lck": 15, "def": 30, "res": 5},
		"weapons": [WT.Type.AXE],
		"promotions": [Id.BERSERKER],
		"promo_level": 10,
		"is_promoted": false,
		"flying": false,
	},
	Id.BERSERKER: {
		"name": "Berserker",
		"base": {"hp": 24, "str": 9, "mag": 0, "skl": 4, "spd": 6, "lck": 2, "def": 5, "res": 1, "mov": 6},
		"growth": {"hp": 75, "str": 60, "mag": 0, "skl": 35, "spd": 40, "lck": 20, "def": 35, "res": 10},
		"weapons": [WT.Type.AXE],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.DARK_MAGE: {
		"name": "Dark Mage",
		"base": {"hp": 16, "str": 0, "mag": 5, "skl": 3, "spd": 3, "lck": 2, "def": 2, "res": 4, "mov": 5},
		"growth": {"hp": 55, "str": 0, "mag": 55, "skl": 35, "spd": 30, "lck": 20, "def": 20, "res": 40},
		"weapons": [WT.Type.TOME],
		"promotions": [Id.SORCERER, Id.SAGE],
		"promo_level": 10,
		"is_promoted": false,
		"flying": false,
	},
	Id.SORCERER: {
		"name": "Sorcerer",
		"base": {"hp": 20, "str": 0, "mag": 8, "skl": 5, "spd": 5, "lck": 3, "def": 4, "res": 7, "mov": 6},
		"growth": {"hp": 60, "str": 0, "mag": 65, "skl": 40, "spd": 35, "lck": 25, "def": 25, "res": 50},
		"weapons": [WT.Type.TOME],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.KNIGHT: {
		"name": "Knight",
		"base": {"hp": 22, "str": 8, "mag": 0, "skl": 4, "spd": 2, "lck": 3, "def": 10, "res": 0, "mov": 4},
		"growth": {"hp": 90, "str": 60, "mag": 0, "skl": 45, "spd": 25, "lck": 35, "def": 60, "res": 10},
		"weapons": [WT.Type.LANCE],
		"promotions": [Id.GREAT_KNIGHT],
		"promo_level": 10,
		"is_promoted": false,
		"flying": false,
	},
	Id.GREAT_KNIGHT: {
		"name": "Great Knight",
		"base": {"hp": 26, "str": 10, "mag": 0, "skl": 6, "spd": 4, "lck": 4, "def": 13, "res": 2, "mov": 7},
		"growth": {"hp": 95, "str": 65, "mag": 0, "skl": 50, "spd": 30, "lck": 40, "def": 65, "res": 15},
		"weapons": [WT.Type.LANCE, WT.Type.AXE],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": false,
	},
	Id.PEGASUS_KNIGHT: {
		"name": "Pegasus Knight",
		"base": {"hp": 17, "str": 5, "mag": 1, "skl": 7, "spd": 9, "lck": 6, "def": 4, "res": 6, "mov": 7},
		"growth": {"hp": 65, "str": 45, "mag": 15, "skl": 60, "spd": 70, "lck": 60, "def": 30, "res": 55},
		"weapons": [WT.Type.LANCE],
		"promotions": [Id.FALCON_KNIGHT],
		"promo_level": 10,
		"is_promoted": false,
		"flying": true,
	},
	Id.FALCON_KNIGHT: {
		"name": "Falcon Knight",
		"base": {"hp": 21, "str": 7, "mag": 3, "skl": 9, "spd": 11, "lck": 7, "def": 6, "res": 9, "mov": 8},
		"growth": {"hp": 70, "str": 50, "mag": 25, "skl": 65, "spd": 70, "lck": 60, "def": 35, "res": 60},
		"weapons": [WT.Type.LANCE, WT.Type.STAFF],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": true,
	},
	Id.WYVERN_RIDER: {
		"name": "Wyvern Rider",
		"base": {"hp": 21, "str": 8, "mag": 0, "skl": 5, "spd": 5, "lck": 3, "def": 9, "res": 0, "mov": 7},
		"growth": {"hp": 80, "str": 60, "mag": 0, "skl": 45, "spd": 45, "lck": 30, "def": 55, "res": 10},
		"weapons": [WT.Type.AXE],
		"promotions": [Id.WYVERN_LORD],
		"promo_level": 10,
		"is_promoted": false,
		"flying": true,
	},
	Id.WYVERN_LORD: {
		"name": "Wyvern Lord",
		"base": {"hp": 25, "str": 10, "mag": 0, "skl": 7, "spd": 7, "lck": 4, "def": 12, "res": 3, "mov": 8},
		"growth": {"hp": 85, "str": 65, "mag": 0, "skl": 50, "spd": 50, "lck": 35, "def": 60, "res": 20},
		"weapons": [WT.Type.AXE, WT.Type.LANCE],
		"promotions": [],
		"promo_level": -1,
		"is_promoted": true,
		"flying": true,
	},
}
#endregion


## Get the name of a class by its ID
static func get_class_name(class_id: int) -> String:
	return DATA[class_id].get("name", "Unknown") if DATA.has(class_id) else "Unknown"


## Identifiant d'une classe depuis son nom affiché (-1 si inconnue, insensible à la casse)
static func get_class_id(class_name_str: String) -> int:
	var needle: String = class_name_str.strip_edges().to_lower()
	for id in DATA:
		if str(DATA[id].get("name", "")).to_lower() == needle:
			return id
	return -1


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


## Toutes les promotions possibles d'une classe (embranchements compris)
static func get_promotions(class_id: int) -> Array:
	return DATA[class_id].get("promotions", []) if DATA.has(class_id) else []


## Promotion par défaut (première branche), ou -1 si la classe est déjà au sommet
static func get_promotion(class_id: int) -> int:
	var branches: Array = get_promotions(class_id)
	return branches[0] if not branches.is_empty() else -1


## La classe a-t-elle plusieurs branches de promotion ?
static func has_branching_promotion(class_id: int) -> bool:
	return get_promotions(class_id).size() > 1


## Résout un choix de promotion (nom de classe ou identifiant) vers un Id valide.
## Renvoie -1 si le choix n'est pas une promotion légale de cette classe.
static func resolve_promotion(class_id: int, choice: Variant) -> int:
	var branches: Array = get_promotions(class_id)
	if branches.is_empty():
		return -1
	if choice == null or (typeof(choice) == TYPE_STRING and str(choice).strip_edges().is_empty()):
		return branches[0]
	var wanted: int = -1
	if typeof(choice) == TYPE_STRING:
		wanted = get_class_id(str(choice))
	else:
		wanted = int(choice)
	return wanted if wanted in branches else -1


## Check if a class is already promoted
static func is_promoted(class_id: int) -> bool:
	return DATA[class_id].get("is_promoted", false) if DATA.has(class_id) else false


## Check if a class can promote
static func can_promote(class_id: int) -> bool:
	return not get_promotions(class_id).is_empty()


## Get the promotion level requirement
static func get_promo_level(class_id: int) -> int:
	return DATA[class_id].get("promo_level", 10) if DATA.has(class_id) else 10


## La classe est-elle volante ? (cible privilégiée des arcs)
static func is_flying(class_id: int) -> bool:
	return DATA[class_id].get("flying", false) if DATA.has(class_id) else false


## Bonus de promotion : différence de stats de base entre la classe actuelle et la promue.
## Toujours positif ou nul, comme dans Fire Emblem.
static func promotion_bonuses(from_class: int, to_class: int) -> Dictionary:
	var old_base: Dictionary = get_base_stats(from_class)
	var new_base: Dictionary = get_base_stats(to_class)
	var bonuses: Dictionary = {}
	for stat in new_base:
		bonuses[stat] = maxi(0, int(new_base[stat]) - int(old_base.get(stat, 0)))
	return bonuses
