class_name TacticsPawnSprite
extends Sprite3D
## Handles the visual representation and animation of a pawn in the tactics game
##
## Deux sortes de planches cohabitent, et le nœud s'adapte à celle qu'il reçoit :
##
## - **Le pack Tiny Swords** ([PawnLook]) : une bande horizontale d'images
##   carrées, une seule vue (l'unité regarde à droite), animée dans le temps.
##   C'est ce que porte un pion dès que sa classe a une correspondance.
## - **Les planches de fiche** en 48 × 96 : une colonne, deux rangées — le
##   visage en haut, le dos en bas — choisies selon l'orientation, sans
##   animation. C'est le repli quand le pack manque ou qu'une classe n'y a pas
##   d'équivalent, et c'est ce que montrent encore les menus.
##
## Rien d'autre ne change : la sélection, la surbrillance et le déplacement ne
## regardent que le [TacticsPawn], jamais sa figurine.

## Animation state machine playback controller
var animator: AnimationNodeStateMachinePlayback = null
## Current frame of the sprite animation
var curr_frame: int = 0

## Reference to the AnimationTree node
@onready var animation_tree: AnimationTree = $AnimationTree
## Reference to the Label3D node displaying the pawn's name
@onready var character_ui_name_label: Label3D = $CharacterUI/NameLabel
## Hauteur du nœud dans la scène, lue avant que l'AnimationTree ne la pilote.
##
## Le `_ready` d'un enfant passe avant celui de son parent : la valeur est donc
## celle de `pawn.tscn`, jamais une image de saut prise au vol. C'est le repère
## à partir duquel la ligne de pieds du pack retombe sur la case.
@onready var _base_y: float = position.y

## L'apparence tirée du pack, ou {} si le pion porte une planche de fiche.
var _look: Dictionary = {}
## Les deux planches du pack, déjà chargées : {"idle": Texture2D, "run": Texture2D}
var _clips: Dictionary = {}
## La boucle en cours ("idle" ou "run"), et de quoi la dérouler.
var _clip: String = ""
var _clip_frames: int = 1
var _clip_fps: float = PawnLook.IDLE_FPS
var _clip_time: float = 0.0


## Sets up the pawn sprite with the given stats and expertise
##
## @param stats: The Stats resource containing pawn data
## @param expertise: The pawn's expertise (class or type)
func setup(stats: Stats, expertise: String) -> void:
	var playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/playback"]
	if playback is AnimationNodeStateMachinePlayback:
		animator = playback
	else:
		push_error("Expected AnimationNodeStateMachinePlayback, but got " + str(typeof(playback)))
		return

	animator.start("IDLE")
	animation_tree.active = true
	_look = PawnLook.for_stats(stats, TeamData.side_for_camp_node(_camp()))
	if _look.is_empty():
		_wear_stats_sheet(stats)
	else:
		_wear_pack_sheets()
	character_ui_name_label.text = stats.override_name if stats.override_name else expertise


## Déroule la boucle du pack. Sans pack, il n'y a qu'une image par vue : rien à
## faire, et `frame` reste au choix de [method rotate_sprite].
func _process(delta: float) -> void:
	if _look.is_empty() or _clip_frames <= 1:
		return
	_clip_time += delta
	frame = int(_clip_time * _clip_fps) % _clip_frames


## Starts the appropriate animation based on the pawn's movement and state
##
## @param move_direction: The direction the pawn is moving in
## @param is_jumping: Whether the pawn is currently jumping
func start_animator(move_direction: Vector3, is_jumping: bool) -> void:
	if not _look.is_empty():
		_play(&"run" if move_direction != Vector3.ZERO else &"idle")
	if move_direction == Vector3.ZERO:
		animator.travel("IDLE")
	elif is_jumping:
		animator.travel("JUMP")


