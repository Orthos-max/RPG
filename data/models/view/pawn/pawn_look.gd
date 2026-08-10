class_name PawnLook
extends RefCounted
## Quelle figurine du pack Tiny Swords porte un pion, et comment elle se pose.
##
## C'est une table, pas un système : elle traduit une classe et un camp en deux
## planches (repos, marche) et en trois nombres (ligne de pieds, taille du
## pixel, flottement). [TacticsPawnSprite] ne fait que les appliquer.
##
## Pourquoi une couche à part de `stats.sprite` — la fiche d'une unité continue
## de porter sa figurine « maison » en 48 × 96, celle qu'affichent l'éditeur de
## personnages et l'écran de préparation. Le plateau, lui, montre le pack. Les
## deux vivent côte à côte : si le pack manque (dossier non copié), [method
## for_stats] rend un dictionnaire vide et le pion reprend sa planche de fiche.
##
## Le pack libre ne contient que cinq unités pour vingt-et-une classes : les
## rapprochements sont notés dans [constant CLASS_UNIT], approximations comprises.

const CD = preload("res://data/models/world/stats/class_data.gd")
const TeamDataRef = preload("res://data/models/world/combat/team/team_data.gd")

## Racine des unités du pack, telle qu'elle est livrée (espaces et parenthèses
## compris — les renommer obligerait à rejouer l'import à chaque mise à jour).
const ROOT: String = "res://assets/packs/tiny-swords-free/Tiny Swords (Free Pack)/Units"

## Un pixel de la planche, en unités de monde.
##
## Le pack dessine ses unités à ~88 px de haut dans une cellule de 192 : à
## 0,0125 la figurine mesure 1,1 unité, soit la taille qu'avaient les planches
## 128 × 256 à leur `pixel_size` de 0,01. Le plateau garde donc son échelle.
const PIXEL_SIZE: float = 0.0125

## Cadences des deux boucles, en images par seconde.
const IDLE_FPS: float = 8.0
const RUN_FPS: float = 12.0

## De combien une unité volante flotte au-dessus de sa case.
##
## Le pack n'a ni pégase ni wyverne : sans ce décalage, Cordelia et Sully
## seraient deux lanciers identiques. Le vol est la seule chose qui les sépare
## en jeu, autant qu'elle se voie.
const HOVER: float = 0.35

## Les cinq unités du pack libre.
##
## `foot` est la rangée de pixels où l'ombre portée touche le sol, mesurée sur
## toutes les images de chaque planche (elle ne bouge pas d'une image à
## l'autre, sauf de 5 px sur la course du lancier — l'appui de la foulée).
## Le nombre d'images n'est pas noté : il se déduit de la planche, dont la
## hauteur est aussi la largeur d'une cellule.
const UNITS: Dictionary = {
	"archer": {"idle": "Archer/Archer_Idle.png", "run": "Archer/Archer_Run.png", "foot": 136},
	"lancer": {"idle": "Lancer/Lancer_Idle.png", "run": "Lancer/Lancer_Run.png", "foot": 198},
	"monk": {"idle": "Monk/Idle.png", "run": "Monk/Run.png", "foot": 134},
	"brute": {"idle": "Pawn/Pawn_Idle Axe.png", "run": "Pawn/Pawn_Run Axe.png", "foot": 135},
	"warrior": {"idle": "Warrior/Warrior_Idle.png", "run": "Warrior/Warrior_Run.png", "foot": 137},
}

## Ce que porte chaque classe. Cinq silhouettes pour vingt-et-une classes : le
## rapprochement se fait sur l'arme et l'allure, pas sur le nom.
##
## Approximations assumées : les montures et les ailes n'existent pas dans le
## pack libre, cavalerie et voltige portent donc toutes la lance à pied — le
## flottement ([constant HOVER]) distingue les secondes.
const CLASS_UNIT: Dictionary = {
	CD.Id.LORD: "warrior", CD.Id.GREAT_LORD: "warrior", CD.Id.MASTER_LORD: "warrior",
	CD.Id.KNIGHT: "warrior", CD.Id.GREAT_KNIGHT: "warrior",
	CD.Id.CAVALIER: "lancer", CD.Id.PALADIN: "lancer",
	CD.Id.PEGASUS_KNIGHT: "lancer", CD.Id.FALCON_KNIGHT: "lancer",
	CD.Id.WYVERN_RIDER: "lancer", CD.Id.WYVERN_LORD: "lancer",
	CD.Id.ARCHER: "archer", CD.Id.SNIPER: "archer", CD.Id.BOW_KNIGHT: "archer",
	CD.Id.CLERIC: "monk", CD.Id.WAR_CLERIC: "monk",
	CD.Id.TACTICIAN: "monk", CD.Id.GRANDMASTER: "monk", CD.Id.SAGE: "monk",
	CD.Id.DARK_MAGE: "monk", CD.Id.SORCERER: "monk",
	CD.Id.BRIGAND: "brute", CD.Id.BERSERKER: "brute",
}

