class_name MapEditorUI
extends CanvasLayer
## Interface de l'éditeur de cartes : barre d'outils, palette, panneaux.
##
## Ne connaît ni la carte ni la scène 3D — elle émet des intentions, et
## [MapEditorLevel] décide quoi en faire. C'est ce qui permet de tester la
## logique d'édition ([MapDocument]) sans jamais instancier cette interface.

signal tool_selected(tool_id: int)
signal unit_picked(path: String)
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

## Outils, dans l'ordre de la palette
enum Tool {
	GRASS = 0, FOREST = 1, MOUNTAIN = 2, WATER = 3, PATH = 4, WALL = 5, PIT = 6,
	RAISE = 7, LOWER = 8,
	UNIT_PLAYER = 9, UNIT_OPPONENT = 10, ERASE = 11,
	DEPLOY = 12, SEIZE = 13,
}

const TERRAIN_LABELS: Array[String] = [
	"🌿 Herbe", "🌲 Forêt", "⛰️ Montagne", "💧 Eau", "🛤️ Chemin", "🧱 Mur", "🕳️ Fosse",
]
const TERRAIN_COLORS: Array[Color] = [
	Color("#4a8c3f"), Color("#2d5a1e"), Color("#8b7355"),
	Color("#2a6e8f"), Color("#c4a97d"), Color("#5a5a5a"), Color("#1a1a1a"),
]

## Unités posables, groupées par camp
const ROSTER: Array[Dictionary] = [
	{"path": "res://data/models/world/stats/hero/lord.tres", "team": "player"},
	{"path": "res://data/models/world/stats/hero/cleric.tres", "team": "player"},
	{"path": "res://data/models/world/stats/hero/archer.tres", "team": "player"},
	{"path": "res://data/models/world/stats/hero/great_knight.tres", "team": "player"},
	{"path": "res://data/models/world/stats/hero/cavalier.tres", "team": "player"},
	{"path": "res://data/models/world/stats/hero/pegasus_knight.tres", "team": "player"},
	{"path": "res://data/models/world/stats/mob/skeleton.tres", "team": "opponent"},
	{"path": "res://data/models/world/stats/mob/skeleton_cpn.tres", "team": "opponent"},
	{"path": "res://data/models/world/stats/mob/skeleton_mage.tres", "team": "opponent"},
]

var _status: Label = null
var _tool_label: Label = null
var _unit_label: Label = null
var _errors: RichTextLabel = null
var _panel_host: Control = null
var _tool_buttons: Dictionary = {}
var _undo_button: Button = null
var _redo_button: Button = null


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
			if tool_id >= 0 and tool_id < TERRAIN_LABELS.size():
				return TERRAIN_LABELS[tool_id]
			return "—"
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
	row.offset_left = -880
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
func _build_palette() -> void:
	var palette := HBoxContainer.new()
	palette.add_theme_constant_override("separation", 4)
	palette.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	palette.offset_top = -62
	palette.offset_bottom = -8
	palette.offset_left = -560
	palette.offset_right = 560
	palette.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(palette)

	for i: int in TERRAIN_LABELS.size():
		palette.add_child(_tool_button(i, TERRAIN_LABELS[i], TERRAIN_COLORS[i]))

	palette.add_child(VSeparator.new())
	palette.add_child(_tool_button(Tool.RAISE, "⬆ Élever", Color("#6b7a8f")))
	palette.add_child(_tool_button(Tool.LOWER, "⬇ Abaisser", Color("#4a5568")))

	palette.add_child(VSeparator.new())
	palette.add_child(_tool_button(Tool.UNIT_PLAYER, "🟢 Joueur", Color("#1b6b3a")))
	palette.add_child(_tool_button(Tool.UNIT_OPPONENT, "🔴 Ennemi", Color("#b71c1c")))
	palette.add_child(_tool_button(Tool.ERASE, "🗑 Effacer", Color("#444455")))

	palette.add_child(VSeparator.new())
	palette.add_child(_tool_button(Tool.DEPLOY, "🪧 Départ", Color("#1f9c8e")))
	palette.add_child(_tool_button(Tool.SEIZE, "⚑ Point", Color("#b8860b")))


func _tool_button(tool_id: int, text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(76, 46)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", Color.WHITE)

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


func _build_status() -> void:
	_tool_label = Label.new()
	_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tool_label.add_theme_font_size_override("font_size", 12)
	_tool_label.add_theme_color_override("font_color", C_GOLD)
	_tool_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tool_label.offset_top = -82
	_tool_label.offset_bottom = -66
	add_child(_tool_label)

	_unit_label = Label.new()
	_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unit_label.add_theme_font_size_override("font_size", 11)
	_unit_label.add_theme_color_override("font_color", C_DIM)
	_unit_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_unit_label.offset_top = -98
	_unit_label.offset_bottom = -84
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


## Liste des unités posables du camp demandé.
static func roster_of(team: String) -> Array:
	return ROSTER.filter(func(u: Dictionary) -> bool: return str(u["team"]) == team)
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
func open_unit_picker(team: String) -> void:
	var box: VBoxContainer = _open_panel(
		"Unité à poser — %s" % ("camp du joueur" if team == "player" else "camp adverse")
	)
	for entry: Dictionary in roster_of(team):
		var path: String = str(entry["path"])
		var label: String = MapDocument.unit_display_name(path)
		var btn := _confirm(label if not label.is_empty() else path, func() -> void:
			unit_picked.emit(path)
			close_panel())
		box.add_child(btn)


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
