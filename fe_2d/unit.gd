extends Node2D
## Unité FE — dessinée procéduralement, stats FE

signal clicked(unit: Node2D)

@export var unit_name := "Unit"
@export var unit_class := "Soldier"
@export var max_hp := 20
@export var hp := 20
@export var mov := 5
@export var atk := 8
@export var def_stat := 4
@export var is_player := true
@export var grid_pos := Vector2i(0, 0)
@export var attack_type := "melee"  # "melee", "ranged", "healer"

var is_selected := false
var has_moved := false
var has_acted := false
var alive := true
var _body_color: Color

func _ready():
	_body_color = Color(0.35, 0.50, 0.95) if is_player else Color(0.88, 0.22, 0.22)
	queue_redraw()

func _draw():
	if not alive: return
	
	# Ombre au sol (draw_circle_shape or explicit rect)
	draw_rect(Rect2(Vector2(-13, 2), Vector2(26, 6)), Color(0, 0, 0, 0.2))
	
	# Corps (diamant)
	draw_colored_polygon(
		PackedVector2Array([Vector2(0, -18), Vector2(13, 0), Vector2(0, 14), Vector2(-13, 0)]),
		Color(_body_color.r, _body_color.g, _body_color.b, 0.92)
	)
	draw_polyline(
		PackedVector2Array([Vector2(0, -18), Vector2(13, 0), Vector2(0, 14), Vector2(-13, 0), Vector2(0, -18)]),
		Color(_body_color.r * 0.55, _body_color.g * 0.55, _body_color.b * 0.55), 1.5
	)
	
	# Tête
	draw_circle(Vector2(0, -24), 8, _body_color)
	draw_arc(Vector2(0, -24), 8, 0, TAU, 20, Color(_body_color.r * 0.55, _body_color.g * 0.55, _body_color.b * 0.55), 1.5)
	
	# Halo de sélection
	if is_selected:
		draw_circle(Vector2(0, -8), 22, Color(1.0, 0.84, 0.0, 0.22))
		draw_arc(Vector2(0, -8), 22, 0, TAU, 36, Color(1.0, 0.84, 0.0, 0.55), 2.0)
	
	# Barre de vie
	var bw := 32.0
	var bh := 4.0
	var by := 16.0
	var ratio := float(hp) / float(max_hp)
	draw_rect(Rect2(-bw/2, by, bw, bh), Color(0.15, 0.15, 0.15, 0.85))
	if ratio > 0:
		var hc := Color(0.15, 0.78, 0.15) if ratio > 0.5 else (Color(0.9, 0.65, 0.05) if ratio > 0.25 else Color(0.9, 0.15, 0.15))
		draw_rect(Rect2(-bw/2, by, bw * ratio, bh), hc)
	
	# Nom
	var font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(-26, by + 15), unit_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

func is_at(wp: Vector2) -> bool:
	return wp.distance_to(global_position) < 20.0

func select():
	is_selected = true
	queue_redraw()

func deselect():
	is_selected = false
	queue_redraw()

func reset_turn():
	has_moved = false
	has_acted = false

func move_to(wp: Vector2, new_gp: Vector2i):
	grid_pos = new_gp
	var t := create_tween()
	t.tween_property(self, "position", wp, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	await t.finished
	has_moved = true

func take_damage(dmg: int):
	hp = maxi(0, hp - dmg)
	queue_redraw()
	var orig = _body_color
	_body_color = Color.RED
	queue_redraw()
	await get_tree().create_timer(0.12).timeout
	_body_color = orig
	queue_redraw()

func is_dead() -> bool:
	return hp <= 0

func die():
	alive = false
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	await t.finished
