class_name MapEditorLevel
extends Node3D
## In-game map editor – paint terrain, place allies/enemies, save/load, generate.
## Zero dependency on the combat system.

const MAP_DATA := preload("res://data/models/world/map/demo_map.tres")
const MAP_DIR := "res://data/models/world/map/"
const MAP_GEN := preload("res://data/models/world/map/map_generator.gd")

const NAMES := ["🌿 Herbe", "🌲 Forêt", "⛰️ Montagne", "💧 Eau", "🛤️ Chemin", "🧱 Mur", "🕳️ Fosse"]
const COLORS := [
	Color("#4a8c3f"), Color("#2d5a1e"), Color("#7a7a7a"),
	Color("#256eb8"), Color("#c4a45a"), Color("#555555"), Color("#3d1e1e"),
]

var _md: Resource
var _tiles: Array = []       # [{body: StaticBody3D, mesh: MeshInstance3D, col: int, row: int}]
var _units: Array = []       # [{marker: MeshInstance3D, col: int, row: int, is_ally: bool}]
var _tool: int = -1
var _cam_yaw: float = -30.0
var _cam_pitch: float = -50.0
var _cam_dist: float = 12.0
var _cam_target := Vector3.ZERO
var _orbiting := false
var _panning := false
var _mouse_prev := Vector2.ZERO
var _status_label: Label = null
var _current_file: String = "demo_map.tres"
var _file_list_popup: PopupMenu = null
var _save_popup: PopupPanel = null
var _save_input: LineEdit = null

signal back_to_menu


func _ready() -> void:
	_md = MAP_DATA.duplicate(true)  # Work on a copy so original demo isn't modified
	_build_tiles()
	_build_lighting()
	_setup_camera()
	_build_ui()
	_show_status("Map chargée: %s" % _current_file)


func _build_tiles() -> void:
	var ts: float = _md.tile_size
	var hw: float = float(_md.grid_size.x) / 2.0
	var hh: float = float(_md.grid_size.y) / 2.0
	
	var parent := Node3D.new()
	parent.name = "EditorTiles"
	add_child(parent)
	
	for row in _md.grid_size.y:
		for col in _md.grid_size.x:
			var terrain: int = _md.get_terrain(col, row)
			var height: float = _md.get_height(col, row)
			var thickness: float = max(abs(height), 0.08)
			
			var mesh := BoxMesh.new()
			mesh.size = Vector3(ts * 0.98, thickness, ts * 0.98)
			
			var mat := StandardMaterial3D.new()
			mat.albedo_color = COLORS[clamp(terrain, 0, COLORS.size() - 1)]
			
			var body := StaticBody3D.new()
			body.name = "Tile_%d_%d" % [col, row]
			body.collision_layer = 1
			body.position = Vector3(
				(float(col) - hw + 0.5) * ts,
				height / 2.0,
				(float(row) - hh + 0.5) * ts
			)
			
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			body.add_child(mi)
			
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = mesh.size
			shape.shape = box
			body.add_child(shape)
			
			parent.add_child(body)
			_tiles.append({"body": body, "mesh": mi, "col": col, "row": row})


func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.name = "EditorLight"
	light.position = Vector3(5, 10, 5)
	light.light_energy = 0.8
	add_child(light)
	light.look_at(Vector3.ZERO, Vector3.UP)
	
	var env := WorldEnvironment.new()
	env.name = "EditorEnv"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#1a1a2e")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.3, 0.35)
	e.ambient_light_energy = 0.4
	env.environment = e
	add_child(env)


func _setup_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "EditorCamera"
	cam.current = true
	add_child(cam)
	_refresh_camera()


