class_name MapData
extends Resource
## Grid-based map definition. Each cell defines terrain type and tile height.
## Used by TacticsArena to procedurally generate the 3D arena.

enum TerrainType {
	GRASS = 0,   ## Walkable plain, green
	FOREST = 1,  ## Walkable forest, dark green, +1 DEF bonus
	MOUNTAIN = 2,## Impassable mountain peak, brown/rock
	WATER = 3,   ## Impassable water, blue
	PATH = 4,    ## Walkable dirt path, beige
	WALL = 5,    ## Impassable wall, dark grey
	PIT = 6,     ## Impassable pit/chasm, black
}

## Grid dimensions (columns × rows)
@export var grid_size: Vector2i = Vector2i(16, 10)

## Size of each tile in world units
@export var tile_size: float = 1.0

## Flattened 2D array of terrain types (int, matching TerrainType enum).
## Index = row * grid_size.x + col
@export var terrain_grid: Array[int] = []

## Flattened 2D array of tile heights (float, in world units).
## 0.0 = ground level, positive = elevated
@export var height_grid: Array[float] = []


## Initialize a default blank map (all grass, height 0)
func init_default() -> void:
	var total: int = grid_size.x * grid_size.y
	terrain_grid.resize(total)
	height_grid.resize(total)
	for i in total:
		terrain_grid[i] = TerrainType.GRASS
		height_grid[i] = 0.0


## Get terrain at grid position
func get_terrain(col: int, row: int) -> int:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= terrain_grid.size():
		return TerrainType.GRASS
	return terrain_grid[idx]


## Set terrain at grid position
func set_terrain(col: int, row: int, terrain: int) -> void:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= terrain_grid.size():
		return
	terrain_grid[idx] = terrain


## Get height at grid position
func get_height(col: int, row: int) -> float:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= height_grid.size():
		return 0.0
	return height_grid[idx]


## Set height at grid position
func set_height(col: int, row: int, h: float) -> void:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= height_grid.size():
		return
	height_grid[idx] = h


## Check if a terrain type is walkable
static func is_walkable(terrain: int) -> bool:
	return terrain != TerrainType.MOUNTAIN and terrain != TerrainType.WATER and terrain != TerrainType.WALL and terrain != TerrainType.PIT


## Check if a terrain type provides a defense bonus
static func get_defense_bonus(terrain: int) -> int:
	match terrain:
		TerrainType.FOREST:
			return 1
		TerrainType.MOUNTAIN:
			return 3
		_:
			return 0
