class_name TacticsTile
extends StaticBody3D
## Handles tiles, hover colors, tile state, pathfinding.
## 
## This is ultimately a module, as it is programatically appended onto every tile by way of the TacticsTileService.
## Dependencies: [TacticsTileService] [br]
## Used by: [TacticsArena]

#region: --- Props ---
## Resource for tile raycasting
var tile_raycast: Resource = load("res://data/modules/tactics/level/arena/tile/raycast/tile_raycasting.tscn")

## Whether the tile is reachable
var reachable: bool = false
## Whether the tile is attackable
var attackable: bool = false
## Whether the tile is being hovered over
var hover: bool = false
## Point de commandement à prendre (objectif « prise de point » du chapitre)
var seize_point: bool = false
## Case où le joueur peut poser une unité avant la bataille
var deploy_point: bool = false

## Terrain type for this tile (from MapData.TerrainType)
@export var terrain_type: int = 0
## Base material for terrain (applied when no special state is active)
var terrain_mat: StandardMaterial3D = null

## Pathfinding starting point.[br]Used by [TacticsArena]
var pf_root: TacticsTile
## The distance to cover.[br]Used by [TacticsArena]
var pf_distance: float

## Material for hover state
var hover_mat: StandardMaterial3D = TacticsConfig.mat_color.hover
## Material for reachable state
var reachable_mat: StandardMaterial3D = TacticsConfig.mat_color.reachable
## Material for hover and reachable state
var hover_reachable_mat: StandardMaterial3D = TacticsConfig.mat_color.reachable_hover
## Material for attackable state
var attackable_mat: StandardMaterial3D = TacticsConfig.mat_color.attackable
## Material for hover and attackable state
var hover_attackable_mat: StandardMaterial3D = TacticsConfig.mat_color.hover_attackable
## Matériau du point de commandement (objectif de chapitre)
var seize_mat: StandardMaterial3D = TacticsConfig.mat_color.seize
## Matériau d'une case de déploiement libre
var deploy_mat: StandardMaterial3D = TacticsConfig.mat_color.deploy
#endregion

#region: --- Processing ---
func _process(_delta: float) -> void:
	# Get child node named "Tile" and cast it to a MeshInstance3D.
	# If the node doesn't exist, it will be null.
	var tile: MeshInstance3D = get_node_or_null("Tile") as MeshInstance3D
	if not tile:
		return # If the "Tile" node wasn't found, the function exits early to avoid errors.
	
	# Apply terrain base material when no special state is active
	# Les marques de scénario (point à prendre, case de déploiement) passent avant
	# le terrain mais derrière tout ce qui dépend du pion en cours : le joueur doit
	# continuer à voir sa portée de déplacement par-dessus.
	if not attackable and not reachable and not hover:
		tile.visible = true
		if deploy_point:
			tile.material_override = deploy_mat
		elif seize_point:
			tile.material_override = seize_mat
		elif terrain_mat:
			tile.material_override = terrain_mat
		return
	
	tile.visible = true
	match hover:
		true: # If hover is true, decide which material to use based on the tile's state
			if reachable:
				tile.material_override = hover_reachable_mat
			elif attackable:
				tile.material_override = hover_attackable_mat
			else:
				tile.material_override = hover_mat
		false: # If hover is false, this block decides between two materials
			if reachable:
				tile.material_override = reachable_mat
			elif attackable:
				tile.material_override = attackable_mat
#endregion

#region: --- Methods ---
# Getters
## Returns all 4 directly adjacent tiles
func get_neighbors(height: float) -> Array:
	return $RayCasting.get_all_neighbors(height)


## Returns any collider directly (<=1m) above
func get_tile_occupier() -> Object:
	return $RayCasting.get_object_above()


## Return whether target tile is occupied
func is_taken() -> bool:
	return get_tile_occupier() != null


# Setters
## Resets the tile's markers (pf_root, pf_distance, reachable, attackable)
func reset_markers() -> void:
	pf_root = null
	pf_distance = 0
	reachable = false
	attackable = false


## Initializes tile (disable hover, instantiate raycast & reset state)
func configure_tile() -> void:
	hover = false
	# Set terrain material
	if TacticsConfig.terrain_material.has(terrain_type):
		terrain_mat = TacticsConfig.terrain_material[terrain_type]
	var instance: Node = tile_raycast.instantiate() # Instantiate raycast
	add_child(instance) # Add raycast as child
	reset_markers() # Reset tile markers
#endregion
