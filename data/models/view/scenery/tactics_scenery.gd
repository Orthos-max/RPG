class_name TacticsScenery
extends RefCounted
## Le décor d'une bataille : ciel, lumière, ombres, grain du terrain.
##
## Le rendu tenait dans des cubes de couleur unie posés sur un fond noir, sans
## ombre portée : des sprites 2D dans un monde 3D qui ne ressemblait ni à l'un
## ni à l'autre. Ce module rassemble ce qui donne au plateau son épaisseur —
## un ciel plutôt qu'un vide, une lumière qui projette les unités sur le sol,
## et un grain qui empêche seize cases d'herbe d'être exactement la même case
## répétée seize fois.
##
## Ciel, lumière et grain restent procéduraux. Tout est projeté en coordonnées
## *monde* (triplanaire) : les cases partagent un seul matériau par terrain, et
## le surlignage de portée part de ce matériau au lieu de l'effacer.
##
## Un seul endroit à retoucher pour la direction artistique, valable en
## bataille comme dans l'éditeur de cartes.
##
## Les terrains courants portent désormais une tuile 32×32 découpée du pack
## SSCAP ([constant TERRAIN_TEXTURES]) ; ceux qui n'en ont pas gardent le grain
## procédural. Les deux voies produisent le même genre de matériau, projeté de
## la même façon : rien d'autre dans le jeu n'a besoin de savoir laquelle a
## servi.

const MapDataClass = preload("res://data/models/world/map/map_data.gd")

## Teinte de base de chaque terrain
##
## Les terrains bâtis disent le **sol** de leur case, pas le bâtiment : la terre
## battue d'un hameau, la cour pavée d'un fortin, les dalles d'une ruine. Ce qui
## se dresse dessus est du décor ([TacticsProps]), avec ses propres teintes.
const TERRAIN_COLORS: Dictionary = {
	MapDataClass.TerrainType.GRASS: "#4a8c3f",
	MapDataClass.TerrainType.FOREST: "#2d5a1e",
	MapDataClass.TerrainType.MOUNTAIN: "#8b7355",
	MapDataClass.TerrainType.WATER: "#2a6e8f",
	MapDataClass.TerrainType.PATH: "#c4a97d",
	MapDataClass.TerrainType.WALL: "#5a5a5a",
	MapDataClass.TerrainType.PIT: "#1a1a1a",
	MapDataClass.TerrainType.VILLAGE: "#9c7b4f",
	MapDataClass.TerrainType.FORT: "#7a746a",
	MapDataClass.TerrainType.GATE: "#6b6660",
	MapDataClass.TerrainType.RUINS: "#7f8069",
	MapDataClass.TerrainType.TOWER: "#63605c",
	MapDataClass.TerrainType.BRIDGE: "#8a6a44",
	MapDataClass.TerrainType.SAND: "#d6c087",
	MapDataClass.TerrainType.SNOW: "#e4ebf2",
	MapDataClass.TerrainType.SWAMP: "#4b5a3c",
}

