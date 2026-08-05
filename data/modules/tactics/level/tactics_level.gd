class_name TacticsLevel
extends Node3D
## Tactics system initialization & turn_stage management.
##
## This is the Tactics Level's topmost script.[br][br]
## Dependencies: [TacticsArena], [TacticsTile], [TacticsCamera], [TacticsControls], [TacticsParticipant], [TacticsOpponent], [TacticsPlayer], [TacticsPawn]

const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")
const ArmySplitClass = preload("res://data/models/world/combat/team/army_split.gd")
const GuestCampScript = preload("res://data/modules/tactics/level/participants/opponent/tactics_opponent.gd")

#region: --- Props ---
## Camera resource for the tactics system
@export var camera: TacticsCameraResource = load("res://data/models/view/camera/tactics/camera.tres")
## Rayon de promenade de la caméra, en unités monde.
##
## 0 — le cas normal — laisse [TacticsFraming] le mesurer sur le plateau : un
## rayon écrit à la main est juste pour la carte qui l'a reçu et faux pour
## toutes les autres, à commencer par celles que le joueur dessine lui-même.
## Une valeur positive reste un choix de chapitre, et prime.
@export var camera_boundary_radius: float = 0.0
## UI control resource for the tactics system
@export var ui_control: TacticsControlsResource = load("res://data/models/view/control/tactics/control.tres")
## Reference to the TacticsParticipant node
var participant: TacticsParticipant
## Reference to the TacticsPlayer node
var player: TacticsPlayer = null
## Reference to the TacticsOpponent node
var opponent: TacticsOpponent
## Troisième camp, créé seulement quand la session le demande (M5)
var guest: TacticsParticipant = null
## Camps en jeu, dans l'ordre où ils prennent leur tour
var camps: Array[Node3D] = []
## Reference to the TacticsArena node
var arena: TacticsArena
## Current turn stage (0: init, 1: handle)
var turn_stage: int = 0
#endregion

#region: --- Processing ---
func _ready() -> void:
	if not ui_control:
		push_error("TacticsControls needs a ControlResource from /data/models/view/control/tactics/")
	if not camera:
		push_error("TacticsCamera needs a CameraResource from /data/models/view/camera/tactics/")

	# Initialize node references
	participant = $TacticsParticipant
	player = $TacticsParticipant/TacticsPlayer
	opponent = $TacticsParticipant/TacticsOpponent
	arena = $TacticsArena

	TacticsScenery.apply_to(self) # Ciel, lumière et ombres portées
	arena.configure_tiles() # Configure arena tiles
	_setup_camps() # Trois camps si la session le demande (M5), deux sinon
	participant.configure(camera, ui_control) # Configure participant with camera and UI control

	_frame_board() # Poser la caméra sur ce plateau-ci, pas sur celui d'avant

func _physics_process(delta: float) -> void:
	match turn_stage:
		0: _init_turn() # Initialize turn
		1: _handle_turn(delta) # Handle ongoing turn


## Pose la caméra sur ce plateau : centre mesuré, rayon, cadrage d'ouverture.
##
## La caméra vit dans `main.tscn` et survit aux niveaux : sans ce recadrage,
## une bataille s'ouvre là où l'écran précédent avait laissé la vue.
func _frame_board() -> void:
	if not camera or not arena:
		return
	var bounds: Dictionary = TacticsFraming.board_bounds(arena)
	var radius: float = camera_boundary_radius if camera_boundary_radius > 0.0 \
			else TacticsFraming.pan_radius(arena)
	camera.frame_board(bounds["center"], radius, TacticsFraming.opening_size(arena))
#endregion

#region: --- Camps ---
## Établit la liste des camps en jeu et crée le troisième si besoin.
func _setup_camps() -> void:
	var session: Node = get_node_or_null("/root/GameSession")
	if session and bool(session.three_way):
		_spawn_guest_camp(float(session.guest_share))

	camps = []
	var sides: Array = session.battle_sides() if session else [
		TeamDataClass.Side.PLAYER, TeamDataClass.Side.OPPONENT
	]
	for side: int in sides:
		var camp: Node3D = participant.get_node_or_null(TeamDataClass.camp_node_name(side)) as Node3D
		if camp:
			camps.append(camp)
	# Repli : une carte sans camp reconnu resterait bloquée au tour 0.
	if camps.is_empty():
		camps = [player, opponent]


## Crée le troisième camp en scindant l'armée adverse (M5).
##
## Aucune carte n'a de troisième armée : plutôt que d'en ajouter une à chaque
## scène, on confie la moitié des pions adverses au nouveau camp. Le partage est
## déterministe ([ArmySplit]), donc identique sur les deux machines d'une partie
## en réseau sans le moindre échange.
func _spawn_guest_camp(share: float) -> void:
	if participant.get_node_or_null("TacticsGuest"):
		return

	var pawns: Array[Node] = []
	for p in opponent.get_children():
		if p is TacticsPawn:
			pawns.append(p)

	var indices: Array[int] = ArmySplitClass.guest_indices(pawns.size(), share)
	if indices.is_empty():
		push_warning("Trois camps demandés mais l'armée adverse (%d pion(s)) ne peut pas être scindée." % pawns.size())
		return

	var camp := Node3D.new()
	camp.set_script(GuestCampScript)
	camp.name = "TacticsGuest"
	participant.add_child(camp)
	camp.owner = self

	for i: int in indices:
		pawns[i].reparent(camp, true)

	guest = camp as TacticsParticipant
	print_rich("[color=green]⚑ Troisième camp : %d pion(s) confiés à %s[/color]" % [
		indices.size(), _guest_label()
	])


## Nom du contrôleur du troisième camp, pour le journal.
func _guest_label() -> String:
	var session: Node = get_node_or_null("/root/GameSession")
	if not session:
		return TeamDataClass.side_name(TeamDataClass.Side.GUEST)
	return TeamDataClass.controller_name(session.controller_for(TeamDataClass.Side.GUEST))
#endregion

#region: --- Methods ---
## Checks requirements to begin the first turn.[br]Used by [TacticsPlayer], [TacticsOpponent]
func _init_turn() -> void:
	for camp: Node3D in camps:
		if not participant.is_configured(camp):
			return
	turn_stage = 1 # Tous les camps sont en place

## Turn state management.[br]Used by [TacticsPlayer], [TacticsOpponent]
func _handle_turn(delta: float) -> void:
	DebugLog.debug_nospam("player_can_act", participant.can_act(player))

	# Les camps jouent dans l'ordre établi par la session : joueur, invité, Ciel.
	for camp: Node3D in camps:
		if not participant.can_act(camp):
			continue
		if not participant.is_configured(camp):
			participant.configure(camera, ui_control)
		participant.act(delta, camp == player, camp)
		return

	if DebugLog.debug_enabled:
		print_rich("[color=green]0Oo◦° O-----------------------------------O °◦oO0[/color]")
		print_rich("[color=green]0Oo◦°[/color][color=red] >}=----->> [/color][color=yellow][ Turn reset! ][/color][color=red] <<-----={< [/color][color=green]°◦oO0[/color]")
		print_rich("[color=green]0Oo◦° O-----------------------------------O °◦oO0[/color]")
	for camp: Node3D in camps:
		camp.reset_turn(camp)
#endregion
