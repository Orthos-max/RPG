class_name TacticsArenaService
extends RefCounted
## Service class for TacticsArena

## The service we inject into every tile
const TILE_SERVICE = preload("res://data/models/world/combat/arena/tile_service/service.gd")
const MAP_DATA = preload("res://data/models/world/map/map_data.gd")

var res: TacticsArenaResource
## L'index de la grille de cette arène, posé par [method configure_tiles].
var grid: BattleGrid = null
## Le parcours en cours. Il vivait sur les tuiles ; il vit désormais ici, indexé
## par coordonnée — les tuiles ne font plus que s'afficher.
var field := PathField.new()


## Initialize the service with a TacticsArenaResource
## [param _res] The TacticsArenaResource to use
func _init(_res: TacticsArenaResource) -> void:
	res = _res


## Set up the arena by connecting signals
## [param arena] The TacticsArena to set up
func setup(arena: TacticsArena) -> void:
	if not res:
		push_error("TacticsArena needs an ArenaResource from /data/models/world/combat/arena/")
	else:
		res.connect("called_reset_all_tile_markers", arena.reset_all_tile_markers)
		res.connect("called_get_pathfinding_tilestack", arena.get_pathfinding_tilestack)
		res.connect("called_mark_hover_tile", arena.mark_hover_tile)


## Reset markers for all tiles in the arena
## [param arena] The TacticsArena containing the tiles
func reset_all_tile_markers(arena: TacticsArena) -> void:
	field.clear()
	for _t: TacticsTile in arena.get_node("Tiles").get_children():
		_t.reset_markers()


## Configure tiles in the arena
## [param arena] The TacticsArena to configure
func configure_tiles(arena: TacticsArena) -> void:
	arena.get_node("Tiles").visible = true
	var _tiles: Node3D = arena.get_node("Tiles")
	TILE_SERVICE.tiles_into_staticbodies(_tiles)

	# L'index de grille se bâtit une fois les tuiles converties : c'est leur
	# position finale qui donne les coordonnées. Les pions se cherchent depuis le
	# niveau, qui les porte tous, quel que soit leur camp.
	var pawn_root: Node = arena.get_parent() if arena.get_parent() else arena
	var tile_size: float = arena.res.map_data.tile_size if arena.res and arena.res.map_data else 0.0
	grid = BattleGrid.build_for(_tiles, pawn_root, tile_size)
	arena.grid = grid


## Calcule le parcours depuis une tuile.
##
## [param root_tile] La tuile de départ.
## [param height] Le dénivelé franchissable d'une case à l'autre (le saut).
## [param allies_on_map] Les unités du camp qui joue. **C'est cette liste qui dit
## de quel calcul il s'agit** :
##
## - **non vide** — un déplacement. On traverse les siens, jamais l'adversaire.
## - **vide** — une portée d'arme. L'occupation ne compte pas : un arc tire
##   par-dessus les têtes, et une cible doit rester visée même si quelqu'un se
##   tient entre les deux.
func process_surrounding_tiles(root_tile: TacticsTile, height: float, allies_on_map: Array = []) -> void:
	if not grid or not grid.has_tile(root_tile):
		return
	field.expand(grid, grid.coord_of(root_tile), height,
		func(coord: Vector2i) -> bool: return _passable(coord, allies_on_map))


## Une case se traverse-t-elle ? Terrain d'abord, occupation ensuite.
##
## Traverser n'est pas s'arrêter : [method mark_reachable_tiles] refuse toute
## case occupée comme destination. On peut donc passer derrière son voisin sans
## pouvoir se poser sur lui — la règle de Fire Emblem.
##
## C'est ce que le code d'origine annonçait sans le faire : son test
## « l'occupant est-il un allié ? » était enfermé dans une branche qui ne
## s'exécutait que si la liste d'alliés était **vide**, donc il répondait
## toujours non. Résultat, une unité était arrêtée par ses propres camarades.
func _passable(coord: Vector2i, allies_on_map: Array) -> bool:
	var tile: Node = grid.tile_at(coord)
	if not tile:
		return false
	if not MAP_DATA.is_walkable(int(tile.terrain_type)):
		return false

	if allies_on_map.is_empty():
		return true  # Portée d'arme : l'occupation ne compte pas.

	var occupier: Object = grid.occupant_of(tile)
	return occupier == null or occupier in allies_on_map


## Get the pathfinding tilestack to a target tile
## [param to] The target tile
## [returns] Array of global positions forming the path
func get_pathfinding_tilestack(to: TacticsTile) -> Array:
	var _path_tiles_stack: Array = []

	if grid and grid.has_tile(to):
		for coord: Vector2i in field.path_to(grid.coord_of(to)):
			var tile: Node3D = grid.tile_at(coord) as Node3D
			if not tile:
				continue
			tile.hover = true
			_path_tiles_stack.append(tile.global_position)

	res.path_tiles_stack = _path_tiles_stack
	return _path_tiles_stack


