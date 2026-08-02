class_name MapGenerator
extends RefCounted
## Procedural map generation engine.
## Produces terrain and height grids for MapData using noise-based algorithms.

const TERRAIN := {GRASS = 0, FOREST = 1, MOUNTAIN = 2, WATER = 3, PATH = 4, WALL = 5, PIT = 6}

## Grid dimensions
var grid_size: Vector2i = Vector2i(16, 10)
## Tile size in world units
var tile_size: float = 1.0
## Random seed (0 = use randi())
var seed: int = 0

## Terrain distribution controls (0.0 – 1.0)
var water_level: float = 0.22       ## Fraction below which = water
var mountain_level: float = 0.72     ## Fraction above which = mountain
var forest_density: float = 0.25     ## Fraction of grass converted to forest
var path_count: int = 2              ## Number of crossing paths

## Height roughness (0.5 = gentle, 3.0 = extreme)
var height_roughness: float = 1.2

var _terrain: Array[int] = []
var _height: Array[float] = []


## Generate a new terrain + height map
func generate() -> void:
	if seed == 0:
		seed = randi()
	seed(seed)
	
	var total: int = grid_size.x * grid_size.y
	_terrain.resize(total)
	_height.resize(total)
	
	# Step 1: Generate base noise heightmap
	_generate_heightmap()
	
	# Step 2: Classify terrain from height
	_classify_terrain()
	
	# Step 3: Add paths
	_add_paths()
	
	# Step 4: Ensure connectivity (fill isolated water tiles)
	_ensure_connectivity()


## Get terrain at grid position
func get_terrain(col: int, row: int) -> int:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= _terrain.size():
		return TERRAIN.GRASS
	return _terrain[idx]


## Get height at grid position
func get_height(col: int, row: int) -> float:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= _height.size():
		return 0.0
	return _height[idx]


#region: --- Generation Steps ---

