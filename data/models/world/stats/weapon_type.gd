class_name WeaponType
## Fire Emblem weapon types and triangle logic
## Sword > Axe > Lance > Sword (bonus +1 dmg, +15 hit)
## Bows: neutral vs melee, effective vs flying (phase 2)
## Tomes: magical damage (targets RES instead of DEF)
## Staves: no combat, support only

enum Type {
	SWORD = 0,
	LANCE = 1,
	AXE = 2,
	BOW = 3,
	TOME = 4,
	STAFF = 5,
	DRAGONSTONE = 6,
	BEASTSTONE = 7,
	BREATH = 8,
	NONE = 9
}

## Physical weapon types (use STR for damage)
const PHYSICAL_WEAPONS: Array[Type] = [
	Type.SWORD, Type.LANCE, Type.AXE, Type.BOW
]

## Magical weapon types (use MAG for damage, target RES)
const MAGICAL_WEAPONS: Array[Type] = [
	Type.TOME, Type.STAFF, Type.DRAGONSTONE, Type.BREATH
]

## Weapon triangle advantage map: attacker_type → disadvantaged type
const TRIANGLE: Dictionary = {
	Type.SWORD: Type.AXE,   # Sword beats Axe
	Type.AXE:   Type.LANCE,  # Axe beats Lance
	Type.LANCE:  Type.SWORD,  # Lance beats Sword
}

## Check if attacker has weapon triangle advantage over defender
static func has_advantage(attacker: Type, defender: Type) -> bool:
	return TRIANGLE.get(attacker, null) == defender

## Check if attacker has weapon triangle disadvantage
static func has_disadvantage(attacker: Type, defender: Type) -> bool:
	return TRIANGLE.get(defender, null) == attacker

## Get weapon triangle hit bonus (positive for advantage, negative for disadvantage, 0 for neutral)
static func get_triangle_hit_bonus(attacker: Type, defender: Type) -> int:
	if has_advantage(attacker, defender):
		return 15
	elif has_disadvantage(attacker, defender):
		return -15
	return 0

## Get weapon triangle damage bonus (positive for advantage, negative for disadvantage)
static func get_triangle_damage_bonus(attacker: Type, defender: Type) -> int:
	if has_advantage(attacker, defender):
		return 1
	elif has_disadvantage(attacker, defender):
		return -1
	return 0

## Check if a weapon type deals magical damage (targets RES)
static func is_magical(type: Type) -> bool:
	return type in MAGICAL_WEAPONS


## Check if a weapon type is physical (uses STR stat for damage, targets DEF)
static func is_physical(type: Type) -> bool:
	return type in PHYSICAL_WEAPONS


## Get the display name for a weapon type
static func get_weapon_name(type: Type) -> String:
	match type:
		Type.SWORD: return "Sword"
		Type.LANCE: return "Lance"
		Type.AXE: return "Axe"
		Type.BOW: return "Bow"
		Type.TOME: return "Tome"
		Type.STAFF: return "Staff"
		Type.DRAGONSTONE: return "Dragonstone"
		Type.BEASTSTONE: return "Beaststone"
		Type.BREATH: return "Breath"
		_: return "None"
