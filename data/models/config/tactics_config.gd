class_name TacticsConfig
extends Node3D
## Tactics system configuration.
##
## This class contains static properties and methods for configuring various aspects
## of the tactics system, including colors, materials, pawn properties, and view settings.

#region: --- Props ---
## Dictionary of color codes used in the tactics system.
static var color: Dictionary = {
	"white": "FFFFFF3F", # Semi-transparent white
	"blue_cola": "008fdbBF", # Semi-transparent blue cola color
	"blue_bolt": "0aa9ffBF", # Semi-transparent blue bolt color
	"rosso_corsa": "d10000BF", # Semi-transparent rosso corsa (racing red) color
	"coral_red": "ff4242BF", # Semi-transparent coral red color
	"seize_gold": "f5c842BF", # Point de commandement à prendre (objectif de chapitre)
	"deploy_teal": "27d9c5BF", # Case de déploiement libre (avant la bataille)
}

## Dictionary of materials used for different states in the tactics system.
static var mat_color: Dictionary = {
	"hover": create_material(str(color.white)),
	"reachable": create_material(str(color.blue_cola)),
	"reachable_hover": create_material(str(color.blue_bolt)),
	"attackable": create_material(str(color.rosso_corsa)),
	"hover_attackable": create_material(str(color.coral_red)),
	"seize": create_material(str(color.seize_gold)),
	"deploy": create_material(str(color.deploy_teal)),
}

## Dictionary of pawn-related configuration values.
static var pawn: Dictionary = {
	"base_walk_speed": 8, ## Base speed for pawn movement on the board
	"animation_frames": 1, ## Number of frames for pawn animations
	"min_height_to_jump": 1, ## The tile height from which we use JUMP pawn animation
	"gravity_strength": 6, ## Force of gravity used in jump & fall physics
	"min_time_for_attack": 1, ## Minimum time required for an attack action
}

## Terrain type enum values (synced with MapData.TerrainType)
const TERRAIN_GRASS: int = 0
const TERRAIN_FOREST: int = 1
const TERRAIN_MOUNTAIN: int = 2
const TERRAIN_WATER: int = 3
const TERRAIN_PATH: int = 4
const TERRAIN_WALL: int = 5
const TERRAIN_PIT: int = 6

## Dictionary of terrain type materials.
static var terrain_material: Dictionary = {
	0: create_terrain_material("4a8c3f"),    # Green grass
	1: create_terrain_material("2d5a1e"),   # Dark green forest
	2: create_terrain_material("8b7355"),   # Rocky brown mountain
	3: create_terrain_material("2a6e8f"),   # Deep blue water
	4: create_terrain_material("c4a97d"),   # Sandy beige path
	5: create_terrain_material("5a5a5a"),   # Dark grey wall
	6: create_terrain_material("1a1a1a"),   # Near-black pit
}

## Dictionary of view-related configuration values.
static var view: Dictionary = {
	"default_t_cam_zoom": 30, ## The default FOV for tactics camera node
}

## Array of UI element names used to filter out UI elements when parsing the mouse cursor position.
static var ui_elem: Array[String] = [
	"%Actions", "%Hints",
]
#endregion


## Creates a terrain material (opaque, unshaded for flat look).
static func create_terrain_material(color_hex: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = Color(color_hex)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.9
	return mat


## Creates a StandardMaterial3D with specified color, texture, and shading mode.
##
## @param color_hex: The color of the material in hexadecimal format.
## @param texture: The albedo texture for the material (optional).
## @param shaded_mode: The shading mode for the material (default: BaseMaterial3D.SHADING_MODE_PER_PIXEL).
## @return: A new StandardMaterial3D instance with the specified properties.
static func create_material(color_hex: Variant, texture: Texture2D = null, shaded_mode: BaseMaterial3D.ShadingMode = BaseMaterial3D.SHADING_MODE_PER_PIXEL) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # Set material to use alpha transparency
	material.albedo_color = Color(str(color_hex)) # Set the material color
	material.albedo_texture = texture # Set the albedo texture (if provided)
	material.shading_mode = shaded_mode # Set the shading mode
	return material
