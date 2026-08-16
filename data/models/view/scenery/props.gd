class_name TacticsProps
extends RefCounted


## Ce qui pousse et ce qui se bâtit sur les cases : arbres, rochers, créneaux,
## maisons, fortins, portes, ruines, tours, ponts, roseaux.
##
## Le plateau disait son terrain par la seule teinte de ses cases — un damier
## vert clair et vert foncé, où « forêt » était une convention à retenir plutôt
## qu'une chose à voir. Ce module y pose des volumes : on reconnaît un bois, un
## éboulis, un rempart, un hameau, sans avoir appris le code couleur.
##
## Tout est procédural, comme [TacticsScenery] : des formes primitives assemblées,
## aucune image à produire, aucun artiste. Quatre règles tiennent l'ensemble :
##
## - **Rien ne cache une unité.** Le décor est plafonné sous la hauteur d'un pion,
##   et sur les cases où l'on peut se tenir — forêt, montagne, village, fortin,
##   ruines — il est décalé vers un coin ou semé en couronne, centre dégagé. Mur
##   et tour étant infranchissables, leur décor peut occuper toute la case sans
##   masquer personne. Seul ce qui est plus bas que [constant FLAT_HEIGHT] a le
##   droit de couvrir le centre : on marche dessus, comme sur le platelage d'un
##   pont.
## - **Rien n'intercepte la souris.** Ces volumes n'ont aucune collision — la
##   sélection continue de viser la tuile elle-même, dont le corps physique est
##   la seule chose que le rayon rencontre.
## - **Rien n'est tiré au hasard.** La variation vient d'un hachage des
##   coordonnées de la case : deux machines d'une même partie en réseau dessinent
##   le même bois, et rouvrir une carte ne le redessine pas autrement.
## - **Un ouvrage lit ses voisines.** Un pont pose ses garde-corps le long de sa
##   travée, une porte ses piliers dans l'alignement du rempart : le sens se
##   déduit de la carte, ce n'est pas un réglage de plus à poser case par case.
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
## C'est ce décalage qui laisse le centre dégagé, donc le pion lisible : arbre
## d'un bois, maison d'un hameau, colonne d'une ruine s'enracinent tous là.
## L'éboulis d'une montagne, lui, sème ses pierres en couronne à [constant
## ROCK_RING] — même promesse, autre figure.
##
## Tenu par un test : 0,30 de case d'écart contre 0,18 de demi-largeur de
## frondaison au plus, le centre reste hors du feuillage. Élargir l'un sans
## resserrer l'autre casserait la promesse.
const CORNER_OFFSET: float = 0.30

## Sous cette hauteur, un décor se marche dessus.
##
## Le platelage d'un pont, un caillou de sable : ils couvrent le centre de leur
## case et c'est bien ce qu'on leur demande. Au-dessus, un décor posé sur une
## case praticable doit s'écarter — c'est la règle que tient le test.
const FLAT_HEIGHT: float = 0.12


#endregion

#region Teintes
## Les décors se détachent de leur terrain sans le renier : un tronc plus sombre
## que le sol de la forêt, un rocher plus clair que la montagne qui le porte.
const TRUNK_COLOR: String = "#4a3524"
const CANOPY_COLOR: String = "#2c6b1c"


## Le vert d'un conifère : plus sombre et plus froid que celui d'un feuillu.
## Deux verts valent mieux qu'un — c'est ce qui fait voir un bois mêlé là où une
## teinte unique ne montrait qu'une seule espèce répétée vingt fois.
const PINE_COLOR: String = "#1f5233"


const ROCK_COLOR: String = "#9d8a72"


## Les deux autres pierres d'un éboulis : le pic, qu'on voit sur le ciel, est
## plus sombre ; la dalle, qui prend le jour à plat, plus claire.
const ROCK_DARK_COLOR: String = "#87795f"


const ROCK_PALE_COLOR: String = "#b0a08a"


const WALL_COLOR: String = "#6b6b6b"


## Ce qui se bâtit. L'ardoise et l'or des toits et des bannières viennent de la
## charte « Velmar : nuit et or » — un plateau et des menus de la même famille.
const STONE_COLOR: String = "#8a867e"


const DARK_STONE_COLOR: String = "#6d6a64"


## La pierre taillée du haut d'un ouvrage : créneaux d'un rempart, merlons d'une
## tour. Plus claire que le corps qu'elle couronne — c'est ce contraste qui fait
## lire une dentelure là où un bloc uni ne montrait qu'une arête.
const CUT_STONE_COLOR: String = "#a8a296"


const PLASTER_COLOR: String = "#c9b48f"


const ROOF_COLOR: String = "#7c3f2d"


const SLATE_COLOR: String = "#3f4a6b"


const WOOD_COLOR: String = "#6d4c2f"


const BANNER_COLOR: String = "#d4af37"


## Ce qui pousse dans la vase, et les touffes qui empêchent une plaine d'être
## un tapis uni.
const REED_COLOR: String = "#5f7a3a"


const TUFT_COLOR: String = "#74b85c"


const PEBBLE_COLOR: String = "#b8a37a"


## Créneaux posés sur une case de rempart.
##
## Trois, et pas quatre : les merlons se posent au tiers de case, donc sur un
## pas qui retombe juste d'une case à l'autre (−1/3, 0, +1/3, puis +2/3 chez la
## voisine). Un rempart de six cases dessine une dentelure régulière au lieu de
## six motifs recollés bout à bout.
const CRENEL_COUNT: int = 3

## Merlons couronnant une tour, posés sur les diagonales.
##
## Sur les diagonales plutôt que sur les axes : sous la caméra tactique, deux
## des quatre côtés sont vus par la tranche, et des merlons cardinaux y
## disparaîtraient de profil.
const TOWER_MERLONS: int = 4

#endregion

#region Voisinages qui donnent le sens d'un ouvrage
## Ce qui prolonge un rempart : une porte s'aligne dessus.
const RAMPART_KINDS: Array[int] = [
	MapDataClass.TerrainType.WALL,
	MapDataClass.TerrainType.TOWER,
	MapDataClass.TerrainType.GATE,
	MapDataClass.TerrainType.MOUNTAIN,
]

