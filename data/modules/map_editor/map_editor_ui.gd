class_name MapEditorUI
extends CanvasLayer
## Interface de l'éditeur de cartes : barre d'outils, palette, panneaux.
##
## Ne connaît ni la carte ni la scène 3D — elle émet des intentions, et
## [MapEditorLevel] décide quoi en faire. C'est ce qui permet de tester la
## logique d'édition ([MapDocument]) sans jamais instancier cette interface.

signal tool_selected(tool_id: int)


## Côté du pinceau, en cases (1, 3 ou 5).
signal brush_size_changed(size: int)


## Le clic peint-il la zone d'un seul tenant au lieu de quelques cases ?
signal fill_mode_changed(on: bool)


signal unit_picked(path: String)
## Niveau retenu pour les prochaines unités posées.
signal unit_level_changed(level: int)
## Le joueur veut sortir sa carte du jeu, ou en faire entrer une.
signal export_requested(to_clipboard: bool, path: String)
signal import_requested(from_clipboard: bool, path: String)
signal save_requested()
signal load_requested(path: String)
signal delete_requested(path: String)
signal new_requested(map_name: String, size: Vector2i)
signal test_requested(with_ciel: bool)
## Le joueur ouvre les réglages : le niveau répond par [method open_settings]
## avec les valeurs de la carte en cours (l'interface ne connaît pas le document).
signal settings_requested()
## Un seul signal pour tout le panneau de réglages : « Appliquer » est un seul
## geste, qui doit se défaire d'un seul coup d'annulation.
signal settings_changed(map_name: String, slots: int, size: Vector2i, objective: Dictionary)
signal undo_requested()
signal redo_requested()
signal back_requested()

const OBJ = preload("res://data/models/campaign/objective.gd")
const LIBRARY = preload("res://data/services/campaign/map_library.gd")

const C_BG: Color = Color("#12101f")
const C_PANEL: Color = Color("#1d1a2e")
const C_GOLD: Color = Color("#f5c842")
const C_TEXT: Color = Color("#e8e6f0")
const C_DIM: Color = Color(1, 1, 1, 0.5)

## Outils de l'éditeur.
##
## **Un outil de terrain porte le numéro du terrain qu'il peint** — c'est ce qui
## permet à l'éditeur de le poser sans table de correspondance. Les autres outils
## commencent à 100 : la place est donc libre pour les terrains à venir, sans
## renuméroter ni rendre illisibles les cartes déjà enregistrées.
##
## La fosse n'y est plus depuis le 2026-08-16 : un trou noir infranchissable que
## rien ne distinguait d'un mur au jeu, et que le gouffre d'eau dit mieux. Le
## terrain existe toujours dans [MapData] — les numéros ne bougent pas, sans quoi
## toute carte enregistrée changerait de sens —, il n'est simplement plus
## proposé au pinceau.
enum Tool {
	GRASS = MapData.TerrainType.GRASS,
	FOREST = MapData.TerrainType.FOREST,
	MOUNTAIN = MapData.TerrainType.MOUNTAIN,
	WATER = MapData.TerrainType.WATER,
	PATH = MapData.TerrainType.PATH,
	WALL = MapData.TerrainType.WALL,
	VILLAGE = MapData.TerrainType.VILLAGE,
	FORT = MapData.TerrainType.FORT,
	GATE = MapData.TerrainType.GATE,
	RUINS = MapData.TerrainType.RUINS,
	TOWER = MapData.TerrainType.TOWER,
	BRIDGE = MapData.TerrainType.BRIDGE,
	SAND = MapData.TerrainType.SAND,
	SNOW = MapData.TerrainType.SNOW,
	SWAMP = MapData.TerrainType.SWAMP,

	RAISE = 100, LOWER = 101,
	UNIT_PLAYER = 110, UNIT_OPPONENT = 111, ERASE = 112,
	DEPLOY = 120, SEIZE = 121,
}

## Un outil de terrain, ou un des autres ?
static func is_terrain_tool(tool_id: int) -> bool:
	return MapData.TERRAINS.has(tool_id)


