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
##   et sur les cases où l'on peut se tenir — forêt, village, fortin, ruines — il
##   est décalé vers un coin, centre dégagé. Montagne, mur et tour étant
##   infranchissables, leur décor peut occuper toute la case sans masquer personne.
##   Seul ce qui est plus bas que [constant FLAT_HEIGHT] a le droit de couvrir le
##   centre : on marche dessus, comme sur le platelage d'un pont.
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
## C'est ce décalage qui laisse le centre dégagé, donc le pion lisible. Il ne
## vaut que pour la **forêt** : c'est le seul de ces trois terrains où une unité
## peut se tenir — montagne et mur sont infranchissables, leur décor a donc le
## droit d'occuper toute la case.
##
## Tenu par un test : 0,30 de case d'écart contre 0,22 de rayon de frondaison
## au plus, le centre reste hors du feuillage. Élargir l'un sans resserrer
## l'autre casserait la promesse.
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
const ROCK_COLOR: String = "#9d8a72"
const WALL_COLOR: String = "#6b6b6b"


## Ce qui se bâtit. L'ardoise et l'or des toits et des bannières viennent de la
## charte « Velmar : nuit et or » — un plateau et des menus de la même famille.
const STONE_COLOR: String = "#8a867e"


const DARK_STONE_COLOR: String = "#6d6a64"


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
				_append(out, "trunk", _tree_trunk(top, cell, tile_size))
				_append(out, "canopy", _tree_canopy(top, cell, tile_size))
			MapDataClass.TerrainType.MOUNTAIN:
				for i: int in 2:
					_append(out, "rock", _rock(top, cell, tile_size, i))
			MapDataClass.TerrainType.WALL:
				_append(out, "merlon", _merlon(top, tile_size))
			MapDataClass.TerrainType.SAND:
				if _noise(cell, 31) < 0.28:
					_append(out, "pebble", _pebble(top, cell, tile_size))
			MapDataClass.TerrainType.SWAMP:
				for i: int in 3:
					_append(out, "reed", _reed(top, cell, tile_size, i))
			MapDataClass.TerrainType.VILLAGE:
				_append(out, "house_wall", _house_wall(top, cell, tile_size))
				_append(out, "house_roof", _house_roof(top, cell, tile_size))
			MapDataClass.TerrainType.FORT:
				_append(out, "keep", _keep(top, cell, tile_size))
				if _has_banner(cell):
					_append(out, "pole", _banner_pole(top, cell, tile_size))
					_append(out, "banner", _banner(top, cell, tile_size))
			MapDataClass.TerrainType.GATE:
				var gate_ew: bool = _runs_east_west(cell, terrain_by_cell, RAMPART_KINDS)
				for side: int in 2:
					_append(out, "pier", _gate_pier(top, tile_size, gate_ew, side))
			MapDataClass.TerrainType.RUINS:
				for i: int in 2:
					_append(out, "column", _broken_column(top, cell, tile_size, i))
				_append(out, "rubble", _rubble(top, cell, tile_size))
			MapDataClass.TerrainType.TOWER:
				_append(out, "tower_shaft", _tower_shaft(top, tile_size))
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


#region Formes
## Tronc d'arbre : un cylindre court, planté hors du centre de la case.
static func _tree_trunk(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var height: float = MAX_HEIGHT * 0.32 * _tree_rise(cell)
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(_tree_girth(cell), height, _tree_girth(cell))),
		top + _corner(cell, tile_size) + Vector3(0.0, height / 2.0, 0.0))