## Grain de chaque terrain : {frequency, contrast, roughness, metallic}
##
## `frequency` donne la taille des taches (bas = larges plaques, haut = grain
## serré), `contrast` leur profondeur. L'eau est lisse et un peu métallique
## pour accrocher la lumière ; la roche est mate et très marquée.
const TERRAIN_GRAIN: Dictionary = {
	MapDataClass.TerrainType.GRASS: {"frequency": 0.020, "contrast": 0.30, "roughness": 0.95, "metallic": 0.0},
	MapDataClass.TerrainType.FOREST: {"frequency": 0.045, "contrast": 0.42, "roughness": 0.98, "metallic": 0.0},
	MapDataClass.TerrainType.MOUNTAIN: {"frequency": 0.035, "contrast": 0.38, "roughness": 1.0, "metallic": 0.0},
	MapDataClass.TerrainType.WATER: {"frequency": 0.030, "contrast": 0.16, "roughness": 0.18, "metallic": 0.25},
	MapDataClass.TerrainType.PATH: {"frequency": 0.055, "contrast": 0.26, "roughness": 0.92, "metallic": 0.0},
	MapDataClass.TerrainType.WALL: {"frequency": 0.040, "contrast": 0.28, "roughness": 0.85, "metallic": 0.0},
	MapDataClass.TerrainType.PIT: {"frequency": 0.050, "contrast": 0.45, "roughness": 1.0, "metallic": 0.0},
	MapDataClass.TerrainType.VILLAGE: {"frequency": 0.050, "contrast": 0.28, "roughness": 0.94, "metallic": 0.0},
	MapDataClass.TerrainType.FORT: {"frequency": 0.045, "contrast": 0.30, "roughness": 0.88, "metallic": 0.0},
	MapDataClass.TerrainType.GATE: {"frequency": 0.040, "contrast": 0.26, "roughness": 0.85, "metallic": 0.0},
	MapDataClass.TerrainType.RUINS: {"frequency": 0.050, "contrast": 0.34, "roughness": 0.92, "metallic": 0.0},
	MapDataClass.TerrainType.TOWER: {"frequency": 0.040, "contrast": 0.30, "roughness": 0.86, "metallic": 0.0},
	# Le bois d'un pont : un grain serré, dans le sens des planches.
	MapDataClass.TerrainType.BRIDGE: {"frequency": 0.075, "contrast": 0.30, "roughness": 0.90, "metallic": 0.0},
	MapDataClass.TerrainType.SAND: {"frequency": 0.065, "contrast": 0.20, "roughness": 0.95, "metallic": 0.0},
	# La neige accroche un peu la lumière, et ses plaques sont larges.
	MapDataClass.TerrainType.SNOW: {"frequency": 0.025, "contrast": 0.12, "roughness": 0.72, "metallic": 0.06},
	# La vase luit : c'est ce qui la distingue d'une forêt sombre vue de haut.
	MapDataClass.TerrainType.SWAMP: {"frequency": 0.038, "contrast": 0.40, "roughness": 0.60, "metallic": 0.10},
}

## Tuile 32×32 du pack SSCAP employée par chaque terrain, quand il en a une.
##
## Les six premières entrées sont des correspondances directes. Les suivantes
## disent le **sol** du terrain bâti, comme le font déjà les teintes : la terre
## battue d'un hameau, la cour dallée d'un fortin, le pavé disjoint d'une ruine,
## les planches d'un pont, le noir d'une fosse.
##
## Ce qui n'est pas listé — porte, tour, neige, marais — garde le grain
## procédural : aucune tuile du pack ne leur convenait sans mentir sur ce
## qu'elles sont.
const TERRAIN_TEXTURES: Dictionary = {
	MapDataClass.TerrainType.GRASS: "res://assets/textures/terrain/terrain_outdoor_grass.png",
	MapDataClass.TerrainType.FOREST: "res://assets/textures/terrain/terrain_outdoor_forest.png",
	MapDataClass.TerrainType.MOUNTAIN: "res://assets/textures/terrain/terrain_mountain_rock.png",
	MapDataClass.TerrainType.WATER: "res://assets/textures/terrain/terrain_outdoor_water.png",
	MapDataClass.TerrainType.PATH: "res://assets/textures/terrain/terrain_outdoor_path.png",
	MapDataClass.TerrainType.SAND: "res://assets/textures/terrain/terrain_outdoor_sand.png",
	MapDataClass.TerrainType.WALL: "res://assets/textures/terrain/terrain_mountain_rock_dark.png",
	MapDataClass.TerrainType.PIT: "res://assets/textures/terrain/terrain_mountain_void.png",
	MapDataClass.TerrainType.VILLAGE: "res://assets/textures/terrain/terrain_outdoor_earth.png",
	MapDataClass.TerrainType.FORT: "res://assets/textures/terrain/terrain_outdoor_pavement.png",
	MapDataClass.TerrainType.RUINS: "res://assets/textures/terrain/terrain_outdoor_cobble.png",
	MapDataClass.TerrainType.BRIDGE: "res://assets/textures/terrain/terrain_indoor_planks.png",
}

## Échelle du bruit en unités monde : le motif se répète tous les 4 tuiles
const GRAIN_WORLD_SCALE: float = 0.25
## Côté des textures de grain (assez pour ne pas pixelliser de près)
const GRAIN_SIZE: int = 256

