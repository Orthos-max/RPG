extends Node
## CielAI (autoload) — pont Godot ↔ Ciel.
##
## Quand le camp adverse est confié à Ciel :
##   * Godot exporte l'état complet du champ de bataille dans `ai_state.json` ;
##   * Ciel dépose un ordre dans `ai_command.json` (supprimé après lecture) ;
##   * chaque ordre est validé par [CielCommand] avant d'atteindre le moteur ;
##   * un ordre invalide est rejeté proprement, journalisé, et renvoyé dans
##     `ai_feedback.json` — le moteur n'est jamais mis dans un état incohérent ;
##   * si aucun ordre valide n'arrive à temps, l'IA locale ([LocalAIBrain]) joue
##     le tour à la place de Ciel : la partie ne peut pas se bloquer.
##
## Le protocole complet est documenté dans docs/CIEL_PROTOCOL.md

const CMD = preload("res://data/models/world/ai/ciel_command.gd")
const EXECUTOR = preload("res://data/models/world/ai/ai_executor.gd")
const CD = preload("res://data/models/world/stats/class_data.gd")
const WT = preload("res://data/models/world/stats/weapon_type.gd")
const ITEMS = preload("res://data/models/world/stats/item_db.gd")
const LOG = preload("res://data/services/combat/battle_log.gd")
const OBJ = preload("res://data/models/campaign/objective.gd")

## Émis à chaque nouvel état exporté (le réseau s'en sert pour diffuser).
signal state_exported(state: Dictionary)

## Compatibilité : reflète l'état du contrôleur adverse dans [GameSession].
static var enabled: bool = true

const STATE_FILE: String = "user://ai_state.json"
const CMD_FILE: String = "user://ai_command.json"
const FEEDBACK_FILE: String = "user://ai_feedback.json"

## Sans pion capable d'agir, on termine le tour au bout de ~4 s
const MAX_WAIT_FRAMES: int = 240
## Sans ordre valide de Ciel, l'IA locale prend la main (~10 s à 60 ips).
## C'est la patience accordée à un client qui réfléchit.
const FALLBACK_AFTER_FRAMES: int = 600
## Patience réduite (~0,5 s) une fois qu'on sait que personne ne répond.
##
## Attendre dix secondes par décision quand aucun client Ciel n'est branché fige
## le jeu à chaque tour adverse — remonté par Aurèle : « il ne se passe rien
## durant son tour ». On laisse sa chance à Ciel **une fois** ; s'il ne répond
## pas, on cesse de l'attendre jusqu'à ce qu'il se manifeste.
const FALLBACK_AFTER_FRAMES_SILENT: int = 30
## Cadence d'export de l'état hors tour adverse (1 frame sur N)
const EXPORT_EVERY_FRAMES: int = 3

var _level_ref: WeakRef = weakref(null)
var _frame: int = 0
var _wait_frames: int = 0
var _idle_frames: int = 0
## Ciel a-t-il répondu depuis le dernier repli ? Tant que non, on ne l'attend plus.
var _ciel_responsive: bool = true
var _last_state_hash: int = 0
var _seq: int = 0
var _turn_number: int = 1
var _last_turn_owner: String = ""
var _last_error: String = ""
var _last_error_code: int = CMD.Err.NONE

# Cache du camp adverse en cours de jeu
var _opponent: TacticsOpponent = null
var _participant: TacticsParticipant = null
var _cmd: Dictionary = {}
## Ordres reçus hors fichier (joueur distant) — déjà validés
var _external_queue: Array = []


# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------
func _ready() -> void:
	_write_json(STATE_FILE, {
		"protocol_version": CMD.PROTOCOL_VERSION,
		"turn": "waiting",
		"stage": 0,
		"stage_name": "waiting",
		"current_pawn": "",
		"pawns": [],
		"message": "CielAI ready.",
	})
	print("[CielAI] Ready — state path: ", ProjectSettings.globalize_path(STATE_FILE))
	print("[CielAI] Protocole v%d — commandes : %s" % [
		CMD.PROTOCOL_VERSION, ", ".join(CMD.supported_actions())
	])


func _physics_process(_delta: float) -> void:
	if not is_active():
		return

	var level: TacticsLevel = _resolve_level()
	if not level:
		return

	# On exporte dès que le niveau existe (même avant le premier tour) : Ciel voit
	# ainsi le terrain et les effectifs pendant l'initialisation, avec turn="unknown".
	_frame += 1
	if _frame % EXPORT_EVERY_FRAMES == 0:
		_export_state(level)

	# Hors tour adverse, on traite quand même le fichier de commande :
	# `toggle` est global, et tout le reste doit être rejeté (OUT_OF_TURN)
	# plutôt que de rester en attente et d'être rejoué au mauvais moment.
	if _whose_turn(level) != "opponent":
		_drain_out_of_turn_command(level)


## Le pont pilote-t-il le camp adverse ?
##
## Deux contrôleurs passent par ce même chemin validé : Ciel (ordres lus dans
## `ai_command.json`) et le joueur distant (ordres reçus par le réseau, poussés
## dans la file interne). La source de vérité reste [GameSession].
func is_active() -> bool:
	var session: Node = _session()
	if session:
		var controller: int = session.controller_for(acting_side())
		enabled = controller == TeamData.Controller.CIEL_AI \
			or controller == TeamData.Controller.REMOTE_PLAYER
	return enabled


