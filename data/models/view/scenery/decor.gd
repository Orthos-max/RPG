class_name TacticsDecor
extends RefCounted
## Ce qui traîne sur les cases : fleurs, herbes hautes, cailloux, champignons.
##
## [TacticsProps] pose ce qui **fait** un terrain — l'arbre d'un bois, le
## créneau d'un rempart, la maison d'un hameau. Il ne pose rien sur une plaine,
## et c'est juste : une plaine n'a rien à montrer d'obligatoire. Restait qu'une
## carte de trente cases d'herbe montrait trente fois exactement la même chose,
## variantes de tuile comprises — un motif ne remplace pas un objet.
##
## Ce module sème donc de la menue monnaie par-dessus : une touffe de fleurs
## ici, un caillou là, un champignon au pied d'un arbre. Rien d'obligatoire,
## rien de lisible en règle — et c'est la condition pour que ça n'encombre pas
## la lecture tactique.
##
## ## Les quatre règles
##
## - **Rien n'est tiré au hasard.** Comme [TacticsProps], tout vient du hachage
##   des coordonnées de la case : la même carte se garnit à l'identique d'une
##   partie à l'autre, et deux machines en réseau voient la même prairie.
## - **Rien ne se pose là où l'on joue.** Ni sur une case de déploiement, ni
##   sous un pion : l'appelant marque ces cases (`blocked`), et elles restent
##   nues. La décoration n'a aucune collision, ne coûte aucun point de
##   mouvement, et ne change pas un seul chiffre.
## - **Rien ne flotte.** Chaque sprite porte son ombre ([constant SHADOW]),
##   posée à plat et décalée dans le sens du soleil du plateau. Les arbres de la
##   forêt en reçoivent une aussi : ce sont les plus gros volumes du décor, et
##   les seuls qu'on voyait léviter.
## - **Rien ne s'emballe.** [constant MAX_DECOR] plafonne la garniture d'une
##   carte. Au-delà, l'écrémage garde les cases dont le hachage tire le plus
##   bas : une carte de huit cents cases est éclaircie **uniformément**, pas
##   tronquée par le haut.
##
## Bataille et éditeur de cartes passent par [method build], avec la même
## description de cases : dessiner une prairie dans l'éditeur et n'y voir aucune
## fleur avant d'avoir lancé la partie serait un drôle d'éditeur.

const MapDataClass = preload("res://data/models/world/map/map_data.gd")
const GridRef = preload("res://data/models/world/utilities/grid.gd")

## Nom du nœud qui accueille toute la garniture, sous l'arène.
const HOST_NAME: StringName = &"Decor"

## Dossier des sprites, produits par `art/dessiner-decor.py`.
const DECOR_DIR: String = "res://assets/textures/decor/"

## Nom du sprite d'ombre, traité à part de tous les autres.
const SHADOW: String = "shadow"

## Plafond de garniture d'une carte, ombres non comprises.
##
## Une carte de 32 × 24 propose quelque deux cents cases éligibles ; en poser
## autant ferait de chaque prairie un massif fleuri, et de chaque plateau une
## soupe de sprites transparents à trier par la carte graphique. Quatre-vingts
## suffisent à ce qu'aucune zone ne soit nue.
const MAX_DECOR: int = 80

## Ce que chaque terrain reçoit : les sprites possibles, et sur quelle part de
## ses cases.
##
## Les fréquences sont basses **et c'est le sujet** : une fleur qu'on remarque
## est une fleur qu'on a mise trop souvent. La forêt est la plus discrète des
## quatre — elle porte déjà un arbre par case.
const SEEDING: Dictionary = {
	MapDataClass.TerrainType.GRASS: {"kinds": ["flower", "blades"], "rate": 0.12},
	MapDataClass.TerrainType.SAND: {"kinds": ["pebbles"], "rate": 0.10},
	MapDataClass.TerrainType.PATH: {"kinds": ["pebbles"], "rate": 0.10},
	MapDataClass.TerrainType.FOREST: {"kinds": ["mushroom", "bush"], "rate": 0.08},
	MapDataClass.TerrainType.MOUNTAIN: {"kinds": ["rock"], "rate": 0.10},
	MapDataClass.TerrainType.VILLAGE: {"kinds": ["hay", "barrel"], "rate": 0.08},
	MapDataClass.TerrainType.FORT: {"kinds": ["stack", "barrel"], "rate": 0.08},
}

