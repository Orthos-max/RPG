class_name CampaignDB
extends RefCounted
## Contenu de la campagne solo : liste ordonnée des chapitres.
##
## Les chapitres vivent ici (et non dans des .tres) pour rester lisibles et
## versionnés avec le code. Ajouter un chapitre = ajouter une entrée dans CHAPTERS.

const OBJ = preload("res://data/models/campaign/objective.gd")
const ChapterDataClass = preload("res://data/models/campaign/chapter_data.gd")

## Unités de départ du joueur (roster initial)
const STARTING_ROSTER: Array[String] = [
	"res://data/models/world/stats/hero/lord.tres",
	"res://data/models/world/stats/hero/cleric.tres",
	"res://data/models/world/stats/hero/archer.tres",
	"res://data/models/world/stats/hero/great_knight.tres",
]

## Unités recrutables à l'intendance, contre de l'or
const RECRUITS: Array[Dictionary] = [
	{"path": "res://data/models/world/stats/hero/cavalier.tres", "cost": 700},
	{"path": "res://data/models/world/stats/hero/pegasus_knight.tres", "cost": 900},
]

const CHAPTERS: Array[Dictionary] = [
	{
		"id": "ch01",
		"index": 0,
		"title": "Chapitre 1 — La brèche",
		"subtitle": "Les marches d'Ylisse",
		"intro_lines": [
			"Une brèche s'est ouverte dans la muraille est.",
			"Des morts-vivants remontent déjà le chemin de ronde.",
			"— Tenez la ligne. Personne ne passe.",
		],
		"outro_lines": [
			"La brèche est colmatée… pour cette nuit.",
			"Mais quelque chose, au loin, observait la bataille.",
		],
		"scene_path": "res://assets/maps/level/map_level.tscn",
		"objective": {"kind": OBJ.Kind.ROUT},
		"bonus_objectives": [
			{"kind": OBJ.Bonus.NO_LOSSES},
			{"kind": OBJ.Bonus.SPEED_RUN, "turns": 8},
		],
		"deploy_slots": 3,
		"reward_gold": 300,
		"recommended_level": 1,
	},
	{
		"id": "ch02",
		"index": 1,
		"title": "Chapitre 2 — Garrick le pillard",
		"subtitle": "Ruines du poste avancé",
		"intro_lines": [
			"Celui qui mène les morts porte encore l'insigne du poste avancé.",
			"— Abattez Garrick, le reste se disloquera.",
		],
		"outro_lines": [
			"Garrick s'effondre en poussière.",
			"Les autres refluent vers la forêt.",
		],
		"scene_path": "res://assets/maps/level/test_level.tscn",
		# La cible doit correspondre au nom affiché d'un pion de la carte
		# (skeleton_cpn.tres → « Garrick »), sinon l'objectif serait gagné d'emblée.
		"objective": {"kind": OBJ.Kind.DEFEAT_BOSS, "target": "Garrick"},
		"bonus_objectives": [
			{"kind": OBJ.Bonus.FULL_ROUT},
			{"kind": OBJ.Bonus.SPEED_RUN, "turns": 10},
		],
		"deploy_slots": 4,
		"reward_gold": 450,
		"recommended_level": 4,
	},
	{
		"id": "ch03",
		"index": 2,
		"title": "Chapitre 3 — Tenir jusqu'à l'aube",
		"subtitle": "Cour intérieure",
		"intro_lines": [
			"Les renforts arrivent à l'aube. Pas avant.",
			"— Alors nous tiendrons jusqu'à l'aube.",
		],
		"outro_lines": [
			"Le premier rayon de soleil balaie la cour.",
			"Les morts se figent, puis tombent.",
		],
		"scene_path": "res://assets/maps/level/map_level.tscn",
		"objective": {"kind": OBJ.Kind.SURVIVE, "turns": 8},
		"bonus_objectives": [
			{"kind": OBJ.Bonus.NO_LOSSES},
		],
		"deploy_slots": 4,
		"reward_gold": 600,
		"recommended_level": 7,
	},
	{
		"id": "ch04",
		"index": 3,
		"title": "Chapitre 4 — Le relais d'Azur",
		"subtitle": "Tour de captage, versant nord",
		"intro_lines": [
			"La bannière plantée sur la tour n'est ni royale ni funèbre : elle est cyan.",
			"— Ce sont eux. La Révolte d'Azur.",
			"Ils détournent le flux du Puits depuis ce relais. Prenez le poste de commandement,",
			"et leur colonne perdra sa route.",
		],
		"outro_lines": [
			"Le poste est à vous. Les tables de captage sont couvertes de relevés :",
			"quelqu'un mesure la Surcharge depuis des années, jour après jour.",
			"Ce ne sont pas les notes d'un pillard.",
		],
		"scene_path": "res://assets/maps/level/map_level.tscn",
		# Prise de point : la case (3, 8) est à l'autre bout de la carte, côté
		# adverse. Il faut traverser, pas seulement survivre.
		"objective": {"kind": OBJ.Kind.SEIZE, "col": 3, "row": 8},
		"bonus_objectives": [
			{"kind": OBJ.Bonus.SPEED_RUN, "turns": 12},
			{"kind": OBJ.Bonus.NO_LOSSES},
		],
		"deploy_slots": 5,
		"reward_gold": 700,
		"recommended_level": 10,
	},
	{
		"id": "ch05",
		"index": 4,
		"title": "Chapitre 5 — La porte du sanctuaire",
		"subtitle": "Antichambre du Puits",
		"intro_lines": [
			"Derrière cette porte, disent les archives, le Puits d'Éternité bat encore.",
			"Un géant à bois de cerf en garde le seuil. Il ne crie pas, il ne menace pas.",
			"Il attend.",
			"— Ne le contournez pas par la droite. Tenez le seuil, c'est tout ce qui compte.",
		],
		"outro_lines": [
			"Le seuil est pris ; le géant s'est retiré sans un mot,",
			"comme s'il avait reçu un ordre que personne n'a entendu.",
			"Loin devant, une silhouette bleue s'éloigne sans se retourner.",
		],
		"scene_path": "res://assets/maps/level/map_level.tscn",
		"objective": {"kind": OBJ.Kind.SEIZE, "col": 13, "row": 9},
		"bonus_objectives": [
			{"kind": OBJ.Bonus.FULL_ROUT},
			{"kind": OBJ.Bonus.SPEED_RUN, "turns": 14},
		],
		"deploy_slots": 5,
		"reward_gold": 900,
		"recommended_level": 13,
	},
]


## Nombre de chapitres de la campagne
static func count() -> int:
	return CHAPTERS.size()


## Chapitre par index (null si hors bornes)
static func get_chapter(index: int) -> ChapterData:
	if index < 0 or index >= CHAPTERS.size():
		return null
	return ChapterDataClass.from_dict(CHAPTERS[index])


## Chapitre par identifiant (null si inconnu)
static func get_chapter_by_id(id: String) -> ChapterData:
	for c: Dictionary in CHAPTERS:
		if str(c.get("id", "")) == id:
			return ChapterDataClass.from_dict(c)
	return null


## Index d'un chapitre depuis son identifiant (-1 si inconnu)
static func index_of(id: String) -> int:
	for i in CHAPTERS.size():
		if str(CHAPTERS[i].get("id", "")) == id:
			return i
	return -1


## Existe-t-il un chapitre après celui-ci ?
static func has_next(index: int) -> bool:
	return index + 1 < CHAPTERS.size()
