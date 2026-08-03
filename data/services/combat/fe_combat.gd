class_name FECombatCalculator
extends RefCounted

const WT = preload("res://data/models/world/stats/weapon_type.gd")
const CD = preload("res://data/models/world/stats/class_data.gd")
const SKILLS = preload("res://data/models/world/stats/skill_db.gd")
## Fire Emblem combat calculator
## Computes hit rate, critical hit, damage, and double attack
## using the full FE formula with weapon triangle bonuses.

# Base hit rate added to all attacks (simulates weapon hit before weapons are implemented)
const BASE_HIT: int = 70

#region Combat Result
## Stores the outcome of a combat calculation
class CombatResult:
	var hit_rate: int = 0        ## Chance to hit (0-100)
	var crit_rate: int = 0        ## Critical hit chance (0-100)
	var damage: int = 0           ## Base damage per hit
	var crit_damage: int = 0      ## Damage on critical hit (damage × 3)
	var can_double: bool = false  ## Whether attacker performs a double attack
	var triangle_bonus: int = 0   ## Weapon triangle damage modifier
	var triangle_hit: int = 0     ## Weapon triangle hit modifier
	var is_magical: bool = false  ## Whether this is a magical attack
	var effective_mult: int = 1   ## Multiplicateur d'arme efficace (arc vs volant = 3)
	var is_effective: bool = false ## L'attaque bénéficie-t-elle d'un bonus d'efficacité
	var terrain_defense: int = 0  ## Bonus de DÉF/RÉS apporté par la tuile du défenseur
	var defense_used: int = 0     ## Défense totale opposée (stat + terrain + compétences)
	var skill_hit: int = 0        ## Précision nette apportée par les compétences
	var skill_crit: int = 0       ## Critique net apporté par les compétences
	var skill_damage: int = 0     ## Dégâts nets apportés par les compétences
	var attacker_skills: Array = [] ## Compétences actives de l'attaquant
	var defender_skills: Array = [] ## Compétences actives du défenseur
	var procs: Array = []         ## Compétences à déclenchement disponibles [{id, proc, chance}]
	var triggered: Array = []     ## Compétences réellement déclenchées lors du jet

	func _to_string() -> String:
		return "Hit: %d%% | Dmg: %d | Crit: %d%% | Double: %s | Triangle: %+d%s%s" % [
			hit_rate, damage, crit_rate, "Yes" if can_double else "No", triangle_bonus,
			(" | Efficace x%d" % effective_mult) if is_effective else "",
			(" | Terrain +%d" % terrain_defense) if terrain_defense > 0 else ""
		]


