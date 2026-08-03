class_name TacticsPlayer
extends TacticsParticipant
## Handles player-specific actions and logic in the tactics game
##
## Les actions humaines (sélection, portées, ciblage, déplacement) vivent
## désormais dans [TacticsParticipant] : en hotseat (M2), le camp adverse peut
## lui aussi être joué par un humain et a besoin des mêmes actions.
## Ce nœud ne garde que ce qui est propre au camp du joueur 1.
## Service: [TacticsPlayerService]


## Processes player-related physics updates
##
## @param _delta: Time elapsed since the last frame (unused)
func _physics_process(_delta: float) -> void:
	# Toggle the display of enemy stats
	player_serv.toggle_enemy_stats(get_node("../TacticsOpponent"))


## Checks if the player's pawn is properly configured
##
## @return: Whether the player's pawn is configured
func is_pawn_configured() -> bool:
	return player_serv.is_pawn_configured(self)
