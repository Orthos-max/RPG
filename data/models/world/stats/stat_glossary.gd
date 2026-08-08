class_name StatGlossary
extends RefCounted
## Ce que fait chaque statistique — source unique des info-bulles.
##
## Les textes disent la **formule réellement appliquée** par [FECombatCalculator]
## et [Stats], pas une paraphrase : une info-bulle qui ment sur un chiffre est
## pire que pas d'info-bulle du tout. Quand une formule change là-bas, elle
## change ici — c'est le prix d'avoir un seul endroit où l'expliquer.
##
## Les clés des stats brutes sont celles de [UnitDocument.STATS] et de
## [StatsResource] ; celles des valeurs dérivées sont celles que [UnitSheet]
## pose dans ses paires (`att`, `hit`, `avoid`, `crit`, `as`).

## Stats brutes : ce que le joueur règle, et ce que le combat en fait.
const STATS: Dictionary = {
	"hp": {
		"label": "PV",
		"desc": "Points de vie. À zéro, l'unité tombe — et elle ne revient pas.",
	},
	"str": {
		"label": "Force",
		"desc": "Dégâts des armes physiques (épée, lance, hache, arc).\n"
			+ "Attaque = Force + puissance de l'arme.\n"
			+ "Amortit aussi le poids de l'arme : chaque point de Force annule un point de poids.",
	},
	"mag": {
		"label": "Magie",
		"desc": "Dégâts des armes magiques (grimoire), et soins du bâton.\n"
			+ "Attaque = Magie + puissance de l'arme.\n"
			+ "Soin du bâton = 10 + Magie / 3.",
	},
	"skl": {
		"label": "Adresse",
		"desc": "Toucher et critique.\n"
			+ "Précision +2 par point, Critique +1 tous les 2 points.\n"
			+ "Décide aussi de la fréquence des compétences à déclenchement "
			+ "(Lune : Adresse %, Astre : Adresse / 2 %).",
	},
	"spd": {
		"label": "Vitesse",
		"desc": "Esquiver, et frapper deux fois.\n"
			+ "Esquive +2 par point.\n"
			+ "Une unité qui dépasse son adversaire de 5 en vitesse d'attaque frappe deux fois.",
	},
	"lck": {
		"label": "Chance",
		"desc": "Précision +1 tous les 2 points, Esquive +1 par point.\n"
			+ "Réduit d'autant le critique adverse : c'est la seule protection contre les coups fatals.",
	},
	"def": {
		"label": "Défense",
		"desc": "Retranchée des dégâts physiques reçus, avec le bonus de la case occupée.",
	},
	"res": {
		"label": "Résistance",
		"desc": "Retranchée des dégâts magiques reçus, avec le bonus de la case occupée.",
	},
	"movement": {
		"label": "Mouvement",
		"desc": "Nombre de cases parcourues en un tour. Le terrain coûte plus ou moins cher.",
	},
}

## Valeurs dérivées : jamais réglées à la main, toujours calculées.
const DERIVED: Dictionary = {
	"att": {
		"label": "Attaque",
		"desc": "Force (ou Magie) + puissance de l'arme.\n"
			+ "Dégâts infligés = Attaque + triangle + compétences − (Défense ou Résistance + terrain).\n"
			+ "Un arc contre une unité volante triple la puissance de l'arme.",
	},
	"hit": {
		"label": "Précision",
		"desc": "Adresse × 2 + Chance / 2 + précision de l'arme.\n"
			+ "Chance de toucher = 70 + Précision + triangle + soutiens + compétences − Esquive adverse.\n"
			+ "Le jet est la moyenne de deux dés : les hautes précisions touchent plus souvent "
			+ "que le chiffre ne le laisse croire.",
	},
	"avoid": {
		"label": "Esquive",
		"desc": "Vitesse × 2 + Chance. Retranchée de la précision de l'assaillant.",
	},
	"crit": {
		"label": "Critique",
		"desc": "Adresse / 2 + critique de l'arme, moins la Chance de la cible.\n"
			+ "Un coup critique inflige le triple des dégâts.",
	},
	"as": {
		"label": "Vitesse d'attaque",
		"desc": "Vitesse − (poids de l'arme − Force), jamais négatif.\n"
			+ "5 de plus que l'adversaire, et l'unité porte un second coup dans le même échange.",
	},
}

## Ordre d'affichage des stats brutes réglables, tel que l'éditeur les présente.
const ORDER: Array[String] = ["str", "mag", "skl", "spd", "lck", "def", "res"]


## Le glossaire connaît-il cette clé ?
static func has_entry(key: String) -> bool:
	return STATS.has(key) or DERIVED.has(key)


## Nom affichable d'une stat (la clé elle-même si elle est inconnue).
static func label(key: String) -> String:
	var entry: Dictionary = _entry(key)
	return str(entry.get("label", key))


## Explication seule, sans titre ("" si la clé est inconnue).
static func describe(key: String) -> String:
	return str(_entry(key).get("desc", ""))


## Info-bulle complète : le nom, puis l'explication.
## Rend "" pour une clé inconnue — un Control n'affiche alors aucune bulle.
static func tooltip(key: String) -> String:
	var entry: Dictionary = _entry(key)
	if entry.is_empty():
		return ""
	return "%s\n\n%s" % [str(entry["label"]), str(entry["desc"])]


static func _entry(key: String) -> Dictionary:
	if STATS.has(key):
		return STATS[key]
	return DERIVED.get(key, {})
