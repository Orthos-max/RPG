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
		# Deux détours et un pont : le corridor de l'est (12, 5), la rive
		# sud-ouest qu'on n'atteint qu'en traversant (3, 8), et le fortin que les
		# morts-vivants gardent (11, 8).
		"chests": [
			{"col": 12, "row": 5, "gold": 80},
			{"col": 3, "row": 8, "gold": 100},
			{"col": 11, "row": 8, "item": "Vulnerary"},
		],
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
		"scene_path": "res://assets/maps/level/outpost_level.tscn",
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
		# Le hameau du nord (3, 1) se prend en chemin ; les ruines (8, 10) sont
		# l'autre passage sous le rempart, celui que la porte fait oublier ; le
		# fortin (0, 15) est planté au milieu du camp de Garrick.
		"chests": [
			{"col": 3, "row": 1, "gold": 70},
			{"col": 8, "row": 10, "item": "Concoction"},
			{"col": 0, "row": 15, "gold": 120},
		],
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
		"scene_path": "res://assets/maps/level/ch03_level.tscn",
		"objective": {"kind": OBJ.Kind.SURVIVE, "turns": 8},
		"bonus_objectives": [
			{"kind": OBJ.Bonus.NO_LOSSES},
		],
		"deploy_slots": 4,
		"reward_gold": 600,
		"recommended_level": 7,
		# Deux coffres dans la cour même (5, 3) et (10, 6) — on tient le siège, on
		# a le temps de les ouvrir. Le troisième est au hameau (2, 6), dehors :
		# huit tours à survivre, et il faut sortir pour l'avoir.
		"chests": [
			{"col": 5, "row": 3, "gold": 90},
			{"col": 10, "row": 6, "item": "Vulnerary"},
			{"col": 2, "row": 6, "gold": 110},
		],
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
		"scene_path": "res://assets/maps/level/ch04_level.tscn",
		# Prise de point : la case (3, 8) est à l'autre bout de la carte, côté
		# adverse. Il faut traverser, pas seulement survivre — la rivière ne se
		# franchit que par ses deux ponts, (8, 2) au nord et (8, 7) au sud.
		"objective": {"kind": OBJ.Kind.SEIZE, "col": 3, "row": 8},
		"bonus_objectives": [
			{"kind": OBJ.Bonus.SPEED_RUN, "turns": 12},
			{"kind": OBJ.Bonus.NO_LOSSES},
		],
		"deploy_slots": 5,
		"reward_gold": 700,
		"recommended_level": 10,
		# Le camp est à l'est, le poste à prendre à l'ouest : deux des trois
		# coffres sont de l'autre côté de la rivière, au hameau du nord (2, 1) et
		# dans l'angle sud-ouest (1, 9). Le troisième (13, 8) est du bon côté,
		# mais en contrebas du camp : il coûte le tour d'un traînard.
		"chests": [
			{"col": 13, "row": 8, "gold": 90},
			{"col": 2, "row": 1, "gold": 130},
			{"col": 1, "row": 9, "item": "Concoction"},
		],
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
		"scene_path": "res://assets/maps/level/ch05_level.tscn",
		# Le seuil est la porte (13, 9), au fond de la troisième salle. La roche
		# ferme le flanc droit : il n'y a pas de chemin qui en fasse le tour.
		"objective": {"kind": OBJ.Kind.SEIZE, "col": 13, "row": 9},
		"bonus_objectives": [
			{"kind": OBJ.Bonus.FULL_ROUT},
			{"kind": OBJ.Bonus.SPEED_RUN, "turns": 14},
		],
		"deploy_slots": 5,
		"reward_gold": 900,
		"recommended_level": 13,
		# Un coffre par salle, du seuil au sanctuaire : les ruines de la première
		# (1, 1), le renfoncement nord de la deuxième (9, 1), et le fond de la
		# troisième (12, 10), à un pas de la porte — celui-là, on le paie d'un
		# tour de plus sous les yeux du gardien.
		"chests": [
			{"col": 1, "row": 1, "gold": 80},
			{"col": 9, "row": 1, "item": "Elixir"},
			{"col": 12, "row": 10, "gold": 150},
		],
	},
	{
		"id": "ch06",
		"index": 5,
		"title": "Chapitre 6 — L'escorte",
		"subtitle": "Route basse, sous la pluie",
		"intro_lines": [
			"Les relevés du relais ne valent rien sans quelqu'un pour les lire.",
			"Votre clerc est la seule à savoir déchiffrer une signature de mana.",
			"— Ils le savent aussi. Ils viendront pour elle.",
			"Tenez jusqu'à ce que l'escorte atteigne la crête.",
		],
		"outro_lines": [
			"La crête est franchie, les relevés sont saufs.",
			"— Ces courbes… ce n'est pas une réserve qu'on vide. C'est un cœur qui s'emballe.",
			"Personne n'ose demander ce qui arrive quand il s'arrête.",
		],
		"scene_path": "res://assets/maps/level/ch06_level.tscn",
		# Protéger : la cible doit correspondre au nom affiché d'un pion du joueur.
		# `required_units` l'impose au déploiement — sans quoi le joueur pourrait
		# la laisser au camp et perdre au premier tour.
		"objective": {"kind": OBJ.Kind.PROTECT, "target": "Lissa", "turns": 10},
		# Identifiants de roster : à renommer en même temps que les héros le jour
		# où les noms suivront le lore.
		"required_units": ["lissa", "chrom"],
		"bonus_objectives": [
			{"kind": OBJ.Bonus.NO_LOSSES},
			{"kind": OBJ.Bonus.FULL_ROUT},
		],
		"deploy_slots": 5,
		"reward_gold": 1000,
		"recommended_level": 15,
		# Escorter, c'est avancer : les coffres tirent dans le sens de la marche.
		# (3, 3) se prend au départ sans quitter la colonne, (9, 11) demande un
		# détour par le bord sud, et (14, 9) attend sur la crête même — celui-là,
		# on l'a en arrivant, ou on ne l'a pas.
		"chests": [
			{"col": 3, "row": 3, "gold": 80},
			{"col": 9, "row": 11, "item": "Vulnerary"},
			{"col": 14, "row": 9, "gold": 140},
		],
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


## Index d'un chapitre depuis son identifiant (-1 si inconnu)
static func index_of(id: String) -> int:
	for i in CHAPTERS.size():
		if str(CHAPTERS[i].get("id", "")) == id:
			return i
	return -1
