class_name CielCommand
extends RefCounted
## Validation des commandes envoyées par Ciel (ai_command.json).
##
## Logique pure et sans dépendance à la scène : chaque commande est parsée puis
## confrontée à un schéma (arguments requis, types, étapes de tour autorisées).
## Une commande invalide est REJETÉE proprement — jamais appliquée au moteur —
## et le motif du rejet est renvoyé à l'appelant pour être journalisé/exposé à Ciel.

## Version du protocole documentée dans docs/CIEL_PROTOCOL.md
const PROTOCOL_VERSION: int = 1

#region Codes d'erreur
enum Err {
	NONE = 0,           ## Commande valide
	MALFORMED_JSON = 1, ## Le fichier n'est pas du JSON valide
	NOT_A_DICT = 2,     ## Le JSON n'est pas un objet
	MISSING_ACTION = 3, ## Champ "action" absent ou vide
	UNKNOWN_ACTION = 4, ## Action inconnue du protocole
	MISSING_ARG = 5,    ## Argument obligatoire absent
	BAD_ARG_TYPE = 6,   ## Argument du mauvais type
	OUT_OF_RANGE = 7,   ## Coordonnée hors de la grille
	WRONG_STAGE = 8,    ## Action interdite à l'étape de tour courante
	OUT_OF_TURN = 9,    ## Ce n'est pas le tour du camp adverse
}
#endregion

#region Étapes de tour (miroir de TacticsParticipantResource)
const STAGE_SELECT_PAWN: int = 0
const STAGE_SHOW_ACTIONS: int = 1
const STAGE_SHOW_MOVEMENTS: int = 2
const STAGE_SELECT_LOCATION: int = 3
const STAGE_MOVE_PAWN: int = 4

## Étapes pendant lesquelles une commande peut être consommée (les autres
## sont des étapes d'animation : le moteur y avance seul).
const INTERACTIVE_STAGES: Array[int] = [
	STAGE_SELECT_PAWN, STAGE_SHOW_ACTIONS, STAGE_SELECT_LOCATION
]
#endregion

#region Schéma des commandes
## Pour chaque action : arguments requis (nom → type attendu), arguments
## optionnels, et étapes de tour où l'action est acceptée.
## `stages` vide = action globale, acceptée à tout moment.
const SCHEMA: Dictionary = {
	"select_pawn": {
		"required": {"name": TYPE_STRING},
		"optional": {},
		"stages": [STAGE_SELECT_PAWN],
	},
	"move": {
		"required": {"col": TYPE_INT, "row": TYPE_INT},
		"optional": {},
		"stages": [STAGE_SHOW_ACTIONS],
	},
	"attack": {
		"required": {"name": TYPE_STRING},
		"optional": {},
		"stages": [STAGE_SHOW_ACTIONS, STAGE_SELECT_LOCATION],
	},
	"heal": {
		"required": {"name": TYPE_STRING},
		"optional": {},
		"stages": [STAGE_SHOW_ACTIONS, STAGE_SELECT_LOCATION],
	},
	"use_item": {
		"required": {"item": TYPE_STRING},
		"optional": {"name": TYPE_STRING},
		"stages": [STAGE_SHOW_ACTIONS, STAGE_SELECT_LOCATION],
	},
	"promote": {
		"required": {},
		"optional": {"class": TYPE_STRING},
		"stages": [STAGE_SHOW_ACTIONS],
	},
	"flee": {
		"required": {},
		"optional": {},
		"stages": [STAGE_SHOW_ACTIONS],
	},
	"guard": {
		"required": {},
		"optional": {},
		"stages": [STAGE_SHOW_ACTIONS, STAGE_SELECT_LOCATION],
	},
	"wait": {
		"required": {},
		"optional": {},
		"stages": [STAGE_SHOW_ACTIONS, STAGE_SELECT_LOCATION],
	},
	"end_pawn": {
		"required": {},
		"optional": {},
		"stages": [STAGE_SHOW_ACTIONS, STAGE_SELECT_LOCATION],
	},
	"end_turn": {
		"required": {},
		"optional": {},
		"stages": [STAGE_SELECT_PAWN, STAGE_SHOW_ACTIONS, STAGE_SELECT_LOCATION],
	},
	"toggle": {
		"required": {"enabled": TYPE_BOOL},
		"optional": {},
		"stages": [],  # Action globale : acceptée hors tour
	},
}

## Actions acceptées même quand ce n'est pas le tour de Ciel.
const GLOBAL_ACTIONS: Array[String] = ["toggle"]
#endregion


## Liste des actions supportées (utile pour la doc et les tests).
static func supported_actions() -> Array:
	var actions: Array = SCHEMA.keys()
	actions.sort()
	return actions


## Parse le contenu brut d'un ai_command.json puis le valide.
## [param raw] Texte JSON brut.
## [param ctx] Contexte optionnel : {"stage": int, "grid_size": Vector2i|Dictionary, "turn": String}
## [returns] Voir [method validate].
static func parse(raw: String, ctx: Dictionary = {}) -> Dictionary:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return _reject(Err.MALFORMED_JSON, "JSON invalide ligne %d : %s" % [
			json.get_error_line(), json.get_error_message()
		])
	return validate(json.data, ctx)


