class_name ObjectiveDB
extends RefCounted
## Objectifs de chapitre et conditions de victoire/défaite.
##
## Logique pure : on lui passe un instantané de la bataille, elle renvoie l'état
## de l'objectif. Le niveau n'a plus qu'à afficher le résultat.

enum Kind {
	ROUT = 0,          ## Vaincre tous les ennemis
	DEFEAT_BOSS = 1,   ## Vaincre un ennemi désigné
	SURVIVE = 2,       ## Tenir N tours
	PROTECT = 3,       ## Garder une unité en vie jusqu'au bout
	SEIZE = 4,         ## Occuper une case précise avec le seigneur
}

enum Status {
	IN_PROGRESS = 0,
	VICTORY = 1,
	DEFEAT = 2,
}

## Objectifs secondaires (récompense, rejouabilité)
enum Bonus {
	NO_LOSSES = 0,     ## Aucune unité perdue
	SPEED_RUN = 1,     ## Terminer sous un nombre de tours
	FULL_ROUT = 2,     ## Éliminer tous les ennemis même si l'objectif est autre
}


## Nom lisible d'un type d'objectif
static func kind_name(kind: int) -> String:
	match kind:
		Kind.ROUT: return "Vaincre tous les ennemis"
		Kind.DEFEAT_BOSS: return "Vaincre le commandant"
		Kind.SURVIVE: return "Survivre"
		Kind.PROTECT: return "Protéger"
		Kind.SEIZE: return "Prendre le point de commandement"
		_: return "Objectif"


## Description d'un objectif configuré
## [param objective] {kind, target, turns}
static func describe(objective: Dictionary) -> String:
	var kind: int = int(objective.get("kind", Kind.ROUT))
	match kind:
		Kind.DEFEAT_BOSS: return "Vaincre %s" % str(objective.get("target", "le commandant"))
		Kind.SURVIVE: return "Survivre %d tours" % int(objective.get("turns", 5))
		Kind.PROTECT: return "Protéger %s" % str(objective.get("target", "l'allié"))
		Kind.SEIZE:
			var where: String = "le point de commandement (%d, %d)" % [
				int(objective.get("col", 0)), int(objective.get("row", 0))
			]
			var seizer: String = str(objective.get("seizer", ""))
			return "Prendre %s avec %s" % [where, seizer] if not seizer.is_empty() \
				else "Prendre %s" % where
		_: return kind_name(kind)


## Évalue l'objectif à partir d'un instantané de bataille.
## [param objective] {kind, target, turns, col, row}
## [param snapshot] {
##     turn: int, seized: bool,
##     player_units: [{name, hp}], enemy_units: [{name, hp}]
##   }
## [returns] {status: Status, reason: String}
static func evaluate(objective: Dictionary, snapshot: Dictionary) -> Dictionary:
	var turn: int = int(snapshot.get("turn", 1))
	var players: Array = snapshot.get("player_units", [])
	var enemies: Array = snapshot.get("enemy_units", [])

	# Défaite universelle : plus personne debout côté joueur.
	if not players.is_empty() and _alive_count(players) == 0:
		return {"status": Status.DEFEAT, "reason": "Toutes vos unités sont tombées"}

	var kind: int = int(objective.get("kind", Kind.ROUT))
	var target: String = str(objective.get("target", ""))

	match kind:
		Kind.ROUT:
			if _alive_count(enemies) == 0:
				return {"status": Status.VICTORY, "reason": "Ennemis anéantis"}

		Kind.DEFEAT_BOSS:
			if not _is_alive_named(enemies, target):
				return {"status": Status.VICTORY, "reason": "%s est vaincu" % target}

		Kind.SURVIVE:
			var needed: int = int(objective.get("turns", 5))
			if turn > needed:
				return {"status": Status.VICTORY, "reason": "%d tours tenus" % needed}
			if _alive_count(enemies) == 0:
				return {"status": Status.VICTORY, "reason": "Ennemis anéantis avant la fin"}

		Kind.PROTECT:
			# Tant qu'aucune unité n'est listée, il n'y a rien à juger : au premier
			# frame d'une bataille, le camp n'est pas encore peuplé et la protégée
			# serait déclarée perdue avant même d'entrer en scène.
			if players.is_empty():
				return {"status": Status.IN_PROGRESS, "reason": describe(objective)}
			if not _is_alive_named(players, target):
				return {"status": Status.DEFEAT, "reason": "%s est tombé" % target}
			if _alive_count(enemies) == 0:
				return {"status": Status.VICTORY, "reason": "%s est sauf" % target}
			var limit: int = int(objective.get("turns", 0))
			if limit > 0 and turn > limit:
				return {"status": Status.VICTORY, "reason": "%s a tenu %d tours" % [target, limit]}

		Kind.SEIZE:
			if bool(snapshot.get("seized", false)):
				return {"status": Status.VICTORY, "reason": "Point de commandement pris"}

	return {"status": Status.IN_PROGRESS, "reason": describe(objective)}


