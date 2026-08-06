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

## Matériau de surlignage de cette case, pour un état donné.
##
## Les aplats de couleur unie d'avant effaçaient le terrain : une case
## atteignable perdait d'un coup le grain que la passe artistique lui avait
## donné. [TacticsScenery] rend maintenant un matériau **teinté par-dessus le
## terrain de cette case-ci** — d'où le passage par `terrain_type`.
## Matériaux de surlignage déjà résolus pour cette case.
var _highlights: Dictionary = {}


func highlight(state: String) -> StandardMaterial3D:
	# `_process` passe ici à chaque frame, pour chaque tuile : on garde la
	# réponse sous la main plutôt que de reconstruire une clé de cache 200 fois
	# par image.
	var known: Variant = _highlights.get(state)
	if known is StandardMaterial3D:
		return known
	var built: StandardMaterial3D = TacticsScenery.highlight_material(terrain_type, state)
	_highlights[state] = built
	return built
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
			tile.material_override = highlight("deploy")
		elif seize_point:
			tile.material_override = highlight("seize")
		elif terrain_mat:
			tile.material_override = terrain_mat
		return
	
	tile.visible = true
	match hover:
		true: # If hover is true, decide which material to use based on the tile's state
			if reachable:
				tile.material_override = highlight("reachable_hover")
			elif attackable:
				tile.material_override = highlight("hover_attackable")
			else:
				tile.material_override = highlight("hover")
		false: # If hover is false, this block decides between two materials
			if reachable:
				tile.material_override = highlight("reachable")
			elif attackable:
				tile.material_override = highlight("attackable")
#endregion

#region: --- Methods ---
# Getters
## Returns all 4 directly adjacent tiles
##
## L'index de grille répond sans moteur physique. Le repli sur les rayons ne
## sert qu'aux tuiles qui n'y sont pas inscrites (scène montée à la main hors
## d'une arène) ; il disparaîtra quand la parité sera prouvée fenêtre ouverte.
func get_neighbors(height: float) -> Array:
	var grid: BattleGrid = BattleGrid.current
	if grid and grid.has_tile(self):
		return grid.neighbors_of(self, height)
	return $RayCasting.get_all_neighbors(height)


## Returns the pawn standing on this tile, if any
func get_tile_occupier() -> Object:
	var grid: BattleGrid = BattleGrid.current
	if grid and grid.has_tile(self):
		return grid.occupant_of(self)
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