func _refresh_camera() -> void:
	var cam := get_node_or_null("EditorCamera") as Camera3D
	if not cam:
		return
	var yr := deg_to_rad(_cam_yaw)
	var pr := deg_to_rad(_cam_pitch)
	cam.position = _cam_target + Vector3(
		_cam_dist * cos(pr) * sin(yr),
		-_cam_dist * sin(pr),
		_cam_dist * cos(pr) * cos(yr)
	)
	cam.look_at(_cam_target)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "EditorUI"
	add_child(canvas)
	
	# Top bar
	var top := Panel.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 44
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color(0, 0, 0, 0.75)
	top.add_theme_stylebox_override("panel", tstyle)
	canvas.add_child(top)
	
	var title := Label.new()
	title.text = "🗺️  ÉDITEUR DE MAP"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#f5c842"))
	title.position = Vector2(10, 8)
	top.add_child(title)
	
	var hint := Label.new()
	hint.text = "🖱️ Clic gauche = peindre  |  Clic droit = orbite  |  Milieu = déplacer  |  ZQSD/AE = clavier  |  ESC = retour"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.position = Vector2(280, 12)
	top.add_child(hint)
	
	# Action buttons (top-right area)
	var _x := 260.0
	_x = _add_top_button(top, _x, "💾 Save", _on_save_pressed, Color("#1b6b3a"))
	_x = _add_top_button(top, _x, "📂 Load", _on_load_pressed, Color("#256eb8"))
	_x = _add_top_button(top, _x, "✨ Générer", _on_generate_pressed, Color("#9b59b6"))
	_x = _add_top_button(top, _x, "🆕 Nouveau", _on_new_pressed, Color("#e67e22"))
	
	# File list popup (hidden, shown on Load)
	_file_list_popup = PopupMenu.new()
	_file_list_popup.name = "FileListPopup"
	_file_list_popup.id_pressed.connect(_on_file_selected)
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = Color(0.08, 0.08, 0.14, 0.98)
	mstyle.set_corner_radius_all(8)
	mstyle.border_width_left = 1
	mstyle.border_width_right = 1
	mstyle.border_width_top = 1
	mstyle.border_width_bottom = 1
	mstyle.border_color = Color("#256eb8")
	_file_list_popup.add_theme_stylebox_override("panel", mstyle)
	_file_list_popup.add_theme_color_override("font_color", Color.WHITE)
	_file_list_popup.add_theme_font_size_override("font_size", 13)
	canvas.add_child(_file_list_popup)
	
	# Status bar (bottom center)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status_label.offset_top = -94
	_status_label.offset_bottom = -80
	canvas.add_child(_status_label)
	
	# Bottom palette
	var pal := HBoxContainer.new()
	pal.add_theme_constant_override("separation", 4)
	pal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pal.offset_top = -60
	pal.offset_bottom = -6
	pal.offset_left = -440
	pal.offset_right = 440
	canvas.add_child(pal)
	
	for i in NAMES.size():
		var btn := _make_btn(NAMES[i], COLORS[i], i)
		btn.pressed.connect(_set_tool.bind(i))
		pal.add_child(btn)
	
	var sep := VSeparator.new()
	pal.add_child(sep)
	
	var ab := _make_btn("🟢 Allié", Color("#1b6b3a"), 7)
	ab.pressed.connect(_set_tool.bind(7))
	pal.add_child(ab)
	
	var eb := _make_btn("🔴 Ennemi", Color("#b71c1c"), 8)
	eb.pressed.connect(_set_tool.bind(8))
	pal.add_child(eb)
	
	var db := _make_btn("🗑️ Effacer", Color("#444"), 9)
	db.pressed.connect(_set_tool.bind(9))
	pal.add_child(db)
	
	# Tool label
	var tl := Label.new()
	tl.name = "ToolLabel"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 12)
	tl.add_theme_color_override("font_color", Color("#f5c842"))
	tl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tl.offset_top = -78
	tl.offset_bottom = -62
	canvas.add_child(tl)


func _add_top_button(parent: Panel, x: float, text: String, callback: Callable, color: Color) -> float:
	var btn := Button.new()
	btn.text = text
	btn.size = Vector2(100, 30)
	btn.position = Vector2(x, 7)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate() as StyleBoxFlat
	h.bg_color = color.lightened(0.25)
	btn.add_theme_stylebox_override("hover", h)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return x + 108


