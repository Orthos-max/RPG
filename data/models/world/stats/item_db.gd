class_name ItemDB
extends RefCounted
## Consommables transportés par les unités (inventaire limité, façon Fire Emblem).
##
## Volontairement minimal : un objet = un effet immédiat. Les armes restent
## portées par [StatsResource] (weapon_type / weapon_might).

enum Kind {
	HEAL = 0,  ## Rend des PV
	BUFF = 1,  ## Bonus de stat temporaire (en tours)
}

## Nombre maximum d'objets transportés par unité
const MAX_ITEMS: int = 5

static var DATA: Dictionary = {
	"Vulnerary": {"kind": Kind.HEAL, "amount": 10, "label": "Potion"},
	"Concoction": {"kind": Kind.HEAL, "amount": 20, "label": "Élixir mineur"},
	"Elixir": {"kind": Kind.HEAL, "amount": 999, "label": "Élixir"},
	"Def Tonic": {"kind": Kind.BUFF, "stat": "def", "amount": 2, "turns": 2, "label": "Tonique de défense"},
	"Spd Tonic": {"kind": Kind.BUFF, "stat": "spd", "amount": 2, "turns": 2, "label": "Tonique de vitesse"},
}


## L'objet existe-t-il ?
static func exists(item_name: String) -> bool:
	return DATA.has(canonical_name(item_name))


## Nom canonique (insensible à la casse) — "" si inconnu.
static func canonical_name(item_name: String) -> String:
	var needle: String = item_name.strip_edges().to_lower()
	for key: String in DATA:
		if key.to_lower() == needle:
			return key
	return ""


## Définition d'un objet (dictionnaire vide si inconnu).
static func get_item(item_name: String) -> Dictionary:
	var key: String = canonical_name(item_name)
	return DATA[key] if not key.is_empty() else {}


## Liste des objets connus
static func all_items() -> Array:
	var names: Array = DATA.keys()
	names.sort()
	return names
