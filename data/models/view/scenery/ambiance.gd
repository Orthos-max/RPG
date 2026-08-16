class_name TacticsAmbiance
extends RefCounted
## Ce qui flotte au-dessus des cases : feuilles, flocons, fumée, poussière.
##
## [TacticsProps] pose ce qui **fait** un terrain, [TacticsDecor] sème la menue
## monnaie qui traîne dessus. Les deux sont immobiles. Une carte tenue à l'arrêt
## — et une carte de jeu tactique passe l'essentiel de son temps à l'arrêt, en
## attendant que le joueur se décide — ne bougeait donc nulle part sauf sur
## l'eau, seul terrain animé du plateau.
##
## Ce module fait respirer le reste : des feuilles qui tombent en tournoyant
## sous un bois, un flocon sur la neige, un panache gris au-dessus d'un hameau,
## la poussière qui souffle bas sur le sable. Rien qui se lise, rien qui se
## joue — de l'air, au sens propre.
##
## ## Les trois règles
##
## - **Un émetteur par îlot, jamais par case.** Les cases voisines d'un même
##   terrain sont regroupées en îlots contigus ([method islands]), et l'îlot
##   entier reçoit un seul [CPUParticles3D] qui sème sur toute son emprise. Un
##   bois de trente cases coûte donc autant qu'un bois d'une seule, et
##   [constant MAX_EMITTERS] plafonne le tout — les plus gros îlots d'abord,
##   ceux qu'on regarde.
## - **C'est du poivre, pas un blizzard.** Le débit tient entre
##   [constant MIN_RATE] et [constant MAX_RATE] particules par seconde et par
##   émetteur, quelle que soit la taille de l'îlot : une carte entièrement
##   enneigée ne doit pas cacher les pions qu'on y déplace. Les tailles vont de
##   0,03 à 0,08 unité — un pion en fait presque une.
## - **Rien de tout cela ne se joue.** Aucune collision, aucun coût, aucun
##   bonus : le module ne lit que le terrain et l'altitude des cases, et ne rend
##   que des nœuds de rendu. Une carte sans ambiance se joue exactement pareil.
##
## Bataille et éditeur passent par [method build] avec la même description de
## cases que [TacticsDecor] — dessiner une forêt dans l'éditeur et n'y voir
## tomber aucune feuille avant d'avoir lancé la partie serait un drôle d'éditeur.

const MapDataClass = preload("res://data/models/world/map/map_data.gd")
const GridRef = preload("res://data/models/world/utilities/grid.gd")

## Nom du nœud qui accueille tous les émetteurs, sous l'arène.
const HOST_NAME: StringName = &"Ambiance"

## Plafond d'émetteurs sur une carte.
##
## Une grande carte mêlant bois, neige et rivières propose une quarantaine
## d'îlots ; en garder vingt suffit à ce qu'aucune région regardée ne soit
## morte, et tient le budget de particules sous le millier — de quoi laisser
## respirer les machines modestes que le jeu vise.
const MAX_EMITTERS: int = 20

## Points de naissance au plus par émetteur.
##
## Les particules naissent sur une liste de points ([constant
## CPUParticles3D.EMISSION_SHAPE_POINTS]) plutôt que dans une boîte : un îlot
## n'est pas un rectangle, et une brume qui déborde sur la plaine voisine
## trahit tout de suite le procédé. Au-delà de ce compte, les cases de l'îlot
## sont échantillonnées à pas régulier — un grand bois sème un peu partout,
## pas partout exactement.
const MAX_POINTS: int = 48

## Points de naissance tirés par case, tant que le plafond le permet.
##
## Un seul point par case ferait naître les feuilles en quinconce, sur la grille
## — visible dès qu'on y prête attention.
const POINTS_PER_CELL: int = 3

## Débit minimal et maximal d'un émetteur, en particules par seconde.
##
## Le débit croît avec la taille de l'îlot puis bute sur le plafond : c'est ce
## qui empêche une carte de neige d'être une carte de neige **et** un rideau.
const MIN_RATE: float = 2.0
const MAX_RATE: float = 8.0

## Part de hasard sur la durée de vie d'une particule.
##
## Sans elle, toutes les feuilles d'une même volée disparaissent ensemble, et
## l'œil attrape le cycle de l'émetteur.
const LIFETIME_JITTER: float = 0.4