## Échelle des tuiles SSCAP en unités monde : un motif par case
##
## Une case fait 1 unité de côté ([member MapData.tile_size]), et la tuile est
## dessinée pour couvrir exactement une case : l'échelle vaut donc 1, et non
## [constant GRAIN_WORLD_SCALE] qui étalait volontairement le bruit sur quatre
## cases. Étirer le motif sur plusieurs cases le rendrait flou ; le resserrer
## le réduirait à une bouillie de pixels vue de la caméra tactique.
const TEXTURE_WORLD_SCALE: float = 1.0

## Part de la teinte de terrain gardée sous une tuile (0 = tuile nue)
##
## L'albédo multiplie la texture : appliquer la couleur pleine assombrirait
## deux fois. On la ramène donc près du blanc — assez pour que la tuile parle
## d'elle-même, assez peu pour que deux terrains restent distincts quand le
## surlignage vient teinter cette couleur ([method highlight_material]).
const TEXTURE_TINT_STRENGTH: float = 0.22

## Tuiles déjà chargées, par type de terrain (valeur nulle = pas de tuile)
static var _texture_cache: Dictionary = {}


#region Décor
## Ciel et lumière ambiante de la vue tactique.
##
## Vue de dessus, on ne voit du ciel que son hémisphère bas : ce sont les
## couleurs « sol » qui remplacent le fond noir autour du plateau, accordées à
## la teinte des menus.
static func environment() -> Environment:
	# Les deux couleurs d'horizon sont volontairement proches : c'est leur écart
	# qui dessinait une ligne de démarcation en travers de l'écran, comme une mer.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#3a4a72")
	sky_material.sky_horizon_color = Color("#6a7492")
	sky_material.ground_horizon_color = Color("#5c6480")
	sky_material.ground_bottom_color = Color("#24213a")
	sky_material.ground_curve = 0.06
	sky_material.sun_angle_max = 40.0
	sky_material.energy_multiplier = 1.0

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Filmic garde les verts saturés sans cramer les blancs des sprites.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.8

	# Brume légère : elle noie le bord lointain du plateau dans le ciel plutôt
	# que de le laisser trancher net sur le vide.
	env.fog_enabled = true
	env.fog_light_color = Color("#5c6480")
	env.fog_light_energy = 0.6
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	return env


## Règle la lumière du plateau : soleil rasant, ombres portées activées.
##
## C'est l'ombre au pied des unités qui les pose sur la carte — sans elle, un
## sprite en billboard flotte au-dessus de sa case. Les pions sont découpés en
## `ALPHA_CUT_OPAQUE_PREPASS`, donc leur silhouette s'imprime correctement.
static func configure_light(light: DirectionalLight3D) -> void:
	if not light:
		return
	light.rotation_degrees = Vector3(-52.0, -132.0, 0.0)
	light.light_color = Color("#fff1d6")
	light.light_energy = 1.1
	light.light_specular = 0.25
	light.shadow_enabled = true
	light.shadow_bias = 0.04
	light.shadow_normal_bias = 1.4
	# Ombres à peine adoucies : nettes, mais sans l'escalier de pixels.
	light.light_angular_distance = 1.0
	light.directional_shadow_max_distance = 60.0


## Pose (ou remplace) ciel et lumière sur un niveau.
##
## [param root] reçoit un `WorldEnvironment` et un `DirectionalLight3D` s'il
## n'en a pas déjà : bataille, carte du joueur et éditeur passent tous par ici,
## et se ressemblent donc.
static func apply_to(root: Node3D) -> void:
	if not root:
		return

	var env_node: WorldEnvironment = null
	var light: DirectionalLight3D = null
	for child in root.get_children():
		if child is WorldEnvironment and not env_node:
			env_node = child
		elif child is DirectionalLight3D and not light:
			light = child

	if not env_node:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		root.add_child(env_node)
	env_node.environment = environment()

	if not light:
		light = DirectionalLight3D.new()
		light.name = "DirectionalLight3D"
		root.add_child(light)
	configure_light(light)
#endregion


