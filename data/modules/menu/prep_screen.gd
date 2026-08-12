extends Control
## Écran de préparation d'un chapitre : intro, objectif, sélection des unités.
##
## Équivalent minimal de la « prep screen » de Fire Emblem : on lit le contexte,
## on choisit qui part au combat (dans la limite des places), puis on lance.

signal battle_requested()
signal back_requested()
signal save_requested()

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
const GLOSSARY = preload("res://data/models/world/stats/stat_glossary.gd")
const ICON = preload("res://data/modules/menu/item_icon.gd")

var _selected: Array = []
var _slots_label: Label
var _unit_rows: VBoxContainer
var _start_button: Button
var _shop_panel: Control = null
var _equip_panel: Control = null
## Unité affichée au menu d'équipement — retenue pour que changer d'arme ne
## renvoie pas le joueur en tête de liste à chaque clic.
var _equip_unit: String = ""
var _detail_panel: Control = null
## Unité affichée à la fiche détaillée.
var _detail_unit: String = ""
## Ligne de retour de la fiche détaillée (ce que l'objet consommé a fait).
var _detail_status: Label = null
## Dernier message de la fiche, retenu à travers la reconstruction du panneau :
## sans lui, « +10 PV » disparaissait au moment même où l'on venait de le mériter.
var _detail_message: String = ""


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
	title.theme_type_variation = &"TitreEmbleme"
	title.add_theme_font_size_override("font_size", 30)
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

	# Barre du bas : les boutons se partagent la largeur disponible au lieu
	# d'occuper chacun 240 px. À six, cette largeur fixe faisait 1520 px pour un
	# écran logique de 1280 : « Lancer la bataille » sortait de l'écran et
	# devenait inatteignable à la souris.
	var bar := MarginContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -90
	bar.offset_bottom = -30
	bar.add_theme_constant_override("margin_left", 24)
	bar.add_theme_constant_override("margin_right", 24)
	add_child(bar)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	bar.add_child(buttons)

	var back := _make_button("← Retour", false)
	back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back)

	var shop := _make_button("🛒  Intendance", false)
	shop.pressed.connect(_toggle_shop)
	buttons.add_child(shop)

	var equip := _make_button("⚔  Équipement", false)
	equip.pressed.connect(_toggle_equipment)
	buttons.add_child(equip)

	var detail := _make_button("📋  Fiches", false)
	detail.pressed.connect(_toggle_detail)
	buttons.add_child(detail)

	# Sauvegarder avant un chapitre risqué : c'est ici que ça se décide, la
	# bataille commencée on ne revient plus en arrière.
	var save := _make_button("💾  Sauvegarder", false)
	save.pressed.connect(func() -> void:
		var campaign: Node = get_node_or_null("/root/Campaign")
		if campaign:
			campaign.set_deployment(_selected)
		save_requested.emit())
	buttons.add_child(save)

	_start_button = _make_button("⚔️  Lancer la bataille", true)
	_start_button.pressed.connect(_on_start)
	buttons.add_child(_start_button)

	for child in buttons.get_children():
		var btn: Button = child as Button
		if btn:
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(120, 46)
			btn.clip_text = true

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

	# Les cases de départ ne se choisissent plus ici : elles se posent sur le
	# plateau, en ouvrant la bataille, là où l'on voit le terrain.
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
	row.custom_minimum_size = Vector2(0, 42)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Les compétences que l'unité aura vraiment : une recrue écrite à la main a
	# les siennes, pas celles que sa classe donnerait.
	var skill_ids: Array = campaign.unit_skills(unit)
	var skills: Array = []
	var explained: Array[String] = []
	for skill_id in skill_ids:
		skills.append(SKILLS.get_skill_name(str(skill_id)))
		explained.append("✨ %s — %s\n   ⟶ %s" % [
			SKILLS.get_skill_name(str(skill_id)),
			SKILLS.describe(str(skill_id)),
			SKILLS.trigger_label(str(skill_id)),
		])

	# L'info-bulle de la ligne dit ce que les compétences font : le nom seul
	# n'apprend rien, et c'est ici qu'on décide qui part au combat.
	var hints: Array[String] = []
	if required:
		hints.append("Cette unité est imposée par le chapitre.")
	if not explained.is_empty():
		hints.append("\n".join(explained))
	row.tooltip_text = "\n\n".join(hints)

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

	# Plus de soins à vendre : l'armée se repose toute seule entre deux batailles,
	# gagnées ou perdues. Faire payer tirait la difficulté dans le mauvais sens —
	# l'or manque justement quand la campagne va mal.

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
		row.add_child(ICON.of_item(item_name))

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

		# « Utiliser » vaut pour tout le catalogue, pas seulement les gains
		# permanents : une potion achetée ici se boit ici, sinon elle ne servait à
		# rien tant qu'on n'était pas en bataille — où le joueur n'a pas non plus de
		# geste pour la boire.
		var use := _make_button("Utiliser", false)
		use.custom_minimum_size = Vector2(120, 30)
		use.pressed.connect(func() -> void:
			var r: Dictionary = campaign.use_item(selected_id.call(), item_name)
			status.text = _item_use_message(r, item_name)
			_rebuild_shop())
		row.add_child(use)

		# Revendre ne valait que pour les armes : l'objet acheté par erreur restait
		# sur les bras de l'unité.
		var sell := _make_button("Revendre", false)
		sell.custom_minimum_size = Vector2(120, 30)
		sell.pressed.connect(func() -> void:
			var r: Dictionary = campaign.sell_item(selected_id.call(), item_name)
			status.text = ("%s revendu (+%d or)." % [
				ITEMS.label(item_name), int(r.get("earned", 0))
			]) if bool(r.get("ok", false)) else str(r.get("reason", ""))
			_rebuild_shop())
		row.add_child(sell)

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
		w_row.add_child(ICON.of_weapon(weapon_id))

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

	# --- Personnages écrits par le joueur ---
	# L'éditeur de personnages savait les créer et les enregistrer, mais rien ne
	# les faisait entrer dans une campagne : `enlist_custom` existait sans que
	# personne l'appelle. C'est ici que le pont se fait, sur la même ligne que
	# les autres recrues.
	for made: Dictionary in campaign.custom_recruits():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		var price: int = int(made["cost"])
		label.text = "✎ %s — %s Lv.%d — %s" % [
			str(made["name"]), str(made["class"]), int(made["level"]),
			"%d or" % price if price > 0 else "gratuit"]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", C_GOLD)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var enlist := _make_button("Enrôler", false)
		enlist.custom_minimum_size = Vector2(120, 30)
		enlist.pressed.connect(func() -> void:
			var r: Dictionary = campaign.hire_custom(str(made["slug"]))
			status.text = ("%s rejoint l'armée." % str(made["name"])) \
				if bool(r.get("ok", false)) else str(r.get("reason", ""))
			_rebuild_shop())
		row.add_child(enlist)
		shop_list.add_child(row)

	var close := _make_button("Fermer", true)
	close.pressed.connect(_toggle_shop)
	box.add_child(close)

	return panel