## Camp dont le pont joue le tour en ce moment.
##
## À deux camps c'est toujours le camp rouge ; à trois (M5), le pont sert aussi
## le troisième camp quand il est tenu par l'invité distant, et il ne doit alors
## pas lire les droits du camp de Ciel.
func acting_side() -> int:
	if _opponent and is_instance_valid(_opponent):
		var side: int = TeamData.side_for_camp_node(_opponent)
		if side != -1:
			return side
	return TeamData.Side.OPPONENT


## Ordre poussé par une source externe autre que le fichier (réseau).
## Il suivra exactement la même validation que les ordres de Ciel.
## [returns] Résultat de validation ({ok, action, args, code, error}).
func push_command(cmd: Dictionary) -> Dictionary:
	var level: TacticsLevel = _resolve_level()
	var pr: TacticsParticipantResource = _participant.res if _participant else null
	var ctx: Dictionary = {
		"stage": pr.stage if pr else CMD.STAGE_SELECT_PAWN,
		"turn": _whose_turn(level),
		"acting_team": TeamData.state_team_name(acting_side()),
		"grid_size": TacticsGrid.grid_size(level.arena if level else null),
	}

	var parsed: Dictionary = CMD.validate(cmd, ctx)
	if not bool(parsed["ok"]):
		_reject(parsed)
		return parsed

	_external_queue.append(parsed)
	return parsed


# ---------------------------------------------------------------------------
# Boucle de tour adverse — appelée par TacticsParticipantTurnService
# ---------------------------------------------------------------------------
func handle_opponent_turn(delta: float, opponent: TacticsOpponent, participant: TacticsParticipant) -> void:
	_opponent = opponent
	_participant = participant

	var level: TacticsLevel = _resolve_level()
	var arena: TacticsArena = level.arena if level else null
	if not arena:
		return

	var pr: TacticsParticipantResource = participant.res
	if pr.stage > 4:
		pr.stage = 0

	_export_state(level)
	_check_global_commands()

	if not is_active():
		# Bascule vers l'IA locale : c'est turn.gd qui reprend la main au prochain frame.
		_opponent = null
		_participant = null
		return

	# Plus personne ne peut agir : on clôt le tour après un court délai de grâce.
	if _all_pawns_done(opponent) and pr.stage <= pr.STAGE_SELECT_PAWN:
		_wait_frames += 1
		if _wait_frames >= 30:
			_do_end_turn(pr)
		return

	# Verrou anti-blocage : sans ordre valide, l'IA locale joue à la place de Ciel.
	if pr.stage in CMD.INTERACTIVE_STAGES:
		_idle_frames += 1
		if _idle_frames >= fallback_delay():
			_idle_frames = 0
			# Un silence de plus : on cesse de l'attendre jusqu'à son retour.
			if _ciel_responsive:
				print_rich("[color=yellow]⏱ Aucun ordre de Ciel — "
					+ "l'IA locale prend la main sans plus l'attendre.[/color]")
			_ciel_responsive = false
			_play_local_fallback(opponent, participant, arena, pr)
			return

	match pr.stage:
		pr.STAGE_SELECT_PAWN:
			_handle_select_pawn_stage(opponent, pr)
		pr.STAGE_SHOW_ACTIONS:
			_handle_show_actions_stage(opponent, pr, arena)
		pr.STAGE_SHOW_MOVEMENTS:
			_handle_show_movements_stage(pr)
		pr.STAGE_SELECT_LOCATION:
			_handle_select_location_stage(opponent, pr, arena)
		pr.STAGE_MOVE_PAWN:
			_handle_move_pawn_stage(delta, participant)
		_:
			pr.stage = pr.STAGE_SELECT_PAWN


# ---------------------------------------------------------------------------
# Étapes
# ---------------------------------------------------------------------------
func _handle_select_pawn_stage(opponent: TacticsOpponent, pr: TacticsParticipantResource) -> void:
	if not _any_pawn_can_act(opponent):
		_wait_frames += 1
		if _wait_frames >= MAX_WAIT_FRAMES:
			_do_end_turn(pr)
		return
	_wait_frames = 0

	var cmd: Dictionary = _next_command(pr)
	if cmd.is_empty():
		return

	match str(cmd["action"]):
		"select_pawn":
			var wanted: String = str(cmd["args"]["name"])
			var pawn: Node = EXECUTOR.find_pawn_by_name(opponent, wanted)
			if not pawn:
				_reject_runtime("select_pawn", "aucun pion adverse vivant nommé \"%s\"" % wanted)
				return
			if not pawn.can_act():
				_reject_runtime("select_pawn", "%s a déjà joué ce tour-ci" % wanted)
				return
			pr.curr_pawn = pawn
			pr.stage = pr.STAGE_SHOW_ACTIONS
			var level: TacticsLevel = _resolve_level()
			if level and level.arena:
				# Marquer la portée dès la sélection : l'état exporté doit dire à
				# Ciel où ce pion peut aller avant qu'il ne demande un `move`.
				_mark_movement_range(level.arena, pawn)
				level.arena.res.mark_hover_tile(pawn.get_tile())
		"end_turn":
			_do_end_turn(pr)