## Ce qui prolonge une travée : un pont pose ses garde-corps le long de celle-ci.
const SPAN_KINDS: Array[int] = [
	MapDataClass.TerrainType.BRIDGE,
	MapDataClass.TerrainType.PATH,
	MapDataClass.TerrainType.GATE,
]


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
	var terrain_by_cell: Dictionary = _index(cells)

	for entry: Variant in cells:
		if not (entry is Dictionary):
			continue
		var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
		var top: Vector3 = entry.get("top", Vector3.ZERO)

		match int(entry.get("terrain", -1)):
			MapDataClass.TerrainType.GRASS:
				# Une touffe sur trois cases environ : de quoi qu'une plaine ne soit
				# pas un tapis uni, sans la transformer en friche.
				if _noise(cell, 30) < 0.34:
					_append(out, "tuft", _tuft(top, cell, tile_size))
			MapDataClass.TerrainType.FOREST:
				_plant_tree(out, top, cell, tile_size)
			MapDataClass.TerrainType.MOUNTAIN:
				_raise_rocks(out, top, cell, tile_size)
			MapDataClass.TerrainType.WALL:
				var wall_ew: bool = _runs_east_west(cell, terrain_by_cell, RAMPART_KINDS)
				_append(out, "wall_base", _wall_base(top, tile_size, wall_ew))
				_append(out, "wall_body", _wall_body(top, tile_size, wall_ew))
				for i: int in CRENEL_COUNT:
					_append(out, "wall_crenel", _wall_crenel(top, tile_size, wall_ew, i))
			MapDataClass.TerrainType.SAND:
				if _noise(cell, 31) < 0.28:
					_append(out, "pebble", _pebble(top, cell, tile_size))
			MapDataClass.TerrainType.SWAMP:
				for i: int in 3:
					_append(out, "reed", _reed(top, cell, tile_size, i))
			MapDataClass.TerrainType.VILLAGE:
				_build_hamlet(out, top, cell, tile_size)
			MapDataClass.TerrainType.FORT:
				_append(out, "keep", _keep(top, cell, tile_size))
				if _has_banner(cell):
					_append(out, "pole", _banner_pole(top, cell, tile_size))
					_append(out, "banner", _banner(top, cell, tile_size))
			MapDataClass.TerrainType.GATE:
				var gate_ew: bool = _runs_east_west(cell, terrain_by_cell, RAMPART_KINDS)
				for side: int in 2:
					_append(out, "pier", _gate_pier(top, tile_size, gate_ew, side))
					_append(out, "lintel", _gate_lintel(top, tile_size, gate_ew, side))
			MapDataClass.TerrainType.RUINS:
				_strew_ruins(out, top, cell, tile_size)
			MapDataClass.TerrainType.TOWER:
				_append(out, "tower_base", _tower_base(top, tile_size))
				_append(out, "tower_shaft", _tower_shaft(top, tile_size))
				for i: int in TOWER_MERLONS:
					_append(out, "tower_merlon", _tower_merlon(top, tile_size, i))
				_append(out, "tower_roof", _tower_roof(top, tile_size))
			MapDataClass.TerrainType.BRIDGE:
				var span_ew: bool = _runs_east_west(cell, terrain_by_cell, SPAN_KINDS)
				_append(out, "deck", _bridge_deck(top, tile_size))
				for side: int in 2:
					_append(out, "railing", _bridge_railing(top, tile_size, span_ew, side))
	return out


