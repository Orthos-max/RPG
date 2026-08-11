class_name TacticsControlsInputService
extends RefCounted
## Service class for managing input-related functionalities in the Tactics game.

## Reference to the TacticsControlsResource.
var controls: TacticsControlsResource
## Node for capturing mouse clicks.
var input_capture: Node


## Initializes the TacticsControlsInputService with necessary resources and nodes.
func _init(_controls: TacticsControlsResource, _input_capture: Node) -> void:
	controls = _controls
	input_capture = _input_capture


## Updates the mouse mode based on whether a joystick is being used.
func update_mouse_mode() -> void:
	# Ne cache la souris QUE si un vrai joystick est connecté ET utilisé.
	# Un simple événement joypad parasite (manette branchée, stick qui envoie
	# des micro-valeurs) ne doit pas faire disparaître le curseur : sur
	# Windows, une manette connectée émet des événements fantômes en continu,
	# et `is_joystick` restait vrai → MOUSE_MODE_HIDDEN → la souris « clippait »
	# pour le joueur au clavier/souris.
	var joystick_connected: bool = not Input.get_connected_joypads().is_empty()
	if joystick_connected and controls.is_joystick:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Handles input events and updates the joystick status.
func handle_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		controls.is_joystick = true
	elif event is InputEventJoypadMotion:
		# Deadzone : ignorer les micro-valeurs du stick (dérive, événements
		# fantômes) qui ne sont pas une vraie intention de jeu.
		var joy: InputEventJoypadMotion = event as InputEventJoypadMotion
		controls.is_joystick = absf(joy.axis_value) > JOYSTICK_DEADZONE
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		controls.is_joystick = false


## Seuil sous lequel un mouvement de stick n'est pas une intention de jeu.
const JOYSTICK_DEADZONE: float = 0.5


## Gets the 3D position of the mouse in the game world.
## Returns null if hovering over a UI element or if input_capture is not set.
func get_3d_canvas_mouse_position(collision_mask: int, ctrl: TacticsControls) -> Object:
	if is_mouse_hovering_ui_elem(ctrl):
		return null
	
	if input_capture:
		return input_capture.project_mouse_position(collision_mask, controls.is_joystick)
	else:
		push_error("InputCapture node not found")
		return null


## Checks if the mouse is hovering over a UI element.
## Returns true if the mouse is over any of the specified UI elements.
func is_mouse_hovering_ui_elem(
		ctrl: TacticsControls, elm: Array[String] = TacticsConfig.ui_elem) -> bool:
	for e: String in elm:
		if ctrl.get_node(e).visible:
			match e:
				"%Actions":
					for action: Button in ctrl.get_node(e).get_children():
						if action.get_global_rect().has_point(ctrl.get_viewport().get_mouse_position()): 
							return true
				"%Hints":
					for hint: TextureRect in ctrl.get_node(e).get_children():
						if hint.get_global_rect().has_point(ctrl.get_viewport().get_mouse_position()): 
							return true
	return false
