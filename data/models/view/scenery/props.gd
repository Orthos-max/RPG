class_name TacticsProps
extends RefCounted
## Ce qui pousse sur les cases : arbres, rochers, créneaux.
##
## Le plateau disait son terrain par la seule teinte de ses cases — un damier
## vert clair et vert foncé, où « forêt » était une convention à retenir plutôt
## qu'une chose à voir. Ce module y pose des volumes : on reconnaît un bois, un
## éboulis, un rempart, sans avoir appris le code couleur.
##
## Tout est procédural, comme [TacticsScenery] : des formes primitives assemblées,
## aucune image à produire, aucun artiste. Trois règles tiennent l'ensemble :
##
## - **Rien ne cache une unité.** Le décor est plafonné sous la hauteur d'un pion,
##   et sur les cases où l'on peut se tenir — la forêt — il est décalé vers un
##   coin, centre dégagé. Montagne et mur étant infranchissables, leur décor peut
##   occuper toute la case sans jamais masquer personne.
## - **Rien n'intercepte la souris.** Ces volumes n'ont aucune collision — la
##   sélection continue de viser la tuile elle-même, dont le corps physique est
##   la seule chose que le rayon rencontre.
## - **Rien n'est tiré au hasard.** La variation vient d'un hachage des
##   coordonnées de la case : deux machines d'une même partie en réseau dessinent
##   le même bois, et rouvrir une carte ne le redessine pas autrement.
##
## Le décor se pose sur les tuiles **réellement en scène**, donc aussi bien sur
## une carte engendrée depuis `MapData` que sur un chapitre écrit à la main.

const MapDataClass = preload("res://data/models/world/map/map_data.gd")
const GridRef = preload("res://data/models/world/utilities/grid.gd")

## Nom du nœud qui accueille tout le décor, sous l'arène.
const HOST_NAME: StringName = &"Props"

#region Dimensions
## Hauteur maximale d'un décor, en unités monde.
##
## Un pion tient dans ~1,2 unité au-dessus de sa case. En restant sous 0,85 le
## décor reste du mobilier : il habille la case sans disputer la silhouette de
## l'unité qui s'y tient.
const MAX_HEIGHT: float = 0.85

## Écart entre le centre de la case et le pied du décor, en fraction de case.
##
## C'est ce décalage qui laisse le centre dégagé, donc le pion lisible. Il ne
## vaut que pour la **forêt** : c'est le seul de ces trois terrains où une unité
## peut se tenir — montagne et mur sont infranchissables, leur décor a donc le
## droit d'occuper toute la case.
##
## Tenu par un test : 0,30 de case d'écart contre 0,22 de rayon de frondaison
## au plus, le centre reste hors du feuillage. Élargir l'un sans resserrer
## l'autre casserait la promesse.
const CORNER_OFFSET: float = 0.30
#endregion

#region Teintes
## Les décors se détachent de leur terrain sans le renier : un tronc plus sombre
## que le sol de la forêt, un rocher plus clair que la montagne qui le porte.
const TRUNK_COLOR: String = "#4a3524"
const CANOPY_COLOR: String = "#2c6b1c"
const ROCK_COLOR: String = "#9d8a72"
const WALL_COLOR: String = "#6b6b6b"
#endregion


#region Pose
## Pose (ou repose) le décor d'une arène de bataille.
##
## Les cases sont lues sur la scène : chacune dit son terrain, et le sommet de
## son volume donne l'altitude où poser ce qui la garnit. Une carte engendrée
## depuis `MapData` et un chapitre écrit à la main passent donc par le même
## chemin, sans que ce module ait à connaître ni l'un ni l'autre.
static func decorate(arena: Node3D) -> void:
	if not arena or not is_instance_valid(arena):
		return

	var cells: Array = []
	for tile: Variant in GridRef.tiles(arena):
		if not (tile is Node3D) or not is_instance_valid(tile):
			continue
		var terrain: Variant = (tile as Node3D).get("terrain_type")
		if terrain == null:
			continue
		var node: Node3D = tile as Node3D
		cells.append({
			"cell": GridRef.tile_to_grid(arena, node),
			"terrain": int(terrain),
			"top": Vector3(node.global_position.x, _tile_top(node), node.global_position.z),
		})

	build(arena, cells, GridRef.tile_size(arena))


