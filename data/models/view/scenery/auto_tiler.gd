class_name TacticsAutoTiler
extends RefCounted
## Les transitions entre terrains : rive, lisière, plage, bord de route.
##
## Chaque case portait une texture 32 × 32 unie, découpée sur la limite exacte
## du carreau. Une forêt posée contre une plaine y faisait un mur au cordeau —
## une frontière que rien dans le paysage ne justifie, et qui trahissait le
## damier sous le décor.
##
## Le pack SSCAP est pourtant bâti pour ça : chaque terrain « posé sur de
## l'herbe » y occupe un bloc de seize cellules, une par voisinage possible en
## croix. [code]art/decouper-bords.py[/code] les extrait dans
## [code]assets/textures/terrain/edges/[/code] ; ce service les choisit.
##
## ## La transition appartient au terrain, pas à l'herbe
##
## On attend l'inverse : « cette case d'herbe a de l'eau à l'est, donc elle
## montre une rive à droite ». Le pack impose l'autre sens — la rive est
## dessinée **dans la case d'eau**, sur un fond d'herbe, et c'est plus juste :
## une berge appartient à l'étang, pas à la prairie. Une case d'herbe n'a donc
## jamais rien à afficher de spécial, quels que soient ses voisins, et l'herbe
## reste ce qu'elle est partout — le fond du tableau.
##
## Conséquence pratique : seuls les terrains listés dans [constant EDGE_SETS]
## reçoivent un habillage. Tout le reste — montagne, mur, neige, marais —
## garde son remplissage, et rien n'est à ajouter pour qu'ils continuent de
## fonctionner.
##
## ## Un calque, pas un remplacement
##
## Le dessus de la case reçoit un quadrilatère à part, posé quelques millimètres
## au-dessus du `BoxMesh`. Deux raisons, et la seconde est la vraie :
##
## 1. Le matériau de terrain est projeté en coordonnées **monde**
##    ([TacticsScenery]) — le motif traverse les cases au lieu de recommencer sur
##    chacune. C'est exactement ce qu'il ne faut pas d'une tuile de bord, qui
##    doit tomber sur SA case, dans SON sens. Le calque porte des UV écrites à
##    la main : `+X` va vers la droite de l'image, `+Z` vers le bas. Aucune
##    convention à deviner, donc aucune rive à l'envers.
## 2. Le surlignage tactique ([TacticsTile]) pose un `material_override` sur le
##    dessus de la case. Un calque séparé se teinte de la même façon et par le
##    même chemin : les cases bleues et rouges restent lisibles par-dessus la
##    rive au lieu d'être recouvertes par elle.

const MapDataClass = preload("res://data/models/world/map/map_data.gd")

## Nom du nœud de calque, cherché et reposé à l'identique d'une bataille à l'autre.
const OVERLAY_NODE: String = "AutoTile"

## Terrains qui reçoivent des bords, et le jeu de tuiles qui les porte.
##
## La montagne y est depuis le 2026-08-12 : elle est franchissable (coût 2),
## donc souvent collée à une plaine que l'œil traverse — ses bords sont
## synthétisés par `art/decouper-bords.py` (le pack SSCAP n'en fournit pas).
const EDGE_SETS: Dictionary = {
	MapDataClass.TerrainType.WATER: "water",
	MapDataClass.TerrainType.FOREST: "forest",
	MapDataClass.TerrainType.SAND: "sand",
	MapDataClass.TerrainType.PATH: "path",
	MapDataClass.TerrainType.MOUNTAIN: "mountain",
	MapDataClass.TerrainType.VILLAGE: "village",
	MapDataClass.TerrainType.FORT: "fort",
}

## Dossier des tuiles de bord.
const EDGE_DIR: String = "res://assets/textures/terrain/edges/"

## Décalage vertical du calque au-dessus du dessus de la case.
##
## Assez pour que le rendu tranche entre les deux surfaces au lieu de les faire
## clignoter l'une dans l'autre, assez peu pour qu'aucune caméra du jeu ne voie
## le calque flotter.
const OVERLAY_LIFT: float = 0.006

## Côtés du masque, dans l'ordre où les lettres s'écrivent, et leur direction
## en coordonnées de grille.
##
## `n` est le côté qui regarde les lignes décroissantes, `s` les croissantes :
## c'est le sens dans lequel [TacticsArena] pose ses cases (la ligne 0 au plus
## petit `z`), et celui dans lequel une image se lit (la première rangée de
## pixels en haut). Les deux coïncident, donc `n` est bien le haut de l'image.
const SIDES: Array[Array] = [
	["n", Vector2i(0, -1)],
	["e", Vector2i(1, 0)],
	["s", Vector2i(0, 1)],
	["w", Vector2i(-1, 0)],
]

## Matériaux de calque déjà bâtis, par « terrain:masque ».
static var _material_cache: Dictionary = {}
## Quadrilatères déjà bâtis, par côté (deux tailles de case suffisent en pratique).
static var _quad_cache: Dictionary = {}


#region Pose
## Habille toutes les cases d'une grille.
##
## Appelée une fois la grille bâtie, donc une fois les terrains connus. Elle est
## idempotente : relancée sur une arène déjà habillée, elle remplace le matériau
## de chaque calque au lieu d'en empiler un second. L'éditeur de cartes s'en
## sert pour rafraîchir le plateau après un coup de pinceau.
static func apply_to_grid(grid: BattleGrid) -> void:
	if not grid:
		return
	var span: Vector2i = grid.dimensions()
	for row: int in span.y:
		for col: int in span.x:
			var cell := Vector2i(col, row)
			var tile: Node = grid.tile_at_cell(cell)
			if tile is TacticsTile:
				apply_to_tile(grid, cell, tile as TacticsTile)


