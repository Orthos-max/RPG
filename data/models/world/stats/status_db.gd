class_name StatusDB
extends RefCounted
## Catalogue des effets de statut — poison, brûlure, paralysie, gel.
##
## Un statut est une **affliction persistante** : posée par un coup, elle survit
## à l'échange et se paie au début de chaque tour de sa victime, jusqu'à ce que
## sa durée s'épuise. C'est le pendant durable des bonus temporaires
## ([method Stats.apply_buff]), qui eux ne font que du bien et n'ont pas de voix
## au chapitre pendant le tour.
##
## Logique pure : aucun nœud, aucune scène, à l'image de [SkillDB] et [ItemDB].
## Le catalogue dit ce qu'un statut [i]est[/i] ; [StatusEffects] dit ce qu'il
## [i]fait[/i] à une liste d'afflictions, et [Stats] le porte sur une unité.
##
## [b]L'identité d'un statut est sa chaîne[/b] (« poison »), pas son entier :
## c'est elle qui est stockée, journalisée, et surtout la seule des deux qui
## traverse le JSON d'un instantané de bataille sans se faire relire en flottant.
## L'énumération [enum Id] n'existe que pour le confort des sites d'appel.

enum Id {
	POISON = 0,     ## Dégâts par tour, rien d'autre — mais longtemps
	BURN = 1,       ## Dégâts par tour et armure entamée
	PARALYZE = 2,   ## L'unité ne peut pas agir, elle passe son tour
	FROST = 3,      ## Membres engourdis : la vitesse s'effondre
}

## Statistiques qu'un statut peut grever. Les mêmes noms que [Stats].
##
## Volontairement étroit : un statut retire de la défense ou de la vitesse, il ne
## touche ni aux PV maximum ni à la croissance. Une affliction se subit un temps,
## elle ne refait pas la fiche.
const MOD_KEYS: Array[String] = ["def", "spd"]

## Plancher de PV des dégâts de statut.
##
## [b]Un statut ne tue pas.[/b] C'est la règle de Fire Emblem, et elle est reprise
## telle quelle : le poison ronge jusqu'à 1 PV et s'arrête là. La raison n'est pas
## la douceur, c'est la lisibilité — une unité perdue à distance, entre deux tours,
## sans qu'aucun coup ne soit porté, est une mort que le joueur n'a pas vue venir
## et n'aurait pas pu empêcher. Qui achève l'empoisonné doit encore le frapper.
const HP_FLOOR: int = 1

## Durée maximale d'une affliction, quelle que soit la voie qui la pose.
## Garde-fou contre une arme mal réglée qui paralyserait dix tours d'affilée.
const MAX_TURNS: int = 9

## Le catalogue.
##
## `damage` sont les PV perdus au début de chaque tour de la victime, `mods` les
## malus de statistique appliqués tant que l'affliction dure, et `blocks_action`
## dit si l'unité perd purement son tour.
##
## Les durées par défaut disent le tempérament de chaque statut : le poison est
## long et faible, la brûlure courte et mordante, la paralysie tient un seul tour
## — c'est déjà énorme dans un jeu où chaque unité n'agit qu'une fois par tour.
static var DATA: Dictionary = {
	"poison": {
		"id": Id.POISON,
		"label": "Poison",
		"glyph": "☠",
		"desc": "Perd 3 PV au début de chaque tour.",
		"damage": 3,
		"mods": {},
		"blocks_action": false,
		"turns": 3,
	},
	"burn": {
		"id": Id.BURN,
		"label": "Brûlure",
		"glyph": "🔥",
		"desc": "Perd 2 PV au début de chaque tour, et 2 points de défense.",
		"damage": 2,
		"mods": {"def": -2},
		"blocks_action": false,
		"turns": 2,
	},
	"paralyze": {
		"id": Id.PARALYZE,
		"label": "Paralysie",
		"glyph": "⚡",
		"desc": "L'unité ne peut ni bouger ni frapper : elle passe son tour.",
		"damage": 0,
		"mods": {},
		"blocks_action": true,
		"turns": 1,
	},
	"frost": {
		"id": Id.FROST,
		"label": "Gel",
		"glyph": "❄",
		"desc": "Perd 3 points de vitesse : plus d'esquive, plus de second coup.",
		"damage": 0,
		"mods": {"spd": -3},
		"blocks_action": false,
		"turns": 2,
	},
}


