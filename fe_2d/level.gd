extends Node2D
## Fire Emblem Level — Controller principal

const BattleGrid = preload("res://fe_2d/battle_grid.gd")
const Unit = preload("res://fe_2d/unit.gd")

@onready var camera: Camera2D = $Camera2D
@onready var turn_lbl: Label = $CanvasLayer/TurnLabel
@onready var info_lbl: Label = $CanvasLayer/InfoLabel
@onready var help_lbl: Label = $CanvasLayer/HelpLabel
@onready var actions_lbl: Label = $CanvasLayer/ActionsLabel
@onready var end_turn_btn: Button = $CanvasLayer/EndTurnBtn
@onready var action_panel: Control = $CanvasLayer/ActionPanel

var grid: BattleGrid
var units: Array = []
var player_team: Array = []
var enemy_team: Array = []
var selected: Unit = null
var move_tiles: Dictionary = {}
var attack_tiles: Dictionary = {}
var is_player_turn := true
var turn_n := 1
var _ending_turn := false
var _awaiting_action := false  # Attend que le joueur choisisse Attaquer/Attendre
var _moved_unit: Unit = null
var _move_target: Vector2i

func _ready():
	grid = BattleGrid.new()
	grid.position = Vector2(420, 90)
	add_child(grid)
	_spawn_units()
	_apply_z()
	_update_ui()
	
	end_turn_btn.pressed.connect(_on_end_turn_btn)
	action_panel.visible = false
	
	# Rendre tous les Labels transparents aux clics
	for c in $CanvasLayer.get_children():
		if c is Label:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	camera.position = grid.grid_to_world(Vector2i(8, 5)) + grid.position
	camera.zoom = Vector2(1.3, 1.3)

func _spawn_units():
	_add_unit("Chrom", "Lord", 22, 5, 10, 5, Vector2i(0, 1), true, "melee")
	_add_unit("Robin", "Tactician", 20, 5, 9, 4, Vector2i(1, 0), true, "melee")
	_add_unit("Frederick", "Great Knight", 28, 6, 12, 9, Vector2i(0, 2), true, "melee")
	_add_unit("Lissa", "Cleric", 18, 5, 4, 3, Vector2i(1, 2), true, "healer")
	_add_unit("Sully", "Cavalier", 21, 7, 8, 6, Vector2i(2, 1), true, "melee")
	_add_unit("Virion", "Archer", 19, 5, 8, 4, Vector2i(0, 3), true, "ranged")
	
	_add_unit("Bandit", "Brigand", 22, 4, 9, 4, Vector2i(11, 3), false, "melee")
	_add_unit("Bandit", "Brigand", 22, 4, 9, 4, Vector2i(10, 5), false, "melee")
	_add_unit("Mercenary", "Mercenary", 24, 5, 10, 6, Vector2i(13, 6), false, "melee")
	_add_unit("Archer", "Archer", 18, 4, 8, 3, Vector2i(7, 8), false, "ranged")
	_add_unit("Mage", "Dark Mage", 16, 4, 11, 2, Vector2i(9, 4), false, "ranged")
	_add_unit("Bandit", "Brigand", 22, 4, 9, 4, Vector2i(9, 2), false, "melee")

func _add_unit(nm: String, cl: String, hp_: int, mov_: int, atk_: int, def_: int, gp: Vector2i, player: bool, atk_type := "melee"):
	var u := Unit.new()
	u.unit_name = nm
	u.unit_class = cl
	u.max_hp = hp_; u.hp = hp_
	u.mov = mov_; u.atk = atk_; u.def_stat = def_
	u.grid_pos = gp
	u.is_player = player
	u.attack_type = atk_type
	u.position = grid.grid_to_world(gp) + grid.position
	add_child(u)
	units.append(u)
	if player: player_team.append(u)
	else: enemy_team.append(u)

## ── Input ──

func _input(event: InputEvent):
	# On utilise _input (pas _unhandled_input) pour être sûr de recevoir les clics
	if not (event is InputEventMouseButton and event.pressed): return
	if not is_player_turn or _ending_turn or _awaiting_action: return
	
	var mp := get_global_mouse_position()
	
	# Ignorer les clics sur les boutons UI
	if _is_over_ui(mp): return
	
	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(mp)

