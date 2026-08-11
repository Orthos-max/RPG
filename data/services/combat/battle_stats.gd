class_name BattleStats
extends RefCounted
## Bilan chiffré d'une bataille, relu depuis le journal de [BattleRecorder].
##
## Le journal enregistrait déjà tout ce qu'il faut — chaque assaut avec son
## `crit`, chaque mort avec son camp — mais personne ne le relisait : l'écran de
## fin annonçait la victoire sans dire ce qu'elle avait coûté. Ce script ne
## compte rien lui-même en cours de bataille ; il relit après coup. Aucun
## compteur à tenir à jour dans le service de combat, donc aucun compteur à
## oublier de remettre à zéro.
##
## Les événements sont lus par leur `kind_name` (et non par l'énumération
## [BattleRecorder.Kind]) : un replay relu depuis un fichier JSON se résume
## exactement comme la bataille en cours.

## Camp d'un pion, tel que [BattleRecorder] l'écrit dans les morts.
const PLAYER_TEAM: String = "player"


## Bilan vide — sert de gabarit : toutes les clés existent toujours.
static func empty() -> Dictionary:
	return {
		"turns": 0,
		"exp_gained": 0,
		"gold_gained": 0,
		"enemies_defeated": 0,
		"allies_fallen": 0,
		"crits": 0,
		"crits_taken": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
	}


## Résume une liste d'événements de [BattleRecorder].
##
## [param player_names] Noms affichés des unités du joueur — c'est le seul moyen
## de savoir de quel côté un assaut a été porté : le journal note qui frappe,
## pas pour quel camp. Un nom inconnu est donc compté comme adverse ; les alliés
## de circonstance (PNJ, invités) doivent figurer dans la liste, sans quoi leurs
## coups seraient portés au crédit de l'ennemi.
static func from_events(events: Array, player_names: Array = []) -> Dictionary:
	var out: Dictionary = empty()

	var allies: Dictionary = {}
	for unit_name in player_names:
		allies[str(unit_name)] = true

	for event: Dictionary in events:
		match str(event.get("kind_name", "")):
			"attack":
				if not bool(event.get("hit", false)):
					continue  # Un coup manqué ne fait ni dégât ni critique.
				var damage: int = int(event.get("damage", 0))
				if allies.has(str(event.get("attacker", ""))):
					out["damage_dealt"] = int(out["damage_dealt"]) + damage
					if bool(event.get("crit", false)):
						out["crits"] = int(out["crits"]) + 1
				else:
					out["damage_taken"] = int(out["damage_taken"]) + damage
					if bool(event.get("crit", false)):
						out["crits_taken"] = int(out["crits_taken"]) + 1
			"death":
				if str(event.get("team", "")) == PLAYER_TEAM:
					out["allies_fallen"] = int(out["allies_fallen"]) + 1
				else:
					out["enemies_defeated"] = int(out["enemies_defeated"]) + 1
			"turn_start":
				out["turns"] = maxi(int(out["turns"]), int(event.get("turn", 0)))

	return out


## XP totale accumulée depuis le niveau 1, montées de niveau comprises.
##
## Les points d'expérience d'une unité repartent de zéro à chaque niveau : lire
## `exp` seul ferait apparaître une montée de niveau comme une perte d'XP. On
## remet donc les échelons franchis dans la somme.
static func total_exp(level: int, exp_points: int) -> int:
	var total: int = exp_points
	for step: int in range(1, maxi(level, 1)):
		total += EXPCalculator.exp_for_next_level(step)
	return total


## Lignes du bilan, prêtes à afficher : `[[libellé, valeur], …]`.
##
## L'ordre est celui d'un compte rendu de bataille : le déroulé (tours), la
## récolte (XP, or), puis les pertes des deux camps.
##
## Les deux camps ont chacun leur ligne, et chaque libellé nomme le sien :
## « Unités tombées » ne disait pas de quel côté elles étaient tombées, et se
## lisait donc comme le total des morts de la bataille — juste au-dessous du
## compte des ennemis vaincus, qui en fait déjà partie.
static func rows(summary: Dictionary) -> Array:
	var out: Array = [
		["Tours joués", str(int(summary.get("turns", 0)))],
		["XP gagnée", "+%d" % int(summary.get("exp_gained", 0))],
	]

	# L'or n'a de sens qu'en campagne : une carte d'essai n'en rapporte pas, et
	# afficher « +0 or » ferait croire à une victoire mal payée.
	if summary.has("gold"):
		out.append(["Or gagné", "+%d (total %d)" % [
			int(summary.get("gold_gained", 0)), int(summary["gold"])]])
	elif int(summary.get("gold_gained", 0)) != 0:
		out.append(["Or gagné", "+%d" % int(summary["gold_gained"])])

	out.append_array([
		["Ennemis vaincus", str(int(summary.get("enemies_defeated", 0)))],
		["Alliés tombés", str(int(summary.get("allies_fallen", 0)))],
		["Coups critiques", str(int(summary.get("crits", 0)))],
		["Critiques subis", str(int(summary.get("crits_taken", 0)))],
		["Dégâts infligés", str(int(summary.get("damage_dealt", 0)))],
		["Dégâts subis", str(int(summary.get("damage_taken", 0)))],
	])
	return out