## Pictogramme de chaque terrain. Le nom, lui, vient de [MapData] : un terrain
## s'appelle pareil dans la palette, sur la fiche d'unité et dans le journal.
const TERRAIN_ICONS: Dictionary = {
	MapData.TerrainType.GRASS: "🌿",
	MapData.TerrainType.FOREST: "🌲",
	MapData.TerrainType.MOUNTAIN: "⛰️",
	MapData.TerrainType.WATER: "💧",
	MapData.TerrainType.PATH: "🛤️",
	MapData.TerrainType.WALL: "🧱",
	MapData.TerrainType.VILLAGE: "🏘️",
	MapData.TerrainType.FORT: "🏰",
	MapData.TerrainType.GATE: "🚪",
	MapData.TerrainType.RUINS: "🏛️",
	MapData.TerrainType.TOWER: "🗼",
	MapData.TerrainType.BRIDGE: "🌉",
	MapData.TerrainType.SAND: "🏜️",
	MapData.TerrainType.SNOW: "❄️",
	MapData.TerrainType.SWAMP: "🌾",
}

## Première ligne de la palette : ce que personne n'a bâti.
const NATURE_TOOLS: Array[int] = [
	Tool.GRASS, Tool.FOREST, Tool.SWAMP, Tool.WATER,
	Tool.SAND, Tool.SNOW, Tool.MOUNTAIN,
]

## Deuxième ligne : ce qui se construit — l'héroïc fantasy tient là-dedans.
const BUILT_TOOLS: Array[int] = [
	Tool.PATH, Tool.BRIDGE, Tool.VILLAGE, Tool.FORT,
	Tool.RUINS, Tool.GATE, Tool.TOWER, Tool.WALL,
]

## Dossiers de fiches livrées avec le jeu, par camp par défaut.
##
## Le roster était une liste de neuf chemins écrite ici : ajouter une unité au
## jeu demandait de venir modifier l'interface, et les personnages écrits dans
## l'éditeur de personnages n'y figuraient pas du tout. On lit le disque.
const UNIT_DIRS: Dictionary = {
	"player": "res://data/models/world/stats/hero",
	"opponent": "res://data/models/world/stats/mob",
}

var _status: Label = null
var _tool_label: Label = null
var _unit_label: Label = null
var _errors: RichTextLabel = null
var _panel_host: Control = null
var _tool_buttons: Dictionary = {}
var _undo_button: Button = null
var _redo_button: Button = null


var _brush_button: Button = null


var _fill_button: Button = null


## Côté du pinceau affiché sur son bouton — le niveau en est la source.
var _brush_size: int = 1


func _ready() -> void:
	layer = 20
	_build_top_bar()
	_build_palette()
	_build_status()
	_panel_host = Control.new()
	_panel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_host)


#region Retours d'information
## Message d'état sous la palette.
func show_status(message: String, color: Color = C_DIM) -> void:
	if _status:
		_status.text = message
		_status.add_theme_color_override("font_color", color)


## Outil courant, affiché en clair pour éviter de peindre par erreur.
func show_tool(tool_id: int, unit_name: String = "") -> void:
	if _tool_label:
		_tool_label.text = "Outil : %s" % tool_name(tool_id)
	if _unit_label:
		_unit_label.text = "Unité : %s" % (unit_name if not unit_name.is_empty() else "—")
	for id: int in _tool_buttons:
		var btn: Button = _tool_buttons[id]
		btn.button_pressed = (id == tool_id)


## Liste des problèmes qui empêchent la carte d'être jouée (vide = tout va bien).
func show_errors(errors: Array) -> void:
	if not _errors:
		return
	if errors.is_empty():
		_errors.text = "[color=#7ddf8f]✔ Carte jouable[/color]"
		return
	var lines: Array[String] = ["[color=#ff9c8a]%d point(s) à corriger :[/color]" % errors.size()]
	for e: String in errors:
		lines.append("• %s" % e)
	_errors.text = "\n".join(lines)


## Grise « annuler » / « rétablir » quand il n'y a rien à défaire ni à refaire.
func show_history(can_undo: bool, can_redo: bool) -> void:
	if _undo_button:
		_undo_button.disabled = not can_undo
		_undo_button.modulate = Color.WHITE if can_undo else Color(1, 1, 1, 0.4)
	if _redo_button:
		_redo_button.disabled = not can_redo
		_redo_button.modulate = Color.WHITE if can_redo else Color(1, 1, 1, 0.4)


