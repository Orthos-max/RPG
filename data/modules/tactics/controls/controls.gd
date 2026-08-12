class_name TacticsControls
extends Control
## Handles UI elements and player controls for the Tactics systems
##
## Resource Interface: [TacticsControlsResource] -- Service: [TacticsControlsService]
##
## [b]Raccourcis clavier de bataille[/b] — tout ce que le menu d'actions propose
## à la souris se joue aussi au clavier. Les touches n'ont aucune logique à
## elles : elles appellent les mêmes méthodes que les boutons, à la seule
## condition que l'étape en cours rende le geste sensé.
##
## [codeblock]
##   Entrée   Fin de tour        (seulement hors action : aucune unité engagée)
##   I        Inventaire         (menu d'actions ouvert)
##   W        Attendre           (menu d'actions ouvert)
##   Échap    Annuler            (retour d'une étape ; sinon, quitte la bataille)
##   Tab      Unité suivante     (celle qui n'a pas encore joué ; X à la manette)
##   G        Grille             — [BattleGridOverlay]
##   X        Accélérer          — tenue, gérée par [BattleSpeed]
##   C        Portée ennemie     — tenue, gérée par [BattleThreatRange]
##   M        Carte              — [BattleMinimap]
##   H        Journal            — [BattleHistory]
## [/codeblock]
##
## [b]Deux chevauchements assumés.[/b] Entrée est aussi `ui_accept`, donc le clic
## de confirmation : la fin de tour est pour cela refusée dès qu'une unité est
## engagée, où Entrée doit rester le « oui » du menu. W est aussi
## `camera_forward` : une pression fait avancer la caméra d'un cheveu en même
## temps qu'elle fait attendre l'unité — sans conséquence, la caméra revient au
## pion suivant.
##
## Échap n'est consommé que s'il y avait quelque chose à annuler ; sinon il
## remonte à [Main], qui ramène à l'écran-titre. C'est ce qui garde la sortie de
## bataille accessible tout en rendant à Échap son sens habituel.

#region: --- Props ---
## Touche de fin de tour.
const KEY_END_TURN: Key = KEY_ENTER
## Touche d'ouverture de l'inventaire.
const KEY_INVENTORY: Key = KEY_I
## Touche « Attendre » (l'unité termine son tour sur place).
const KEY_WAIT: Key = KEY_W
## Touche d'annulation (retour d'une étape).
const KEY_CANCEL: Key = KEY_ESCAPE
## Touche « unité suivante » — l'action d'entrée `cycle_unit` de `project.godot`.
const KEY_CYCLE_UNIT: Key = KEY_TAB

## Resource containing control-related data and settings
@export var controls: TacticsControlsResource = load("res://data/models/view/control/tactics/control.tres")
## Resource containing camera-related data and settings
@export var t_cam: TacticsCameraResource = load("res://data/models/view/camera/tactics/camera.tres")
## Resource containing participant-related data and settings
@export var participant: TacticsParticipantResource = load("res://data/models/world/combat/participant/participant.tres")
## Resource containing arena-related data and settings
@export var arena: TacticsArenaResource = load("res://data/models/world/combat/arena/arena.tres")

## Currently selected pawn
var curr_pawn: TacticsPawn = null
## Service handling control logic
var serv: TacticsControlsService
## Panneau d'inventaire ouvert, le cas échéant (voir [BattleInventoryPanel])
var _inventory: BattleInventoryPanel = null

## Texture for Xbox controller layout
@onready var layout_xbox: Texture2D = load("res://assets/textures/ui/labels/controls-ui-xbox.png")
## Texture for PC controls layout
@onready var layout_pc: Texture2D = load("res://assets/textures/ui/labels/controls-ui.png")
## Node for capturing mouse clicks
@onready var input_capture: InputCapture = $InputCapture
#endregion

