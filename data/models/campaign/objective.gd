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
		Kind.SEIZE: return "Prendre la case (%d, %d)" % [
			int(objective.get("col", 0)), int(objective.get("row", 0))
		]
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
