class_name TacticsParticipant
extends Node3D
## Handles participant (i.e. Player & Opponent) actions and decision-making
## 
## Resource Interface: [TacticsParticipantResource] -- Service: [TacticsParticipantService]
## Parent of: [TacticsPlayer], [TacticsOpponent]

## Resource containing participant data and configurations
@export var res: TacticsParticipantResource = load("res://data/models/world/combat/participant/participant.tres")
## Resource for camera-related data and configurations
@export var camera: TacticsCameraResource = load("res://data/models/view/camera/tactics/camera.tres")
## Resource for control-related data and configurations
@export var controls: TacticsControlsResource = load("res://data/models/view/control/tactics/control.tres")
## Service handling participant logic and operations
var serv: TacticsParticipantService
## Service des actions « humaines » (sélection, portées, ciblage).
## Porté par la classe de base : en hotseat (M2), les deux camps peuvent être
## joués par un humain, donc les deux ont besoin de ces actions.
var player_serv: TacticsPlayerService
## Reference to the TacticsArena node
@onready var arena: TacticsArena = %TacticsArena
## Reference to the TacticsPlayer node
@onready var player: TacticsPlayer = %TacticsPlayer
## Reference to the TacticsOpponent node
@onready var opponent: TacticsOpponent = %TacticsOpponent


## Initializes the TacticsParticipant node
func _ready() -> void:
	# Initialize the service with necessary resources
	serv = TacticsParticipantService.new(res, camera, controls)
	# Set up the service with this node as context
	serv.setup(self)
	# Actions humaines, disponibles pour les deux camps (hotseat)
	player_serv = TacticsPlayerService.new(res, camera, controls, arena)
	# Connect the skip_turn signal to the skip_turn method
	res.connect("called_skip_turn", skip_turn)


## Performs the participant's action
##
## @param delta: Time elapsed since the last frame
## @param is_player: Whether the acting participant is the player
## @param parent: The parent node of the participant
func act(delta: float, is_player: bool, parent: Node3D) -> void:
	serv.act(delta, is_player, parent, self)


## Configures the participant with camera and control resources
##
## @param my_camera: The camera resource to use
## @param my_control: The control resource to use
func configure(my_camera: Resource, my_control: Resource) -> void:
	serv.configure(my_camera, my_control)


## Checks if the participant is properly configured
##
## @param parent: The parent node of the participant
## @return: Whether the participant is configured
func is_configured(parent: Node3D) -> bool:
	return serv.is_configured(parent)


## Checks if the participant can perform an action
##
## @param parent: The parent node of the participant
## @return: Whether the participant can act
func can_act(parent: Node3D) -> bool:
	return serv.can_act(parent)


## Resets the participant's turn
##
## @param parent: The parent node of the participant
func reset_turn(parent: Node3D) -> void:
	serv.reset_turn(parent)


## Skips the participant's turn
## Le camp qui passe est celui qui joue (en hotseat, ce n'est pas toujours le joueur 1).
func skip_turn() -> void:
	var camp: Node3D = res.acting_camp if res.acting_camp and is_instance_valid(res.acting_camp) else player
	serv.skip_turn(camp)


#region Actions humaines (partagées par les deux camps — hotseat)
## Displays the available actions for the current pawn
func show_available_pawn_actions() -> void:
	player_serv.show_available_pawn_actions()


## Displays the available movement options for the current pawn
func show_available_movements() -> void:
	player_serv.show_available_movements()


## Displays the attackable targets for the current pawn
func display_attackable_targets() -> void:
	player_serv.display_attackable_targets()


## Initiates the movement of the current pawn
func move_pawn() -> void:
	player_serv.move_pawn()
#endregion


## Resets the participant's pawn references when unloading a level
func reset_participant() -> void:
	res.curr_pawn = null
	res.attackable_pawn = null
	res.stage = res.STAGE_SELECT_PAWN
	res.turn_just_started = true