## Rotates the sprite to face the camera and selects the appropriate frame
##
## @param _global_basis: The global basis of the pawn
func rotate_sprite(_global_basis: Basis) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	# Get forward vector of the camera (looking down the negative Z-axis)
	var _camera_forward: Vector3 = -camera.global_basis.z
	# Measure how much the pawn faces towards or away from camera
	var _scalar: float = _global_basis.z.dot(_camera_forward)

	# Le produit `basis.x · avant_caméra` vaut `marche · droite_caméra` : positif,
	# le pion se dirige vers la droite de l'écran.
	var goes_right: bool = _global_basis.x.dot(_camera_forward) > 0

	if not _look.is_empty():
		# Le pack ne dessine qu'un profil, tourné vers la droite : il n'y a pas
		# de rangée de dos à choisir, seulement un miroir à poser ou non.
		flip_h = not goes_right
		return

	# Determine if the sprite should be flipped horizontally
	flip_h = goes_right
	# Choix de la rangée. Attention au signe : `look_at_direction()` ajoute un PI
	# à l'angle, donc `basis.z` pointe dans le sens de la marche, pas à l'opposé.
	# Un scalaire négatif veut donc dire « le pion vient vers nous », et c'est
	# alors la rangée du HAUT — celle du visage — qu'il faut. La rangée du bas
	# porte le dos. C'est l'inverse de ce que la lecture naïve suggère.
	if _scalar < -0.306: # vient vers la caméra : on voit son visage
		frame = curr_frame
	elif _scalar > 0.306: # s'éloigne : on voit son dos
		frame = curr_frame + 1 * TacticsPawnResource.ANIMATION_FRAMES
	# Entre les deux seuils, la frame ne change pas. Sur les quatre directions de
	# la grille le scalaire vaut ±0,435 : la marge est mince mais jamais franchie.


## Adjusts the pawn's position to the center of its current tile
##
## @param pawn: The TacticsPawn to adjust
## @return: Whether the adjustment was successful
func adjust_to_center(pawn: TacticsPawn) -> bool:
	if pawn.get_tile() and not pawn.res.is_moving:
		pawn.global_position = pawn.get_tile().global_position
		return true
	return false


#region Habillage
## La planche de la fiche : une colonne, deux rangées, aucune animation.
func _wear_stats_sheet(stats: Stats) -> void:
	_clips.clear()
	_clip = ""
	texture = load(stats.sprite) as Texture2D
	hframes = 1
	vframes = 2
	frame = 0
	offset = Vector2.ZERO
	pixel_size = 0.01


## Les deux planches du pack, posées pieds sur la case.
##
## `offset` se calcule une fois pour toutes : les deux boucles d'une même unité
## partagent la taille de cellule et la ligne de pieds, donc changer de boucle
## ne déplace pas la figurine.
func _wear_pack_sheets() -> void:
	_clips = {
		&"idle": load(str(_look["idle"])) as Texture2D,
		&"run": load(str(_look["run"])) as Texture2D,
	}
	pixel_size = float(_look["pixel_size"])
	vframes = 1

	# Une cellule est carrée : la hauteur de la planche donne son côté.
	var cell: float = float(_clips[&"idle"].get_height())
	# Le pied doit tomber à `hover` au-dessus de la case, alors que le nœud est
	# suspendu à `_base_y` et que la texture est centrée sur lui.
	var ground: float = (float(_look["hover"]) - _base_y) / pixel_size
	offset = Vector2(0, float(_look["foot"]) - cell / 2.0 + ground)

	_clip = ""
	_play(&"idle")


## Passe à une boucle du pack (sans rien faire si c'est déjà elle).
func _play(clip: StringName) -> void:
	if _clip == clip or not _clips.has(clip):
		return
	_clip = clip
	texture = _clips[clip]
	# La bande est horizontale et ses cellules sont carrées : autant d'images que
	# la largeur contient de fois la hauteur. Rien à tenir à jour à la main quand
	# le pack change le nombre de poses d'une animation.
	hframes = maxi(1, int(texture.get_width() / texture.get_height()))
	_clip_frames = hframes
	_clip_fps = PawnLook.RUN_FPS if clip == &"run" else PawnLook.IDLE_FPS
	_clip_time = 0.0
	frame = 0


## Le nœud de camp qui porte ce pion (`TacticsPlayer`, `TacticsOpponent`…).
func _camp() -> Node:
	var pawn: Node = get_parent()
	return pawn.get_parent() if pawn else null
#endregion
