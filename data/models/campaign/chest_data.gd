class_name ChestData
extends RefCounted
## Ce qu'un chapitre pose de trésors sur sa carte, en données pures.
##
## Un coffre est une case et une récompense : de l'or, ou un objet du catalogue
## ([ItemDB]). Il se déclare dans [CampaignDB], à côté de l'objectif et du roster
## ennemi, et **jamais dans le `.tres` de la carte** — le terrain est partagé
## entre les chapitres et vérrouillé par les tests, la garniture d'un chapitre
## ne l'est pas.
##
## Rien ici ne connaît de scène : [method parse] lit un tableau de dictionnaires
## écrit à la main et rend des entrées propres. C'est ce qui permet à la fois à
## [BattleChests] de les armer en combat et à un test de les valider en
## `--headless`, sans monter la moindre carte.
##
## Une déclaration mal formée est **écartée**, pas corrigée : un coffre à la
## case (-3, 12) ou promettant un objet qui n'existe pas ne doit pas apparaître
## sur le plateau, et le test de données le rattrape avant le joueur.

const ITEMS = preload("res://data/models/world/stats/item_db.gd")


## Nettoie les coffres déclarés par un chapitre.
##
## [param raw] `[{col, row, gold}, …]` ou `[{col, row, item}, …]`
## [returns] `[{cell: Vector2i, gold: int, item: String}, …]` — `gold` vaut zéro
## pour un coffre à objet, `item` est vide pour un coffre à or.
##
## Les doublons de case tombent : deux coffres sur la même case ne feraient
## qu'un seul ramassage, et le second serait un trésor invisible.
static func parse(raw: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for entry: Variant in raw:
		var chest: Dictionary = _one(entry)
		if chest.is_empty() or seen.has(chest["cell"]):
			continue
		seen[chest["cell"]] = true
		out.append(chest)
	return out


## Une déclaration, ou un dictionnaire vide si elle ne veut rien dire.
static func _one(entry: Variant) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var raw: Dictionary = entry as Dictionary
	if not raw.has("col") or not raw.has("row"):
		return {}
	var cell := Vector2i(int(raw["col"]), int(raw["row"]))
	if cell.x < 0 or cell.y < 0:
		return {}

	# Un objet inconnu du catalogue ne se ramasse pas : mieux vaut pas de coffre
	# du tout qu'un coffre qui s'ouvre sur rien.
	var item: String = ITEMS.canonical_name(str(raw.get("item", "")))
	var gold: int = maxi(0, int(raw.get("gold", 0)))
	if item.is_empty() and gold <= 0:
		return {}
	return {"cell": cell, "gold": 0 if not item.is_empty() else gold, "item": item}


## Ce que le coffre contient, tel qu'on l'annonce au joueur.
##
## « +120 or », « Potion ». Le libellé de l'objet vient d'[ItemDB] : le joueur
## doit lire le même mot au coffre, à l'intendance et dans son sac.
static func reward_label(chest: Dictionary) -> String:
	var item: String = str(chest.get("item", ""))
	if not item.is_empty():
		return ITEMS.label(item)
	return "+%d or" % int(chest.get("gold", 0))
