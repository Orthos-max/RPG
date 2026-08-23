class_name PawnLook
extends RefCounted
## Quelle figurine du pack Tiny Swords porte un pion, et comment elle se pose.
##
## C'est une table, pas un système : elle traduit une classe et un camp en deux
## planches (repos, marche) et en trois nombres (ligne de pieds, taille du
## pixel, flottement). [TacticsPawnSprite] ne fait que les appliquer.
##
## Pourquoi une couche à part de `stats.sprite` — la fiche d'une unité continue
## de porter sa figurine « maison », celle que l'écran de préparation affiche et
## que le pion reprend en repli. Les deux vivent côte à côte : si le pack manque
## (dossier non copié) ou si la classe n'y a pas d'équivalent, [method for_stats]
## rend un dictionnaire vide et la planche de fiche reprend la main. Les menus
## qui veulent montrer la figurine du plateau passent par [method
## still_for_stats] — c'est le cas de l'éditeur de personnages.
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

## Les passes jouées une fois, puis rendues : le coup porté, la blessure encaissée,
## la chute. Elles ne remplacent pas le repos et la course, elles s'y ajoutent —
## une planche qui n'en a pas continue de tourner en boucle sans rien perdre.
const ATTACK_FPS: float = 12.0
const HURT_FPS: float = 12.0
## Plus lente que les autres : une chute qui défile à douze images vaut un
## clignotement. À huit, les cinq poses se lisent une par une.
const DIE_FPS: float = 8.0

## Toutes les boucles connues, dans l'ordre où une planche les déclare.
##
## L'ordre n'a d'importance que pour le chargement : `idle` d'abord, car c'est
## elle qui donne la cellule de référence et le repli de toutes les autres.
const CLIPS: Array[String] = ["idle", "run", "attack", "die", "hurt"]

## Les boucles qui ne tournent pas : jouées une fois sur ordre du combat.
const ONESHOT_CLIPS: Array[String] = ["attack", "die", "hurt"]

## Cadence d'une boucle, [constant IDLE_FPS] pour tout ce qui n'est pas nommé.
static func fps_for(clip: StringName) -> float:
	match String(clip):
		"run": return RUN_FPS
		"attack": return ATTACK_FPS
		"hurt": return HURT_FPS
		"die": return DIE_FPS
		_: return IDLE_FPS

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

