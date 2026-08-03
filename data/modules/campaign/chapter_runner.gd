class_name ChapterRunner
extends Node
## Pilote un chapitre de campagne à l'intérieur d'un [TacticsLevel].
##
## Trois responsabilités :
##   1. appliquer le roster persistant aux pions du niveau (déploiement) ;
##   2. compter les tours et évaluer l'objectif du chapitre ([ObjectiveDB]) ;
##   3. renvoyer le résultat (victoire/défaite + objectifs secondaires) à [Main].

signal chapter_finished(victory: bool, bonuses: Array, reason: String)

const OBJ = preload("res://data/models/campaign/objective.gd")
const EXECUTOR = preload("res://data/models/world/ai/ai_executor.gd")

## Intervalle d'évaluation de l'objectif (secondes)
const CHECK_INTERVAL: float = 0.5

var chapter: ChapterData = null
var level: TacticsLevel = null

var turn: int = 1
var _finished: bool = false
var _accum: float = 0.0
var _turn_counted: bool = false
var _deployed_names: Array = []


## Branche le runner sur un niveau chargé.
func setup(target_level: TacticsLevel, target_chapter: ChapterData) -> void:
	level = target_level
	chapter = target_chapter


func _ready() -> void:
	# Le niveau finit de s'initialiser sur la frame suivante : on attend.
	await get_tree().process_frame
	_apply_roster()


func _process(delta: float) -> void:
	if _finished or not chapter or not level or not is_instance_valid(level):
		return

	_count_turns()

	_accum += delta
	if _accum < CHECK_INTERVAL:
		return
	_accum = 0.0

	var snapshot: Dictionary = build_snapshot()
	if snapshot["player_units"].is_empty() and snapshot["enemy_units"].is_empty():
		return  # Niveau pas encore peuplé.

	var verdict: Dictionary = OBJ.evaluate(chapter.objective, snapshot)
	var status: int = int(verdict["status"])
	if status == OBJ.Status.IN_PROGRESS:
		return

	_finished = true
	var victory: bool = status == OBJ.Status.VICTORY
	var bonuses: Array = OBJ.evaluate_bonuses(chapter.bonus_objectives, snapshot) if victory else []
	chapter_finished.emit(victory, bonuses, str(verdict["reason"]))


## Instantané de la bataille, au format attendu par [ObjectiveDB].
func build_snapshot() -> Dictionary:
	return {
		"turn": turn,
		"seized": false,
		"player_units": _units_of(level.player),
		"enemy_units": _units_of(level.opponent),
	}


## État des unités du joueur, pour reporter XP/PV dans le roster persistant.
func player_unit_snapshots() -> Array:
	var out: Array = []
	if not level or not level.player or not is_instance_valid(level.player):
		return out
	for p in level.player.get_children():
		if not p is TacticsPawn or not is_instance_valid(p):
			continue
		var s = p.stats
		var unit_name: String = EXECUTOR.display_name(p)
		out.append({
			"id": unit_name.to_lower().replace(" ", "_"),
			"name": unit_name,
			"hp": s.hp, "max_hp": s.max_hp,
			"exp": s.exp, "level": s.level,
			"class_id": s.character_class, "is_promoted": s.is_promoted,
			"str": s.str, "mag": s.mag, "skl": s.skl, "spd": s.spd,
			"lck": s.lck, "def": s.def, "res": s.res, "movement": s.movement,
		})
	return out


#region Internes
func _units_of(team: Node) -> Array:
	var units: Array = []
	if not team or not is_instance_valid(team):
		return units
	for p in team.get_children():
		if p is TacticsPawn and is_instance_valid(p) and p.stats:
			units.append({"name": EXECUTOR.display_name(p), "hp": p.stats.hp})
	return units


## Un tour complet = les deux camps ont épuisé leurs actions (le niveau les réinitialise).
func _count_turns() -> void:
	if not level.participant or not is_instance_valid(level.participant):
		return
	var anyone_can_act: bool = level.participant.can_act(level.player) \
		or level.participant.can_act(level.opponent)
	if not anyone_can_act:
		if not _turn_counted:
			turn += 1
			_turn_counted = true
	else:
		_turn_counted = false


## Applique le roster persistant aux pions du niveau et retire les non-déployés.
func _apply_roster() -> void:
	var campaign: Node = get_node_or_null("/root/Campaign")
	if not campaign or not level or not level.player or campaign.roster.is_empty():
		return

	_deployed_names.clear()
	for p in level.player.get_children():
		if not p is TacticsPawn or not is_instance_valid(p) or not p.stats:
			continue
		var unit_name: String = EXECUTOR.display_name(p)
		var id: String = unit_name.to_lower().replace(" ", "_")
		var unit: Dictionary = campaign.get_unit(id)

		if unit.is_empty():
			continue  # Pion propre au niveau (PNJ, invité) : on n'y touche pas.

		if not bool(unit.get("alive", true)) or not id in campaign.deployment:
			p.queue_free()  # Non déployé (ou tombé) : il ne participe pas.
			continue

		_deployed_names.append(unit_name)
		_apply_unit(p.stats, unit)

	print_rich("[color=cyan]📋 Déploiement : %s[/color]" % (
		", ".join(_deployed_names) if not _deployed_names.is_empty() else "roster par défaut du niveau"
	))


func _apply_unit(stats: Stats, unit: Dictionary) -> void:
	stats.level = int(unit.get("level", stats.level))
	stats.exp = int(unit.get("exp", stats.exp))
	stats.character_class = int(unit.get("class_id", stats.character_class))
	stats.is_promoted = bool(unit.get("is_promoted", stats.is_promoted))
	stats.max_hp = int(unit.get("max_hp", stats.max_hp))
	stats.hp = clampi(int(unit.get("hp", stats.max_hp)), 1, stats.max_hp)
	stats.str = int(unit.get("str", stats.str))
	stats.mag = int(unit.get("mag", stats.mag))
	stats.skl = int(unit.get("skl", stats.skl))
	stats.spd = int(unit.get("spd", stats.spd))
	stats.lck = int(unit.get("lck", stats.lck))
	stats.def = int(unit.get("def", stats.def))
	stats.res = int(unit.get("res", stats.res))
	stats.movement = int(unit.get("movement", stats.movement))
	stats.apply_class_growths(stats.character_class)
	stats.attack_power = stats.get_total_attack()
#endregion