## Simple noise generator using hash mixing (avoids Perlin dependency)
func _noise(x: float, y: float) -> float:
	var n: int = int(x * 127.1 + y * 311.7)
	n = (n << 13) ^ n
	n = (n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff
	return float(n) / 2147483647.0


## Smooth interpolated noise
func _smooth_noise(x: float, y: float) -> float:
	var fx: float = floor(x)
	var fy: float = floor(y)
	var dx: float = x - fx
	var dy: float = y - fy
	
	# Smoothstep
	dx = dx * dx * (3.0 - 2.0 * dx)
	dy = dy * dy * (3.0 - 2.0 * dy)
	
	var n00 := _noise(fx, fy)
	var n10 := _noise(fx + 1.0, fy)
	var n01 := _noise(fx, fy + 1.0)
	var n11 := _noise(fx + 1.0, fy + 1.0)
	
	return lerp(lerp(n00, n10, dx), lerp(n01, n11, dx), dy)


## Multi-octave fractal noise
func _fractal_noise(x: float, y: float, octaves: int = 4, lacunarity: float = 2.0, persistence: float = 0.5) -> float:
	var value: float = 0.0
	var amplitude: float = 1.0
	var frequency: float = 1.0
	var max_value: float = 0.0
	
	for _i in octaves:
		value += _smooth_noise(x * frequency, y * frequency) * amplitude
		max_value += amplitude
		amplitude *= persistence
		frequency *= lacunarity
	
	return value / max_value


func _generate_heightmap() -> void:
	var scale: float = 5.0  # Noise scale (lower = bigger features)
	var base_x: float = randf() * 1000.0
	var base_y: float = randf() * 1000.0
	
	for row in grid_size.y:
		for col in grid_size.x:
			var idx: int = row * grid_size.x + col
			var nx: float = base_x + float(col) / scale
			var ny: float = base_y + float(row) / scale
			var raw: float = _fractal_noise(nx, ny, 4, 2.0, 0.5)
			_height[idx] = snapped(raw * height_roughness, 0.1)


func _classify_terrain() -> void:
	# Build histogram for water/mountain thresholds
	var all_h: Array[float] = []
	for h in _height:
		all_h.append(h)
	all_h.sort()
	
	var n: int = all_h.size()
	var water_cutoff: float = all_h[int(float(n) * water_level)]
	var mountain_cutoff: float = all_h[int(float(n) * mountain_level)]
	
	for row in grid_size.y:
		for col in grid_size.x:
			var idx: int = row * grid_size.x + col
			var h: float = _height[idx]
			
			if h <= water_cutoff:
				# Water bodies in low areas
				_terrain[idx] = TERRAIN.WATER
				_height[idx] = snapped(min(h - 0.3, -0.1), 0.1)  # Sink water tiles
			elif h >= mountain_cutoff:
				# Mountains in high areas
				_terrain[idx] = TERRAIN.MOUNTAIN
			else:
				# Grass or forest
				var local_noise := _smooth_noise(float(col) * 0.4, float(row) * 0.4)
				if local_noise < forest_density:
					_terrain[idx] = TERRAIN.FOREST
				else:
					_terrain[idx] = TERRAIN.GRASS


func _add_paths() -> void:
	for _p in path_count:
		# Pick two random border points
		var start_col: int = randi_range(0, grid_size.x - 1)
		var end_col: int = randi_range(0, grid_size.x - 1)
		var start_row: int = randi_range(0, grid_size.y - 1)
		var end_row: int = randi_range(0, grid_size.y - 1)
		
		# Draw a simple line between them
		_draw_path_line(start_col, start_row, end_col, end_row)


func _draw_path_line(x0: int, y0: int, x1: int, y1: int) -> void:
	# Bresenham with width
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	
	var path_width: int = 1
	
	while true:
		for wo in range(-path_width, path_width + 1):
			for wi in range(-path_width, path_width + 1):
				var pc: int = x0 + wo
				var pr: int = y0 + wi
				if pc >= 0 and pc < grid_size.x and pr >= 0 and pr < grid_size.y:
					var idx: int = pr * grid_size.x + pc
					if _terrain[idx] == TERRAIN.GRASS or _terrain[idx] == TERRAIN.FOREST:
						_terrain[idx] = TERRAIN.PATH
		
		if x0 == x1 and y0 == y1:
			break
		
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy


func _ensure_connectivity() -> void:
	# Convert single isolated water tiles to grass
	# (lakes with no neighbor water = puddle → fill it)
	for row in grid_size.y:
		for col in grid_size.x:
			var idx: int = row * grid_size.x + col
			if _terrain[idx] != TERRAIN.WATER:
				continue
			
			# Count water neighbors
			var water_neighbors := 0
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if dr == 0 and dc == 0:
						continue
					var nr: int = row + dr
					var nc: int = col + dc
					if nr >= 0 and nr < grid_size.y and nc >= 0 and nc < grid_size.x:
						if _terrain[nr * grid_size.x + nc] == TERRAIN.WATER:
							water_neighbors += 1
			
			# Isolated puddle (0-1 water neighbors) → fill with grass
			if water_neighbors <= 1:
				_terrain[idx] = TERRAIN.GRASS
				_height[idx] = max(_height[idx], 0.0)
	
	# Add bridges over water (path crossing water → grass bridge)
	for row in grid_size.y:
		for col in grid_size.x:
			var idx: int = row * grid_size.x + col
			if _terrain[idx] != TERRAIN.PATH:
				continue
			# Remove water under paths (creates causeway)
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					var nr: int = row + dr
					var nc: int = col + dc
					if nr >= 0 and nr < grid_size.y and nc >= 0 and nc < grid_size.x:
						var nidx: int = nr * grid_size.x + nc
						if _terrain[nidx] == TERRAIN.WATER:
							_terrain[nidx] = TERRAIN.GRASS
							_height[nidx] = 0.0

#endregion