func _is_over_ui(mp: Vector2) -> bool:
	var btn_rect := Rect2(end_turn_btn.global_position, end_turn_btn.size)
	if btn_rect.has_point(mp): return true
	if action_panel.visible:
		var ap_rect := Rect2(action_panel.global_position, action_panel.size)
		if ap_rect.has_point(mp): return true
	return false

func _handle_left_click(mp: Vector2):
	# Sélection d'unité joueur
	for u in player_team:
		if u.alive and not u.has_moved and u.is_at(mp):
			_select(u)
			return
	
	# Déplacement sur case highlightée
	if selected != null and not selected.has_moved:
		var gp := grid.world_to_grid(mp - grid.position)
		if gp in move_tiles:
			_move_to(selected, gp)
			return
	
	# Clic sur unité ennemie adjacente = attaquer
	if selected != null and not selected.has_acted:
		var gp := grid.world_to_grid(mp - grid.position)
		if gp in attack_tiles:
			for e in enemy_team:
				if e.alive and e.grid_pos == gp:
					_do_combat(selected, e)
					return
	
	_deselect()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("end_turn") and is_player_turn and not _ending_turn:
		end_turn()

## ── Sélection ──

func _select(u):
	if selected: _deselect()
	selected = u
	u.select()
	grid.set_selection(u.grid_pos)
	
	var blocked := {}
	for u2 in units:
		if u2.alive and u2 != u:
			blocked[u2.grid_pos] = true
	
	move_tiles = grid.get_movement_range(u.grid_pos, u.mov, blocked)
	move_tiles.erase(u.grid_pos)
	grid.set_highlights(move_tiles, Color(0.2, 0.5, 1.0, 0.25))
	
	# Surbrillance des cibles potentielles (dans la portée d'attaque + move)
	_show_attack_targets(u)
	
	info_lbl.text = "%s  %s\n❤️ %d/%d  ⚔️ %d  🛡️ %d  👣 %d  🎯 %s" % [
		u.unit_name, u.unit_class, u.hp, u.max_hp, u.atk, u.def_stat, u.mov,
		"1×" if u.attack_type == "melee" else "2×"
	]

func _show_attack_targets(u):
	attack_tiles.clear()
	if u.attack_type == "healer": return
	var rng = 1 if u.attack_type == "melee" else 2
	for e in enemy_team:
		if not e.alive: continue
		for dx in range(-rng, rng+1):
			for dy in range(-rng, rng+1):
				if absi(dx) + absi(dy) > rng: continue
				var atp = e.grid_pos + Vector2i(dx, dy)
				if atp in move_tiles:
					attack_tiles[atp] = true
					grid.highlight_tiles[atp] = Color(1.0, 0.3, 0.2, 0.3)
	grid.queue_redraw()

func _deselect():
	if selected: selected.deselect()
	selected = null
	move_tiles.clear()
	attack_tiles.clear()
	grid.clear_highlights()
	grid.clear_selection()
	info_lbl.text = ""

## ── Mouvement ──

func _move_to(u, tgp: Vector2i):
	_move_target = tgp
	_moved_unit = u
	grid.clear_highlights()
	grid.clear_selection()
	var tw: Vector2 = grid.grid_to_world(tgp) + grid.position
	await u.move_to(tw, tgp)
	_apply_z()
	
	if u == selected: _deselect()
	
	# Vérifier si un ennemi est adjacent
	var adjacent_enemy: Unit = null
	for e in enemy_team:
		if not e.alive: continue
		var d = absi(u.grid_pos.x - e.grid_pos.x) + absi(u.grid_pos.y - e.grid_pos.y)
		var rng = 1 if u.attack_type == "melee" else 2
		if d <= rng:
			adjacent_enemy = e
			break
	
	# Healer adjacent à allié blessé
	if u.attack_type == "healer":
		var heal_target: Unit = null
		for p in player_team:
			if p.alive and p != u and p.hp < p.max_hp:
				var d = absi(u.grid_pos.x - p.grid_pos.x) + absi(u.grid_pos.y - p.grid_pos.y)
				if d == 1:
					heal_target = p
					break
		if heal_target:
			_show_action_menu(u, heal_target, adjacent_enemy)
			return
	
	if adjacent_enemy:
		_show_action_menu(u, null, adjacent_enemy)
	else:
		# Pas d'ennemi → fin de l'action
		u.has_acted = true
		_update_ui()
		_check_auto_end()

