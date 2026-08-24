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
	STATUS_APPLIED = 10,  ## Une affliction vient d'être posée ([StatusDB])
	STATUS_DAMAGE = 11,   ## Une affliction se paie au début d'un tour
	BOSS_PHASE = 12,      ## Un boss franchit un seuil de PV ([BossPhases])
	KNOCKBACK = 13,       ## Un pion est repoussé par un coup ([Knockback])
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


## Une affliction posée par un coup ([StatusDB] nomme `status`).
##
## `source` est celui qui l'a posée — l'information ne se retrouve nulle part
## ailleurs une fois l'échange résolu, et c'est elle qui rend la ligne d'historique
## lisible : « la Lame venimeuse d'Elyan », et non un poison venu de nulle part.
func record_status_applied(source: String, target: String, status: String, turns: int) -> void:
	record(Kind.STATUS_APPLIED, {
		"source": source, "target": target, "status": status, "turns": turns,
	})


## Les PV qu'une affliction coûte au début d'un tour.
##
## `statuses` liste ce qui a mordu (une unité peut brûler [i]et[/i] être
## empoisonnée), et `expired` ce qui s'est dissipé dans la foulée.
func record_status_damage(pawn: String, damage: int, pawn_hp: int,
		statuses: Array = [], expired: Array = []) -> void:
	record(Kind.STATUS_DAMAGE, {
		"pawn": pawn, "damage": damage, "pawn_hp": pawn_hp,
		"statuses": statuses, "expired": expired,
	})


## Un boss vient de franchir un seuil de PV et de changer de forme.
##
## L'événement porte le [b]compte rendu de ce qui a réellement été appliqué[/b]
## ([method Stats.advance_boss_phases]) et non la phase telle qu'elle est écrite
## au catalogue : le soin est celui qui a tenu sous les PV maximum, les
## compétences sont celles qui n'étaient pas déjà connues. Un replay relu doit
## raconter la bataille qui a eu lieu, pas celle que [BossDB] promettait.
func record_boss_phase(pawn: String, phase: Dictionary) -> void:
	record(Kind.BOSS_PHASE, {
		"pawn": pawn,
		"phase": int(phase.get("number", 0)),
		"label": str(phase.get("label", "")),
		"message": str(phase.get("message", "")),
		"threshold": float(phase.get("threshold", 0.0)),
		"gains": phase.get("gains", {}),
		"healed": int(phase.get("healed", 0)),
		"learned": phase.get("learned", []),
		"cured": phase.get("cured", []),
		"pawn_hp": int(phase.get("hp", 0)),
	})


## Un pion soufflé de sa case par une compétence de repoussement.
##
## L'événement porte les [b]deux[/b] cases, et non le seul point d'arrivée : un
## replay relu doit pouvoir redessiner le plateau tour par tour, et une case
## quittée sans qu'on sache d'où laisserait un trou. `tiles` est la distance
## réellement parcourue — jamais celle que la compétence promettait — et
## `blocked` dit que quelque chose a arrêté le recul avant son terme.
func record_knockback(source: String, target: String, skill: String, tiles: int,
		from_col: int, from_row: int, to_col: int, to_row: int,
		blocked: bool = false) -> void:
	record(Kind.KNOCKBACK, {
		"source": source, "target": target, "skill": skill, "tiles": tiles,
		"from": {"col": from_col, "row": from_row},
		"to": {"col": to_col, "row": to_row},
		"blocked": blocked,
	})


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
		Kind.STATUS_APPLIED: return "status_applied"
		Kind.STATUS_DAMAGE: return "status_damage"
		Kind.BOSS_PHASE: return "boss_phase"
		Kind.KNOCKBACK: return "knockback"
		_: return "event"