## Amplitude de la variation de taille : de 0,8 à 1,2 fois la taille nominale.
const SIZE_JITTER: float = 0.4

## Ce que chaque terrain met dans son air.
##
## Ce qui n'est pas listé ne reçoit rien, et c'est un choix : le chemin, le mur,
## la porte, le pont, le marais restent immobiles. Le calme est aussi une
## ambiance, et quinze terrains qui bougent tous n'en font plus aucun.
##
## Les clés, une fois pour toutes :
##
## - `color` — teinte **et** opacité de la particule. C'est l'alpha qui décide
##   de la discrétion : au-delà de ~0,7 une feuille devient un objet.
## - `colors` — deux teintes entre lesquelles chaque particule tire la sienne
##   (facultatif) : le vert et le roux d'un même sous-bois.
## - `rate` — particules par seconde et **par case** de l'îlot, avant le
##   plafonnement entre [constant MIN_RATE] et [constant MAX_RATE].
## - `lifetime` — durée de vie en secondes ; avec `rate`, elle fixe le nombre de
##   particules vivantes à la fois.
## - `gravity` — négative pour ce qui tombe, positive pour ce qui monte, nulle
##   pour ce qui flotte.
## - `direction` / `spread` / `speed` — l'élan de départ : vers le bas pour une
##   feuille, vers le haut pour un reflet, presque à plat pour la poussière du
##   désert.
## - `size` — côté de la particule en unités monde (une case en fait 1).
## - `grow` — taille au début et à la fin de la vie, en facteur : la fumée
##   s'élargit en montant, un reflet s'éteint en rétrécissant.
## - `spin` — vitesse de rotation en degrés par seconde ; c'est le tournoiement
##   d'une feuille, et rien d'autre n'en a besoin.
## - `rise` / `band` — hauteur de naissance au-dessus du sol de la case, et
##   épaisseur de la tranche où elle se tire au hasard. Une feuille naît dans la
##   frondaison, un reflet à la surface de l'eau, une fumée sur le toit.
## - `damping` — freinage ; ce qui souffle s'essouffle, ce qui tombe non.
## - `additive` — mélange par addition plutôt que par transparence (facultatif).
##   Réservé aux reflets de l'eau : c'est ce qui fait scintiller au lieu de
##   déposer une pastille claire.
const AMBIANCES: Dictionary = {
	# Feuilles vertes et rousses, qui tombent en tournoyant sous la frondaison.
	MapDataClass.TerrainType.FOREST: {
		"color": Color(1.0, 1.0, 1.0, 0.62),
		"colors": [Color(0.44, 0.62, 0.22), Color(0.66, 0.42, 0.16)],
		"rate": 0.35,
		"lifetime": 4.5,
		"gravity": Vector3(0.0, -0.30, 0.0),
		"direction": Vector3(0.0, -1.0, 0.0),
		"spread": 35.0,
		"speed": 0.10,
		"size": 0.055,
		"grow": Vector2(1.0, 0.85),
		"spin": 110.0,
		"rise": 1.30,
		"band": 0.50,
		"damping": 0.15,
	},
	# Flocons : plus lents que les feuilles, et sans tournoiement.
	MapDataClass.TerrainType.SNOW: {
		"color": Color(0.94, 0.97, 1.0, 0.70),
		"rate": 0.40,
		"lifetime": 5.0,
		"gravity": Vector3(0.0, -0.20, 0.0),
		"direction": Vector3(0.12, -1.0, 0.0),
		"spread": 22.0,
		"speed": 0.08,
		"size": 0.040,
		"grow": Vector2(1.0, 1.0),
		"spin": 0.0,
		"rise": 1.60,
		"band": 0.70,
		"damping": 0.05,
	},
	# Reflets : ils montent de la surface, s'éteignent en rétrécissant.
	MapDataClass.TerrainType.WATER: {
		"color": Color(0.80, 0.93, 1.0, 0.55),
		"rate": 0.30,
		"lifetime": 2.2,
		"gravity": Vector3.ZERO,
		"direction": Vector3(0.0, 1.0, 0.0),
		"spread": 18.0,
		"speed": 0.22,
		"size": 0.035,
		"grow": Vector2(1.0, 0.25),
		"spin": 0.0,
		"rise": 0.05,
		"band": 0.06,
		"damping": 0.35,
		"additive": true,
	},
	# Poussière dorée, soufflée presque à plat.
	MapDataClass.TerrainType.SAND: {
		"color": Color(0.91, 0.81, 0.57, 0.40),
		"rate": 0.30,
		"lifetime": 3.0,
		"gravity": Vector3(0.0, 0.02, 0.0),
		"direction": Vector3(0.94, 0.16, 0.30),
		"spread": 16.0,
		"speed": 0.55,
		"size": 0.045,
		"grow": Vector2(0.7, 1.4),
		"spin": 0.0,
		"rise": 0.18,
		"band": 0.16,
		"damping": 0.30,
	},
	# Brume de crête : elle dérive, elle ne tombe pas.
	MapDataClass.TerrainType.MOUNTAIN: {
		"color": Color(0.76, 0.80, 0.86, 0.26),
		"rate": 0.25,
		"lifetime": 5.5,
		"gravity": Vector3(0.0, 0.01, 0.0),
		"direction": Vector3(0.80, 0.10, 0.59),
		"spread": 28.0,
		"speed": 0.12,
		"size": 0.080,
		"grow": Vector2(0.8, 1.6),
		"spin": 0.0,
		"rise": 0.45,
		"band": 0.35,
		"damping": 0.04,
	},
	# Fumée de cheminée : elle monte du toit en s'élargissant.
	MapDataClass.TerrainType.VILLAGE: {
		"color": Color(0.72, 0.71, 0.70, 0.34),
		"rate": 0.35,
		"lifetime": 4.0,
		"gravity": Vector3(0.0, 0.12, 0.0),
		"direction": Vector3(0.10, 1.0, 0.0),
		"spread": 12.0,
		"speed": 0.32,
		"size": 0.050,
		"grow": Vector2(0.6, 2.2),
		"spin": 0.0,
		"rise": 1.40,
		"band": 0.12,
		"damping": 0.10,
	},
	# Le même feu, dans une cour plus haute et plus sombre.
	MapDataClass.TerrainType.FORT: {
		"color": Color(0.66, 0.65, 0.64, 0.32),
		"rate": 0.30,
		"lifetime": 4.2,
		"gravity": Vector3(0.0, 0.11, 0.0),
		"direction": Vector3(0.10, 1.0, 0.0),
		"spread": 12.0,
		"speed": 0.30,
		"size": 0.050,
		"grow": Vector2(0.6, 2.2),
		"spin": 0.0,
		"rise": 1.65,
		"band": 0.12,
		"damping": 0.10,
	},
	# Cendres et poussière de pierre, qui retombent sans se presser.
	MapDataClass.TerrainType.RUINS: {
		"color": Color(0.70, 0.67, 0.60, 0.34),
		"rate": 0.30,
		"lifetime": 4.5,
		"gravity": Vector3(0.0, -0.06, 0.0),
		"direction": Vector3(0.0, -1.0, 0.0),
		"spread": 55.0,
		"speed": 0.08,
		"size": 0.040,
		"grow": Vector2(1.0, 0.9),
		"spin": 35.0,
		"rise": 0.85,
		"band": 0.45,
		"damping": 0.20,
	},
}

