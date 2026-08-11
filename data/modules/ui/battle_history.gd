class_name BattleHistory
extends CanvasLayer
## Historique de combat défilant — la touche [b]H[/b] l'ouvre et la referme.
##
## Tout ce qui se passe en bataille était déjà écrit quelque part : [BattleRecorder]
## note chaque assaut, chaque soin, chaque chute, et le service de combat imprime
## la même chose dans la console. Mais la console n'existe pas pour un joueur, et
## à l'écran les chiffres passent en une demi-seconde — d'autant plus vite quand
## on accélère le tour adverse ([BattleSpeed], touche X). « Il m'a fait combien,
## déjà ? » n'avait aucune réponse.
##
## Ce panneau écoute le journal ([signal BattleRecorder.event_recorded]) et en
## rend une ligne lisible. Il ne calcule rien et ne décide de rien : il traduit.
##
## [b]La traduction est une fonction pure.[/b] [method describe] et [method tint]
## prennent un événement et rendent un texte et une couleur, sans le moindre
## nœud — c'est ce qui rend le formatage vérifiable en `--headless`, là où le
## panneau lui-même n'a pas lieu d'être ([method available]).

const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")
const ClassDataClass = preload("res://data/models/world/stats/class_data.gd")

## La touche qui ouvre et referme le panneau.
const TOGGLE_KEY: Key = KEY_H
const TOGGLE_KEY_LABEL: String = "H"

## Nombre d'événements gardés à l'affichage.
##
## Cinquante lignes couvrent largement les deux ou trois derniers tours — de quoi
## répondre à « qu'est-ce qui vient de se passer ? », qui est la seule question
## qu'on pose à un historique en cours de bataille. Le journal complet, lui, part
## dans le replay JSON ([method BattleRecorder.save_replay]).
const MAX_LINES: int = 50

## Au-dessus du bandeau de tour (10) et de l'accélérateur (11), sous le fondu (100).
const LAYER: int = 12

## Largeur et hauteur du panneau, en pixels.
const PANEL_SIZE := Vector2(400, 250)

const C_PANEL := Color(0.05, 0.04, 0.10, 0.88)
const C_GOLD := Color("#f5c842")
const C_ACCENT := Color("#e94560")
const C_TEXT := Color(1, 1, 1, 0.85)
const C_DIM := Color(1, 1, 1, 0.5)
const C_HEAL := Color(0.55, 0.9, 0.6)

var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _lines: VBoxContainer = null
var _toggle: Button = null


## Y a-t-il un écran où afficher l'historique ?
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


#region Traduction d'un événement
## Ligne lisible d'un événement du journal — `""` si rien ne mérite d'être dit.
##
## L'événement est lu par son `kind_name` et non par son entier : c'est déjà la
## clé qu'emploie [BattleStats], et c'est la seule des deux qui survive à un
## aller-retour par le JSON d'un replay.
static func describe(event: Dictionary) -> String:
	match str(event.get("kind_name", "")):
		"turn_start":
			return "▶  Tour %d — %s" % [
				int(event.get("turn", 1)), team_label(str(event.get("team", ""))),
			]
		"move":
			var to: Dictionary = event.get("to", {})
			return "→  %s se déplace en (%d, %d)" % [
				str(event.get("pawn", "?")), int(to.get("col", -1)), int(to.get("row", -1)),
			]
		"attack":
			return _attack_line(event)
		"heal":
			return "✚  %s soigne %s de %d PV — %s : %d PV" % [
				str(event.get("healer", "?")), str(event.get("target", "?")),
				int(event.get("amount", 0)), str(event.get("target", "?")),
				int(event.get("target_hp", 0)),
			]
		"death":
			return "☠  %s tombe (%s)" % [
				str(event.get("pawn", "?")), team_label(str(event.get("team", ""))),
			]
		"level_up":
			return "★  %s passe niveau %d" % [
				str(event.get("pawn", "?")), int(event.get("level", 1)),
			]
		"promotion":
			return "★  %s devient %s" % [
				str(event.get("pawn", "?")),
				ClassDataClass.get_class_name(int(event.get("class_id", 0))),
			]
		"objective":
			var won: bool = str(event.get("status", "")) == "victory"
			return "⚑  %s — %s" % [
				"Victoire" if won else "Défaite", str(event.get("reason", "")),
			]
		"command_rejected":
			return "⚠  Ordre refusé (%s) : %s" % [
				str(event.get("action", "?")), str(event.get("reason", "")),
			]
	return ""


## L'assaut, avec ce qui a décidé de son issue : critique, coup redoublé, PV restants.
static func _attack_line(event: Dictionary) -> String:
	var attacker: String = str(event.get("attacker", "?"))
	var defender: String = str(event.get("defender", "?"))
	if not bool(event.get("hit", false)):
		return "✗  %s attaque %s et manque son coup" % [attacker, defender]

	var line: String = "⚔  %s → %s : %d dégâts" % [
		attacker, defender, int(event.get("damage", 0)),
	]
	if bool(event.get("crit", false)):
		line += "  💥 critique !"
	if bool(event.get("double", false)):
		line += "  ⚔×2"
	return "%s  (%s : %d PV)" % [line, defender, int(event.get("defender_hp", 0))]


