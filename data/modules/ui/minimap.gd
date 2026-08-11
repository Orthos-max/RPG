class_name BattleMinimap
extends CanvasLayer
## Minimap de bataille — le plateau entier dans un coin de l'écran.
##
## Le champ de vision tactique ne montre jamais toute la carte : la caméra est
## basse, les reliefs cachent des cases, et on perd de vue où sont les renforts.
## Cette vignette répond à la seule question qui compte entre deux tours : qui
## est où.
##
## Elle ne connaît ni l'arène ni les pions directement — elle lit l'index de
## grille ([BattleGrid]) et les camps du niveau, comme tout le reste du jeu.
## [method snapshot] rend cet état en données pures : couleurs et rectangles se
## déduisent ensuite sans le moindre nœud, ce qui rend la lecture vérifiable en
## headless même si le dessin, lui, n'y a pas lieu.

const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")
const SceneryClass = preload("res://data/models/view/scenery/tactics_scenery.gd")

## Côté maximal de la vignette, en pixels.
const MAX_SIZE: float = 168.0
## Côté minimal d'une case dessinée — en deçà, la carte devient illisible.
const MIN_CELL: float = 3.0
## Côté maximal d'une case : une petite carte ne doit pas remplir l'écran.
const MAX_CELL: float = 12.0
## Marge intérieure du cadre, en pixels.
const PADDING: float = 6.0
## Intervalle entre deux relectures du plateau, en secondes.
##
## Les pions se déplacent en glissant sur plusieurs frames : redessiner à chaque
## image ne montrerait rien de plus et ferait travailler l'interface pour rien.
const REFRESH: float = 0.2

## Sous le bandeau de tour (10) et sous le fondu (100), au-dessus du jeu.
const LAYER: int = 9

const C_PANEL := Color(0.05, 0.04, 0.10, 0.82)
const C_EDGE := Color("#f5c842")
## Case sans tuile — un trou du plateau, ou hors du rectangle englobant.
const C_VOID := Color(0, 0, 0, 0)

## Le niveau observé.
var level: Node = null

var _root: Control = null
var _canvas: Control = null
var _toggle: Button = null
var _state: Dictionary = {}
var _since_refresh: float = 0.0


## Y a-t-il un écran où dessiner la carte ?
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


#region Lecture du plateau
## État du plateau en données pures : dimensions, terrains, pions.
##
## Rend `{"size": Vector2i, "terrain": PackedInt32Array, "pawns": Array}` où
## `terrain` est indexé ligne par ligne (`row * size.x + col`, -1 = pas de case)
## et chaque pion vaut `{"cell": Vector2i, "side": int}`.
static func snapshot(from_level: Node) -> Dictionary:
	var empty: Dictionary = {"size": Vector2i.ZERO, "terrain": PackedInt32Array(), "pawns": []}

	var grid: BattleGrid = _grid_of(from_level)
	if not grid:
		return empty
	var dims: Vector2i = grid.dimensions()
	if dims.x <= 0 or dims.y <= 0:
		return empty

	var terrain := PackedInt32Array()
	terrain.resize(dims.x * dims.y)
	for row: int in dims.y:
		for col: int in dims.x:
			var tile: TacticsTile = grid.tile_at_cell(Vector2i(col, row)) as TacticsTile
			terrain[row * dims.x + col] = tile.terrain_type if tile else -1

	return {"size": dims, "terrain": terrain, "pawns": _read_pawns(from_level, grid)}


## L'index de grille de ce niveau — le sien s'il l'expose, celui en cours sinon.
static func _grid_of(from_level: Node) -> BattleGrid:
	if from_level is TacticsLevel:
		var arena: TacticsArena = (from_level as TacticsLevel).arena
		if arena and arena.grid:
			return arena.grid
	return BattleGrid.current


## Les pions vivants, avec leur case et leur camp.
##
## Le camp se lit sur le nœud parent ([method TeamData.side_for_camp_node]) et
## non sur le pion : c'est déjà ainsi que le reste du jeu répartit les armées,
## et un pion confié au troisième camp est *reparenté*, donc suivi sans rien
## avoir à mettre à jour.
static func _read_pawns(from_level: Node, grid: BattleGrid) -> Array:
	var out: Array = []
	if not from_level is TacticsLevel:
		return out
	var participant: Node = (from_level as TacticsLevel).participant
	if not participant or not is_instance_valid(participant):
		return out

	for camp: Node in participant.get_children():
		var side: int = TeamDataClass.side_for_camp_node(camp)
		if side < 0:
			continue
		for child: Node in camp.get_children():
			if not child is TacticsPawn:
				continue
			var pawn: TacticsPawn = child as TacticsPawn
			if not pawn.is_alive() or pawn.is_queued_for_deletion():
				continue
			var cell: Vector2i = grid.cell_of(pawn.get_tile())
			if cell.x < 0 or cell.y < 0:
				continue
			out.append({"cell": cell, "side": side})
	return out