static func tool_name(tool_id: int) -> String:
	match tool_id:
		Tool.RAISE: return "⬆ Élever le terrain"
		Tool.LOWER: return "⬇ Abaisser le terrain"
		Tool.UNIT_PLAYER: return "🟢 Poser une unité du joueur"
		Tool.UNIT_OPPONENT: return "🔴 Poser un adversaire"
		Tool.ERASE: return "🗑 Effacer une unité"
		Tool.DEPLOY: return "🪧 Case de déploiement"
		Tool.SEIZE: return "⚑ Point de commandement"
		_:
			return terrain_label(tool_id) if is_terrain_tool(tool_id) else "—"


## Nom d'un terrain sur un bouton : son pictogramme et son nom français.
static func terrain_label(terrain: int) -> String:
	return "%s %s" % [str(TERRAIN_ICONS.get(terrain, "▪")), MapData.type_label(terrain)]


## Ce que dit un terrain de plus que sa couleur : ce qu'il coûte, ce qu'il donne.
##
## Le même résumé qu'au survol d'une case en bataille — c'est [MapData] qui
## l'écrit, pour que le joueur lise la même chose en dessinant et en jouant.
static func terrain_tooltip(terrain: int) -> String:
	return MapData.type_summary(terrain)


#endregion


#region Barre du haut
func _build_top_bar() -> void:
	var bar := Panel.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 46
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)

	var title := Label.new()
	title.text = "🗺  ÉDITEUR DE CARTES"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", C_GOLD)
	title.position = Vector2(14, 12)
	bar.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -1000
	row.offset_right = -12
	row.offset_top = 8
	row.offset_bottom = 38
	row.alignment = BoxContainer.ALIGNMENT_END
	bar.add_child(row)

	_undo_button = _action("↶ Annuler", Color("#3b3b52"),
		func() -> void: undo_requested.emit(), 74.0)
	_undo_button.tooltip_text = "Annuler le dernier changement (Ctrl+Z)"
	row.add_child(_undo_button)

	_redo_button = _action("↷ Rétablir", Color("#3b3b52"),
		func() -> void: redo_requested.emit(), 78.0)
	_redo_button.tooltip_text = "Rétablir le changement annulé (Ctrl+Maj+Z)"
	row.add_child(_redo_button)
	show_history(false, false)

	row.add_child(VSeparator.new())
	row.add_child(_action("🆕 Nouvelle", Color("#e67e22"), _open_new_panel))
	row.add_child(_action("📂 Ouvrir", Color("#256eb8"), _open_library_panel))
	row.add_child(_action("🔗 Partager", Color("#1f7a8c"), _open_share_panel))
	row.add_child(_action("⚙ Réglages", Color("#5d4e8c"),
		func() -> void: settings_requested.emit()))
	row.add_child(_action("💾 Enregistrer", Color("#1b6b3a"),
		func() -> void: save_requested.emit()))
	row.add_child(_action("▶ Tester", Color("#9b59b6"), _open_test_panel))
	row.add_child(_action("↩ Retour", Color("#444455"),
		func() -> void: back_requested.emit()))


func _action(text: String, color: Color, callback: Callable, width: float = 108.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 30)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.22)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(callback)
	return btn
#endregion


#region Palette
## Trois rangées : la nature, les constructions, puis ce qui se pose dessus.
##
## Une seule rangée tenait tant qu'il y avait sept terrains. À seize, elle
## dépassait de l'écran — et mélangeait de toute façon un lac et un point de
## commandement, qui ne sont pas la même sorte de geste.
func _build_palette() -> void:
	var palette := VBoxContainer.new()
	palette.add_theme_constant_override("separation", 4)
	palette.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	palette.offset_top = -156
	palette.offset_bottom = -8
	palette.offset_left = -500
	palette.offset_right = 500
	palette.alignment = BoxContainer.ALIGNMENT_END
	add_child(palette)

	var nature: HBoxContainer = _palette_row(palette)
	for terrain: int in NATURE_TOOLS:
		nature.add_child(_terrain_button(terrain))

	var built: HBoxContainer = _palette_row(palette)
	for terrain: int in BUILT_TOOLS:
		built.add_child(_terrain_button(terrain))

	var tools: HBoxContainer = _palette_row(palette)
	tools.add_child(_tool_button(Tool.RAISE, "⬆ Élever", Color("#6b7a8f")))
	tools.add_child(_tool_button(Tool.LOWER, "⬇ Abaisser", Color("#4a5568")))
	tools.add_child(VSeparator.new())
	tools.add_child(_build_brush_button())
	tools.add_child(_build_fill_button())
	tools.add_child(VSeparator.new())
	tools.add_child(_tool_button(Tool.UNIT_PLAYER, "🟢 Joueur", Color("#1b6b3a")))
	tools.add_child(_tool_button(Tool.UNIT_OPPONENT, "🔴 Ennemi", Color("#b71c1c")))
	tools.add_child(_tool_button(Tool.ERASE, "🗑 Effacer", Color("#444455")))
	tools.add_child(VSeparator.new())
	tools.add_child(_tool_button(Tool.DEPLOY, "🪧 Départ", Color("#1f9c8e")))
	tools.add_child(_tool_button(Tool.SEIZE, "⚑ Point", Color("#b8860b")))


