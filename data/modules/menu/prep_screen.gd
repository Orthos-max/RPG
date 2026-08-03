extends Control
## Écran de préparation d'un chapitre : intro, objectif, sélection des unités.
##
## Équivalent minimal de la « prep screen » de Fire Emblem : on lit le contexte,
## on choisit qui part au combat (dans la limite des places), puis on lance.

signal battle_requested()
signal back_requested()

const C_BG := Color("#141026")
const C_PANEL := Color("#16213e")
const C_ACCENT := Color("#e94560")
const C_GOLD := Color("#f5c842")
const C_TEXT := Color("#eeeeee")
const C_BUTTON := Color("#0f3460")

var chapter: ChapterData = null

var _selected: Array = []
var _slots_label: Label
var _unit_rows: VBoxContainer
var _start_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var campaign: Node = get_node_or_null("/root/Campaign")
	if campaign:
		_selected = campaign.deployment.duplicate()
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = chapter.title if chapter else "Chapitre"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", C_GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30
	title.offset_bottom = 70
	add_child(title)

	var objective := Label.new()
	objective.text = "🎯 %s   |   %s" % [
		chapter.objective_text() if chapter else "—",
		chapter.subtitle if chapter else "",
	]
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.add_theme_font_size_override("font_size", 15)
	objective.add_theme_color_override("font_color", C_ACCENT)
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective.offset_top = 72
	objective.offset_bottom = 98
	add_child(objective)

	# Introduction narrative
	var intro := Label.new()
	intro.text = "\n".join(chapter.intro_lines) if chapter else ""
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 14)
	intro.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	intro.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	intro.offset_left = 120
	intro.offset_right = -120
	intro.offset_top = 108
	intro.offset_bottom = 190
	add_child(intro)

	_slots_label = Label.new()
	_slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slots_label.add_theme_font_size_override("font_size", 14)
	_slots_label.add_theme_color_override("font_color", C_GOLD)
	_slots_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_slots_label.offset_top = 196
	_slots_label.offset_bottom = 220
	add_child(_slots_label)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 160
	scroll.offset_right = -160
	scroll.offset_top = 228
	scroll.offset_bottom = -110
	add_child(scroll)

	_unit_rows = VBoxContainer.new()
	_unit_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_unit_rows)

	var buttons := HBoxContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.offset_top = -90
	buttons.offset_bottom = -30
	buttons.add_theme_constant_override("separation", 16)
	add_child(buttons)

	var back := _make_button("← Retour", false)
	back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back)

	_start_button = _make_button("⚔️  Lancer la bataille", true)
	_start_button.pressed.connect(_on_start)
	buttons.add_child(_start_button)

	_refresh()


func _refresh() -> void:
	var campaign: Node = get_node_or_null("/root/Campaign")
	if not campaign or not chapter:
		return

	for child in _unit_rows.get_children():
		child.queue_free()

	for unit: Dictionary in campaign.available_units():
		_unit_rows.add_child(_make_unit_row(unit, campaign))

	# Unités tombées : affichées grisées, pour que la perte se voie.
	for unit: Dictionary in campaign.roster:
		if not bool(unit.get("alive", true)):
			var lost := Label.new()
			lost.text = "☠ %s — tombé au combat" % str(unit.get("name", "?"))
			lost.add_theme_font_size_override("font_size", 13)
			lost.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
			_unit_rows.add_child(lost)

	_slots_label.text = "Déploiement : %d / %d place(s)   —   Or : %d   —   Niveau conseillé : %d" % [
		_selected.size(), chapter.deploy_slots, campaign.gold, chapter.recommended_level
	]
	_start_button.disabled = _selected.is_empty()


func _make_unit_row(unit: Dictionary, campaign: Node) -> Control:
	var id: String = str(unit.get("id", ""))
	var row := Button.new()
	row.toggle_mode = true
	row.button_pressed = id in _selected
	row.custom_minimum_size = Vector2(0, 42)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = "%s  %-14s Lv.%-3d %-14s PV %d/%d  MOV %d" % [
		"✔" if row.button_pressed else "  ",
		str(unit.get("name", "?")),
		int(unit.get("level", 1)),
		campaign.unit_class_name(unit),
		int(unit.get("hp", 0)), int(unit.get("max_hp", 0)),
		int(unit.get("movement", 0)),
	]
	row.add_theme_font_size_override("font_size", 14)

	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	row.add_theme_stylebox_override("normal", style)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = C_BUTTON
	pressed.border_width_left = 4
	pressed.border_color = C_GOLD
	row.add_theme_stylebox_override("pressed", pressed)
	row.add_theme_color_override("font_color", C_TEXT)

	row.toggled.connect(func(on: bool) -> void: _on_unit_toggled(id, on))
	return row


func _on_unit_toggled(id: String, on: bool) -> void:
	if on:
		if _selected.size() >= chapter.deploy_slots:
			_refresh()  # Places épuisées : on annule visuellement la sélection.
			return
		if not id in _selected:
			_selected.append(id)
	else:
		_selected.erase(id)
	_refresh()


func _on_start() -> void:
	var campaign: Node = get_node_or_null("/root/Campaign")
	if campaign:
		campaign.set_deployment(_selected)
	battle_requested.emit()


func _make_button(text: String, accent: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(240, 46)
	btn.add_theme_font_size_override("font_size", 17)
	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if accent else C_BUTTON
	style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", C_TEXT)
	return btn