func _handle_show_actions_stage(opponent: TacticsOpponent, pr: TacticsParticipantResource, arena: TacticsArena) -> void:
	var pawn: TacticsPawn = pr.curr_pawn
	if not pawn or not is_instance_valid(pawn):
		pr.stage = pr.STAGE_SELECT_PAWN
		return

	if not pawn.res.can_move and not pawn.res.can_attack:
		_do_end_pawn(pawn, pr)
		return

	var cmd: Dictionary = _next_command(pr)
	if cmd.is_empty():
		return

	match str(cmd["action"]):
		"move":
			_do_move(pawn, pr, arena, int(cmd["args"]["col"]), int(cmd["args"]["row"]))
		"attack":
			_do_attack_setup(pawn, pr, arena, str(cmd["args"]["name"]))
		"heal":
			_do_heal_setup(opponent, pawn, pr, arena, str(cmd["args"]["name"]))
		"use_item":
			_do_use_item(opponent, pawn, pr, cmd["args"])
		"promote":
			_do_promote(pawn, cmd["args"].get("class", null))
		"flee":
			_do_flee(pawn, pr, arena)
		"guard":
			_do_guard(pawn, pr)
		"wait", "end_pawn":
			_do_end_pawn(pawn, pr)
		"end_turn":
			_do_end_turn(pr)


func _handle_show_movements_stage(pr: TacticsParticipantResource) -> void:
	var pawn: TacticsPawn = pr.curr_pawn
	if not pawn or not is_instance_valid(pawn):
		pr.stage = pr.STAGE_SELECT_PAWN
		return
	# On attend la fin de l'animation de déplacement.
	if pawn.res and not pawn.res.pathfinding_tilestack.is_empty():
		return
	pr.stage = pr.STAGE_SELECT_LOCATION
	pr.turn_just_started = true


func _handle_select_location_stage(opponent: TacticsOpponent, pr: TacticsParticipantResource, arena: TacticsArena) -> void:
	var pawn: TacticsPawn = pr.curr_pawn
	if not pawn or not is_instance_valid(pawn):
		pr.stage = pr.STAGE_SELECT_PAWN
		return

	if not pawn.res.can_attack:
		_do_end_pawn(pawn, pr)
		return

	var cmd: Dictionary = _next_command(pr)
	if cmd.is_empty():
		return

	match str(cmd["action"]):
		"attack":
			_commit_target(pr, arena, _find_enemy(str(cmd["args"]["name"])), "attack")
		"heal":
			_commit_target(pr, arena, EXECUTOR.find_pawn_by_name(opponent, str(cmd["args"]["name"])), "heal")
		"use_item":
			_do_use_item(opponent, pawn, pr, cmd["args"])
		"guard":
			_do_guard(pawn, pr)
		"wait", "end_pawn":
			_do_end_pawn(pawn, pr)
		"end_turn":
			_do_end_turn(pr)


func _handle_move_pawn_stage(delta: float, participant: TacticsParticipant) -> void:
	participant.serv.combat_service.attack_pawn(delta, false)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
## Recalcule et marque les tuiles atteignables par un pion (pathfinding du moteur).
func _mark_movement_range(arena: TacticsArena, pawn: TacticsPawn) -> void:
	if not arena or not pawn or not pawn.get_tile():
		return
	var allies: Array = _opponent.get_children() if _opponent and is_instance_valid(_opponent) else []
	arena.res.reset_all_tile_markers()
	arena.process_surrounding_tiles(pawn.get_tile(), pawn.stats.jump, allies)
	arena.mark_reachable_tiles(pawn.get_tile(), pawn.stats.movement)


func _do_move(pawn: TacticsPawn, pr: TacticsParticipantResource, arena: TacticsArena, col: int, row: int) -> bool:
	if not pawn.res.can_move:
		_reject_runtime("move", "%s a déjà bougé" % EXECUTOR.display_name(pawn))
		return false

	var target_tile: Node = TacticsGrid.find_tile(arena, col, row)
	if not target_tile:
		_reject_runtime("move", "aucune tuile en (%d,%d)" % [col, row])
		return false

	var allies: Array = _opponent.get_children() if _opponent and is_instance_valid(_opponent) else []
	arena.res.reset_all_tile_markers()
	arena.process_surrounding_tiles(pawn.get_tile(), pawn.stats.jump, allies)
	arena.mark_reachable_tiles(pawn.get_tile(), pawn.stats.movement)

	if not target_tile.get("reachable"):
		_reject_runtime("move", "(%d,%d) hors de portée de %s (MOV %d)" % [
			col, row, EXECUTOR.display_name(pawn), pawn.stats.movement
		])
		return false

	var path: Array = arena.get_pathfinding_tilestack(target_tile)
	if path.is_empty():
		_reject_runtime("move", "aucun chemin vers (%d,%d)" % [col, row])
		return false

	var from: Vector2i = TacticsGrid.tile_to_grid(arena, pawn.get_tile())
	pawn.res.pathfinding_tilestack = path
	pr.stage = pr.STAGE_SHOW_MOVEMENTS
	pr.turn_just_started = true
	_record(&"record_move", [EXECUTOR.display_name(pawn), from.x, from.y, col, row])
	return true


func _do_attack_setup(pawn: TacticsPawn, pr: TacticsParticipantResource, arena: TacticsArena, target_name: String) -> bool:
	if not pawn.res.can_attack:
		_reject_runtime("attack", "%s a déjà attaqué" % EXECUTOR.display_name(pawn))
		return false
	return _commit_target(pr, arena, _find_enemy(target_name), "attack")


