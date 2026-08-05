class_name TacticsCameraZoomService
extends RefCounted
## Service class for handling camera zoom in tactical view
##
## Le zoom agit sur la propriété qui gouverne l'échelle de l'image, et cette
## propriété dépend de la projection : `fov` (un angle d'ouverture) en
## perspective, `size` (une hauteur de monde) en orthographique — le cadrage
## « Awakening » de [TacticsFraming]. Écrire dans `fov` une caméra
## orthographique ne provoque aucune erreur : ça ne fait simplement rien, et le
## zoom reste muet. D'où la question posée au nœud plutôt qu'une hypothèse.

const DELTA_SMOOTHING: int = 10

var res: TacticsCameraResource


func _init(_res: TacticsCameraResource) -> void:
	res = _res


## Nom de la propriété d'échelle du nœud caméra, selon sa projection.
static func zoom_property(cam_node: Camera3D) -> StringName:
	if cam_node and cam_node.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return &"size"
	return &"fov"


## Valeur d'échelle actuellement affichée par le nœud caméra.
static func current_zoom(cam_node: Camera3D) -> float:
	if not cam_node:
		return 0.0
	return float(cam_node.get(zoom_property(cam_node)))


## Adjust the target FOV for zooming
func zoom_camera(zoom_increment: float) -> void:
	res.target_fov = clamp(res.target_fov + zoom_increment, res.min_zoom, res.max_zoom)


## Smoothly interpolate current FOV to target FOV
func apply_zoom_smoothing(camera: TacticsCamera, delta: float) -> void:
	if res.current_fov != res.target_fov:
		res.current_fov = lerp(res.current_fov, res.target_fov, (res.zoom_smoothness * DELTA_SMOOTHING) * delta)
		camera.cam_node.set(zoom_property(camera.cam_node), res.current_fov)


## Reset camera zoom to default value
func reset_cam_zoom(cam_node: Camera3D, camera: TacticsCamera) -> void:
	res.target_fov = default_zoom(cam_node)

	var tween: Tween = camera.create_tween()
	tween.tween_property(cam_node, String(zoom_property(cam_node)), res.target_fov, res.zoom_duration).set_trans(Tween.TRANS_SINE)


## Échelle de repos : l'ouverture par défaut, ou le cadrage courant du plateau.
##
## En orthographique il n'y a pas de « zoom par défaut » universel : la bonne
## valeur est celle qu'a posée le cadrage d'ouverture, propre à chaque carte.
static func default_zoom(cam_node: Camera3D) -> float:
	if zoom_property(cam_node) == &"size":
		return current_zoom(cam_node)
	return float(TacticsConfig.view.default_t_cam_zoom)


## Aligne l'état du zoom sur ce que le nœud affiche réellement.
##
## Après un recadrage, `current_fov`/`target_fov` décrivent encore l'ancienne
## échelle : le lissage repartirait aussitôt vers elle et déferait le cadrage.
func adopt_current_zoom(cam_node: Camera3D) -> void:
	res.current_fov = current_zoom(cam_node)
	res.target_fov = res.current_fov
