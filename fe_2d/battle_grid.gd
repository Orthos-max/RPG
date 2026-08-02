extends Node2D
## Grille isométrique procédurale — rendu Fire Emblem

const TILE_W := 64
const TILE_H := 32
const COLS := 16
const ROWS := 10

enum Terrain { GRASS, FOREST, MOUNTAIN, WATER, PATH, WALL, PIT }

var terrain_data: Array = []
var highlight_tiles: Dictionary = {}
var selection_tile := Vector2i(-1, -1)
var _rng: RandomNumberGenerator

func _init():
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42
	_generate_map()

func _ready():
	queue_redraw()

func _generate_map():
	terrain_data = []
	terrain_data.resize(COLS * ROWS)
	
	for x in COLS: for y in ROWS:
		terrain_data[y * COLS + x] = Terrain.GRASS
	
	# Château (gauche)
	for x in range(0, 3):
		for y in range(0, 3):
			_set_tile(x, y, Terrain.PATH)
	_set_tile(3, 0, Terrain.PATH); _set_tile(3, 1, Terrain.PATH); _set_tile(3, 2, Terrain.PATH)
	_set_tile(4, 0, Terrain.PATH); _set_tile(4, 1, Terrain.PATH); _set_tile(4, 2, Terrain.PATH)
	
	# Forêts éparses
	for _i in 8:
		var fx = _rng.randi_range(4, 10)
		var fy = _rng.randi_range(0, 9)
		_set_tile(fx, fy, Terrain.FOREST)
		if fx < COLS-1: _set_tile(fx+1, fy, Terrain.FOREST)
	
	# Montagnes (droite)
	for x in range(12, 16):
		for y in range(6, 10):
			_set_tile(x, y, Terrain.MOUNTAIN)
	_set_tile(11, 8, Terrain.MOUNTAIN); _set_tile(11, 9, Terrain.MOUNTAIN)
	_set_tile(12, 5, Terrain.MOUNTAIN)
	
	# Collines isolées
	_set_tile(8, 3, Terrain.MOUNTAIN); _set_tile(9, 3, Terrain.MOUNTAIN)
	
	# Rivière diagonale
	_set_tile(14, 0, Terrain.WATER); _set_tile(14, 1, Terrain.WATER)
	_set_tile(15, 0, Terrain.WATER); _set_tile(15, 1, Terrain.WATER)
	_set_tile(13, 2, Terrain.WATER); _set_tile(12, 3, Terrain.WATER)
	_set_tile(12, 4, Terrain.WATER)
	
	# Routes
	for y in range(3, 8):
		_set_tile(2, y, Terrain.PATH)
	for x in range(2, 7):
		_set_tile(x, 5, Terrain.PATH)

func _set_tile(x: int, y: int, t: Terrain):
	if x >= 0 and x < COLS and y >= 0 and y < ROWS:
		terrain_data[y * COLS + x] = t

func get_terrain(gp: Vector2i) -> Terrain:
	if gp.x < 0 or gp.x >= COLS or gp.y < 0 or gp.y >= ROWS:
		return Terrain.GRASS
	return terrain_data[gp.y * COLS + gp.x]

func is_walkable(gp: Vector2i) -> bool:
	if gp.x < 0 or gp.x >= COLS or gp.y < 0 or gp.y >= ROWS:
		return false
	var t = get_terrain(gp)
	return t != Terrain.WATER and t != Terrain.MOUNTAIN and t != Terrain.WALL and t != Terrain.PIT

func grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(
		(gp.x - gp.y) * TILE_W / 2.0,
		(gp.x + gp.y) * TILE_H / 2.0
	)

func world_to_grid(wp: Vector2) -> Vector2i:
	var fx = wp.x / (TILE_W / 2.0)
	var fy = wp.y / (TILE_H / 2.0)
	return Vector2i(roundi((fx + fy) / 2.0), roundi((fy - fx) / 2.0))

func get_movement_cost(gp: Vector2i) -> int:
	var t = get_terrain(gp)
	return 2 if t == Terrain.FOREST else (1 if is_walkable(gp) else 999)

func get_defense_bonus(gp: Vector2i) -> int:
	var t = get_terrain(gp)
	match t:
		Terrain.FOREST:  return 1
		Terrain.MOUNTAIN: return 2
		_: return 0

func get_movement_range(start: Vector2i, moves: int, blocked: Dictionary = {}) -> Dictionary:
	var result := {}
	var queue: Array = [{"pos": start, "rem": moves}]
	var visited := {start: moves}
	
	while queue.size() > 0:
		var cur = queue.pop_front()
		var pos: Vector2i = cur.pos
		var rem: int = cur.rem
		result[pos] = rem
		if rem <= 0: continue
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var np = pos + dir
			if not is_walkable(np): continue
			if np in blocked: continue
			if np in visited: continue
			var cost = get_movement_cost(np)
			if rem >= cost:
				visited[np] = rem - cost
				queue.append({"pos": np, "rem": rem - cost})
	return result

func _draw():
	for x in COLS:
		for y in ROWS:
			var gp = Vector2i(x, y)
			var pos = grid_to_world(gp)
			var col = _terrain_color(get_terrain(gp))
			_draw_diamond(pos, col, Color(col.r * 0.65, col.g * 0.65, col.b * 0.65, 1.0))
	
	for gp in highlight_tiles:
		_draw_diamond(grid_to_world(gp), highlight_tiles[gp], Color.WHITE, 1.0)
	
	if selection_tile.x >= 0:
		var sp = grid_to_world(selection_tile)
		_draw_diamond(sp, Color(1.0, 0.85, 0.0, 0.3), Color(1.0, 0.85, 0.0, 0.7), 2.5)

func _draw_diamond(center: Vector2, fill: Color, outline: Color, ow: float = 1.0):
	var pts = PackedVector2Array([
		center + Vector2(0, -TILE_H/2.0),
		center + Vector2(TILE_W/2.0, 0),
		center + Vector2(0, TILE_H/2.0),
		center + Vector2(-TILE_W/2.0, 0),
	])
	draw_colored_polygon(pts, fill)
	draw_polyline(pts + PackedVector2Array([pts[0]]), outline, ow)

func _terrain_color(t: Terrain) -> Color:
	match t:
		Terrain.GRASS:   return Color(0.45, 0.70, 0.32, 1.0)
		Terrain.FOREST:  return Color(0.18, 0.48, 0.15, 1.0)
		Terrain.MOUNTAIN: return Color(0.52, 0.48, 0.42, 1.0)
		Terrain.WATER:   return Color(0.22, 0.48, 0.78, 0.92)
		Terrain.PATH:    return Color(0.78, 0.72, 0.58, 1.0)
		_:               return Color(0.45, 0.70, 0.32, 1.0)

func set_highlights(tiles: Dictionary, color := Color(0.2, 0.5, 1.0, 0.3)):
	highlight_tiles.clear()
	for gp in tiles:
		highlight_tiles[gp] = color
	queue_redraw()

func clear_highlights():
	highlight_tiles.clear()
	queue_redraw()

func set_selection(gp: Vector2i):
	selection_tile = gp
	queue_redraw()

func clear_selection():
	selection_tile = Vector2i(-1, -1)
	queue_redraw()
