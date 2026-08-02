extends Control
## Main menu screen with chapter select, unit roster, and game launch.
## Built entirely in code — no .tscn dependencies.

signal chapter_selected(level_name: String)
signal quit_requested

const GAME_SCENE := "res://assets/scene/main.tscn"
const STATS_FILES := {
	"hero": "res://data/models/world/stats/hero/",
	"mob": "res://data/models/world/stats/mob/",
}

# Preload scripts (avoids class_name parse-order issues and base-method collisions)
const _CDB = preload("res://data/models/world/stats/class_data.gd")
const WeaponTypeRef = preload("res://data/models/world/stats/weapon_type.gd")
const StatsResource = preload("res://data/models/world/stats/stats_res.gd")

# Theme colors
const C_BG: Color = Color("#1a1a2e")
const C_ACCENT: Color = Color("#e94560")
const C_GOLD: Color = Color("#f5c842")
const C_TEXT: Color = Color("#eeeeee")
const C_PANEL: Color = Color("#16213e")
const C_BUTTON: Color = Color("#0f3460")
const C_BUTTON_HOVER: Color = Color("#1a508b")
const C_STAT_BAR: Color = Color("#2d6a4f")
const C_HP_BAR: Color = Color("#d62828")

var _roster_panel: Control
var _chapter_buttons: VBoxContainer


func _ready() -> void:
	_clear_children()
	_build_background()
	_build_menu_buttons()
	_build_roster_panel()


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()


#region Background
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Decorative top bar
	var bar := ColorRect.new()
	bar.color = C_ACCENT
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 4)
	add_child(bar)
	
	# Title
	var title := Label.new()
	title.text = "FIRE EMBLEM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", C_GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 40
	title.offset_bottom = 90
	add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = "Tactical RPG"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", C_ACCENT)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	subtitle.offset_top = 90
	subtitle.offset_bottom = 120
	add_child(subtitle)
	
	# Version
	var version := Label.new()
	version.text = "v0.3 — Phase 3"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	version.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	version.offset_top = 120
	version.offset_bottom = 140
	add_child(version)
#endregion


#region Menu Buttons
func _build_menu_buttons() -> void:
	var btn_container := VBoxContainer.new()
	btn_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# 5 buttons (50px) + gaps ~ 320px total, width 340px for 280px buttons
	btn_container.offset_left = -170
	btn_container.offset_top = -160
	btn_container.offset_right = 170
	btn_container.offset_bottom = 160
	btn_container.add_theme_constant_override("separation", 8)
	add_child(btn_container)
	_chapter_buttons = btn_container
	
	# Chapter 1 button
	var ch1 := _make_button("⚔️  Chapitre 1 — Prélude")
	ch1.pressed.connect(func(): chapter_selected.emit("test"))
	btn_container.add_child(ch1)
	
	# Spacer
	var spacer0 := Control.new()
	spacer0.custom_minimum_size = Vector2(0, 16)
	btn_container.add_child(spacer0)
	
	# Map Editor button
	var editor_btn := _make_button("🎨  Map Editor", false)
	editor_btn.pressed.connect(func(): chapter_selected.emit("map_editor"))
	btn_container.add_child(editor_btn)
	
	# Spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	btn_container.add_child(spacer1)
	
	# Units button
	var units_btn := _make_button("📋  Unités", false)
	units_btn.pressed.connect(_on_units)
	btn_container.add_child(units_btn)
	
	# Quit button
	var quit_btn := _make_button("🚪  Quitter", false)
	quit_btn.pressed.connect(func(): quit_requested.emit())
	btn_container.add_child(quit_btn)
	
	# Footer
	var footer := Label.new()
	footer.text = "Fait avec ❤️ par Aurèle & Ciel"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	footer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	footer.offset_top = -30
	footer.offset_bottom = -10
	add_child(footer)


func _make_button(text: String, accent: bool = true) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 50)
	btn.add_theme_font_size_override("font_size", 18)
	
	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if accent else C_BUTTON
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	btn.add_theme_stylebox_override("normal", style)
	
	var style_hover := style.duplicate() as StyleBoxFlat
	style_hover.bg_color = Color(C_ACCENT).lightened(0.15) if accent else C_BUTTON_HOVER
	btn.add_theme_stylebox_override("hover", style_hover)
	
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	
	return btn
#endregion


#region Roster Panel
func _on_units() -> void:
	if _roster_panel:
		_roster_panel.visible = !_roster_panel.visible
		return


