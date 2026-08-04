extends Control
## Écran de préparation d'un chapitre : intro, objectif, sélection des unités.
##
## Équivalent minimal de la « prep screen » de Fire Emblem : on lit le contexte,
## on choisit qui part au combat (dans la limite des places), puis on lance.

signal battle_requested()
signal back_requested()

const C_BG := Color("#141026")
const C_PANEL := Color("#16213e")
const C_ACCENT := Color("#e94560")
const C_GOLD := Color("#f5c842")
const C_TEXT := Color("#eeeeee")
const C_BUTTON := Color("#0f3460")

var chapter: ChapterData = null

const ITEMS = preload("res://data/models/world/stats/item_db.gd")
const SKILLS = preload("res://data/models/world/stats/skill_db.gd")
const CDB = preload("res://data/models/world/stats/class_data.gd")

var _selected: Array = []
var _slots_label: Label
var _unit_rows: VBoxContainer
var _start_button: Button
var _shop_panel: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var campaign: Node = get_node_or_null("/root/Campaign")
	if campaign:
		_selected = campaign.deployment.duplicate()
		# Le déploiement peut venir du chapitre précédent : les unités imposées
		# ici doivent apparaître cochées dès l'ouverture de l'écran.
		for id: String in campaign.required_deployment():
			if not id in _selected:
				_selected.push_front(id)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = chapter.title if chapter else "Chapitre"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", C_GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30
	title.offset_bottom = 70
	add_child(title)

	var objective := Label.new()
	objective.text = "🎯 %s   |   %s" % [
		chapter.objective_text() if chapter else "—",
		chapter.subtitle if chapter else "",
	]
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.add_theme_font_size_override("font_size", 15)
	objective.add_theme_color_override("font_color", C_ACCENT)
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective.offset_top = 72
	objective.offset_bottom = 98
	add_child(objective)

	# Introduction narrative
	var intro := Label.new()
	intro.text = "\n".join(chapter.intro_lines) if chapter else ""
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 14)
	intro.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	intro.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	intro.offset_left = 120
	intro.offset_right = -120
	intro.offset_top = 108
	intro.offset_bottom = 190
	add_child(intro)

	_slots_label = Label.new()
	_slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slots_label.add_theme_font_size_override("font_size", 14)
	_slots_label.add_theme_color_override("font_color", C_GOLD)
	_slots_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_slots_label.offset_top = 196
	_slots_label.offset_bottom = 220
	add_child(_slots_label)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 160
	scroll.offset_right = -160
	scroll.offset_top = 228
	scroll.offset_bottom = -110
	add_child(scroll)

	_unit_rows = VBoxContainer.new()
	_unit_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_unit_rows)

	var buttons := HBoxContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.offset_top = -90
	buttons.offset_bottom = -30
	buttons.add_theme_constant_override("separation", 16)
	add_child(buttons)

	var back := _make_button("← Retour", false)
	back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back)

	var shop := _make_button("🛒  Intendance", false)
	shop.pressed.connect(_toggle_shop)
	buttons.add_child(shop)

	_start_button = _make_button("⚔️  Lancer la bataille", true)
	_start_button.pressed.connect(_on_start)
	buttons.add_child(_start_button)

	_refresh()


func _refresh() -> void:
	var campaign: Node = get_node_or_null("/root/Campaign")
	if not campaign or not chapter:
		return

	for child in _unit_rows.get_children():
		child.queue_free()

	for unit: Dictionary in campaign.available_units():
		_unit_rows.add_child(_make_unit_row(unit, campaign))

	# Unités tombées : affichées grisées, pour que la perte se voie.
	for unit: Dictionary in campaign.roster:
		if not bool(unit.get("alive", true)):
			var lost := Label.new()
			lost.text = "☠ %s — tombé au combat" % str(unit.get("name", "?"))
			lost.add_theme_font_size_override("font_size", 13)
			lost.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
			_unit_rows.add_child(lost)

	_slots_label.text = "Déploiement : %d / %d place(s)   —   Or : %d   —   Niveau conseillé : %d" % [
		_selected.size(), chapter.deploy_slots, campaign.gold, chapter.recommended_level
	]
	_start_button.disabled = _selected.is_empty()


