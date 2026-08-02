extends Node
## Main — Menu 2D → Éditeur ou Jeu

var fe_level: Node2D = null
var _menu_ref: CanvasLayer = null

func _ready() -> void:
	_show_menu()

func _show_menu() -> void:
	# Menu simple via CanvasLayer
	var menu := CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.12, 1.0)
	bg.size = Vector2(1280, 720)
	menu.add_child(bg)
	
	var title := Label.new()
	title.text = "⚔️ Fire Emblem — Tactical RPG"
	title.position = Vector2(300, 200)
	title.add_theme_font_size_override("font_size", 28)
	menu.add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = "Projet Godot 2D — Tamilah Ciel"
	subtitle.position = Vector2(420, 240)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	menu.add_child(subtitle)
	
	# Bouton Jeu
	var gb := Button.new()
	gb.text = "▶️  JOUER"
	gb.position = Vector2(440, 340)
	gb.size = Vector2(400, 60)
	gb.add_theme_font_size_override("font_size", 22)
	gb.pressed.connect(func(): menu.queue_free(); _load_game())
	menu.add_child(gb)
	
	# Bouton Éditeur
	var eb := Button.new()
	eb.text = "🗺️  ÉDITEUR DE MAPS"
	eb.position = Vector2(440, 420)
	eb.size = Vector2(400, 60)
	eb.add_theme_font_size_override("font_size", 22)
	eb.pressed.connect(func(): menu.queue_free(); _load_editor())
	menu.add_child(eb)
	
	# Instructions
	var help := Label.new()
	help.text = "Appuie sur Entrée pour jouer"
	help.position = Vector2(460, 530)
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	menu.add_child(help)
	
	add_child(menu)
	
	# Stocker la ref menu pour _input
	_menu_ref = menu

func _load_game() -> void:
	_disable_3d_camera()
	var scn := load("res://fe_2d/fe_level.tscn") as PackedScene
	if scn:
		fe_level = scn.instantiate()
		add_child(fe_level)

func _load_editor() -> void:
	_disable_3d_camera()
	var scn := load("res://fe_2d/editor/map_editor.tscn") as PackedScene
	if scn:
		fe_level = scn.instantiate()
		add_child(fe_level)

func _disable_3d_camera() -> void:
	var cam3d = get_node_or_null("Camera/TacticsCamera")
	if cam3d and cam3d is Camera3D:
		cam3d.current = false

func _input(event: InputEvent) -> void:
	# Entrée sur le menu = jouer
	if event.is_action_pressed("ui_accept") and _menu_ref:
		_menu_ref.queue_free()
		_menu_ref = null
		_load_game()
		return
	
	if event.is_action_pressed("ui_cancel") and fe_level:
		fe_level.queue_free()
		fe_level = null
		_show_menu()
