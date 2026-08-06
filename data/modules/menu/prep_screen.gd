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
const WEAPONS = preload("res://data/models/world/stats/weapon_db.gd")
const SKILLS = preload("res://data/models/world/stats/skill_db.gd")
const CDB = preload("res://data/models/world/stats/class_data.gd")
const CMAP = preload("res://data/models/campaign/chapter_map.gd")
const MAP_DATA = preload("res://data/models/world/map/map_data.gd")

## Glyphe et couleur de chaque terrain, pour lire la carte d'un coup d'œil.
const TERRAIN_GLYPH: Dictionary = {
	MAP_DATA.TerrainType.GRASS: "·",
	MAP_DATA.TerrainType.FOREST: "♣",
	MAP_DATA.TerrainType.MOUNTAIN: "▲",
	MAP_DATA.TerrainType.WATER: "≈",
	MAP_DATA.TerrainType.PATH: "─",
	MAP_DATA.TerrainType.WALL: "█",
	MAP_DATA.TerrainType.PIT: "▒",
}
const TERRAIN_COLOR: Dictionary = {
	MAP_DATA.TerrainType.GRASS: Color("#5a8f4a"),
	MAP_DATA.TerrainType.FOREST: Color("#2f6b34"),
	MAP_DATA.TerrainType.MOUNTAIN: Color("#7a6a55"),
	MAP_DATA.TerrainType.WATER: Color("#2b5a8f"),
	MAP_DATA.TerrainType.PATH: Color("#8a7a5c"),
	MAP_DATA.TerrainType.WALL: Color("#3a3a44"),
	MAP_DATA.TerrainType.PIT: Color("#15151c"),
}

