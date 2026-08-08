class_name SupportTracker
extends Node
## Manages all support relationships in a battle.
## Attached to the TacticsArena as a child node.
## Tracks support points, triggers rank-ups, and provides combat bonuses.

## Static reference to the active tracker instance
static var instance: SupportTracker = null

## All active support pairs, keyed by "NameA|NameB"
var pairs: Dictionary = {}


func _ready() -> void:
	instance = self
	print_rich("[color=cyan]💬 SupportTracker ready[/color]")


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Initialize tracker (clears all pairs for a fresh battle)
func reset() -> void:
	pairs.clear()


## Get or create a support pair between two named characters
func get_pair(name_a: String, name_b: String) -> SupportPair:
	if name_a == name_b or name_a.is_empty() or name_b.is_empty():
		return null
	
	var pair := SupportPair.new(name_a, name_b)
	var key := pair.get_key()
	
	if pairs.has(key):
		return pairs[key]
	
	pairs[key] = pair
	return pair


## Award support points for two characters standing adjacent this turn
func award_adjacent(name_a: String, name_b: String) -> void:
	var pair := get_pair(name_a, name_b)
	if not pair:
		return
	
	var new_rank := pair.add_points(SupportDB.PTS_ADJACENT_TURN)
	if new_rank >= 0:
		_announce_rank_up(pair)


## Award support points for being within support range during combat
func award_nearby_combat(name_a: String, name_b: String) -> void:
	var pair := get_pair(name_a, name_b)
	if not pair:
		return
	
	var new_rank := pair.add_points(SupportDB.PTS_NEARBY_COMBAT)
	if new_rank >= 0:
		_announce_rank_up(pair)


## Award support points for healing
func award_heal(healer_name: String, target_name: String) -> void:
	var pair := get_pair(healer_name, target_name)
	if not pair:
		return
	
	var new_rank := pair.add_points(SupportDB.PTS_HEAL)
	if new_rank >= 0:
		_announce_rank_up(pair)


## Get all support bonuses for a character from all nearby allies
## Returns the combined bonuses as a Dictionary
func get_combined_bonuses(char_name: String, nearby_allies: Array[String]) -> Dictionary:
	var result := {"hit": 0, "crit": 0, "avoid": 0, "crit_avoid": 0}
	
	for ally_name in nearby_allies:
		var pair := get_pair(char_name, ally_name)
		if pair and pair.rank > SupportDB.Rank.NONE:
			var bonuses := pair.get_bonuses()
			for key in bonuses:
				result[key] += bonuses[key]
	
	return result


## Find allies within support range of a given pawn
func get_nearby_support_allies(pawn: TacticsPawn, all_allies: Array) -> Array[String]:
	var result: Array[String] = []
	var pawn_pos: Vector3 = pawn.global_position
	
	for ally in all_allies:
		if ally == pawn:
			continue
		if not ally.is_alive():
			continue
		var dist: float = pawn_pos.distance_to(ally.global_position)
		if dist <= float(SupportDB.SUPPORT_RANGE):
			var ally_name: String = ally.stats.override_name if ally.stats.override_name else ally.stats.expertise
			result.append(ally_name)
	
	return result


## Announce a rank-up to the console
func _announce_rank_up(pair: SupportPair) -> void:
	var emoji: String = ""
	match pair.rank:
		SupportDB.Rank.C: emoji = "💚"
		SupportDB.Rank.B: emoji = "💙"
		SupportDB.Rank.A: emoji = "💜"
		SupportDB.Rank.S: emoji = "💛"
	
	print_rich("[color=%s]🫂 SUPPORT %s %s → %s Rank %s! (%d pts)[/color]" % [
		"lime", emoji,
		pair.char_a, pair.char_b,
		SupportDB.rank_name(pair.rank),
		pair.points
	])
