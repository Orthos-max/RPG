class_name TacticsPawn
extends CharacterBody3D
## Represents a pawn in the tactics game, handling movement, combat, and state management

## Resource containing control-related data and configurations
@export var controls: TacticsControlsResource = load("res://data/models/view/control/tactics/control.tres")

## Resource containing pawn-specific data and configurations
var res: TacticsPawnResource
## Service handling pawn-related logic and operations
var serv: TacticsPawnService

## Reference to the Stats node, handling pawn statistics
@onready var stats: Stats = $Expertise/Stats
## The expertise (class or type) of the pawn
@onready var expertise: String = $Expertise/Stats.expertise
## Reference to the TacticsPawnSprite node, handling visual representation
@onready var character: TacticsPawnSprite = $Character


## Initializes the TacticsPawn node
func _ready() -> void:
	res = TacticsPawnResource.new()
	serv = TacticsPawnService.new()
	serv.setup(self)
	controls.set_actions_menu_visibility(false, self)
	show_pawn_stats(false)


## Processes pawn logic every physics frame
##
## @param delta: Time elapsed since the last frame
func _physics_process(delta: float) -> void:
	serv.process(self, delta)


## Centers the pawn on its current tile
##
## @return: Whether the centering operation was successful
func center() -> bool:
	return character.adjust_to_center(self)


## Shows or hides the pawn's stats UI
##
## @param v: Whether to show (true) or hide (false) the stats
func show_pawn_stats(v: bool) -> void:
	$Character/CharacterUI.visible = v


## Gets the tile the pawn is currently on
##
## @return: The TacticsTile the pawn is on
func get_tile() -> TacticsTile:
	return $Tile.get_collider()


## Nom affiché du pion — unique au sein de son camp.
##
## Plusieurs mobs partagent le même intitulé de classe (« Brigand » ×3) : sans
## suffixe, Ciel ne pourrait pas désigner un pion précis avec `select_pawn`.
## Le suffixe vient du nom de nœud (stable, y compris après la mort d'un voisin).
func display_name() -> String:
	var base: String = base_name()
	var parent: Node = get_parent()
	if not parent:
		return base

	var homonyms: int = 0
	for sibling in parent.get_children():
		if sibling is TacticsPawn and sibling.base_name() == base:
			homonyms += 1
	if homonyms <= 1:
		return base

	return "%s#%d" % [base, _node_index()]


## Intitulé de base : nom propre s'il existe, sinon la classe.
func base_name() -> String:
	if stats and stats.override_name != "":
		return stats.override_name
	return expertise


## Indice tiré du nom de nœud ("Pawn" → 1, "Pawn3" → 3).
func _node_index() -> int:
	var node_name: String = String(name)
	var digits: String = ""
	for i in range(node_name.length() - 1, -1, -1):
		if not node_name[i].is_valid_int():
			break
		digits = node_name[i] + digits
	return int(digits) if not digits.is_empty() else 1


## Checks if the pawn is alive
##
## @return: Whether the pawn's current health is above 0
func is_alive() -> bool:
	if not stats:
		return false
	return stats.curr_health > 0


## Checks if the pawn can move
##
## @return: Whether the pawn can move and is alive
func can_pawn_move() -> bool:
	return res.can_move and is_alive()


## Checks if the pawn can attack
##
## @return: Whether the pawn can attack and is alive
func can_pawn_attack() -> bool:
	return res.can_attack and is_alive()


## Checks if the pawn can perform any action
##
## @return: Whether the pawn can move or attack, and is alive
func can_act() -> bool:
	return (res.can_move or res.can_attack) and is_alive()


## Resets the pawn's turn state
func reset_turn() -> void:
	res.reset_turn()
	# Les bonus temporaires (garde, toniques) vieillissent d'un tour.
	if stats:
		stats.tick_buffs()


## Ends the pawn's turn
func end_pawn_turn() -> void:
	res.end_pawn_turn()
	# Award support points for adjacent allies at end of turn
	_check_support_adjacency()


## Check for adjacent allies and award support points
func _check_support_adjacency() -> void:
	var tracker := SupportTracker.instance
	if not tracker:
		return
	
	var my_name: String = stats.override_name if stats.override_name else expertise
	var parent_node = get_parent()
	if not parent_node:
		return
	
	for ally in parent_node.get_children():
		if ally == self or not ally.is_alive():
			continue
		var dist: float = global_position.distance_to(ally.global_position)
		if dist <= 1.5:  # Adjacent (with slight tolerance for non-centered pawns)
			var ally_name: String = ally.stats.override_name if ally.stats.override_name else ally.expertise
			tracker.award_adjacent(my_name, ally_name)


## Initiates an attack on a target pawn
##
## @param target_pawn: The TacticsPawn to attack
## @param delta: Time elapsed since the last frame
## @return: Whether the attack was successful
func attack_target_pawn(target_pawn: TacticsPawn, delta: float) -> bool:
	return serv.attack_target_pawn(self, target_pawn, delta)


## Moves the pawn along its designated path
##
## @param delta: Time elapsed since the last frame
func move_along_path(delta: float) -> void:
	serv.movement.move_along_path(self, delta)
