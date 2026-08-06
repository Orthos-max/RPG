extends Control
## Écran-titre de Ciel Emblem — construit en code (pas de dépendance .tscn).
##
## Nouvelle partie / Continuer / Mode CielAI / Options / Extras / Quitter.
## L'écran ne connaît pas la suite : il émet des signaux que [Main] orchestre.

signal new_game_requested(difficulty: int, permadeath: bool)
signal continue_requested()
signal load_requested()
signal ciel_mode_requested()
signal host_requested()
signal join_requested()
signal editor_requested()
signal character_editor_requested()
signal quit_requested()

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

const C_BG := Color("#141026")
const C_ACCENT := Color("#e94560")
const C_GOLD := Color("#f5c842")
const C_TEXT := Color("#eeeeee")
const C_BUTTON := Color("#0f3460")
const C_BUTTON_HOVER := Color("#1a508b")

var _difficulty: int = DIFF.Level.NORMAL
var _permadeath: bool = true
var _difficulty_button: Button
var _permadeath_button: Button
var _status: Label

## Largeur logique en deçà de laquelle le menu repasse sur une seule colonne.
const NARROW_WIDTH: float = 760.0
## Rapport largeur/hauteur en deçà duquel une seule colonne se lit mieux.
##
## Le projet est en `stretch/mode="canvas_items"` : la largeur **logique** ne
## bouge pas avec la fenêtre, seule la hauteur s'étire. Se fier à `size.x` seul
## ne déclencherait donc jamais rien — c'est la forme de la fenêtre qui dit s'il
## y a de la place pour deux colonnes.
const WIDE_RATIO: float = 1.1

var _title: Label
var _subtitle: Label
var _grids: Array[GridContainer] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_apply_layout)
	_apply_layout()


## Adapte le menu à la place disponible.
##
## Deux colonnes dès qu'il y a de la largeur, une seule sur une fenêtre étroite —
## et le titre rétrécit avec elle. Le tout vit dans un `ScrollContainer` : sur une
## fenêtre courte, on fait défiler au lieu de perdre les derniers boutons hors de
## l'écran.
func _apply_layout() -> void:
	var wide: bool = is_wide(size)
	for grid: GridContainer in _grids:
		if is_instance_valid(grid):
			grid.columns = 2 if wide else 1
	if _title:
		_title.add_theme_font_size_override("font_size", 48 if wide else 34)
	if _subtitle:
		_subtitle.add_theme_font_size_override("font_size", 16 if wide else 13)


## Y a-t-il la place pour deux colonnes ?
##
## Règle pure, testable sans monter d'écran : assez large en valeur absolue,
## **et** plus large que haute. Une fenêtre en portrait passe sur une colonne.
static func is_wide(viewport: Vector2) -> bool:
	return viewport.x >= NARROW_WIDTH and viewport.x >= viewport.y * WIDE_RATIO


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Tout le menu vit dans un défilement : une fenêtre courte fait défiler au
	# lieu de pousser les derniers boutons hors de l'écran.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 48)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_title = Label.new()
	_title.text = "CIEL EMBLEM"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", C_GOLD)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "Tactical RPG — le camp adverse est joué par une IA externe"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_color_override("font_color", C_ACCENT)
	column.add_child(_subtitle)

	column.add_child(_spacer(16))

	# --- Partir au combat ---
	var play := _make_grid(column)

	var new_btn := _make_button("⚔️  Nouvelle partie", true)
	new_btn.pressed.connect(func() -> void:
		new_game_requested.emit(_difficulty, _permadeath))
	play.add_child(new_btn)

	var continue_btn := _make_button("💾  Continuer")
	continue_btn.disabled = not _has_save()
	continue_btn.pressed.connect(func() -> void: continue_requested.emit())
	play.add_child(continue_btn)

	var load_btn := _make_button("📂  Charger une partie")
	load_btn.disabled = not _has_any_save()
	load_btn.pressed.connect(func() -> void: load_requested.emit())
	play.add_child(load_btn)

	var ciel_btn := _make_button("🤖  Escarmouche CielAI")
	ciel_btn.pressed.connect(func() -> void: ciel_mode_requested.emit())
	play.add_child(ciel_btn)

	var host_btn := _make_button("🌐  Créer une partie en ligne")
	host_btn.pressed.connect(func() -> void: host_requested.emit())
	play.add_child(host_btn)

	var join_btn := _make_button("🔑  Rejoindre avec un code")
	join_btn.pressed.connect(func() -> void: join_requested.emit())
	play.add_child(join_btn)

	column.add_child(_spacer(14))

	# --- Réglages de la prochaine campagne ---
	var options := _make_grid(column)

	_difficulty_button = _make_button(_difficulty_label())
	_difficulty_button.pressed.connect(_cycle_difficulty)
	options.add_child(_difficulty_button)

	_permadeath_button = _make_button(_permadeath_label())
	_permadeath_button.pressed.connect(_toggle_permadeath)
	options.add_child(_permadeath_button)

	column.add_child(_spacer(14))

	# --- Extras ---
	var extras := _make_grid(column)

	var editor_btn := _make_button("🗺️  Éditeur de cartes")
	editor_btn.pressed.connect(func() -> void: editor_requested.emit())
	extras.add_child(editor_btn)

	var chars_btn := _make_button("🧑  Éditeur de personnages")
	chars_btn.pressed.connect(func() -> void: character_editor_requested.emit())
	extras.add_child(chars_btn)

	var quit_btn := _make_button("🚪  Quitter")
	quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	extras.add_child(quit_btn)

	column.add_child(_spacer(12))

	_status = Label.new()
	_status.text = _save_summary()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	column.add_child(_status)


## Une grille de boutons, retenue pour que [method _apply_layout] la recolonne.
func _make_grid(parent: Node) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)
	_grids.append(grid)
	return grid


#region Options
func _cycle_difficulty() -> void:
	_difficulty = (_difficulty + 1) % DIFF.Level.size()
	_difficulty_button.text = _difficulty_label()


func _toggle_permadeath() -> void:
	_permadeath = not _permadeath
	_permadeath_button.text = _permadeath_label()


func _difficulty_label() -> String:
	return "🎚  Difficulté : %s" % DIFF.get_level_name(_difficulty)


func _permadeath_label() -> String:
	return "☠️  Mort permanente : %s" % ("oui" if _permadeath else "non")
#endregion


#region Helpers
func _campaign() -> Node:
	return get_node_or_null("/root/Campaign")


func _has_save() -> bool:
	var campaign: Node = _campaign()
	return campaign.has_save(0) if campaign else false


## Une sauvegarde, quel que soit son emplacement ?
func _has_any_save() -> bool:
	var campaign: Node = _campaign()
	if not campaign:
		return false
	for slot: int in range(campaign.SAVE_SLOTS):
		if campaign.has_save(slot):
			return true
	return false


func _save_summary() -> String:
	var campaign: Node = _campaign()
	if not campaign or not campaign.has_save(0):
		return "Aucune sauvegarde — commence une nouvelle partie."
	return "Sauvegarde trouvée : %s" % ProjectSettings.globalize_path(campaign.save_path(0))


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


func _make_button(text: String, accent: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	# Les boutons s'étirent dans leur colonne : une largeur mini suffit, la
	# grille fait le reste selon la place disponible.
	btn.custom_minimum_size = Vector2(280, 46)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", 18)

	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if accent else C_BUTTON
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(C_ACCENT).lightened(0.15) if accent else C_BUTTON_HOVER
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	return btn
#endregion