func _show_action_menu(u, heal_target, enemy):
	_awaiting_action = true
	action_panel.visible = true
	action_panel.position = u.position + Vector2(30, -60)
	
	# Nettoyer anciens boutons
	for c in action_panel.get_children():
		if c is Button: c.queue_free()
	
	if u.attack_type == "healer" and heal_target:
		info_lbl.text = "✨ Soigner %s ?" % heal_target.unit_name
		var btn := _make_action_btn("✨ Soigner (+8 HP)", func():
			var amt = mini(8, heal_target.max_hp - heal_target.hp)
			heal_target.hp += amt
			heal_target.queue_redraw()
			u.has_acted = true
			info_lbl.text = "%s soigne %s de %d HP !" % [u.unit_name, heal_target.unit_name, amt]
			_finish_action()
		)
		action_panel.add_child(btn)
	elif enemy:
		var pv = _preview_combat(u, enemy)
		info_lbl.text = "⚔️ %s ⚔️ %s" % [u.unit_name, enemy.unit_name]
		var atk_btn := _make_action_btn("⚔️ Attaquer %s" % pv, func():
			await _do_combat(u, enemy)
			u.has_acted = true
			_finish_action()
		)
		action_panel.add_child(atk_btn)
	
	var wait_btn := _make_action_btn("⏸️ Attendre", func():
		u.has_acted = true
		info_lbl.text = "%s attend." % u.unit_name
		_finish_action()
	)
	action_panel.add_child(wait_btn)