#region: --- Processing ---
func _ready() -> void:
	# Initialize the service with necessary resources
	serv = TacticsControlsService.new(controls, t_cam, participant, arena, input_capture)
	serv.setup(self)
	
	# Connect action buttons to their respective methods, and pose leur libellé :
	# la clé branche le bouton, la table de libellés l'habille.
	for action: String in controls.actions.keys():
		var str_name: StringName = controls.actions[action]
		var button: Button = get_act(action)
		button.connect("pressed", Callable(self, str_name))
		button.text = controls.label_for(action)

func _physics_process(delta: float) -> void:
	# Handle physics-based processing
	serv.physics_process(delta, self)

func _input(event: InputEvent) -> void:
	# Handle input events
	serv.handle_input(event)

	# Tab est aussi la navigation au clavier de Godot : sans cette confiscation,
	# la même pression promènerait le focus d'un bouton d'action à l'autre en
	# plus de changer d'unité, et Entrée déclencherait ensuite le bouton mis en
	# évidence plutôt que la confirmation attendue. La bascule elle-même est lue
	# par [TacticsControlsSelectionService], qui interroge l'état de l'action et
	# non l'événement : elle ne dépend donc pas de cette ligne.
	if InputMap.has_action(TacticsControlsResource.ACTION_CYCLE_UNIT) \
			and event.is_action_pressed(TacticsControlsResource.ACTION_CYCLE_UNIT):
		get_viewport().set_input_as_handled()
#endregion

#region: --- Methods ---
## Sets the cursor shape to 'move'
func set_cursor_shape_to_move() -> void:
	CursorService.set_cursor_shape_to_move()


## Sets the cursor shape to 'arrow'
func set_cursor_shape_to_arrow() -> void:
	CursorService.set_cursor_shape_to_arrow()


## Moves the camera based on input
func move_camera(delta: float) -> void:
	serv.move_camera(delta)


## Retrieves an action button node
func get_act(action: String = "") -> Button:
	if action == "": 
		return %Actions
	return %Actions.get_node(action)


## Checks if the mouse is hovering over a UI element
func is_mouse_hovering_ui_elem() -> bool:
	return serv.is_mouse_hovering_ui_elem(self)


## Sets the visibility of the actions menu
func set_actions_menu_visibility(v: bool, p: Variant) -> void:
	serv.set_actions_menu_visibility(v, p, self)


## Met à jour l'encart de prévision de combat (survol d'une cible)
func set_battle_forecast(forecast: Dictionary) -> void:
	var panel: Node = get_node_or_null("%BattleForecast")
	if not panel or not panel.has_method("show_forecast"):
		return
	if forecast.is_empty():
		panel.clear_forecast()
	else:
		panel.show_forecast(forecast)


## Gets the 3D position of the mouse in the game world
func get_3d_canvas_mouse_position(collision_mask: int) -> Object:
	return serv.get_3d_canvas_mouse_position(collision_mask, self)


## Selects a pawn for the player
func select_pawn(camp: TacticsParticipant) -> void:
	serv.select_pawn(camp, self)


## Initiates the process of selecting a new location for the pawn
func select_new_location() -> void:
	serv.select_new_location(self)


## Initiates the process of selecting a pawn to attack
## Oublie la bataille précédente.
##
## Les contrôles vivent dans `main.tscn` et **survivent aux niveaux** : sans ce
## nettoyage, `curr_pawn` désignait encore une unité de la bataille d'avant,
## libérée depuis. En debug Godot annule la référence ; dans une build exportée
## elle reste pendante, et la sélection travaillait dessus — plus rien ne
## répondait au clic (remonté par Aurèle le 2026-08-07).
func reset_for_level() -> void:
	curr_pawn = null
	set_battle_forecast({})
	set_unit_sheet({})
	set_terrain(-1)


## Fait pointer les contrôles vers l'arène réellement montée en scène.
##
## Les contrôles vivent dans `main.tscn` et survivent aux niveaux : ils ne
## peuvent que **deviner** quelle ressource d'arène est en jeu, et leur valeur
## par défaut (`arena.tres`) n'était juste que pour les cartes qui l'emploient.
## Les chapitres, eux, passent par `map_arena.tres` — deux instances distinctes,
## donc les contrôles émettaient tous leurs signaux d'arène dans le vide :
## surlignage du survol, remise à zéro des marqueurs, et surtout **le calcul du
## trajet**, qui rendait une pile vide. Déplacer une unité à la souris était
## impossible ; le pion repassait aussitôt au menu sans avoir bougé.
##
## Le niveau appelle donc ceci en s'ouvrant, avec l'arène qu'il a réellement
## montée. Deviner ne suffit pas.
func use_arena(live: TacticsArenaResource) -> void:
	if not live or live == arena:
		return
	arena = live
	if serv:
		serv.use_arena(live)


