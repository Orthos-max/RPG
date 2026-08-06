class_name LocalAIBrain
extends RefCounted
## IA locale heuristique — le camp adverse reste jouable sans le pont CielAI.
##
## Logique 100% pure (dictionnaires seulement, aucun nœud) pour être testable
## en headless. Le service d'opposition traduit les pions en dictionnaires,
## demande une décision, puis applique le résultat au moteur.
##
## Un "unit" est un dictionnaire :
##   name, team, col, row, hp, max_hp, atk, def, res, movement, attack_range,
##   is_magical, terrain_def
## Une "tuile atteignable" est un dictionnaire : col, row, def_bonus

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

#region Poids heuristiques
const W_KILL: float = 40.0        ## Prime à l'achèvement d'une cible
const W_DAMAGE: float = 2.0       ## Prime aux dégâts infligés
const W_WEAKNESS: float = 12.0    ## Prime aux cibles déjà blessées
const W_THREAT: float = 1.5       ## Prime à neutraliser les cibles dangereuses
const W_COUNTER: float = 1.2      ## Pénalité pour les dégâts de riposte
const W_TERRAIN: float = 2.5      ## Prime au terrain défensif
const W_EXPOSURE: float = 3.0     ## Pénalité pour se retrouver à portée de plusieurs ennemis
const W_APPROACH: float = 1.0     ## Pénalité de distance quand on ne peut pas frapper
#endregion


## Gabarit d'unité — sert de base aux appelants et aux tests.
static func make_unit(data: Dictionary = {}) -> Dictionary:
	var u: Dictionary = {
		"name": "", "team": "opponent",
		"col": 0, "row": 0,
		"hp": 10, "max_hp": 10,
		"atk": 5, "def": 0, "res": 0,
		"movement": 4, "attack_range": 1, "min_range": 1,
		"is_magical": false, "terrain_def": 0,
	}
	u.merge(data, true)
	return u


## Distance de Manhattan entre deux positions (unités ou tuiles).
static func distance(a: Dictionary, b: Dictionary) -> int:
	return absi(int(a.get("col", 0)) - int(b.get("col", 0))) \
		+ absi(int(a.get("row", 0)) - int(b.get("row", 0)))


## Dégâts attendus d'un attaquant sur un défenseur, terrain compris.
static func expected_damage(attacker: Dictionary, defender: Dictionary) -> float:
	var def_stat: int = int(defender.get("res", 0)) if bool(attacker.get("is_magical", false)) \
		else int(defender.get("def", 0))
	var terrain: int = int(defender.get("terrain_def", 0))
	return float(maxi(0, int(attacker.get("atk", 0)) - def_stat - terrain))


## L'unité est-elle vivante ?
static func is_alive(u: Dictionary) -> bool:
	return int(u.get("hp", 0)) > 0


## Intérêt d'attaquer `enemy` depuis une position donnée.
## `dist` sert à savoir si l'ennemi peut riposter.
static func score_target(actor: Dictionary, enemy: Dictionary, difficulty: int, dist: int = 1) -> float:
	var profile: Dictionary = DIFF.get_profile(difficulty)
	var dmg: float = expected_damage(actor, enemy)
	var score: float = dmg * W_DAMAGE

	# Achèvement : la priorité numéro un en Fire Emblem.
	if dmg >= float(enemy.get("hp", 0)):
		score += W_KILL

	# Cibles déjà entamées (pondéré par la difficulté).
	var max_hp: float = maxf(1.0, float(enemy.get("max_hp", 1)))
	var missing: float = 1.0 - (float(enemy.get("hp", 0)) / max_hp)
	score += missing * W_WEAKNESS * float(profile["focus_weak"])

	# Neutraliser d'abord ce qui fait mal.
	score += expected_damage(enemy, actor) * W_THREAT

	# Riposte : si l'ennemi nous atteint à cette distance, on encaisse.
	# La portée minimale compte autant que la maximale — charger un archer, c'est
	# précisément le moyen de lui retirer sa riposte.
	if can_strike(enemy, dist):
		var counter: float = expected_damage(enemy, actor)
		score -= counter * W_COUNTER * (2.0 - float(profile["aggression"]))
		# Se faire tuer en ripostant est rédhibitoire.
		if counter >= float(actor.get("hp", 0)):
			score -= W_KILL

	return score


## L'unité atteint-elle une cible située à `dist` cases ?
##
## Même règle que le moteur de combat ([method WeaponType.reaches]), mais exprimée
## sur le dictionnaire que manipule l'IA : elle n'a pas accès aux ressources.
static func can_strike(unit: Dictionary, dist: int) -> bool:
	if dist <= 0:
		return false
	return dist >= int(unit.get("min_range", 1)) and dist <= int(unit.get("attack_range", 1))


## Nombre d'ennemis pouvant frapper cette case au tour suivant (mouvement + portée).
static func exposure(tile: Dictionary, enemies: Array) -> int:
	var count: int = 0
	for e: Dictionary in enemies:
		if not is_alive(e):
			continue
		var reach: int = int(e.get("movement", 0)) + int(e.get("attack_range", 1))
		if distance(tile, e) <= reach:
			count += 1
	return count