func _palette_row(host: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	host.add_child(row)
	return row


## Bouton d'un terrain : sa teinte réelle, son nom, et ce qu'il vaut au combat.
func _terrain_button(terrain: int) -> Button:
	var btn: Button = _tool_button(terrain, terrain_label(terrain), _terrain_color(terrain))
	btn.tooltip_text = terrain_tooltip(terrain)
	return btn


## Teinte du bouton : celle que la case prendra vraiment, prise au décor.
static func _terrain_color(terrain: int) -> Color:
	return Color(str(TacticsScenery.TERRAIN_COLORS.get(terrain, "#4a8c3f")))


func _tool_button(tool_id: int, text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(76, 44)
	btn.add_theme_font_size_override("font_size", 10)
	# La neige et le sable sont plus clairs que le texte blanc : sur ces
	# boutons-là, c'est l'encre du fond de l'éditeur qui se lit.
	btn.add_theme_color_override("font_color",
		C_BG if color.get_luminance() > 0.55 else Color.WHITE)
	btn.clip_text = true

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.22)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = color.lightened(0.35)
	pressed.border_width_bottom = 3
	pressed.border_color = C_GOLD
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.pressed.connect(func() -> void: tool_selected.emit(tool_id))
	_tool_buttons[tool_id] = btn
	return btn


## Taille du pinceau : un bouton qui tourne, 1 → 3 → 5 → 1.
##
## Trois boutons pour trois tailles auraient pris la place de trois terrains,
## pour un réglage qu'on change en passant.
func _build_brush_button() -> Button:
	_brush_button = _action("▦ Pinceau 1×1", Color("#3b3b52"), func() -> void:
		var sizes: Array[int] = MapDocument.BRUSH_SIZES
		var next: int = sizes[(maxi(0, sizes.find(_brush_size)) + 1) % sizes.size()]
		brush_size_changed.emit(next), 92.0)
	_brush_button.custom_minimum_size = Vector2(92, 44)
	_brush_button.tooltip_text = "Nombre de cases peintes d'un coup (1, 3 ou 5 de côté)"
	return _brush_button


## Remplissage : le clic peint toute l'étendue d'un seul tenant.
func _build_fill_button() -> Button:
	_fill_button = Button.new()
	_fill_button.text = "🪣 Remplir"
	_fill_button.toggle_mode = true
	_fill_button.custom_minimum_size = Vector2(80, 44)
	_fill_button.add_theme_font_size_override("font_size", 10)
	_fill_button.add_theme_color_override("font_color", Color.WHITE)
	_fill_button.tooltip_text = "Un clic peint toute la zone de même terrain, d'un seul tenant"

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#3b3b52")
	style.set_corner_radius_all(5)
	_fill_button.add_theme_stylebox_override("normal", style)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#6b5a1f")
	pressed.border_width_bottom = 3
	pressed.border_color = C_GOLD
	_fill_button.add_theme_stylebox_override("pressed", pressed)
	_fill_button.add_theme_stylebox_override("hover_pressed", pressed)

	_fill_button.toggled.connect(func(on: bool) -> void: fill_mode_changed.emit(on))
	return _fill_button


## Montre la taille de pinceau retenue par le niveau.
func show_brush(size: int) -> void:
	_brush_size = size
	if _brush_button:
		_brush_button.text = "▦ Pinceau %d×%d" % [size, size]


func _build_status() -> void:
	_tool_label = Label.new()
	_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tool_label.add_theme_font_size_override("font_size", 12)
	_tool_label.add_theme_color_override("font_color", C_GOLD)
	_tool_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tool_label.offset_top = -176
	_tool_label.offset_bottom = -160
	add_child(_tool_label)

	_unit_label = Label.new()
	_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unit_label.add_theme_font_size_override("font_size", 11)
	_unit_label.add_theme_color_override("font_color", C_DIM)
	_unit_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_unit_label.offset_top = -192
	_unit_label.offset_bottom = -178
	add_child(_unit_label)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", C_DIM)
	_status.position = Vector2(14, 54)
	add_child(_status)

	# Bilan de validation, en permanence : une carte injouable ne doit pas se
	# découvrir au moment de l'enregistrer.
	_errors = RichTextLabel.new()
	_errors.bbcode_enabled = true
	_errors.fit_content = true
	_errors.scroll_active = false
	_errors.add_theme_font_size_override("normal_font_size", 11)
	_errors.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_errors.offset_left = 14
	_errors.offset_top = 76
	_errors.offset_right = 400
	_errors.offset_bottom = 300
	_errors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_errors)


