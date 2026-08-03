class_name DifficultyDB
extends RefCounted
## Niveaux de difficulté : handicap du camp adverse + tempérament de l'IA locale.
##
## Utilisé par le mode solo (choix au démarrage d'une campagne) et par le pont
## CielAI (bonus de stats progressif décrit dans le backlog P2).

enum Level {
	EASY = 0,    ## Adversaire affaibli, IA peu regardante
	NORMAL = 1,  ## Équilibre de référence
	BRUTAL = 2,  ## Adversaire renforcé, IA focalisée sur les cibles fragiles
}

## Pour chaque niveau :
##   stat_bonus       — bonus plat appliqué aux stats offensives des pions adverses
##   hp_bonus         — bonus plat de PV max des pions adverses
##   per_chapter      — bonus supplémentaire cumulé par chapitre franchi
##   max_scaling      — plafond du bonus cumulé
##   aggression       — 0.0 = prudent (fuit le danger) … 1.0 = fonce
##   focus_weak       — poids donné à l'achèvement des cibles blessées
##   uses_exposure    — l'IA évalue-t-elle le risque de se faire prendre à revers
const DATA: Dictionary = {
	Level.EASY: {
		"name": "Facile",
		"stat_bonus": -1,
		"hp_bonus": -2,
		"per_chapter": 0.0,
		"max_scaling": 0,
		"aggression": 1.0,
		"focus_weak": 0.2,
		"uses_exposure": false,
	},
	Level.NORMAL: {
		"name": "Normal",
		"stat_bonus": 0,
		"hp_bonus": 0,
		"per_chapter": 0.25,
		"max_scaling": 3,
		"aggression": 0.7,
		"focus_weak": 1.0,
		"uses_exposure": true,
	},
	Level.BRUTAL: {
		"name": "Brutal",
		"stat_bonus": 2,
		"hp_bonus": 4,
		"per_chapter": 0.5,
		"max_scaling": 6,
		"aggression": 0.55,
		"focus_weak": 1.8,
		"uses_exposure": true,
	},
}


## Nom affichable d'un niveau
static func get_level_name(level: int) -> String:
	return DATA.get(level, DATA[Level.NORMAL])["name"]


## Récupère la table d'un niveau (retombe sur NORMAL si inconnu)
static func get_profile(level: int) -> Dictionary:
	return DATA.get(level, DATA[Level.NORMAL])


## Bonus de stat appliqué au camp adverse pour un niveau et un chapitre donnés.
## Le handicap progresse doucement au fil de la campagne, jusqu'à un plafond.
static func stat_handicap(level: int, chapter_index: int = 0) -> int:
	var p: Dictionary = get_profile(level)
	var scaled: int = int(floor(float(p["per_chapter"]) * float(max(0, chapter_index))))
	return int(p["stat_bonus"]) + mini(scaled, int(p["max_scaling"]))


## Bonus de PV max appliqué au camp adverse.
static func hp_handicap(level: int, chapter_index: int = 0) -> int:
	var p: Dictionary = get_profile(level)
	var scaled: int = int(floor(float(p["per_chapter"]) * float(max(0, chapter_index)) * 2.0))
	return int(p["hp_bonus"]) + mini(scaled, int(p["max_scaling"]) * 2)


## Applique le handicap à un dictionnaire de stats vivantes (Stats ou dictionnaire).
## Renvoie les modifications appliquées, pour journalisation.
static func apply_to_stats(stats: Object, level: int, chapter_index: int = 0) -> Dictionary:
	if not stats:
		return {}
	var bonus: int = stat_handicap(level, chapter_index)
	var hp_bonus: int = hp_handicap(level, chapter_index)

	stats.set("str", maxi(0, int(stats.get("str")) + bonus))
	stats.set("mag", maxi(0, int(stats.get("mag")) + bonus))
	stats.set("skl", maxi(0, int(stats.get("skl")) + bonus))
	stats.set("spd", maxi(0, int(stats.get("spd")) + bonus))
	stats.set("def", maxi(0, int(stats.get("def")) + bonus))

	var new_max_hp: int = maxi(1, int(stats.get("max_hp")) + hp_bonus)
	stats.set("max_hp", new_max_hp)
	stats.set("hp", clampi(int(stats.get("hp")) + hp_bonus, 1, new_max_hp))

	return {"stat_bonus": bonus, "hp_bonus": hp_bonus}
