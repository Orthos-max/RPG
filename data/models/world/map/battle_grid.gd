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


## Coordonnée de grille d'un point du monde.
##
## Arrondi au demi supérieur (`floor(x + 0.5)`) et non `round()` : les tuiles
## générées tombent sur des positions en .5, et `round()` s'éloigne de zéro,
## ce qui ouvrirait un trou d'une case entre -0.5 et +0.5 — deux voisines
## cesseraient de l'être au milieu de la carte.
func coord_at_position(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_position.x / tile_size + 0.5),
		floori(world_position.z / tile_size + 0.5),
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


## Nombre de cases inscrites.
func size() -> int:
	return _tile_at.size()


## Les tuiles orthogonalement adjacentes, à une dénivellation près.
## [param tile] La tuile de départ.
## [param max_height_diff] Écart de hauteur toléré — au-delà, on ne passe pas.
func neighbors_of(tile: Node, max_height_diff: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if not has_tile(tile):
		return found

	var coord: Vector2i = coord_of(tile)
	var from_height: float = height_at(coord)
	for offset: Vector2i in NEIGHBOR_OFFSETS:
		var neighbor_coord: Vector2i = coord + offset
		var neighbor: Node = _tile_at.get(neighbor_coord)
		if not neighbor:
			continue
		if absf(height_at(neighbor_coord) - from_height) <= max_height_diff:
			found.append(neighbor as Node3D)

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
