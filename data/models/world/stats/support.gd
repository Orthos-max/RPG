class_name SupportDB
extends RefCounted
## Fire Emblem support system — tracks support points, ranks, and bonuses
## between pairs of characters. Supports C→B→A→S ranks.

#region Support Rank Enum
enum Rank {
	NONE = 0,
	C = 1,
	B = 2,
	A = 3,
	S = 4,
}
#endregion

#region Support Point Thresholds
## Points required to unlock each rank
const THRESHOLDS: Dictionary = {
	Rank.C: 30,
	Rank.B: 60,
	Rank.A: 100,
	Rank.S: 160,
}
#endregion

#region Point Gains
const PTS_ADJACENT_TURN: int = 2   ## Per turn standing adjacent
const PTS_DUAL_COMBAT: int = 3     ## Per combat where both fight same enemy
const PTS_NEARBY_COMBAT: int = 1   ## Per combat when within support range
const PTS_HEAL: int = 2            ## Healing an ally with staff
#endregion

#region Support Range
## Maximum tile distance for support bonuses to apply
const SUPPORT_RANGE: int = 3
#endregion

#region Default Bonuses
## [Hit, Crit, Avoid, CritAvoid] per rank
const BONUSES: Dictionary = {
	Rank.C:   {"hit": 10, "crit": 0,  "avoid": 0,  "crit_avoid": 0},
	Rank.B:   {"hit": 10, "crit": 5,  "avoid": 5,  "crit_avoid": 0},
	Rank.A:   {"hit": 10, "crit": 5,  "avoid": 10, "crit_avoid": 5},
	Rank.S:   {"hit": 15, "crit": 10, "avoid": 10, "crit_avoid": 5},
}
#endregion

## Get a human-readable name for a support rank
static func rank_name(rank: int) -> String:
	match rank:
		Rank.C: return "C"
		Rank.B: return "B"
		Rank.A: return "A"
		Rank.S: return "S"
		_: return "-"


## Get the combined support bonuses for a rank
static func get_bonuses(rank: int) -> Dictionary:
	return BONUSES.get(rank, {"hit": 0, "crit": 0, "avoid": 0, "crit_avoid": 0})


## Get the point threshold for a rank
static func threshold_for(rank: int) -> int:
	return THRESHOLDS.get(rank, 999)
