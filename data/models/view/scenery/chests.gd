class_name TacticsChests
extends RefCounted
## Les coffres, vus du plateau : un sprite par case, fermé puis ouvert.
##
## Le pendant visuel de [BattleChests], qui tient l'état et ne connaît aucune
## scène. Le partage est le même qu'entre [BattleGrid] et les tuiles : les
## règles d'un côté, ce qu'on en voit de l'autre.
##
## ## Ce qu'un coffre emprunte à [TacticsDecor]
##
## Même façon de poser : un [Sprite3D] en panneau publicitaire, filtré au plus
## proche voisin (du pixel art filtré linéairement devient une purée), découpé
## plutôt que trié, et **posé par sa base** — sans ce report, le coffre serait
## enterré jusqu'à sa serrure.
##
## ## Ce qu'il ne lui emprunte pas
##
## Un décor est semé au hasard du hachage et peut disparaître sous l'écrémage ;
## un coffre est **placé**, et il n'a pas le droit de manquer : c'est une règle
## de jeu, pas une garniture. Il est aussi plus haut ([constant HEIGHT]) que tout
## ce que sème [TacticsDecor], pour qu'on le repère d'un coup d'œil sur une case
## qu'on n'a pas encore visitée.
##
## Sans texture sur le disque — ou sans écran du tout —, [method place] ne pose
## rien et [method mark_opened] ne fait rien : le ramassage, lui, continue de
## fonctionner. C'est ce qui rend la mécanique vérifiable en `--headless`.

## Nom du nœud qui accueille tous les coffres, sous l'arène.
const HOST_NAME: StringName = &"Chests"

## Dossier des sprites, produits par `art/dessiner-coffres.py`.
const CHEST_DIR: String = "res://assets/textures/chests/"

## Sprite d'un coffre (fermé). Un coffre ouvert n'a pas de sprite : il disparaît.
const CLOSED: String = "chest"

## Hauteur du coffre au sol, en unités monde (pour une case de 1).
##
## Un demi-carreau : au-dessus, il dispute sa silhouette au pion qui vient le
## chercher ; en dessous, il se confond avec les cailloux de [TacticsDecor], et
## personne ne fait un détour pour un caillou.
const HEIGHT: float = 0.50

## Décalage vertical au-dessus du sol de sa case — même valeur que
## [constant TacticsDecor.LIFT], et pour la même raison : assez pour que le
## sprite ne clignote pas dans le dessus de la case, assez peu pour qu'aucune
## caméra du jeu ne le voie décollé.
const LIFT: float = 0.004

## Les sprites posés, par case. Vide en `--headless`.
static var _sprites: Dictionary = {}

## Sprites déjà chargés, par nom (valeur nulle = fichier absent).
static var _texture_cache: Dictionary = {}


#region Pose
## Pose un coffre sur chacune des cases décrites.
##
## [param arena] L'arène de la bataille — les coffres deviennent ses enfants.
## [param chests] L'état armé par [method BattleChests.arm] ; les coffres déjà
## ouverts (il n'y en a pas au chargement, mais la fonction ne le suppose pas)
## reçoivent d'emblée leur sprite ouvert.
##
## Idempotent : le nœud d'accueil est reconstruit à chaque appel.
static func place(arena: Node3D, chests: BattleChests) -> void:
	_sprites.clear()
	if not arena or not is_instance_valid(arena):
		return

	var previous: Node = arena.get_node_or_null(NodePath(HOST_NAME))
	if previous:
		arena.remove_child(previous)
		previous.queue_free()
	if not chests or chests.cells().is_empty():
		return

	var root := Node3D.new()
	root.name = HOST_NAME
	arena.add_child(root)

	for cell: Vector2i in chests.cells():
		if not chests.is_closed(cell):
			continue  # Un coffre ouvert n'a pas de sprite : il a disparu.
		var tile: Node3D = TacticsGrid.find_tile(arena, cell.x, cell.y)
		if not tile:
			push_warning("[TacticsChests] Coffre en (%d, %d) : la carte n'a pas cette case."
				% [cell.x, cell.y])
			continue
		var sprite: Sprite3D = _sprite()
		if not sprite:
			return  # Texture absente : aucun coffre ne se posera, inutile d'insister.
		sprite.name = "Chest_%d_%d" % [cell.x, cell.y]
		sprite.position = Vector3(tile.global_position.x,
			_tile_top(tile) + LIFT, tile.global_position.z)
		root.add_child(sprite)
		_sprites[cell] = sprite


## Fait disparaître le coffre d'une case : il n'y a pas de visuel « ouvert »,
## le coffre s'évanouit quand on le ramasse.
##
## Sans effet si aucun sprite n'a été posé là — le cas de tous les tests et de
## tout lancement `--headless`.
static func mark_opened(cell: Vector2i) -> void:
	var sprite: Variant = _sprites.get(cell)
	if not (sprite is Sprite3D) or not is_instance_valid(sprite as Sprite3D):
		return
	var node: Sprite3D = sprite as Sprite3D
	node.visible = false
	_sprites.erase(cell)


## Oublie les coffres du plateau précédent.
##
## Les sprites appartiennent à l'arène et meurent avec elle ; ce dictionnaire,
## lui, est un statique — sans ce nettoyage il désignerait des nœuds libérés.
static func clear() -> void:
	_sprites.clear()
#endregion


#region Internes
## Le sprite d'un coffre, ou `null` si sa texture manque du disque.
static func _sprite() -> Sprite3D:
	var texture: Texture2D = chest_texture(CLOSED)
	if not texture or texture.get_height() <= 0:
		return null

	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.pixel_size = HEIGHT / float(texture.get_height())
	# L'origine du sprite est sa **base** : sans ce report, le coffre serait
	# enterré jusqu'à sa serrure.
	sprite.offset = Vector2(0.0, texture.get_height() / 2.0)
	return sprite


## Texture d'un coffre, ou `null` si elle manque.
##
## Le chargement passe par [method ResourceLoader.exists] pour la même raison que
## [method TacticsDecor.decor_texture] : une image que Godot n'a pas encore
## importée ne doit pas emporter la bataille, seulement priver la case de son
## sprite.
static func chest_texture(kind: String) -> Texture2D:
	if _texture_cache.has(kind):
		return _texture_cache[kind]

	var texture: Texture2D = null
	var path: String = "%s%s.png" % [CHEST_DIR, kind]
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_texture_cache[kind] = texture
	return texture


## Altitude du dessus d'une tuile, en coordonnées monde.
##
## Même mesure que [method TacticsDecor._tile_top] : un coffre posé sur une
## montagne surélevée doit reposer sur son sommet, pas flotter à l'altitude du
## plancher de la carte.
static func _tile_top(tile: Node3D) -> float:
	for child: Node in tile.get_children():
		if child is MeshInstance3D:
			var mesh_node: MeshInstance3D = child as MeshInstance3D
			var box: AABB = mesh_node.get_aabb()
			return (mesh_node.global_transform * Vector3(0.0, box.end.y, 0.0)).y
	return tile.global_position.y
#endregion