func _do_heal_setup(opponent: TacticsOpponent, pawn: TacticsPawn, pr: TacticsParticipantResource,
		arena: TacticsArena, target_name: String) -> bool:
	if not WT.is_healing(pawn.stats.weapon_type):
		_reject_runtime("heal", "%s ne porte pas de bâton" % EXECUTOR.display_name(pawn))
		return false
	if not pawn.res.can_attack:
		_reject_runtime("heal", "%s a déjà agi" % EXECUTOR.display_name(pawn))
		return false
	return _commit_target(pr, arena, EXECUTOR.find_pawn_by_name(opponent, target_name), "heal")


## Verrouille une cible (attaque ou soin) et enchaîne sur la résolution du combat.
func _commit_target(pr: TacticsParticipantResource, arena: TacticsArena, target: Node, kind: String) -> bool:
	if not target or not is_instance_valid(target):
		_reject_runtime(kind, "cible introuvable ou déjà tombée")
		return false

	var pawn: TacticsPawn = pr.curr_pawn
	if pawn and is_instance_valid(pawn) and pawn.get_tile() and target.get_tile():
		var a: Vector2i = TacticsGrid.tile_to_grid(arena, pawn.get_tile())
		var b: Vector2i = TacticsGrid.tile_to_grid(arena, target.get_tile())
		var dist: int = absi(a.x - b.x) + absi(a.y - b.y)
		if dist > pawn.stats.attack_range:
			_reject_runtime(kind, "%s est à %d cases, portée %d" % [
				EXECUTOR.display_name(target), dist, pawn.stats.attack_range
			])
			return false

	pr.attackable_pawn = target
	arena.res.reset_all_tile_markers()
	arena.res.mark_hover_tile(target.get_tile())
	pr.stage = pr.STAGE_MOVE_PAWN
	pr.turn_just_started = true
	return true


func _do_use_item(opponent: TacticsOpponent, pawn: TacticsPawn, pr: TacticsParticipantResource, args: Dictionary) -> void:
	var item_name: String = str(args.get("item", ""))
	var user: Node = pawn
	if args.has("name"):
		user = EXECUTOR.find_pawn_by_name(opponent, str(args["name"]))
		if not user:
			_reject_runtime("use_item", "allié introuvable : %s" % str(args["name"]))
			return

	var result: Dictionary = user.stats.use_item(item_name)
	if not bool(result.get("ok", false)):
		_reject_runtime("use_item", str(result.get("reason", "objet inutilisable")))
		return

	print_rich("[color=aqua]🧪 %s utilise %s (%s +%d)[/color]" % [
		EXECUTOR.display_name(user), result["item"], result["effect"], int(result.get("amount", 0))
	])
	_record(&"record", [LOG.Kind.HEAL, {"pawn": EXECUTOR.display_name(user),
		"item": result["item"], "effect": result["effect"],
		"amount": result.get("amount", 0)}])

	# Utiliser un objet consomme l'action du pion.
	_do_end_pawn(pawn, pr)


func _do_promote(pawn: TacticsPawn, choice: Variant) -> void:
	var result: Dictionary = pawn.stats.promote_to(choice)
	if not bool(result.get("promoted", false)):
		_reject_runtime("promote", str(result.get("reason", "promotion impossible")))
		return
	_record(&"record", [LOG.Kind.PROMOTION, {
		"pawn": EXECUTOR.display_name(pawn),
		"to": CD.get_class_name(int(result["to"])),
		"bonuses": result.get("bonuses", {}),
	}])


func _do_flee(pawn: TacticsPawn, pr: TacticsParticipantResource, arena: TacticsArena) -> void:
	if not pawn.res.can_move:
		_reject_runtime("flee", "%s a déjà bougé" % EXECUTOR.display_name(pawn))
		return

	var level: TacticsLevel = _resolve_level()
	var allies: Array = _opponent.get_children() if _opponent and is_instance_valid(_opponent) else []
	arena.res.reset_all_tile_markers()
	arena.process_surrounding_tiles(pawn.get_tile(), pawn.stats.jump, allies)
	arena.mark_reachable_tiles(pawn.get_tile(), pawn.stats.movement)

	var tile: Node = EXECUTOR.safest_retreat_tile(arena, pawn, level.player if level else null)
	if not tile:
		_reject_runtime("flee", "aucune case de repli atteignable")
		return

	var dest: Vector2i = TacticsGrid.tile_to_grid(arena, tile)
	var path: Array = arena.get_pathfinding_tilestack(tile)
	if path.is_empty():
		_reject_runtime("flee", "aucun chemin de repli")
		return

	pawn.res.pathfinding_tilestack = path
	pawn.res.can_attack = false  # Fuir, c'est renoncer à frapper.
	pr.stage = pr.STAGE_SHOW_MOVEMENTS
	pr.turn_just_started = true
	print_rich("[color=orange]🏃 %s se replie en (%d,%d)[/color]" % [
		EXECUTOR.display_name(pawn), dest.x, dest.y
	])


func _do_guard(pawn: TacticsPawn, pr: TacticsParticipantResource) -> void:
	# Se mettre en garde : +2 DÉF / +2 RÉS jusqu'au prochain tour du pion.
	pawn.stats.apply_buff("def", 2, 2)
	pawn.stats.apply_buff("res", 2, 2)
	print_rich("[color=cyan]🛡 %s se met en garde (+2 DÉF/RÉS)[/color]" % EXECUTOR.display_name(pawn))
	_do_end_pawn(pawn, pr)


