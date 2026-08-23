class_name TacticsPawnSprite
extends Sprite3D
## Handles the visual representation and animation of a pawn in the tactics game
##
## Deux sortes de planches cohabitent, et le nœud s'adapte à celle qu'il reçoit :
##
## - **Le pack Tiny Swords** ([PawnLook]) : une bande horizontale d'images
##   carrées, une seule vue (l'unité regarde à droite), animée dans le temps.
##   C'est ce que porte un pion dès que sa classe a une correspondance.
## - **Les planches maison** ([constant PawnLook.CUSTOM_SHEETS]) : même chose,
##   mais la grille est annoncée au lieu d'être déduite — celle de l'elfe rousse
##   est une colonne de deux images. Une fiche y a droit en désignant sa planche.
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
## Les planches déjà chargées, par boucle : {&"idle": {texture, rows, foot}, …}
##
## Le repos et la course y sont toujours ; le coup, la blessure et la chute
## seulement quand le personnage les a dessinés.
var _clips: Dictionary = {}
## La boucle en cours, et de quoi la dérouler.
var _clip: StringName = &""
var _clip_frames: int = 1
var _clip_fps: float = PawnLook.IDLE_FPS
var _clip_time: float = 0.0
## La passe jouée une fois (coup, blessure, chute) et le temps qu'il lui reste.
##
## Tant qu'elle court, elle a la main : ni le repos ni la course ne peuvent la
## couper. C'est la seule règle de priorité du nœud, et elle suffit — le combat
## ne demande jamais deux passes à la fois.
var _oneshot: StringName = &""
var _oneshot_left: float = 0.0
## Vrai quand la dernière image doit rester à l'écran : un mort ne se relève pas.
var _oneshot_holds: bool = false
## Vrai une fois la pose finale atteinte : plus rien ne rhabille la figurine.
##
## Le pion continue d'appeler [method start_animator] à chaque image, mort ou
## vif — sans ce verrou, la chute se jouait bien, puis le cadavre se relevait au
## repos une image plus tard.
var _frozen: bool = false
## De combien la ligne de pieds doit descendre sous le centre du nœud.
##
## Ne dépend que de la case et du nœud, jamais de la planche : calculé une fois à
## l'habillage, il resserre le calcul d'`offset` à chaque changement de boucle.
var _ground: float = 0.0


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
	if _look.is_empty():
		return

	# Une passe se déroule sans reboucler : sa dernière image est sa conclusion,
	# et le modulo la ferait repartir au premier temps du geste.
	if not _oneshot.is_empty():
		_oneshot_left -= delta
		if _oneshot_left > 0.0:
			_clip_time += delta
			frame = mini(int(_clip_time * _clip_fps), _clip_frames - 1)
			return
		_end_oneshot()
		return

	if _clip_frames <= 1:
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


#region Passes de combat
## Joue une passe une fois, puis rend la main au repos.
##
## C'est la porte d'entrée du combat sur la figurine : [TacticsPawnCombatService]
## l'appelle au moment du coup, de la blessure et de la chute, sans jamais
## demander si la planche existe. Elle n'existe pas la plupart du temps — le pack
## Tiny Swords ne dessine que le repos et la course, une planche de fiche ne
## dessine rien du tout — et c'est exactement pourquoi l'absence rend 0.0 au lieu
## de se plaindre : brancher une animation ne doit pas obliger tous les
## personnages à en avoir une.
##
## La chute fait exception à « rend la main au repos » : sa dernière image reste,
## le temps que le combat retire le pion.
##
## [param clip] &"attack", &"die" ou &"hurt".
## [returns] la durée de la passe en secondes, 0.0 si le personnage ne l'a pas.
func play_clip(clip: StringName) -> float:
	if _look.is_empty() or not _clips.has(clip):
		return 0.0

	var frames: int = _wear_clip(clip)
	if frames <= 0:
		return 0.0

	_oneshot = clip
	_oneshot_holds = clip == &"die"
	_oneshot_left = float(frames) / maxf(1.0, _clip_fps)
	return _oneshot_left


## Le coup porté. Voir [method play_clip].
func play_attack() -> float:
	return play_clip(&"attack")