## Terrain de chaque case, indexé par coordonnée — de quoi lire ses voisines.
static func _index(cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in cells:
		if entry is Dictionary:
			out[entry.get("cell", Vector2i.ZERO)] = int(entry.get("terrain", -1))
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


#region Forêt
## Les trois arbres que sait pousser une case de bois.
##
## Un seul cylindre coiffé d'un cône donnait un bois de quilles : toutes les
## cases portaient la même silhouette, à la carrure près. Trois profils, tirés
## du hachage de la case, suffisent à ce qu'un bois de vingt cases n'ait plus
## deux arbres voisins pareils.
enum TreeShape {
	LEAFY, ## Feuillu : fût évasé, deux branches, trois masses de feuillage.
	PINE, ## Conifère : trois étages de cônes, du plus large au plus effilé.
	SAPLING, ## Jeune pousse : un fût court, deux petites masses, bien plus bas.
}

## Quel arbre pousse sur cette case. Feuillus en majorité, pousses en minorité.
static func _tree_of(cell: Vector2i) -> TreeShape:
	var draw: float = _noise(cell, 4)
	if draw < 0.44:
		return TreeShape.LEAFY
	if draw < 0.82:
		return TreeShape.PINE
	return TreeShape.SAPLING


## Plante l'arbre d'une case de forêt : fût, branches et frondaison.
static func _plant_tree(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	match _tree_of(cell):
		TreeShape.PINE:
			_plant_pine(out, top, cell, tile_size)
		TreeShape.SAPLING:
			_plant_sapling(out, top, cell, tile_size)
		_:
			_plant_leafy(out, top, cell, tile_size)


## Les trois masses de feuillage d'un feuillu.
##
## `[altitude, hauteur, largeur, dehors, côté]` : les deux premières en fraction
## de [constant MAX_HEIGHT], les trois suivantes en fraction de case. `dehors`
## éloigne du centre de la case, `côté` glisse le long du bord — **aucune ne
## rentre vers le centre**, et c'est ce qui garde lisible le pion qui s'y tient.
const LEAFY_MASSES: Array = [
	[0.58, 0.36, 0.32, 0.02, -0.04],
	[0.80, 0.28, 0.25, 0.01, 0.07],
	[0.55, 0.26, 0.23, 0.06, -0.10],
]

## Les trois étages d'un conifère. `[altitude, hauteur, largeur]`, mêmes unités.
const PINE_TIERS: Array = [
	[0.34, 0.36, 0.32],
	[0.60, 0.32, 0.25],
	[0.84, 0.30, 0.17],
]

## Les deux masses d'une jeune pousse, dans le format de [constant LEAFY_MASSES].
const SAPLING_MASSES: Array = [
	[0.40, 0.30, 0.27, 0.02, -0.02],
	[0.58, 0.22, 0.19, 0.05, 0.07],
]


## Feuillu : un fût qui s'évase du pied, deux branches, trois masses de feuilles.
static func _plant_leafy(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	var rise: float = _tree_rise(cell)
	var girth: float = _tree_girth(cell)
	var foot: Vector3 = top + _corner(cell, tile_size)
	var trunk_h: float = MAX_HEIGHT * 0.42 * rise
	var trunk_w: float = tile_size * 0.13 * girth

	_append(out, "trunk", Transform3D(
		Basis(Vector3.UP, _noise(cell, 2) * TAU).scaled(Vector3(trunk_w, trunk_h, trunk_w)),
		foot + Vector3(0.0, trunk_h / 2.0, 0.0)))

	# Deux branches, chacune de son côté, et toutes deux penchées vers l'extérieur
	# de la case : une branche qui rentre passerait au-dessus du pion.
	var out_dir: Vector3 = _corner_dir(cell)
	var side_dir: Vector3 = Vector3(-out_dir.z, 0.0, out_dir.x)
	for i: int in 2:
		var lean: Vector3 = (side_dir * (1.0 if i == 0 else -1.0) * 0.9
			+ out_dir * 0.45 + Vector3.UP * 0.9).normalized()
		var length: float = MAX_HEIGHT * (0.20 + _noise(cell, 5 + i) * 0.08) * rise
		var joint: Vector3 = foot + Vector3(0.0, trunk_h * (0.52 + 0.16 * float(i)), 0.0)
		_append(out, "trunk", Transform3D(
			_aim(lean).scaled(Vector3(trunk_w * 0.38, length, trunk_w * 0.38)),
			joint + lean * length / 2.0))

	_pile_masses(out, "canopy", LEAFY_MASSES, foot, cell, tile_size, rise, girth)


## Conifère : un fût grêle et trois cônes empilés, le dernier en flèche.
static func _plant_pine(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	var rise: float = _tree_rise(cell)
	var girth: float = _tree_girth(cell)
	var foot: Vector3 = top + _corner(cell, tile_size)
	var trunk_h: float = MAX_HEIGHT * 0.28 * rise
	var trunk_w: float = tile_size * 0.10 * girth

	_append(out, "trunk", Transform3D(
		Basis(Vector3.UP, _noise(cell, 2) * TAU).scaled(Vector3(trunk_w, trunk_h, trunk_w)),
		foot + Vector3(0.0, trunk_h / 2.0, 0.0)))

	for i: int in PINE_TIERS.size():
		var tier: Array = PINE_TIERS[i]
		var width: float = tile_size * float(tier[2]) * girth
		var height: float = MAX_HEIGHT * float(tier[1]) * rise
		# Chaque étage tourne pour lui-même : sans cela, les arêtes des trois
		# cônes s'alignent et l'arbre redevient un seul cône à gradins.
		_append(out, "pine", Transform3D(
			Basis(Vector3.UP, _noise(cell, 6 + i) * TAU).scaled(Vector3(width, height, width)),
			foot + Vector3(0.0, MAX_HEIGHT * float(tier[0]) * rise, 0.0)))


## Jeune pousse : deux masses sur un fût court — de quoi trouer la canopée.
static func _plant_sapling(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	var rise: float = _tree_rise(cell)
	var girth: float = _tree_girth(cell)
	var foot: Vector3 = top + _corner(cell, tile_size)
	var trunk_h: float = MAX_HEIGHT * 0.26 * rise
	var trunk_w: float = tile_size * 0.10 * girth

	_append(out, "trunk", Transform3D(
		Basis(Vector3.UP, _noise(cell, 2) * TAU).scaled(Vector3(trunk_w, trunk_h, trunk_w)),
		foot + Vector3(0.0, trunk_h / 2.0, 0.0)))

	_pile_masses(out, "canopy", SAPLING_MASSES, foot, cell, tile_size, rise, girth)


## Pose une frondaison décrite au format de [constant LEAFY_MASSES].
static func _pile_masses(out: Dictionary, kind: String, masses: Array, foot: Vector3,
		cell: Vector2i, tile_size: float, rise: float, girth: float) -> void:
	var out_dir: Vector3 = _corner_dir(cell)
	var side_dir: Vector3 = Vector3(-out_dir.z, 0.0, out_dir.x)
	for i: int in masses.size():
		var mass: Array = masses[i]
		var width: float = tile_size * float(mass[2]) * girth
		var height: float = MAX_HEIGHT * float(mass[1]) * rise
		var offset: Vector3 = out_dir * tile_size * float(mass[3]) \
			+ side_dir * tile_size * float(mass[4])
		_append(out, kind, Transform3D(
			Basis(Vector3.UP, _noise(cell, 7 + i) * TAU).scaled(Vector3(width, height, width)),
			foot + offset + Vector3(0.0, MAX_HEIGHT * float(mass[0]) * rise, 0.0)))


## Carrure d'un arbre — sa largeur, qui a le droit de varier franchement.
##
## Plafonnée à 1,10 : au-delà, la plus large des masses de feuillage mordait sur
## le centre de la case, que [constant CORNER_OFFSET] promet de laisser libre.
static func _tree_girth(cell: Vector2i) -> float:
	return 0.85 + _noise(cell, 1) * 0.25


## Élancement d'un arbre : sa part du plafond, jamais davantage.
##
## Un seul facteur servait aux deux, et il montait à 1,2 : un arbre sur quatre
## dépassait [constant MAX_HEIGHT] d'un cinquième. Le test ne l'avait pas vu — il
## ne dessinait qu'une case de forêt, et le hachage de celle-là tombait juste.
static func _tree_rise(cell: Vector2i) -> float:
	return 0.78 + _noise(cell, 1) * 0.22


#endregion


#region Montagne
## Ce qu'un éboulis pose sur une case : trois pierres, jamais de la même famille.
enum Stone {
	BLOCK, ## Bloc anguleux, trapu, basculé.
	SPIRE, ## Pic effilé — c'est lui qui donne à la case son profil de montagne.
	SLAB, ## Dalle plate, couchée de guingois.
}

## Distance du centre de la case où se posent les pierres, en fraction de case.
##
## La montagne se traverse (au prix de deux points de mouvement) : une unité peut
## s'y tenir, donc son décor s'écarte du centre comme celui d'un bois. Sous 0,32
## la plus large des dalles commencerait à mordre dessus.
const ROCK_RING: float = 0.32


## Deux ou trois pierres autour du centre de la case, chacune de son espèce.
static func _raise_rocks(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	var count: int = 2 if _noise(cell, 12) < 0.30 else 3
	for i: int in count:
		var salt: int = 10 + i * 7
		var seat: Vector3 = top + _scatter(cell, tile_size, i, count, salt)
		match _stone_of(cell, salt):
			Stone.SPIRE:
				_append(out, "rock_pic", _rock_spire(seat, cell, salt, tile_size))
			Stone.SLAB:
				_append(out, "rock_slab", _rock_slab(seat, cell, salt, tile_size))
			_:
				_append(out, "rock", _rock_block(seat, cell, salt, tile_size))


## Quelle pierre tire cette place de l'éboulis.
static func _stone_of(cell: Vector2i, salt: int) -> Stone:
	var draw: float = _noise(cell, salt + 500)
	if draw < 0.46:
		return Stone.BLOCK
	if draw < 0.78:
		return Stone.SPIRE
	return Stone.SLAB


## Bloc anguleux : trapu, tourné et basculé, jamais cubique.
##
## Un bloc plutôt qu'une sphère : Godot lisse les normales d'une `SphereMesh`
## quel que soit son nombre de segments, ce qui donne un galet — un œuf, même,
## dès qu'on l'étire. Ce sont les arêtes vives et l'inclinaison qui font la
## pierre : chaque face prend la lumière autrement.
static func _rock_block(seat: Vector3, cell: Vector2i, salt: int,
		tile_size: float) -> Transform3D:
	var bulk: float = 0.75 + _noise(cell, salt + 1) * 0.5
	var width: float = tile_size * 0.28 * bulk
	var depth: float = width * (0.60 + _noise(cell, salt + 2) * 0.55)
	var height: float = MAX_HEIGHT * 0.26 * bulk
	var tilt := Basis.from_euler(Vector3(
		(_noise(cell, salt + 3) - 0.5) * 0.55,
		_noise(cell, salt + 4) * TAU,
		(_noise(cell, salt + 5) - 0.5) * 0.55))
	return Transform3D(
		tilt.scaled(Vector3(width, height, depth)),
		seat + Vector3(0.0, height / 2.0, 0.0))


## Pic : une aiguille à cinq pans, deux fois plus haute que large.
##
## C'est la pièce qui fait lire « montagne » plutôt que « caillasse » : deux
## blocs trapus ne montraient qu'un éboulis, une arête qui monte donne un relief.
static func _rock_spire(seat: Vector3, cell: Vector2i, salt: int,
		tile_size: float) -> Transform3D:
	var bulk: float = 0.80 + _noise(cell, salt + 1) * 0.45
	var width: float = tile_size * 0.20 * bulk
	var height: float = MAX_HEIGHT * (0.42 + _noise(cell, salt + 2) * 0.26)
	# À peine dévié de l'aplomb : un pic couché n'est plus un pic.
	var tilt := Basis.from_euler(Vector3(
		(_noise(cell, salt + 3) - 0.5) * 0.30,
		_noise(cell, salt + 4) * TAU,
		(_noise(cell, salt + 5) - 0.5) * 0.30))
	return Transform3D(
		tilt.scaled(Vector3(width, height, width * (0.85 + _noise(cell, salt + 6) * 0.3))),
		seat + Vector3(0.0, height / 2.0, 0.0))


## Dalle : une pierre plate posée en biais, celle sur laquelle on s'assoit.
static func _rock_slab(seat: Vector3, cell: Vector2i, salt: int,
		tile_size: float) -> Transform3D:
	var bulk: float = 0.80 + _noise(cell, salt + 1) * 0.35
	var width: float = tile_size * 0.30 * bulk
	var depth: float = width * (0.55 + _noise(cell, salt + 2) * 0.40)
	var height: float = MAX_HEIGHT * 0.11 * bulk
	# Franchement inclinée : à plat, une dalle ne se distingue pas du sol.
	var tilt := Basis.from_euler(Vector3(
		(_noise(cell, salt + 3) - 0.5) * 0.75,
		_noise(cell, salt + 4) * TAU,
		(_noise(cell, salt + 5) - 0.5) * 0.75))
	return Transform3D(
		tilt.scaled(Vector3(width, height, depth)),
		seat + Vector3(0.0, height / 2.0, 0.0))


## Place la [param index]e pièce d'un semis de [param count], autour du centre.
##
## Un tour complet réparti en parts égales, plus une dérive dans la part : les
## pièces ne se superposent jamais, et elles ne dessinent pas non plus l'étoile
## régulière qu'un angle fixe donnerait.
static func _scatter(cell: Vector2i, tile_size: float, index: int, count: int,
		salt: int) -> Vector3:
	var angle: float = (float(index) + 0.15 + _noise(cell, salt + 900) * 0.7) \
		* (TAU / float(count))
	var radius: float = tile_size * (ROCK_RING + _noise(cell, salt + 901) * 0.05)
	return Vector3(cos(angle), 0.0, sin(angle)) * radius


#endregion


#region Formes


## Soubassement d'un rempart : une semelle plus large que le mur, très basse.
##
## C'est le fruit d'un ouvrage de pierre — la retraite d'un ou deux pouces qui
## pose le mur sur le sol au lieu de l'y planter. Sombre, elle fait aussi le
## liseré qui décolle le rempart de sa case.
##
## [param east_west] le rempart court-il d'est en ouest ?
static func _wall_base(top: Vector3, tile_size: float, east_west: bool) -> Transform3D:
	var height: float = MAX_HEIGHT * 0.10
	return Transform3D(
		Basis.IDENTITY.scaled(_along(tile_size * 0.96, height, tile_size * 0.64, east_west)),
		top + Vector3(0.0, height / 2.0, 0.0))


## Corps d'un rempart : le chemin de ronde, continu d'une case à la suivante.
##
## Il court sur toute la longueur de la case dans le sens du rempart, et n'en
## occupe que la moitié en travers : c'est cette proportion qui fait lire un
## **mur** — un bloc plein cadre ne montrait qu'un cube gris.
##
## [param east_west] le rempart court-il d'est en ouest ?
static func _wall_body(top: Vector3, tile_size: float, east_west: bool) -> Transform3D:
	var base_h: float = MAX_HEIGHT * 0.10
	var height: float = MAX_HEIGHT * 0.42
	return Transform3D(
		Basis.IDENTITY.scaled(_along(tile_size * 0.92, height, tile_size * 0.54, east_west)),
		top + Vector3(0.0, base_h + height / 2.0, 0.0))


## Créneau : un des blocs dentelant le haut du rempart, embrasure entre deux.
##
## Sa position ne dépend que de la case et du rang, jamais d'un tirage : trois
## créneaux au pas d'un tiers de case retombent exactement sur ceux de la case
## voisine, et un rempart de six cases porte une seule dentelure.
##
## [param east_west] le rempart court-il d'est en ouest ? [param index] 0 à 2.
static func _wall_crenel(top: Vector3, tile_size: float, east_west: bool,
		index: int) -> Transform3D:
	var walk_h: float = MAX_HEIGHT * 0.52 # semelle + corps
	var height: float = MAX_HEIGHT * 0.19
	var step: float = (float(index) - float(CRENEL_COUNT - 1) / 2.0) / float(CRENEL_COUNT)
	var offset: Vector3 = Vector3(step, 0.0, 0.0) if east_west else Vector3(0.0, 0.0, step)
	return Transform3D(
		Basis.IDENTITY.scaled(_along(tile_size * 0.17, height, tile_size * 0.54, east_west)),
		top + offset * tile_size + Vector3(0.0, walk_h + height / 2.0, 0.0))


## Dimensions d'un ouvrage qui court dans un sens : longueur, hauteur, épaisseur.
##
## [param east_west] vrai, l'ouvrage s'allonge sur `x` ; faux, sur `z`.
static func _along(length: float, height: float, thickness: float,
		east_west: bool) -> Vector3:
	return Vector3(length, height, thickness) if east_west \
		else Vector3(thickness, height, length)


## Touffe d'herbe : un petit cône, à peine plus haut qu'un caillou.
##
## Délibérément menue et claire. Une touffe plus haute prenait, de loin, l'allure
## d'un arbre — or un bois donne +1 DÉF et une plaine rien : deux terrains qu'on
## doit distinguer d'un coup d'œil avant de décider où poser une unité.
static func _tuft(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var scale_factor: float = 0.7 + _noise(cell, 32) * 0.6
	var height: float = MAX_HEIGHT * 0.12 * scale_factor
	var width: float = tile_size * 0.13 * scale_factor
	return Transform3D(
		Basis(Vector3.UP, _noise(cell, 33) * TAU).scaled(Vector3(width, height, width)),
		top + _corner(cell, tile_size) + Vector3(0.0, height / 2.0, 0.0))


## Caillou de sable : posé à plat, assez bas pour qu'on lui marche dessus.
static func _pebble(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var scale_factor: float = 0.6 + _noise(cell, 34) * 0.6
	var height: float = FLAT_HEIGHT * 0.5 * scale_factor
	var width: float = tile_size * 0.13 * scale_factor
	return Transform3D(
		Basis(Vector3.UP, _noise(cell, 35) * TAU).scaled(Vector3(width, height, width * 0.7)),
		top + _corner(cell, tile_size) * 0.7 + Vector3(0.0, height / 2.0, 0.0))


## Roseau de marais : une lame fine, penchée, trois par case.
static func _reed(top: Vector3, cell: Vector2i, tile_size: float, index: int) -> Transform3D:
	var salt: int = 40 + index
	var scale_factor: float = 0.7 + _noise(cell, salt) * 0.6
	var height: float = MAX_HEIGHT * 0.42 * scale_factor
	var yaw: float = _noise(cell, salt + 50) * TAU
	# Penchés, et chacun dans son sens : d'aplomb, trois lames font une brosse.
	var lean := Basis.from_euler(Vector3(
		(_noise(cell, salt + 100) - 0.5) * 0.5, yaw, (_noise(cell, salt + 150) - 0.5) * 0.5))
	var spread: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw)) * tile_size * 0.05
	return Transform3D(
		lean.scaled(Vector3(tile_size * 0.035, height, tile_size * 0.035)),
		top + _corner(cell, tile_size) + spread + Vector3(0.0, height / 2.0, 0.0))


#region Constructions
## Le hameau d'une case : une maison, et parfois la remise qui va avec.
##
## Un bloc coiffé d'un prisme faisait bien une maison, mais **la** maison :
## seize cases de village en alignaient seize exemplaires. Deux modèles, un
## débord de toit, une cheminée, une porte et une remise de temps en temps
## suffisent à ce qu'un hameau ait l'air habité.
static func _build_hamlet(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	_build_house(out, top + _corner(cell, tile_size), cell, tile_size)
	# La remise se pose dans le coin opposé : accolée à la maison, elle n'en
	# serait qu'une excroissance, et au centre elle gênerait le pion.
	if _noise(cell, 24) < 0.42:
		_build_shed(out, top + _corner(cell, tile_size, 2), cell, tile_size)


## Part du plafond prise par les murs d'une maison ; le toit prend le reste.
const HOUSE_WALL_RISE: float = 0.40
const HOUSE_ROOF_RISE: float = 0.32


## Corps de logis : murs, toit débordant, porte, et souvent une cheminée.
##
## Deux modèles selon le hachage — la grande chaumière au toit de tuile, et la
## petite maison au toit d'ardoise croisé d'une croupe. Le débord du toit est ce
## qui distingue une maison d'une caisse : c'est l'ombre portée sous l'avant-toit
## qui donne l'épaisseur du mur.
static func _build_house(out: Dictionary, seat: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	var small: bool = _noise(cell, 23) < 0.42
	var grow: float = 0.88 + _noise(cell, 20) * 0.24
	var width: float = tile_size * (0.20 if small else 0.26) * grow
	var depth: float = width * ((1.00 + _noise(cell, 21) * 0.18) if small
		else (1.02 + _noise(cell, 21) * 0.30))
	var wall_h: float = MAX_HEIGHT * HOUSE_WALL_RISE * (0.85 if small else 1.0)
	var roof_h: float = MAX_HEIGHT * HOUSE_ROOF_RISE * (0.90 if small else 1.0)
	# Une maison n'est jamais de biais : elle s'aligne sur un quart de tour.
	var basis := Basis(Vector3.UP, floor(_noise(cell, 22) * 4.0) * (TAU / 4.0))

	_append(out, "house_wall", Transform3D(
		basis.scaled(Vector3(width, wall_h, depth)),
		seat + Vector3(0.0, wall_h / 2.0, 0.0)))

	# Le faîtage d'un `PrismMesh` court sur `z` : la profondeur étant le grand
	# côté, le toit se pose dans le sens de la maison sans qu'on ait à le tourner.
	var ridge: String = "house_hip" if small else "house_roof"
	_append(out, ridge, Transform3D(
		basis.scaled(Vector3(width * 1.22, roof_h, depth * 1.12)),
		seat + Vector3(0.0, wall_h + roof_h / 2.0, 0.0)))
	if small:
		# La croupe : un second pan, en travers et un peu plus bas, qui casse la
		# ligne du faîtage — c'est ce qui fait lire quatre pans au lieu de deux.
		_append(out, ridge, Transform3D(
			basis.scaled(Vector3(depth * 1.10, roof_h * 0.80, width * 1.00)),
			seat + Vector3(0.0, wall_h + roof_h * 0.40, 0.0)))

	_hang_door(out, basis, seat, cell, width, depth, wall_h)
	if _noise(cell, 25) < 0.58:
		_raise_chimney(out, basis, seat, cell, tile_size, width, depth, wall_h, roof_h)


## Porte : un panneau de bois plaqué sur la façade, du côté qui regarde dehors.
##
## Du côté qui regarde dehors, et pas d'un côté tiré au sort : une porte qui
## donne sur le centre de la case est un mur pour la caméra tactique, qui voit
## la maison de l'extérieur du plateau.
static func _hang_door(out: Dictionary, basis: Basis, seat: Vector3, cell: Vector2i,
		width: float, depth: float, wall_h: float) -> void:
	var want: Vector3 = _corner_dir(cell)
	var facing: int = 0
	var best: float = -2.0
	for i: int in 4:
		var normal: Vector3 = basis * (Vector3.RIGHT if i % 2 == 0 else Vector3.BACK) \
			* (1.0 if i < 2 else -1.0)
		var score: float = normal.normalized().dot(want)
		if score > best:
			best = score
			facing = i
	var side: float = 1.0 if facing < 2 else -1.0
	var along_x: bool = facing % 2 == 0
	var reach: float = (width if along_x else depth) / 2.0
	var normal: Vector3 = (basis * (Vector3.RIGHT if along_x else Vector3.BACK)).normalized() * side

	var door_h: float = wall_h * 0.62
	var leaf: float = (depth if along_x else width) * 0.34
	var thick: float = leaf * 0.22
	var size := Vector3(thick, door_h, leaf) if along_x else Vector3(leaf, door_h, thick)
	_append(out, "door", Transform3D(
		basis.scaled(size),
		seat + normal * (reach + thick * 0.35) + Vector3(0.0, door_h / 2.0, 0.0)))


## Cheminée : un conduit de pierre qui perce le toit près du pignon.
static func _raise_chimney(out: Dictionary, basis: Basis, seat: Vector3, cell: Vector2i,
		tile_size: float, width: float, depth: float, wall_h: float,
		roof_h: float) -> void:
	var stack: float = tile_size * 0.075
	var height: float = roof_h * 0.95
	# Sur le rampant, à un tiers du faîtage : plantée au milieu du toit, elle
	# ressemble à un mât ; au bord, elle flotte à côté de la maison.
	var offset: Vector3 = basis * Vector3(
		width * (0.18 if _noise(cell, 26) < 0.5 else -0.18), 0.0,
		depth * (0.30 if _noise(cell, 27) < 0.5 else -0.30))
	_append(out, "chimney", Transform3D(
		basis.scaled(Vector3(stack, height, stack)),
		seat + offset + Vector3(0.0, wall_h + roof_h * 0.35 + height / 2.0, 0.0)))


## Remise : une resserre basse, à toit de chaume, dans un coin de la cour.
static func _build_shed(out: Dictionary, seat: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	var grow: float = 0.85 + _noise(cell, 36) * 0.3
	var width: float = tile_size * 0.15 * grow
	var depth: float = width * (1.05 + _noise(cell, 37) * 0.35)
	var wall_h: float = MAX_HEIGHT * 0.22
	var roof_h: float = MAX_HEIGHT * 0.16
	var basis := Basis(Vector3.UP, floor(_noise(cell, 38) * 4.0) * (TAU / 4.0))

	_append(out, "house_wall", Transform3D(
		basis.scaled(Vector3(width, wall_h, depth)),
		seat + Vector3(0.0, wall_h / 2.0, 0.0)))
	_append(out, "house_roof", Transform3D(
		basis.scaled(Vector3(width * 1.25, roof_h, depth * 1.10)),
		seat + Vector3(0.0, wall_h + roof_h / 2.0, 0.0)))


## Donjon d'un fortin : un tambour de pierre trapu, dans un coin de la cour.
##
## Sa taille varie franchement d'une case à l'autre : un fortin de six cases
## alignait sinon six tourelles rigoureusement identiques, ce qui ressemblait
## moins à une place forte qu'à un jeu d'échecs renversé.
static func _keep(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var height: float = MAX_HEIGHT * _keep_rise(cell)
	var width: float = _keep_width(cell, tile_size)
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(width, height, width)),
		top + _corner(cell, tile_size) + Vector3(0.0, height / 2.0, 0.0))


## Hampe plantée sur le donjon — c'est elle qui porte les couleurs.
##
## Elle monte jusqu'au plafond du décor, quelle que soit la taille du donjon :
## c'est la hampe qui aligne les bannières d'un même fortin, pas les tourelles.
static func _banner_pole(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var keep_h: float = MAX_HEIGHT * _keep_rise(cell)
	var height: float = MAX_HEIGHT - keep_h
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(tile_size * 0.03, height, tile_size * 0.03)),
		top + _corner(cell, tile_size) + Vector3(0.0, keep_h + height / 2.0, 0.0))


## Bannière : un fanion d'or, du côté du coin — on tient une place forte.
static func _banner(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var height: float = MAX_HEIGHT * 0.18
	var yaw: float = _noise(cell, 60) * TAU
	var basis := Basis(Vector3.UP, yaw)
	var side: Vector3 = basis * Vector3(tile_size * 0.06, 0.0, 0.0)
	return Transform3D(
		basis.scaled(Vector3(tile_size * 0.11, height, tile_size * 0.012)),
		top + _corner(cell, tile_size) + side
			+ Vector3(0.0, MAX_HEIGHT - height, 0.0))


## Toute case de fortin n'est pas un mât : deux sur cinq environ portent les
## couleurs, les autres ne sont que de la pierre. Une bannière par case en
## faisait une haie de fanions.
static func _has_banner(cell: Vector2i) -> bool:
	return _noise(cell, 62) < 0.45


## Part du plafond qu'occupe le donjon d'une case.
static func _keep_rise(cell: Vector2i) -> float:
	return 0.38 + _noise(cell, 61) * 0.30


static func _keep_width(cell: Vector2i, tile_size: float) -> float:
	return tile_size * (0.26 + _noise(cell, 63) * 0.08)


## Pilier de porte : deux montants dans l'alignement du rempart, passage libre.
##
## [param east_west] le rempart court-il d'est en ouest ? [param side] 0 ou 1.
static func _gate_pier(top: Vector3, tile_size: float, east_west: bool, side: int) -> Transform3D:
	var height: float = MAX_HEIGHT * GATE_PIER_RISE
	var away: Vector3 = _gate_axis(east_west, side)
	var thin: float = tile_size * 0.16
	var thick: float = tile_size * 0.24
	var size := Vector3(thin, height, thick) if east_west else Vector3(thick, height, thin)
	return Transform3D(
		Basis.IDENTITY.scaled(size),
		top + away * tile_size * 0.38 + Vector3(0.0, height / 2.0, 0.0))


## Part du plafond prise par les montants d'une porte ; le linteau a le reste.
const GATE_PIER_RISE: float = 0.78


## Linteau : la traverse posée sur les montants — deux demi-poutres, une par côté.
##
## Une seule poutre d'un montant à l'autre passerait au-dessus du centre de la
## case, or une porte se franchit : c'est la seule règle du module qu'un décor
## de case praticable ne peut pas enfreindre. Les deux demi-poutres se rejoignent
## donc à un jeu près — quelques centièmes de case, que la caméra tactique ne
## sépare pas, et le centre reste libre pour le pion qui s'y tient.
##
## [param east_west] le rempart court-il d'est en ouest ? [param side] 0 ou 1.
static func _gate_lintel(top: Vector3, tile_size: float, east_west: bool,
		side: int) -> Transform3D:
	var pier_h: float = MAX_HEIGHT * GATE_PIER_RISE
	var height: float = MAX_HEIGHT * (1.0 - GATE_PIER_RISE)
	var away: Vector3 = _gate_axis(east_west, side)
	var size: Vector3 = _along(tile_size * 0.60, height, tile_size * 0.30, east_west)
	return Transform3D(
		Basis.IDENTITY.scaled(size),
		top + away * tile_size * 0.33 + Vector3(0.0, pier_h + height / 2.0, 0.0))


## De quel côté de la case se pose la moitié [param side] d'une porte.
static func _gate_axis(east_west: bool, side: int) -> Vector3:
	var sign_side: float = 1.0 if side == 0 else -1.0
	return Vector3(sign_side, 0.0, 0.0) if east_west else Vector3(0.0, 0.0, sign_side)


## Ce qu'il reste d'un édifice : la case tire une de ces trois scènes.
enum Ruin {
	COLONNADE, ## Deux colonnes brisées sur leur socle, de hauteurs inégales.
	FALLEN, ## Une colonne debout, et le fût de sa voisine couché à côté.
	WALL, ## Un pan de mur écroulé, en trois assises de moins en moins hautes.
}

## Quelle ruine porte cette case.
static func _ruin_of(cell: Vector2i) -> Ruin:
	var draw: float = _noise(cell, 71)
	if draw < 0.38:
		return Ruin.COLONNADE
	if draw < 0.72:
		return Ruin.FALLEN
	return Ruin.WALL


## Jonche une case de ruines : colonnes, fûts couchés, pans de mur et blocs.
##
## Deux fûts identiques et un caillou tenaient lieu de ruine ; on y lisait deux
## bornes plutôt qu'un édifice écroulé. Ce qui fait une ruine, c'est le
## **désordre réglé** : ce qui tient encore debout, ce qui est tombé à côté, et
## ce qui s'est cassé en morceaux.
static func _strew_ruins(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	match _ruin_of(cell):
		Ruin.FALLEN:
			_raise_column(out, top, cell, tile_size, 0)
			_lay_shaft(out, top, cell, tile_size, 1)
		Ruin.WALL:
			_break_wall(out, top, cell, tile_size)
		_:
			_raise_column(out, top, cell, tile_size, 0)
			_raise_column(out, top, cell, tile_size, 1)

	_append(out, "rubble", _rubble(top, cell, tile_size, 2))
	if _noise(cell, 83) < 0.55:
		_append(out, "rubble", _rubble(top, cell, tile_size, 3))


## Colonne brisée : un fût arrêté net, sur le socle qui l'a portée.
##
## Le socle fait plus que garnir : c'est lui qui pose la colonne sur le sol au
## lieu de l'y planter, et son débord donne l'ombre qui dit la pierre taillée.
static func _raise_column(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float, index: int) -> void:
	var salt: int = 70 + index * 5
	var seat: Vector3 = top + _corner(cell, tile_size, index)
	var width: float = tile_size * (0.12 + _noise(cell, salt + 1) * 0.04)
	var plinth_h: float = MAX_HEIGHT * 0.05
	var height: float = MAX_HEIGHT * (0.26 + _noise(cell, salt) * 0.32)

	_append(out, "plinth", Transform3D(
		Basis(Vector3.UP, _noise(cell, salt + 2) * TAU)
			.scaled(Vector3(width * 1.7, plinth_h, width * 1.7)),
		seat + Vector3(0.0, plinth_h / 2.0, 0.0)))
	_append(out, "column", Transform3D(
		Basis(Vector3.UP, _noise(cell, salt + 3) * TAU).scaled(Vector3(width, height, width)),
		seat + Vector3(0.0, plinth_h + height / 2.0, 0.0)))


## Fût couché : la colonne d'à côté, tombée le long du bord de la case.
##
## Couchée **en travers du rayon**, jamais vers le centre : un fût qui roule sur
## la case bloquerait la seule chose que ce module promet de ne pas boucher.
static func _lay_shaft(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float, index: int) -> void:
	var seat: Vector3 = top + _corner(cell, tile_size, index)
	var angle: float = _corner_angle(cell, index) + PI / 2.0 \
		+ (_noise(cell, 76) - 0.5) * 0.5
	var lie: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var girth: float = tile_size * (0.11 + _noise(cell, 77) * 0.03)
	var length: float = tile_size * (0.28 + _noise(cell, 78) * 0.14)
	_append(out, "shaft", Transform3D(
		_aim(lie).scaled(Vector3(girth, length, girth)),
		seat + Vector3(0.0, girth / 2.0, 0.0)))


## Les trois assises d'un pan de mur écroulé. `[écart, hauteur, longueur]`, en
## fractions de case sauf la hauteur, en fraction du plafond.
const RUIN_COURSES: Array = [
	[-0.17, 0.34, 0.18],
	[0.00, 0.24, 0.16],
	[0.16, 0.13, 0.15],
]


## Pan de mur : trois assises alignées le long du bord, en marche d'escalier.
##
## Les hauteurs décroissent d'un bout à l'autre — c'est ce dégradé qui fait lire
## un mur *tombé*, là où trois blocs de même hauteur feraient une murette neuve.
static func _break_wall(out: Dictionary, top: Vector3, cell: Vector2i,
		tile_size: float) -> void:
	var seat: Vector3 = top + _corner(cell, tile_size)
	var angle: float = _corner_angle(cell) + PI / 2.0
	var run: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var thickness: float = tile_size * (0.11 + _noise(cell, 79) * 0.03)

	for i: int in RUIN_COURSES.size():
		var course: Array = RUIN_COURSES[i]
		var height: float = MAX_HEIGHT * float(course[1]) * (0.85 + _noise(cell, 84 + i) * 0.3)
		_append(out, "ruin_wall", Transform3D(
			Basis(Vector3.UP, -angle).scaled(
				Vector3(tile_size * float(course[2]), height, thickness)),
			seat + run * tile_size * float(course[0]) + Vector3(0.0, height / 2.0, 0.0)))


## Pierre effondrée : le bloc qui manque aux colonnes, couché de travers.
static func _rubble(top: Vector3, cell: Vector2i, tile_size: float,
		quarters: int) -> Transform3D:
	var salt: int = 80 + quarters * 4
	var bulk: float = 0.75 + _noise(cell, salt) * 0.5
	var height: float = MAX_HEIGHT * 0.14 * bulk
	var width: float = tile_size * 0.18 * bulk
	var tilt := Basis.from_euler(Vector3(
		(_noise(cell, salt + 1) - 0.5) * 0.5,
		_noise(cell, salt + 2) * TAU,
		(_noise(cell, salt + 3) - 0.5) * 0.5))
	return Transform3D(
		tilt.scaled(Vector3(width, height, width * (0.55 + _noise(cell, salt + 4) * 0.4))),
		top + _corner(cell, tile_size, quarters) * 0.85 + Vector3(0.0, height / 2.0, 0.0))


## Une tour de guet en quatre assises, et le plafond partagé entre elles.
##
## Deux boîtes empilées donnaient un champignon gris : rien n'y disait la
## pierre. Une tour se reconnaît à un **profil**, pas à un volume — un pied
## évasé, un fût étroit, une couronne dentelée, une flèche. Les quatre parts
## ci-dessous se répartissent [constant MAX_HEIGHT] sans le dépasser (leur
## somme fait exactement 1), et c'est le rétrécissement du pied au fût qui
## fait paraître la tour plus haute qu'elle n'a le droit de l'être.
const TOWER_BASE_RISE: float = 0.09
const TOWER_SHAFT_RISE: float = 0.42
const TOWER_MERLON_RISE: float = 0.13
const TOWER_ROOF_RISE: float = 0.36


## Assise d'une tour : un socle octogonal évasé, bas et large.
static func _tower_base(top: Vector3, tile_size: float) -> Transform3D:
	var height: float = MAX_HEIGHT * TOWER_BASE_RISE
	var width: float = tile_size * 0.70
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(width, height, width)),
		top + Vector3(0.0, height / 2.0, 0.0))


## Fût d'une tour de guet : un tambour octogonal, nettement plus étroit que
## l'assise qui le porte — c'est ce ressaut qui fait la tour.
static func _tower_shaft(top: Vector3, tile_size: float) -> Transform3D:
	var base_h: float = MAX_HEIGHT * TOWER_BASE_RISE
	var height: float = MAX_HEIGHT * TOWER_SHAFT_RISE
	var width: float = tile_size * 0.48
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(width, height, width)),
		top + Vector3(0.0, base_h + height / 2.0, 0.0))


## Merlon de couronnement : un des blocs en encorbellement au sommet du fût.
##
## Posé un peu **hors** du fût, et plus loin du centre que le débord du toit :
## sans cela l'avant-toit les couvrirait tous les quatre et la couronne ne se
## verrait pas. C'est la dentelure qui distingue une tour de guet d'un clocher.
##
## [param index] 0 à 3, un par diagonale.
static func _tower_merlon(top: Vector3, tile_size: float, index: int) -> Transform3D:
	var shaft_top: float = MAX_HEIGHT * (TOWER_BASE_RISE + TOWER_SHAFT_RISE)
	var height: float = MAX_HEIGHT * TOWER_MERLON_RISE
	var block: float = tile_size * 0.13
	var angle: float = (float(index) + 0.5) * (TAU / float(TOWER_MERLONS))
	var away: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * tile_size * 0.27
	return Transform3D(
		Basis(Vector3.UP, -angle).scaled(Vector3(block, height, block)),
		top + away + Vector3(0.0, shaft_top + height / 2.0, 0.0))


## Flèche d'ardoise : un cône à huit pans posé sur la couronne, avec débord.
##
## C'est elle qu'on reconnaît de loin — et elle part du haut des merlons, pas
## du haut du fût : un toit qui naîtrait sous la couronne l'avalerait.
static func _tower_roof(top: Vector3, tile_size: float) -> Transform3D:
	var crown_top: float = MAX_HEIGHT * (
		TOWER_BASE_RISE + TOWER_SHAFT_RISE + TOWER_MERLON_RISE)
	var height: float = MAX_HEIGHT * TOWER_ROOF_RISE
	var width: float = tile_size * 0.58
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(width, height, width)),
		top + Vector3(0.0, crown_top + height / 2.0, 0.0))


## Platelage d'un pont : une dalle de bois sur toute la case, assez basse pour
## qu'on la foule ([constant FLAT_HEIGHT]).
static func _bridge_deck(top: Vector3, tile_size: float) -> Transform3D:
	var height: float = FLAT_HEIGHT * 0.5
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(tile_size * 0.94, height, tile_size * 0.94)),
		top + Vector3(0.0, height / 2.0, 0.0))


## Garde-corps : deux lisses le long de la travée, à hauteur de genou.
##
## [param east_west] le pont court-il d'est en ouest ? [param side] 0 ou 1.
static func _bridge_railing(top: Vector3, tile_size: float, east_west: bool,
		side: int) -> Transform3D:
	var height: float = MAX_HEIGHT * 0.22
	var sign_side: float = 1.0 if side == 0 else -1.0
	var away: Vector3 = Vector3(0.0, 0.0, sign_side) if east_west else Vector3(sign_side, 0.0, 0.0)
	var long: float = tile_size * 0.94
	var thin: float = tile_size * 0.07
	var size := Vector3(long, height, thin) if east_west else Vector3(thin, height, long)
	return Transform3D(
		Basis.IDENTITY.scaled(size),
		top + away * tile_size * 0.44 + Vector3(0.0, height / 2.0 + FLAT_HEIGHT * 0.5, 0.0))


## L'ouvrage court-il d'est en ouest ?
##
## Lu sur les voisines de la case : un pont suit ses planches, une porte suit son
## rempart. Sans voisine parlante, on tranche pour l'est-ouest — il faut bien une
## orientation, et une case isolée ne dément personne.
static func _runs_east_west(cell: Vector2i, terrain_by_cell: Dictionary,
		kinds: Array[int]) -> bool:
	var horizontal: int = 0
	var vertical: int = 0
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT]:
		if kinds.has(int(terrain_by_cell.get(cell + step, -1))):
			horizontal += 1
	for step: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
		if kinds.has(int(terrain_by_cell.get(cell + step, -1))):
			vertical += 1
	return horizontal >= vertical