func _make_action_btn(txt: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.size = Vector2(180, 26)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(cb)
	return btn

func _finish_action():
	_awaiting_action = false
	action_panel.visible = false
	await get_tree().create_timer(0.3).timeout
	info_lbl.text = ""
	_update_ui()
	_check_auto_end()

## ── Combat ──

func _preview_combat(atk: Unit, dfs: Unit) -> String:
	var atk_dmg = maxi(1, atk.atk - dfs.def_stat - grid.get_defense_bonus(dfs.grid_pos))
	var dfs_dmg := 0
	if dfs.attack_type != "healer":
		var dfs_range = 1 if dfs.attack_type == "melee" else 2
		var d = absi(atk.grid_pos.x - dfs.grid_pos.x) + absi(atk.grid_pos.y - dfs.grid_pos.y)
		if d <= dfs_range:
			dfs_dmg = maxi(1, dfs.atk - atk.def_stat - grid.get_defense_bonus(atk.grid_pos))
	var result := "%d dmg → %d cnt" % [atk_dmg, dfs_dmg]
	# Prédiction fatale
	if atk_dmg >= dfs.hp: result += " 💀"
	if dfs_dmg >= atk.hp: result += " ⚠️"
	return result

func _do_combat(atk: Unit, dfs: Unit):
	# Attaque
	var dmg = maxi(1, atk.atk - dfs.def_stat - grid.get_defense_bonus(dfs.grid_pos))
	dfs.take_damage(dmg)
	info_lbl.text = "%s inflige %d dégâts à %s !" % [atk.unit_name, dmg, dfs.unit_name]
	await get_tree().create_timer(0.4).timeout
	
	# Contre-attaque si ennemi en vie et à portée
	if dfs.alive and dfs.attack_type != "healer":
		var dfs_range = 1 if dfs.attack_type == "melee" else 2
		var d = absi(atk.grid_pos.x - dfs.grid_pos.x) + absi(atk.grid_pos.y - dfs.grid_pos.y)
		if d <= dfs_range:
			var cnt = maxi(1, dfs.atk - atk.def_stat - grid.get_defense_bonus(atk.grid_pos))
			atk.take_damage(cnt)
			info_lbl.text += "\n%s contre-attaque: %d dégâts !" % [dfs.unit_name, cnt]
			await get_tree().create_timer(0.3).timeout
	
	_cleanup()

func _try_combat(u):
	# Pour l'IA (auto-combat après move)
	if u.has_acted: return
	for e in enemy_team:
		if not e.alive: continue
		var rng = 1 if u.attack_type == "melee" else 2
		var d = absi(u.grid_pos.x - e.grid_pos.x) + absi(u.grid_pos.y - e.grid_pos.y)
		if d <= rng:
			await _do_combat(u, e)
			u.has_acted = true
			break

## ── Tours ──

func _check_auto_end():
	if not is_player_turn or _ending_turn or _awaiting_action: return
	for u in player_team:
		if u.alive and not u.has_moved:
			return
	_ending_turn = true
	info_lbl.text = "⏳ Fin de tour automatique..."
	await get_tree().create_timer(0.8).timeout
	end_turn()

func _on_end_turn_btn():
	if is_player_turn and not _ending_turn and not _awaiting_action:
		end_turn()

func end_turn():
	_ending_turn = true
	_awaiting_action = false
	action_panel.visible = false
	is_player_turn = false
	_deselect()
	_update_ui()
	await _enemy_turn()
	_ending_turn = false
	is_player_turn = true
	turn_n += 1
	for u in units:
		if u.alive: u.reset_turn()
	_update_ui()
	_cleanup()

func _enemy_turn():
	for e in enemy_team:
		if not e.alive or e.has_moved: continue
		await get_tree().create_timer(0.3).timeout
		
		var tgt: Unit = null
		var bd := 999
		for p in player_team:
			if not p.alive: continue
			var d = absi(e.grid_pos.x - p.grid_pos.x) + absi(e.grid_pos.y - p.grid_pos.y)
			if d < bd: bd = d; tgt = p
		if not tgt: continue
		
		var blocked := {}
		for u in units:
			if u.alive and u != e and u != tgt:
				blocked[u.grid_pos] = true
		var tiles = grid.get_movement_range(e.grid_pos, e.mov, blocked)
		tiles.erase(e.grid_pos)
		
		var bt: Vector2i = e.grid_pos
		var bs := 99999
		for tp in tiles:
			var sc = absi(tp.x - tgt.grid_pos.x) + absi(tp.y - tgt.grid_pos.y)
			if sc < bs: bs = sc; bt = tp
		
		if bt != e.grid_pos:
			await e.move_to(grid.grid_to_world(bt) + grid.position, bt)
			await get_tree().create_timer(0.15).timeout
		
		var atk_range = 1 if e.attack_type == "melee" else 2
		if absi(e.grid_pos.x - tgt.grid_pos.x) + absi(e.grid_pos.y - tgt.grid_pos.y) <= atk_range:
			var dmg = maxi(1, e.atk - tgt.def_stat - grid.get_defense_bonus(tgt.grid_pos))
			tgt.take_damage(dmg)
			if tgt.alive and tgt.attack_type != "healer":
				await get_tree().create_timer(0.25).timeout
				var tgt_range = 1 if tgt.attack_type == "melee" else 2
				if absi(e.grid_pos.x - tgt.grid_pos.x) + absi(e.grid_pos.y - tgt.grid_pos.y) <= tgt_range:
					var cnt = maxi(1, tgt.atk - e.def_stat - grid.get_defense_bonus(e.grid_pos))
					e.take_damage(cnt)
			await get_tree().create_timer(0.2).timeout
		e.has_acted = true
	_apply_z()

func _cleanup():
	var dead = []
	for u in units:
		if not u.alive: dead.append(u)
	for u in dead:
		await u.die()
		units.erase(u)
		player_team.erase(u)
		enemy_team.erase(u)
		u.queue_free()
	
	if enemy_team.is_empty():
		info_lbl.text = "🏆 VICTOIRE !"
		is_player_turn = false
		end_turn_btn.disabled = true
	elif player_team.is_empty():
		info_lbl.text = "💀 DÉFAITE..."
		is_player_turn = false
		end_turn_btn.disabled = true

func _apply_z():
	units.sort_custom(func(a, b): return a.grid_pos.y < b.grid_pos.y)
	for u in units:
		u.z_index = u.grid_pos.x + u.grid_pos.y

func _update_ui():
	if is_player_turn:
		turn_lbl.text = "🔵 PHASE JOUEUR — Tour %d" % turn_n
		turn_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
		end_turn_btn.visible = true
	else:
		turn_lbl.text = "🔴 PHASE ENNEMIE — Tour %d" % turn_n
		turn_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		end_turn_btn.visible = false
	
	var remaining := 0
	for u in player_team:
		if u.alive and not u.has_moved: remaining += 1
	actions_lbl.text = "Unités disponibles: %d" % remaining
	end_turn_btn.text = "⏎ Fin de tour (%d)" % remaining
	
	help_lbl.text = "🖱️ Clic G: sélectionner/déplacer/attaquer | 🔽: zoom | 🖱️ Clic D: caméra | ⏎: fin de tour"
