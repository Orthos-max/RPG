extends Node2D
## Éditeur de maps 2D isométrique — style Fire Emblem

const BattleGrid = preload("res://fe_2d/battle_grid.gd")
const Unit = preload("res://fe_2d/unit.gd")

enum Mode { PAINT, UNITS, ERASE }
enum Terrain { GRASS, FOREST, MOUNTAIN, WATER, PATH, WALL, PIT }

const TERRAIN_NAMES := ["Herbe", "Forêt", "Montagne", "Eau", "Route", "Mur", "Fosse"]
const TERRAIN_COLORS := [
	Color(0.45, 0.70, 0.32),
	Color(0.18, 0.48, 0.15),
	Color(0.52, 0.48, 0.42),
	Color(0.22, 0.48, 0.78),
	Color(0.78, 0.72, 0.58),
	Color(0.45, 0.42, 0.38),
	Color(0.25, 0.20, 0.15),
]

@onready var camera: Camera2D = $Camera2D
@onready var palette_panel: Panel = $CanvasLayer/PalettePanel
@onready var info_lbl: Label = $CanvasLayer/InfoLabel
@onready var mode_lbl: Label = $CanvasLayer/ModeLabel
@onready var help_lbl: Label = $CanvasLayer/HelpLabel

var grid: BattleGrid
var current_mode := Mode.PAINT
var brush_terrain := Terrain.GRASS
var placed_units: Array = []
var edited_tiles: Dictionary = {}  # Vector2i -> Terrain  (overrides)
var _last_painted := Vector2i(-999, -999)

func _ready():
	grid = BattleGrid.new()
	grid.position = Vector2(420, 90)
	add_child(grid)
	
	camera.position = grid.grid_to_world(Vector2i(8, 5)) + grid.position
	camera.zoom = Vector2(1.3, 1.3)
	
	_build_palette()
	_update_ui()

func _build_palette():
	var y := 40.0
	for i in TERRAIN_NAMES.size():
		var btn := Button.new()
		btn.text = " %s" % TERRAIN_NAMES[i]
		btn.flat = false
		btn.position = Vector2(8, y)
		btn.size = Vector2(120, 24)
		btn.add_theme_color_override("font_color", TERRAIN_COLORS[i])
		btn.add_theme_font_size_override("font_size", 12)
		var idx = i
		btn.pressed.connect(func(): _select_terrain(idx))
		if i == 0: _highlight_btn(btn, true)
		btn.name = "terrain_btn_%d" % i
		palette_panel.add_child(btn)
		y += 26
	
	# Mode buttons
	y += 8
	for md in [{"name": "🖌️ Peindre", "mode": Mode.PAINT}, {"name": "👤 Unités", "mode": Mode.UNITS}, {"name": "🧹 Effacer", "mode": Mode.ERASE}]:
		var btn := Button.new()
		btn.text = md.name
		btn.position = Vector2(8, y)
		btn.size = Vector2(120, 24)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(m=md.mode): set_mode(m))
		if md.mode == Mode.PAINT: _highlight_btn(btn, true)
		btn.name = "mode_btn_%d" % md.mode
		palette_panel.add_child(btn)
		y += 26
	
	# Save / Load
	y += 8
	for act in [{"name": "💾 Sauver", "cb": _save_map}, {"name": "📂 Charger", "cb": _load_map}, {"name": "🗑️ Clear", "cb": _clear_map}, {"name": "▶️ Jouer", "cb": _test_play}]:
		var btn := Button.new()
		btn.text = act.name
		btn.position = Vector2(8, y)
		btn.size = Vector2(120, 24)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(act.cb)
		palette_panel.add_child(btn)
		y += 26

func _highlight_btn(btn: Button, on: bool):
	btn.add_theme_color_override("font_color", Color.WHITE if on else Color(0.85, 0.85, 0.85))
	btn.add_theme_stylebox_override("normal", StyleBoxFlat.new())
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal")
	sb.bg_color = Color(0.2, 0.5, 1.0, 0.6) if on else Color(0.2, 0.2, 0.2, 0.4)
	sb.border_width_left = 2 if on else 0
	sb.border_color = Color(1.0, 1.0, 1.0, 0.8) if on else Color.TRANSPARENT

func _select_terrain(idx: int):
	brush_terrain = idx as Terrain
	current_mode = Mode.PAINT
	_update_mode_buttons()
	_refresh_palette_highlight()

func set_mode(md: Mode):
	current_mode = md
	_update_mode_buttons()

func _update_mode_buttons():
	for c in palette_panel.get_children():
		if c is Button and c.name.begins_with("mode_btn_"):
			var mid = c.name.trim_prefix("mode_btn_").to_int()
			_highlight_btn(c, mid == current_mode)

func _refresh_palette_highlight():
	for c in palette_panel.get_children():
		if c is Button and c.name.begins_with("terrain_btn_"):
			var tid = c.name.trim_prefix("terrain_btn_").to_int()
			_highlight_btn(c, tid == brush_terrain and current_mode == Mode.PAINT)

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var mp := get_global_mouse_position()
		var gl := mp - grid.position
		var gp := grid.world_to_grid(gl)
		if gp.x < 0 or gp.x >= BattleGrid.COLS or gp.y < 0 or gp.y >= BattleGrid.ROWS:
			return
		
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				match current_mode:
					Mode.PAINT:
						if gp != _last_painted:
							_paint(gp)
							_last_painted = gp
					Mode.ERASE:
						_paint_terrain(gp, Terrain.GRASS)
					Mode.UNITS:
						# Clic sur unité existante = supprimer
						for u in placed_units:
							if u.is_at(mp):
								placed_units.erase(u)
								u.queue_free()
								_update_ui()
								return
						# Sinon = placer unité joueur (clic simple) ou ennemi (clic shift)
						_add_unit_at(gp, not Input.is_key_pressed(KEY_SHIFT))
			
			MOUSE_BUTTON_RIGHT:
				if current_mode == Mode.UNITS:
					# Clic droit = placer ennemi
					_add_unit_at(gp, false)
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			brush_terrain = ((brush_terrain as int) + 1) % TERRAIN_NAMES.size() as Terrain
			current_mode = Mode.PAINT
			_update_mode_buttons()
			_refresh_palette_highlight()
			_update_ui()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			brush_terrain = ((brush_terrain as int) - 1 + TERRAIN_NAMES.size()) % TERRAIN_NAMES.size() as Terrain
			current_mode = Mode.PAINT
			_update_mode_buttons()
			_refresh_palette_highlight()
			_update_ui()
	
	if event.is_action_pressed("end_turn"):
		_test_play()
	if event.is_action_pressed("ui_cancel"):
		_clear_map()

