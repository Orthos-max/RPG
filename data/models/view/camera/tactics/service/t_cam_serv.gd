class_name TacticsCameraService
extends RefCounted
## Service class for TacticsCamera

var res: TacticsCameraResource
var controls: TacticsControlsResource
var move: TacticsCameraMovementService
var zoom: TacticsCameraZoomService
var rotate: TacticsCameraRotationService
var pan: TacticsCameraPanningService

const DELTA_SMOOTHING: int = 10
const MIN_VEL: float = 0.01


## Initialize the service and its sub-services
func _init(_res: TacticsCameraResource, _controls: TacticsControlsResource) -> void:
	res = _res
	controls = _controls
	move = TacticsCameraMovementService.new(res, controls)
	zoom = TacticsCameraZoomService.new(res)
	rotate = TacticsCameraRotationService.new(res, controls)
	pan = TacticsCameraPanningService.new(res)


## Set up initial camera properties
func setup(camera: TacticsCamera, cam_node: Camera3D) -> void:
	if not controls:
		push_error("TacticsControls needs a ControlResource from /data/models/view/control/tactics/")
	if not res:
		push_error("TacticsCamera needs a CameraResource (T Cam) from /data/models/view/camera/tactics/")
	else:
		# `fov` en perspective, `size` en orthographique : le zoom sait laquelle.
		res.current_fov = TacticsCameraZoomService.current_zoom(cam_node)
		res.target_fov = res.current_fov
		res.viewport_size = camera.get_viewport().size


## Main processing function for camera behavior
func process(delta: float, camera: TacticsCamera) -> void:
	rotate.check_free_look_activation(delta, camera)
	
	if res.in_free_look:
		rotate.free_look(delta, camera.t_pivot, camera.p_pivot)
	elif not res.is_snapping_to_quad:
		rotate.rotate_camera(delta, camera.t_pivot, camera.p_pivot)
	
	var input_dir: Vector2 = InputCaptureResource.cam_direction
	if input_dir != Vector2.ZERO:
		# La main du joueur prime sur le suivi : tant qu'une cible est posée,
		# move_camera refuse de bouger et focus_on_target ramène la vue à chaque
		# image. Déplacer la caméra, c'est décider de ne plus suivre.
		res.target = null
		pan.wasd_pan(delta, camera, input_dir)
	elif pan.is_cursor_near_edge(camera) and not controls.is_joystick:
		pan.edge_pan(delta, camera)
	else:
		res.panning_timer = 0.0
		move.stabilize_camera(delta, camera)
	
	if camera.velocity.length() < MIN_VEL:
		camera.velocity = Vector3.ZERO
	
	move.focus_on_target(camera, delta)
	zoom.apply_zoom_smoothing(camera, delta)