## Le statut existe-t-il ?
static func exists(status: String) -> bool:
	return DATA.has(canonical_key(status))


## Clé canonique (insensible à la casse) — "" si le statut est inconnu.
static func canonical_key(status: String) -> String:
	var needle: String = status.strip_edges().to_lower()
	for key: String in DATA:
		if key == needle:
			return key
	return ""


## Définition d'un statut (dictionnaire vide si inconnu).
static func get_status(status: String) -> Dictionary:
	var key: String = canonical_key(status)
	return DATA[key] if not key.is_empty() else {}


## Clé d'un statut désigné par son entier — "" si l'entier ne correspond à rien.
##
## Le pont depuis [enum Id] vers l'identité réelle : `key_for(Id.POISON)` rend
## « poison ». C'est le seul sens utile, le stockage étant toujours la chaîne.
static func key_for(status_id: int) -> String:
	for key: String in DATA:
		if int(DATA[key]["id"]) == status_id:
			return key
	return ""


## Tous les statuts du catalogue, dans l'ordre de déclaration.
static func all_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in DATA:
		keys.append(str(key))
	return keys


## Nom affichable ("Poison"). Rend la clé brute pour un statut inconnu, plutôt
## qu'une chaîne vide : mieux vaut un mot technique à l'écran que rien du tout.
static func label(status: String) -> String:
	var entry: Dictionary = get_status(status)
	return str(entry.get("label", status))


## Pictogramme d'un statut ("" s'il est inconnu).
static func glyph(status: String) -> String:
	return str(get_status(status).get("glyph", ""))


## Description affichable.
static func describe(status: String) -> String:
	return str(get_status(status).get("desc", ""))


## Dégâts infligés au début de chaque tour de la victime (0 si aucun).
static func damage(status: String) -> int:
	return int(get_status(status).get("damage", 0))


## Le statut prive-t-il l'unité de son tour ?
static func blocks_action(status: String) -> bool:
	return bool(get_status(status).get("blocks_action", false))


## Malus appliqué à une statistique par ce statut (0 s'il n'y touche pas).
static func stat_mod(status: String, stat: String) -> int:
	return int(get_status(status).get("mods", {}).get(stat, 0))


## Durée par défaut du statut, en tours (0 s'il est inconnu).
static func default_turns(status: String) -> int:
	return int(get_status(status).get("turns", 0))


## Le statut en une poignée de caractères : « ☠ Poison (2) ».
##
## C'est la forme que lisent la fiche d'unité et l'étiquette de survol — assez
## pour savoir ce qu'on subit et combien de temps encore, sans ouvrir de bulle.
## Rend "" pour un statut inconnu, l'appelant n'affiche alors aucune ligne.
static func short_label(status: String, turns: int) -> String:
	var entry: Dictionary = get_status(status)
	if entry.is_empty():
		return ""
	return "%s %s (%d)" % [str(entry["glyph"]), str(entry["label"]), maxi(0, turns)]


## Info-bulle complète : le nom, l'effet, et ce qu'il reste à endurer.
static func tooltip(status: String, turns: int) -> String:
	var entry: Dictionary = get_status(status)
	if entry.is_empty():
		return ""
	return "%s %s\n\n%s\n\n⟶ Encore %d tour%s." % [
		str(entry["glyph"]), str(entry["label"]), str(entry["desc"]),
		maxi(0, turns), "" if maxi(0, turns) <= 1 else "s",
	]
