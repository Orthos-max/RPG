class_name WeaponDB
extends RefCounted
## Catalogue des armes — ce qu'une unité tient réellement en main.
##
## Jusqu'ici une unité portait deux chiffres nus ([member StatsResource.weapon_type]
## et [member StatsResource.weapon_might]) fixés une fois pour toutes dans sa
## fiche : le triangle des armes était calculé à chaque coup sans que personne
## puisse en décider. Une arme est désormais une donnée nommée, achetable,
## transportable et **échangeable avant l'assaut**.
##
## Logique pure : aucun nœud, aucune scène. C'est [Stats] qui applique une arme
## à une unité ([method Stats.equip]), et l'écran de préparation qui la choisit.

const WT = preload("res://data/models/world/stats/weapon_type.gd")

## Nombre d'armes transportées par unité. Volontairement plus étroit que
## l'inventaire de consommables : choisir son arme doit rester un arbitrage.
const MAX_WEAPONS: int = 3

## Prix de revente, en fraction du prix d'achat (aligné sur [ItemDB]).
const RESALE_RATIO: float = 0.5

## Le catalogue.
##
## `hit` et `crit` sont des **modificateurs** ajoutés aux valeurs de l'unité, et
## `weight` un malus de vitesse d'attaque amorti par la force (voir
## [method Stats.speed_penalty]) : une hache d'acier frappe fort, rate souvent et
## interdit le second coup à qui n'a pas les bras pour elle.
##
## `range` est la portée maximale ; la minimale découle du type d'arme
## ([method WeaponType.get_min_range]), c'est elle qui prive un arc de riposte
## au contact.
static var DATA: Dictionary = {
	# --- Lames ---
	"iron_sword": {"label": "Épée de fer", "type": WT.Type.SWORD,
		"might": 5, "range": 1, "hit": 0, "crit": 0, "weight": 5, "price": 300, "icon": "iron_sword"},
	"steel_sword": {"label": "Épée d'acier", "type": WT.Type.SWORD,
		"might": 8, "range": 1, "hit": -5, "crit": 0, "weight": 10, "price": 700, "icon": "steel_sword"},
	"rapier": {"label": "Rapière", "type": WT.Type.SWORD,
		"might": 5, "range": 1, "hit": 10, "crit": 5, "weight": 4, "price": 900, "icon": "rapier"},
	"killing_edge": {"label": "Épée tueuse", "type": WT.Type.SWORD,
		"might": 7, "range": 1, "hit": 0, "crit": 30, "weight": 8, "price": 1300, "icon": "killing_edge"},

	# --- Lances ---
	"iron_lance": {"label": "Lance de fer", "type": WT.Type.LANCE,
		"might": 6, "range": 1, "hit": -5, "crit": 0, "weight": 7, "price": 320, "icon": "iron_lance"},
	"steel_lance": {"label": "Lance d'acier", "type": WT.Type.LANCE,
		"might": 9, "range": 1, "hit": -10, "crit": 0, "weight": 12, "price": 720, "icon": "steel_lance"},
	"javelin": {"label": "Javelot", "type": WT.Type.LANCE,
		"might": 4, "range": 2, "hit": -10, "crit": 0, "weight": 8, "price": 500, "icon": "javelin"},

	# --- Haches ---
	"iron_axe": {"label": "Hache de fer", "type": WT.Type.AXE,
		"might": 7, "range": 1, "hit": -15, "crit": 0, "weight": 9, "price": 300, "icon": "iron_axe"},
	"steel_axe": {"label": "Hache d'acier", "type": WT.Type.AXE,
		"might": 10, "range": 1, "hit": -20, "crit": 0, "weight": 13, "price": 650, "icon": "steel_axe"},

	# --- Arcs (jamais utilisables au contact) ---
	"iron_bow": {"label": "Arc de fer", "type": WT.Type.BOW,
		"might": 5, "range": 2, "hit": 0, "crit": 0, "weight": 6, "price": 350, "icon": "iron_bow"},
	"steel_bow": {"label": "Arc d'acier", "type": WT.Type.BOW,
		"might": 8, "range": 2, "hit": -5, "crit": 0, "weight": 10, "price": 700, "icon": "steel_bow"},

	# --- Grimoires (visent la RÉS) ---
	"fire": {"label": "Feu", "type": WT.Type.TOME,
		"might": 5, "range": 2, "hit": 5, "crit": 0, "weight": 5, "price": 400, "icon": "fire"},
	"thunder": {"label": "Foudre", "type": WT.Type.TOME,
		"might": 3, "range": 2, "hit": 10, "crit": 10, "weight": 4, "price": 560, "icon": "thunder"},

	# --- Bâtons (soignent, ne ripostent pas) ---
	"heal_staff": {"label": "Bâton de soin", "type": WT.Type.STAFF,
		"might": 0, "range": 1, "hit": 0, "crit": 0, "weight": 3, "price": 400, "icon": "heal_staff"},
}