## Ce que l'intitulé d'une unité impose, par-dessus sa classe.
##
## Le chef de brigands est un Brigand comme les autres pour les statistiques ;
## sur le plateau il doit se reconnaître, sinon le joueur ne sait pas lequel des
## quatre morts-vivants identiques termine le chapitre.
const NAME_UNIT: Dictionary = {
	"brigand chief": "warrior",
}

## Couleur du pack par camp.
const SIDE_COLOR: Dictionary = {
	TeamDataRef.Side.PLAYER: "Blue",
	TeamDataRef.Side.OPPONENT: "Red",
	TeamDataRef.Side.GUEST: "Purple",
}
const DEFAULT_COLOR: String = "Blue"

## L'or du seigneur — seulement du côté du joueur : porté par l'adversaire, il
## brouillerait la lecture bleu/rouge des camps, qui prime sur tout le reste.
const LORD_COLOR: String = "Yellow"
const LORD_CLASSES: Array = [CD.Id.LORD, CD.Id.GREAT_LORD, CD.Id.MASTER_LORD]

## Les morts-vivants ne suivent pas la couleur de leur camp : ils sont noirs, et
## violets quand ils lancent des sorts. Ils se reconnaissent à leur figurine de
## fiche, qui vit dans `assets/textures/actor/mob/`.
const MOB_MARKER: String = "/actor/mob/"
const MOB_COLOR: String = "Black"
const MOB_CASTER_COLOR: String = "Purple"


## L'apparence d'un pion, ou {} s'il n'y en a pas (le pion garde alors sa
## planche de fiche).
##
## [param side] un [enum TeamData.Side], tel que
## [method TeamData.side_for_camp_node] le rend pour le nœud de camp.
## [returns] {idle: String, run: String, foot: int, pixel_size: float, hover: float}
static func for_stats(stats: Stats, side: int) -> Dictionary:
	if not stats:
		return {}

	var key: String = _unit_key(stats)
	if not UNITS.has(key):
		return {}

	var unit: Dictionary = UNITS[key]
	var color: String = _color(stats, side)
	var idle: String = "%s/%s Units/%s" % [ROOT, color, unit["idle"]]
	var run: String = "%s/%s Units/%s" % [ROOT, color, unit["run"]]
	# Le pack n'est pas indispensable au jeu : absent, la planche de fiche reprend.
	if not ResourceLoader.exists(idle) or not ResourceLoader.exists(run):
		return {}

	return {
		"idle": idle,
		"run": run,
		"foot": int(unit["foot"]),
		"pixel_size": PIXEL_SIZE,
		"hover": HOVER if CD.is_flying(stats.character_class) else 0.0,
	}


#region Internes
## L'unité du pack : l'intitulé d'abord s'il impose quelque chose, la classe sinon.
static func _unit_key(stats: Stats) -> String:
	var label: String = stats.expertise.strip_edges().to_lower()
	if NAME_UNIT.has(label):
		return str(NAME_UNIT[label])
	return str(CLASS_UNIT.get(stats.character_class, ""))


static func _color(stats: Stats, side: int) -> String:
	if stats.sprite.contains(MOB_MARKER):
		return MOB_CASTER_COLOR if _is_caster(stats.character_class) else MOB_COLOR
	if side == TeamDataRef.Side.PLAYER and stats.character_class in LORD_CLASSES:
		return LORD_COLOR
	return str(SIDE_COLOR.get(side, DEFAULT_COLOR))


static func _is_caster(class_id: int) -> bool:
	return class_id == CD.Id.DARK_MAGE or class_id == CD.Id.SORCERER
#endregion