## Les planches dessinées pour une unité précise, rangées sous le chemin que sa
## fiche porte dans `stats.sprite`.
##
## C'est le seul endroit où une fiche décide de sa figurine de plateau : elle
## désigne sa planche, la table dit comment la découper. Le pack déduit tout de
## ses cellules carrées — une planche maison, elle, peut empiler ses images, et
## une colonne ne se déduit de rien.
##
## Deux écritures cohabitent, et une fiche choisit celle que son dessin mérite :
##
## - **Une planche pour tout** — `{rows, foot}` posé à plat. Le repos et la course
##   la partagent : une figurine sans foulée rejoue son repos en marchant, plus
##   vite ([constant RUN_FPS]), ce qui vaut mieux qu'une silhouette figée. C'est
##   le cas de l'elfe rousse, dont les deux poses respirent sans avancer.
## - **Une planche par boucle** — `{idle: {...}, run: {...}, attack: {...},
##   die: {...}, hurt: {...}}`, chacune avec ses `rows`, son `foot`, et son `file`
##   quand ce n'est pas la planche-clé. Seule `idle` est obligatoire : elle sert de
##   repli à `run` et donne la cellule de référence. Les boucles absentes ne
##   manquent à personne — [TacticsPawnSprite] ne les jouera simplement jamais.
##
## `rows` est le nombre de rangées de la planche (les colonnes s'en déduisent :
## la hauteur d'une rangée donne le côté de la cellule). `foot` est la rangée de
## pixels où les pieds touchent le sol, mesurée dans la cellule : elle est relevée
## **par planche**, car rien n'oblige un dessinateur à caler sa chute sur son repos.
const CUSTOM_SHEETS: Dictionary = {
	"res://assets/textures/pawns/elfe_rousse_v2_pawn.png": {"rows": 2, "foot": 127},
	# L'épéiste : cinq planches dessinées séparément, la première jeu du projet à
	# avoir un coup, une blessure et une chute. Sa planche de chute est plus large
	# que les autres (160 au lieu de 128) — le corps s'étale en tombant ; la cellule
	# se déduit de la hauteur, la largeur n'a donc rien à annoncer.
	"res://assets/textures/pawns/test_episte_idle.png": {
		"idle": {"rows": 2, "foot": 120},
		"run": {"file": "res://assets/textures/pawns/test_episte_walk.png", "rows": 6, "foot": 120},
		"attack": {"file": "res://assets/textures/pawns/test_episte_attack.png", "rows": 6, "foot": 120},
		"die": {"file": "res://assets/textures/pawns/test_episte_die.png", "rows": 5, "foot": 120},
		"hurt": {"file": "res://assets/textures/pawns/test_episte_hurt.png", "rows": 3, "foot": 120},
	},
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
## Une planche maison passe avant le pack : un dessin fait pour ce personnage-là
## vaut mieux que la silhouette générique que sa classe lui vaudrait.
##
## [param side] un [enum TeamData.Side], tel que
## [method TeamData.side_for_camp_node] le rend pour le nœud de camp.
## [returns] {idle: String, run: String, foot: int, pixel_size: float,
## hover: float, rows: int, full_cell: bool, clips: Dictionary}
##
## `clips` range chaque boucle disponible sous son nom — `{file, rows, foot}` —
## et c'est la seule entrée que [TacticsPawnSprite] lit pour s'habiller. Les
## champs `idle`, `run`, `rows` et `foot` restent au premier plan : ce sont ceux
## du repos, et les menus ([method still_for_stats]) n'ont besoin de rien d'autre.
static func for_stats(stats: Stats, side: int) -> Dictionary:
	if not stats:
		return {}

	var custom: Dictionary = _custom_look(stats)
	if not custom.is_empty():
		return custom

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

	# Le pack ne dessine que deux boucles, en bandes d'une seule rangée, et cale
	# ses deux planches sur la même ligne de pieds.
	var foot: int = int(unit["foot"])
	return {
		"idle": idle,
		"run": run,
		"foot": foot,
		"pixel_size": PIXEL_SIZE,
		"hover": HOVER if CD.is_flying(stats.character_class) else 0.0,
		"rows": 1,
		"full_cell": false,
		"clips": {
			"idle": {"file": idle, "rows": 1, "foot": foot},
			"run": {"file": run, "rows": 1, "foot": foot},
		},
	}


## La figurine **fixe** d'un pion, pour un menu : la première image de sa boucle
## de repos, ou null si sa classe n'a pas d'équivalent dans le pack.
##
## Un menu n'a pas de [TacticsPawnSprite] à animer, seulement un [TextureRect] à
## remplir. Le découpage vit ici pour que « une cellule est carrée, la hauteur de
## la planche donne son côté » ne soit pas réécrit écran par écran.
##
## La vignette ne prend qu'une **demi-cellule**, calée en bas sur la ligne de
## pieds et centrée horizontalement : le pack laisse la moitié de sa cellule vide
## au-dessus de l'unité (~88 px dessinés sur 192): rendue entière, la figurine
## occuperait le tiers de la vignette. Une planche maison, elle, est dessinée au
## format de sa cellule (`full_cell`) : la rogner couperait le personnage en deux.
static func still_for_stats(stats: Stats, side: int) -> Texture2D:
	var look: Dictionary = for_stats(stats, side)
	if look.is_empty():
		return null
	var sheet: Texture2D = load(str(look["idle"])) as Texture2D
	if not sheet:
		return null

	var cell: float = float(sheet.get_height()) / float(maxi(1, int(look.get("rows", 1))))
	var box: float = cell if bool(look.get("full_cell", false)) else cell / 2.0
	var still := AtlasTexture.new()
	still.atlas = sheet
	still.region = Rect2((cell - box) / 2.0, maxf(0.0, float(look["foot"]) - box), box, box)
	return still


#region Internes
## L'apparence d'une unité qui porte sa propre planche, ou {} si sa fiche
## désigne une figurine ordinaire.
##
## Le camp n'entre pas en compte : une planche maison n'a qu'une teinte, celle de
## son dessin. Le nombre de planches, lui, dépend du personnage — voir [constant
## CUSTOM_SHEETS].
static func _custom_look(stats: Stats) -> Dictionary:
	var sheet: String = stats.sprite.strip_edges()
	if not CUSTOM_SHEETS.has(sheet):
		return {}
	# Même prudence que pour le pack : une planche manquante rend la main à la
	# figurine de fiche plutôt que de laisser un pion invisible sur le plateau.
	if not ResourceLoader.exists(sheet):
		return {}

	var clips: Dictionary = _custom_clips(sheet, CUSTOM_SHEETS[sheet])
	# Sans repos, il n'y a pas de figurine : la fiche reprend la main.
	if not clips.has("idle"):
		return {}

	var idle: Dictionary = clips["idle"]
	return {
		"idle": str(idle["file"]),
		"run": str(clips["run"]["file"]),
		"foot": int(idle["foot"]),
		"pixel_size": PIXEL_SIZE,
		"hover": HOVER if CD.is_flying(stats.character_class) else 0.0,
		"rows": int(idle["rows"]),
		"full_cell": true,
		"clips": clips,
	}


## Les boucles déclarées par une entrée de [constant CUSTOM_SHEETS], mises au
## format commun `{clip: {file, rows, foot}}`.
##
## Les deux écritures de la table se rejoignent ici, et une seule règle les
## sépare : `rows` à plat veut dire « une planche pour tout ». Une planche
## nommée mais absente du disque est passée sous silence plutôt que de faire
## échouer l'habillage entier — c'est ce qui permet de brancher une animation
## avant que son dessin ne soit livré.
static func _custom_clips(sheet: String, entry: Dictionary) -> Dictionary:
	if entry.has("rows"):
		var whole: Dictionary = {"file": sheet, "rows": int(entry["rows"]), "foot": int(entry["foot"])}
		return {"idle": whole, "run": whole.duplicate()}

	var clips: Dictionary = {}
	for clip: String in CLIPS:
		if not entry.has(clip):
			continue
		var part: Dictionary = entry[clip]
		var file: String = str(part.get("file", sheet))
		if not ResourceLoader.exists(file):
			continue
		clips[clip] = {"file": file, "rows": int(part["rows"]), "foot": int(part["foot"])}

	# Une figurine sans foulée marche sur son repos, comme l'elfe rousse.
	if clips.has("idle") and not clips.has("run"):
		clips["run"] = clips["idle"].duplicate()
	return clips


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