## L'arme existe-t-elle ?
static func exists(weapon_id: String) -> bool:
	return DATA.has(canonical_id(weapon_id))


## Identifiant canonique (insensible à la casse) — "" si inconnu.
static func canonical_id(weapon_id: String) -> String:
	var needle: String = weapon_id.strip_edges().to_lower()
	for key: String in DATA:
		if key.to_lower() == needle:
			return key
	return ""


## Définition d'une arme (dictionnaire vide si inconnue).
static func get_weapon(weapon_id: String) -> Dictionary:
	var key: String = canonical_id(weapon_id)
	return DATA[key] if not key.is_empty() else {}


## Toutes les armes connues, triées par identifiant.
static func all_weapons() -> Array:
	var ids: Array = DATA.keys()
	ids.sort()
	return ids


## Libellé affichable.
static func label(weapon_id: String) -> String:
	var w: Dictionary = get_weapon(weapon_id)
	return str(w.get("label", weapon_id))


## Chemin de la vignette de l'arme — "" si elle n'en a pas.
##
## Les vignettes partagent le dossier des objets ([constant ItemDB.ICON_DIR]) :
## c'est le même pack, et l'intendance les affiche côte à côte.
static func icon_path(weapon_id: String) -> String:
	var icon: String = str(get_weapon(weapon_id).get("icon", ""))
	return (ItemDB.ICON_DIR + icon + ".png") if not icon.is_empty() else ""


## Prix d'achat (0 si l'arme est inconnue).
static func price(weapon_id: String) -> int:
	return int(get_weapon(weapon_id).get("price", 0))


## Prix de revente.
static func resale_price(weapon_id: String) -> int:
	return int(floor(float(price(weapon_id)) * RESALE_RATIO))


## Type d'arme ([enum WeaponType.Type]) — [constant WeaponType.Type.NONE] si inconnue.
static func weapon_type(weapon_id: String) -> int:
	return int(get_weapon(weapon_id).get("type", WT.Type.NONE))


## L'arme soigne-t-elle au lieu de frapper ?
static func is_staff(weapon_id: String) -> bool:
	return weapon_type(weapon_id) == WT.Type.STAFF


## Armes vendues en boutique, de la moins chère à la plus chère.
static func shop_stock() -> Array:
	var stock: Array = []
	for key: String in DATA:
		if price(key) > 0:
			stock.append(key)
	stock.sort_custom(func(a: String, b: String) -> bool: return price(a) < price(b))
	return stock


## Ligne descriptive d'une arme, pour la boutique et le menu d'équipement.
static func describe(weapon_id: String) -> String:
	var w: Dictionary = get_weapon(weapon_id)
	if w.is_empty():
		return ""
	var reach: String = "portée %d" % int(w["range"])
	var min_reach: int = WT.get_min_range(int(w["type"]))
	if min_reach > 1:
		reach = "portée %d uniquement" % int(w["range"])
	elif int(w["range"]) > 1:
		reach = "portée 1-%d" % int(w["range"])

	var parts: Array[String] = ["Pui %d" % int(w["might"]), reach]
	if int(w["hit"]) != 0:
		parts.append("Préc %+d" % int(w["hit"]))
	if int(w["crit"]) != 0:
		parts.append("Crit %+d" % int(w["crit"]))
	if int(w["weight"]) != 0:
		parts.append("Poids %d" % int(w["weight"]))
	return "  ".join(parts)