#region Terrain
## Matériau d'un type de terrain : teinte, motif, réponse à la lumière.
##
## Le motif vient de la tuile SSCAP du terrain quand il en a une, du bruit
## procédural sinon. Le reste — teinte, rugosité, projection — ne change pas :
## c'est ce qui permet au surlignage de partir de ce matériau sans savoir
## laquelle des deux voies l'a produit.
static func terrain_material(terrain_type: int) -> StandardMaterial3D:
	var grain: Dictionary = TERRAIN_GRAIN.get(terrain_type, TERRAIN_GRAIN[MapDataClass.TerrainType.GRASS])
	var base_color := Color(str(TERRAIN_COLORS.get(terrain_type, "#4a8c3f")))

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = float(grain["roughness"])
	mat.metallic = float(grain["metallic"])

	var tile: Texture2D = terrain_texture(terrain_type)
	if tile:
		mat.albedo_texture = tile
		# La texture porte sa propre couleur : la teinte de base est réduite à
		# une trace (10 %) pour que le pixel art domine — sinon elle écrase la
		# tuile et le rendu retombe sur l'ancien grain procédural (le bug
		# « seule la forêt montre sa tuile »). Cette trace suffit pourtant à ce
		# que deux terrains restent distinguables sous le surlignage (un test
		# l'exige). Le grain est conservé en relief (normal map) pour que la
		# surface garde du volume sous la caméra tactique.
		mat.albedo_color = base_color.lerp(Color.WHITE, 0.9)
		mat.normal_enabled = true
		mat.normal_texture = grain_normal_texture(
			float(grain["frequency"]), float(grain["contrast"]), terrain_type)
		mat.normal_scale = 0.35
		# Du pixel art filtré linéairement devient une purée : le plus proche
		# voisin garde l'arête des pixels, les mipmaps évitent le grésillement
		# des cases lointaines sous la caméra tactique.
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		mat.uv1_scale = Vector3.ONE * TEXTURE_WORLD_SCALE
	else:
		mat.albedo_texture = grain_texture(
			float(grain["frequency"]), float(grain["contrast"]), terrain_type)
		mat.albedo_color = base_color
		mat.uv1_scale = Vector3.ONE * GRAIN_WORLD_SCALE

	# Projection en coordonnées monde : le motif traverse les cases au lieu de
	# recommencer à l'identique sur chacune. Avec une tuile à l'échelle 1, les
	# flancs des cases surélevées reçoivent le même motif que leur dessus, sans
	# dépliage UV à écrire.
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	return mat