func _paint(gp: Vector2i):
	_paint_terrain(gp, brush_terrain)

func _paint_terrain(gp: Vector2i, t: Terrain):
	edited_tiles[gp] = t
	grid.terrain_data[gp.y * BattleGrid.COLS + gp.x] = t
	grid.queue_redraw()
	_update_ui()

func _add_unit_at(gp: Vector2i, is_player: bool):
	# Vérifier pas déjà d'unité sur cette case
	for u in placed_units:
		var d = absi(u.grid_pos.x - gp.x) + absi(u.grid_pos.y - gp.y)
		if d == 0: return
	if not grid.is_walkable(gp): return
	
	var u := Unit.new()
	u.unit_name = "Chrom" if is_player else "Bandit"
	u.unit_class = "Lord" if is_player else "Brigand"
	u.max_hp = 22; u.hp = 22
	u.mov = 5; u.atk = 10; u.def_stat = 5
	u.grid_pos = gp
	u.is_player = is_player
	u.position = grid.grid_to_world(gp) + grid.position
	add_child(u)
	placed_units.append(u)
	_update_ui()

func _clear_map():
	for gp in edited_tiles:
		grid.terrain_data[gp.y * BattleGrid.COLS + gp.x] = BattleGrid.Terrain.GRASS
	edited_tiles.clear()
	for u in placed_units: u.queue_free()
	placed_units.clear()
	grid._generate_map()  # Restore default
	grid.queue_redraw()
	_update_ui()

func _save_map():
	# Sauvegarde en JSON dans user:// — fiable et accessible
	var path := "user://user_map.json"
	
	var data := {
		"cols": BattleGrid.COLS,
		"rows": BattleGrid.ROWS,
		"terrain": [],
		"units": []
	}
	
	for v in grid.terrain_data:
		data.terrain.append(v)
	
	for u in placed_units:
		data.units.append({
			"x": u.grid_pos.x,
			"y": u.grid_pos.y,
			"player": u.is_player,
			"name": u.unit_name,
			"class": u.unit_class
		})
	
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		info_lbl.text = "✅ Map sauvée (%d tiles, %d unités)" % [edited_tiles.size(), placed_units.size()]
	else:
		info_lbl.text = "❌ Erreur: impossible d'écrire %s" % path

func _load_map():
	var path := "user://user_map.json"
	if not FileAccess.file_exists(path):
		info_lbl.text = "❌ Aucune map trouvée. Sauve d'abord une map."
		return
	
	_clear_map()
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		info_lbl.text = "❌ Erreur lecture fichier"
		return
	
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(txt)
	if err != OK:
		info_lbl.text = "❌ JSON invalide: %s" % json.get_error_message()
		return
	
	var data = json.get_data()
	if not data is Dictionary:
		info_lbl.text = "❌ Format invalide"
		return
	
	# Restaurer terrain
	var terrain_arr = data.get("terrain", [])
	for i in mini(terrain_arr.size(), grid.terrain_data.size()):
		var v = int(terrain_arr[i])
		grid.terrain_data[i] = v
		edited_tiles[Vector2i(i % BattleGrid.COLS, i / BattleGrid.COLS)] = v as Terrain
	
	# Restaurer unités
	for ud in data.get("units", []):
		if not ud is Dictionary: continue
		var gp := Vector2i(int(ud.get("x", 0)), int(ud.get("y", 0)))
		var is_p := bool(ud.get("player", true))
		_add_unit_at(gp, is_p)
		if placed_units.size() > 0:
			var u = placed_units[-1]
			u.unit_name = str(ud.get("name", "Unit"))
			u.unit_class = str(ud.get("class", "Soldier"))
	
	grid.queue_redraw()
	info_lbl.text = "✅ Map chargée (%d tiles, %d unités)" % [edited_tiles.size(), placed_units.size()]

func _test_play():
	# Switch to game mode: pass map + units to level controller
	info_lbl.text = "⚔️ Lancement du jeu..."
	get_tree().call_deferred("change_scene_to_file", "res://fe_2d/fe_level.tscn")

func _make_zeros(n: int) -> String:
	var parts: Array[String] = []
	for _i in n: parts.append("0.0")
	return ", ".join(parts)

func _format_array(arr: Array) -> String:
	var parts: Array[String] = []
	for v in arr: parts.append(str(v))
	return ", ".join(parts)

func _update_ui():
	var count := edited_tiles.size()
	var mode_name := ""
	match current_mode:
		Mode.PAINT: mode_name = "🖌️ %s" % TERRAIN_NAMES[brush_terrain]
		Mode.UNITS: mode_name = "👤 Placement"
		Mode.ERASE: mode_name = "🧹 Effacer"
	mode_lbl.text = "Mode: %s | Tiles modifiées: %d | Unités placées: %d" % [mode_name, count, placed_units.size()]