func _build_roster_panel() -> void:
	_roster_panel = Control.new()
	_roster_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roster_panel.visible = false
	add_child(_roster_panel)
	
	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_clicked)
	_roster_panel.add_child(dim)
	
	# Panel container
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_top = -280
	panel.offset_right = 400
	panel.offset_bottom = 280
	
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = C_PANEL
	panel_style.set_corner_radius_all(12)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = C_ACCENT
	panel.add_theme_stylebox_override("panel", panel_style)
	_roster_panel.add_child(panel)
	
	# Title
	var title := Label.new()
	title.text = "📋  ROSTER DES UNITÉS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = -260
	title.offset_left = -380
	title.offset_right = 380
	title.offset_bottom = -230
	_roster_panel.add_child(title)
	
	# Close button
	var close := Button.new()
	close.text = "✕ Retour"
	close.custom_minimum_size = Vector2(120, 36)
	close.add_theme_font_size_override("font_size", 14)
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = C_BUTTON
	close_style.set_corner_radius_all(6)
	close.add_theme_stylebox_override("normal", close_style)
	close.add_theme_color_override("font_color", C_TEXT)
	close.pressed.connect(func(): _roster_panel.visible = false)
	close.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	close.offset_top = -50
	close.offset_left = -60
	close.offset_right = 60
	close.offset_bottom = -14
	_roster_panel.add_child(close)
	
	# Unit cards (scrollable if needed)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	scroll.offset_top = -180
	scroll.offset_bottom = 80
	scroll.offset_left = -370
	scroll.offset_right = 370
	_roster_panel.add_child(scroll)
	
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	scroll.add_child(cards)
	
	# Load and display each hero
	var heroes := _load_hero_stats()
	for stats: StatsResource in heroes:
		var card := _build_unit_card(stats)
		cards.add_child(card)


func _on_dim_clicked(_event: InputEvent) -> void:
	if _event is InputEventMouseButton and _event.pressed:
		_roster_panel.visible = false


func _load_hero_stats() -> Array[StatsResource]:
	var heroes: Array[StatsResource] = []
	var dir := DirAccess.open(STATS_FILES["hero"])
	if not dir:
		return heroes
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load(STATS_FILES["hero"] + file_name)
			if res != null:
				heroes.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# Sort by character_class then level
	heroes.sort_custom(func(a, b): return a.character_class < b.character_class)
	return heroes


func _build_unit_card(stats: StatsResource) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(160, 260)
	
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(C_BUTTON)
	card_style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", card_style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(vbox)
	
	# Name
	var cls_name: String = _CDB.get_class_name(stats.character_class) if stats.character_class != 0 else "???"
	var promo_str: String = " ⭐" if stats.is_promoted else ""
	var name_label := Label.new()
	name_label.text = "%s%s" % [_truncate(stats.override_name if stats.override_name else stats.expertise, 14), promo_str]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", C_GOLD)
	vbox.add_child(name_label)
	
	# Class
	var class_label := Label.new()
	class_label.text = "Lv.%d %s" % [stats.level, cls_name]
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	class_label.add_theme_font_size_override("font_size", 11)
	class_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	vbox.add_child(class_label)
	
	# Separator
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(sep)
	
	# Stats (use Dictionary to avoid GDScript nested-array inference issues)
	var stats_data: Dictionary = {
		"HP": stats.hp,
		"Str": stats.str, "Mag": stats.mag,
		"Skl": stats.skl, "Spd": stats.spd, "Lck": stats.lck,
		"Def": stats.def, "Res": stats.res,
		"Mov": stats.movement,
	}
	
	for stat_key in stats_data:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		
		var stat_name := Label.new()
		stat_name.text = stat_key
		stat_name.add_theme_font_size_override("font_size", 10)
		stat_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		stat_name.custom_minimum_size = Vector2(28, 0)
		row.add_child(stat_name)
		
		var stat_val := Label.new()
		stat_val.text = str(stats_data[stat_key])
		stat_val.add_theme_font_size_override("font_size", 11)
		stat_val.add_theme_color_override("font_color", C_TEXT)
		stat_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(stat_val)
		
		vbox.add_child(row)
	
	# Weapon
	var wpn_sep := HSeparator.new()
	vbox.add_child(wpn_sep)
	
	var wpn_row := HBoxContainer.new()
	var wpn_label := Label.new()
	wpn_label.text = WeaponTypeRef.get_weapon_name(stats.weapon_type)
	wpn_label.add_theme_font_size_override("font_size", 10)
	wpn_label.add_theme_color_override("font_color", C_ACCENT)
	wpn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wpn_row.add_child(wpn_label)
	vbox.add_child(wpn_row)
	
	return card


func _truncate(s: String, max_len: int) -> String:
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len - 1) + "…"
#endregion