func _make_unit_row(unit: Dictionary, campaign: Node) -> Control:
	var id: String = str(unit.get("id", ""))
	# Une unité imposée par le chapitre (la protégée, le seigneur) est cochée et
	# verrouillée : la décocher rendrait l'objectif intenable.
	var required: bool = id in chapter.required_units
	var row := Button.new()
	row.toggle_mode = true
	row.button_pressed = id in _selected or required
	row.disabled = required
	if required:
		row.tooltip_text = "Cette unité est imposée par le chapitre."
	row.custom_minimum_size = Vector2(0, 42)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var skills: Array = []
	for skill_id in CDB.unlocked_skills(int(unit.get("class_id", 0)), int(unit.get("level", 1))):
		skills.append(SKILLS.get_skill_name(str(skill_id)))

	row.text = "%s  %-14s Lv.%-3d %-14s PV %d/%d  MOV %d  %s" % [
		"🔒" if required else ("✔" if row.button_pressed else "  "),
		str(unit.get("name", "?")),
		int(unit.get("level", 1)),
		campaign.unit_class_name(unit),
		int(unit.get("hp", 0)), int(unit.get("max_hp", 0)),
		int(unit.get("movement", 0)),
		("✨ " + ", ".join(skills)) if not skills.is_empty() else "",
	]
	row.add_theme_font_size_override("font_size", 14)

	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	row.add_theme_stylebox_override("normal", style)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = C_BUTTON
	pressed.border_width_left = 4
	pressed.border_color = C_GOLD
	row.add_theme_stylebox_override("pressed", pressed)
	row.add_theme_color_override("font_color", C_TEXT)

	row.toggled.connect(func(on: bool) -> void: _on_unit_toggled(id, on))
	return row


func _on_unit_toggled(id: String, on: bool) -> void:
	if on:
		if _selected.size() >= chapter.deploy_slots:
			_refresh()  # Places épuisées : on annule visuellement la sélection.
			return
		if not id in _selected:
			_selected.append(id)
	else:
		_selected.erase(id)
	_refresh()


func _on_start() -> void:
	var campaign: Node = get_node_or_null("/root/Campaign")
	if campaign:
		campaign.set_deployment(_selected)
	battle_requested.emit()


#region Intendance
## Ouvre/ferme la boutique : achats, soins et recrutement entre deux chapitres.
func _toggle_shop() -> void:
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
		_shop_panel = null
		_refresh()
		return
	_shop_panel = _build_shop()
	add_child(_shop_panel)


