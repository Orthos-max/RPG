class_name RaceDB
extends RefCounted
## Catalogue des peuples — humains, elfes, nains, kitsune, morts-vivants.
##
## La classe d'une unité dit son métier, sa race dit son corps. Deux archers
## n'ont pas la même main selon qu'ils sont nés dans la garde d'un baron ou sous
## les futaies : c'est tout ce que ce catalogue ajoute, et il n'en ajoute pas
## davantage — une race vaut un ou deux points, jamais un destin. Le lore
## (`docs/WORLDBUILDING.md`) peut donc grandir sans que le jeu ait à se rééquilibrer.
##
## Logique pure : aucun nœud, aucune scène, à l'image de [StatusDB] et [SkillDB].
##
## [b]Une race ne touche jamais la fiche.[/b] Son bonus s'ajoute au moment du
## calcul ([method Stats.effective]), pas à l'import : une `.tres` reste la vérité
## de ce qu'une unité vaut nue, la même fiche prêtée à deux peuples reste
## comparable, et la montée de niveau ne fait pas croître un chiffre déjà gonflé.
## C'est aussi ce qui permet de relire une race dans un instantané de bataille
## sans risquer de la compter deux fois — le piège que
## [method Stats.set_active_buffs] a dû désamorcer pour les toniques.
##
## [b]L'identité d'une race est sa chaîne[/b] (« elf »), pas son entier : c'est
## elle qui est écrite dans les `.tres`, portée par le roster et sauvegardée en
## JSON. L'énumération [enum Id] n'existe que pour le confort des sites d'appel.

const GLOSSARY = preload("res://data/models/world/stats/stat_glossary.gd")

enum Id {
	HUMAN = 0,    ## L'étalon : la garde, les vallées, le gros des armées
	ELF = 1,      ## La main sûre et le pied léger
	DWARF = 2,    ## L'armure faite chair, et la lenteur qui va avec
	KITSUNE = 3,  ## Vif et chanceux, difficile à toucher et à surprendre
	UNDEAD = 4,   ## Des os qui tiennent debout, et plus rien pour parer la magie
}

## Statistiques qu'une race peut modifier. Les mêmes noms que [Stats].
##
## Volontairement étroit, pour la même raison que [constant StatusDB.MOD_KEYS] :
## une race pèse sur ce qui se joue à l'échange — frapper, toucher, esquiver,
## encaisser. Elle ne touche ni aux PV maximum, ni au mouvement, ni aux
## croissances. Les PV surtout : ils servent de dénominateur partout (ratio de
## vie, seuils de phase de boss, soins bornés), et un total qui dépendrait d'un
## bonus dérivé se contredirait d'un appel à l'autre.
const MOD_KEYS: Array[String] = ["str", "mag", "skl", "spd", "lck", "def", "res"]

## Amplitude maximale d'un modificateur de race, dans les deux sens.
##
## Un garde-fou, pas une cible : au-delà, la race déciderait du combat à la place
## du joueur, et choisir son peuple cesserait d'être un choix de saveur pour
## devenir un choix obligé.
const MAX_MOD: int = 2

## Le catalogue.
##
## `mods` sont les points ajoutés (ou retirés) aux statistiques de combat, tant
## que l'unité vit — une race ne s'use pas, contrairement à un tonique.
##
## L'humain est l'étalon : il est le plus léger des cinq, et c'est à lui que les
## autres se mesurent. Chaque peuple gagne environ deux points, et aucun n'en
## perd plus d'un — un elfe reste jouable en première ligne, un nain rattrape à
## pied ce qu'il perd en vitesse.
static var DATA: Dictionary = {
	"human": {
		"id": Id.HUMAN,
		"label": "Humain",
		"desc": "Les gens des vallées et de la garde. Rien d'exceptionnel, "
			+ "sinon l'obstination — et une chance qui leur reste.",
		"mods": {"lck": 1},
	},
	"elf": {
		"id": Id.ELF,
		"label": "Elfe",
		"desc": "Nés sous les futaies, la main sûre et le pied léger : "
			+ "ils touchent mieux, et se laissent moins toucher.",
		"mods": {"skl": 1, "spd": 1},
	},
	"dwarf": {
		"id": Id.DWARF,
		"label": "Nain",
		"desc": "Taillés dans la roche des monts. Ce qui les frappe s'émousse, "
			+ "mais rien ne les presse.",
		"mods": {"def": 2, "spd": -1},
	},
	"kitsune": {
		"id": Id.KITSUNE,
		"label": "Kitsune",
		"desc": "Le peuple-renard, vif et chanceux : difficile à toucher, "
			+ "plus difficile encore à surprendre.",
		"mods": {"spd": 1, "lck": 1},
	},
	"undead": {
		"id": Id.UNDEAD,
		"label": "Mort-vivant",
		"desc": "Des os qui tiennent debout sans savoir pourquoi. La lame y "
			+ "mord mal ; il n'y a plus personne pour parer la magie.",
		"mods": {"def": 1, "res": -1},
	},
}


