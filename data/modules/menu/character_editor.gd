extends Control
## Éditeur de personnages — créer une recrue et l'envoyer à l'armée.
##
## La règle et la validation vivent dans [UnitDocument], le rangement dans
## [UnitLibrary] : cet écran ne fait que les relier à des boutons. C'est le même
## partage que l'éditeur de cartes, et il permet d'éprouver tout ce qui compte
## sans monter d'interface.
##
## Le panneau de droite affiche les valeurs **dérivées** (précision, esquive,
## critique, vitesse d'attaque) recalculées à chaque modification : ce sont
## elles qui décident d'un combat, et les lire pendant qu'on règle les stats
## évite de créer un personnage sur le papier avant de découvrir en jeu qu'il
## est increvable ou inoffensif.

signal back_requested()

const CDB = preload("res://data/models/world/stats/class_data.gd")
const WEAPONS = preload("res://data/models/world/stats/weapon_db.gd")
const ITEMS = preload("res://data/models/world/stats/item_db.gd")
const StatsRes = preload("res://data/models/world/stats/stats_res.gd")
const CharStats = preload("res://data/modules/stats/stats.gd")

const C_BG := Color("#141026")
const C_PANEL := Color("#16213e")
const C_ACCENT := Color("#e94560")
const C_GOLD := Color("#f5c842")
const C_TEXT := Color("#eeeeee")
const C_BUTTON := Color("#0f3460")

var doc: UnitDocument = null

