class_name EXPCalculator
extends RefCounted
## Fire Emblem experience point calculator
## Computes EXP gained from combat based on level difference and kill/damage.

# Base EXP values
const BASE_KILL_EXP: int = 30
const BASE_DAMAGE_EXP: int = 10
const BASE_HEAL_EXP: int = 15

# Level difference multiplier (per level above/below)
const LEVEL_DIFF_FACTOR: float = 3.0

# Minimum EXP per action
const MIN_EXP: int = 1

# EXP required per level (FE-style scaling)
const EXP_TO_LEVEL: Array[int] = [
	0,    # Level 1
	30,   # Level 2
	40,   # Level 3
	50,   # Level 4
	60,   # Level 5
	70,   # Level 6
	80,   # Level 7
	90,   # Level 8
	100,  # Level 9
	100,  # Level 10
	100,  # Level 11
	100,  # Level 12
	100,  # Level 13
	100,  # Level 14
	100,  # Level 15
	100,  # Level 16
	100,  # Level 17
	100,  # Level 18
	100,  # Level 19
	100,  # Level 20
]


## Calculate EXP gained for killing an enemy
## Formula: BASE_KILL_EXP + (enemy_level - attacker_level) * LEVEL_DIFF_FACTOR
## Minimum 1 EXP, bonus for killing a promoted enemy (+10)
static func exp_for_kill(attacker_level: int, defender_level: int, defender_promoted: bool = false) -> int:
	var base: int = BASE_KILL_EXP + int((defender_level - attacker_level) * LEVEL_DIFF_FACTOR)
	if defender_promoted:
		base += 10
	return max(MIN_EXP, base)


## Calculate EXP gained for damaging an enemy (without killing)
static func exp_for_damage(attacker_level: int, defender_level: int) -> int:
	return max(MIN_EXP, BASE_DAMAGE_EXP + int((defender_level - attacker_level) * LEVEL_DIFF_FACTOR))


## Get EXP required to reach the next level
static func exp_for_next_level(current_level: int) -> int:
	if current_level < 1:
		return EXP_TO_LEVEL[0]
	if current_level >= EXP_TO_LEVEL.size():
		return 100  # Max level
	return EXP_TO_LEVEL[current_level]


## Check if unit has enough EXP to level up
static func can_level_up(current_level: int, current_exp: int) -> bool:
	return current_exp >= exp_for_next_level(current_level) and current_level < 20