var _selected: Array = []
var _slots_label: Label
var _unit_rows: VBoxContainer
var _start_button: Button
var _shop_panel: Control = null
var _equip_panel: Control = null
## Unité affichée au menu d'équipement — retenue pour que changer d'arme ne
## renvoie pas le joueur en tête de liste à chaque clic.
var _equip_unit: String = ""
var _positions_panel: Control = null
## Unité à poser au menu des positions
var _position_unit: String = ""
## Carte du chapitre lue une seule fois ([ChapterMap])
var _map: Dictionary = {}


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

	var equip := _make_button("⚔  Équipement", false)
	equip.pressed.connect(_toggle_equipment)
	buttons.add_child(equip)

	var positions := _make_button("🗺  Positions", false)
	positions.pressed.connect(_toggle_positions)
	buttons.add_child(positions)

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

	var posted: int = 0
	for id in _selected:
		if campaign.deployment_tile(str(id)).x >= 0:
			posted += 1
	_slots_label.text = "Déploiement : %d / %d place(s)   —   Positions choisies : %d   —   Or : %d   —   Niveau conseillé : %d" % [
		_selected.size(), chapter.deploy_slots, posted, campaign.gold, chapter.recommended_level
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

	# L'arme en main se lit sur la ligne : c'est elle qui décide de la moitié d'un
	# échange, et on la choisit juste à côté, au menu d'équipement.
	var weapon: String = str(unit.get("weapon", ""))
	var weapon_text: String = "⚔ %s" % WEAPONS.label(weapon) if not weapon.is_empty() else "⚔ —"

	row.text = "%s  %-14s Lv.%-3d %-14s PV %d/%d  MOV %d  %-18s %s" % [
		"🔒" if required else ("✔" if row.button_pressed else "  "),
		str(unit.get("name", "?")),
		int(unit.get("level", 1)),
		campaign.unit_class_name(unit),
		int(unit.get("hp", 0)), int(unit.get("max_hp", 0)),
		int(unit.get("movement", 0)),
		weapon_text,
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

	# --- Armurerie ---
	var forge := Label.new()
	forge.text = "⚔  ARMURERIE  (fourreau : %d armes max — l'arme en main se choisit au menu Équipement)" % WEAPONS.MAX_WEAPONS
	forge.add_theme_font_size_override("font_size", 13)
	forge.add_theme_color_override("font_color", C_GOLD)
	shop_list.add_child(forge)

	for weapon_id: String in WEAPONS.shop_stock():
		var w_row := HBoxContainer.new()
		w_row.add_theme_constant_override("separation", 8)

		var w_label := Label.new()
		w_label.text = "%-20s %-34s %5d or" % [
			WEAPONS.label(weapon_id), WEAPONS.describe(weapon_id), WEAPONS.price(weapon_id)
		]
		w_label.add_theme_font_size_override("font_size", 13)
		w_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		w_row.add_child(w_label)

		var buy_weapon := _make_button("Acheter", false)
		buy_weapon.custom_minimum_size = Vector2(120, 30)
		buy_weapon.pressed.connect(func() -> void:
			var r: Dictionary = campaign.buy_weapon(selected_id.call(), weapon_id)
			if bool(r.get("ok", false)):
				status.text = "%s acheté (%d or)%s." % [
					WEAPONS.label(weapon_id), int(r.get("cost", 0)),
					" et mis en main" if bool(r.get("equipped", false)) else "",
				]
			else:
				status.text = str(r.get("reason", ""))
			_rebuild_shop())
		w_row.add_child(buy_weapon)

		var sell_weapon := _make_button("Revendre", false)
		sell_weapon.custom_minimum_size = Vector2(120, 30)
		sell_weapon.pressed.connect(func() -> void:
			var r: Dictionary = campaign.sell_weapon(selected_id.call(), weapon_id)
			status.text = ("%s revendu (+%d or)." % [
				WEAPONS.label(weapon_id), int(r.get("earned", 0))
			]) if bool(r.get("ok", false)) else str(r.get("reason", ""))
			_rebuild_shop())
		w_row.add_child(sell_weapon)

		shop_list.add_child(w_row)

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


## Ouvre/ferme le menu d'équipement : quelle arme chaque unité prend en main.
func _toggle_equipment() -> void:
	if _equip_panel and is_instance_valid(_equip_panel):
		_equip_panel.queue_free()
		_equip_panel = null
		_refresh()
		return
	_equip_panel = _build_equipment()
	add_child(_equip_panel)


## Menu d'équipement — une unité, son fourreau, et l'arme qu'elle empoigne.
##
## Le fourreau se remplit à l'intendance ; ici on n'achète rien, on décide.
## Chaque arme annonce ce qu'elle change (puissance, portée, précision, critique)
## et ce qu'elle coûte en vitesse d'attaque pour cette unité-là — une hache
## d'acier ne pèse pas le même poids sur un mage et sur un guerrier.
func _build_equipment() -> Control:
	var campaign: Node = get_node_or_null("/root/Campaign")
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 140
	box.offset_right = -140
	box.offset_top = 70
	box.offset_bottom = -70
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "⚔  ÉQUIPEMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_GOLD)
	box.add_child(title)

	if not campaign:
		return panel

	var target := OptionButton.new()
	target.custom_minimum_size = Vector2(0, 34)
	for u: Dictionary in campaign.available_units():
		var held: String = str(u.get("weapon", ""))
		target.add_item("%s — %s" % [
			str(u["name"]), WEAPONS.label(held) if not held.is_empty() else "mains nues"
		])
		target.set_item_metadata(target.item_count - 1, str(u["id"]))
		if str(u["id"]) == _equip_unit:
			target.select(target.item_count - 1)
	if target.item_count > 0 and target.selected < 0:
		target.select(0)
	box.add_child(target)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", C_ACCENT)
	status.text = "Choisis une unité, puis l'arme qu'elle porte au combat."
	box.add_child(status)

	var list := VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	box.add_child(list)

	var fill := func() -> void:
		for child in list.get_children():
			child.queue_free()
		if target.item_count == 0 or target.selected < 0:
			return
		var unit_id: String = str(target.get_item_metadata(target.selected))
		_equip_unit = unit_id
		var arsenal: Array = campaign.unit_arsenal(unit_id)
		if arsenal.is_empty():
			var empty := Label.new()
			empty.text = "Fourreau vide — achète une arme à l'intendance."
			empty.add_theme_font_size_override("font_size", 14)
			empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
			list.add_child(empty)
			return

		var unit: Dictionary = campaign.get_unit(unit_id)
		for weapon: Dictionary in arsenal:
			list.add_child(_make_weapon_row(campaign, unit, weapon, status))

	target.item_selected.connect(func(_i: int) -> void: fill.call())
	fill.call()

	var close := _make_button("Fermer", true)
	close.pressed.connect(_toggle_equipment)
	box.add_child(close)

	return panel


## Une ligne du menu d'équipement : l'arme, ce qu'elle vaut, et le bouton qui la
## met en main (grisé si elle y est déjà).
func _make_weapon_row(campaign: Node, unit: Dictionary, weapon: Dictionary,
		status: Label) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var penalty: int = maxi(0, int(WEAPONS.get_weapon(str(weapon["id"])).get("weight", 0))
		- int(unit.get("str", 0)))

	var label := Label.new()
	label.text = "%s %-20s %s%s" % [
		"▶" if bool(weapon["equipped"]) else "  ",
		str(weapon["label"]),
		str(weapon["description"]),
		("   ⏳ VIT −%d" % penalty) if penalty > 0 else "",
	]
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", C_GOLD if bool(weapon["equipped"]) else C_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var equip := _make_button("Équiper", false)
	equip.custom_minimum_size = Vector2(120, 30)
	equip.disabled = bool(weapon["equipped"])
	equip.pressed.connect(func() -> void:
		var r: Dictionary = campaign.equip_weapon(str(unit.get("id", "")), str(weapon["id"]))
		status.text = ("%s prend %s en main." % [
			str(unit.get("name", "")), str(weapon["label"])
		]) if bool(r.get("ok", false)) else str(r.get("reason", ""))
		_rebuild_equipment())
	row.add_child(equip)

	return row


## Reconstruit le menu d'équipement après un changement d'arme.
func _rebuild_equipment() -> void:
	if not _equip_panel or not is_instance_valid(_equip_panel):
		return
	var old: Control = _equip_panel
	_equip_panel = _build_equipment()
	add_child(_equip_panel)
	old.queue_free()
	_refresh()


#region Positions de départ
## Ouvre/ferme le choix des cases de départ — donc du terrain.
func _toggle_positions() -> void:
	if _positions_panel and is_instance_valid(_positions_panel):
		_positions_panel.queue_free()
		_positions_panel = null
		# La fermeture emporte les nœuds que la closure de reconstruction tenait.
		remove_meta("positions_rebuild")
		_refresh()
		return
	_positions_panel = _build_positions()
	add_child(_positions_panel)


## Choix des cases de départ, avec le terrain de chacune.
##
## Le bonus défensif d'une case était calculé de bout en bout depuis longtemps —
## jusqu'au pont CielAI — sans que le joueur puisse jamais le choisir. C'est le
## sens de cet écran : poser l'archer dans la forêt (+1 DÉF) avant que le premier
## coup ne parte, plutôt que de le découvrir en encaissant.
func _build_positions() -> Control:
	var campaign: Node = get_node_or_null("/root/Campaign")
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 80
	box.offset_right = -80
	box.offset_top = 40
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "🗺  POSITIONS DE DÉPART"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_GOLD)
	box.add_child(title)

	if _map.is_empty():
		_map = CMAP.read(chapter)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", C_ACCENT)
	box.add_child(status)

	if not campaign or not bool(_map.get("ok", false)):
		# Une carte écrite à la main ne déclare pas son terrain : on le dit, et le
		# placement se fera comme avant, en jeu, à l'ouverture de la bataille.
		status.text = "Cette carte ne se lit pas d'avance (%s).\nLe placement restera possible en début de bataille." % str(_map.get("reason", "raison inconnue"))
		var back := _make_button("Fermer", true)
		back.pressed.connect(_toggle_positions)
		box.add_child(back)
		return panel

	status.text = "Choisis une unité, puis sa case. Deux unités posées sur la même case échangent leurs places."

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	box.add_child(columns)

	var roster_column := VBoxContainer.new()
	roster_column.custom_minimum_size = Vector2(300, 0)
	roster_column.add_theme_constant_override("separation", 4)
	columns.add_child(roster_column)

	var grid_holder := VBoxContainer.new()
	grid_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(grid_holder)

	# `queue_free` seul laisserait l'ancien contenu une frame de plus, et les deux
	# versions se chevaucheraient dans le conteneur : on détache tout de suite.
	var rebuild := func() -> void:
		for column: Node in [roster_column, grid_holder]:
			for child in column.get_children():
				column.remove_child(child)
				child.queue_free()
		_fill_position_roster(roster_column, campaign, status)
		grid_holder.add_child(_build_position_grid(campaign, status))

	set_meta("positions_rebuild", rebuild)
	rebuild.call()

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)

	var reset := _make_button("Réinitialiser", false)
	reset.pressed.connect(func() -> void:
		campaign.clear_deployment_tiles()
		status.text = "Positions remises à la ligne de départ de la carte."
		_rebuild_positions())
	footer.add_child(reset)

	var close := _make_button("Fermer", true)
	close.pressed.connect(_toggle_positions)
	footer.add_child(close)

	return panel


