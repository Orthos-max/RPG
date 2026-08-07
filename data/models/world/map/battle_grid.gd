class_name BattleGrid
extends RefCounted
## L'index de la grille de bataille, en données pures.
##
## Deux questions gouvernent toute la tactique : « qui est à côté de qui » et
## « cette case est-elle occupée ». Le jeu les posait à des rayons 3D
## ([TacticsTileRaycast]), donc à un moteur physique, donc à une scène montée —
## c'est pourquoi aucun tour de combat n'était vérifiable en headless.
##
## Ici, elles se répondent par de l'arithmétique sur des coordonnées. Les tuiles
## ne servent plus qu'à l'affichage ; leur position dans le monde n'est lue
## qu'une fois, à la construction.
##
## Une bataille à la fois : [member current] donne l'index en cours, ce qui évite
## à chaque tuile de remonter jusqu'à l'arène pour poser sa question.

## Les quatre voisins orthogonaux. Pas de diagonale : la règle du jeu est celle
## de Fire Emblem, on se déplace en croix.
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## Index de la bataille en cours, ou `null` hors combat.
static var current: BattleGrid = null

## Côté d'une case, en unités de monde.
var tile_size: float = 1.0

## Vector2i -> nœud de tuile
var _tile_at: Dictionary = {}
## instance_id d'une tuile -> Vector2i
var _coord_of: Dictionary = {}
## Vector2i -> hauteur (y) de la tuile
var _height_at: Dictionary = {}
## Vector2i -> pion qui l'occupe
var _occupant_at: Dictionary = {}
## Coordonnée de la case (0, 0) du damier.
var _origin: Vector2i = Vector2i.ZERO

## Repère du damier : une tuile réelle, sa position et sa coordonnée.
##
## Sans lui, on ne sait pas *où* le quadrillage est posé. Voir
## [method coord_at_position] : c'est toute l'affaire.
var _anchor_world := Vector2.ZERO
var _anchor_coord := Vector2i.ZERO
var _anchored: bool = false

## Racine sous laquelle chercher les pions. L'occupation se recalcule à partir
## de leur position : aucun pion n'a à signaler ses déplacements.
var _pawn_root: Node = null
## Image du dernier recalcul, pour n'en faire qu'un par image affichée.
var _occupancy_frame: int = -1


## Construit l'index à partir des tuiles réellement en scène.
##
## Passer par les nœuds plutôt que par [MapData] n'est pas un détour : les
## chapitres écrits à la main n'ont pas de MapData, et leurs tuiles sont posées
## dans l'éditeur. Lire la scène couvre les deux cas.
## [param tiles_parent] Le nœud « Tiles » de l'arène.
## [param pawn_root] La racine sous laquelle vivent les pions (le niveau).
## [param size] Côté d'une case ; déduit des positions si nul.
static func build_for(tiles_parent: Node3D, pawn_root: Node, size: float = 0.0) -> BattleGrid:
	var grid: BattleGrid = BattleGrid.new()
	grid._pawn_root = pawn_root

	var tiles: Array = []
	for child: Node in tiles_parent.get_children():
		if child is TacticsTile:
			tiles.append(child)

	grid.tile_size = size if size > 0.0 else BattleGrid._infer_tile_size(tiles)
	for tile: Node3D in tiles:
		grid.add_tile(tile, tile.global_position)

	current = grid
	return grid


## Inscrit une tuile à la coordonnée que sa position désigne.
func add_tile(tile: Node, world_position: Vector3) -> void:
	var coord: Vector2i = coord_at_position(world_position)

	# La première tuile inscrite devient le repère du damier : à partir d'elle,
	# toute position se compte en cases pleines, sans supposer où tombent les
	# centres.
	if not _anchored:
		_anchor_world = Vector2(world_position.x, world_position.z)
		_anchor_coord = coord
		_anchored = true

	_tile_at[coord] = tile
	_coord_of[tile.get_instance_id()] = coord
	_height_at[coord] = world_position.y

	# L'origine suit la case la plus au nord-ouest : c'est elle qui fait le pont
	# entre les coordonnées signées d'ici et le (colonne, ligne) partant de zéro
	# que parlent le pont CielAI et les cartes.
	if _tile_at.size() == 1:
		_origin = coord
	else:
		_origin = Vector2i(mini(_origin.x, coord.x), mini(_origin.y, coord.y))