## Pose (ou repose) le décor sur un hôte quelconque, à partir de cases décrites.
##
## L'éditeur de cartes n'a pas d'arène : ses tuiles sont des corps posés à plat,
## sans script ni terrain déclaré. Il connaît en revanche son document, donc il
## décrit ses cases lui-même et passe par ici — dessiner une forêt et n'y voir
## aucun arbre avant d'avoir lancé la bataille serait un drôle d'éditeur.
##
## Idempotent : le nœud d'accueil est reconstruit à chaque appel, ce qui permet
## de redessiner après chaque coup de pinceau.
##
## [param cells] `[{cell: Vector2i, terrain: int, top: Vector3}, …]`
static func build(host: Node3D, cells: Array, tile_size: float) -> void:
	if not host or not is_instance_valid(host):
		return

	var previous: Node = host.get_node_or_null(NodePath(HOST_NAME))
	if previous:
		host.remove_child(previous)
		previous.queue_free()

	var batches: Dictionary = placements(cells, tile_size)
	if batches.is_empty():
		return

	var props := Node3D.new()
	props.name = HOST_NAME
	host.add_child(props)

	for kind: String in batches:
		_add_batch(props, kind, batches[kind], tile_size)


## Répartit les cases par type de décor. `{kind: [Transform3D, …]}`
##
## Public, et c'est délibéré : c'est **tout le calcul** du décor, séparé de sa
## pose. Un `MultiMesh` ne restitue pas en headless les transformations qu'on lui
## écrit — `get_instance_transform()` y rend l'identité — donc un test qui
## interrogerait le résultat posé ne mesurerait rien. Il interroge ceci.
static func placements(cells: Array, tile_size: float) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in cells:
		if not (entry is Dictionary):
			continue
		var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
		var top: Vector3 = entry.get("top", Vector3.ZERO)

		match int(entry.get("terrain", -1)):
			MapDataClass.TerrainType.FOREST:
				_append(out, "trunk", _tree_trunk(top, cell, tile_size))
				_append(out, "canopy", _tree_canopy(top, cell, tile_size))
			MapDataClass.TerrainType.MOUNTAIN:
				for i: int in 2:
					_append(out, "rock", _rock(top, cell, tile_size, i))
			MapDataClass.TerrainType.WALL:
				_append(out, "merlon", _merlon(top, tile_size))
	return out


static func _append(out: Dictionary, kind: String, xform: Transform3D) -> void:
	if not out.has(kind):
		out[kind] = []
	out[kind].append(xform)


## Altitude du dessus d'une tuile, en coordonnées monde.
##
## Lue sur le volume affiché plutôt que sur `MapData` : les cases sculptées à la
## main n'ont pas de hauteur déclarée, et un décor flottant se voit tout de suite.
static func _tile_top(tile: Node3D) -> float:
	for child: Node in tile.get_children():
		if child is MeshInstance3D:
			var mesh_node: MeshInstance3D = child as MeshInstance3D
			var box: AABB = mesh_node.get_aabb()
			return (mesh_node.global_transform * Vector3(0.0, box.end.y, 0.0)).y
	return tile.global_position.y
#endregion


#region Formes
## Tronc d'arbre : un cylindre court, planté hors du centre de la case.
static func _tree_trunk(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var scale_factor: float = 0.8 + _noise(cell, 1) * 0.4
	var height: float = MAX_HEIGHT * 0.32 * scale_factor
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(scale_factor, height, scale_factor)),
		top + _corner(cell, tile_size) + Vector3(0.0, height / 2.0, 0.0))


## Frondaison : un cône posé sur le tronc, tourné d'une case à l'autre.
static func _tree_canopy(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var scale_factor: float = 0.8 + _noise(cell, 1) * 0.4
	var trunk_h: float = MAX_HEIGHT * 0.32 * scale_factor
	var height: float = MAX_HEIGHT * 0.68 * scale_factor
	var basis: Basis = Basis(Vector3.UP, _noise(cell, 2) * TAU)
	return Transform3D(
		basis.scaled(Vector3(scale_factor, height, scale_factor)),
		top + _corner(cell, tile_size) + Vector3(0.0, trunk_h + height / 2.0, 0.0))


## Rocher : un bloc anguleux posé de guingois, deux par case, jamais pareils.
##
## Un bloc plutôt qu'une sphère : Godot lisse les normales d'une `SphereMesh`
## quel que soit son nombre de segments, ce qui donne un galet — un œuf, même,
## dès qu'on l'étire. Ce sont les arêtes vives et l'inclinaison qui font la
## pierre : chaque face prend la lumière autrement.
static func _rock(top: Vector3, cell: Vector2i, tile_size: float, index: int) -> Transform3D:
	var salt: int = 10 + index
	var scale_factor: float = 0.7 + _noise(cell, salt) * 0.5
	# Trapu, et jamais cubique : un bloc aussi haut que large est une caisse.
	var height: float = MAX_HEIGHT * 0.30 * scale_factor
	var width: float = tile_size * 0.34 * scale_factor
	var depth: float = width * (0.55 + _noise(cell, salt + 400) * 0.6)
	var yaw: float = _noise(cell, salt + 100) * TAU

	# Basculé franchement : d'aplomb, il redevient une caisse.
	var tilt := Basis.from_euler(Vector3(
		(_noise(cell, salt + 200) - 0.5) * 0.7,
		yaw,
		(_noise(cell, salt + 300) - 0.5) * 0.7))

	# Les deux rochers d'une case s'écartent l'un de l'autre, sans quoi ils se
	# superposeraient en un seul caillou plus gros.
	var away: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw)) * tile_size * 0.16
	return Transform3D(
		tilt.scaled(Vector3(width, height, depth)),
		top + _corner(cell, tile_size) * 0.6 + away + Vector3(0.0, height / 2.0, 0.0))