## Colonne de gauche : les unités déployées, et la case de chacune.
func _fill_position_roster(column: VBoxContainer, campaign: Node, status: Label) -> void:
	var header := Label.new()
	header.text = "Unités déployées (%d)" % _selected.size()
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", C_GOLD)
	column.add_child(header)

	if _selected.is_empty():
		var none := Label.new()
		none.text = "Aucune unité sélectionnée."
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		column.add_child(none)
		return

	for id in _selected:
		var unit: Dictionary = campaign.get_unit(str(id))
		if unit.is_empty():
			continue
		var pos: Vector2i = campaign.deployment_tile(str(id))
		var placed: bool = pos.x >= 0
		var bonus: int = CMAP.defense_at(_map, pos) if placed else 0

		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = str(id) == _position_unit
		btn.custom_minimum_size = Vector2(0, 34)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s %-13s %s" % [
			"▶" if str(id) == _position_unit else "  ",
			str(unit.get("name", "?")),
			("(%d, %d) %s" % [pos.x, pos.y, _terrain_note(pos, bonus)]) if placed else "— non posée",
		]
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", C_GOLD if placed else C_TEXT)
		var style := StyleBoxFlat.new()
		style.bg_color = C_PANEL
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		btn.add_theme_stylebox_override("normal", style)
		var pressed_style := style.duplicate() as StyleBoxFlat
		pressed_style.bg_color = C_BUTTON
		pressed_style.border_width_left = 4
		pressed_style.border_color = C_GOLD
		btn.add_theme_stylebox_override("pressed", pressed_style)

		var unit_id: String = str(id)
		btn.pressed.connect(func() -> void:
			_position_unit = unit_id
			status.text = "%s en main — clique une case." % str(unit.get("name", "?"))
			_rebuild_positions())
		column.add_child(btn)