## Habille une case : choisit sa tuile de bord et pose (ou reprend) son calque.
static func apply_to_tile(grid: BattleGrid, cell: Vector2i, tile: TacticsTile) -> void:
	var overlay: MeshInstance3D = tile.get_node_or_null(OVERLAY_NODE) as MeshInstance3D

	var material: StandardMaterial3D = overlay_material(
		int(tile.terrain_type), mask_at(grid, cell, int(tile.terrain_type)))
	if not material:
		# Terrain sans bords, ou tuile manquante du dossier `edges/`. Un calque
		# posé par un terrain précédent — l'éditeur repeint une case — s'en va.
		if overlay:
			tile.set_autotile(null, null)
			overlay.queue_free()
		return

	var top: MeshInstance3D = tile.get_node_or_null("Tile") as MeshInstance3D
	if not top or not top.mesh:
		return
	var box: AABB = top.mesh.get_aabb()

	if not overlay:
		overlay = MeshInstance3D.new()
		overlay.name = OVERLAY_NODE
		# Le calque ne projette pas d'ombre : il double le dessus de la case, et
		# deux surfaces à six millièmes l'une de l'autre s'ombrageraient l'une
		# l'autre en un moiré de bandes sombres.
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tile.add_child(overlay)

	overlay.mesh = quad_mesh(box.size.x, box.size.z)
	overlay.position = Vector3(box.get_center().x, box.end.y + OVERLAY_LIFT, box.get_center().z)
	overlay.material_override = material
	tile.set_autotile(overlay, material)
#endregion


#region Choix de la tuile
## Le masque d'une case : les côtés où son terrain s'arrête.
##
## Les lettres sortent dans l'ordre n, e, s, w — celui des noms de fichiers.
## `fill` quand le terrain se poursuit de tous les côtés.
##
## **Hors grille compte comme le même terrain.** Une rive dessinée au bord du
## plateau montrerait de l'herbe là où il n'y a rien du tout : le damier s'arrête
## sur le vide, et le flanc de la case dit déjà la coupure.
static func mask_at(grid: BattleGrid, cell: Vector2i, terrain: int) -> String:
	if not grid or not EDGE_SETS.has(terrain):
		return "fill"

	var mask: String = ""
	for side: Array in SIDES:
		var neighbor: Node = grid.tile_at_cell(cell + (side[1] as Vector2i))
		if neighbor and int(neighbor.terrain_type) != terrain:
			mask += str(side[0])
	return mask if not mask.is_empty() else "fill"


## Matériau du calque d'un terrain pour un masque, ou `null` s'il n'en a pas.
##
## Le chargement passe par [method ResourceLoader.exists] pour la même raison
## que [method TacticsScenery.terrain_texture] : une image que Godot n'a pas
## encore importée ne doit pas emporter la scène, seulement priver la case de
## son bord. Les absences sont mises en cache comme les présences.
static func overlay_material(terrain: int, mask: String) -> StandardMaterial3D:
	var key: String = "%d:%s" % [terrain, mask]
	var cached: Variant = _material_cache.get(key)
	if cached != null:
		return cached as StandardMaterial3D
	if _material_cache.has(key):
		return null

	var material: StandardMaterial3D = _build_material(terrain, mask)
	_material_cache[key] = material
	return material


static func _build_material(terrain: int, mask: String) -> StandardMaterial3D:
	if not EDGE_SETS.has(terrain):
		return null
	var path: String = "%s%s_%s.png" % [EDGE_DIR, str(EDGE_SETS[terrain]), mask]
	if not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path) as Texture2D
	if not texture:
		return null

	var grain: Dictionary = TacticsScenery.TERRAIN_GRAIN.get(
		terrain, TacticsScenery.TERRAIN_GRAIN[MapDataClass.TerrainType.GRASS])

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# La réponse à la lumière reste celle du terrain : l'eau accroche le soleil,
	# le sable non. C'est ce qui empêche le calque de se détacher du plateau.
	material.roughness = float(grain["roughness"])
	material.metallic = float(grain["metallic"])
	# Le pixel art filtré linéairement devient une purée ; les mipmaps évitent le
	# grésillement des cases lointaines sous la caméra tactique.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# Le quadrilatère n'a qu'une face utile, et l'orientation d'une face dépend
	# d'un ordre de sommets qu'on n'a pas envie de devoir démontrer. On désactive
	# l'élimination : le calque est visible de partout, et il est plat.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
#endregion


#region Géométrie
## Le quadrilatère du dessus d'une case, UV écrites à la main.
##
## `u` suit `+X`, `v` suit `+Z` : le coin de l'image en haut à gauche tombe sur
## le coin de la case au plus petit `x` et au plus petit `z`. C'est toute la
## convention, et elle tient en une ligne parce qu'elle est posée ici plutôt que
## déduite d'un `PlaneMesh` ou d'une projection triplanaire.
static func quad_mesh(width: float, depth: float) -> ArrayMesh:
	var key: String = "%.4f:%.4f" % [width, depth]
	var cached: Variant = _quad_cache.get(key)
	if cached is ArrayMesh:
		return cached

	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var vertices := PackedVector3Array([
		Vector3(-half_x, 0.0, -half_z),
		Vector3(half_x, 0.0, -half_z),
		Vector3(half_x, 0.0, half_z),
		Vector3(-half_x, 0.0, half_z),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_quad_cache[key] = mesh
	return mesh
#endregion