## Le coup encaissé. Voir [method play_clip].
func play_hurt() -> float:
	return play_clip(&"hurt")


## La chute — la figurine reste sur sa dernière image. Voir [method play_clip].
func play_die() -> float:
	return play_clip(&"die")


## Range la passe qui vient de finir.
func _end_oneshot() -> void:
	var holds: bool = _oneshot_holds
	_oneshot = &""
	_oneshot_left = 0.0
	_oneshot_holds = false
	if not holds:
		_play(&"idle")
		return
	# Figer, c'est ramener la boucle à une seule image : [method _process] s'arrête
	# de lui-même, et la pose finale tient jusqu'au prochain habillage.
	frame = maxi(0, hframes * vframes - 1)
	_clip_frames = 1
#endregion


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
	_clip = &""
	_oneshot = &""
	_oneshot_left = 0.0
	_oneshot_holds = false
	texture = load(stats.sprite) as Texture2D
	hframes = 1
	vframes = 2
	frame = 0
	offset = Vector2.ZERO
	pixel_size = 0.01


## Toutes les planches annoncées par [PawnLook], chargées d'un coup.
##
## Le pack n'en donne que deux ; un personnage dessiné pour lui-même peut en
## donner cinq. Le nœud ne fait pas la différence : il prend ce qu'on lui tend et
## joue ce qu'il a.
func _wear_pack_sheets() -> void:
	_clips.clear()
	var sources: Dictionary = _look.get("clips", {})
	for clip: String in PawnLook.CLIPS:
		if not sources.has(clip):
			continue
		var part: Dictionary = sources[clip]
		var sheet: Texture2D = load(str(part["file"])) as Texture2D
		if not sheet:
			continue
		_clips[StringName(clip)] = {
			"texture": sheet, "rows": int(part["rows"]), "foot": int(part["foot"]),
		}

	pixel_size = float(_look["pixel_size"])
	# Le pied doit tomber à `hover` au-dessus de la case, alors que le nœud est
	# suspendu à `_base_y` et que la texture est centrée sur lui. Le reste de
	# l'`offset` dépend de la planche, et se règle donc à chaque changement de
	# boucle ([method _wear_clip]) : rien n'oblige une chute à se caler sur un repos.
	_ground = (float(_look["hover"]) - _base_y) / pixel_size

	_clip = &""
	_oneshot = &""
	_oneshot_left = 0.0
	_oneshot_holds = false
	_play(&"idle")


## Passe à une boucle (sans rien faire si c'est déjà elle).
##
## Une passe en cours ne se laisse pas couper : c'est ici que la marche et le
## repos, appelés à chaque image par [method start_animator], cessent d'effacer
## le coup d'épée à peine commencé.
func _play(clip: StringName) -> void:
	if not _oneshot.is_empty() or _clip == clip:
		return
	_wear_clip(clip)


## Pose une planche et prépare son défilé.
##
## [returns] le nombre d'images de la boucle, 0 si le personnage ne l'a pas.
func _wear_clip(clip: StringName) -> int:
	if not _clips.has(clip):
		return 0

	var entry: Dictionary = _clips[clip]
	var sheet: Texture2D = entry["texture"]
	_clip = clip
	texture = sheet
	# Une cellule est carrée : le côté est la hauteur divisée par les rangées, et
	# la largeur dit combien de colonnes suivent. Le pack range ses poses en bande
	# (une rangée), une planche maison les empile (une colonne) — et une planche
	# plus large que haute, comme la chute de l'épéiste, garde sa marge autour du
	# personnage sans que rien n'ait à le savoir.
	vframes = maxi(1, int(entry["rows"]))
	var cell: int = maxi(1, sheet.get_height() / vframes)
	hframes = maxi(1, sheet.get_width() / cell)
	_clip_frames = hframes * vframes
	_clip_fps = PawnLook.fps_for(clip)
	_clip_time = 0.0
	frame = 0
	offset = Vector2(0, float(entry["foot"]) - float(cell) / 2.0 + _ground)
	return _clip_frames


## Le nœud de camp qui porte ce pion (`TacticsPlayer`, `TacticsOpponent`…).
func _camp() -> Node:
	var pawn: Node = get_parent()
	return pawn.get_parent() if pawn else null
#endregion