## Ouvre/ferme le menu d'équipement : quelle arme chaque unité prend en main.
#region Fiche détaillée
func _toggle_detail() -> void:
	if _detail_panel and is_instance_valid(_detail_panel):
		_detail_panel.queue_free()
		_detail_panel = null
		_refresh()
		return
	# On rouvre les fiches sur une ligne vierge : le message de la fois d'avant
	# parlerait d'un objet bu il y a longtemps.
	_detail_message = ""
	_detail_panel = _build_detail()
	add_child(_detail_panel)


## La fiche complète d'une unité : figurine, classe, statistiques, compétences,
## arsenal, inventaire.
##
## L'écran de préparation ne montrait qu'une ligne par unité — nom, niveau, PV,
## arme. Tout le reste (les statistiques que le combat utilise vraiment, les
## compétences débloquées, ce qu'elle porte) n'était visible nulle part avant
## d'engager la bataille.
func _build_detail() -> Control:
	var campaign: Node = get_node_or_null("/root/Campaign")
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Une fiche se lit : le fond est opaque, pas voilé. À 0,75 l'écran du dessous
	# transparaissait entre les lignes et rendait les chiffres pénibles à suivre.
	var dim := ColorRect.new()
	dim.color = Color(C_BG, 0.97)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 140
	box.offset_right = -140
	box.offset_top = 60
	box.offset_bottom = -60
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "📋  FICHES D'UNITÉ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_GOLD)
	box.add_child(title)

	if not campaign:
		return panel

	var target := OptionButton.new()
	target.custom_minimum_size = Vector2(0, 34)
	for u: Dictionary in campaign.roster:
		target.add_item("%s%s" % [str(u["name"]),
			"  ☠" if not bool(u.get("alive", true)) else ""])
		target.set_item_metadata(target.item_count - 1, str(u["id"]))
		if str(u["id"]) == _detail_unit:
			target.select(target.item_count - 1)
	if target.item_count > 0 and target.selected < 0:
		target.select(0)
	box.add_child(target)

	_detail_status = Label.new()
	_detail_status.add_theme_font_size_override("font_size", 13)
	_detail_status.add_theme_color_override("font_color", C_ACCENT)
	_detail_status.text = _detail_message
	box.add_child(_detail_status)

	var sheet := VBoxContainer.new()
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sheet)

	var show_unit := func(id: String) -> void:
		_detail_unit = id
		for child in sheet.get_children():
			sheet.remove_child(child)
			child.queue_free()
		_fill_detail(sheet, campaign.get_unit(id))

	target.item_selected.connect(func(index: int) -> void:
		show_unit.call(str(target.get_item_metadata(index))))
	if target.item_count > 0:
		show_unit.call(str(target.get_item_metadata(target.selected)))

	var close := _make_button("Fermer", true)
	close.pressed.connect(_toggle_detail)
	box.add_child(close)
	return panel


