class_name TacticsCamera
extends CharacterBody3D
## Handles camera movement features
##
## Camera movement methods:[br]
## - [code]rotate_camera[/code]: "Cardinal Points" mode [i](Q,E)[/i][br]
## - [code]move_camera[/code]: "Panning" mode [i](W,A,S,D)[/i][br]
## - [code]free_look[/code]: "Free Look" mode [i](MMB or Right Stick movement)[/i][br]
## - [code]follow[/code]: "Focus" mode [i](programmatically called)[/i][br][br]
## 
## Resource Interface: [TacticsCameraResource] -- Service: [TacticsCameraService]

## Resource containing camera attributes and signals
@export var res: TacticsCameraResource = load("res://data/models/view/camera/tactics/camera.tres")
## Resource containing control settings
@export var controls: TacticsControlsResource = load("res://data/models/view/control/tactics/control.tres")

## Service handling camera operations
static var serv: TacticsCameraService

## Node for horizontal rotation
@onready var t_pivot: Node3D = $TwistPivot
## Node for vertical rotation
@onready var p_pivot: Node3D = $TwistPivot/PitchPivot
## Main camera node
@onready var cam_node: Camera3D = $TwistPivot/PitchPivot/Camera3D


func _ready() -> void:
	# Le cadrage « Awakening » précède la mise en service : c'est lui qui décide
	# de la projection, donc de la propriété sur laquelle le zoom va travailler.
	TacticsFraming.apply_projection(cam_node, cam_node.size)
	res.x_rot = int(TacticsFraming.PITCH_DEGREES)
	res.y_rot = TacticsFraming.YAW_DEGREES
	# Les bornes du .tres sont des degrés d'ouverture, sans rapport avec la
	# hauteur de monde qu'attend une caméra orthographique.
	res.min_zoom = TacticsFraming.MIN_ORTHO_SIZE
	res.max_zoom = TacticsFraming.MAX_ORTHO_SIZE

	serv = TacticsCameraService.new(res, controls) # Initialize camera service
	serv.setup(self, cam_node) # Set up camera service
	res.boundary_center = global_position  # Set the initial boundary center
	# Connect signals
	res.connect("called_rotate_camera", rotate_camera)
	res.connect("called_move_camera", move_camera)
	res.connect("called_frame_board", frame_board)


func _process(delta: float) -> void:
	serv.process(delta, self) # Process camera service


## Pose la caméra sur un plateau : centre, rayon de promenade, hauteur d'image.
##
## Appelée à l'ouverture d'une bataille ([TacticsLevel]). Le déplacement est
## instantané et sans cible : le joueur doit voir son armée dès la première
## image, pas y arriver en glissant depuis l'endroit où l'écran précédent avait
## laissé la caméra.
func frame_board(center: Vector3, radius: float, size: float) -> void:
	res.target = null
	velocity = Vector3.ZERO
	global_position = center
	res.boundary_center = center
	res.boundary_radius = radius

	TacticsFraming.apply_projection(cam_node, size)
	serv.zoom.adopt_current_zoom(cam_node)

	# Sans cela, la vue arriverait à l'inclinaison de repos en glissant sur une
	# poignée d'images — visible, et pour rien.
	t_pivot.rotation_degrees = Vector3(res.x_rot, res.y_rot, 0)
	p_pivot.rotation_degrees = Vector3(0, 0, res.z_rot)


## Moves the camera based on input
func move_camera(h: float, v: float, joystick: bool, delta: float) -> void:
	serv.move.move_camera(h, v, joystick, delta, self)


## Rotates the camera
func rotate_camera(delta: float, twist: int = 0) -> void:
	res.is_rotating = true
	serv.rotate.add_angle_to_horiz_rotation(twist)
	serv.rotate.rotate_camera(delta, t_pivot, p_pivot)


## Enables free look mode
func free_look(delta: float) -> void:
	serv.rotate.free_look(delta, t_pivot, p_pivot)


## Zooms the camera
static func zoom_camera(zoom_increment: float) -> void:
	serv.zoom.zoom_camera(zoom_increment)


## Resets camera zoom to default
func reset_cam_zoom() -> void:
	serv.zoom.reset_cam_zoom(cam_node, self)
