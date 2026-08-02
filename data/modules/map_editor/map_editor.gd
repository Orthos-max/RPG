@tool
class_name MapEditor
extends Node3D

const MapDataClass = preload("res://data/models/world/map/map_data.gd")
## In-editor terrain painter for MapData grids.
##
## Add this node to a scene, assign a MapData resource, and paint terrain types
## by clicking on the grid cells in the Godot viewport.
##
## Controls:
##   - Left click: paint selected terrain
##   - Scroll wheel: cycle through terrain types
##   - Hold Shift + click: raise/lower tile height

const TERRAIN_NAMES := ["GRASS", "FOREST", "MOUNTAIN", "WATER", "PATH", "WALL", "PIT"]

## MapData resource to edit
@export var map_data: Resource

## Currently selected terrain type for painting (0=GRASS ... 6=PIT)
@export var brush_terrain: int = 0

## Brush height value for shift-click
@export var brush_height: float = 0.0

## Grid overlay toggle
@export var show_grid: bool = true:
	set(v):
		show_grid = v
		if grid_lines:
			grid_lines.visible = v

## Grid line color
@export var grid_color: Color = Color(0.3, 0.3, 0.3, 0.5)

var grid_lines: Node3D = null
var preview_tiles: Node3D = null
var _camera: Camera3D = null
var _pending_rebuild: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if grid_lines:
		grid_lines.queue_free()
		grid_lines = null
	if preview_tiles:
		preview_tiles.queue_free()
		preview_tiles = null


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_pending_rebuild = true


func _process(_delta: float) -> void:
	if _pending_rebuild:
		_pending_rebuild = false
		# Initialize map_data if needed
		var md = _get_md()
		if md and md.get("terrain_grid") != null and md.terrain_grid.is_empty():
			md.init_default()
		_rebuild_preview()


func _exit_tree() -> void:
	if grid_lines:
		grid_lines.queue_free()
		grid_lines = null
	if preview_tiles:
		preview_tiles.queue_free()
		preview_tiles = null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not map_data:
		warnings.append("Assign a MapData resource to edit the terrain grid.")
	return warnings


func _get_md():
	return map_data


func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		return
	var md = _get_md()
	if not md:
		return
	
	if not _camera:
		_camera = EditorInterface.get_editor_viewport_3d().get_camera_3d()
	if not _camera:
		return
	
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos: Vector2 = EditorInterface.get_editor_viewport_3d().get_mouse_position()
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			var tile_pos: Vector2i = _mouse_to_tile(mouse_pos)
			if tile_pos.x >= 0 and tile_pos.y >= 0:
				if Input.is_key_pressed(KEY_SHIFT):
					md.set_height(tile_pos.x, tile_pos.y, brush_height)
				else:
					md.set_terrain(tile_pos.x, tile_pos.y, brush_terrain)
				_rebuild_preview()
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_terrain = (brush_terrain + 1) % 7
			if brush_terrain < TERRAIN_NAMES.size():
				print_rich("[color=cyan][MapEditor][/color] Brush: [b]%s[/b]" % TERRAIN_NAMES[brush_terrain])
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_terrain = ((brush_terrain - 1) + 7) % 7
			if brush_terrain < TERRAIN_NAMES.size():
				print_rich("[color=cyan][MapEditor][/color] Brush: [b]%s[/b]" % TERRAIN_NAMES[brush_terrain])


func _mouse_to_tile(mouse_pos: Vector2) -> Vector2i:
	var md = _get_md()
	if not _camera or not md:
		return Vector2i(-1, -1)
	
	var origin: Vector3 = _camera.project_ray_origin(mouse_pos)
	var direction: Vector3 = _camera.project_ray_normal(mouse_pos)
	
	if abs(direction.y) < 0.0001:
		return Vector2i(-1, -1)
	
	var t: float = -origin.y / direction.y
	if t <= 0:
		return Vector2i(-1, -1)
	
	var hit_point: Vector3 = origin + direction * t
	var ts: float = md.tile_size
	var half_w: float = float(md.grid_size.x) / 2.0
	var half_h: float = float(md.grid_size.y) / 2.0
	
	var col: int = int(floor(hit_point.x / ts + half_w))
	var row: int = int(floor(hit_point.z / ts + half_h))
	
	if col < 0 or col >= md.grid_size.x or row < 0 or row >= md.grid_size.y:
		return Vector2i(-1, -1)
	
	return Vector2i(col, row)


func _rebuild_preview() -> void:
	if not Engine.is_editor_hint():
		return
	
	var md = _get_md()
	
	if preview_tiles:
		preview_tiles.queue_free()
		preview_tiles = null
	if grid_lines:
		grid_lines.queue_free()
		grid_lines = null
	
	if not md:
		return
	
	preview_tiles = Node3D.new()
	preview_tiles.name = "MapEditorPreview"
	add_child(preview_tiles)
	
	grid_lines = Node3D.new()
	grid_lines.name = "MapEditorGrid"
	grid_lines.visible = show_grid
	add_child(grid_lines)
	
	var ts: float = md.tile_size
	var half_w: float = float(md.grid_size.x) / 2.0
	var half_h: float = float(md.grid_size.y) / 2.0
	
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(ts * 0.96, 0.02, ts * 0.96)
	
	for row in md.grid_size.y:
		for col in md.grid_size.x:
			var terrain: int = md.get_terrain(col, row)
			var height: float = md.get_height(col, row)
			
			var mi := MeshInstance3D.new()
			mi.name = "Preview_%d_%d" % [col, row]
			mi.mesh = box_mesh
			mi.position = Vector3(
				(float(col) - half_w + 0.5) * ts,
				height + 0.01,
				(float(row) - half_h + 0.5) * ts
			)
			
			if TacticsConfig.terrain_material.has(terrain):
				mi.material_override = TacticsConfig.terrain_material[terrain]
			
			preview_tiles.add_child(mi)
	
	_draw_grid(half_w, half_h, ts)


func _draw_grid(half_w: float, half_h: float, ts: float) -> void:
	var md = _get_md()
	if not md:
		return
	var gs = md.grid_size
	var y_offset: float = 0.015
	
	for col in range(gs.x + 1):
		var x: float = (float(col) - half_w) * ts
		var mi := MeshInstance3D.new()
		mi.name = "GridV_%d" % col
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.02, 0.01, float(gs.y) * ts)
		mi.mesh = mesh
		mi.position = Vector3(x, y_offset, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = grid_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.flags_unshaded = true
		mi.material_override = mat
		grid_lines.add_child(mi)
	
	for row in range(gs.y + 1):
		var z: float = (float(row) - half_h) * ts
		var mi := MeshInstance3D.new()
		mi.name = "GridH_%d" % row
		var mesh := BoxMesh.new()
		mesh.size = Vector3(float(gs.x) * ts, 0.01, 0.02)
		mi.mesh = mesh
		mi.position = Vector3(0.0, y_offset, z)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = grid_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.flags_unshaded = true
		mi.material_override = mat
		grid_lines.add_child(mi)