func _make_btn(text: String, color: Color, _id: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(80, 46)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate() as StyleBoxFlat
	h.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", h)
	return btn


func _set_tool(id: int) -> void:
	_tool = id
	var tl := _get_label()
	if tl:
		match id:
			0,1,2,3,4,5,6: tl.text = "Pinceau: %s" % NAMES[id]
			7: tl.text = "Placer: 🟢 Allié"
			8: tl.text = "Placer: 🔴 Ennemi"
			9: tl.text = "Effacer unité"


func _get_label() -> Label:
	var ui := get_node_or_null("EditorUI")
	if not ui: return null
	return ui.get_node_or_null("ToolLabel") as Label


func _show_status(msg: String, color: Color = Color("#aaaaaa")) -> void:
	if _status_label:
		_status_label.add_theme_color_override("font_color", color)
		_status_label.text = msg


#region: --- Save / Load / Generate ---

func _on_save_pressed() -> void:
	# Show save dialog with filename input
	if not _save_popup:
		_build_save_dialog()
	
	# Pre-fill with current filename
	_save_input.text = _current_file
	_save_input.select_all()
	_save_input.grab_focus()
	
	# Center on screen
	var vp_size := get_viewport().get_visible_rect().size
	_save_popup.position = Vector2(vp_size.x / 2 - 150, vp_size.y / 2 - 55)
	_save_popup.popup()


func _build_save_dialog() -> void:
	var ui := get_node_or_null("EditorUI")
	if not ui:
		return
	
	_save_popup = PopupPanel.new()
	_save_popup.name = "SavePopup"
	_save_popup.size = Vector2(300, 120)
	_save_popup.borderless = false
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.08, 0.14, 0.98)
	pstyle.set_corner_radius_all(10)
	pstyle.border_width_left = 1
	pstyle.border_width_right = 1
	pstyle.border_width_top = 1
	pstyle.border_width_bottom = 1
	pstyle.border_color = Color("#f5c842")
	_save_popup.add_theme_stylebox_override("panel", pstyle)
	
	var lbl := Label.new()
	lbl.text = "💾 Enregistrer la map"
	lbl.position = Vector2(12, 12)
	lbl.add_theme_color_override("font_color", Color("#f5c842"))
	lbl.add_theme_font_size_override("font_size", 13)
	_save_popup.add_child(lbl)
	
	_save_input = LineEdit.new()
	_save_input.position = Vector2(12, 42)
	_save_input.size = Vector2(276, 28)
	_save_input.placeholder_text = "nom_de_la_map.tres"
	_save_input.add_theme_font_size_override("font_size", 12)
	_save_popup.add_child(_save_input)
	
	var ok := Button.new()
	ok.text = "💾 Sauvegarder"
	ok.position = Vector2(12, 82)
	ok.size = Vector2(132, 26)
	ok.add_theme_font_size_override("font_size", 11)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("#1b6b3a")
	bs.set_corner_radius_all(4)
	ok.add_theme_stylebox_override("normal", bs)
	var bh := bs.duplicate() as StyleBoxFlat
	bh.bg_color = Color("#1b6b3a").lightened(0.2)
	ok.add_theme_stylebox_override("hover", bh)
	ok.pressed.connect(_on_save_confirm)
	_save_popup.add_child(ok)
	
	var cancel := Button.new()
	cancel.text = "✕ Annuler"
	cancel.position = Vector2(156, 82)
	cancel.size = Vector2(132, 26)
	cancel.add_theme_font_size_override("font_size", 11)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#555555")
	cs.set_corner_radius_all(4)
	cancel.add_theme_stylebox_override("normal", cs)
	var ch := cs.duplicate() as StyleBoxFlat
	ch.bg_color = Color("#555555").lightened(0.2)
	cancel.add_theme_stylebox_override("hover", ch)
	cancel.pressed.connect(func(): _save_popup.hide())
	_save_popup.add_child(cancel)
	
	ui.add_child(_save_popup)


func _on_save_confirm() -> void:
	var name: String = _save_input.text.strip_edges()
	if name.is_empty():
		_show_status("❌ Nom vide", Color("#e6615b"))
		_save_popup.hide()
		return
	
	# Ensure .tres extension
	if not name.ends_with(".tres"):
		name += ".tres"
	
	_current_file = name
	_save_popup.hide()
	
	var path: String = MAP_DIR + name
	var err := ResourceSaver.save(_md, path)
	if err == OK:
		_show_status("✅ Sauvegardé: %s" % name, Color("#5dbe6b"))
		print("[MapEditor] Saved: %s" % path)
	else:
		_show_status("❌ Erreur sauvegarde (err=%d)" % err, Color("#e6615b"))
		printerr("[MapEditor] Save failed for %s (err=%d)" % [path, err])


func _on_load_pressed() -> void:
	_file_list_popup.clear()
	
	# Add title (non-clickable)
	_file_list_popup.add_item("📂 Charger une map…")
	_file_list_popup.set_item_disabled(0, true)
	_file_list_popup.add_separator("Maps disponibles")
	
	var dir := DirAccess.open(MAP_DIR)
	if not dir:
		_show_status("❌ Dossier maps introuvable", Color("#e6615b"))
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var has_files := false
	var names: Array[String] = []
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			names.append(file_name)
			has_files = true
		file_name = dir.get_next()
	dir.list_dir_end()
	
	if not has_files:
		_show_status("⚠️ Aucun fichier .tres dans maps/", Color("#ffaa44"))
		return
	
	names.sort()
	for n in names:
		var icon := "📄 "
		if n == _current_file:
			icon = "📌 "
		_file_list_popup.add_item(icon + n)
	
	# Show popup at center of screen
	var vp_size := get_viewport().get_visible_rect().size
	_file_list_popup.position = Vector2(vp_size.x / 2 - 160, vp_size.y / 2 - 100)
	_file_list_popup.popup()