## Valide une commande déjà désérialisée.
## [returns] Dictionnaire :
##   ok (bool), action (String), args (Dictionary),
##   code (Err), error (String), global (bool)
static func validate(data: Variant, ctx: Dictionary = {}) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _reject(Err.NOT_A_DICT, "La commande doit être un objet JSON")

	var cmd: Dictionary = data
	var action: String = str(cmd.get("action", "")).strip_edges()
	if action.is_empty():
		return _reject(Err.MISSING_ACTION, "Champ \"action\" manquant")
	if not SCHEMA.has(action):
		return _reject(Err.UNKNOWN_ACTION, "Action inconnue : \"%s\" (connues : %s)" % [
			action, ", ".join(supported_actions())
		])

	var spec: Dictionary = SCHEMA[action]
	var is_global: bool = action in GLOBAL_ACTIONS
	var args: Dictionary = {}

	# --- Arguments requis ---
	for arg_name: String in spec["required"]:
		if not cmd.has(arg_name):
			return _reject(Err.MISSING_ARG, "Argument \"%s\" requis pour \"%s\"" % [arg_name, action])
		var coerced: Variant = _coerce(cmd[arg_name], spec["required"][arg_name])
		if coerced == null:
			return _reject(Err.BAD_ARG_TYPE, "Argument \"%s\" attend le type %s" % [
				arg_name, _type_name(spec["required"][arg_name])
			])
		args[arg_name] = coerced

	# --- Arguments optionnels ---
	for arg_name: String in spec["optional"]:
		if not cmd.has(arg_name):
			continue
		var coerced: Variant = _coerce(cmd[arg_name], spec["optional"][arg_name])
		if coerced == null:
			return _reject(Err.BAD_ARG_TYPE, "Argument optionnel \"%s\" attend le type %s" % [
				arg_name, _type_name(spec["optional"][arg_name])
			])
		args[arg_name] = coerced

	# --- Nom de pion non vide ---
	if args.has("name") and str(args["name"]).strip_edges().is_empty():
		return _reject(Err.MISSING_ARG, "Argument \"name\" vide")

	# --- Contrôle du tour ---
	# Le camp attendu est « opponent » par défaut ; à trois camps (M5), le pont
	# sert aussi le camp « guest » quand c'est l'invité distant qui commande.
	var acting_team: String = str(ctx.get("acting_team", "opponent"))
	if not is_global and ctx.has("turn") and str(ctx["turn"]) != acting_team:
		return _reject(Err.OUT_OF_TURN, "Ce n'est pas le tour de %s (turn=%s)" % [
			acting_team, str(ctx["turn"])
		])

	# --- Contrôle de l'étape ---
	var stages: Array = spec["stages"]
	if not stages.is_empty() and ctx.has("stage"):
		var stage: int = int(ctx["stage"])
		if not stage in stages:
			return _reject(Err.WRONG_STAGE, "\"%s\" interdit à l'étape %d (attendu : %s)" % [
				action, stage, str(stages)
			])

	# --- Bornes de la grille ---
	if action == "move" and ctx.has("grid_size"):
		var gs: Vector2i = _as_grid_size(ctx["grid_size"])
		if gs.x > 0 and gs.y > 0:
			var col: int = args["col"]
			var row: int = args["row"]
			if col < 0 or row < 0 or col >= gs.x or row >= gs.y:
				return _reject(Err.OUT_OF_RANGE, "Case (%d,%d) hors grille %dx%d" % [col, row, gs.x, gs.y])

	return {
		"ok": true,
		"action": action,
		"args": args,
		"code": Err.NONE,
		"error": "",
		"global": is_global,
	}


#region Internes
static func _reject(code: Err, message: String) -> Dictionary:
	return {
		"ok": false,
		"action": "",
		"args": {},
		"code": code,
		"error": message,
		"global": false,
	}


## Convertit une valeur JSON vers le type attendu, ou null si incompatible.
## JSON ne distingue pas int et float : 5.0 est accepté pour un int, pas 5.4.
static func _coerce(value: Variant, expected: int) -> Variant:
	match expected:
		TYPE_STRING:
			if typeof(value) == TYPE_STRING:
				return value
			return null
		TYPE_INT:
			if typeof(value) == TYPE_INT:
				return value
			if typeof(value) == TYPE_FLOAT and is_equal_approx(value, roundf(value)):
				return int(value)
			return null
		TYPE_BOOL:
			if typeof(value) == TYPE_BOOL:
				return value
			return null
		_:
			return value


static func _type_name(t: int) -> String:
	match t:
		TYPE_STRING: return "string"
		TYPE_INT: return "int"
		TYPE_BOOL: return "bool"
		_: return "variant"


static func _as_grid_size(raw: Variant) -> Vector2i:
	if typeof(raw) == TYPE_VECTOR2I:
		return raw
	if typeof(raw) == TYPE_DICTIONARY:
		return Vector2i(int(raw.get("x", 0)), int(raw.get("y", 0)))
	return Vector2i.ZERO
#endregion
