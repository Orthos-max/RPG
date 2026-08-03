class_name TacticsOpponent
extends TacticsParticipant
## Handles opponent AI actions and decision-making
## 
## Service: [TacticsOpponentService]

## Service handling opponent-specific logic and operations
var opponent_serv: TacticsOpponentService


## Initializes the TacticsOpponent node
func _ready() -> void:
	super._ready() # Call the parent's _ready function
	opponent_serv = TacticsOpponentService.new(res, camera, controls, arena) # Initialize the opponent service
	_apply_difficulty_handicap()


## Applique le handicap de difficulté au camp adverse (P2 — équilibrage).
## Les pions sont déjà initialisés à ce stade : _ready() remonte des enfants vers le parent.
func _apply_difficulty_handicap() -> void:
	var session: Node = get_node_or_null("/root/GameSession")
	if not session:
		return
	var campaign: Node = get_node_or_null("/root/Campaign")
	var chapter_index: int = int(campaign.chapter_index) if campaign else 0

	var applied: Dictionary = {}
	for p in get_children():
		if p is TacticsPawn and p.stats:
			applied = DifficultyDB.apply_to_stats(p.stats, session.difficulty, chapter_index)

	if not applied.is_empty() and (int(applied["stat_bonus"]) != 0 or int(applied["hp_bonus"]) != 0):
		print_rich("[color=orange]⚖ Difficulté %s — adversaire %+d stats / %+d PV[/color]" % [
			DifficultyDB.get_level_name(session.difficulty),
			int(applied["stat_bonus"]), int(applied["hp_bonus"])
		])


## Checks if the opponent's pawn is properly configured
##
## @return: Whether the pawn is configured
func is_pawn_configured() -> bool:
	return opponent_serv.is_pawn_configured(self) # Delegate to the service


## Chooses a pawn for the opponent to act with
func choose_pawn() -> void:
	opponent_serv.choose_pawn(self) # Delegate to the service


## Initiates the action of chasing the nearest enemy
func chase_nearest_enemy() -> void:
	opponent_serv.chase_nearest_enemy(self, get_node("../TacticsPlayer")) # Delegate to the service


## Checks if the opponent's pawn has finished moving
func is_pawn_done_moving() -> void:
	opponent_serv.is_pawn_done_moving() # Delegate to the service


## Chooses a pawn for the opponent to attack
func choose_pawn_to_attack() -> void:
	opponent_serv.choose_pawn_to_attack() # Delegate to the service