## Teinte d'une case sur la vignette — celle du terrain, un peu assombrie.
##
## On reprend les couleurs du décor 3D ([TacticsScenery]) plutôt que d'en
## inventer : la vignette et le plateau doivent se lire comme la même carte.
static func terrain_color(terrain: int) -> Color:
	if terrain < 0:
		return C_VOID
	return Color(str(SceneryClass.TERRAIN_COLORS.get(terrain, "#4a8c3f"))).darkened(0.1)


## Côté d'une case pour un plateau de [param dims], en pixels.
static func cell_side(dims: Vector2i) -> float:
	if dims.x <= 0 or dims.y <= 0:
		return 0.0
	var side: float = MAX_SIZE / float(maxi(dims.x, dims.y))
	return clampf(side, MIN_CELL, MAX_CELL)
#endregion


#region Montage
func _ready() -> void:
	layer = LAYER
	_build()
	_reload()


func _build() -> void:
	_root = Control.new()
	_root.name = "MinimapRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# `PRESET_MODE_MINSIZE` : la colonne ne fait que la taille de son contenu, et
	# `GROW_DIRECTION_BEGIN` la fait grandir vers la gauche — le coin haut-droit
	# reste le point fixe quand la vignette change de dimensions avec la carte.
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.add_theme_constant_override("separation", 4)
	_root.add_child(column)

	_toggle = Button.new()
	_toggle.text = "🗺  Carte (M)"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	_toggle.add_theme_font_size_override("font_size", 12)
	_toggle.pressed.connect(toggle)
	column.add_child(_toggle)

	_canvas = MinimapCanvas.new()
	(_canvas as MinimapCanvas).board = self
	_canvas.name = "MinimapCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(_canvas)
#endregion


#region Vie de la vignette
func _process(delta: float) -> void:
	if not _canvas or not _canvas.visible:
		return
	_since_refresh += delta
	if _since_refresh < REFRESH:
		return
	_since_refresh = 0.0
	_reload()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_M:
		toggle()
		get_viewport().set_input_as_handled()


## Montre ou masque la vignette (le bouton, lui, reste : sinon on ne pourrait
## plus la rappeler).
func toggle() -> void:
	if not _canvas:
		return
	_canvas.visible = not _canvas.visible
	if _canvas.visible:
		_reload()


## Relit le plateau et redimensionne la vignette en conséquence.
func _reload() -> void:
	if not level or not is_instance_valid(level):
		return
	_state = snapshot(level)
	if not _canvas:
		return

	var dims: Vector2i = _state.get("size", Vector2i.ZERO)
	var side: float = cell_side(dims)
	_canvas.custom_minimum_size = Vector2(
		dims.x * side + 2.0 * PADDING, dims.y * side + 2.0 * PADDING)
	_canvas.queue_redraw()


## Dessine le plateau sur [param canvas] — appelé par lui, depuis son `_draw`.
func draw_map(canvas: Control) -> void:
	var dims: Vector2i = _state.get("size", Vector2i.ZERO)
	if dims.x <= 0 or dims.y <= 0:
		return

	var side: float = cell_side(dims)
	var frame := Rect2(Vector2.ZERO, canvas.size)
	canvas.draw_rect(frame, C_PANEL)
	canvas.draw_rect(frame, C_EDGE, false, 1.0)

	var terrain: PackedInt32Array = _state.get("terrain", PackedInt32Array())
	for row: int in dims.y:
		for col: int in dims.x:
			var index: int = row * dims.x + col
			if index >= terrain.size():
				continue
			var color: Color = terrain_color(terrain[index])
			if color.a <= 0.0:
				continue
			canvas.draw_rect(Rect2(
				PADDING + col * side, PADDING + row * side, side, side), color)

	# Les pions par-dessus : un point cerné de noir, pour rester lisible sur la
	# neige comme sur la fosse.
	var radius: float = maxf(side * 0.36, 1.5)
	for pawn: Dictionary in _state.get("pawns", []):
		var cell: Vector2i = pawn["cell"]
		if cell.x >= dims.x or cell.y >= dims.y:
			continue
		var center := Vector2(
			PADDING + (cell.x + 0.5) * side, PADDING + (cell.y + 0.5) * side)
		canvas.draw_circle(center, radius + 1.0, Color(0, 0, 0, 0.7))
		canvas.draw_circle(center, radius, TeamDataClass.side_color(int(pawn["side"])))
#endregion


## La toile : elle ne sait rien du jeu, elle rend la main à la minimap.
##
## Un nœud à part parce que `_draw` n'existe que sur un [Control], et que la
## minimap est un [CanvasLayer] — c'est lui qui la maintient au-dessus du monde
## 3D quelle que soit la caméra.
class MinimapCanvas extends Control:
	var board: BattleMinimap = null

	func _draw() -> void:
		if board and is_instance_valid(board):
			board.draw_map(self)
