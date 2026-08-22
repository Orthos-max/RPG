class_name LevelUpFx
extends CanvasLayer
## Écran de montée de niveau animé — « Velmar : nuit et or ».
##
## Quand une unité monte de niveau ([BattleLog.Kind.LEVEL_UP]) ou est promue
## ([BattleLog.Kind.PROMOTION]), un panneau doré apparaît au centre : titre
## qui rebondit, nom de l'unité, niveau atteint, et une pluie de braises
## dorées qui montent — dans la même famille que le [TitleBackdrop].
##
## L'animation est purement décorative : tout est en [code]mouse_filter =
## MOUSE_FILTER_IGNORE[/code], le jeu continue de tourner dessous, et en
## headless (tests, serveur) le nœud n'existe même pas — l'API reste sûre.
##
## Plusieurs montées d'affilée (deux kills au même tour) : les événements
## sont mis en file et joués en séquence, un à la fois.

const LAYER: int = 95  ## Sous le fondu de transition (100).

const C_GOLD := Color("#f5c842")
const C_GOLD_BRIGHT := Color("#ffe08a")
const C_BG := Color(0.05, 0.04, 0.10, 0.92)

## Durée de l'animation d'entrée (rebond).
const ENTER: float = 0.55
## Temps d'affichage stable, titre qui pulse.
const HOLD: float = 1.4
## Durée de la sortie (fondu + repli).
const EXIT: float = 0.45

const ClassDataClass = preload("res://data/models/world/stats/class_data.gd")

var _queue: Array = []
var _busy: bool = false
var _root: Control = null
var _panel: PanelContainer = null
var _title: Label = null
var _subtitle: Label = null
var _detail: Label = null
var _particles: CPUParticles2D = null


## Crée l'effet et l'accroche à [param parent] (appelé par [Main]).
static func attach(parent: Node) -> LevelUpFx:
	var fx := LevelUpFx.new()
	fx.name = "LevelUpFx"
	parent.add_child(fx)
	return fx


func _init() -> void:
	layer = LAYER
	if DisplayServer.get_name() == "headless":
		return
	_build()
	_listen()


func _build() -> void:
	_root = Control.new()
	_root.name = "LevelUpRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = C_BG
	style.border_color = C_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	_panel.add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", C_GOLD)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 20)
	_subtitle.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(_subtitle)

	_detail = Label.new()
	_detail.name = "Detail"
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 16)
	_detail.add_theme_color_override("font_color", C_GOLD_BRIGHT)
	column.add_child(_detail)

	# Braises dorées qui montent, comme sur l'écran-titre.
	_particles = CPUParticles2D.new()
	_particles.name = "Sparks"
	_particles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_particles.amount = 26
	_particles.lifetime = 1.1
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(150, 6)
	_particles.position = Vector2(0, 42)
	_particles.direction = Vector2(0, -1)
	_particles.spread = 28.0
	_particles.gravity = Vector2(0, -160)
	_particles.initial_velocity_min = 60.0
	_particles.initial_velocity_max = 140.0
	_particles.scale_amount_min = 0.6
	_particles.scale_amount_max = 1.4
	_particles.color = C_GOLD
	_particles.texture = _spark_texture()
	_particles.emitting = false
	_root.add_child(_particles)


## Petite boule dorée procédurale, sans fichier externe.
func _spark_texture() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(x - 3.5, y - 3.5).length()
			var a: float = clampf(1.0 - d / 4.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.9, 0.55, a * a))
	return ImageTexture.create_from_image(img)


func _listen() -> void:
	var recorder: Node = get_node_or_null("/root/BattleRecorder")
	if recorder and not recorder.event_recorded.is_connected(_on_event):
		recorder.event_recorded.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	match str(event.get("kind_name", "")):
		"level_up":
			_queue.append({"promotion": false, "event": event})
		"promotion":
			_queue.append({"promotion": true, "event": event})
		_:
			return
	if not _busy:
		_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		return
	_busy = true
	var entry: Dictionary = _queue.pop_front()
	_show(entry["promotion"], entry["event"])


func _show(is_promotion: bool, event: Dictionary) -> void:
	var pawn: String = str(event.get("pawn", "?"))
	var title_text: String = "★  PROMOTION !  ★" if is_promotion else "★  NIVEAU SUPÉRIEUR !  ★"
	var detail_text: String
	if is_promotion:
		detail_text = ClassDataClass.get_class_name(int(event.get("class_id", 0)))
	else:
		detail_text = "Niveau %d" % int(event.get("level", 1))

	_title.text = title_text
	_subtitle.text = pawn
	_detail.text = detail_text

	# La promotion mérite un peu plus de faste.
	var gold: Color = C_GOLD_BRIGHT if is_promotion else C_GOLD
	_title.add_theme_color_override("font_color", gold)
	var panel_style: StyleBoxFlat = _panel.get_theme_stylebox("panel")
	panel_style.border_color = gold
	_particles.amount = 42 if is_promotion else 26
	_particles.color = gold

	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.2, 0.2)
	_panel.modulate.a = 0.0
	_panel.visible = true
	_particles.emitting = true

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2.ONE, ENTER) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tw.chain().tween_interval(HOLD)
	tw.set_parallel(false)
	tw.tween_property(_panel, "scale", Vector2(1.06, 1.06), EXIT) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_panel, "modulate:a", 0.0, EXIT)
	tw.tween_callback(_finish)


func _finish() -> void:
	_panel.visible = false
	_particles.emitting = false
	_busy = false
	_play_next()