## Couleur d'une ligne, selon ce qu'elle raconte.
static func tint(event: Dictionary) -> Color:
	match str(event.get("kind_name", "")):
		"turn_start", "objective", "level_up", "promotion":
			return C_GOLD
		"death":
			return C_ACCENT
		"heal":
			return C_HEAL
		"attack":
			return C_ACCENT if bool(event.get("crit", false)) else C_TEXT
		"move", "command_rejected":
			return C_DIM
	return C_TEXT


## Nom lisible d'un camp, à partir de l'étiquette qu'écrit le journal.
##
## Le journal parle le contrat CielAI (« player », « opponent ») ; le joueur, lui,
## lit du français. [TeamData] tient déjà les deux bouts de cette traduction.
static func team_label(state_name: String) -> String:
	match state_name:
		"player": return TeamDataClass.side_name(TeamDataClass.Side.PLAYER)
		"opponent": return TeamDataClass.side_name(TeamDataClass.Side.OPPONENT)
		"guest": return TeamDataClass.side_name(TeamDataClass.Side.GUEST)
	return "Inconnu"
#endregion


#region Montage
func _ready() -> void:
	layer = LAYER
	_build()
	_listen()
	# Une bataille reprise après coupure a déjà des événements derrière elle : sans
	# ce rattrapage, l'historique s'ouvrirait vide sur un combat en cours.
	_backfill()


func _build() -> void:
	var root := Control.new()
	root.name = "HistoryRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Coin bas-droit : la fiche d'unité et l'encart de terrain tiennent le
	# bas-gauche, la prévision de combat et la minimap le haut-droit.
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.add_theme_constant_override("separation", 4)
	root.add_child(column)

	_panel = PanelContainer.new()
	_panel.name = "HistoryPanel"
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_GOLD
	style.border_width_left = 2
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	column.add_child(_panel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)

	_lines = VBoxContainer.new()
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_theme_constant_override("separation", 2)
	_scroll.add_child(_lines)

	_toggle = Button.new()
	_toggle.text = "📜  Journal (%s)" % TOGGLE_KEY_LABEL
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	_toggle.add_theme_font_size_override("font_size", 12)
	_toggle.pressed.connect(toggle)
	column.add_child(_toggle)


## Branche le panneau sur le journal de bataille, s'il tourne.
func _listen() -> void:
	var recorder: Node = _recorder()
	if recorder and not recorder.event_recorded.is_connected(_on_event):
		recorder.event_recorded.connect(_on_event)


## Reprend les événements déjà journalisés, dans l'ordre.
func _backfill() -> void:
	var recorder: Node = _recorder()
	if not recorder:
		return
	for event: Dictionary in recorder.recent(MAX_LINES):
		_append(event)


func _recorder() -> Node:
	return get_node_or_null("/root/BattleRecorder")
#endregion


#region Vie du panneau
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()


## Ouvre ou referme l'historique (le bouton, lui, reste : sinon on ne pourrait
## plus le rappeler).
func toggle() -> void:
	if not _panel:
		return
	_panel.visible = not _panel.visible
	if _panel.visible:
		_scroll_to_bottom()


## L'historique est-il ouvert ?
func is_open() -> bool:
	return _panel != null and _panel.visible


## Nombre de lignes affichées — plafonné à [constant MAX_LINES].
func line_count() -> int:
	return _lines.get_child_count() if _lines else 0


func _on_event(event: Dictionary) -> void:
	_append(event)
	if is_open():
		_scroll_to_bottom()


## Ajoute une ligne, et retire la plus ancienne quand le panneau déborde.
func _append(event: Dictionary) -> void:
	if not _lines:
		return
	var text: String = describe(event)
	if text.is_empty():
		return  # Événement sans intérêt pour un joueur.

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(PANEL_SIZE.x - 40, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", tint(event))
	_lines.add_child(label)

	while _lines.get_child_count() > MAX_LINES:
		var oldest: Node = _lines.get_child(0)
		_lines.remove_child(oldest)
		oldest.queue_free()


## Ramène la vue sur la dernière ligne.
##
## Une frame d'attente : la barre de défilement ne connaît sa course qu'une fois
## le conteneur remis en page, et sans ce délai on la pousserait à une valeur
## maximale d'avant la ligne qu'on vient d'ajouter.
func _scroll_to_bottom() -> void:
	var tree: SceneTree = get_tree()
	if not tree or not _scroll:
		return
	await tree.process_frame
	if not is_instance_valid(_scroll):
		return
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
#endregion