## Créneau : un bandeau posé sur le mur, plein cadre — un rempart n'a pas de coin.
static func _merlon(top: Vector3, tile_size: float) -> Transform3D:
	var height: float = MAX_HEIGHT * 0.3
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(tile_size * 0.82, height, tile_size * 0.82)),
		top + Vector3(0.0, height / 2.0, 0.0))


## Décalage du centre de la case vers un de ses quatre coins.
static func _corner(cell: Vector2i, tile_size: float) -> Vector3:
	var angle: float = floor(_noise(cell, 3) * 4.0) * (TAU / 4.0) + (TAU / 8.0)
	return Vector3(cos(angle), 0.0, sin(angle)) * tile_size * CORNER_OFFSET


## Bruit déterministe dans [0, 1), propre à une case et à un usage (`salt`).
##
## Pas de générateur aléatoire : deux machines d'une même partie en réseau
## doivent dessiner le même bois, et rouvrir une carte ne doit pas la redessiner.
static func _noise(cell: Vector2i, salt: int) -> float:
	var mixed: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)
	return float(absi(mixed) % 10007) / 10007.0
#endregion


#region Rendu
## Ajoute un lot de décors identiques en un seul nœud.
##
## Un `MultiMesh` dessine ses milliers de copies d'un seul tenant : une carte
## entièrement boisée coûte deux nœuds, pas deux par case.
static func _add_batch(host: Node3D, kind: String, xforms: Array, tile_size: float) -> void:
	if xforms.is_empty():
		return

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = _mesh_for(kind, tile_size)
	multi.instance_count = xforms.size()
	for i: int in xforms.size():
		multi.set_instance_transform(i, xforms[i])

	var node := MultiMeshInstance3D.new()
	node.name = kind
	node.multimesh = multi
	node.material_override = _material_for(kind)
	# Le décor projette son ombre comme le reste du plateau : c'est elle qui le
	# pose sur sa case au lieu de le laisser flotter.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	host.add_child(node)


## Maillage unitaire d'un type de décor — mis à l'échelle par chaque instance.
static func _mesh_for(kind: String, tile_size: float) -> Mesh:
	match kind:
		"trunk":
			var trunk := CylinderMesh.new()
			trunk.top_radius = tile_size * 0.045
			trunk.bottom_radius = tile_size * 0.06
			trunk.height = 1.0
			trunk.radial_segments = 6
			trunk.rings = 1
			return trunk
		"canopy":
			var canopy := CylinderMesh.new()
			canopy.top_radius = 0.0
			canopy.bottom_radius = tile_size * 0.22
			canopy.height = 1.0
			canopy.radial_segments = 7
			canopy.rings = 1
			return canopy
		_:
			# Rocher et créneau : un cube unitaire, mis aux dimensions voulues par
			# l'échelle de chaque instance. Les arêtes vives font tout le travail.
			var block := BoxMesh.new()
			block.size = Vector3.ONE
			return block


## Matériau d'un type de décor : mat, sans transparence, comme le terrain.
static func _material_for(kind: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.metallic = 0.0
	match kind:
		"trunk":
			mat.albedo_color = Color(TRUNK_COLOR)
			mat.roughness = 0.95
		"canopy":
			mat.albedo_color = Color(CANOPY_COLOR)
			mat.roughness = 0.9
		"rock":
			mat.albedo_color = Color(ROCK_COLOR)
			mat.roughness = 1.0
		_:
			mat.albedo_color = Color(WALL_COLOR)
			mat.roughness = 0.85
	return mat
#endregion