## Frondaison : un cône posé sur le tronc, tourné d'une case à l'autre.
static func _tree_canopy(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var trunk_h: float = MAX_HEIGHT * 0.32 * _tree_rise(cell)
	var height: float = MAX_HEIGHT * 0.68 * _tree_rise(cell)
	var basis: Basis = Basis(Vector3.UP, _noise(cell, 2) * TAU)
	return Transform3D(
		basis.scaled(Vector3(_tree_girth(cell), height, _tree_girth(cell))),
		top + _corner(cell, tile_size) + Vector3(0.0, trunk_h + height / 2.0, 0.0))


## Carrure d'un arbre — sa largeur, qui a le droit de varier franchement.
static func _tree_girth(cell: Vector2i) -> float:
	return 0.8 + _noise(cell, 1) * 0.4


## Élancement d'un arbre : sa part du plafond, jamais davantage.
##
## Un seul facteur servait aux deux, et il montait à 1,2 : un arbre sur quatre
## dépassait [constant MAX_HEIGHT] d'un cinquième. Le test ne l'avait pas vu — il
## ne dessinait qu'une case de forêt, et le hachage de celle-là tombait juste.
static func _tree_rise(cell: Vector2i) -> float:
	return 0.78 + _noise(cell, 1) * 0.22


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
## Corps d'une maison : un bloc de torchis, planté dans un coin de la case.
static func _house_wall(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var height: float = MAX_HEIGHT * 0.42
	return Transform3D(
		_house_basis(cell).scaled(Vector3(_house_width(cell, tile_size),
			height, _house_depth(cell, tile_size))),
		top + _corner(cell, tile_size) + Vector3(0.0, height / 2.0, 0.0))


## Toit à quatre pans, débordant un peu sur les murs qu'il couvre.
static func _house_roof(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var wall_h: float = MAX_HEIGHT * 0.42
	var height: float = MAX_HEIGHT * 0.34
	return Transform3D(
		_house_basis(cell).scaled(Vector3(_house_width(cell, tile_size) * 1.2,
			height, _house_depth(cell, tile_size) * 1.2)),
		top + _corner(cell, tile_size) + Vector3(0.0, wall_h + height / 2.0, 0.0))


## Une maison n'est jamais de biais : elle s'aligne sur un quart de tour.
static func _house_basis(cell: Vector2i) -> Basis:
	return Basis(Vector3.UP, floor(_noise(cell, 22) * 4.0) * (TAU / 4.0))


static func _house_width(cell: Vector2i, tile_size: float) -> float:
	return tile_size * 0.25 * (0.85 + _noise(cell, 20) * 0.3)


static func _house_depth(cell: Vector2i, tile_size: float) -> float:
	return _house_width(cell, tile_size) * (0.8 + _noise(cell, 21) * 0.4)


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
	var height: float = MAX_HEIGHT * 0.9
	var sign_side: float = 1.0 if side == 0 else -1.0
	var away: Vector3 = Vector3(sign_side, 0.0, 0.0) if east_west else Vector3(0.0, 0.0, sign_side)
	var thin: float = tile_size * 0.16
	var thick: float = tile_size * 0.24
	var size := Vector3(thin, height, thick) if east_west else Vector3(thick, height, thin)
	return Transform3D(
		Basis.IDENTITY.scaled(size),
		top + away * tile_size * 0.38 + Vector3(0.0, height / 2.0, 0.0))


## Colonne brisée : un fût court, arrêté net — deux par case de ruines.
static func _broken_column(top: Vector3, cell: Vector2i, tile_size: float,
		index: int) -> Transform3D:
	var salt: int = 70 + index
	var height: float = MAX_HEIGHT * (0.22 + _noise(cell, salt) * 0.28)
	var width: float = tile_size * 0.15
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(width, height, width)),
		top + _corner(cell, tile_size, index) + Vector3(0.0, height / 2.0, 0.0))


## Pierre effondrée : le bloc qui manque aux colonnes, couché de travers.
static func _rubble(top: Vector3, cell: Vector2i, tile_size: float) -> Transform3D:
	var height: float = MAX_HEIGHT * 0.16
	var width: float = tile_size * 0.20
	var tilt := Basis.from_euler(Vector3(
		(_noise(cell, 80) - 0.5) * 0.4, _noise(cell, 81) * TAU, (_noise(cell, 82) - 0.5) * 0.4))
	return Transform3D(
		tilt.scaled(Vector3(width, height, width * 0.65)),
		top + _corner(cell, tile_size, 2) * 0.85 + Vector3(0.0, height / 2.0, 0.0))


## Fût d'une tour de guet : plein cadre, la case est infranchissable.
static func _tower_shaft(top: Vector3, tile_size: float) -> Transform3D:
	var height: float = MAX_HEIGHT * 0.62
	var width: float = tile_size * 0.62
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(width, height, width)),
		top + Vector3(0.0, height / 2.0, 0.0))