## Encombrement de chaque sprite : hauteur au sol, et largeur de son ombre.
##
## En unités monde, pour une case de 1. Tout tient sous le quart d'une case :
## au-delà, une touffe de fleurs commence à disputer sa silhouette au pion qui
## se tient à côté — et le décor n'est là que pour être vu du coin de l'œil.
const SIZES: Dictionary = {
	"flower": {"height": 0.30, "shadow": 0.20},
	"blades": {"height": 0.34, "shadow": 0.24},
	"mushroom": {"height": 0.22, "shadow": 0.18},
	"bush": {"height": 0.40, "shadow": 0.30},
	"pebbles": {"height": 0.18, "shadow": 0.22},
	"rock": {"height": 0.26, "shadow": 0.24},
	"hay": {"height": 0.32, "shadow": 0.26},
	"barrel": {"height": 0.34, "shadow": 0.22},
	"stack": {"height": 0.36, "shadow": 0.28},
}

## Écart au centre de la case, en fraction de case.
##
## Même valeur que [constant TacticsProps.CORNER_OFFSET], et pour la même
## raison : c'est ce qui laisse le centre — donc le pion — dégagé.
const CORNER_OFFSET: float = 0.30

## Amplitude de la variation de taille : de 0,8 à 1,2 fois la taille nominale.
const SIZE_JITTER: float = 0.4

## Décalage vertical d'un sprite au-dessus du sol de sa case.
##
## Assez pour qu'il ne clignote pas dans le dessus de la case, assez peu pour
## qu'aucune caméra du jeu ne le voie décollé.
const LIFT: float = 0.004

## Décalage vertical d'une ombre — sous les sprites, au-dessus du sol.
const SHADOW_LIFT: float = 0.012

## Sens dans lequel les ombres s'allongent, à plat sur le sol.
##
## C'est la composante horizontale du soleil du plateau, normalisée : la lumière
## de [method TacticsScenery.configure_light] descend d'un lacet de -132° et
## d'une inclinaison de -52°, ce qui pousse les ombres vers le sud-est. Une
## ombre centrée sous son objet ne dit rien ; une ombre qui part du mauvais côté
## se remarque tout de suite.
const SHADOW_DIR: Vector2 = Vector2(0.744, 0.669)

## De combien l'ombre se décale, en fraction de sa propre largeur.
const SHADOW_SLIP: float = 0.28

## Teinte des ombres : un gris bleuté, jamais du noir.
##
## Une ombre noire creuse un trou dans le sol ; celle-ci l'assombrit en le
## refroidissant, comme le fait l'ombre portée du soleil directionnel.
const SHADOW_TINT: Color = Color(0.08, 0.09, 0.16, 0.32)

## Combien l'ombre d'un arbre déborde de sa frondaison.
##
## Sous 1, l'ombre se cache sous le feuillage et ne pose rien ; au-delà de ~1,2
## elle bave sur les cases voisines.
const TREE_SHADOW_SPAN: float = 1.05

## Sprites déjà chargés, par nom (valeur nulle = fichier absent).
static var _texture_cache: Dictionary = {}


#region Pose
## Garnit une arène de bataille, cases de déploiement et pions exclus.
##
## Les cases se lisent sur la scène, comme le fait [method TacticsProps.decorate]
## — une carte engendrée depuis `MapData` et un chapitre écrit à la main passent
## donc par le même chemin.
##
## Idempotent : rappelée après que le déploiement a ouvert ses cases, elle
## regarnit le plateau en les évitant.
static func decorate(arena: Node3D) -> void:
	if not arena or not is_instance_valid(arena):
		return

	var grid: BattleGrid = BattleGrid.current
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
			"blocked": bool(node.get("deploy_point"))
				or (grid != null and grid.occupant_of(node) != null),
		})

	build(arena, cells, GridRef.tile_size(arena))


## Garnit un hôte quelconque à partir de cases décrites.
##
## [param cells] `[{cell: Vector2i, terrain: int, top: Vector3, blocked: bool}, …]`
## — `blocked` marque les cases où rien ne doit se poser (départ, pion).
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

	var batches: Dictionary = placements(cells, tile_size)
	if batches.is_empty():
		return

	var root := Node3D.new()
	root.name = HOST_NAME
	host.add_child(root)

	# Les ombres passent en premier : posées à plat sous des sprites debout, elles
	# n'ont pas à se disputer la profondeur avec eux, mais l'ordre de l'arbre
	# départage les transparences que le tri par distance laisse à égalité.
	for kind: String in [SHADOW] + SIZES.keys():
		for entry: Variant in batches.get(kind, []):
			var sprite: Sprite3D = _sprite(kind, entry as Dictionary)
			if sprite:
				root.add_child(sprite)
