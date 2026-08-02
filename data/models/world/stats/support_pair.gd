class_name SupportPair
extends RefCounted
## Tracks the support relationship between two specific characters.
## Stores points, current rank, and provides rank-up checks.

var char_a: String  ## First character's name (alphabetically sorted key)
var char_b: String  ## Second character's name
var points: int = 0 ## Accumulated support points
var rank: int = SupportDB.Rank.NONE
var rank_reached: Array[bool] = [true, false, false, false, false]  ## Which rank conversations have been seen


## Create a support pair between two characters
func _init(_char_a: String, _char_b: String) -> void:
	# Sort alphabetically for consistent pairing
	if _char_a.naturalnocasecmp_to(_char_b) <= 0:
		char_a = _char_a
		char_b = _char_b
	else:
		char_a = _char_b
		char_b = _char_a


## Add support points. Returns the new rank if a rank-up occurred, else -1.
func add_points(amount: int) -> int:
	if rank >= SupportDB.Rank.S:
		return -1  # Maxed out
	
	points += amount
	
	# Check for rank-up (can skip ranks if enough points)
	var new_rank: int = rank
	for r in range(rank + 1, SupportDB.Rank.S + 1):
		if points >= SupportDB.threshold_for(r):
			new_rank = r
	
	if new_rank > rank:
		rank = new_rank
		return rank
	
	return -1


## Check if this pair has a conversation available at the current rank
func has_unread_conversation() -> bool:
	return rank > SupportDB.Rank.NONE and not rank_reached[rank]


## Mark the current rank conversation as read
func mark_conversation_read() -> void:
	if rank <= SupportDB.Rank.S:
		rank_reached[rank] = true


## Get the pair key (used for dictionary lookup)
func get_key() -> String:
	return char_a + "|" + char_b


## Get the combined combat bonuses for this pair's rank
func get_bonuses() -> Dictionary:
	return SupportDB.get_bonuses(rank)


## Get display string
func to_display_string() -> String:
	return "%s ♡ %s | Rank %s (%d pts)" % [char_a, char_b, SupportDB.rank_name(rank), points]
