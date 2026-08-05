class_name TacticsFraming
extends RefCounted
## Le cadrage d'une bataille : orthographique, incliné, posé sur le plateau.
##
## La caméra tactique vit dans `main.tscn`, au-dessus des niveaux qui vont et
## viennent : elle entrait donc en bataille là où l'écran précédent l'avait
## laissée — à l'origine du monde, avec un rayon de déplacement centré sur ce
## même point. Sur une carte posée ailleurs, ou après une dérive quelconque,
## le joueur ouvrait sa première bataille sur un morceau de ciel.
##
## Ce module répond à deux questions, et à elles seules :
## - **où cadrer** : le centre et l'étendue réels du plateau, mesurés sur les
##   tuiles en scène (donc valables aussi pour les chapitres écrits à la main,
##   sans `MapData`) ;
## - **comment cadrer** : la projection orthographique et l'inclinaison fixe du
##   cadrage « Awakening », jusqu'ici prototypées dans `shot.gd` seulement.
##
## Le calcul est pur — il ne touche aucun nœud, il rend des nombres — de façon
## à se vérifier en headless (`test_map.gd`). L'application, elle, est le travail
## de [TacticsCamera], prévenu par un signal de [TacticsCameraResource].

const GridRef = preload("res://data/models/world/utilities/grid.gd")

#region Cadrage « Awakening »
## Inclinaison de la vue, en degrés. Fixe : c'est elle qui fait la signature.
##
## À -52°, une unité debout garde sa silhouette (on la reconnaît) tandis que le
## plateau reste lisible case par case. Plus haut, on tombe sur un plan de
## dessus où tout se ressemble ; plus bas, les rangées du fond se masquent.
const PITCH_DEGREES: float = -52.0

## Orientation de repos, en degrés. Un des quatre quadrants entre lesquels la
## rotation bascule (Q/E) — la vue diagonale, pas de face.
const YAW_DEGREES: int = 315

## Bornes du zoom orthographique, en unités monde (hauteur de l'image).
##
## En orthographique, ce n'est plus l'angle d'ouverture qui règle l'échelle mais
## la hauteur du monde tenant dans l'écran : `size`. 7, c'est sept cases de haut
## — assez près pour lire un duel ; 26 couvre une grande carte d'un seul regard.
const MIN_ORTHO_SIZE: float = 7.0
const MAX_ORTHO_SIZE: float = 26.0

## Marge laissée autour du plateau quand on cadre la carte entière, en cases.
const FIT_MARGIN: float = 3.5

## Bornes du cadrage d'ouverture. Une carte minuscule ne mérite pas qu'on colle
## le nez dessus, une immense ne doit pas rendre les unités illisibles.
const MIN_OPENING_SIZE: float = 9.0
const MAX_OPENING_SIZE: float = 18.0
#endregion


#region Mesures du plateau
## Étendue réelle des tuiles d'une arène : `{center, size}` en unités monde.
##
## Mesurée sur les tuiles plutôt que déduite de `MapData` : les chapitres écrits
## à la main n'en ont pas, et c'est justement là que le centre risque de ne pas
## être l'origine. Renvoie une étendue nulle si l'arène n'a pas (encore) de tuile.
static func board_bounds(arena: Node) -> Dictionary:
	var tiles: Array = GridRef.tiles(arena)
	var lowest: Vector3 = Vector3.ZERO
	var highest: Vector3 = Vector3.ZERO
	var found: bool = false

	for tile: Variant in tiles:
		if not (tile is Node3D) or not is_instance_valid(tile):
			continue
		var pos: Vector3 = (tile as Node3D).global_position
		lowest = lowest.min(pos) if found else pos
		highest = highest.max(pos) if found else pos
		found = true

	if not found:
		return {"center": Vector3.ZERO, "size": Vector2.ZERO}

	return {
		"center": (lowest + highest) / 2.0,
		# Les positions sont celles des centres de tuile : une carte d'une seule
		# colonne mesure quand même une case de large.
		"size": Vector2(highest.x - lowest.x, highest.z - lowest.z),
	}


## Hauteur d'image (`size`) nécessaire pour tenir un plateau entier à l'écran.
##
## Le plateau est vu en diagonale : ses deux côtés se projettent tous les deux
## sur la verticale de l'écran, à 45° chacun, puis l'inclinaison les écrase d'un
## facteur `sin(PITCH)`. C'est cette hauteur écrasée qui gouverne — la largeur
## disponible est plus généreuse sur un écran large.
static func fit_size(board: Vector2) -> float:
	var diagonal: float = (absf(board.x) + absf(board.y)) * cos(deg_to_rad(45.0))
	var foreshortened: float = diagonal * sin(absf(deg_to_rad(PITCH_DEGREES)))
	return foreshortened + FIT_MARGIN


## Hauteur d'image du cadrage d'ouverture : le plateau entier, mais borné.
static func opening_size(arena: Node) -> float:
	var bounds: Dictionary = board_bounds(arena)
	var board: Vector2 = bounds["size"]
	if board == Vector2.ZERO:
		return MIN_OPENING_SIZE
	return clampf(fit_size(board), MIN_OPENING_SIZE, MAX_OPENING_SIZE)


## Rayon dans lequel le joueur peut promener sa vue autour du centre du plateau.
##
## Assez pour amener n'importe quel coin au centre de l'écran, pas assez pour
## perdre la carte de vue : c'est la demi-diagonale du plateau, plus une case.
static func pan_radius(arena: Node) -> float:
	var board: Vector2 = board_bounds(arena)["size"]
	return maxf(board.length() / 2.0 + 1.0, 1.0)
#endregion


#region Application
## Passe un nœud caméra en projection orthographique au cadrage demandé.
##
## En orthographique, `fov` ne veut plus rien dire : deux objets de même taille
## occupent la même place à l'écran quelle que soit leur distance. C'est ce qui
## donne le damier régulier des tactical-RPG — et ce qui oblige le zoom à agir
## sur `size` ([TacticsCameraZoomService]).
static func apply_projection(cam_node: Camera3D, size: float) -> void:
	if not cam_node:
		return
	cam_node.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam_node.size = clampf(size, MIN_ORTHO_SIZE, MAX_ORTHO_SIZE)
	# Le plateau tient dans une poignée d'unités : la portée par défaut (4000)
	# gaspillerait toute la précision du tampon de profondeur.
	cam_node.near = 0.1
	cam_node.far = 200.0
#endregion
