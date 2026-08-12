class_name BattleGridOverlay
extends Node3D
## Quadrillage du plateau — la touche [b]G[/b] l'affiche et le masque.
##
## Les cases du jeu se lisent à leur couleur de terrain, et rien d'autre : deux
## cases d'herbe voisines n'ont pas de bord commun visible. Compter « à trois
## cases de là » revenait donc à survoler le plateau à la souris pour voir les
## surlignages s'allumer un par un. Un liseré sur le bord de chaque case rend au
## joueur ce que le jeu suppose qu'il voit.
##
## [b]Rien n'est calculé sur le jeu.[/b] Un seul [MeshInstance3D] porte toutes
## les lignes, construit une fois, montré ou caché ensuite : aucune tuile n'est
## touchée, aucun matériau de terrain n'est remplacé, et le quadrillage ne
## participe à aucune règle. C'est ce qui le distingue de la portée ennemie
## ([BattleThreatRange]), qui pose des drapeaux sur les cases.
##
## [b]L'état survit à la bataille.[/b] Un joueur qui joue quadrillé le veut à
## tous les chapitres : [member remembered] retient le dernier choix, et un
## quadrillage remonté sur la carte suivante s'y rallume seul.
##
## [b]La géométrie est une fonction pure.[/b] [method tile_outline] rend les
## sommets d'un contour sans nœud ni scène : le tracé se vérifie en `--headless`,
## là où le rendu n'a pas lieu d'être.

## La touche qui montre et masque le quadrillage.
const TOGGLE_KEY: Key = KEY_G
## L'action d'entrée correspondante, telle que `project.godot` la déclare.
##
## Passer par l'action plutôt que par le code de touche brut, c'est lire la
## touche **physique** : sur un clavier AZERTY, `keycode` rend la lettre imprimée
## et non la position, et le G du quadrillage n'aurait pas été le même selon la
## disposition. C'est aussi ce qui rendra la touche remappable.
const TOGGLE_ACTION: String = "toggle_grid"

## Hauteur du liseré au-dessus de la surface de la case, en unités de monde.
## Assez pour ne pas lutter avec le sol (z-fighting), assez peu pour rester posé
## dessus plutôt que flotter.
const LIFT: float = 0.02

## Le liseré ne fait pas tout à fait le tour : une case de 1 unité reçoit un
## carré de 0,94 — ce qui laisse voir la rainure entre deux cases au lieu de la
## combler d'un trait deux fois trop épais.
const INSET: float = 0.94

## Couleur du trait — une encre sombre, lisible sur l'herbe comme sur la pierre.
const C_LINE := Color(0.05, 0.06, 0.10, 0.55)

## Dernier choix du joueur, retenu d'une bataille à l'autre.
static var remembered: bool = false

## L'arène quadrillée. Renseignée au montage ; devinée sinon.
var arena: Node = null

var _mesh: MeshInstance3D = null
var _shown: bool = false


## Y a-t-il un écran où dessiner le quadrillage ?
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


#region Géométrie
## Les quatre côtés du contour d'une case, en segments bout à bout.
##
## Rend huit sommets — quatre paires, une par côté — prêts pour un maillage en
## [constant Mesh.PRIMITIVE_LINES]. [param center] est le centre de la case au
## niveau de sa surface ; [param side] le côté du carré tracé.
static func tile_outline(center: Vector3, side: float) -> PackedVector3Array:
	var h: float = side / 2.0
	var y: float = center.y + LIFT
	var nw := Vector3(center.x - h, y, center.z - h)
	var ne := Vector3(center.x + h, y, center.z - h)
	var se := Vector3(center.x + h, y, center.z + h)
	var sw := Vector3(center.x - h, y, center.z + h)
	return PackedVector3Array([nw, ne, ne, se, se, sw, sw, nw])


