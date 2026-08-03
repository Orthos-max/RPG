extends Control
## Écran-titre de Ciel Emblem — construit en code (pas de dépendance .tscn).
##
## Nouvelle partie / Continuer / Mode CielAI / Options / Extras / Quitter.
## L'écran ne connaît pas la suite : il émet des signaux que [Main] orchestre.

signal new_game_requested(difficulty: int, permadeath: bool)
signal continue_requested()
signal ciel_mode_requested()
signal hotseat_requested()
signal host_requested()
signal join_requested()
signal editor_requested()
signal fe2d_requested()
signal quit_requested()

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

const C_BG := Color("#141026")
const C_ACCENT := Color("#e94560")
const C_GOLD := Color("#f5c842")
const C_TEXT := Color("#eeeeee")
const C_BUTTON := Color("#0f3460")
const C_BUTTON_HOVER := Color("#1a508b")

var _difficulty: int = DIFF.Level.NORMAL
var _permadeath: bool = true
var _difficulty_button: Button
var _permadeath_button: Button
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "CIEL EMBLEM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", C_GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 60
	title.offset_bottom = 120
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Tactical RPG — le camp adverse est joué par une IA externe"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", C_ACCENT)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 118
	subtitle.offset_bottom = 148
	add_child(subtitle)

	var menu := VBoxContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -180
	menu.offset_right = 180
	menu.offset_top = -140
	menu.offset_bottom = 200
	menu.add_theme_constant_override("separation", 10)
	add_child(menu)

	var new_btn := _make_button("⚔️  Nouvelle partie", true)
	new_btn.pressed.connect(func() -> void:
		new_game_requested.emit(_difficulty, _permadeath))
	menu.add_child(new_btn)

	var continue_btn := _make_button("💾  Continuer")
	continue_btn.disabled = not _has_save()
	continue_btn.pressed.connect(func() -> void: continue_requested.emit())
	menu.add_child(continue_btn)

	var ciel_btn := _make_button("🤖  Escarmouche CielAI")
	ciel_btn.pressed.connect(func() -> void: ciel_mode_requested.emit())
	menu.add_child(ciel_btn)

	var hotseat_btn := _make_button("🪑  Duel local (2 joueurs)")
	hotseat_btn.pressed.connect(func() -> void: hotseat_requested.emit())
	menu.add_child(hotseat_btn)

	var host_btn := _make_button("🌐  Créer une partie en ligne")
	host_btn.pressed.connect(func() -> void: host_requested.emit())
	menu.add_child(host_btn)

	var join_btn := _make_button("🔑  Rejoindre avec un code")
	join_btn.pressed.connect(func() -> void: join_requested.emit())
	menu.add_child(join_btn)

	menu.add_child(_spacer(12))

	_difficulty_button = _make_button(_difficulty_label())
	_difficulty_button.pressed.connect(_cycle_difficulty)
	menu.add_child(_difficulty_button)

	_permadeath_button = _make_button(_permadeath_label())
	_permadeath_button.pressed.connect(_toggle_permadeath)
	menu.add_child(_permadeath_button)

	menu.add_child(_spacer(12))

	var editor_btn := _make_button("🗺️  Éditeur de cartes")
	editor_btn.pressed.connect(func() -> void: editor_requested.emit())
	menu.add_child(editor_btn)

	var fe2d_btn := _make_button("🧪  Prototype 2D")
	fe2d_btn.pressed.connect(func() -> void: fe2d_requested.emit())
	menu.add_child(fe2d_btn)

	var quit_btn := _make_button("🚪  Quitter")
	quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	menu.add_child(quit_btn)

	_status = Label.new()
	_status.text = _save_summary()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -46
	_status.offset_bottom = -24
	add_child(_status)


#region Options
func _cycle_difficulty() -> void:
	_difficulty = (_difficulty + 1) % DIFF.Level.size()
	_difficulty_button.text = _difficulty_label()


func _toggle_permadeath() -> void:
	_permadeath = not _permadeath
	_permadeath_button.text = _permadeath_label()


func _difficulty_label() -> String:
	return "🎚  Difficulté : %s" % DIFF.get_level_name(_difficulty)


func _permadeath_label() -> String:
	return "☠️  Mort permanente : %s" % ("oui" if _permadeath else "non")
#endregion


#region Helpers
func _campaign() -> Node:
	return get_node_or_null("/root/Campaign")


func _has_save() -> bool:
	var campaign: Node = _campaign()
	return campaign.has_save(0) if campaign else false


func _save_summary() -> String:
	var campaign: Node = _campaign()
	if not campaign or not campaign.has_save(0):
		return "Aucune sauvegarde — commence une nouvelle partie."
	return "Sauvegarde trouvée : %s" % ProjectSettings.globalize_path(campaign.save_path(0))


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


func _make_button(text: String, accent: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 46)
	btn.add_theme_font_size_override("font_size", 18)

	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if accent else C_BUTTON
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(C_ACCENT).lightened(0.15) if accent else C_BUTTON_HOVER
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	return btn
#endregion
