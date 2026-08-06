class_name TacticsArena
extends Node3D
## Tile config & sorting, neighbours, hover & reach UI overlay, pathfinding and targeting utilities.
## 
## Resource Interface: [TacticsArenaResource] -- Service: [TacticsArenaService]
## Dependency: [TacticsTile] -- Service: [TacticsTileService]

const MapDataClass = preload("res://data/models/world/map/map_data.gd")

## Resource containing arena-related data and configurations
@export var res: TacticsArenaResource = load("res://data/models/world/combat/arena/arena.tres")
## Service handling arena-related operations
var serv: TacticsArenaService
## Index de la grille en données : adjacence et occupation, sans rayon 3D.
## Bâti par [method configure_tiles], une fois les tuiles à leur place.
var grid: BattleGrid = null


func _ready() -> void:
	serv = TacticsArenaService.new(res) # Initialize the arena service
	
	# If MapData is set, generate tiles procedurally
	if res.map_data:
		_generate_from_map_data()
	
	serv.setup(self) # Set up the arena
	# Create support tracker if not already present
	if not has_node("SupportTracker"):
		var tracker := SupportTracker.new()
		tracker.name = "SupportTracker"
		add_child(tracker)


## Procedurally generates the arena tiles from MapData.
## Creates a Tiles node with MeshInstance3D children, then converts them via the tile service.
func _generate_from_map_data() -> void:
	var md = res.map_data  # MapData, dynamically typed to avoid class_name load order issues
	if not md:
		return
	
	# Remove existing Tiles node if present
	var existing: Node = get_node_or_null("Tiles")
	if existing:
		existing.queue_free()
		await get_tree().process_frame
	
	var tiles_node := Node3D.new()
	tiles_node.name = "Tiles"
	add_child(tiles_node)
	
	var half_w: float = float(md.grid_size.x) / 2.0
	var half_h: float = float(md.grid_size.y) / 2.0
	var ts: float = md.tile_size
	
	for row in md.grid_size.y:
		for col in md.grid_size.x:
			var terrain: int = md.get_terrain(col, row)
			var height: float = md.get_height(col, row)
			
			# Each tile gets its own BoxMesh with thickness matching its elevation
			var tile_mesh := BoxMesh.new()
			var thickness: float = max(abs(height), 0.08)
			tile_mesh.size = Vector3(ts * 0.98, thickness, ts * 0.98)
			
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.name = "Tile_%d_%d" % [col, row]
			mesh_instance.mesh = tile_mesh
			
			# Position: center the grid around origin
			# Y position = height/2 so the cube extends from 0 to height
			mesh_instance.position = Vector3(
				(float(col) - half_w + 0.5) * ts,
				height / 2.0,
				(float(row) - half_h + 0.5) * ts
			)
			
			tiles_node.add_child(mesh_instance)
	
	# Convert tiles to StaticBody3D with TacticsTile script
	TacticsTileService.tiles_into_staticbodies(tiles_node)
	
	# Assign terrain types to each tile after conversion
	var idx: int = 0
	for row in md.grid_size.y:
		for col in md.grid_size.x:
			if idx < tiles_node.get_child_count():
				var tile: TacticsTile = tiles_node.get_child(idx) as TacticsTile
				if tile:
					tile.terrain_type = md.get_terrain(col, row)
					# Re-apply terrain material
					if TacticsConfig.terrain_material.has(tile.terrain_type):
						tile.terrain_mat = TacticsConfig.terrain_material[tile.terrain_type]
			idx += 1

## Resets all tile markers in the arena
func reset_all_tile_markers() -> void:
	serv.reset_all_tile_markers(self)


## Configures all tiles in the arena
func configure_tiles() -> void:
	serv.configure_tiles(self)


## Processes tiles surrounding a given root tile
## [param root_tile] The central tile to process around
## [param height] The height to consider for processing
## [param allies_on_map] Array of allied pawns on the map (optional)
func process_surrounding_tiles(root_tile: TacticsTile, height: float, allies_on_map: Array = []) -> void:
	serv.process_surrounding_tiles(root_tile, height, allies_on_map)


## Returns an array of tiles representing the pathfinding stack to a given tile
## [param to] The destination tile
## [returns] Array of tiles forming the path
func get_pathfinding_tilestack(to: TacticsTile) -> Array:
	return serv.get_pathfinding_tilestack(to)


## Finds the nearest tile adjacent to any target pawn
## [param pawn] The pawn seeking a target
## [param target_pawns] Array of potential target pawns
## [returns] The nearest adjacent tile to a target
func get_nearest_target_adjacent_tile(pawn: TacticsPawn, target_pawns: Array) -> TacticsTile:
	return serv.get_nearest_target_adjacent_tile(pawn, target_pawns)


## Identifies the weakest attackable pawn from an array of pawns
## [param pawn_arr] Array of pawns to evaluate
## [returns] The weakest attackable pawn
func get_weakest_attackable_pawn(pawn_arr: Array) -> TacticsPawn:
	return serv.get_weakest_attackable_pawn(pawn_arr)


## Marks a tile as hovered
## [param tile] The tile to mark as hovered
func mark_hover_tile(tile: TacticsTile) -> void:
	serv.mark_hover_tile(self, tile)


## Marks tiles reachable within a certain distance from a root tile
## [param root] The starting tile
## [param distance] The maximum distance to consider
func mark_reachable_tiles(root: TacticsTile, distance: float) -> void:
	serv.mark_reachable_tiles(self, root, distance)


## Marks tiles attackable within a certain distance from a root tile
## [param root] The starting tile
## [param distance] The maximum attack distance
func mark_attackable_tiles(root: TacticsTile, distance: float, min_distance: float = 1.0) -> void:
	serv.mark_attackable_tiles(self, root, distance, min_distance)