## Get the nearest tile adjacent to a target pawn
## [param pawn] The pawn seeking a target
## [param target_pawns] Array of potential target pawns
## [returns] The nearest adjacent tile or the pawn's current tile if no target found
func get_nearest_target_adjacent_tile(pawn: TacticsPawn, target_pawns: Array) -> TacticsTile:
	var _nearest_target: TacticsTile = null

	for _p: TacticsPawn in target_pawns:
		if not is_instance_valid(_p) or not _p.stats or _p.stats.curr_health <= 0:
			continue
		# Une unité hors grille n'a pas de case : `get_tile()` rend `null`, et le
		# parcours de ses voisines faisait tomber le tour adverse.
		var stand: TacticsTile = _p.get_tile()
		if not stand:
			continue
		for _n: TacticsTile in stand.get_neighbors(pawn.stats.jump):
			if not _nearest_target or _distance_of(_n) < _distance_of(_nearest_target):
				if _distance_of(_n) > 0 and not _n.is_taken():
					_nearest_target = _n

	# Remonter le chemin jusqu'à une case réellement à portée de mouvement.
	while _nearest_target and not _nearest_target.reachable:
		_nearest_target = _root_tile_of(_nearest_target)

	if _nearest_target:
		return _nearest_target
	else:
		DebugLog.debug_nospam("nearest_target", pawn)
		return pawn.get_tile()


## Nombre de pas jusqu'à une tuile, dans le parcours en cours.
func _distance_of(tile: TacticsTile) -> float:
	if not grid or not grid.has_tile(tile):
		return 0.0
	return field.distance_at(grid.coord_of(tile))


## La tuile d'où l'on vient pour atteindre celle-ci, ou `null` à l'origine.
func _root_tile_of(tile: TacticsTile) -> TacticsTile:
	if not grid or not grid.has_tile(tile):
		return null
	var coord: Vector2i = grid.coord_of(tile)
	if not field.has_root(coord):
		return null
	return grid.tile_at(field.root_of(coord)) as TacticsTile


## Get the weakest attackable pawn from an array of pawns
## [param pawn_arr] Array of pawns to evaluate
## [returns] The weakest attackable pawn or null if none found
func get_weakest_attackable_pawn(pawn_arr: Array) -> TacticsPawn:
	var _weakest: TacticsPawn = null
	
	for _p: TacticsPawn in pawn_arr:
		if not is_instance_valid(_p) or not _p.stats:
			continue
		if not _weakest or _p.stats.curr_health < _weakest.stats.curr_health:
			var stand: TacticsTile = _p.get_tile()
			if _p.stats.curr_health > 0 and stand and stand.attackable:
				_weakest = _p
	
	return _weakest


## Mark a tile as hovered and unmark others
## [param arena] The TacticsArena containing the tiles
## [param tile] The tile to mark as hovered
func mark_hover_tile(arena: TacticsArena, tile: TacticsTile) -> void:
	for _t: TacticsTile in arena.get_node("Tiles").get_children():
		_t.hover = false
	
	if tile:
		tile.hover = true


## Mark reachable tiles within a certain distance from a root tile
## [param arena] The TacticsArena containing the tiles
## [param root] The starting tile
## [param distance] The maximum distance to consider
func mark_reachable_tiles(arena: TacticsArena, root: TacticsTile, distance: float) -> void:
	for _t: TacticsTile in arena.get_node("Tiles").get_children():
		var _dist: float = _distance_of(_t)
		var _has_dist: bool = _dist > 0
		var _reachable: bool = _dist <= distance
		var _not_taken: bool = not _t.is_taken()
		var _is_root: bool = _t == root

		_t.reachable = (_has_dist and _reachable and _not_taken) or _is_root


## Marque les cases qu'une unité peut frapper depuis sa tuile.
##
## [param distance] Portée maximale de l'arme.
## [param min_distance] Portée **minimale** — un arc vaut 2 et ne frappe pas au
## contact. Sans ce plancher, Virion tirait à bout portant : la portée d'arme
## avait un plafond mais pas de seuil, et seule la riposte connaissait la règle.
func mark_attackable_tiles(arena: TacticsArena, root: TacticsTile, distance: float,
		min_distance: float = 1.0) -> void:
	for _t: TacticsTile in arena.get_node("Tiles").get_children():
		var _dist: float = _distance_of(_t)
		var _has_dist: bool = _dist > 0
		var _in_reach: bool = _dist <= distance and _dist >= min_distance
		var _is_root: bool = _t == root

		_t.attackable = (_has_dist and _in_reach) or _is_root