## Les quatre voisines d'une case, pour le regroupement en îlots.
##
## Quatre et non huit : deux bois qui ne se touchent que par un coin sont deux
## bois, et leur donner un seul émetteur laisserait une moitié du feuillage
## sans une feuille.
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]

## Le point tendre partagé par toutes les particules (dégradé radial).
##
## Un quad nu donnerait des confettis carrés. Ce dégradé est calculé, pas
## chargé : le module ne dépend d'aucune image, donc d'aucun import.
static var _dot: GradientTexture2D = null

## Un maillage (et son matériau) par terrain — tous les émetteurs d'un même
## terrain le partagent.
static var _mesh_cache: Dictionary = {}


#region Pose
## Fait respirer une arène de bataille.
##
## Les cases se lisent sur la scène, comme le fait [method TacticsDecor.decorate]
## — carte engendrée depuis `MapData` et chapitre écrit à la main passent donc
## par le même chemin.
static func decorate(arena: Node3D) -> void:
	if not arena or not is_instance_valid(arena):
		return

	var cells: Array = []
	for tile: Variant in GridRef.tiles(arena):
		if not (tile is Node3D) or not is_instance_valid(tile):
			continue
		var node: Node3D = tile as Node3D
		var terrain: Variant = node.get("terrain_type")
		if terrain == null:
			continue
		cells.append({
			"cell": GridRef.tile_to_grid(arena, node),
			"terrain": int(terrain),
			"top": Vector3(node.global_position.x, _tile_top(node), node.global_position.z),
		})

	build(arena, cells, GridRef.tile_size(arena))