## Liste des unités posables du camp demandé : `[{path, name, custom}]`.
##
## Deux sources, dans cet ordre : les fiches livrées avec le jeu, puis les
## personnages écrits par le joueur. Ces derniers sont proposés **aux deux
## camps** — rien ne dit qu'une créature de son cru soit un allié plutôt qu'un
## adversaire, et c'est justement ce qu'on vient choisir ici.
static func roster_of(team: String) -> Array:
	var out: Array = []

	var dir := DirAccess.open(str(UNIT_DIRS.get(team, "")))
	if dir:
		var files: PackedStringArray = dir.get_files()
		files.sort()
		for file_name: String in files:
			# Un `.tres` exporté est livré en `.remap` : c'est le nom d'origine
			# qui doit être chargé, sinon le roster est vide dans le jeu installé.
			var clean: String = file_name.trim_suffix(".remap")
			if not clean.ends_with(".tres"):
				continue
			var path: String = "%s/%s" % [str(UNIT_DIRS[team]), clean]
			out.append({
				"path": path,
				"name": MapDocument.unit_display_name(path),
				"custom": false,
			})

	for entry: Dictionary in UnitLibrary.list_units():
		if not bool(entry.get("valid", false)):
			continue
		out.append({
			"path": UnitLibrary.path_for(str(entry["slug"])),
			"name": str(entry["name"]),
			"custom": true,
		})

	return out
#endregion


#region Panneaux
## Ferme le panneau ouvert, s'il y en a un.
func close_panel() -> void:
	for child in _panel_host.get_children():
		child.queue_free()


## Un panneau modal centré, prêt à recevoir des lignes.
func _open_panel(title_text: String, width: float = 460.0) -> VBoxContainer:
	close_panel()

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close_panel())
	_panel_host.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -width / 2.0
	panel.offset_right = width / 2.0
	panel.offset_top = -220
	panel.offset_bottom = 220
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.set_corner_radius_all(10)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = C_GOLD
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	_panel_host.add_child(panel)

	var scroll := ScrollContainer.new()
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var heading := Label.new()
	heading.text = title_text
	heading.add_theme_font_size_override("font_size", 19)
	heading.add_theme_color_override("font_color", C_GOLD)
	box.add_child(heading)
	return box


func _open_new_panel() -> void:
	var box: VBoxContainer = _open_panel("Nouvelle carte")

	var name_input := LineEdit.new()
	name_input.placeholder_text = "Nom de la carte"
	name_input.text = "Ma carte"
	box.add_child(_labelled("Nom", name_input))

	var cols := SpinBox.new()
	cols.min_value = MapDocument.MIN_SIZE.x
	cols.max_value = MapDocument.MAX_SIZE.x
	cols.value = 16
	box.add_child(_labelled("Colonnes", cols))

	var rows := SpinBox.new()
	rows.min_value = MapDocument.MIN_SIZE.y
	rows.max_value = MapDocument.MAX_SIZE.y
	rows.value = 10
	box.add_child(_labelled("Lignes", rows))

	box.add_child(_note("Une nouvelle carte remplace celle en cours d'édition. "
		+ "Pense à enregistrer avant."))

	box.add_child(_confirm("Créer", func() -> void:
		new_requested.emit(name_input.text, Vector2i(int(cols.value), int(rows.value)))
		close_panel()))