## Évalue les objectifs secondaires au moment de la victoire.
## [param bonuses] Liste de {kind, turns}
## [returns] Liste de {kind, achieved, label}
static func evaluate_bonuses(bonuses: Array, snapshot: Dictionary) -> Array:
	var results: Array = []
	var turn: int = int(snapshot.get("turn", 1))
	var players: Array = snapshot.get("player_units", [])
	var enemies: Array = snapshot.get("enemy_units", [])

	for b: Dictionary in bonuses:
		var kind: int = int(b.get("kind", Bonus.NO_LOSSES))
		var achieved: bool = false
		var label: String = ""
		match kind:
			Bonus.NO_LOSSES:
				achieved = _alive_count(players) == players.size()
				label = "Aucune perte"
			Bonus.SPEED_RUN:
				var limit: int = int(b.get("turns", 10))
				achieved = turn <= limit
				label = "Terminé en %d tours ou moins" % limit
			Bonus.FULL_ROUT:
				achieved = _alive_count(enemies) == 0
				label = "Tous les ennemis éliminés"
		results.append({"kind": kind, "achieved": achieved, "label": label})
	return results


## Unité que le chapitre demande de garder en vie ("" si l'objectif est autre).
##
## Un objectif PROTECT n'a de sens que si la protégée est réellement sur le
## champ de bataille : le chapitre doit l'imposer au déploiement
## ([member ChapterData.required_units]), sinon le joueur pourrait la laisser
## au camp et perdre à la première évaluation.
static func protected_target(objective: Dictionary) -> String:
	if int(objective.get("kind", Kind.ROUT)) != Kind.PROTECT:
		return ""
	return str(objective.get("target", ""))


## Case à prendre d'un objectif « prise de point » — (-1, -1) si sans objet.
static func seize_target(objective: Dictionary) -> Vector2i:
	if int(objective.get("kind", Kind.ROUT)) != Kind.SEIZE:
		return Vector2i(-1, -1)
	return Vector2i(int(objective.get("col", -1)), int(objective.get("row", -1)))


## Le point de commandement est-il tenu ?
##
## [param units] Unités du joueur : [{name, hp, col, row}].
## Le chapitre peut nommer un `seizer` — tradition Fire Emblem où seul le
## seigneur prend le point. Sans lui, n'importe quelle unité debout suffit.
static func is_seized(objective: Dictionary, units: Array) -> bool:
	var target: Vector2i = seize_target(objective)
	if target.x < 0 or target.y < 0:
		return false

	var seizer: String = str(objective.get("seizer", ""))
	for u: Dictionary in units:
		if int(u.get("hp", 0)) <= 0:
			continue
		if not seizer.is_empty() and str(u.get("name", "")) != seizer:
			continue
		if int(u.get("col", -1)) == target.x and int(u.get("row", -1)) == target.y:
			return true
	return false


#region Internes
static func _alive_count(units: Array) -> int:
	var n: int = 0
	for u: Dictionary in units:
		if int(u.get("hp", 0)) > 0:
			n += 1
	return n


static func _is_alive_named(units: Array, unit_name: String) -> bool:
	if unit_name.is_empty():
		return false
	for u: Dictionary in units:
		if str(u.get("name", "")) == unit_name:
			return int(u.get("hp", 0)) > 0
	return false
#endregion