## Toit conique d'ardoise : c'est lui qui fait reconnaître une tour de loin.
static func _tower_roof(top: Vector3, tile_size: float) -> Transform3D:
	var shaft_h: float = MAX_HEIGHT * 0.62
	var height: float = MAX_HEIGHT * 0.38
	var width: float = tile_size * 0.78
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3(width, height, width)),
		top + Vector3(0.0, shaft_h + height / 2.0, 0.0))


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
	var angle: float = (floor(_noise(cell, 3) * 4.0) + float(quarters)) * (TAU / 4.0) \
		+ (TAU / 8.0)
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
##
## Les solides de révolution ajoutés depuis les arbres suivent une convention
## simple : rayon 1/2 et hauteur 1, donc l'échelle de l'instance donne
## directement largeur et hauteur. Tronc et frondaison, plus anciens, cuisent
## leur rayon dans le maillage — les toucher casserait un bois déjà réglé.
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
		"keep", "tower_shaft":
			return _drum(8)
		"column":
			return _drum(6)
		"pole":
			return _drum(5)
		"tuft":
			return _cone(3, 0.12)
		"tower_roof":
			return _cone(8, 0.0)
		"house_roof":
			# Un toit à deux pans plutôt qu'un cône : le faîtage est ce qui fait
			# lire « maison » plutôt que « tente » sur une case de 30 pixels.
			var roof := PrismMesh.new()
			roof.size = Vector3.ONE
			return roof
		_:
			# Rocher, créneau, murs, piliers, platelage : un cube unitaire, mis aux
			# dimensions voulues par l'échelle de chaque instance. Les arêtes vives
			# font tout le travail.
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


## Teinte et réponse à la lumière de chaque type de décor.
##
## L'or d'une bannière et l'ardoise d'un toit sont les seuls à ne pas être mats :
## c'est ce reflet qui les fait ressortir d'un plateau entièrement rugueux.
const SURFACES: Dictionary = {
	"trunk": {"color": TRUNK_COLOR, "roughness": 0.95, "metallic": 0.0},
	"canopy": {"color": CANOPY_COLOR, "roughness": 0.90, "metallic": 0.0},
	"rock": {"color": ROCK_COLOR, "roughness": 1.00, "metallic": 0.0},
	"merlon": {"color": WALL_COLOR, "roughness": 0.85, "metallic": 0.0},
	"tuft": {"color": TUFT_COLOR, "roughness": 0.95, "metallic": 0.0},
	"pebble": {"color": PEBBLE_COLOR, "roughness": 1.00, "metallic": 0.0},
	"reed": {"color": REED_COLOR, "roughness": 0.90, "metallic": 0.0},
	"house_wall": {"color": PLASTER_COLOR, "roughness": 0.92, "metallic": 0.0},
	"house_roof": {"color": ROOF_COLOR, "roughness": 0.85, "metallic": 0.0},
	"keep": {"color": STONE_COLOR, "roughness": 0.92, "metallic": 0.0},
	"tower_shaft": {"color": STONE_COLOR, "roughness": 0.92, "metallic": 0.0},
	"rubble": {"color": STONE_COLOR, "roughness": 1.00, "metallic": 0.0},
	"pier": {"color": DARK_STONE_COLOR, "roughness": 0.90, "metallic": 0.0},
	"column": {"color": DARK_STONE_COLOR, "roughness": 0.90, "metallic": 0.0},
	"tower_roof": {"color": SLATE_COLOR, "roughness": 0.55, "metallic": 0.05},
	"banner": {"color": BANNER_COLOR, "roughness": 0.40, "metallic": 0.25},
	"pole": {"color": TRUNK_COLOR, "roughness": 0.95, "metallic": 0.0},
	"deck": {"color": WOOD_COLOR, "roughness": 0.90, "metallic": 0.0},
	"railing": {"color": WOOD_COLOR, "roughness": 0.90, "metallic": 0.0},
}


## Matériau d'un type de décor : sans transparence, comme le terrain.
static func _material_for(kind: String) -> StandardMaterial3D:
	var surface: Dictionary = SURFACES.get(kind, SURFACES["merlon"])
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(str(surface["color"]))
	mat.roughness = float(surface["roughness"])
	mat.metallic = float(surface["metallic"])
	return mat
#endregion
