class_name Toast
extends CanvasLayer
## Notifications éphémères, en haut de l'écran — montée de niveau, coup critique,
## objet obtenu.
##
## Trois événements du jeu comptent plus que les autres et n'avaient aucun écho :
## une unité qui monte de niveau (la ligne partait dans la console), un critique
## (l'écran tremble, mais rien ne dit pourquoi) et un achat (une ligne d'état au
## bas de l'intendance, que personne ne regarde). Le journal de bataille
## ([BattleHistory], touche H) les garde tous — encore faut-il l'ouvrir. Ces
## bandeaux-ci disent la même chose sans qu'on demande, puis s'effacent.
##
## [b]Un seul par partie, monté par [Main][/b] et gardé d'un écran à l'autre :
## l'achat se fait à l'intendance, le critique en bataille, et les deux doivent
## pouvoir prévenir. [member current] donne le nœud vivant à qui veut poster
## ([method post]) — sans lui, l'appel ne fait rien, ce qui rend l'API sûre en
## `--headless` comme dans un test qui ne monte aucune interface.
##
## [b]La traduction est une fonction pure.[/b] [method describe] prend un
## événement du journal et rend un texte : le formatage se vérifie sans écran,
## comme celui de [BattleHistory], dont il reprend les lignes déjà écrites.

const HistoryClass = preload("res://data/modules/ui/battle_history.gd")

## Le bandeau vivant, s'il y en a un.
static var current: Toast = null

## Durée d'affichage avant l'effacement, en secondes.
##
## Deux secondes et demie : le temps de lire une ligne sans que le bandeau
## survive au coup suivant. L'effacement en ajoute une demie.
const LIFETIME: float = 2.5
## Durée du fondu de sortie, en secondes.
const FADE: float = 0.5
## Nombre de bandeaux empilés au maximum — au-delà, le plus ancien s'efface.
##
## Un tour adverse peut porter quatre critiques d'affilée ; empiler les quatre
## couvrirait le plateau, qui est ce qu'on regarde.
const MAX_TOASTS: int = 4

## Au-dessus de tout le jeu, sous le fondu de transition (100).
const LAYER: int = 90

const C_GOLD := Color("#f5c842")
const C_CRIT := Color("#e94560")
const C_ITEM := Color(0.55, 0.92, 0.6)

var _column: VBoxContainer = null


## Y a-t-il un écran où poser un bandeau ?
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


## Poste un bandeau, s'il y a une interface pour l'accueillir.
##
## Sans bandeau monté (tests, `--headless`, écran de chargement), l'appel ne fait
## rien : c'est ce qui permet de l'appeler depuis n'importe où sans garde.
static func post(text: String, tint: Color = C_GOLD) -> void:
	if text.is_empty():
		return
	if current and is_instance_valid(current):
		current.show_toast(text, tint)


#region Traduction d'un événement
## Texte du bandeau pour un événement du journal — `""` si rien à annoncer.
##
## Trois événements seulement : le reste appartient au journal de bataille, qui
## les tient déjà tous. Un bandeau par déplacement rendrait le plateau illisible.
static func describe(event: Dictionary) -> String:
	match str(event.get("kind_name", "")):
		"level_up", "promotion":
			# La ligne existe déjà, mot pour mot, dans le journal de bataille.
			return HistoryClass.describe(event)
		"attack":
			if not bool(event.get("crit", false)) or not bool(event.get("hit", false)):
				return ""
			return "💥  Coup critique !  %s → %s : %d dégâts" % [
				str(event.get("attacker", "?")), str(event.get("defender", "?")),
				int(event.get("damage", 0)),
			]
	return ""


## Couleur du bandeau, selon ce qu'il annonce.
static func tint_for(event: Dictionary) -> Color:
	return C_CRIT if str(event.get("kind_name", "")) == "attack" else C_GOLD


## Bandeau d'un objet obtenu — achat à l'intendance, ramassage en bataille.
static func post_item(label: String, owner_name: String = "") -> void:
	if label.is_empty():
		return
	post("🎁  %s obtient %s" % [owner_name, label] if not owner_name.is_empty()
		else "🎁  %s obtenu" % label, C_ITEM)
#endregion


#region Montage
func _ready() -> void:
	layer = LAYER
	_build()
	_listen()
	current = self


func _build() -> void:
	var root := Control.new()
	root.name = "ToastRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Haut de l'écran, au centre : le seul bord qu'aucun panneau n'occupe — la
	# minimap tient le haut-droit, la fiche d'unité le bas-gauche, le journal le
	# bas-droit.
	_column = VBoxContainer.new()
	_column.name = "ToastColumn"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_column.anchor_left = 0.5
	_column.anchor_right = 0.5
	_column.anchor_top = 0.0
	_column.offset_left = -280
	_column.offset_right = 280
	_column.offset_top = 56
	_column.grow_vertical = Control.GROW_DIRECTION_END
	_column.add_theme_constant_override("separation", 6)
	root.add_child(_column)


## Branche les bandeaux sur le journal de bataille, s'il tourne.
func _listen() -> void:
	var recorder: Node = get_node_or_null("/root/BattleRecorder")
	if recorder and not recorder.event_recorded.is_connected(_on_event):
		recorder.event_recorded.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	show_toast(describe(event), tint_for(event))


## Le bandeau meurt avec la partie : plus personne ne doit lui poster de texte.
func _exit_tree() -> void:
	if current == self:
		current = null
#endregion


#region Vie d'un bandeau
## Pose un bandeau ; un texte vide n'en pose aucun.
func show_toast(text: String, tint: Color = C_GOLD) -> void:
	if text.is_empty() or not _column or not is_instance_valid(_column):
		return

	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.10, 0.88)
	style.border_color = tint
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", tint)
	frame.add_child(label)

	_column.add_child(frame)
	_trim()

	# Le fondu emporte le bandeau avec lui : sans cette libération, une bataille
	# longue laisserait derrière elle des centaines de panneaux transparents.
	var tween: Tween = create_tween()
	tween.tween_interval(LIFETIME)
	tween.tween_property(frame, "modulate:a", 0.0, FADE)
	tween.tween_callback(frame.queue_free)


## Nombre de bandeaux affichés.
func toast_count() -> int:
	return _column.get_child_count() if _column else 0


## Retire les plus anciens quand la pile déborde.
func _trim() -> void:
	while _column.get_child_count() > MAX_TOASTS:
		var oldest: Node = _column.get_child(0)
		_column.remove_child(oldest)
		oldest.queue_free()
#endregion