## La race existe-t-elle ?
static func exists(race: String) -> bool:
	return DATA.has(canonical_key(race))


## Clé canonique (insensible à la casse) — "" si la race est inconnue.
##
## La chaîne vide est une réponse ordinaire, pas une erreur : l'immense majorité
## des fiches n'ont pas de peuple déclaré, et n'en tirent donc aucun bonus.
static func canonical_key(race: String) -> String:
	var needle: String = race.strip_edges().to_lower()
	for key: String in DATA:
		if key == needle:
			return key
	return ""


## Définition d'une race (dictionnaire vide si inconnue).
static func get_race(race: String) -> Dictionary:
	var key: String = canonical_key(race)
	return DATA[key] if not key.is_empty() else {}


## Clé d'une race désignée par son entier — "" si l'entier ne correspond à rien.
static func key_for(race_id: int) -> String:
	for key: String in DATA:
		if int(DATA[key]["id"]) == race_id:
			return key
	return ""


## Toutes les races du catalogue, dans l'ordre de déclaration.
static func all_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in DATA:
		keys.append(str(key))
	return keys


## Nom affichable (« Elfe »), "" pour une unité sans peuple.
##
## Contrairement à [method StatusDB.label], une clé inconnue ne se rend pas
## telle quelle : une fiche muette ne doit rien afficher du tout, et non le mot
## technique d'une race effacée du catalogue.
static func label(race: String) -> String:
	return str(get_race(race).get("label", ""))


## Description affichable.
static func describe(race: String) -> String:
	return str(get_race(race).get("desc", ""))


## Modificateurs d'une race ({} si elle est inconnue ou sans peuple).
static func mods(race: String) -> Dictionary:
	var entry: Dictionary = get_race(race)
	return (entry.get("mods", {}) as Dictionary).duplicate() if not entry.is_empty() else {}


## Ce que la race ajoute (ou retire) à une statistique — 0 si elle n'y touche pas.
##
## Le seul point d'entrée du calcul : [method Stats.effective] ne demande rien
## d'autre au catalogue, et tout ce qui décide d'un échange passe par elle.
static func stat_mod(race: String, stat: String) -> int:
	return int(get_race(race).get("mods", {}).get(stat, 0))


## Les modificateurs en toutes lettres : « Adresse +1, Vitesse +1 ».
##
## Les noms viennent de [StatGlossary], qui est déjà l'endroit où chaque
## statistique est nommée et expliquée. L'ordre est celui de
## [constant MOD_KEYS], et non celui du dictionnaire : deux races se lisent alors
## dans le même ordre, quoi qu'on ait tapé dans le catalogue.
static func mods_line(race: String) -> String:
	var entry_mods: Dictionary = get_race(race).get("mods", {})
	var parts: Array[String] = []
	for stat: String in MOD_KEYS:
		var amount: int = int(entry_mods.get(stat, 0))
		if amount != 0:
			parts.append("%s %+d" % [str(GLOSSARY.STATS[stat]["label"]), amount])
	return ", ".join(parts)


## La race en une ligne, pour la fiche d'unité : « Elfe — Adresse +1, Vitesse +1 ».
##
## Le joueur lit ses statistiques brutes dans la grille de la fiche ; sans cette
## ligne, il n'aurait aucun moyen de savoir pourquoi son elfe touche deux points
## plus haut que ce que la grille annonce. Rend "" pour une unité sans peuple.
static func summary(race: String) -> String:
	var name: String = label(race)
	if name.is_empty():
		return ""
	var line: String = mods_line(race)
	return name if line.is_empty() else "%s — %s" % [name, line]


## Info-bulle complète : le nom, ce que ce peuple est, ce qu'il vaut.
static func tooltip(race: String) -> String:
	var entry: Dictionary = get_race(race)
	if entry.is_empty():
		return ""
	var line: String = mods_line(race)
	return "%s\n\n%s%s" % [
		str(entry["label"]), str(entry["desc"]),
		"" if line.is_empty() else "\n\n⟶ %s." % line,
	]