## La zone de déploiement, case par case, terrain compris.
func _build_position_grid(campaign: Node, status: Label) -> Control:
	var slots: Array = _map["slots"]
	var min_col: int = 9999
	var max_col: int = -1
	var min_row: int = 9999
	var max_row: int = -1
	for pos: Vector2i in slots:
		min_col = mini(min_col, pos.x)
		max_col = maxi(max_col, pos.x)
		min_row = mini(min_row, pos.y)
		max_row = maxi(max_row, pos.y)

	# Qui occupe quoi, pour marquer les cases prises d'un coup d'œil.
	var occupants: Dictionary = {}
	for id in _selected:
		var pos: Vector2i = campaign.deployment_tile(str(id))
		if pos.x >= 0:
			occupants[pos] = str(campaign.get_unit(str(id)).get("name", "?"))

	var grid := GridContainer.new()
	grid.columns = max_col - min_col + 1
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)

	for row: int in range(min_row, max_row + 1):
		for col: int in range(min_col, max_col + 1):
			var pos := Vector2i(col, row)
			grid.add_child(_make_tile_button(pos, slots.has(pos), occupants, campaign, status))

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 6)
	wrapper.add_child(grid)

	var legend := Label.new()
	legend.text = "♣ Forêt +1 DÉF     ▲ Montagne +3 DÉF (infranchissable)     · Plaine     ─ Chemin     ≈ Eau"
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	wrapper.add_child(legend)
	return wrapper