## Resolve a full combat between attacker and defender
## @param attacker: Attacking character's Stats
## @param defender: Defending character's Stats
## @param support_bonuses: Optional support bonuses {"hit": N, "crit": N, "avoid": N, "crit_avoid": N}
## @param terrain_defense: Optional terrain defense bonus (added to DEF/RES)
## Returns CombatResult with computed values
static func calculate(attacker: Stats, defender: Stats, support_bonuses: Dictionary = {}, terrain_defense: int = 0) -> CombatResult:
	var result = CombatResult.new()
	
	# Extract support bonuses (with defaults)
	var sup_hit: int = support_bonuses.get("hit", 0)
	var sup_crit: int = support_bonuses.get("crit", 0)
	var sup_avoid: int = support_bonuses.get("avoid", 0)
	var sup_crit_avoid: int = support_bonuses.get("crit_avoid", 0)
	
	# Determine if magical attack
	result.is_magical = WT.is_magical(attacker.weapon_type)
	
	# --- Damage calculation ---
	# Physical: ATK = STR + weapon_might, reduced by DEF
	# Magical:  ATK = MAG + weapon_might, reduced by RES
	# Arme efficace (arc contre volant) : le might est triplé avant réduction.
	result.effective_mult = WT.get_effective_multiplier(
		attacker.weapon_type, CD.is_flying(defender.character_class)
	)
	result.is_effective = result.effective_mult > 1
	result.terrain_defense = terrain_defense

	var atk = attacker.get_attack_stat() + attacker.weapon_might * result.effective_mult
	var def_stat = defender.res if result.is_magical else defender.def

	# --- Compétences ---
	# L'attaquant est en position d'attaque, le défenseur en position de défense :
	# chacun n'active que les compétences pertinentes à son rôle.
	var atk_ctx: Dictionary = attacker.skill_context(true, 0, CD.is_flying(defender.character_class))
	var def_ctx: Dictionary = defender.skill_context(false, terrain_defense, false)
	var atk_skills: Array = attacker.get_skills()
	var def_skills: Array = defender.get_skills()
	result.attacker_skills = atk_skills
	result.defender_skills = def_skills

	var atk_mods: Dictionary = SKILLS.aggregate(atk_skills, atk_ctx)
	var def_mods: Dictionary = SKILLS.aggregate(def_skills, def_ctx)
	result.skill_damage = int(atk_mods["damage"])
	result.skill_hit = int(atk_mods["hit"]) - int(def_mods["avoid"])
	result.skill_crit = int(atk_mods["crit"]) - int(def_mods["crit_avoid"])
	result.procs = SKILLS.active_procs(atk_skills, atk_ctx, attacker.skl)

	# Weapon triangle damage bonus
	result.triangle_bonus = WT.get_triangle_damage_bonus(
		attacker.weapon_type, defender.weapon_type
	)

	# Base damage (minimum 0, minimum 1 if triangle advantage guarantees at least 1)
	# Apply terrain defense bonus (e.g. FOREST +1 DEF, MOUNTAIN +3 DEF)
	result.defense_used = def_stat + terrain_defense + int(def_mods["defense"])
	result.damage = max(0, atk + result.triangle_bonus + result.skill_damage - result.defense_used)

	# --- Critical hit ---
	# Crit = (Skl / 2) + support_crit + compétences - defender's CritEvade (Lck + support_crit_avoid)
	result.crit_rate = max(0, attacker.get_crit() + sup_crit + result.skill_crit
		- (defender.get_crit_evade() + sup_crit_avoid))
	result.crit_damage = result.damage * 3  # FE crit = 3x damage

	# --- Hit rate ---
	# Hit = BASE + (Skl × 2) + (Lck / 2) + triangle + support_hit + compétences - (defender's Avoid + support_avoid)
	result.triangle_hit = WT.get_triangle_hit_bonus(
		attacker.weapon_type, defender.weapon_type
	)
	result.hit_rate = clampi(
		BASE_HIT + attacker.get_base_hit() + sup_hit + result.triangle_hit + result.skill_hit
			- (defender.get_avoid() + sup_avoid),
		0, 100
	)

	# --- Double attack ---
	# If attacker's Spd ≥ defender's Spd + 5, attacker doubles
	result.can_double = attacker.get_attack_speed() >= defender.get_attack_speed() + 5
	
	return result


## Roll the RNG for a combat result
## Returns:
##   - 0 = miss
##   - 1 = normal hit
##   - 2 = critical hit
##   - 3 = double hit (two normal hits)
##   - 4 = double hit with crit (one crit + one normal, or just the crit if target dies)
static func roll_combat(result: CombatResult) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var outcomes = {
		"hit": false,
		"crit": false,
		"double": false,
		"total_damage": 0,
		"hit_rate": result.hit_rate,
		"crit_rate": result.crit_rate,
		"base_damage": result.damage,
		"skills": [],  ## Compétences déclenchées pendant l'échange
	}
	
	# True hit: FE uses 2-RN system (average of 2 rolls) for more reliable hit rates
	# This makes displayed hit rates >50% more likely and <50% less likely
	var rn1 = rng.randi_range(1, 100)
	var rn2 = rng.randi_range(1, 100)
	var true_hit = (rn1 + rn2) / 2.0
	
	outcomes["hit"] = true_hit <= result.hit_rate
	
	if not outcomes["hit"]:
		outcomes["hit_rate"] = int(true_hit)  # Show the rolled value
		return outcomes  # Miss — no damage
	
	# Check for critical hit
	# In FE Awakening, crit roll is separate from hit roll
	var crit_roll = rng.randi_range(1, 100)
	outcomes["crit"] = crit_roll <= result.crit_rate
	
	# Base damage for the first hit
	var first_hit_dmg = result.crit_damage if outcomes["crit"] else result.damage
	outcomes["total_damage"] = first_hit_dmg

	# Check for double attack
	if result.can_double:
		outcomes["double"] = true
		outcomes["total_damage"] += result.damage  # Second hit is always normal damage

	# --- Compétences à déclenchement ---
	# Chaque proc est tiré séparément ; l'effet s'ajoute aux dégâts du coup.
	result.triggered = []
	for proc: Dictionary in result.procs:
		if rng.randi_range(1, 100) > int(proc["chance"]):
			continue
		result.triggered.append(proc["id"])
		outcomes["skills"].append(proc["id"])
		match str(proc["proc"]):
			"pierce":
				# Lune : la moitié de la défense opposée est ignorée.
				outcomes["total_damage"] += int(floor(float(result.defense_used) / 2.0))
			"extra_hit":
				# Astre : une frappe supplémentaire aux dégâts de base.
				outcomes["total_damage"] += result.damage

	return outcomes
