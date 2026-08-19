extends Node
## BattleRecorder (autoload) — journal des événements de bataille + replay persisté.
##
## Deux usages :
##   1. alimenter `ai_state.json` avec les événements récents (Ciel voit ce qui
##      vient de se passer : qui a attaqué qui, pour combien, qui est tombé) ;
##   2. écrire un replay JSON complet dans `user://replays/` pour analyser après
##      coup les décisions de Ciel.

signal event_recorded(event: Dictionary)

const REPLAY_DIR: String = "user://replays"
## Nombre d'événements conservés en mémoire pour l'état exporté
const RECENT_LIMIT: int = 20
## Garde-fou : au-delà, on tronque le replay en mémoire
const MAX_EVENTS: int = 4000

enum Kind {
	TURN_START = 0,
	MOVE = 1,
	ATTACK = 2,
	HEAL = 3,
	DEATH = 4,
	LEVEL_UP = 5,
	PROMOTION = 6,
	COMMAND_REJECTED = 7,
	OBJECTIVE = 8,
	CHEST = 9,
}

## Tous les événements de la partie courante
var events: Array = []
## Compteur monotone : sert d'identifiant d'événement et de curseur pour Ciel
var seq: int = 0
## Métadonnées de la partie en cours (mode, difficulté, chapitre)
var meta: Dictionary = {}

var _started_at: String = ""


func _ready() -> void:
	start_battle({})


## Démarre (ou redémarre) l'enregistrement d'une bataille.
func start_battle(battle_meta: Dictionary = {}) -> void:
	events.clear()
	seq = 0
	meta = battle_meta.duplicate(true)
	_started_at = Time.get_datetime_string_from_system(true)


## Enregistre un événement. [param data] est fusionné dans l'entrée.
func record(kind: int, data: Dictionary = {}) -> Dictionary:
	seq += 1
	var event: Dictionary = {
		"seq": seq,
		"kind": kind,
		"kind_name": kind_name(kind),
		"t": Time.get_ticks_msec(),
	}
	event.merge(data, true)
	events.append(event)
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)
	event_recorded.emit(event)
	return event


## Raccourcis de journalisation
func record_turn_start(team: String, turn: int) -> void:
	record(Kind.TURN_START, {"team": team, "turn": turn})


func record_move(pawn: String, from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	record(Kind.MOVE, {
		"pawn": pawn, "from": {"col": from_col, "row": from_row},
		"to": {"col": to_col, "row": to_row},
	})


func record_attack(attacker: String, defender: String, damage: int, hit: bool,
		crit: bool, double_hit: bool, defender_hp: int) -> void:
	record(Kind.ATTACK, {
		"attacker": attacker, "defender": defender, "damage": damage,
		"hit": hit, "crit": crit, "double": double_hit, "defender_hp": defender_hp,
	})


func record_heal(healer: String, target: String, amount: int, target_hp: int) -> void:
	record(Kind.HEAL, {"healer": healer, "target": target, "amount": amount, "target_hp": target_hp})


func record_death(pawn: String, team: String, killer: String = "") -> void:
	record(Kind.DEATH, {"pawn": pawn, "team": team, "killer": killer})


## Un coffre vidé — l'or et l'objet passent par ici, et nulle part ailleurs.
##
## Le bandeau ([Toast]), la ligne d'historique ([BattleHistory]) et l'or du bilan
## ([BattleStats]) se déduisent tous de cet événement : [BattleChests] verse la
## récompense, le journal la raconte. Une seule source, donc jamais deux comptes
## qui divergent.
func record_chest(pawn: String, col: int, row: int, gold: int, item: String) -> void:
	record(Kind.CHEST, {
		"pawn": pawn, "cell": {"col": col, "row": row}, "gold": gold, "item": item,
	})


func record_rejected_command(action: String, code: int, reason: String) -> void:
	record(Kind.COMMAND_REJECTED, {"action": action, "code": code, "reason": reason})


## Les N derniers événements, pour l'état exporté vers Ciel.
func recent(limit: int = RECENT_LIMIT) -> Array:
	if events.size() <= limit:
		return events.duplicate(true)
	return events.slice(events.size() - limit).duplicate(true)


## Événements postérieurs à un curseur (Ciel n'a qu'à mémoriser le dernier seq lu).
func since(cursor: int) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if int(e.get("seq", 0)) > cursor:
			out.append(e)
	return out


## Écrit le replay complet sur disque. Renvoie le chemin, ou "" en cas d'échec.
func save_replay(label: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPLAY_DIR))
	var stamp: String = Time.get_datetime_string_from_system(true).replace(":", "-")
	var suffix: String = ("_" + label) if not label.is_empty() else ""
	var path: String = "%s/replay_%s%s.json" % [REPLAY_DIR, stamp, suffix]

	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_error("[BattleRecorder] Écriture du replay impossible : %s" % path)
		return ""
	f.store_string(JSON.stringify({
		"started_at": _started_at,
		"ended_at": Time.get_datetime_string_from_system(true),
		"meta": meta,
		"event_count": events.size(),
		"events": events,
	}, "\t"))
	f.close()
	return path


static func kind_name(kind: int) -> String:
	match kind:
		Kind.TURN_START: return "turn_start"
		Kind.MOVE: return "move"
		Kind.ATTACK: return "attack"
		Kind.HEAL: return "heal"
		Kind.DEATH: return "death"
		Kind.LEVEL_UP: return "level_up"
		Kind.PROMOTION: return "promotion"
		Kind.COMMAND_REJECTED: return "command_rejected"
		Kind.OBJECTIVE: return "objective"
		Kind.CHEST: return "chest"
		_: return "event"