## Une case de la zone : son terrain, son bonus, et qui s'y tient.
func _make_tile_button(pos: Vector2i, open: bool, occupants: Dictionary,
		campaign: Node, status: Label) -> Button:
	var terrain: int = CMAP.terrain_at(_map, pos)
	var bonus: int = CMAP.defense_at(_map, pos)
	var occupant: String = str(occupants.get(pos, ""))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(52, 46)
	btn.disabled = not open
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = ("%s\n%s" % [
		occupant.substr(0, 4) if not occupant.is_empty() else str(TERRAIN_GLYPH.get(terrain, "?")),
		"+%d" % bonus if bonus > 0 else "",
	]).strip_edges()
	btn.add_theme_font_size_override("font_size", 12)
	btn.tooltip_text = "(%d, %d) — %s%s" % [
		pos.x, pos.y, _terrain_name(terrain),
		"" if occupant.is_empty() else "\n%s s'y tient" % occupant,
	]

	var style := StyleBoxFlat.new()
	style.bg_color = TERRAIN_COLOR.get(terrain, C_PANEL)
	if not open:
		style.bg_color = style.bg_color.darkened(0.55)
	style.set_corner_radius_all(4)
	if not occupant.is_empty():
		style.border_width_bottom = 3
		style.border_width_top = 3
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_color = C_GOLD
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_stylebox_override("hover", style.duplicate())
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))

	if not open:
		return btn

	btn.pressed.connect(func() -> void:
		# Une unité décochée entre-temps ne se pose plus : sa case serait effacée
		# au lancement de la bataille, et le clic aurait menti.
		if _position_unit.is_empty() or not _position_unit in _selected:
			status.text = "Choisis d'abord une unité déployée, à gauche."
			return
		campaign.set_deployment_tile(_position_unit, pos)
		var unit: Dictionary = campaign.get_unit(_position_unit)
		status.text = "%s se poste en (%d, %d) — %s." % [
			str(unit.get("name", "?")), pos.x, pos.y, _terrain_note(pos, bonus)
		]
		_rebuild_positions())
	return btn


## Reconstruit les deux colonnes sans refermer le panneau.
func _rebuild_positions() -> void:
	if not _positions_panel or not is_instance_valid(_positions_panel):
		return
	if not has_meta("positions_rebuild"):
		return
	var rebuild: Callable = get_meta("positions_rebuild")
	if rebuild.is_valid():
		rebuild.call()


func _terrain_note(pos: Vector2i, bonus: int) -> String:
	var name: String = _terrain_name(CMAP.terrain_at(_map, pos))
	return "%s 🛡+%d" % [name, bonus] if bonus > 0 else name


func _terrain_name(terrain: int) -> String:
	return UnitSheet.terrain_label(TacticsGrid.terrain_type_name(terrain))
#endregion


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
