class_name ChapterData
extends Resource
## Définition d'un chapitre de la campagne solo.
##
## Un chapitre = une carte + un objectif + un roster ennemi + un peu d'écriture.
## Les chapitres sont décrits dans [CampaignDB] pour rester versionnés avec le code.

const OBJ = preload("res://data/models/campaign/objective.gd")

## Identifiant stable (utilisé dans la sauvegarde)
@export var id: String = "ch01"
## Position dans la campagne (0 = premier)
@export var index: int = 0
## Titre affiché
@export var title: String = "Chapitre"
## Sous-titre / lieu
@export var subtitle: String = ""
## Répliques d'introduction (boîtes de texte simples)
@export var intro_lines: Array[String] = []
## Répliques de fin de chapitre
@export var outro_lines: Array[String] = []
## Scène du niveau à charger
@export var scene_path: String = "res://assets/maps/level/map_level.tscn"
## Objectif principal : {kind, target, turns, col, row}
@export var objective: Dictionary = {"kind": 0}
## Objectifs secondaires : [{kind, turns}]
@export var bonus_objectives: Array = []
## Nombre d'unités déployables
@export var deploy_slots: int = 3
## Cases ouvertes au déploiement ([[col, row], …]).
## Vide : le voisinage de la ligne de départ de la carte fait office de zone.
@export var deploy_tiles: Array = []
## Unités que le chapitre impose au déploiement (identifiants de roster).
## Indispensable à un objectif « protéger » : la protégée doit être en scène.
@export var required_units: Array[String] = []
## Le roster de campagne remplace-t-il les pions de la carte ?
## Faux pour une carte du joueur : ses unités sont celles qu'elle déclare.
@export var use_roster: bool = true
## Unités recrutables à la fin du chapitre (chemins .tres)
@export var recruits: Array[String] = []
## Or gagné à la victoire
@export var reward_gold: int = 300
## Coffres posés sur la carte : `[{col, row, gold}]` ou `[{col, row, item}]`.
##
## Ils vivent ici, et non dans le `.tres` de la carte : le terrain est partagé
## entre les chapitres — et verrouillé par les tests — alors que ce qu'on trouve
## dessus appartient au chapitre. [ChestData] les nettoie, [BattleChests] les
## arme au chargement du niveau.
@export var chests: Array = []
## Niveau conseillé (affiché sur l'écran de préparation)
@export var recommended_level: int = 1


## Description lisible de l'objectif principal
func objective_text() -> String:
	return OBJ.describe(objective)


## Construit un chapitre depuis un dictionnaire (utilisé par [CampaignDB])
static func from_dict(data: Dictionary) -> ChapterData:
	var c := ChapterData.new()
	c.id = str(data.get("id", "ch"))
	c.index = int(data.get("index", 0))
	c.title = str(data.get("title", "Chapitre"))
	c.subtitle = str(data.get("subtitle", ""))
	c.scene_path = str(data.get("scene_path", c.scene_path))
	c.objective = data.get("objective", {"kind": 0})
	c.bonus_objectives = data.get("bonus_objectives", [])
	c.deploy_slots = int(data.get("deploy_slots", 3))
	c.deploy_tiles = data.get("deploy_tiles", [])
	c.use_roster = bool(data.get("use_roster", true))
	c.reward_gold = int(data.get("reward_gold", 300))
	c.chests = data.get("chests", [])
	c.recommended_level = int(data.get("recommended_level", 1))

	var lines: Array[String] = []
	for l in data.get("intro_lines", []):
		lines.append(str(l))
	c.intro_lines = lines

	var outro: Array[String] = []
	for l in data.get("outro_lines", []):
		outro.append(str(l))
	c.outro_lines = outro

	var rec: Array[String] = []
	for r in data.get("recruits", []):
		rec.append(str(r))
	c.recruits = rec

	var required: Array[String] = []
	for r in data.get("required_units", []):
		required.append(str(r))
	c.required_units = required
	return c