## Pose l'ambiance d'un hôte quelconque à partir de cases décrites.
##
## [param cells] `[{cell: Vector2i, terrain: int, top: Vector3}, …]` — la même
## description que [method TacticsDecor.build], `blocked` en moins : de l'air
## au-dessus d'un pion reste de l'air.
##
## Idempotent : le nœud d'accueil est reconstruit à chaque appel, ce qui permet
## de redessiner après un coup de pinceau dans l'éditeur.
static func build(host: Node3D, cells: Array, tile_size: float) -> void:
	if not host or not is_instance_valid(host):
		return

	var previous: Node = host.get_node_or_null(NodePath(HOST_NAME))
	if previous:
		host.remove_child(previous)
		previous.queue_free()

	var plan: Array = emitters(cells, tile_size)
	if plan.is_empty():
		return

	var root := Node3D.new()
	root.name = HOST_NAME
	host.add_child(root)

	for rank: int in plan.size():
		var node: CPUParticles3D = _emitter(plan[rank] as Dictionary, rank)
		if node:
			root.add_child(node)
#endregion


#region Calcul
## Les émetteurs d'une carte, prêts à poser. `[{terrain, cells, position, points, amount}, …]`
##
## Public pour la même raison que [method TacticsDecor.placements] : c'est tout
## le calcul, séparé de la pose. Un test l'interroge sans écran ni caméra — et
## des particules posées, elles, ne se laissent pas relire.
##
## `position` est le centre de gravité de l'îlot en coordonnées monde, `points`
## les naissances **relatives** à ce centre, `amount` le nombre de particules
## vivantes à la fois (débit × durée de vie).
static func emitters(cells: Array, tile_size: float) -> Array:
	var groups: Array = islands(cells)
	# Les plus gros îlots d'abord : quand le plafond tombe, il tombe sur les
	# recoins d'une case ou deux, pas sur la forêt qu'on regarde.
	groups.sort_custom(_by_island_weight)
	if groups.size() > MAX_EMITTERS:
		groups.resize(MAX_EMITTERS)

	var out: Array = []
	for group: Array in groups:
		var terrain: int = int((group[0] as Dictionary)["terrain"])
		var params: Dictionary = AMBIANCES[terrain]

		var origin := Vector3.ZERO
		for entry: Dictionary in group:
			origin += entry["top"] as Vector3
		origin /= float(group.size())

		var rate: float = clampf(group.size() * float(params["rate"]), MIN_RATE, MAX_RATE)
		out.append({
			"terrain": terrain,
			"cells": group.size(),
			"position": origin,
			"points": _birth_points(group, params, origin, tile_size),
			"amount": maxi(1, roundi(rate * float(params["lifetime"]))),
		})
	return out


## Les îlots contigus de même terrain, parmi les cases qui ont une ambiance.
##
## `[[{cell, terrain, top}, …], …]` — un tableau par îlot, cases triées par
## ligne puis colonne. Le parcours part des cases dans cet ordre, si bien que
## deux appels sur la même carte rendent exactement les mêmes îlots, dans le
## même ordre : une carte rechargée ne redistribue pas ses émetteurs.
static func islands(cells: Array) -> Array:
	var lookup: Dictionary = {}
	for entry: Variant in cells:
		if not (entry is Dictionary):
			continue
		var terrain: int = int((entry as Dictionary).get("terrain", -1))
		if not AMBIANCES.has(terrain):
			continue
		lookup[(entry as Dictionary).get("cell", Vector2i.ZERO)] = entry

	var ordered: Array = lookup.keys()
	ordered.sort_custom(_by_reading_order)

	var seen: Dictionary = {}
	var out: Array = []
	for start: Vector2i in ordered:
		if seen.has(start):
			continue
		var terrain: int = int((lookup[start] as Dictionary)["terrain"])

		# Parcours en largeur : la case, puis ses voisines de même terrain, puis
		# les leurs. Une pile suffit — l'ordre de visite ne change rien à
		# l'ensemble trouvé, et le tri final le remet en ordre de lecture.
		var group: Array = []
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			group.append(lookup[cell])
			for step: Vector2i in NEIGHBORS:
				var neighbor: Vector2i = cell + step
				if seen.has(neighbor) or not lookup.has(neighbor):
					continue
				if int((lookup[neighbor] as Dictionary)["terrain"]) != terrain:
					continue
				seen[neighbor] = true
				queue.append(neighbor)

		group.sort_custom(_by_cell_reading_order)
		out.append(group)
	return out