#endregion


## Décalage du centre de la case vers un de ses quatre coins.
##
## [param quarters] fait tourner d'autant de quarts de tour : c'est ce qui écarte
## les unes des autres les pièces d'un même décor — deux colonnes et leur bloc
## effondré ne se posent pas dans le même coin.
static func _corner(cell: Vector2i, tile_size: float, quarters: int = 0) -> Vector3:
	return _corner_dir(cell, quarters) * tile_size * CORNER_OFFSET


## Direction du centre de la case vers le coin où se pose son décor.
##
## C'est le « dehors » d'une case : un arbre pousse ses branches de ce côté, une
## maison y tourne sa porte, et aucune frondaison ne s'écarte dans l'autre sens.
static func _corner_dir(cell: Vector2i, quarters: int = 0) -> Vector3:
	var angle: float = _corner_angle(cell, quarters)
	return Vector3(cos(angle), 0.0, sin(angle))


## Angle du coin où se pose le décor d'une case, en radians dans le plan `xz`.
static func _corner_angle(cell: Vector2i, quarters: int = 0) -> float:
	return (floor(_noise(cell, 3) * 4.0) + float(quarters)) * (TAU / 4.0) + (TAU / 8.0)


## Repère d'un membre couché ou penché : son axe `y` suit [param dir].
##
## Les maillages de révolution du module montent tous selon `y` — une branche,
## un fût de colonne tombé ne sont que ces mêmes maillages visés ailleurs.
static func _aim(dir: Vector3) -> Basis:
	var axis: Vector3 = Vector3.UP.cross(dir)
	if axis.length() < 0.0001:
		return Basis.IDENTITY
	return Basis(axis.normalized(), Vector3.UP.angle_to(dir))


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
##
## **Tous** les maillages du module tiennent dans le cube unité : rayon 1/2,
## hauteur 1. L'échelle de l'instance donne donc directement largeur et hauteur,
## et un test peut juger l'encombrement d'un décor sur sa seule transformation,
## sans ouvrir le maillage. Tronc et frondaison cuisaient jadis leur rayon dans
## le maillage, et le test devait connaître le chiffre par cœur.
static func _mesh_for(kind: String, _tile_size: float) -> Mesh:
	match kind:
		"trunk":
			# Évasé du pied : c'est le fruit de l'arbre, ce qui l'enracine au lieu
			# de le poser. Le même maillage sert aux branches, visées ailleurs.
			return _cone(6, 0.33)
		"canopy":
			# Une masse de feuilles n'a pas d'arête : c'est le seul décor du module
			# où le lissage des normales d'une sphère est ce qu'on cherche.
			return _blob(7, 4)
		"pine":
			return _cone(7, 0.02)
		"rock_pic":
			return _cone(5, 0.06)
		"keep", "tower_shaft", "tower_base":
			return _drum(8)
		"column", "shaft":
			return _drum(8)
		"pole":
			return _drum(5)
		"tuft":
			return _cone(3, 0.12)
		"tower_roof":
			return _cone(8, 0.0)
		"house_roof", "house_hip":
			# Un toit à deux pans plutôt qu'un cône : le faîtage est ce qui fait
			# lire « maison » plutôt que « tente » sur une case de 30 pixels.
			var roof := PrismMesh.new()
			roof.size = Vector3.ONE
			return roof
		_:
			# Blocs, dalles, créneaux, murs, piliers, linteaux, socles, cheminées,
			# portes, platelage : un cube unitaire, mis aux dimensions voulues par
			# l'échelle de chaque instance. Les arêtes vives font tout le travail.
			var block := BoxMesh.new()
			block.size = Vector3.ONE
			return block


