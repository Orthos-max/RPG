class_name ItemDB
extends RefCounted
## Consommables transportés par les unités (inventaire limité, façon Fire Emblem).
##
## Volontairement minimal : un objet = un effet immédiat. Les armes restent
## portées par [StatsResource] (weapon_type / weapon_might).

enum Kind {
	HEAL = 0,   ## Rend des PV
	BUFF = 1,   ## Bonus de stat temporaire (en tours)
	BOOST = 2,  ## Gain de stat permanent (utilisé depuis l'intendance)
}

## Nombre maximum d'objets transportés par unité
const MAX_ITEMS: int = 5

## Prix de revente, en fraction du prix d'achat
const RESALE_RATIO: float = 0.5

## Dossier des vignettes 32×32 découpées du pack Shikashi.
const ICON_DIR: String = "res://assets/textures/items/"

## Le catalogue.
##
## `icon` nomme la vignette du dossier [constant ICON_DIR] : les trois soins
## portent la fiole à croix verte (rouge, verte, dorée — du plus faible au plus
## fort), les toniques une fiole nue, et les gains permanents un objet à part,
## pour qu'on ne confonde pas d'un coup d'œil ce qui se boit et ce qui se garde.
static var DATA: Dictionary = {
	"Vulnerary": {"kind": Kind.HEAL, "amount": 10, "price": 100, "label": "Potion",
		"icon": "vulnerary"},
	"Concoction": {"kind": Kind.HEAL, "amount": 20, "price": 220, "label": "Élixir mineur",
		"icon": "concoction"},
	"Elixir": {"kind": Kind.HEAL, "amount": 999, "price": 500, "label": "Élixir",
		"icon": "elixir"},
	"Def Tonic": {"kind": Kind.BUFF, "stat": "def", "amount": 2, "turns": 2, "price": 180,
		"label": "Tonique de défense", "icon": "def_tonic"},
	"Spd Tonic": {"kind": Kind.BUFF, "stat": "spd", "amount": 2, "turns": 2, "price": 180,
		"label": "Tonique de vitesse", "icon": "spd_tonic"},
	"Energy Drop": {"kind": Kind.BOOST, "stat": "str", "amount": 2, "price": 900,
		"label": "Potion de force (+2 FOR définitif)", "icon": "energy_drop"},
	"Speedwing": {"kind": Kind.BOOST, "stat": "spd", "amount": 2, "price": 900,
		"label": "Aile de vitesse (+2 VIT définitif)", "icon": "speedwing"},
	"Dracoshield": {"kind": Kind.BOOST, "stat": "def", "amount": 2, "price": 900,
		"label": "Écaille de dragon (+2 DÉF définitif)", "icon": "dracoshield"},
	"Seraph Robe": {"kind": Kind.BOOST, "stat": "max_hp", "amount": 5, "price": 1000,
		"label": "Robe séraphique (+5 PV définitif)", "icon": "seraph_robe"},
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


## Prix d'achat (0 si l'objet est inconnu)
static func price(item_name: String) -> int:
	return int(get_item(item_name).get("price", 0))


## Prix de revente
static func resale_price(item_name: String) -> int:
	return int(floor(float(price(item_name)) * RESALE_RATIO))


## Libellé affichable
static func label(item_name: String) -> String:
	var item: Dictionary = get_item(item_name)
	return str(item.get("label", item_name))


## Chemin de la vignette de l'objet — "" s'il n'en a pas.
static func icon_path(item_name: String) -> String:
	var icon: String = str(get_item(item_name).get("icon", ""))
	return (ICON_DIR + icon + ".png") if not icon.is_empty() else ""


## L'objet donne-t-il un gain permanent ? (utilisable seulement hors combat)
static func is_boost(item_name: String) -> bool:
	return int(get_item(item_name).get("kind", Kind.HEAL)) == Kind.BOOST


## Objets vendus en boutique (tous ceux qui ont un prix), triés par prix
static func shop_stock() -> Array:
	var stock: Array = []
	for key: String in DATA:
		if price(key) > 0:
			stock.append(key)
	stock.sort_custom(func(a, b): return price(a) < price(b))
	return stock