func _do_end_pawn(pawn: TacticsPawn, pr: TacticsParticipantResource) -> void:
	if pawn and is_instance_valid(pawn):
		pawn.res.can_move = false
		pawn.res.can_attack = false
		pawn.end_pawn_turn()
	pr.stage = pr.STAGE_SELECT_PAWN
	pr.curr_pawn = null
	_idle_frames = 0


func _do_end_turn(pr: TacticsParticipantResource) -> void:
	var level: TacticsLevel = _resolve_level()
	if level and level.opponent and is_instance_valid(level.opponent):
		for p in level.opponent.get_children():
			if p is TacticsPawn and is_instance_valid(p):
				p.end_pawn_turn()
	pr.stage = pr.STAGE_SELECT_PAWN
	pr.curr_pawn = null
	_wait_frames = 0
	_idle_frames = 0


# ---------------------------------------------------------------------------
# Repli sur l'IA locale (verrou anti-blocage)
# ---------------------------------------------------------------------------
func _play_local_fallback(opponent: TacticsOpponent, participant: TacticsParticipant,
		arena: TacticsArena, pr: TacticsParticipantResource) -> void:
	var level: TacticsLevel = _resolve_level()
	if not level:
		return

	# Choisir un pion si Ciel n'en a pas sélectionné.
	var pawn: TacticsPawn = pr.curr_pawn
	if not pawn or not is_instance_valid(pawn) or not pawn.can_act():
		pawn = null
		for p in opponent.get_children():
			if p is TacticsPawn and is_instance_valid(p) and p.can_act():
				pawn = p
				break
	if not pawn:
		_do_end_turn(pr)
		return

	pr.curr_pawn = pawn
	var difficulty: int = _difficulty()
	var plan: Dictionary = EXECUTOR.plan(arena, pawn, opponent, level.player, difficulty)

	print_rich("[color=yellow]⏱ CielAI silencieux — l'IA locale joue %s : %s[/color]" % [
		EXECUTOR.display_name(pawn), str(plan.get("decision", {}).get("reason", "attente"))
	])

	if bool(plan.get("needs_move", false)) and plan.get("tile"):
		var path: Array = arena.get_pathfinding_tilestack(plan["tile"])
		if not path.is_empty():
			pawn.res.pathfinding_tilestack = path
			pr.stage = pr.STAGE_SHOW_MOVEMENTS
			pr.turn_just_started = true
			return

	if str(plan.get("action", "")) == "attack" and plan.get("target"):
		_commit_target(pr, arena, plan["target"], "attack")
		return

	_do_end_pawn(pawn, pr)


# ---------------------------------------------------------------------------
# Lecture & validation des commandes
# ---------------------------------------------------------------------------
## Lit le prochain ordre valide. Renvoie {} si aucun ordre, ou si l'ordre a été rejeté.
## Combien de frames attendre un ordre de Ciel avant que l'IA locale ne joue.
##
## Pleine patience tant qu'il répond ; réduite dès qu'il s'est tu une fois. Un
## seul ordre suffit à la lui rendre — brancher un client en cours de partie
## fonctionne donc sans rien redémarrer.
func fallback_delay() -> int:
	return FALLBACK_AFTER_FRAMES if _ciel_responsive else FALLBACK_AFTER_FRAMES_SILENT


## Ciel vient de se manifester : on lui rend toute sa patience.
func _note_ciel_answered() -> void:
	if not _ciel_responsive:
		print_rich("[color=green]🤖 Ciel répond de nouveau — patience rendue.[/color]")
	_ciel_responsive = true


func _next_command(pr: TacticsParticipantResource) -> Dictionary:
	# Les ordres réseau sont déjà validés à la réception : ils passent devant.
	if not _external_queue.is_empty():
		var queued: Dictionary = _external_queue.pop_front()
		if not str(queued["action"]) in _actions_for_stage(pr.stage):
			_reject_runtime(str(queued["action"]),
				"reçu à l'étape %s, ignoré" % _stage_name(pr.stage))
			return {}
		_idle_frames = 0
		_note_ciel_answered()
		_cmd = queued
		return queued

	var raw: String = _consume_command_file()
	if raw.is_empty():
		return {}
	# Un fichier d'ordre écrit, même invalide, prouve qu'un client est branché.
	_note_ciel_answered()

	var level: TacticsLevel = _resolve_level()
	var acting: String = TeamData.state_team_name(acting_side())
	var ctx: Dictionary = {
		"stage": pr.stage,
		"turn": acting,
		"acting_team": acting,
		"grid_size": TacticsGrid.grid_size(level.arena if level else null),
	}

	var parsed: Dictionary = CMD.parse(raw, ctx)
	if not bool(parsed["ok"]):
		_reject(parsed)
		return {}

	_idle_frames = 0
	_last_error = ""
	_last_error_code = CMD.Err.NONE
	_cmd = parsed
	_write_feedback(parsed["action"], true, CMD.Err.NONE, "")
	return parsed