## Tambour unitaire : rayon 1/2, hauteur 1, autant de pans que demandé.
static func _drum(segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


## Cône unitaire : base de rayon 1/2, sommet plus ou moins épointé.
static func _cone(segments: int, top_radius: float) -> CylinderMesh:
	var mesh := _drum(segments)
	mesh.top_radius = top_radius
	return mesh


## Masse arrondie unitaire : une sphère de rayon 1/2, à aplatir par l'instance.
static func _blob(segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


## Teinte et réponse à la lumière de chaque type de décor.
##
## L'or d'une bannière et l'ardoise d'un toit sont les seuls à ne pas être mats :
## c'est ce reflet qui les fait ressortir d'un plateau entièrement rugueux.
const SURFACES: Dictionary = {
	"trunk": {"color": TRUNK_COLOR, "roughness": 0.95, "metallic": 0.0},
	"canopy": {"color": CANOPY_COLOR, "roughness": 0.90, "metallic": 0.0},
	"pine": {"color": PINE_COLOR, "roughness": 0.92, "metallic": 0.0},
	"rock": {"color": ROCK_COLOR, "roughness": 1.00, "metallic": 0.0},
	"rock_pic": {"color": ROCK_DARK_COLOR, "roughness": 1.00, "metallic": 0.0},
	"rock_slab": {"color": ROCK_PALE_COLOR, "roughness": 1.00, "metallic": 0.0},
	"wall_base": {"color": DARK_STONE_COLOR, "roughness": 0.95, "metallic": 0.0},
	"wall_body": {"color": WALL_COLOR, "roughness": 0.85, "metallic": 0.0},
	"wall_crenel": {"color": CUT_STONE_COLOR, "roughness": 0.85, "metallic": 0.0},
	"tuft": {"color": TUFT_COLOR, "roughness": 0.95, "metallic": 0.0},
	"pebble": {"color": PEBBLE_COLOR, "roughness": 1.00, "metallic": 0.0},
	"reed": {"color": REED_COLOR, "roughness": 0.90, "metallic": 0.0},
	"house_wall": {"color": PLASTER_COLOR, "roughness": 0.92, "metallic": 0.0},
	"house_roof": {"color": ROOF_COLOR, "roughness": 0.85, "metallic": 0.0},
	"house_hip": {"color": SLATE_COLOR, "roughness": 0.70, "metallic": 0.0},
	"chimney": {"color": DARK_STONE_COLOR, "roughness": 0.95, "metallic": 0.0},
	"door": {"color": WOOD_COLOR, "roughness": 0.90, "metallic": 0.0},
	"keep": {"color": STONE_COLOR, "roughness": 0.92, "metallic": 0.0},
	"tower_shaft": {"color": STONE_COLOR, "roughness": 0.92, "metallic": 0.0},
	"tower_base": {"color": DARK_STONE_COLOR, "roughness": 0.95, "metallic": 0.0},
	"tower_merlon": {"color": CUT_STONE_COLOR, "roughness": 0.88, "metallic": 0.0},
	"rubble": {"color": STONE_COLOR, "roughness": 1.00, "metallic": 0.0},
	"pier": {"color": DARK_STONE_COLOR, "roughness": 0.90, "metallic": 0.0},
	"lintel": {"color": CUT_STONE_COLOR, "roughness": 0.90, "metallic": 0.0},
	"column": {"color": CUT_STONE_COLOR, "roughness": 0.88, "metallic": 0.0},
	"plinth": {"color": DARK_STONE_COLOR, "roughness": 0.95, "metallic": 0.0},
	"shaft": {"color": CUT_STONE_COLOR, "roughness": 0.92, "metallic": 0.0},
	"ruin_wall": {"color": DARK_STONE_COLOR, "roughness": 0.95, "metallic": 0.0},
	"tower_roof": {"color": SLATE_COLOR, "roughness": 0.55, "metallic": 0.05},
	"banner": {"color": BANNER_COLOR, "roughness": 0.40, "metallic": 0.25},
	"pole": {"color": TRUNK_COLOR, "roughness": 0.95, "metallic": 0.0},
	"deck": {"color": WOOD_COLOR, "roughness": 0.90, "metallic": 0.0},
	"railing": {"color": WOOD_COLOR, "roughness": 0.90, "metallic": 0.0},
}


## Matériau d'un type de décor : sans transparence, comme le terrain.
static func _material_for(kind: String) -> StandardMaterial3D:
	var surface: Dictionary = SURFACES.get(kind, SURFACES["wall_body"])
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(str(surface["color"]))
	mat.roughness = float(surface["roughness"])
	mat.metallic = float(surface["metallic"])
	return mat
#endregion
