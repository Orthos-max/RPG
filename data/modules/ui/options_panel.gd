class_name OptionsPanel
extends Control
## Panneau d'options audio — un curseur par bus, réglé en direct.
##
## Le service [Audio] savait déjà régler et enregistrer les volumes ; il manquait
## l'endroit où le joueur le lui demande. Chaque curseur agit immédiatement (on
## entend ce qu'on règle) et l'écriture dans `user://settings.json` attend la
## fermeture : autrement, faire glisser un curseur écrirait le fichier trente
## fois de suite.
##
## Le panneau se pose par-dessus l'écran qui l'ouvre et avale les clics — un
## bouton de menu resté cliquable derrière un dialogue est un bug classique.

signal closed()

## Bus réglables, dans l'ordre d'affichage : `[bus, libellé]`.
const CHANNELS: Array = [
	["Master", "🎚  Volume général"],
	[SoundDB.BUS_MUSIC, "🎵  Musique"],
	[SoundDB.BUS_SFX, "🔊  Effets"],
	[SoundDB.BUS_UI, "🖱  Interface"],
]

const C_PANEL := Color("#16213e")
const C_GOLD := Color("#f5c842")
const C_TEXT := Color("#e8e6f0")

## Curseurs par bus, pour les relire (et les tester) sans fouiller l'arbre.
var _sliders: Dictionary = {}
var _values: Dictionary = {}


## Le pourcentage affiché à droite d'un curseur.
static func percent_label(linear: float) -> String:
	return "%d %%" % roundi(clampf(linear, 0.0, 1.0) * 100.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Rien de ce qui est derrière ne doit rester cliquable.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	frame.custom_minimum_size = Vector2(420, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)

	var title := Label.new()
	title.text = "Options audio"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", C_GOLD)
	column.add_child(title)

	for channel: Array in CHANNELS:
		_add_slider(column, str(channel[0]), str(channel[1]))

	var hint := Label.new()
	hint.text = "Les réglages sont enregistrés en fermant."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	column.add_child(hint)

	var close := Button.new()
	close.text = "Fermer"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(close_panel)
	column.add_child(close)


## Une ligne « libellé — curseur — pourcentage ».
func _add_slider(parent: Node, bus: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	label.add_theme_color_override("font_color", C_TEXT)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = _current_volume(bus)
	slider.custom_minimum_size = Vector2(160, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var readout := Label.new()
	readout.text = percent_label(slider.value)
	readout.custom_minimum_size = Vector2(56, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_color_override("font_color", C_GOLD)
	row.add_child(readout)

	slider.value_changed.connect(func(value: float) -> void:
		readout.text = percent_label(value)
		apply(bus, value))

	_sliders[bus] = slider
	_values[bus] = slider.value


#region Réglages
## Applique un volume au bus (sans écrire le fichier — voir [method close_panel]).
func apply(bus: String, linear: float) -> void:
	_values[bus] = clampf(linear, 0.0, 1.0)
	var audio: Node = _audio()
	if audio:
		audio.set_volume(bus, linear)


## Volume affiché pour un bus : celui du service, ou le plein pot sans service.
func _current_volume(bus: String) -> float:
	var audio: Node = _audio()
	return float(audio.get_volume(bus)) if audio else 1.0


## Position d'un curseur — les tests s'en servent pour vérifier le câblage.
func slider_value(bus: String) -> float:
	var slider: HSlider = _sliders.get(bus)
	return slider.value if slider else -1.0


## Enregistre et referme.
func close_panel() -> void:
	var audio: Node = _audio()
	if audio:
		audio.save_settings()
	closed.emit()
	queue_free()


func _audio() -> Node:
	return get_node_or_null("/root/Audio")


## Échap referme le panneau — et n'atteint pas l'écran de dessous, qui y
## verrait un « retour au menu ».
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
#endregion