## Tuile SSCAP d'un terrain, ou `null` s'il n'en a pas.
##
## Le chargement passe par [method ResourceLoader.exists] plutôt que par un
## `preload` : une image que Godot n'a pas encore importée ferait échouer la
## compilation du script entier, et le terrain retomberait alors sans bruit sur
## son grain procédural plutôt que d'emporter la scène avec lui.
##
## Le résultat est mis en cache, `null` compris — inutile de redemander à chaque
## matériau une image dont on sait déjà qu'elle manque.
static func terrain_texture(terrain_type: int) -> Texture2D:
	if _texture_cache.has(terrain_type):
		return _texture_cache[terrain_type]

	var tile: Texture2D = null
	var path: String = str(TERRAIN_TEXTURES.get(terrain_type, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		tile = load(path) as Texture2D
	_texture_cache[terrain_type] = tile
	return tile


## Texture de grain : du bruit ramené à une plage claire, qui module la teinte.
##
## Le dégradé ne descend jamais à zéro — sinon le bruit noircirait le terrain
## au lieu de le nuancer.
static func grain_texture(frequency: float, contrast: float, seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.seed = seed_value
	noise.fractal_octaves = 3

	var ramp := Gradient.new()
	var floor_value: float = clampf(1.0 - contrast, 0.0, 1.0)
	ramp.set_color(0, Color(floor_value, floor_value, floor_value))
	ramp.set_color(1, Color.WHITE)

	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = GRAIN_SIZE
	texture.height = GRAIN_SIZE
	texture.seamless = true
	texture.color_ramp = ramp
	return texture


## Texture de relief (normal map) : le même bruit, converti en hauteurs.
##
## Une normal map reçoit du RGB qui encode des directions, pas une teinte : un
## bruit en niveaux de gris y fait des creux et des bosses. C'est ce qui rend
## la tuile SSCAP vivante sans retoucher à ses pixels — le grain de l'ancien
## rendu procédural survit, mais en volume, sous la couleur du pack.
static func grain_normal_texture(frequency: float, contrast: float, seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.seed = seed_value + 4096
	noise.fractal_octaves = 3

	var ramp := Gradient.new()
	var floor_value: float = clampf(1.0 - contrast, 0.0, 1.0)
	ramp.set_color(0, Color(0.5, 0.5, 1.0))          # plat (bleu = zéro hauteur)
	ramp.set_color(1, Color(0.5 + floor_value * 0.5, 0.5 + floor_value * 0.5, 1.0))

	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = GRAIN_SIZE
	texture.height = GRAIN_SIZE
	texture.seamless = true
	texture.as_normal_map = true
	texture.color_ramp = ramp
	return texture


## Teintes de surlignage, par état de tuile.
##
## Ce ne sont plus des couleurs de remplacement mais des **teintes** : le grain
## du terrain reste visible dessous. Une case atteignable est de l'herbe vue à
## travers un lavis bleu, pas un rectangle bleu.
const HIGHLIGHT_TINTS: Dictionary = {
	"hover": "#f2f4ff",
	"reachable": "#2f7fd6",
	"reachable_hover": "#5fb6ff",
	"attackable": "#c62b2b",
	"hover_attackable": "#ff5a5a",
	"seize": "#f5c842",
	"deploy": "#27d9c5",
	## Portée adverse (touche C) — un rose franc, qui ne se confond ni avec le
	## bleu de son propre déplacement ni avec le rouge de sa propre portée d'arme.
	"threat": "#e0559c",
}

## Part de la teinte dans le mélange avec la couleur du terrain (0 = terrain nu).
const HIGHLIGHT_BLEND: float = 0.68
## Lueur propre du surlignage : de quoi rester lisible dans une ombre portée.
const HIGHLIGHT_GLOW: float = 0.22

## Matériaux de surlignage déjà construits, par « terrain:état ».
static var _highlight_cache: Dictionary = {}


## Matériau de surlignage d'une case, grain du terrain compris.
##
## Le surlignage effaçait le terrain : `material_override` posait un aplat de
## couleur unie, et une case atteignable perdait d'un coup le grain que toute la
## passe artistique lui avait donné. On repart donc du matériau de terrain, on
## mélange la teinte d'état à sa couleur et on ajoute une lueur — le motif, sa
## projection en coordonnées monde et sa réponse à la lumière sont conservés.
##
## Les matériaux sont mis en cache par couple (terrain, état) : sept états pour
## seize terrains font au pire 112 matériaux, construits une seule fois — et en
## pratique bien moins, une carte n'employant jamais toute la palette.
static func highlight_material(terrain_type: int, state: String) -> StandardMaterial3D:
	var key: String = "%d:%s" % [terrain_type, state]
	var cached: Variant = _highlight_cache.get(key)
	if cached is StandardMaterial3D:
		return cached

	var mat: StandardMaterial3D = tinted(terrain_material(terrain_type), state)
	_highlight_cache[key] = mat
	return mat


## Le même matériau, passé au lavis d'un état de tuile.
##
## Extrait de [method highlight_material] pour que le calque d'auto-tuilage
## ([TacticsAutoTiler]) se teinte exactement comme le terrain qu'il recouvre.
## Sans cela, une rive resterait bleu-mer par-dessus une case atteignable bleu
## clair, et le joueur perdrait de vue jusqu'où il peut aller.
##
## Le matériau rendu est un duplicata : l'original sert encore ailleurs.
static func tinted(base: StandardMaterial3D, state: String) -> StandardMaterial3D:
	if not base:
		return null
	var tint := Color(str(HIGHLIGHT_TINTS.get(state, "#ffffff")))
	var mat: StandardMaterial3D = base.duplicate()
	mat.albedo_color = mat.albedo_color.lerp(tint, HIGHLIGHT_BLEND)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = HIGHLIGHT_GLOW
	return mat


## Tous les matériaux de terrain, prêts pour [TacticsConfig].
static func terrain_materials() -> Dictionary:
	var out: Dictionary = {}
	for terrain_type: int in TERRAIN_COLORS:
		out[terrain_type] = terrain_material(terrain_type)
	return out
#endregion