## Décision complète pour un pion.
## [param actor] Le pion adverse qui joue.
## [param allies] Ses alliés (pour éviter de s'empiler).
## [param enemies] Les pions du camp d'en face.
## [param reachable] Tuiles atteignables ce tour-ci ({col,row,def_bonus}).
## [param difficulty] DifficultyDB.Level
## [returns] {action: "attack"|"move"|"wait", target: String, col: int, row: int, score: float, reason: String}
static func decide(actor: Dictionary, allies: Array, enemies: Array, reachable: Array,
		difficulty: int = DIFF.Level.NORMAL) -> Dictionary:
	var result: Dictionary = {
		"action": "wait", "target": "", "col": int(actor.get("col", 0)),
		"row": int(actor.get("row", 0)), "score": 0.0, "reason": "aucune option",
	}

	var live_enemies: Array = []
	for e: Dictionary in enemies:
		if is_alive(e):
			live_enemies.append(e)
	if live_enemies.is_empty() or not is_alive(actor):
		result["reason"] = "aucune cible vivante"
		return result

	var profile: Dictionary = DIFF.get_profile(difficulty)
	var use_exposure: bool = bool(profile["uses_exposure"])
	var atk_range: int = int(actor.get("attack_range", 1))

	# Cases candidates : les tuiles atteignables + la position actuelle (rester sur place).
	var spots: Array = _candidate_spots(actor, allies, reachable)

	# --- 1. Peut-on frapper depuis une case atteignable ? ---
	var best: Dictionary = {}
	var best_score: float = -INF
	for spot: Dictionary in spots:
		var here: Dictionary = actor.duplicate()
		here["col"] = int(spot["col"])
		here["row"] = int(spot["row"])
		here["terrain_def"] = int(spot.get("def_bonus", 0))

		for enemy: Dictionary in live_enemies:
			var dist: int = distance(here, enemy)
			if dist > atk_range or dist == 0:
				continue
			var score: float = score_target(here, enemy, difficulty, dist)
			score += float(spot.get("def_bonus", 0)) * W_TERRAIN
			if use_exposure:
				score -= float(exposure(here, live_enemies)) * W_EXPOSURE
			if score > best_score:
				best_score = score
				best = {
					"action": "attack", "target": str(enemy.get("name", "")),
					"col": here["col"], "row": here["row"], "score": score,
					"reason": "attaque %s (dmg≈%d)" % [
						str(enemy.get("name", "")), int(expected_damage(here, enemy))
					],
				}

	if not best.is_empty():
		return best

	# --- 2. Sinon : se rapprocher de la cible la plus intéressante ---
	var target: Dictionary = _best_approach_target(actor, live_enemies, difficulty)
	if target.is_empty():
		return result

	best_score = -INF
	for spot: Dictionary in spots:
		var dist: int = distance(spot, target)
		var score: float = -float(dist) * W_APPROACH
		score += float(spot.get("def_bonus", 0)) * W_TERRAIN
		if use_exposure:
			# En approche, on accepte le risque proportionnellement à l'agressivité.
			score -= float(exposure(spot, live_enemies)) * W_EXPOSURE * (1.0 - float(profile["aggression"]))
		if score > best_score:
			best_score = score
			result = {
				"action": "move", "target": str(target.get("name", "")),
				"col": int(spot["col"]), "row": int(spot["row"]), "score": score,
				"reason": "approche de %s (dist %d)" % [str(target.get("name", "")), dist],
			}

	return result


## Choisit la cible à rejoindre quand aucune attaque n'est possible ce tour-ci.
static func _best_approach_target(actor: Dictionary, enemies: Array, difficulty: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -INF
	for enemy: Dictionary in enemies:
		# Valeur de la cible, atténuée par l'éloignement.
		var score: float = score_target(actor, enemy, difficulty, 99) - float(distance(actor, enemy)) * W_APPROACH
		if score > best_score:
			best_score = score
			best = enemy
	return best


## Cases retenues : celles atteignables et libres, plus la case actuelle.
static func _candidate_spots(actor: Dictionary, allies: Array, reachable: Array) -> Array:
	var occupied: Dictionary = {}
	for a: Dictionary in allies:
		if str(a.get("name", "")) == str(actor.get("name", "")):
			continue
		if is_alive(a):
			occupied["%d,%d" % [int(a.get("col", -1)), int(a.get("row", -1))]] = true

	var spots: Array = [{
		"col": int(actor.get("col", 0)),
		"row": int(actor.get("row", 0)),
		"def_bonus": int(actor.get("terrain_def", 0)),
	}]
	for t: Dictionary in reachable:
		var key: String = "%d,%d" % [int(t.get("col", -1)), int(t.get("row", -1))]
		if occupied.has(key):
			continue
		if int(t.get("col", -1)) == int(actor.get("col", 0)) and int(t.get("row", -1)) == int(actor.get("row", 0)):
			continue
		spots.append({
			"col": int(t.get("col", 0)),
			"row": int(t.get("row", 0)),
			"def_bonus": int(t.get("def_bonus", 0)),
		})
	return spots