## Consomme un ordre déposé alors que ce n'est pas le tour de Ciel.
## `toggle` est appliqué, le reste est rejeté avec le code OUT_OF_TURN.
func _drain_out_of_turn_command(level: TacticsLevel) -> void:
	if not FileAccess.file_exists(CMD_FILE):
		return
	var raw: String = _consume_command_file()
	if raw.is_empty():
		return

	var parsed: Dictionary = CMD.parse(raw, {"turn": _whose_turn(level)})
	if not bool(parsed["ok"]):
		_reject(parsed)
		return

	if str(parsed["action"]) == "toggle":
		toggle(bool(parsed["args"]["enabled"]))
	else:
		_write_feedback(str(parsed["action"]), true, CMD.Err.NONE, "")


## À qui appartient le tour en cours ?
func _whose_turn(level: TacticsLevel) -> String:
	if not level or not level.participant or not is_instance_valid(level.participant):
		return "unknown"
	# On suit l'ordre de jeu réel : à trois camps (M5), l'invité s'intercale
	# entre le joueur et Ciel.
	for camp in _camps_in_order(level):
		if is_instance_valid(camp) and level.participant.can_act(camp):
			return TeamData.state_team_name(TeamData.side_for_camp_node(camp))
	return "unknown"


## Camps de la bataille, dans l'ordre où ils jouent.
func _camps_in_order(level: TacticsLevel) -> Array:
	if level and not level.camps.is_empty():
		return level.camps
	var fallback: Array = []
	if level and level.player:
		fallback.append(level.player)
	if level and level.opponent:
		fallback.append(level.opponent)
	return fallback


## Commandes globales (toggle) — acceptées à tout moment, y compris hors tour.
func _check_global_commands() -> void:
	if not FileAccess.file_exists(CMD_FILE):
		return
	var f := FileAccess.open(CMD_FILE, FileAccess.READ)
	if not f:
		return
	var content: String = f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(content) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return  # Les ordres malformés sont traités (et rejetés) par _next_command.
	if str(json.data.get("action", "")) != "toggle":
		return

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CMD_FILE))
	var parsed: Dictionary = CMD.validate(json.data, {})
	if not bool(parsed["ok"]):
		_reject(parsed)
		return

	toggle(bool(parsed["args"]["enabled"]))


func _consume_command_file() -> String:
	if not FileAccess.file_exists(CMD_FILE):
		return ""
	var f := FileAccess.open(CMD_FILE, FileAccess.READ)
	if not f:
		return ""
	var content: String = f.get_as_text()
	f.close()
	# Le fichier est consommé, valide ou non : Ciel ne doit jamais rejouer un ordre.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CMD_FILE))
	return content


## Rejet d'une commande invalidée par le schéma.
func _reject(parsed: Dictionary) -> void:
	_last_error = str(parsed["error"])
	_last_error_code = int(parsed["code"])
	push_warning("[CielAI] Commande rejetée [%s] %s" % [_error_name(_last_error_code), _last_error])
	print_rich("[color=red]⛔ CielAI — commande rejetée : %s[/color]" % _last_error)
	_record(&"record_rejected_command", [str(parsed.get("action", "")), _last_error_code, _last_error])
	_write_feedback(str(parsed.get("action", "")), false, _last_error_code, _last_error)


## Rejet d'une commande bien formée mais inapplicable (cible absente, hors portée…).
func _reject_runtime(action: String, reason: String) -> void:
	_last_error = reason
	_last_error_code = CMD.Err.OUT_OF_RANGE
	print_rich("[color=red]⛔ CielAI — %s impossible : %s[/color]" % [action, reason])
	_record(&"record_rejected_command", [action, _last_error_code, reason])
	_write_feedback(action, false, _last_error_code, reason)


func _write_feedback(action: String, ok: bool, code: int, message: String) -> void:
	_write_json(FEEDBACK_FILE, {
		"protocol_version": CMD.PROTOCOL_VERSION,
		"action": action,
		"ok": ok,
		"code": code,
		"code_name": _error_name(code),
		"error": message,
		"seq": _seq,
		"at": Time.get_datetime_string_from_system(true),
	})


static func _error_name(code: int) -> String:
	match code:
		CMD.Err.NONE: return "OK"
		CMD.Err.MALFORMED_JSON: return "MALFORMED_JSON"
		CMD.Err.NOT_A_DICT: return "NOT_A_DICT"
		CMD.Err.MISSING_ACTION: return "MISSING_ACTION"
		CMD.Err.UNKNOWN_ACTION: return "UNKNOWN_ACTION"
		CMD.Err.MISSING_ARG: return "MISSING_ARG"
		CMD.Err.BAD_ARG_TYPE: return "BAD_ARG_TYPE"
		CMD.Err.OUT_OF_RANGE: return "OUT_OF_RANGE"
		CMD.Err.WRONG_STAGE: return "WRONG_STAGE"
		CMD.Err.OUT_OF_TURN: return "OUT_OF_TURN"
		_: return "UNKNOWN"


