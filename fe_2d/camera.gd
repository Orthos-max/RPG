extends Camera2D
## Caméra FE — drag clic droit, zoom molette


@export var min_z := 0.5
@export var max_z := 2.5
@export var z_step := 0.1
@export var drag_speed := 1.0

var _dragging := false
var _drag_start := Vector2.ZERO
var _cam_start := Vector2.ZERO

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
			if event.pressed:
				_drag_start = event.position
				_cam_start = position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = (zoom + Vector2(z_step, z_step)).clamp(Vector2(min_z, min_z), Vector2(max_z, max_z))
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = (zoom - Vector2(z_step, z_step)).clamp(Vector2(min_z, min_z), Vector2(max_z, max_z))
	
	if event is InputEventMouseMotion and _dragging:
		position = _cam_start - (event.position - _drag_start) / zoom.x * drag_speed