#endregion


#region Calcul
## Ce que porte chaque case, sprite par sprite. `{kind: [{position, yaw, size}, …]}`
##
## Public pour la même raison que [method TacticsProps.placements] : c'est tout
## le calcul, séparé de la pose. Un test l'interroge sans écran ni caméra.
##
## `size` est un encombrement en **unités monde** : la hauteur au sol d'un
## sprite debout, le diamètre d'une ombre couchée. `yaw` est une rotation autour
## de la verticale — elle ne sert qu'aux ombres, un sprite en panneau publicitaire
## faisant toujours face à la caméra.
static func placements(cells: Array, tile_size: float) -> Dictionary:
	var chosen: Array = _sown(cells, tile_size)
	chosen.sort_custom(_by_thinning_rank)
	if chosen.size() > MAX_DECOR:
		chosen.resize(MAX_DECOR)

	var out: Dictionary = {}
	for entry: Dictionary in chosen:
		var kind: String = str(entry["kind"])
		_append(out, kind, {
			"position": entry["position"] + Vector3(0.0, LIFT, 0.0),
			"yaw": 0.0,
			"size": entry["size"],
		})
		_append(out, SHADOW, _shadow_at(
			entry["position"], float(SIZES[kind]["shadow"]) * float(entry["jitter"])))

	# L'ombre des arbres ne dépend pas de la garniture : une case de forêt en
	# reçoit une, qu'elle porte un champignon, un pion ou rien du tout.
	for cell_entry: Variant in cells:
		if not (cell_entry is Dictionary):
			continue
		if int(cell_entry.get("terrain", -1)) != MapDataClass.TerrainType.FOREST:
			continue
		var cell: Vector2i = cell_entry.get("cell", Vector2i.ZERO)
		var foot: Vector3 = cell_entry.get("top", Vector3.ZERO) \
			+ _prop_foot(cell, tile_size)
		_append(out, SHADOW, _shadow_at(
			foot, _canopy_span(cell, tile_size) * TREE_SHADOW_SPAN))

	return out


## Les cases qui tirent une décoration, avant écrémage.
static func _sown(cells: Array, tile_size: float) -> Array:
	var out: Array = []
	for entry: Variant in cells:
		if not (entry is Dictionary) or bool(entry.get("blocked", false)):
			continue
		var terrain: int = int(entry.get("terrain", -1))
		var seeding: Variant = SEEDING.get(terrain)
		if not (seeding is Dictionary):
			continue

		var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
		if _noise(cell, 200) >= float(seeding["rate"]):
			continue

		var kinds: Array = seeding["kinds"]
		var kind: String = str(kinds[int(_noise(cell, 201) * kinds.size()) % kinds.size()])
		var jitter: float = 1.0 - SIZE_JITTER / 2.0 + _noise(cell, 202) * SIZE_JITTER
		out.append({
			"cell": cell,
			"kind": kind,
			"jitter": jitter,
			"size": float(SIZES[kind]["height"]) * jitter,
			"position": (entry.get("top", Vector3.ZERO) as Vector3) + _offset(cell, terrain, tile_size),
		})
	return out


## L'écrémage : les cases au hachage le plus bas restent, les autres tombent.
##
## Le rang vient d'un tirage **propre à l'écrémage** — pas de la place de la case
## dans la liste, qui ferait d'une carte trop grande une carte garnie en haut et
## nue en bas. La coordonnée départage les ex æquo : deux cases ne peuvent pas
## permuter d'un appel à l'autre selon l'ordre où l'appelant les a décrites.
static func _by_thinning_rank(a: Dictionary, b: Dictionary) -> bool:
	var rank_a: float = _noise(a["cell"], 203)
	var rank_b: float = _noise(b["cell"], 203)
	if rank_a != rank_b:
		return rank_a < rank_b
	var cell_a: Vector2i = a["cell"]
	var cell_b: Vector2i = b["cell"]
	if cell_a.y != cell_b.y:
		return cell_a.y < cell_b.y
	return cell_a.x < cell_b.x


## Où se pose la garniture d'une case, par rapport à son centre.
##
## En forêt, elle part du coin **opposé** à l'arbre ([method TacticsProps.prop_foot]
## avec deux quarts de tour) : un champignon dans le tronc de son propre chêne
## n'est pas un sous-bois, c'est un défaut d'alignement.
static func _offset(cell: Vector2i, terrain: int, tile_size: float) -> Vector3:
	if terrain == MapDataClass.TerrainType.FOREST:
		return _prop_foot(cell, tile_size, 2)
	var angle: float = _noise(cell, 204) * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * tile_size * CORNER_OFFSET