# ---------------------------------------------------------------------------
# Export de l'état
# ---------------------------------------------------------------------------
func _export_state(level: TacticsLevel) -> void:
	if not level or not is_instance_valid(level):
		return

	var part: TacticsParticipant = _participant
	var opponent: TacticsOpponent = _opponent
	if not part or not opponent:
		part = level.participant
		opponent = level.opponent
	if not part or not opponent or not is_instance_valid(part):
		return

	var pr: TacticsParticipantResource = part.res
	if not pr:
		return

	var arena: TacticsArena = level.arena

	var whose_turn: String = _whose_turn(level)

	# Comptage des tours : un tour complet = joueur puis adversaire.
	if whose_turn != _last_turn_owner and whose_turn != "unknown":
		if whose_turn == "player" and _last_turn_owner == "opponent":
			_turn_number += 1
		_last_turn_owner = whose_turn
		_record(&"record_turn_start", [whose_turn, _turn_number])

	var state: Dictionary = {
		"protocol_version": CMD.PROTOCOL_VERSION,
		"turn": whose_turn,
		"turn_number": _turn_number,
		"stage": pr.stage,
		"stage_name": _stage_name(pr.stage),
		"stage_actions": _actions_for_stage(pr.stage),
		"current_pawn": "",
		"mode": _mode_name(),
		"difficulty": _difficulty_name(),
		"opponent_controller": _controller_name(),
		"controllers": _controllers_map(),
		"last_error": _last_error,
		"last_error_code": _last_error_code,
		"pawns": [],
	}

	var cp: TacticsPawn = pr.curr_pawn
	if cp and is_instance_valid(cp):
		state["current_pawn"] = EXECUTOR.display_name(cp)

	# Tous les camps sont exportés, chacun sous son étiquette d'équipe : à trois
	# camps (M5), Ciel voit apparaître une troisième valeur, « guest ».
	for camp in _camps_in_order(level):
		if not is_instance_valid(camp):
			continue
		var team: String = TeamData.state_team_name(TeamData.side_for_camp_node(camp))
		for p in camp.get_children():
			if p is TacticsPawn and is_instance_valid(p):
				state["pawns"].append(_pawn_dict(arena, p, team, cp))

	if arena and is_instance_valid(arena):
		var gs: Vector2i = TacticsGrid.grid_size(arena)
		state["tile_size"] = TacticsGrid.tile_size(arena)
		state["grid_size"] = {"x": gs.x, "y": gs.y}
		state["terrain"] = _terrain_map(arena)

	var recorder: Node = _recorder()
	if recorder:
		state["events"] = recorder.recent()
		state["event_cursor"] = recorder.seq

	var chapter: Node = _campaign()
	if chapter and chapter.current_chapter():
		var current: ChapterData = chapter.current_chapter()
		state["objective"] = current.objective_text()
		# Point de commandement : sans ses coordonnées, Ciel ne peut pas défendre
		# ce que le joueur vient prendre. Champ additif, absent des autres chapitres.
		var point: Vector2i = OBJ.seize_target(current.objective)
		if point.x >= 0:
			state["objective_point"] = {"col": point.x, "row": point.y}

	var json_str: String = JSON.stringify(state, "\t")
	var h: int = hash(json_str)
	if h == _last_state_hash:
		return
	_last_state_hash = h

	_seq += 1
	state["seq"] = _seq
	state["timestamp"] = Time.get_unix_time_from_system()
	_write_json(STATE_FILE, state)
	state_exported.emit(state)

	# En réseau, l'hôte diffuse le même état à l'invité : une seule source de vérité.
	var network: Node = _network()
	if network and network.role == 1:  # Role.HOST
		network.broadcast_state(state)


func _pawn_dict(arena: TacticsArena, p: TacticsPawn, team: String, current: TacticsPawn) -> Dictionary:
	var tile: Node = p.get_tile()
	var g: Vector2i = TacticsGrid.tile_to_grid(arena, tile) if tile else Vector2i(-1, -1)
	var s = p.stats

	var d: Dictionary = {
		"name": EXECUTOR.display_name(p),
		"team": team,
		"grid_col": g.x,
		"grid_row": g.y,
		"hp": s.hp,
		"max_hp": s.max_hp,
		"level": s.level,
		"exp": s.exp,
		"class_name": CD.get_class_name(s.character_class),
		"is_promoted": s.is_promoted,
		"is_flying": CD.is_flying(s.character_class),
		"str": s.str, "mag": s.mag, "skl": s.skl, "spd": s.spd,
		"lck": s.lck, "def": s.def, "res": s.res,
		"movement": s.movement,
		"attack_range": s.attack_range,
		"weapon_type": s.weapon_type,
		"weapon_name": WT.get_weapon_name(s.weapon_type),
		"weapon_might": s.weapon_might,
		# Portée minimale et arsenal : sans eux, Ciel ne peut pas savoir qu'un
		# archer pris au contact ne riposte pas — ni qu'une unité a mieux au
		# fourreau que ce qu'elle tient.
		"min_range": WT.get_min_range(s.weapon_type),
		"equipped_weapon": s.equipped_weapon,
		"weapons": s.weapons.duplicate(),
		"is_magical": WT.is_magical(s.weapon_type),
		"items": s.items.duplicate(),
		"skills": s.get_skills(),
		"buffs": s.active_buffs(),
		"terrain": TacticsGrid.terrain_name(tile),
		"terrain_def": TacticsGrid.terrain_defense(tile),
		"can_move": p.res.can_move,
		"can_attack": p.res.can_attack,
		"alive": p.is_alive(),
	}

	# Portées : uniquement pour le pion actif, pour ne pas alourdir l'export.
	# Le déplacement vient du pathfinding marqué ; la portée d'attaque est
	# géométrique (la calculer via le pathfinding écraserait le marquage).
	if current and p == current and arena and p.is_alive():
		d["reachable_tiles"] = TacticsGrid.reachable_tiles(arena)
		d["attack_tiles"] = TacticsGrid.tiles_in_range(arena, g, s.attack_range)
	return d


