class_name TacticsGrid
extends RefCounted
## Conversions monde 3D ↔ grille (col, row).
##
## Le pont CielAI et l'IA locale raisonnent en coordonnées de grille alors que
## l'arène vit en coordonnées monde : cette classe est le seul endroit qui
## connaît la formule de conversion.

const MapDataRef = preload("res://data/models/world/map/map_data.gd")

## Position de repli quand l'arène n'expose pas de MapData
const FALLBACK_GRID := Vector2i(16, 10)


## Toutes les tuiles de l'arène (tableau vide si l'arène n'est pas prête).
static func tiles(arena: Node) -> Array:
	if not arena or not is_instance_valid(arena):
		return []
	var node: Node = arena.get_node_or_null("Tiles")
	if not node:
		return []
	return node.get_children()


## Taille de la grille de l'arène.
static func grid_size(arena: Node) -> Vector2i:
	var md: Resource = _map_data(arena)
	if md:
		return md.grid_size
	return FALLBACK_GRID


## Taille d'une tuile en unités monde.
static func tile_size(arena: Node) -> float:
	var md: Resource = _map_data(arena)
	if md:
		return md.tile_size
	return 1.0


## Convertit une tuile en coordonnées de grille. Renvoie (-1,-1) si impossible.
static func tile_to_grid(arena: Node, tile: Node3D) -> Vector2i:
	if not tile or not is_instance_valid(tile):
		return Vector2i(-1, -1)

	# L'index de bataille tient déjà la réponse, et sans MapData. La formule qui
	# suit ne sert qu'aux tuiles qu'il ne connaît pas (éditeur, scène isolée).
	var grid: BattleGrid = BattleGrid.current
	if grid and grid.has_tile(tile):
		return grid.cell_of(tile)

	var gs: Vector2i = grid_size(arena)
	var ts: float = tile_size(arena)
	var pos: Vector3 = tile.global_position

	var col: int = int(round((pos.x / ts) + (float(gs.x) / 2.0) - 0.5))
	var row: int = int(round((pos.z / ts) + (float(gs.y) / 2.0) - 0.5))
	return Vector2i(clampi(col, 0, gs.x - 1), clampi(row, 0, gs.y - 1))


## Tuile située à une position de grille (null si absente).
static func find_tile(arena: Node, col: int, row: int) -> Node3D:
	# Consultation directe plutôt qu'un balayage de toutes les tuiles.
	var grid: BattleGrid = BattleGrid.current
	if grid and grid.size() > 0:
		var found: Node = grid.tile_at_cell(Vector2i(col, row))
		if found is Node3D:
			return found as Node3D

	for tile in tiles(arena):
		if tile is Node3D and tile_to_grid(arena, tile) == Vector2i(col, row):
			return tile
	return null


## Bonus défensif du terrain d'une tuile.
static func terrain_defense(tile: Node) -> int:
	if not tile or not is_instance_valid(tile):
		return 0
	var terrain: Variant = tile.get("terrain_type")
	if terrain == null:
		return 0
	return MapDataRef.get_defense_bonus(int(terrain))


## Nom lisible du terrain d'une tuile.
static func terrain_name(tile: Node) -> String:
	if not tile or not is_instance_valid(tile):
		return "unknown"
	var terrain: Variant = tile.get("terrain_type")
	if terrain == null:
		return "unknown"
	return terrain_type_name(int(terrain))


## Nom lisible d'un type de terrain.
static func terrain_type_name(terrain: int) -> String:
	match terrain:
		MapDataRef.TerrainType.GRASS: return "grass"
		MapDataRef.TerrainType.FOREST: return "forest"
		MapDataRef.TerrainType.MOUNTAIN: return "mountain"
		MapDataRef.TerrainType.WATER: return "water"
		MapDataRef.TerrainType.PATH: return "path"
		MapDataRef.TerrainType.WALL: return "wall"
		MapDataRef.TerrainType.PIT: return "pit"
		_: return "unknown"


## Tuiles actuellement marquées atteignables, en coordonnées de grille.
## [returns] [{col, row, def_bonus, terrain}]
static func reachable_tiles(arena: Node) -> Array:
	var out: Array = []
	for tile in tiles(arena):
		if not tile.get("reachable"):
			continue
		var g: Vector2i = tile_to_grid(arena, tile)
		out.append({
			"col": g.x, "row": g.y,
			"def_bonus": terrain_defense(tile),
			"terrain": terrain_name(tile),
		})
	return out


## Cases situées à portée (distance de Manhattan) d'une position de grille.
## Calcul géométrique : n'écrase pas le marquage de pathfinding en cours.
## [returns] [{col, row}]
static func tiles_in_range(arena: Node, center: Vector2i, reach: int) -> Array:
	var gs: Vector2i = grid_size(arena)
	var out: Array = []
	if center.x < 0 or center.y < 0 or reach <= 0:
		return out
	for d_row in range(-reach, reach + 1):
		var span: int = reach - absi(d_row)
		for d_col in range(-span, span + 1):
			if d_col == 0 and d_row == 0:
				continue
			var col: int = center.x + d_col
			var row: int = center.y + d_row
			if col < 0 or row < 0 or col >= gs.x or row >= gs.y:
				continue
			out.append({"col": col, "row": row})
	return out


## Tuiles actuellement marquées attaquables, en coordonnées de grille.
static func attackable_tiles(arena: Node) -> Array:
	var out: Array = []
	for tile in tiles(arena):
		if not tile.get("attackable"):
			continue
		var g: Vector2i = tile_to_grid(arena, tile)
		out.append({"col": g.x, "row": g.y})
	return out


static func _map_data(arena: Node) -> Resource:
	if not arena or not is_instance_valid(arena):
		return null
	var res: Variant = arena.get("res")
	if not res:
		return null
	return res.get("map_data")