## Coordonnées (colonne, ligne) d'une tuile, comptées depuis zéro.
## Renvoie (-1, -1) si la tuile est inconnue de l'index.
func cell_of(tile: Node) -> Vector2i:
	if not has_tile(tile):
		return Vector2i(-1, -1)
	return coord_of(tile) - _origin


## Tuile posée à une (colonne, ligne), ou `null`.
func tile_at_cell(cell: Vector2i) -> Node:
	return _tile_at.get(cell + _origin)


## Coordonnée de grille d'un point du monde — la case **la plus proche**.
##
## On compte les cases depuis une tuile réelle, et on arrondit. Sans ce repère,
## il faudrait deviner où le quadrillage est posé, et c'est là qu'était le piège :
## `floori(x + 0.5)` suppose des centres de case sur les entiers. Or une carte de
## largeur **paire** les met sur les demis (…, 1.5, 2.5, …) — et la formule
## plaçait alors la frontière entre deux cases exactement sur le centre de l'une
## d'elles. Un pion arrêté à quelques centièmes en deçà de son centre était
## attribué à la case précédente ; `adjust_to_center` l'y recollait, et il
## terminait son déplacement une case trop tôt. Mesuré le 2026-08-07 sur le
## chapitre 1 : visait la case (8, 7), finissait en (8, 6).
##
## Compter depuis une tuile connue règle les deux paritées d'un coup, et rend à
## chaque case la moitié de l'écart qui la sépare de ses voisines.
func coord_at_position(world_position: Vector3) -> Vector2i:
	if not _anchored:
		# Aucune tuile inscrite encore : c'est cet appel-là qui pose le repère,
		# et l'étiquette qu'il choisit n'a qu'à être cohérente avec elle-même.
		return Vector2i(
			floori(world_position.x / tile_size + 0.5),
			floori(world_position.z / tile_size + 0.5),
		)
	return _anchor_coord + Vector2i(
		roundi((world_position.x - _anchor_world.x) / tile_size),
		roundi((world_position.z - _anchor_world.y) / tile_size),
	)


## La tuile connaît-elle sa place dans l'index ?
func has_tile(tile: Node) -> bool:
	return tile != null and _coord_of.has(tile.get_instance_id())


## Coordonnée d'une tuile inscrite.
func coord_of(tile: Node) -> Vector2i:
	return _coord_of.get(tile.get_instance_id(), Vector2i.ZERO)


## Tuile posée à une coordonnée, ou `null`.
func tile_at(coord: Vector2i) -> Node:
	return _tile_at.get(coord)


## Hauteur (y) d'une coordonnée.
func height_at(coord: Vector2i) -> float:
	return _height_at.get(coord, 0.0)


## Emprise réelle de la grille, en (colonnes, lignes).
##
## Une carte générée depuis [MapData] connaît ses dimensions d'avance ; une carte
## posée à la main, non — et [TacticsGrid.grid_size] retombait alors sur un
## 16×10 de secours, faux pour le 10×20 du chapitre 2. L'index, lui, sait ce
## qu'il a inscrit.
func dimensions() -> Vector2i:
	if _tile_at.is_empty():
		return Vector2i.ZERO
	var span := Vector2i.ZERO
	for coord: Vector2i in _tile_at:
		var cell: Vector2i = coord - _origin
		span.x = maxi(span.x, cell.x)
		span.y = maxi(span.y, cell.y)
	return span + Vector2i.ONE


## Nombre de cases inscrites.
func size() -> int:
	return _tile_at.size()


## Les coordonnées orthogonalement adjacentes, à une dénivellation près.
##
## C'est la forme utile au parcours ([PathField]), qui raisonne en coordonnées
## et n'a que faire des nœuds : une tuile n'a plus à exister pour qu'on sache
## par où l'on passe.
## [param coord] La case de départ.
## [param max_height_diff] Écart de hauteur toléré — au-delà, on ne passe pas.
func neighbor_coords(coord: Vector2i, max_height_diff: float) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if not _tile_at.has(coord):
		return found

	var from_height: float = height_at(coord)
	for offset: Vector2i in NEIGHBOR_OFFSETS:
		var neighbor_coord: Vector2i = coord + offset
		if not _tile_at.has(neighbor_coord):
			continue
		if absf(height_at(neighbor_coord) - from_height) <= max_height_diff:
			found.append(neighbor_coord)

	return found