## Carte des terrains : une ligne de codes par rangée + la légende des bonus.
func _terrain_map(arena: TacticsArena) -> Dictionary:
	var gs: Vector2i = TacticsGrid.grid_size(arena)
	var rows: Array = []
	var grid: Array = []
	for _r in gs.y:
		var row: Array = []
		row.resize(gs.x)
		row.fill("?")
		grid.append(row)

	for tile in TacticsGrid.tiles(arena):
		var g: Vector2i = TacticsGrid.tile_to_grid(arena, tile)
		if g.x < 0 or g.y < 0 or g.y >= grid.size() or g.x >= gs.x:
			continue
		grid[g.y][g.x] = TacticsGrid.terrain_name(tile).substr(0, 1)

	for row: Array in grid:
		rows.append("".join(row))

	return {
		"legend": {"g": "grass", "f": "forest (+1 DEF)", "m": "mountain (bloqué)",
			"w": "water (bloqué)", "p": "path", "a": "wall (bloqué)", "i": "pit (bloqué)"},
		"rows": rows,
	}


# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------
func _find_enemy(pawn_name: String) -> Node:
	var level: TacticsLevel = _resolve_level()
	if not level or not level.player:
		return null
	return EXECUTOR.find_pawn_by_name(level.player, pawn_name)


func _any_pawn_can_act(opponent: TacticsOpponent) -> bool:
	for p in opponent.get_children():
		if p is TacticsPawn and is_instance_valid(p) and p.can_act():
			return true
	return false


func _all_pawns_done(opponent: TacticsOpponent) -> bool:
	return not _any_pawn_can_act(opponent)


func _stage_name(stage: int) -> String:
	match stage:
		0: return "select_pawn"
		1: return "show_actions"
		2: return "show_movements"
		3: return "select_location"
		4: return "move_pawn"
		_: return "stage_%d" % stage


## Commandes acceptées à l'étape courante — évite à Ciel de deviner.
func _actions_for_stage(stage: int) -> Array:
	var actions: Array = []
	for action: String in CMD.supported_actions():
		var stages: Array = CMD.SCHEMA[action]["stages"]
		if stages.is_empty() or stage in stages:
			actions.append(action)
	return actions


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_error("[CielAI] Écriture impossible : %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _record(method: StringName, args: Array) -> void:
	var recorder: Node = _recorder()
	if recorder and recorder.has_method(method):
		recorder.callv(method, args)


func _recorder() -> Node:
	var tree := get_tree()
	return tree.root.get_node_or_null("BattleRecorder") if tree else null


func _session() -> Node:
	var tree := get_tree()
	return tree.root.get_node_or_null("GameSession") if tree else null


func _campaign() -> Node:
	var tree := get_tree()
	return tree.root.get_node_or_null("Campaign") if tree else null


func _network() -> Node:
	var tree := get_tree()
	return tree.root.get_node_or_null("Network") if tree else null


func _difficulty() -> int:
	var session: Node = _session()
	return int(session.difficulty) if session else 1


func _difficulty_name() -> String:
	var session: Node = _session()
	if not session:
		return "normal"
	return DifficultyDB.get_level_name(session.difficulty)


func _mode_name() -> String:
	var session: Node = _session()
	if not session:
		return "ciel"
	match session.mode:
		0: return "solo"
		1: return "ciel"
		2: return "hotseat"
		3: return "network"
		_: return "inconnu"


func _controller_name() -> String:
	var session: Node = _session()
	if not session:
		return "CielAI"
	return TeamData.controller_name(session.controller_for(TeamData.Side.OPPONENT))


## Contrôleur de chaque camp en jeu, indexé par son étiquette d'équipe.
## Permet à Ciel de savoir qui tient quoi quand la bataille compte trois camps.
func _controllers_map() -> Dictionary:
	var session: Node = _session()
	if not session:
		return {}
	var out: Dictionary = {}
	for side: int in session.battle_sides():
		out[TeamData.state_team_name(side)] = TeamData.controller_name(session.controller_for(side))
	return out


func _resolve_level() -> TacticsLevel:
	var ref = _level_ref.get_ref()
	if ref and is_instance_valid(ref):
		return ref as TacticsLevel
	var tree := get_tree()
	if not tree:
		return null
	# Le niveau peut être n'importe où dans l'arbre (racine, ou Main/World/…).
	var found: TacticsLevel = _search_level(tree.root)
	if found:
		_level_ref = weakref(found)
	return found


func _search_level(node: Node) -> TacticsLevel:
	if node is TacticsLevel:
		return node
	for child in node.get_children():
		var found: TacticsLevel = _search_level(child)
		if found:
			return found
	return null


# ---------------------------------------------------------------------------
# API publique
# ---------------------------------------------------------------------------
## Active/désactive le contrôle de Ciel (l'IA locale prend le relais si off).
func toggle(val: bool = true) -> void:
	enabled = val
	var session: Node = _session()
	if session:
		session.set_ciel_enabled(val)
	_idle_frames = 0
	var msg: String = "CielAI: enabled" if val else "CielAI: disabled (IA locale)"
	print(msg)
	_write_feedback("toggle", true, CMD.Err.NONE, msg)