## Remplit la fiche d'une unité.
func _fill_detail(host: VBoxContainer, unit: Dictionary) -> void:
	if unit.is_empty():
		host.add_child(_note("Unité introuvable."))
		return

	# --- En-tête : figurine, nom, classe, niveau ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)

	var look := TextureRect.new()
	look.custom_minimum_size = Vector2(96, 96)
	look.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Vignette réduite (96 px pour une case de 128) : au plus proche voisin, une
	# réduction jette des pixels au lieu de les moyenner. Le linéaire tient le
	# rôle ici ; le « nearest » est réservé au pion, qui lui est agrandi.
	look.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	look.texture = _unit_front(unit)
	header.add_child(look)

	var who := Label.new()
	who.text = "%s\n%s   Niv. %d%s\nPV %d / %d   MOV %d" % [
		str(unit.get("name", "?")),
		CDB.get_class_name(int(unit.get("class_id", 0))),
		int(unit.get("level", 1)),
		"  (promue)" if bool(unit.get("is_promoted", false)) else "",
		int(unit.get("hp", 0)), int(unit.get("max_hp", 0)), int(unit.get("movement", 0)),
	]
	who.add_theme_font_size_override("font_size", 16)
	who.add_theme_color_override("font_color", C_GOLD)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(who)
	host.add_child(header)

	if not bool(unit.get("alive", true)):
		host.add_child(_note("☠ Tombée au combat — elle ne repartira pas."))

	# --- Statistiques ---
	# Chaque chiffre porte l'explication de ce qu'il fait : c'est ici qu'on
	# compare deux unités avant de choisir qui part, et « Adresse 12 » ne dit
	# rien tant qu'on ignore ce que l'Adresse décide.
	var stat_chips: Array = []
	for key: String in GLOSSARY.ORDER:
		stat_chips.append({
			"text": "%s %d" % [GLOSSARY.label(key), int(unit.get(key, 0))],
			"tooltip": GLOSSARY.tooltip(key),
		})
	host.add_child(_detail_chips("Statistiques", stat_chips))

	# --- Croissances : ce que l'unité gagnera en montant, et qui décide de sa
	# valeur à long terme bien plus que ses chiffres actuels.
	var growths: Dictionary = CDB.get_growths(int(unit.get("class_id", 0)))
	var growth_chips: Array = []
	for key: String in GLOSSARY.ORDER:
		growth_chips.append({
			"text": "%s %d%%" % [GLOSSARY.label(key), int(growths.get(key, 0))],
			"tooltip": "%s\n\nChance, à chaque niveau gagné, de prendre un point.\n\n%s" % [
				GLOSSARY.label(key), GLOSSARY.describe(key)],
		})
	host.add_child(_detail_chips("Croissances", growth_chips))

	# --- Compétences ---
	# Celles qu'elle aura vraiment : la campagne sait lire une fiche écrite à la
	# main aussi bien qu'une unité ordinaire.
	var campaign: Node = get_node_or_null("/root/Campaign")
	var owned: Array = campaign.unit_skills(unit) if campaign else CDB.unlocked_skills(
		int(unit.get("class_id", 0)), int(unit.get("level", 1)))
	var skill_chips: Array = []
	for sk: Variant in owned:
		skill_chips.append({
			"text": "✨ %s" % SKILLS.get_skill_name(str(sk)),
			"tooltip": SKILLS.tooltip(str(sk)),
		})
	if skill_chips.is_empty():
		host.add_child(_detail_line("Compétences", "aucune pour l'instant"))
	else:
		host.add_child(_detail_chips("Compétences", skill_chips))

	# --- Arsenal ---
	# Chaque arme du fourreau porte sa vignette : à quatre lames aux noms
	# proches, l'image dit plus vite que le texte laquelle est en main.
	var held: String = str(unit.get("weapon", ""))
	var arsenal: Array = unit.get("weapons", [])
	if arsenal.is_empty():
		host.add_child(_detail_line("Fourreau", "mains nues"))
	else:
		var rack := VBoxContainer.new()
		var rack_head := Label.new()
		rack_head.text = "Fourreau"
		rack_head.add_theme_font_size_override("font_size", 12)
		rack_head.add_theme_color_override("font_color", C_ACCENT)
		rack.add_child(rack_head)

		var rack_row := HBoxContainer.new()
		rack_row.add_theme_constant_override("separation", 6)
		for w: Variant in arsenal:
			var weapon_id: String = str(w)
			var equipped: bool = weapon_id == held
			rack_row.add_child(ICON.of_weapon(weapon_id))
			var name_label := Label.new()
			name_label.text = "%s%s" % [WEAPONS.label(weapon_id), "  ⟵ en main" if equipped else ""]
			name_label.add_theme_font_size_override("font_size", 14)
			name_label.add_theme_color_override("font_color", C_GOLD if equipped else C_TEXT)
			rack_row.add_child(name_label)
		rack.add_child(rack_row)
		host.add_child(rack)

	# --- Inventaire ---
	# La fiche listait ce que l'unité portait sans permettre d'y toucher : c'est
	# pourtant l'écran où l'on voit ses PV, donc celui où l'on décide de lui faire
	# boire une potion. Chaque objet porte maintenant son bouton.
	host.add_child(_detail_inventory(unit))