## Les tuiles orthogonalement adjacentes, à une dénivellation près.
## [param tile] La tuile de départ.
## [param max_height_diff] Écart de hauteur toléré — au-delà, on ne passe pas.
func neighbors_of(tile: Node, max_height_diff: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if not has_tile(tile):
		return found

	for neighbor_coord: Vector2i in neighbor_coords(coord_of(tile), max_height_diff):
		found.append(_tile_at[neighbor_coord] as Node3D)

	return found


## Le pion posé sur cette tuile, ou `null`.
func occupant_of(tile: Node) -> Object:
	if not has_tile(tile):
		return null
	refresh_occupancy()
	return _occupant_at.get(coord_of(tile))


## Cette tuile porte-t-elle un pion ?
func is_taken(tile: Node) -> bool:
	return occupant_of(tile) != null


## Recalcule qui occupe quoi depuis la position des pions.
##
## Une fois par image suffit : entre deux, rien ne bouge du point de vue des
## règles. [param force] contourne ce cache — utile aux tests, qui ne font pas
## défiler d'images.
func refresh_occupancy(force: bool = false) -> void:
	var frame: int = Engine.get_process_frames()
	if not force and frame == _occupancy_frame:
		return
	_occupancy_frame = frame

	_occupant_at.clear()
	if _pawn_root and is_instance_valid(_pawn_root):
		_collect_pawns(_pawn_root)


## Pose un pion sur une case, sans attendre le prochain recalcul.
## Les tests s'en servent pour bâtir une situation sans monter de scène.
func place_occupant(coord: Vector2i, pawn: Object) -> void:
	if pawn == null:
		_occupant_at.erase(coord)
	else:
		_occupant_at[coord] = pawn
	_occupancy_frame = Engine.get_process_frames()


## Parcourt l'arbre à la recherche des pions. On ne descend pas dans un pion :
## ses enfants sont sa figurine et son interface, jamais un autre pion.
func _collect_pawns(node: Node) -> void:
	for child: Node in node.get_children():
		if child is TacticsPawn:
			_occupant_at[coord_at_position((child as Node3D).global_position)] = child
		else:
			_collect_pawns(child)


## Déduit le côté d'une case de l'écart **médian** entre deux colonnes de tuiles.
##
## Le plus petit écart ne convient pas : sur une carte posée à la main, deux
## tuiles peuvent se trouver à 0,996 l'une de l'autre au lieu de 1,0 — quatre
## millièmes qui ne se voient pas à l'œil. Retenir ce 0,996 comme côté de case
## décale progressivement le calcul des coordonnées, jusqu'à faire **sauter une
## colonne entière** : deux tuiles tombent sur la même case, une case reste vide,
## et le plateau se retrouve percé de part en part. C'est ce qui coupait le
## chapitre 2 en deux moitiés injoignables (2026-08-06) — 160 cases indexées pour
## 200 tuiles posées.
##
## La médiane, elle, ignore une poignée d'irrégularités : il faudrait que la
## moitié de la carte soit de travers pour la tromper.
static func _infer_tile_size(tiles: Array) -> float:
	var xs: Array[float] = []
	for tile: Node3D in tiles:
		var x: float = tile.global_position.x
		if not xs.has(x):
			xs.append(x)
	return tile_size_from_columns(xs)


## Côté de case déduit des abscisses des colonnes — la médiane de leurs écarts.
##
## Séparé de [method _infer_tile_size] pour être éprouvable sans monter de scène :
## c'est cette arithmétique-là qui a coupé le chapitre 2 en deux.
static func tile_size_from_columns(xs: Array[float]) -> float:
	if xs.size() < 2:
		return 1.0

	var sorted_xs: Array[float] = xs.duplicate()
	sorted_xs.sort()
	var gaps: Array[float] = []
	for i: int in range(1, sorted_xs.size()):
		var gap: float = sorted_xs[i] - sorted_xs[i - 1]
		if gap > 0.001:
			gaps.append(gap)
	if gaps.is_empty():
		return 1.0

	gaps.sort()
	return gaps[gaps.size() / 2]
