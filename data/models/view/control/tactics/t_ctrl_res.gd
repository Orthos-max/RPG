class_name TacticsControlsResource
extends Resource
## Resource class for managing tactics controls and related signals.

## Signal emitted when the actions menu visibility needs to be set.
signal called_set_actions_menu_visibility
## Signal emitted when the camera needs to be moved.
signal called_move_camera
## Signal emitted when a pawn needs to be selected.
signal called_select_pawn
## Demande de basculer sur une autre unité, menu d'actions déjà ouvert.
signal called_reselect_pawn
## Signal emitted when a pawn needs to be selected for attack.
signal called_select_pawn_to_attack
## Signal emitted when a new location needs to be selected.
signal called_select_new_location
## Signal emitted when the cursor shape needs to be set to "move".
signal called_set_cursor_shape_to_move
## Signal emitted when the cursor shape needs to be set to "arrow".
signal called_set_cursor_shape_to_arrow
## Émis quand l'encart de prévision de combat doit être mis à jour.
signal called_set_battle_forecast
## Émis quand la fiche de l'unité survolée doit être mise à jour.
signal called_set_unit_sheet

## Terrain de la case survolée (un entier négatif masque l'encart)
signal called_set_terrain

## Indicates whether the current input device is a joystick.
@export var is_joystick: bool
## Indicates whether the input hints are folded.
@export var input_hints_folded: bool

## Dictionary of available actions and their corresponding methods.
##
## La clé est un **identifiant** : c'est le nom du nœud bouton dans
## `controls.tscn`, et il ne doit jamais être lu par un joueur. Le texte affiché
## vit dans [member action_labels], séparément — sans quoi traduire le menu
## reviendrait à débrancher les boutons de leurs méthodes.
var actions: Dictionary = {
	"Move": "_player_wants_to_move",
	"Undo": "_player_wants_to_undo_move",
	"Wait": "_player_wants_to_wait",
	"Cancel": "_player_wants_to_cancel",
	"Attack": "_player_wants_to_attack",
	"Inventory": "_player_wants_to_open_inventory",
}

## Libellés affichés, par clé d'action. Le jeu est francophone : le menu aussi.
var action_labels: Dictionary = {
	"Move": "Déplacer",
	"Undo": "Annuler le déplacement",
	"Wait": "Attendre",
	"Cancel": "Retour",
	"Attack": "Attaquer",
	"Inventory": "Inventaire",
}

## Libellé du bouton d'attaque quand l'unité porte un bâton : elle soigne.
const LABEL_HEAL: String = "Soigner"

## Nom de l'action d'entrée qui passe à l'unité suivante (voir `project.godot`).
const ACTION_CYCLE_UNIT: String = "cycle_unit"

## Raccourcis qui n'ont **pas** de bouton dans le menu d'actions.
##
## [member actions] habille les boutons : chaque clé y désigne un nœud de
## `controls.tscn`, et en ajouter une sans bouton casserait le montage. Ceux-ci
## ne se jouent qu'à la touche ; ils sont listés ici pour que le mapping reste
## l'endroit unique où l'on lit ce que le joueur peut faire.
##
## La clé est l'identifiant de l'action, la valeur ce qui s'affiche.
var shortcut_actions: Dictionary = {
	"CycleUnit": "Unité suivante",
	"ToggleGrid": "Grille",
}

## Touche par défaut de chaque raccourci, telle qu'elle se dit au joueur.
var shortcut_keys: Dictionary = {
	"CycleUnit": "Tab",
	"ToggleGrid": "G",
}


## Libellé affichable d'une action. Retombe sur la clé si la table l'ignore —
## un bouton sans traduction reste lisible plutôt que vide.
func label_for(action: String) -> String:
	if shortcut_actions.has(action):
		return "%s (%s)" % [shortcut_actions[action], shortcut_keys.get(action, "")]
	return str(action_labels.get(action, action))


## Sets the visibility of the actions menu.
func set_actions_menu_visibility(v: bool, p: Variant) -> void:
	called_set_actions_menu_visibility.emit(v, p)


## Initiates camera movement.
func move_camera(delta: float) -> void:
	called_move_camera.emit(delta)


## Selects a pawn for the given player.
func select_pawn(camp: TacticsParticipant) -> void:
	called_select_pawn.emit(camp)


## Bascule sur l'unité survolée si le joueur en clique une autre que la sienne.
func reselect_pawn(camp: TacticsParticipant) -> void:
	called_reselect_pawn.emit(camp)


## Selects a pawn to attack.
func select_pawn_to_attack() -> void:
	called_select_pawn_to_attack.emit()


## Selects a new location.
func select_new_location() -> void:
	called_select_new_location.emit()


## Sets the cursor shape to "move".
func set_cursor_shape_to_move() -> void:
	called_set_cursor_shape_to_move.emit()


## Sets the cursor shape to "arrow".
func set_cursor_shape_to_arrow() -> void:
	called_set_cursor_shape_to_arrow.emit()


## Met à jour l'encart de prévision ; un dictionnaire vide le masque.
func set_battle_forecast(forecast: Dictionary) -> void:
	called_set_battle_forecast.emit(forecast)


## Met à jour la fiche de l'unité survolée ; un dictionnaire vide la masque.
func set_unit_sheet(sheet: Dictionary) -> void:
	called_set_unit_sheet.emit(sheet)


## Met à jour l'encart de terrain ; un entier négatif le masque.
func set_terrain(terrain: int) -> void:
	called_set_terrain.emit(terrain)