func reselect_pawn(camp: TacticsParticipant) -> void:
	serv.reselect_pawn(camp, self)


func select_pawn_to_attack() -> void:
	serv.select_pawn_to_attack(self)


## Handles the player's intention to move
func _player_wants_to_move() -> void:
	_play_ui("ui_select")
	serv.player_wants_to_move()


## Handles the player's intention to cancel an action
func _player_wants_to_cancel() -> void:
	_play_ui("ui_cancel")
	serv.player_wants_to_cancel()


## Handles the player's intention to wait
func _player_wants_to_wait() -> void:
	_play_ui("ui_confirm")
	serv.player_wants_to_wait()


## Ouvre le sac et le fourreau de l'unité sélectionnée.
##
## Le panneau remplace l'ancien bouton « Debug : fin de tour », qui n'avait rien
## à faire dans un menu de joueur. Passer son tour reste possible : chaque unité
## a « Attendre », et c'est le camp qui rend la main quand elles ont toutes joué.
func _player_wants_to_open_inventory() -> void:
	if not is_instance_valid(curr_pawn):
		return
	if _inventory and is_instance_valid(_inventory):
		return  # Déjà ouvert : un second clic ne doit pas empiler deux panneaux.

	_inventory = BattleInventoryPanel.open(self, curr_pawn)
	if not _inventory:
		return
	_play_ui("ui_select")
	_inventory.item_chosen.connect(_on_inventory_item)
	_inventory.weapon_chosen.connect(_on_inventory_weapon)
	_inventory.closed.connect(func() -> void: _play_ui("ui_cancel"))


## L'unité boit : l'effet s'applique et son tour se termine.
func _on_inventory_item(item_name: String) -> void:
	var result: Dictionary = serv.player_wants_to_use_item(item_name)
	_play_ui("ui_confirm" if bool(result.get("ok", false)) else "ui_cancel")


## L'unité dégaine : la fiche affichée doit suivre, la portée vient de changer.
func _on_inventory_weapon(weapon_id: String) -> void:
	var result: Dictionary = serv.player_wants_to_equip(weapon_id)
	_play_ui("ui_confirm" if bool(result.get("ok", false)) else "ui_cancel")
	if bool(result.get("ok", false)) and is_instance_valid(curr_pawn):
		set_actions_menu_visibility(true, curr_pawn)


## Handles the player's intention to attack
func _player_wants_to_attack() -> void:
	_play_ui("ui_select")
	serv.player_wants_to_attack()


## Ramène le pion à son point de départ (annulation du déplacement)
func _player_wants_to_undo_move() -> void:
	_play_ui("ui_cancel")
	serv.player_wants_to_undo_move()


## Joue un son d'interface (silencieux tant qu'aucun fichier n'est fourni)
func _play_ui(cue: String) -> void:
	var audio: Node = get_node_or_null("/root/Audio")
	if audio:
		audio.play(cue)


## Met à jour la fiche d'unité affichée au survol (dictionnaire vide = masquée)
func set_unit_sheet(sheet: Dictionary) -> void:
	var panel: Node = get_node_or_null("%UnitSheet")
	if not panel or not panel.has_method("show_sheet"):
		return
	if sheet.is_empty():
		panel.clear_sheet()
	else:
		panel.show_sheet(sheet)


## Met à jour l'encart de terrain de la case survolée (négatif = masqué)
func set_terrain(terrain: int) -> void:
	var panel: Node = get_node_or_null("%TerrainPanel")
	if not panel or not panel.has_method("show_terrain"):
		return
	panel.show_terrain(terrain)
#endregion