var _name_edit: LineEdit
var _class_picker: OptionButton
var _sprite_picker: OptionButton
var _rows: VBoxContainer
var _preview: Label
var _status: Label
var _library: VBoxContainer
## Fiche dont la suppression attend confirmation
var _pending_delete: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not doc:
		doc = UnitDocument.from_class(CDB.Id.LORD)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 36)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = "🧑  ÉDITEUR DE PERSONNAGES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", C_GOLD)
	column.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", C_ACCENT)
	_status.text = "Règle ta recrue, puis enregistre-la."
	column.add_child(_status)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	column.add_child(columns)

	# --- Colonne de gauche : la fiche ---
	var form_scroll := ScrollContainer.new()
	form_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(form_scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	form_scroll.add_child(_rows)

	# --- Colonne de droite : aperçu et bibliothèque ---
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(380, 0)
	side.add_theme_constant_override("separation", 8)
	columns.add_child(side)

	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.add_theme_font_size_override("font_size", 14)
	_preview.add_theme_color_override("font_color", C_TEXT)
	side.add_child(_preview)

	var lib_title := Label.new()
	lib_title.text = "📚  Personnages enregistrés"
	lib_title.add_theme_font_size_override("font_size", 15)
	lib_title.add_theme_color_override("font_color", C_GOLD)
	side.add_child(lib_title)

	var lib_scroll := ScrollContainer.new()
	lib_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lib_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(lib_scroll)

	_library = VBoxContainer.new()
	_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library.add_theme_constant_override("separation", 4)
	lib_scroll.add_child(_library)

	# --- Barre du bas ---
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	column.add_child(bar)

	for entry: Array in [
		["← Retour", func() -> void: back_requested.emit(), false],
		["🆕  Nouvelle fiche", _on_new, false],
		["➕  Ajouter à l'armée", _on_enlist, false],
		["💾  Enregistrer", _on_save, true],
	]:
		var btn := _make_button(str(entry[0]), bool(entry[2]))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(120, 44)
		btn.clip_text = true
		btn.pressed.connect(entry[1] as Callable)
		bar.add_child(btn)

	_rebuild_form()
	_refresh_library()


#region Formulaire
func _rebuild_form() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	_name_edit = LineEdit.new()
	_name_edit.text = doc.name
	_name_edit.max_length = UnitDocument.MAX_NAME
	_name_edit.custom_minimum_size = Vector2(0, 34)
	_name_edit.text_changed.connect(func(t: String) -> void:
		doc.name = t
		_refresh_preview())
	_rows.add_child(_labelled("Nom", _name_edit))

	_class_picker = OptionButton.new()
	_class_picker.custom_minimum_size = Vector2(0, 34)
	for id: int in CDB.Id.values():
		_class_picker.add_item("%s%s" % [
			CDB.get_class_name(id), "  (promue)" if CDB.is_promoted(id) else ""])
		_class_picker.set_item_metadata(_class_picker.item_count - 1, id)
		if id == doc.class_id:
			_class_picker.select(_class_picker.item_count - 1)
	_class_picker.item_selected.connect(_on_class_changed)
	_rows.add_child(_labelled("Classe", _class_picker))

	_rows.add_child(_labelled("Figurine", _build_sprite_picker()))

	_rows.add_child(_number("Niveau", doc.level, UnitDocument.MIN_LEVEL, UnitDocument.MAX_LEVEL,
		func(v: int) -> void: doc.level = v))
	_rows.add_child(_number("PV max", doc.max_hp, UnitDocument.MIN_HP, UnitDocument.MAX_HP,
		func(v: int) -> void: doc.max_hp = v))
	_rows.add_child(_number("Mouvement", doc.movement, 1, UnitDocument.MAX_MOVEMENT,
		func(v: int) -> void: doc.movement = v))

	var stat_labels: Dictionary = {
		"str": "Force", "mag": "Magie", "skl": "Adresse", "spd": "Vitesse",
		"lck": "Chance", "def": "Défense", "res": "Résistance",
	}
	for key: String in UnitDocument.STATS:
		var stat_key: String = key
		_rows.add_child(_number(str(stat_labels[key]), int(doc.stats.get(key, 0)),
			UnitDocument.MIN_STAT, UnitDocument.MAX_STAT,
			func(v: int) -> void: doc.stats[stat_key] = v))

	# --- Armes autorisées par la classe ---
	var weapon_title := Label.new()
	weapon_title.text = "Armes  (la première est en main, %d max)" % WEAPONS.MAX_WEAPONS
	weapon_title.add_theme_font_size_override("font_size", 14)
	weapon_title.add_theme_color_override("font_color", C_GOLD)
	_rows.add_child(weapon_title)

	var allowed: Array = CDB.get_weapons(doc.class_id)
	for id: String in WEAPONS.shop_stock():
		if not WEAPONS.weapon_type(id) in allowed:
			continue
		var weapon_id: String = id
		var check := CheckBox.new()
		check.text = "%s — %s" % [WEAPONS.label(id), WEAPONS.describe(id)]
		check.button_pressed = id in doc.weapons
		check.add_theme_font_size_override("font_size", 13)
		check.add_theme_color_override("font_color", C_TEXT)
		check.toggled.connect(func(on: bool) -> void: _on_weapon_toggled(weapon_id, on))
		_rows.add_child(check)

	# --- Consommables de départ ---
	var item_title := Label.new()
	item_title.text = "Objets de départ  (%d max)" % ITEMS.MAX_ITEMS
	item_title.add_theme_font_size_override("font_size", 14)
	item_title.add_theme_color_override("font_color", C_GOLD)
	_rows.add_child(item_title)

	for item_name: String in ITEMS.shop_stock():
		if ITEMS.is_boost(item_name):
			continue  # Les gains permanents s'achètent, ils ne se distribuent pas.
		var key: String = item_name
		var check := CheckBox.new()
		check.text = ITEMS.label(item_name)
		check.button_pressed = item_name in doc.items
		check.add_theme_font_size_override("font_size", 13)
		check.add_theme_color_override("font_color", C_TEXT)
		check.toggled.connect(func(on: bool) -> void: _on_item_toggled(key, on))
		_rows.add_child(check)

	_refresh_preview()


## Une ligne « intitulé + champ ».
## Choix de la figurine, avec un aperçu de ce qu'on choisit.
##
## Une liste de noms ne dirait rien : « chemist » ou « mage » ne se devinent pas.
## L'aperçu montre la rangée du bas de la planche — l'unité **de face**, celle
## qu'on voit le plus souvent en jeu.
func _build_sprite_picker() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(48, 48)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var show_look := func(path: String) -> void:
		var sheet: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
		if not sheet:
			preview.texture = null
			return
		# La planche fait deux rangées : dos en haut, face en bas. On découpe la
		# seconde plutôt que d'afficher les deux l'une au-dessus de l'autre.
		var half := AtlasTexture.new()
		half.atlas = sheet
		half.region = Rect2(0, sheet.get_height() / 2.0,
			sheet.get_width(), sheet.get_height() / 2.0)
		preview.texture = half

	_sprite_picker = OptionButton.new()
	_sprite_picker.custom_minimum_size = Vector2(0, 34)
	_sprite_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Premier choix : « celle de la classe ». Sans lui, une fiche ne pourrait plus
	# suivre sa classe si on la change après coup.
	_sprite_picker.add_item("Celle de la classe (%s)" %
		CDB.get_sprite(doc.class_id).get_file().trim_prefix("chr_pawn_").trim_suffix(".png"))
	_sprite_picker.set_item_metadata(0, "")

	for entry: Dictionary in UnitDocument.available_sprites():
		_sprite_picker.add_item(str(entry["label"]))
		_sprite_picker.set_item_metadata(_sprite_picker.item_count - 1, str(entry["path"]))
		if str(entry["path"]) == doc.sprite:
			_sprite_picker.select(_sprite_picker.item_count - 1)

	_sprite_picker.item_selected.connect(func(index: int) -> void:
		doc.sprite = str(_sprite_picker.get_item_metadata(index))
		show_look.call(doc.effective_sprite())
		_refresh_preview())

	row.add_child(_sprite_picker)
	row.add_child(preview)
	show_look.call(doc.effective_sprite())
	return row


func _labelled(text: String, field: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(130, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", C_TEXT)
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row


## Une ligne numérique bornée. La borne est posée par le champ lui-même : on ne
## peut pas taper 300 en force, donc la validation n'a jamais à le reprocher.
func _number(text: String, value: int, low: int, high: int, apply: Callable) -> Control:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = value
	spin.custom_minimum_size = Vector2(0, 32)
	spin.value_changed.connect(func(v: float) -> void:
		apply.call(int(v))
		_refresh_preview())
	return _labelled(text, spin)
#endregion


#region Réactions
func _on_class_changed(index: int) -> void:
	doc.class_id = int(_class_picker.get_item_metadata(index))
	# Changer de classe rebat les bases : c'est ce qu'on attend en la choisissant,
	# et ça évite un archer avec les statistiques d'un chevalier.
	doc.apply_class_bases()
	_status.text = "Classe changée : les bases et l'arme suivent."
	_rebuild_form()


func _on_weapon_toggled(weapon_id: String, on: bool) -> void:
	if on:
		if doc.weapons.size() >= WEAPONS.MAX_WEAPONS:
			_status.text = "Pas plus de %d armes." % WEAPONS.MAX_WEAPONS
			_rebuild_form()
			return
		if not weapon_id in doc.weapons:
			doc.weapons.append(weapon_id)
	else:
		doc.weapons.erase(weapon_id)
	_refresh_preview()


func _on_item_toggled(item_name: String, on: bool) -> void:
	if on:
		if doc.items.size() >= ITEMS.MAX_ITEMS:
			_status.text = "Pas plus de %d objets." % ITEMS.MAX_ITEMS
			_rebuild_form()
			return
		doc.items.append(item_name)
	else:
		doc.items.erase(item_name)
	_refresh_preview()


func _on_new() -> void:
	doc = UnitDocument.from_class(CDB.Id.LORD)
	_status.text = "Nouvelle fiche."
	_rebuild_form()


func _on_save() -> void:
	var result: Dictionary = UnitLibrary.save(doc)
	if bool(result["ok"]):
		_status.text = "Enregistré : %s" % ProjectSettings.globalize_path(str(result["path"]))
	else:
		_status.text = "⛔ %s" % str(result["error"])
	_refresh_library()


## Verse le personnage dans l'armée de la campagne en cours.
func _on_enlist() -> void:
	var campaign: Node = get_node_or_null("/root/Campaign")
	if not campaign or campaign.roster.is_empty():
		_status.text = "⛔ Aucune campagne en cours — commence une partie d'abord."
		return

	var errors: Array[String] = doc.validate()
	if not errors.is_empty():
		_status.text = "⛔ %s" % errors[0]
		return

	var result: Dictionary = campaign.enlist_custom(doc)
	_status.text = ("%s rejoint l'armée." % doc.name) if bool(result["ok"]) \
		else "⛔ %s" % str(result.get("reason", ""))
#endregion


#region Aperçu et bibliothèque
## Valeurs dérivées, calculées par le moteur lui-même.
##
## On monte une unité vivante à partir de la fiche plutôt que de recopier les
## formules : c'est la seule façon d'être sûr que l'aperçu dit la même chose que
## le combat.
func _refresh_preview() -> void:
	if not _preview:
		return

	var live: CharStats = CharStats.new()
	var res := StatsRes.new()
	res.override_name = doc.name
	res.character_class = doc.class_id
	res.level = doc.level
	res.hp = doc.max_hp
	res.movement = doc.movement
	res.use_class_growths = doc.growths.is_empty()
	for key: String in UnitDocument.STATS:
		res.set(key, int(doc.stats.get(key, 0)))
	var typed: Array[String] = []
	typed.assign(doc.weapons)
	res.weapons = typed
	res.equipped_weapon = doc.weapons[0] if not doc.weapons.is_empty() else ""
	live.import_stats(res)

	var skills: Array = []
	for id in live.get_skills():
		skills.append(SkillDB.get_skill_name(str(id)))

	var lines: Array[String] = [
		"[ %s ]  %s  Niv. %d" % [doc.name, CDB.get_class_name(doc.class_id), doc.level],
		"PV %d   MOV %d" % [live.max_hp, live.movement],
		"",
		"Arme : %s" % (WEAPONS.label(doc.weapons[0]) if not doc.weapons.is_empty() else "mains nues"),
		"Attaque %d   Précision %d   Critique %d" % [
			live.get_total_attack(), live.get_base_hit(), live.get_crit()],
		"Esquive %d   Vitesse d'attaque %d%s" % [
			live.get_avoid(), live.get_attack_speed(),
			("  (poids −%d)" % live.speed_penalty()) if live.speed_penalty() > 0 else ""],
		"",
		"Compétences : %s" % (", ".join(skills) if not skills.is_empty() else "aucune"),
	]

	var errors: Array[String] = doc.validate()
	if not errors.is_empty():
		lines.append("")
		lines.append("⛔ %s" % errors[0])
	_preview.text = "\n".join(lines)
	_preview.add_theme_color_override("font_color", C_ACCENT if not errors.is_empty() else C_TEXT)
	live.free()


func _refresh_library() -> void:
	for child in _library.get_children():
		_library.remove_child(child)
		child.queue_free()

	var units: Array = UnitLibrary.list_units()
	if units.is_empty():
		var empty := Label.new()
		empty.text = "Aucun personnage enregistré."
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		_library.add_child(empty)
		return

	for entry: Dictionary in units:
		var slug: String = str(entry["slug"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var open := _make_button("%s — %s Niv.%d" % [
			str(entry["name"]), str(entry["class_name"]), int(entry["level"])], false)
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.custom_minimum_size = Vector2(0, 34)
		open.clip_text = true
		open.pressed.connect(func() -> void: _open(slug))
		row.add_child(open)

		var erase := _make_button("✕" if _pending_delete != slug else "?", false)
		erase.custom_minimum_size = Vector2(44, 34)
		erase.pressed.connect(func() -> void: _erase(slug))
		row.add_child(erase)

		_library.add_child(row)


func _open(slug: String) -> void:
	var loaded: UnitDocument = UnitLibrary.load_unit(slug)
	if not loaded:
		_status.text = "⛔ Fiche illisible : %s" % slug
		return
	doc = loaded
	_pending_delete = ""
	_status.text = "%s chargé." % doc.name
	_rebuild_form()
	_refresh_library()


## Deux clics pour supprimer : le premier arme, le second efface.
func _erase(slug: String) -> void:
	if _pending_delete != slug:
		_pending_delete = slug
		_status.text = "Supprimer « %s » ? Clique de nouveau pour confirmer." % slug
		_refresh_library()
		return
	UnitLibrary.delete_unit(slug)
	_pending_delete = ""
	_status.text = "Fiche supprimée."
	_refresh_library()
#endregion


func _make_button(text: String, accent: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 40)
	btn.add_theme_font_size_override("font_size", 15)
	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if accent else C_BUTTON
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", C_TEXT)
	return btn
