class_name StatusAura
extends RefCounted
## À quoi ressemble une affliction sur le plateau — une table, pas un système.
##
## [StatusDB] dit ce qu'un statut [i]fait[/i], [StatusEffects] ce qu'il devient au
## fil des tours ; celle-ci dit ce qu'il [i]a l'air[/i]. Le partage est le même
## qu'entre [PawnLook] et la fiche d'unité : une couche de vue, sans nœud, sans
## scène, que [StatusVFX] se contente d'appliquer.
##
## [b]Pourquoi une table pure et pas des particules écrites dans le pion.[/b]
## Le choix « quel effet pour quelles afflictions » est une décision de jeu — un
## empoisonné qui brûle porte deux auras, un statut inconnu n'en porte aucune, un
## statut expiré perd la sienne. C'est exactement le genre de règle qu'on veut
## pouvoir vérifier en `--headless`, où aucune particule n'existe. [method plan]
## rend donc la liste des auras à afficher pour une liste d'afflictions, et c'est
## la seule chose que les tests ont besoin de connaître.
##
## Les trois auras se distinguent [b]à la couleur d'abord, au mouvement ensuite[/b] :
## le poison monte lentement en vert, la brûlure crache de l'orange vers le haut,
## la paralysie grésille en jaune tout autour du buste. Deux pions côte à côte
## doivent se lire d'un coup d'œil, sans passer par l'étiquette de survol.

const DB = preload("res://data/models/world/stats/status_db.gd")
const STATUS = preload("res://data/services/combat/status_effects.gd")

## Hauteur du buste au-dessus de la case — la même que [BattleVFX].
const TORSO_HEIGHT: float = 0.9

## L'aura de chaque statut du catalogue.
##
## Les clés sont celles de [StatusDB] ; un statut sans entrée ici ne porte
## simplement aucune aura (voir la garde de test « tout statut a une aura »).
##
## Chaque champ : `texture` l'image d'effet (`assets/textures/effects/`),
## `color` la teinte, `amount` le nombre de grains vivants à la fois, `lifetime`
## leur durée de vie, `speed` leur vitesse initiale (min/max), `spread` l'angle
## de tir autour de `direction`, `gravity` ce qui les emporte ensuite, `size` la
## taille d'un grain, `radius` le rayon d'émission autour du pion, `height` la
## hauteur d'émission, et `additive` le mode de fondu.
##
## [b]Peu de grains, courte vie.[/b] Une aura persiste tant que l'affliction
## tient, et une bataille peut en porter une dizaine à l'écran : 10 à 16 grains
## par effet suffisent à la lisibilité et laissent le budget de rendu tranquille.
const SPECS: Dictionary = {
	"poison": {
		"texture": &"mote",
		"color": Color(0.36, 0.93, 0.34),
		"amount": 12,
		"lifetime": 1.5,
		"speed": Vector2(0.12, 0.32),
		"spread": 18.0,
		"gravity": Vector3(0.0, 0.32, 0.0),
		"size": 0.085,
		"radius": 0.26,
		"height": 0.30,
		"additive": true,
	},
	"burn": {
		"texture": &"spark",
		"color": Color(1.0, 0.44, 0.10),
		"amount": 16,
		"lifetime": 0.55,
		"speed": Vector2(0.7, 1.5),
		"spread": 24.0,
		"gravity": Vector3(0.0, 1.4, 0.0),
		"size": 0.10,
		"radius": 0.20,
		"height": 0.20,
		"additive": true,
	},
	"paralyze": {
		"texture": &"spark",
		# Les décharges partent dans tous les sens (`spread` à 180°) et vivent un
		# quart de seconde : l'œil ne voit pas des grains qui montent, il voit un
		# grésillement — c'est ce qui sépare la paralysie de la brûlure, dont les
		# étincelles suivent toutes la même colonne.
		"color": Color(1.0, 0.93, 0.22),
		"amount": 10,
		"lifetime": 0.22,
		"speed": Vector2(1.1, 2.2),
		"spread": 180.0,
		"gravity": Vector3.ZERO,
		"size": 0.07,
		"radius": 0.30,
		"height": TORSO_HEIGHT,
		"additive": true,
	},
	"frost": {
		"texture": &"mote",
		"color": Color(0.62, 0.90, 1.0),
		"amount": 12,
		"lifetime": 1.4,
		"speed": Vector2(0.10, 0.28),
		"spread": 35.0,
		"gravity": Vector3(0.0, -0.30, 0.0),
		"size": 0.075,
		"radius": 0.28,
		"height": 1.05,
		"additive": true,
	},
}


## Le statut a-t-il une aura ?
static func has_aura(status: String) -> bool:
	return SPECS.has(DB.canonical_key(status))


## L'aura d'un statut — dictionnaire vide s'il n'en a pas.
##
## La copie est délibérée : l'appelant règle des particules à partir de ce
## dictionnaire, et une table de constantes ne doit pas repartir modifiée.
static func aura(status: String) -> Dictionary:
	var key: String = DB.canonical_key(status)
	if not SPECS.has(key):
		return {}
	var out: Dictionary = (SPECS[key] as Dictionary).duplicate(true)
	out["status"] = key
	return out


## Les auras à afficher pour une liste d'afflictions.
##
## [b]La fonction pure de tout ce module.[/b] Elle prend ce que porte [Stats]
## ([method Stats.active_statuses]) et rend, dans l'ordre du catalogue de la
## liste, un dictionnaire d'aura par affliction — statuts inconnus écartés,
## durées épuisées écartées, doublons fondus, puisque la liste passe d'abord par
## [method StatusEffects.sanitize].
##
## Une unité saine rend `[]`, et c'est le cas qui éteint toutes les auras.
static func plan(entries: Array) -> Array:
	var out: Array = []
	for raw: Variant in STATUS.sanitize(entries):
		var spec: Dictionary = aura(str((raw as Dictionary)["status"]))
		if not spec.is_empty():
			out.append(spec)
	return out


## Les seules clés de [method plan] — ce que [StatusVFX] allume, et rien d'autre.
static func plan_keys(entries: Array) -> Array[String]:
	var keys: Array[String] = []
	for spec: Variant in plan(entries):
		keys.append(str((spec as Dictionary)["status"]))
	return keys