## L'inventaire d'une unité, un objet par ligne, chacun avec son bouton.
##
## Une unité tombée ne consomme plus rien : les boutons sont grisés plutôt
## qu'absents, pour que le sac reste lisible.
func _detail_inventory(unit: Dictionary) -> Control:
	var section := VBoxContainer.new()
	var head := Label.new()
	head.text = "Objets  (%d / %d)" % [unit.get("items", []).size(), ITEMS.MAX_ITEMS]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", C_ACCENT)
	section.add_child(head)

	var bag: Array = unit.get("items", [])
	if bag.is_empty():
		var empty := Label.new()
		empty.text = "sac vide — l'intendance en vend"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		section.add_child(empty)
		return section

	var campaign: Node = get_node_or_null("/root/Campaign")
	var unit_id: String = str(unit.get("id", ""))
	var alive: bool = bool(unit.get("alive", true))
	for it: Variant in bag:
		var item_name: String = str(it)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(ICON.of_item(item_name))

		var label := Label.new()
		label.text = ITEMS.label(item_name)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", C_TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var use := _make_button("Utiliser", false)
		use.custom_minimum_size = Vector2(110, 28)
		use.add_theme_font_size_override("font_size", 13)
		use.disabled = not alive or not campaign
		use.pressed.connect(func() -> void:
			var r: Dictionary = campaign.use_item(unit_id, item_name)
			_detail_message = _item_use_message(r, item_name)
			_rebuild_detail())
		row.add_child(use)

		section.add_child(row)
	return section


