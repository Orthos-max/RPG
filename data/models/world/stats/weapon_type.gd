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

## Armes efficaces contre les unités volantes (dégâts d'arme triplés, façon FE)
const EFFECTIVE_VS_FLYING: Array[Type] = [Type.BOW]

## Armes qui ne frappent jamais au contact : un arc a besoin de recul.
## C'est ce qui rend un archer vulnérable à qui vient le chercher.
const RANGED_ONLY: Array[Type] = [Type.BOW]

## Armes qui n'engagent aucun combat (le bâton soigne, il ne riposte pas).
const NON_COMBAT: Array[Type] = [Type.STAFF, Type.NONE]

## Armes qui soignent au lieu de frapper. **Le bâton, et lui seul.**
##
## À ne pas confondre avec [method is_magical], qui répond à une tout autre
## question : « cette attaque vise-t-elle la RÉS plutôt que la DÉF ? ». Un
## grimoire est magique sans être un bâton — il brûle, il ne soigne pas.
const HEALING_WEAPONS: Array[Type] = [Type.STAFF]

## Multiplicateur appliqué au might de l'arme sur une cible sensible
const EFFECTIVE_MULTIPLIER: int = 3

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

## L'arme est-elle efficace contre les volants ? (arcs)
static func is_effective_vs_flying(type: Type) -> bool:
	return type in EFFECTIVE_VS_FLYING


## Multiplicateur de might contre une cible donnée.
## [param defender_flying] La cible est-elle une unité volante ?
## [returns] 3 si l'arme est efficace contre elle, 1 sinon.
static func get_effective_multiplier(type: Type, defender_flying: bool) -> int:
	if defender_flying and is_effective_vs_flying(type):
		return EFFECTIVE_MULTIPLIER
	return 1


## Portée minimale d'une arme : 1 si elle sert au contact, 2 pour un arc.
static func get_min_range(type: Type) -> int:
	return 2 if type in RANGED_ONLY else 1


## L'arme peut-elle engager un combat ? (un bâton, non)
static func is_combat_weapon(type: Type) -> bool:
	return not type in NON_COMBAT


## L'arme soigne-t-elle au lieu de frapper ?
##
## C'est cette question — et non [method is_magical] — qui décide de ce qu'une
## unité peut viser : un soigneur ne vise que ses alliés, un combattant que ses
## ennemis.
static func is_healing(type: Type) -> bool:
	return type in HEALING_WEAPONS


## L'arme atteint-elle une cible située à `distance` cases ?
##
## [param max_range] Portée de l'unité ([member StatsResource.attack_range]).
## Un arc de portée 2 ne touche qu'à 2 ; une lame de portée 1, qu'à 1 ; un
## grimoire de portée 2 couvre 1 et 2.
static func reaches(type: Type, max_range: int, distance: int) -> bool:
	if distance <= 0:
		return false
	return distance >= get_min_range(type) and distance <= maxi(1, max_range)


## Check if a weapon type deals magical damage (targets RES)
static func is_magical(type: Type) -> bool:
	return type in MAGICAL_WEAPONS


## Check if a weapon type is physical (uses STR stat for damage, targets DEF)
static func is_physical(type: Type) -> bool:
	return type in PHYSICAL_WEAPONS


## Nom français d'un type d'arme — ce que lit un joueur.
##
## [method get_weapon_name] reste en anglais : ce nom-là part dans `ai_state.json`
## et le pont CielAI en dépend.
static func get_weapon_label(type: Type) -> String:
	match type:
		Type.SWORD: return "Épée"
		Type.LANCE: return "Lance"
		Type.AXE: return "Hache"
		Type.BOW: return "Arc"
		Type.TOME: return "Grimoire"
		Type.STAFF: return "Bâton"
		Type.DRAGONSTONE: return "Pierre de dragon"
		Type.BEASTSTONE: return "Pierre de bête"
		Type.BREATH: return "Souffle"
		_: return "Mains nues"


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