## Centre (surface comprise) et côté du contour à tracer pour une tuile.
##
## La tuile est un pavé dont le nœud se tient au milieu : sa surface est donc
## plus haute que sa position d'une demi-épaisseur, et cette épaisseur suit le
## relief de la carte. On la lit sur le maillage plutôt que de la supposer —
## c'est la seule façon de couvrir à la fois les cartes engendrées depuis un
## [MapData] et les chapitres dessinés à la main.
##
## [returns] `{"center": Vector3, "side": float}`, ou un dictionnaire vide si la
## tuile ne porte pas de maillage lisible.
static func outline_of(tile: Node3D) -> Dictionary:
	if not tile or not is_instance_valid(tile):
		return {}
	var mesh: MeshInstance3D = tile.get_node_or_null("Tile") as MeshInstance3D
	if not mesh or not mesh.mesh:
		return {}

	var box: AABB = mesh.get_aabb()
	var footprint: float = minf(box.size.x, box.size.z)
	if footprint <= 0.0:
		return {}
	return {
		"center": Vector3(tile.global_position.x, tile.global_position.y + box.end.y,
			tile.global_position.z),
		"side": footprint * INSET,
	}
#endregion


#region Montage
func _ready() -> void:
	if not arena or not is_instance_valid(arena):
		arena = _find_arena()
	_build()
	set_shown(remembered)


## L'arène de la bataille en cours, cherchée sous le niveau parent.
func _find_arena() -> Node:
	var level: Node = get_parent()
	if level is TacticsLevel:
		return (level as TacticsLevel).arena
	return level.get_node_or_null("TacticsArena") if level else null


## Bâtit le maillage des liserés, une fois pour toute la bataille.
##
## Un seul maillage plutôt qu'un nœud par case : une carte de 20×20 en ferait
## quatre cents, tous à dessiner et à libérer, pour un tracé qui ne bouge jamais.
func _build() -> void:
	if _mesh and is_instance_valid(_mesh):
		_mesh.queue_free()
		_mesh = null

	var tiles: Node = arena.get_node_or_null("Tiles") if arena and is_instance_valid(arena) else null
	if not tiles:
		return

	var drawn: int = 0
	var points := PackedVector3Array()
	for tile: Node in tiles.get_children():
		if not tile is Node3D:
			continue
		var shape: Dictionary = outline_of(tile as Node3D)
		if shape.is_empty():
			continue
		points.append_array(tile_outline(shape["center"], float(shape["side"])))
		drawn += 1
	if drawn == 0:
		return

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point: Vector3 in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()

	_mesh = MeshInstance3D.new()
	_mesh.name = "GridLines"
	_mesh.mesh = mesh
	_mesh.material_override = _line_material()
	# Le quadrillage n'est qu'un repère : il ne doit ni s'éclairer, ni porter
	# d'ombre sur les cases qu'il souligne.
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_mesh.visible = _shown


## Le trait : sans lumière, semi-transparent, et sans profondeur inscrite — trois
## liserés qui se croisent ne doivent pas se découper l'un l'autre.
func _line_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = C_LINE
	mat.vertex_color_use_as_albedo = false
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	return mat


## Nombre de cases effectivement quadrillées (0 hors bataille).
func outlined_count() -> int:
	if not _mesh or not is_instance_valid(_mesh):
		return 0
	var mesh: ImmediateMesh = _mesh.mesh as ImmediateMesh
	if not mesh or mesh.get_surface_count() == 0:
		return 0
	# Huit sommets par case (quatre côtés, deux sommets chacun).
	return int(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 8)
#endregion


#region Vie de l'affichage
## G montre le quadrillage, G le remet.
##
## Les répétitions clavier sont ignorées : une touche laissée enfoncée en produit
## des dizaines, et le quadrillage clignoterait.
func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(TOGGLE_ACTION):
		if not event.is_action_pressed(TOGGLE_ACTION):
			return
	else:
		# Repli, si la carte d'entrées ne déclare pas l'action : le code de touche.
		var key := event as InputEventKey
		if not key or key.keycode != TOGGLE_KEY or key.echo or not key.pressed:
			return
	toggle()
	get_viewport().set_input_as_handled()


## Bascule l'affichage. [returns] son nouvel état.
func toggle() -> bool:
	set_shown(not _shown)
	return _shown


## Montre ou masque le quadrillage, et retient le choix pour la suite.
func set_shown(v: bool) -> void:
	_shown = v
	remembered = v
	if _mesh and is_instance_valid(_mesh):
		_mesh.visible = v


## Le quadrillage est-il affiché ?
func is_shown() -> bool:
	return _shown
#endregion