func _build_shop() -> Control:
	var campaign: Node = get_node_or_null("/root/Campaign")
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 120
	box.offset_right = -120
	box.offset_top = 60
	box.offset_bottom = -60
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "🛒  INTENDANCE — Or : %d" % (campaign.gold if campaign else 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_GOLD)
	box.add_child(title)

	if not campaign:
		return panel

	# Unité destinataire des achats
	var target := OptionButton.new()
	target.custom_minimum_size = Vector2(0, 34)
	for u: Dictionary in campaign.available_units():
		target.add_item("%s (%d/%d PV, %d objet(s))" % [
			str(u["name"]), int(u["hp"]), int(u["max_hp"]), u.get("items", []).size()
		])
		target.set_item_metadata(target.item_count - 1, str(u["id"]))
	if target.item_count > 0:
		target.select(0)
	box.add_child(target)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", C_ACCENT)
	status.text = "Choisis une unité, puis achète, soigne ou recrute."
	box.add_child(status)

	var selected_id := func() -> String:
		if target.item_count == 0 or target.selected < 0:
			return ""
		return str(target.get_item_metadata(target.selected))

	# --- Soins ---
	var heal_row := HBoxContainer.new()
	heal_row.add_theme_constant_override("separation", 8)
	var heal_one := _make_button("⚕ Soigner l'unité", false)
	heal_one.custom_minimum_size = Vector2(260, 36)
	heal_one.pressed.connect(func() -> void:
		var r: Dictionary = campaign.heal_unit(selected_id.call())
		status.text = ("Soigné de %d PV pour %d or." % [int(r.get("healed", 0)), int(r.get("cost", 0))]) \
			if bool(r.get("ok", false)) else str(r.get("reason", ""))
		_rebuild_shop())
	heal_row.add_child(heal_one)

	var heal_all := _make_button("⚕ Tout soigner (%d or)" % campaign.heal_all_cost(), false)
	heal_all.custom_minimum_size = Vector2(260, 36)
	heal_all.pressed.connect(func() -> void:
		var r: Dictionary = campaign.heal_all()
		status.text = "%d unité(s) soignée(s) pour %d or." % [
			int(r.get("healed_units", 0)), int(r.get("cost", 0))]
		_rebuild_shop())
	heal_row.add_child(heal_all)
	box.add_child(heal_row)

	# --- Boutique ---
	var shop_scroll := ScrollContainer.new()
	shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var shop_list := VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("separation", 4)
	shop_scroll.add_child(shop_list)
	box.add_child(shop_scroll)

	for item_name: String in ITEMS.shop_stock():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.text = "%-28s %5d or" % [ITEMS.label(item_name), ITEMS.price(item_name)]
		label.add_theme_font_size_override("font_size", 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var buy := _make_button("Acheter", false)
		buy.custom_minimum_size = Vector2(120, 30)
		buy.pressed.connect(func() -> void:
			var r: Dictionary = campaign.buy_item(selected_id.call(), item_name)
			status.text = ("%s acheté (%d or)." % [item_name, int(r.get("cost", 0))]) \
				if bool(r.get("ok", false)) else str(r.get("reason", ""))
			_rebuild_shop())
		row.add_child(buy)

		if ITEMS.is_boost(item_name):
			var use := _make_button("Utiliser", false)
			use.custom_minimum_size = Vector2(120, 30)
			use.pressed.connect(func() -> void:
				var r: Dictionary = campaign.use_booster(selected_id.call(), item_name)
				status.text = ("+%d %s définitif." % [int(r.get("amount", 0)), str(r.get("stat", ""))]) \
					if bool(r.get("ok", false)) else str(r.get("reason", ""))
				_rebuild_shop())
			row.add_child(use)

		shop_list.add_child(row)

	# --- Recrutement ---
	for recruit: Dictionary in campaign.available_recruits():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = "🎖 %s — %s Lv.%d — %d or" % [
			str(recruit["name"]), str(recruit["class"]), int(recruit["level"]), int(recruit["cost"])]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", C_GOLD)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var hire := _make_button("Recruter", false)
		hire.custom_minimum_size = Vector2(120, 30)
		hire.pressed.connect(func() -> void:
			var r: Dictionary = campaign.hire(str(recruit["path"]))
			status.text = ("%s rejoint l'armée." % str(recruit["name"])) \
				if bool(r.get("ok", false)) else str(r.get("reason", ""))
			_rebuild_shop())
		row.add_child(hire)
		shop_list.add_child(row)

	var close := _make_button("Fermer", true)
	close.pressed.connect(_toggle_shop)
	box.add_child(close)

	return panel


## Reconstruit le panneau après un achat (les prix et l'or ont changé).
func _rebuild_shop() -> void:
	if not _shop_panel or not is_instance_valid(_shop_panel):
		return
	var old: Control = _shop_panel
	_shop_panel = _build_shop()
	add_child(_shop_panel)
	old.queue_free()
	_refresh()
#endregion


func _make_button(text: String, accent: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(240, 46)
	btn.add_theme_font_size_override("font_size", 17)
	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if accent else C_BUTTON
	style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", C_TEXT)
	return btn