## L'ombre d'un objet posé en [param foot], large de [param span].
static func _shadow_at(foot: Vector3, span: float) -> Dictionary:
	var slip: Vector2 = SHADOW_DIR * span * SHADOW_SLIP
	return {
		"position": foot + Vector3(slip.x, SHADOW_LIFT, slip.y),
		"yaw": 0.0,
		"size": span,
	}


## Bruit déterministe dans [0, 1), propre à une case et à un usage (`salt`).
##
## La même formule que [method TacticsProps._noise] (qui est privée) : les deux
## modules doivent tirer les mêmes rangs pour la même case, sans dépendre l'un
## de l'autre.
static func _noise(cell: Vector2i, salt: int) -> float:
	var mixed: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)
	return float(absi(mixed) % 10007) / 10007.0


## Le coin de la case où un arbre s'enracine, en coordonnées monde.
##
## Réplique de [method TacticsProps._corner] (privée) : une ombre de forêt doit
## tomber sous l'arbre que [TacticsProps] a dessiné, pas au centre de la case.
static func _prop_foot(cell: Vector2i, tile_size: float, quarters: int = 0) -> Vector3:
	var angle: float = (floor(_noise(cell, 3) * 4.0) + float(quarters)) * (TAU / 4.0) \
		+ (TAU / 8.0)
	return Vector3(cos(angle), 0.0, sin(angle)) * tile_size * CORNER_OFFSET


## Largeur de la frondaison d'un arbre de la case, en unités monde.
##
## Réplique de la carrure d'un arbre de [TacticsProps] : l'ombre d'un chêne doit
## couvrir ce que le chêne couvre.
static func _canopy_span(cell: Vector2i, tile_size: float) -> float:
	return (0.8 + _noise(cell, 1) * 0.4) * tile_size


static func _append(out: Dictionary, kind: String, entry: Dictionary) -> void:
	if not out.has(kind):
		out[kind] = []
	out[kind].append(entry)


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
## Le sprite d'une entrée, ou `null` si sa texture manque.
static func _sprite(kind: String, entry: Dictionary) -> Sprite3D:
	var texture: Texture2D = decor_texture(kind)
	if not texture or texture.get_height() <= 0:
		return null

	var sprite := Sprite3D.new()
	sprite.name = kind
	sprite.texture = texture
	# Du pixel art filtré linéairement devient une purée : douze pixels de fleur
	# n'y survivraient pas. Pas de mipmaps — ces sprites sont minuscules et
	# toujours vus de près, et leurs textures ne sont pas importées avec.
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.position = entry["position"]

	if kind == SHADOW:
		# Couchée : la texture d'ombre est un disque, elle se regarde d'en haut.
		sprite.rotation_degrees = Vector3(-90.0, rad_to_deg(float(entry["yaw"])), 0.0)
		sprite.pixel_size = float(entry["size"]) / float(texture.get_width())
		sprite.modulate = SHADOW_TINT
		# Non éclairée : une ombre qui reçoit la lumière du soleil s'éclaircit là
		# où elle devrait être la plus franche.
		sprite.shaded = false
		# Le dégradé va jusqu'à zéro : le découper le rendrait à bord net, ce qui
		# est exactement ce qu'on cherche à éviter.
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sprite.render_priority = -1
		return sprite

	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = true
	# Découpé plutôt que trié : un sprite transparent posé sur un sol opaque se
	# passe très bien du tri par profondeur, qui le ferait clignoter derrière ses
	# voisins selon l'angle de la caméra.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.pixel_size = float(entry["size"]) / float(texture.get_height())
	# L'origine du sprite est sa **base** : sans ce report, la fleur serait
	# enterrée jusqu'à mi-tige, à moitié dans sa propre case.
	sprite.offset = Vector2(0.0, texture.get_height() / 2.0)
	return sprite


## Sprite d'un type de décor, ou `null` s'il manque du disque.
##
## Le chargement passe par [method ResourceLoader.exists] pour la même raison que
## [method TacticsScenery.terrain_texture] : une image que Godot n'a pas encore
## importée ne doit pas emporter la scène, seulement priver la case de sa fleur.
static func decor_texture(kind: String) -> Texture2D:
	if _texture_cache.has(kind):
		return _texture_cache[kind]

	var texture: Texture2D = null
	var path: String = "%s%s.png" % [DECOR_DIR, kind]
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_texture_cache[kind] = texture
	return texture
#endregion
