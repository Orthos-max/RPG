extends Node
## GameSession (autoload) — qui joue, contre qui, dans quel mode, à quelle difficulté.
##
## Point d'entrée unique pour savoir comment un camp est piloté. La boucle de tour
## interroge [method controller_for] au lieu de coder en dur « joueur local vs IA »,
## ce qui prépare le hotseat (M2) et le réseau (M3) sans redéfaire le gameplay.

const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")
const ArmySplitClass = preload("res://data/models/world/combat/team/army_split.gd")
const DIFF = preload("res://data/models/world/ai/difficulty.gd")

signal mode_changed(mode: int)
signal teams_changed()

enum Mode {
	SOLO = 0,     ## Campagne solo : joueur local vs IA locale
	CIEL = 1,     ## Le camp adverse est piloté par Ciel
	HOTSEAT = 2,  ## Deux humains sur la même machine (M2)
	NETWORK = 3,  ## Un humain distant via code d'accès (M3)
}

## Mode de jeu courant
var mode: int = Mode.CIEL
## Difficulté courante (module l'IA locale et le handicap adverse)
var difficulty: int = DIFF.Level.NORMAL
## Index du chapitre en cours (sert au handicap progressif)
var chapter_index: int = 0
## Code d'accès de la partie en réseau (M3/M4) — vide hors réseau
var join_code: String = ""
## Trois camps en jeu (M5) : joueur local, invité distant et Ciel.
var three_way: bool = false
## Part de l'armée adverse cédée au troisième camp quand [member three_way] est actif.
var guest_share: float = ArmySplitClass.DEFAULT_SHARE

## Camps de la bataille, indexés par TeamData.Side
var teams: Dictionary = {}


func _ready() -> void:
	reset_teams()


## Remet les camps dans la configuration par défaut du mode courant.
func reset_teams() -> void:
	teams = {
		TeamDataClass.Side.PLAYER: TeamDataClass.create(
			TeamDataClass.Side.PLAYER, TeamDataClass.Controller.LOCAL_PLAYER
		),
		TeamDataClass.Side.OPPONENT: TeamDataClass.create(
			TeamDataClass.Side.OPPONENT, _default_opponent_controller()
		),
	}
	teams[TeamDataClass.Side.OPPONENT].display_name = TeamDataClass.controller_name(
		teams[TeamDataClass.Side.OPPONENT].controller
	)
	if three_way:
		teams[TeamDataClass.Side.GUEST] = TeamDataClass.create(
			TeamDataClass.Side.GUEST, _default_guest_controller()
		)
		teams[TeamDataClass.Side.GUEST].display_name = TeamDataClass.controller_name(
			teams[TeamDataClass.Side.GUEST].controller
		)
	teams_changed.emit()


## Active ou désactive la troisième armée (M5).
##
## Les contrôleurs par défaut deviennent : joueur local, invité distant, Ciel —
## le trio que décrit le backlog. L'appelant reste libre de les surcharger
## ensuite avec [method set_controller].
func set_three_way(enabled: bool) -> void:
	if three_way == enabled:
		return
	three_way = enabled
	reset_teams()


## Camps effectivement en jeu, dans l'ordre où ils jouent leur tour.
func battle_sides() -> Array[int]:
	var sides: Array[int] = [TeamDataClass.Side.PLAYER]
	if teams.has(TeamDataClass.Side.GUEST):
		sides.append(TeamDataClass.Side.GUEST)
	sides.append(TeamDataClass.Side.OPPONENT)
	return sides


## Camps hostiles à `side`.
##
## Règle volontairement simple : chacun pour soi. Deux camps différents sont
## toujours ennemis, ce qui laisse la règle « même parent = allié » du combat
## valable telle quelle, sans notion d'alliance à maintenir.
func hostiles_of(side: int) -> Array[int]:
	var out: Array[int] = []
	for other: int in battle_sides():
		if other != side:
			out.append(other)
	return out


## Change de mode et réaligne les contrôleurs.
func set_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	reset_teams()
	mode_changed.emit(mode)


## Camp correspondant à un côté.
func get_team(side: int) -> TeamData:
	return teams.get(side, null)


## Contrôleur pilotant un camp.
func controller_for(side: int) -> int:
	var t: TeamData = get_team(side)
	if not t:
		return TeamDataClass.Controller.LOCAL_PLAYER
	return t.controller


## Force un contrôleur sur un camp (écran « créer une partie », toggle Ciel…).
func set_controller(side: int, ctrl: int, label: String = "") -> void:
	var t: TeamData = get_team(side)
	if not t:
		return
	t.controller = ctrl
	t.display_name = label if not label.is_empty() else TeamDataClass.controller_name(ctrl)
	teams_changed.emit()


## Le camp adverse est-il confié à Ciel ?
func is_ciel_controlled(side: int = TeamDataClass.Side.OPPONENT) -> bool:
	return controller_for(side) == TeamDataClass.Controller.CIEL_AI


## Bascule le camp adverse entre Ciel et l'IA locale (miroir de la commande `toggle`).
func set_ciel_enabled(enabled: bool) -> void:
	set_controller(
		TeamDataClass.Side.OPPONENT,
		TeamDataClass.Controller.CIEL_AI if enabled else TeamDataClass.Controller.LOCAL_AI
	)
	mode = Mode.CIEL if enabled else Mode.SOLO


## Profil heuristique courant de l'IA locale.
func ai_profile() -> Dictionary:
	return DIFF.get_profile(difficulty)


## Handicap de stats à appliquer au camp adverse pour le chapitre courant.
func opponent_handicap() -> Dictionary:
	return {
		"stat_bonus": DIFF.stat_handicap(difficulty, chapter_index),
		"hp_bonus": DIFF.hp_handicap(difficulty, chapter_index),
	}


## Génère un code d'invitation court (M3/M4) : 6 caractères sans ambiguïté visuelle.
static func generate_join_code(length: int = 6) -> String:
	const ALPHABET: String = "ACDEFGHJKLMNPQRSTUVWXYZ2345679"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code: String = ""
	for _i in length:
		code += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
	return code


func _default_opponent_controller() -> int:
	# À trois camps, le camp rouge revient à Ciel : c'est la promesse de M5,
	# l'invité distant prend le troisième camp.
	if three_way:
		return TeamDataClass.Controller.CIEL_AI
	match mode:
		Mode.CIEL: return TeamDataClass.Controller.CIEL_AI
		Mode.HOTSEAT: return TeamDataClass.Controller.LOCAL_PLAYER
		Mode.NETWORK: return TeamDataClass.Controller.REMOTE_PLAYER
		_: return TeamDataClass.Controller.LOCAL_AI


func _default_guest_controller() -> int:
	match mode:
		Mode.NETWORK: return TeamDataClass.Controller.REMOTE_PLAYER
		Mode.HOTSEAT: return TeamDataClass.Controller.LOCAL_PLAYER
		_: return TeamDataClass.Controller.LOCAL_AI