func _open_settings_panel(current_name: String = "", slots: int = 4,
		objective: Dictionary = {}, size: Vector2i = Vector2i(16, 10)) -> void:
	var box: VBoxContainer = _open_panel("Réglages de la carte")

	var name_input := LineEdit.new()
	name_input.text = current_name
	name_input.placeholder_text = "Nom de la carte"
	box.add_child(_labelled("Nom", name_input))

	var cols := SpinBox.new()
	cols.min_value = MapDocument.MIN_SIZE.x
	cols.max_value = MapDocument.MAX_SIZE.x
	cols.value = size.x
	box.add_child(_labelled("Colonnes", cols))

	var rows := SpinBox.new()
	rows.min_value = MapDocument.MIN_SIZE.y
	rows.max_value = MapDocument.MAX_SIZE.y
	rows.value = size.y
	box.add_child(_labelled("Lignes", rows))

	box.add_child(_note("Agrandir ajoute de l'herbe sur les bords. Rétrécir oublie "
		+ "ce qui sort de la grille — unités, cases de départ, point de "
		+ "commandement. Ça s'annule (Ctrl+Z)."))

	var slots_input := SpinBox.new()
	slots_input.min_value = 1
	slots_input.max_value = 12
	slots_input.value = slots
	box.add_child(_labelled("Unités déployables", slots_input))

	var kinds := OptionButton.new()
	var kind_ids: Array[int] = [
		OBJ.Kind.ROUT, OBJ.Kind.DEFEAT_BOSS, OBJ.Kind.SURVIVE,
		OBJ.Kind.PROTECT, OBJ.Kind.SEIZE,
	]
	for i: int in kind_ids.size():
		kinds.add_item(OBJ.kind_name(kind_ids[i]), i)
	var current_kind: int = int(objective.get("kind", OBJ.Kind.ROUT))
	kinds.select(maxi(0, kind_ids.find(current_kind)))
	box.add_child(_labelled("Objectif", kinds))

	var turns := SpinBox.new()
	turns.min_value = 1
	turns.max_value = 40
	turns.value = int(objective.get("turns", 8))
	box.add_child(_labelled("Tours (survie / protection)", turns))

	var target := LineEdit.new()
	target.text = str(objective.get("target", ""))
	target.placeholder_text = "Nom affiché de l'unité visée"
	box.add_child(_labelled("Cible (commandant / protégée)", target))

	box.add_child(_note("Le point de commandement se pose sur la carte avec l'outil ⚑ : "
		+ "choisir « prendre le point » ici sans le poser laisse la carte injouable."))

	box.add_child(_confirm("Appliquer", func() -> void:
		settings_changed.emit(name_input.text, int(slots_input.value),
			Vector2i(int(cols.value), int(rows.value)), {
				"kind": kind_ids[kinds.get_selected_id()],
				"turns": int(turns.value),
				"target": target.text.strip_edges(),
				"col": int(objective.get("col", 0)),
				"row": int(objective.get("row", 0)),
			})
		close_panel()))


## Ouvre les réglages avec les valeurs de la carte en cours.
func open_settings(current_name: String, slots: int, objective: Dictionary,
		size: Vector2i = Vector2i(16, 10)) -> void:
	_open_settings_panel(current_name, slots, objective, size)


func _open_library_panel() -> void:
	var box: VBoxContainer = _open_panel("Cartes enregistrées", 560.0)
	var maps: Array = LIBRARY.list_maps()

	if maps.is_empty():
		box.add_child(_note("Aucune carte pour l'instant. Dessine-en une et enregistre-la : "
			+ "elle atterrira dans le dossier `maps` de tes données de jeu."))
		return

	for entry: Dictionary in maps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.text = "%s   %dx%d · %d unité(s) %s" % [
			str(entry["name"]), entry["grid"].x, entry["grid"].y, int(entry["units"]),
			"" if bool(entry["playable"]) else "  ⚠ injouable",
		]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", C_TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var path: String = str(entry["path"])
		var open_btn := _action("Ouvrir", Color("#256eb8"), func() -> void:
			load_requested.emit(path)
			close_panel())
		open_btn.custom_minimum_size = Vector2(88, 28)
		row.add_child(open_btn)

		var del_btn := _action("Supprimer", Color("#7a2020"), func() -> void:
			delete_requested.emit(path)
			_open_library_panel())
		del_btn.custom_minimum_size = Vector2(88, 28)
		row.add_child(del_btn)

		box.add_child(row)