## Où naissent les particules d'un îlot, relativement à son centre.
##
## Les points sont **semés dans la case**, pas posés en son centre : sans ce
## décalage, les feuilles tomberaient en colonnes régulières et la grille se
## lirait dans l'air. Au-delà de [constant MAX_POINTS], les cases sont prises à
## pas régulier plutôt que les premières trouvées — un grand bois sème sur toute
## sa surface, pas sur son bord nord.
static func _birth_points(
	group: Array, params: Dictionary, origin: Vector3, tile_size: float
) -> PackedVector3Array:
	var stride: int = maxi(1, ceili(float(group.size()) / float(MAX_POINTS)))
	var kept: int = ceili(float(group.size()) / float(stride))
	var per_cell: int = clampi(MAX_POINTS / maxi(kept, 1), 1, POINTS_PER_CELL)

	var rise: float = float(params["rise"])
	var band: float = float(params["band"])

	var out := PackedVector3Array()
	var index: int = 0
	while index < group.size():
		var entry: Dictionary = group[index]
		var cell: Vector2i = entry["cell"]
		var top: Vector3 = entry["top"]
		for k: int in per_cell:
			out.append(Vector3(
				top.x + (_noise(cell, 300 + k) - 0.5) * tile_size,
				top.y + rise + _noise(cell, 320 + k) * band,
				top.z + (_noise(cell, 340 + k) - 0.5) * tile_size
			) - origin)
		index += stride
	return out