func _on_file_selected(id: int) -> void:
	if id < 2:
		return  # Title or separator, ignore
	var item_text: String = _file_list_popup.get_item_text(id)
	# Strip icon prefix ("📄 " or "📌 ")
	var file_name: String = item_text.substr(3) if item_text.begins_with("📄 ") or item_text.begins_with("📌 ") else item_text
	var path: String = MAP_DIR + file_name
	var loaded: Resource = load(path)
	if loaded:
		# Rebuild tiles from loaded data
		_clear_scene()
		_md = loaded.duplicate(true)
		_current_file = file_name
		_tiles.clear()
		_units.clear()
		_tool = -1
		_build_tiles()
		_show_status("📂 Chargé: %s" % file_name, Color("#5dbe6b"))
		print("[MapEditor] Loaded: %s" % path)
	else:
		_show_status("❌ Échec chargement: %s" % file_name, Color("#e6615b"))


func _on_generate_pressed() -> void:
	var gen := MAP_GEN.new()
	gen.grid_size = _md.grid_size
	gen.seed = randi()
	gen.generate()
	
	# Copy terrain from generator to our MapData
	for row in _md.grid_size.y:
		for col in _md.grid_size.x:
			_md.set_terrain(col, row, gen.get_terrain(col, row))
			_md.set_height(col, row, gen.get_height(col, row))
	
	# Rebuild visual tiles
	_rebuild_all_tiles()
	
	# Auto-save with generated name
	_current_file = "gen_map_%d.tres" % gen.seed
	_show_status("✨ Map générée (seed=%d) — 💾 pour sauver" % gen.seed, Color("#c39bdd"))
	print("[MapEditor] Generated map with seed=%d" % gen.seed)


func _on_new_pressed() -> void:
	_clear_scene()
	_md = MAP_DATA.duplicate(true)
	_md.init_default()
	_tiles.clear()
	_units.clear()
	_tool = -1
	_current_file = "new_map.tres"
	_build_tiles()
	_show_status("🆕 Nouvelle map vierge", Color("#e6a044"))


func _clear_scene() -> void:
	for t in _tiles:
		if is_instance_valid(t.body):
			t.body.queue_free()
	for u in _units:
		if is_instance_valid(u.marker):
			u.marker.queue_free()
	_tiles.clear()
	_units.clear()


func _rebuild_all_tiles() -> void:
	var ts: float = _md.tile_size
	var hw: float = float(_md.grid_size.x) / 2.0
	var hh: float = float(_md.grid_size.y) / 2.0
	
	for t in _tiles:
		var terrain: int = _md.get_terrain(t.col, t.row)
		var height: float = _md.get_height(t.col, t.row)
		var thickness: float = max(abs(height), 0.08)
		t.body.position = Vector3(
			(float(t.col) - hw + 0.5) * ts,
			height / 2.0,
			(float(t.row) - hh + 0.5) * ts
		)
		t.mesh.mesh.size = Vector3(ts * 0.98, thickness, ts * 0.98)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLORS[clamp(terrain, 0, COLORS.size() - 1)]
		t.mesh.material_override = mat
		# Update collision shape too
		for child in t.body.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				child.shape.size = t.mesh.mesh.size

#endregion


#region: --- Camera Keyboard Controls ---

func _process(delta: float) -> void:
	var cam := get_node_or_null("EditorCamera") as Camera3D
	if not cam:
		return
	
	var pan_speed: float = _cam_dist * 3.0 * delta
	var rot_speed: float = 90.0 * delta
	var moved := false
	
	# Z / W — pan avant
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z):
		var forward := -cam.global_basis.z
		forward.y = 0
		if forward.length() > 0.001:
			_cam_target += forward.normalized() * pan_speed
		moved = true
	
	# S — pan arrière
	if Input.is_key_pressed(KEY_S):
		var forward := -cam.global_basis.z
		forward.y = 0
		if forward.length() > 0.001:
			_cam_target -= forward.normalized() * pan_speed
		moved = true
	
	# Q (AZERTY) — pan gauche (only if A not pressed to avoid conflict with rotate)
	if Input.is_key_pressed(KEY_Q) and not Input.is_key_pressed(KEY_A):
		var left := -cam.global_basis.x
		left.y = 0
		if left.length() > 0.001:
			_cam_target += left.normalized() * pan_speed
		moved = true
	
	# D — pan droite
	if Input.is_key_pressed(KEY_D):
		var left := -cam.global_basis.x
		left.y = 0
		if left.length() > 0.001:
			_cam_target -= left.normalized() * pan_speed
		moved = true
	
	# A — rotation yaw gauche (only if Q not pressed)
	if Input.is_key_pressed(KEY_A) and not Input.is_key_pressed(KEY_Q):
		_cam_yaw -= rot_speed
		moved = true
	
	# E — rotation yaw droite
	if Input.is_key_pressed(KEY_E):
		_cam_yaw += rot_speed
		moved = true
	
	if moved:
		_refresh_camera()