## Choix de l'unité à poser, ouvert quand on prend un outil de placement.
##
## Le niveau se règle ici, avant de choisir : c'est un réglage du pinceau, pas
## de la case. On peut donc poser six squelettes de niveau 8 d'affilée sans
## rouvrir ce panneau entre chacun.
func open_unit_picker(team: String, level: int = 1) -> void:
	var box: VBoxContainer = _open_panel(
		"Unité à poser — %s" % ("camp du joueur" if team == "player" else "camp adverse")
	)

	var spin := SpinBox.new()
	spin.min_value = MapDocument.MIN_LEVEL
	spin.max_value = MapDocument.MAX_LEVEL
	spin.value = clampi(level, MapDocument.MIN_LEVEL, MapDocument.MAX_LEVEL)
	spin.custom_minimum_size = Vector2(110, 30)
	box.add_child(_labelled("Niveau des unités posées", spin))
	box.add_child(_note("Une unité posée au-dessus de 1 monte réellement les "
		+ "échelons, par les croissances de sa classe. Le tirage est fixe : la "
		+ "même carte donne toujours la même unité."))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	box.add_child(scroll)

	var roster: Array = roster_of(team)
	if roster.is_empty():
		list.add_child(_note("Aucune unité disponible pour ce camp."))
		return

	for entry: Dictionary in roster:
		var path: String = str(entry["path"])
		var label: String = str(entry["name"])
		if label.is_empty():
			label = path.get_file()
		if bool(entry.get("custom", false)):
			label = "✎ %s" % label  # Écrit par le joueur
		var btn := _confirm(label, func() -> void:
			unit_level_changed.emit(int(spin.value))
			unit_picked.emit(path)
			close_panel())
		list.add_child(btn)


## Sortir une carte du jeu, ou en faire entrer une.
##
## Le format d'échange existait depuis le début — [MapDocument] se sérialise en
## JSON lisible, exprès pour qu'on puisse envoyer une carte à quelqu'un. Il n'y
## avait simplement aucun moyen de le faire depuis le jeu : il fallait aller
## chercher le fichier dans `user://maps/` à la main.
func _open_share_panel() -> void:
	var box: VBoxContainer = _open_panel("Partager une carte", 520.0)
	box.add_child(_note("Une carte est un fichier JSON lisible. L'envoyer à "
		+ "quelqu'un suffit à la lui faire jouer — il n'y a rien d'autre dedans."))

	box.add_child(_confirm("📋  Copier la carte dans le presse-papiers", func() -> void:
		export_requested.emit(true, "")
		close_panel()))
	box.add_child(_confirm("📥  Remplacer par la carte du presse-papiers", func() -> void:
		import_requested.emit(true, "")
		close_panel()))

	box.add_child(HSeparator.new())

	box.add_child(_confirm("📤  Exporter vers un fichier…", func() -> void:
		_open_file_dialog(FileDialog.FILE_MODE_SAVE_FILE,
			func(path: String) -> void: export_requested.emit(false, path))))
	box.add_child(_confirm("📂  Importer un fichier…", func() -> void:
		_open_file_dialog(FileDialog.FILE_MODE_OPEN_FILE,
			func(path: String) -> void: import_requested.emit(false, path))))

	box.add_child(_note("Importer remplace la carte en cours. L'annulation "
		+ "(Ctrl+Z) la ramène si c'était une erreur."))


## Un sélecteur de fichier natif, sur tout le disque — une carte reçue d'un ami
## est dans les téléchargements, pas dans le dossier du jeu.
func _open_file_dialog(mode: FileDialog.FileMode, on_chosen: Callable) -> void:
	close_panel()
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.json ; Carte Ciel Emblem"])
	dialog.title = "Exporter la carte" if mode == FileDialog.FILE_MODE_SAVE_FILE \
		else "Importer une carte"
	dialog.file_selected.connect(func(path: String) -> void:
		on_chosen.call(path)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(820, 560))


func _open_test_panel() -> void:
	var box: VBoxContainer = _open_panel("Tester la carte")
	box.add_child(_note("La carte se joue comme un chapitre : même objectif, même "
		+ "déploiement, même IA. Rien n'est enregistré dans ta campagne."))

	box.add_child(_confirm("Jouer contre l'IA locale", func() -> void:
		test_requested.emit(false)
		close_panel()))
	box.add_child(_confirm("Jouer contre Ciel", func() -> void:
		test_requested.emit(true)
		close_panel()))


#region Briques d'interface
func _labelled(text: String, control: Control) -> Control:
	var row := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", C_DIM)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _note(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", C_DIM)
	return label


func _confirm(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 38)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2d6a4f")
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)
	btn.pressed.connect(callback)
	return btn
#endregion
#endregion
