class_name BattleInventoryPanel
extends Control
## Le sac et le fourreau d'une unité, ouverts au milieu d'une bataille.
##
## Jusqu'ici l'inventaire ne se consultait qu'à l'intendance : une potion achetée
## avant le chapitre restait au fond du sac pendant qu'on la regardait mourir, et
## l'arme du départ était celle de toute la bataille. Deux gestes que tout Fire
## Emblem accorde en plein combat, et que le menu d'actions ne proposait pas.
##
## Le panneau ne décide de rien : il liste, et **émet**. C'est
## [TacticsControlsSelectionService] qui consomme l'objet, applique l'effet et
## clôt le tour — la même règle que « Attendre », au même endroit.
##
## Monté en code plutôt qu'en `.tscn` : il n'existe que le temps d'un choix, et
## son contenu dépend entièrement de l'unité ouverte.

## L'unité veut boire/se parer. Le tour se consomme (voir le service).
signal item_chosen(item_name: String)
## L'unité change d'arme. Gratuit : c'est un choix, pas une action.
signal weapon_chosen(weapon_id: String)
## Le panneau se referme sans rien faire.
signal closed

## Largeur du panneau. Assez large pour une description d'arme sur une ligne.
const WIDTH: int = 460

var _pawn: TacticsPawn = null
var _rows: VBoxContainer = null


## Ouvre l'inventaire de [param pawn] par-dessus [param parent].
##
## Rend `null` si le pion n'a rien à montrer : ouvrir un panneau vide ferait
## croire à un bug plutôt qu'à un sac vide.
static func open(parent: Node, pawn: TacticsPawn) -> BattleInventoryPanel:
	if not parent or not pawn or not is_instance_valid(pawn) or not pawn.stats:
		return null
	if not has_content(pawn):
		return null

	var panel := BattleInventoryPanel.new()
	panel._pawn = pawn
	parent.add_child(panel)
	return panel


## L'unité a-t-elle de quoi remplir le panneau ?
##
## Sert aussi à griser le bouton du menu d'actions : un bouton qui ouvre le vide
## est un bouton qui ment.
static func has_content(pawn: TacticsPawn) -> bool:
	if not pawn or not is_instance_valid(pawn) or not pawn.stats:
		return false
	return not pawn.stats.items.is_empty() or not pawn.stats.weapons.is_empty()


## Un objet est-il utilisable au milieu d'une bataille ?
##
## Les gains permanents (BOOST) ne le sont pas : ils se boivent à l'intendance,
## où le roster les enregistre. Bus ici, le gain vivrait le temps de la bataille
## et disparaîtrait au report — un objet à 900 or évaporé sans rien dire.
static func usable_in_battle(item_name: String) -> bool:
	return ItemDB.exists(item_name) and not ItemDB.is_boost(item_name)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Le panneau prend la main : un clic à côté le referme, et rien derrière lui
	# ne doit répondre — sans quoi choisir une potion sélectionnerait aussi la
	# case du plateau qui se trouve dessous.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.45)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.custom_minimum_size = Vector2(WIDTH, 0)
	frame.offset_left = -WIDTH / 2.0
	frame.offset_right = WIDTH / 2.0
	frame.offset_top = -220
	frame.offset_bottom = 220
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)

	var title := Label.new()
	title.text = "Inventaire — %s" % _pawn.base_name()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#f5c842"))
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	_build_items()
	_build_weapons()

	var close := Button.new()
	close.text = "Retour"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(_dismiss)
	column.add_child(close)


## Le sac : une ligne par consommable, « Utiliser » seulement si l'effet vaut
## quelque chose ici.
func _build_items() -> void:
	_rows.add_child(_heading("Sac (%d/%d)" % [_pawn.stats.items.size(), ItemDB.MAX_ITEMS]))
	if _pawn.stats.items.is_empty():
		_rows.add_child(_note("Le sac est vide."))
		return

	for item_name: String in _pawn.stats.items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(ItemIcon.of_item(item_name))

		var label := Label.new()
		label.text = ItemDB.label(item_name)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 15)
		row.add_child(label)

		var effect := Label.new()
		effect.text = _effect_of(item_name)
		effect.add_theme_font_size_override("font_size", 13)
		effect.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		row.add_child(effect)

		var use := Button.new()
		use.text = "Utiliser"
		use.custom_minimum_size = Vector2(96, 32)
		if usable_in_battle(item_name):
			use.pressed.connect(_on_item_pressed.bind(item_name))
		else:
			use.disabled = true
			use.tooltip_text = "Se garde pour l'intendance."
		row.add_child(use)

		_rows.add_child(row)


## Le fourreau : l'arme en main d'abord, puis celles qu'on peut lui substituer.
func _build_weapons() -> void:
	_rows.add_child(_heading("Armes"))
	var arsenal: Array = _pawn.stats.arsenal()
	if arsenal.is_empty():
		_rows.add_child(_note("Cette unité se bat avec ce que sa fiche lui donne."))
		return

	for weapon: Dictionary in arsenal:
		var equipped: bool = bool(weapon["equipped"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(ItemIcon.of_weapon(str(weapon["id"])))

		var label := Label.new()
		label.text = ("▸ %s" % str(weapon["label"])) if equipped else str(weapon["label"])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 15)
		if equipped:
			label.add_theme_color_override("font_color", Color("#f5c842"))
		row.add_child(label)

		var stats := Label.new()
		stats.text = str(weapon["description"])
		stats.add_theme_font_size_override("font_size", 13)
		stats.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		row.add_child(stats)

		var equip := Button.new()
		equip.text = "En main" if equipped else "Équiper"
		equip.custom_minimum_size = Vector2(96, 32)
		equip.disabled = equipped
		if not equipped:
			equip.pressed.connect(_on_weapon_pressed.bind(str(weapon["id"])))
		row.add_child(equip)

		_rows.add_child(row)


## Ce que l'objet fait, en trois mots.
func _effect_of(item_name: String) -> String:
	var item: Dictionary = ItemDB.get_item(item_name)
	match int(item.get("kind", ItemDB.Kind.HEAL)):
		ItemDB.Kind.HEAL:
			var amount: int = int(item.get("amount", 0))
			return "PV max" if amount >= 999 else "+%d PV" % amount
		ItemDB.Kind.BUFF:
			return "+%d %s (%d tours)" % [
				int(item.get("amount", 0)),
				str(item.get("stat", "")).to_upper(),
				int(item.get("turns", 0)),
			]
		ItemDB.Kind.BOOST:
			return "définitif"
	return ""


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	return label


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	return label


func _on_item_pressed(item_name: String) -> void:
	item_chosen.emit(item_name)
	_dismiss()


func _on_weapon_pressed(weapon_id: String) -> void:
	weapon_chosen.emit(weapon_id)
	# Changer d'arme ne coûte rien : on rouvre sur le fourreau à jour plutôt que
	# de renvoyer le joueur au menu d'actions pour un second aller-retour.
	_refresh()


## Reconstruit les lignes après un changement d'arme.
func _refresh() -> void:
	if not is_instance_valid(_pawn) or not _pawn.stats:
		_dismiss()
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_build_items()
	_build_weapons()


func _dismiss() -> void:
	closed.emit()
	queue_free()


func _gui_input(event: InputEvent) -> void:
	# Un clic dans le vide referme : c'est le geste attendu d'une fenêtre modale.
	if event is InputEventMouseButton and event.pressed:
		_dismiss()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_dismiss()
		# Sans ceci, Échap traverserait jusqu'à [Main], qui ramène à l'écran-titre :
		# refermer son sac quitterait la bataille.
		get_viewport().set_input_as_handled()