#endregion


#region: --- Input ---

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# If popup is visible, close it first
		if _save_popup and _save_popup.visible:
			_save_popup.hide()
			return
		if _file_list_popup and _file_list_popup.visible:
			_file_list_popup.hide()
			return
		back_to_menu.emit()
		return
	
	# Enter key — confirm save popup
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _save_popup and _save_popup.visible:
				_on_save_confirm()
				return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			_panning = false
			_mouse_prev = event.position
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_orbiting = false
			_mouse_prev = event.position
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_do_tool(event.position)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = max(3.0, _cam_dist - 1.0)
			_refresh_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = min(25.0, _cam_dist + 1.0)
			_refresh_camera()
	
	if event is InputEventMouseMotion:
		if _orbiting:
			var d: Vector2 = event.position - _mouse_prev
			_mouse_prev = event.position
			_cam_yaw -= d.x * 0.3
			_cam_pitch -= d.y * 0.3
			_cam_pitch = clamp(_cam_pitch, -89.0, -5.0)
			_refresh_camera()
		elif _panning:
			var d: Vector2 = event.position - _mouse_prev
			_mouse_prev = event.position
			var cam := get_node_or_null("EditorCamera") as Camera3D
			if cam:
				var pan_speed: float = _cam_dist * 0.003
				_cam_target += cam.global_basis.x * (-d.x * pan_speed)
				_cam_target += cam.global_basis.y * (d.y * pan_speed)
			_refresh_camera()

#endregion


#region: --- Tools ---

func _do_tool(screen_pos: Vector2) -> void:
	if _tool < 0:
		return
	
	var cam := get_node_or_null("EditorCamera") as Camera3D
	if not cam:
		return
	
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 80.0
	
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	
	var hit_pos: Vector3 = result.position
	var hw: float = float(_md.grid_size.x) / 2.0
	var hh: float = float(_md.grid_size.y) / 2.0
	var ts: float = _md.tile_size
	
	var col := int(round(hit_pos.x / ts + hw - 0.5))
	var row := int(round(hit_pos.z / ts + hh - 0.5))
	
	if col < 0 or col >= _md.grid_size.x or row < 0 or row >= _md.grid_size.y:
		return
	
	match _tool:
		0, 1, 2, 3, 4, 5, 6:
			_paint(col, row, _tool)
		7:
			_place_unit(col, row, true)
		8:
			_place_unit(col, row, false)
		9:
			_remove_unit(col, row)


func _paint(col: int, row: int, terrain: int) -> void:
	_md.set_terrain(col, row, terrain)
	for t in _tiles:
		if t.col == col and t.row == row:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = COLORS[clamp(terrain, 0, COLORS.size() - 1)]
			t.mesh.material_override = mat
			break


func _place_unit(col: int, row: int, is_ally: bool) -> void:
	for u in _units:
		if u.col == col and u.row == row:
			return
	
	var hw: float = float(_md.grid_size.x) / 2.0
	var hh: float = float(_md.grid_size.y) / 2.0
	var ts: float = _md.tile_size
	var height: float = _md.get_height(col, row)
	
	var marker := MeshInstance3D.new()
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = 0.2
	cmesh.bottom_radius = 0.2
	cmesh.height = 1.6
	marker.mesh = cmesh
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#2d6a4f") if is_ally else Color("#d62828")
	marker.material_override = mat
	
	marker.position = Vector3(
		(float(col) - hw + 0.5) * ts,
		height + 0.9,
		(float(row) - hh + 0.5) * ts
	)
	add_child(marker)
	_units.append({"marker": marker, "col": col, "row": row, "is_ally": is_ally})


func _remove_unit(col: int, row: int) -> void:
	for i in range(_units.size() - 1, -1, -1):
		var u = _units[i]
		if u.col == col and u.row == row:
			u.marker.queue_free()
			_units.remove_at(i)
			return

#endregion