## Les gros îlots avant les petits ; à taille égale, l'ordre de lecture.
##
## Le départage n'est pas cosmétique : sans lui, deux îlots de même taille
## pourraient permuter d'un appel à l'autre selon l'ordre où l'appelant a décrit
## ses cases, et l'écrémage garderait l'un puis l'autre.
static func _by_island_weight(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return a.size() > b.size()
	return _by_cell_reading_order(a[0], b[0])


static func _by_cell_reading_order(a: Dictionary, b: Dictionary) -> bool:
	return _by_reading_order(a["cell"], b["cell"])


static func _by_reading_order(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## Bruit déterministe dans [0, 1), propre à une case et à un usage (`salt`).
##
## La même formule que [method TacticsDecor._noise] : une carte rechargée doit
## semer ses feuilles aux mêmes endroits, et deux machines en réseau voir le
## même bois.
static func _noise(cell: Vector2i, salt: int) -> float:
	var mixed: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)
	return float(absi(mixed) % 10007) / 10007.0


## Altitude du dessus d'une tuile, en coordonnées monde.
static func _tile_top(tile: Node3D) -> float:
	for child: Node in tile.get_children():
		if child is MeshInstance3D:
			var mesh_node: MeshInstance3D = child as MeshInstance3D
			var box: AABB = mesh_node.get_aabb()
			return (mesh_node.global_transform * Vector3(0.0, box.end.y, 0.0)).y
	return tile.global_position.y
#endregion


#region Rendu
## L'émetteur d'un îlot, réglé sur l'ambiance de son terrain.
static func _emitter(plan: Dictionary, rank: int) -> CPUParticles3D:
	var terrain: int = int(plan["terrain"])
	var params: Variant = AMBIANCES.get(terrain)
	if not (params is Dictionary):
		return null
	var settings: Dictionary = params

	var node := CPUParticles3D.new()
	node.name = "%s_%d" % [MapDataClass.type_key(terrain), rank]
	node.position = plan["position"]
	node.mesh = particle_mesh(terrain)
	# Une feuille ne porte pas d'ombre : la carte graphique la dessinerait deux
	# fois pour un pixel gris que personne ne cherche.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	node.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	node.emission_points = plan["points"]
	node.amount = int(plan["amount"])
	node.lifetime = float(settings["lifetime"])
	node.lifetime_randomness = LIFETIME_JITTER
	# L'ambiance est déjà en l'air quand la carte s'ouvre : sans ce préchauffage,
	# la première seconde d'une bataille se joue sous un ciel vide qui se remplit.
	node.preprocess = float(settings["lifetime"])
	node.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	node.direction = settings["direction"]
	node.spread = float(settings["spread"])
	node.gravity = settings["gravity"]
	var speed: float = float(settings["speed"])
	node.initial_velocity_min = speed * 0.6
	node.initial_velocity_max = speed * 1.3
	node.damping_min = float(settings["damping"]) * 0.5
	node.damping_max = float(settings["damping"])

	var spin: float = float(settings["spin"])
	if spin > 0.0:
		node.angle_min = -180.0
		node.angle_max = 180.0
		node.angular_velocity_min = -spin
		node.angular_velocity_max = spin

	node.scale_amount_min = 1.0 - SIZE_JITTER / 2.0
	node.scale_amount_max = 1.0 + SIZE_JITTER / 2.0
	node.scale_amount_curve = _growth_curve(settings["grow"])

	node.color = settings["color"]
	node.color_ramp = _fade_ramp()
	var colors: Variant = settings.get("colors")
	if colors is Array and (colors as Array).size() >= 2:
		node.color_initial_ramp = _two_tone_ramp(
			(colors as Array)[0], (colors as Array)[1])

	node.emitting = true
	return node


## Le maillage d'un terrain : un quad à la taille de sa particule, et son matériau.
##
## Partagé par tous les émetteurs du terrain — vingt bois ne font pas vingt
## matériaux. Public pour que les tests puissent vérifier la taille annoncée
## sans monter une scène.
static func particle_mesh(terrain: int) -> QuadMesh:
	var cached: Variant = _mesh_cache.get(terrain)
	if cached is QuadMesh:
		return cached

	var settings: Dictionary = AMBIANCES.get(terrain, {})
	var size: float = float(settings.get("size", 0.05))
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	mesh.material = _particle_material(settings)
	_mesh_cache[terrain] = mesh
	return mesh


## Le matériau d'une ambiance : un point tendre, orienté vers la caméra.
##
## Non éclairé, et volontairement : une feuille de cinq centimètres qui reçoit
## le soleil directionnel du plateau devient une pastille noire dès qu'elle
## passe dans une ombre portée. Aucune lueur propre non plus — l'ambiance est
## derrière le jeu, pas devant.
static func _particle_material(settings: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if bool(settings.get("additive", false)):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = dot_texture()
	# La couleur vient de la particule, pas du matériau : c'est ce qui permet à
	# une même feuille d'être verte ou rousse sans dupliquer quoi que ce soit.
	mat.vertex_color_use_as_albedo = true
	# `BILLBOARD_PARTICLES` plutôt que le panneau publicitaire ordinaire : lui
	# seul garde la rotation **et** l'échelle de la particule, c'est-à-dire le
	# tournoiement des feuilles et l'élargissement de la fumée.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Un quad transparent qui écrit dans le tampon de profondeur découpe les
	# particules derrière lui : c'est le tri par distance qui s'en charge.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


## Le point tendre partagé par toutes les particules.
##
## Un dégradé radial, calculé une fois : blanc plein au centre, transparent au
## bord. Il n'est pas chargé d'un fichier — l'ambiance ne doit pas disparaître
## parce qu'une image n'a pas été réimportée.
static func dot_texture() -> GradientTexture2D:
	if _dot:
		return _dot

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	_dot = GradientTexture2D.new()
	_dot.gradient = ramp
	_dot.width = 32
	_dot.height = 32
	_dot.fill = GradientTexture2D.FILL_RADIAL
	_dot.fill_from = Vector2(0.5, 0.5)
	_dot.fill_to = Vector2(1.0, 0.5)
	return _dot


## Le fondu d'une particule : elle apparaît, vit, s'efface.
##
## Sans lui, chaque flocon surgit et disparaît d'un coup — c'est ce clignotement,
## et non les particules elles-mêmes, qui attire l'œil hors du jeu.
static func _fade_ramp() -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.72, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	return ramp


## Les deux teintes entre lesquelles chaque particule tire la sienne à sa naissance.
static func _two_tone_ramp(first: Color, second: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, first)
	ramp.set_color(1, second)
	return ramp


## La courbe de taille d'une particule : `grow.x` à sa naissance, `grow.y` à sa mort.
static func _growth_curve(grow: Vector2) -> Curve:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = maxf(maxf(grow.x, grow.y), 1.0)
	curve.add_point(Vector2(0.0, grow.x))
	curve.add_point(Vector2(1.0, grow.y))
	return curve
#endregion