## Une ligne « intitulé : contenu » de la fiche.
## Une ligne de détail découpée en étiquettes survolables.
##
## [param entries] [{text, tooltip}] — une étiquette par élément.
##
## Un Label ne reçoit pas la souris par défaut (`MOUSE_FILTER_IGNORE`) : sans le
## réglage explicite, aucune de ces bulles n'apparaîtrait jamais.
func _detail_chips(label_text: String, entries: Array) -> Control:
	var row := VBoxContainer.new()
	var head := Label.new()
	head.text = label_text
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", C_ACCENT)
	row.add_child(head)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 2)
	for entry: Dictionary in entries:
		var chip := Label.new()
		chip.text = str(entry.get("text", ""))
		chip.add_theme_font_size_override("font_size", 14)
		chip.add_theme_color_override("font_color", C_TEXT)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.tooltip_text = str(entry.get("tooltip", ""))
		flow.add_child(chip)
	row.add_child(flow)
	return row


func _detail_line(label_text: String, content: String) -> Control:
	var row := VBoxContainer.new()
	var head := Label.new()
	head.text = label_text
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", C_ACCENT)
	row.add_child(head)

	var body := Label.new()
	body.text = content
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", C_TEXT)
	row.add_child(body)
	return row


## La moitié **haute** d'une planche : l'unité de face, celle qu'on voit venir.
##
## Le README des figurines a longtemps annoncé le dos en haut ; c'est faux, et
## cet écran découpait donc la mauvaise moitié — le roster montrait toutes les
## unités de dos.
func _front_of(sheet_path: String) -> Texture2D:
	if sheet_path.is_empty() or not ResourceLoader.exists(sheet_path):
		return null
	var sheet: Texture2D = load(sheet_path) as Texture2D
	if not sheet:
		return null
	var half := AtlasTexture.new()
	half.atlas = sheet
	half.region = Rect2(0, 0, sheet.get_width(), sheet.get_height() / 2.0)
	return half


## La figurine de fiche d'une unité — le sprite du pack d'abord.
##
## Le roster montrait les **anciennes** planches : `unit.sprite` pointe vers la
## planche historique, pas vers les figurines Tiny Swords du pack qui équipent
## les pions au combat. On résout donc d'abord le sprite à jour via [PawnLook]
## (la même clé classe/camp que le pion), et on ne retombe sur la planche
## directe que si le pack ne connaît pas l'unité. Jamais le placeholder Godot.
func _unit_front(unit: Dictionary) -> Texture2D:
	var probe := Stats.new()
	probe.character_class = int(unit.get("class_id", 0))
	var still: Texture2D = PawnLook.still_for_stats(probe, TeamData.Side.PLAYER)
	probe.free()
	if still:
		return still
	return _front_of(str(unit.get("sprite", "")))


func _note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return l
#endregion


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
	row.add_child(ICON.of_weapon(str(weapon["id"])))

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


## Ce qu'un objet consommé vient de faire, dit en une ligne — ou la raison du
## refus. Un seul texte pour les deux écrans qui savent utiliser un objet.
func _item_use_message(result: Dictionary, item_name: String) -> String:
	if not bool(result.get("ok", false)):
		return str(result.get("reason", ""))
	var amount: int = int(result.get("amount", 0))
	var stat: String = str(result.get("stat", ""))
	match str(result.get("effect", "")):
		"heal":
			return "%s bu : +%d PV." % [ITEMS.label(item_name), amount]
		"buff":
			# Le tonique ne peut pas vieillir entre deux chapitres : il attend la
			# bataille, et le joueur doit savoir qu'il n'agira que là.
			return "%s bu : +%d %s pendant %d tour(s), dès l'entrée en bataille." % [
				ITEMS.label(item_name), amount, GLOSSARY.label(stat),
				int(result.get("turns", 0))]
		"boost":
			return "%s : +%d %s définitif." % [
				ITEMS.label(item_name), amount, GLOSSARY.label(stat)]
	return "%s utilisé." % ITEMS.label(item_name)


## Reconstruit la fiche après un objet consommé (PV, statistiques et sac ont bougé).
func _rebuild_detail() -> void:
	if not _detail_panel or not is_instance_valid(_detail_panel):
		return
	var old: Control = _detail_panel
	_detail_panel = _build_detail()
	add_child(_detail_panel)
	old.queue_free()
	_refresh()


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
