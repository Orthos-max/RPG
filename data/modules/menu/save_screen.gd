extends Control
## Écran de sauvegarde et de chargement — quatre emplacements, décrits.
##
## La campagne écrivait déjà toute seule (nouvelle partie, fin de chapitre) et
## « Continuer » relisait cet unique emplacement. Ce qui manquait, c'est de
## pouvoir **choisir** : garder une partie avant un chapitre risqué, en mener
## deux de front, revenir en arrière après une mort permanente.
##
## L'écran ne charge rien pour s'afficher : [method Campaign.slot_info] relit
## l'en-tête des fichiers, sinon décrire les emplacements écraserait la partie
## en cours.

signal slot_loaded()
signal back_requested()

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

const C_BG := Color("#141026")
const C_PANEL := Color("#16213e")
const C_ACCENT := Color("#e94560")
const C_GOLD := Color("#f5c842")
const C_TEXT := Color("#eeeeee")
const C_BUTTON := Color("#0f3460")

## `true` : on écrit dans un emplacement. `false` : on en charge un.
var saving: bool = false

var _rows: VBoxContainer
var _status: Label
## Emplacement dont la suppression attend confirmation (-1 : aucun)
var _pending_delete: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	scroll.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "💾  SAUVEGARDER" if saving else "📂  CHARGER UNE PARTIE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", C_GOLD)
	column.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", C_ACCENT)
	_status.text = "Choisis un emplacement." if saving \
		else "Choisis la partie à reprendre."
	column.add_child(_status)

	column.add_child(_spacer(8))

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	column.add_child(_rows)

	column.add_child(_spacer(12))

	var back := _make_button("← Retour", false)
	back.pressed.connect(func() -> void: back_requested.emit())
	column.add_child(back)

	_refresh()


func _refresh() -> void:
	var campaign: Node = _campaign()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if not campaign:
		return
	for info: Dictionary in campaign.all_slots():
		_rows.add_child(_make_row(info, campaign))


## Une ligne d'emplacement : ce qu'il contient, et ce qu'on peut en faire.
func _make_row(info: Dictionary, campaign: Node) -> Control:
	var slot: int = int(info["slot"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	row.add_child(panel)

	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 14)
	text.add_theme_color_override("font_color", C_TEXT)
	text.text = _describe(info)
	panel.add_child(text)

	# L'emplacement automatique se charge, mais ne s'écrase pas à la main : c'est
	# le filet du jeu, et l'écraser reviendrait à s'en priver sans le vouloir.
	if saving:
		var write := _make_button("Sauvegarder", true)
		write.custom_minimum_size = Vector2(150, 40)
		write.disabled = bool(info["auto"])
		if write.disabled:
			write.tooltip_text = "Emplacement écrit automatiquement par le jeu."
		write.pressed.connect(func() -> void: _write_slot(slot, campaign))
		row.add_child(write)
	else:
		var read := _make_button("Charger", true)
		read.custom_minimum_size = Vector2(150, 40)
		read.disabled = not bool(info["exists"])
		read.pressed.connect(func() -> void: _read_slot(slot, campaign))
		row.add_child(read)

	var erase := _make_button("Supprimer" if _pending_delete != slot else "Confirmer ?", false)
	erase.custom_minimum_size = Vector2(130, 40)
	erase.disabled = not bool(info["exists"])
	erase.pressed.connect(func() -> void: _erase_slot(slot, campaign))
	row.add_child(erase)

	return row


## Description d'un emplacement, telle qu'elle s'affiche.
func _describe(info: Dictionary) -> String:
	var head: String = "Emplacement %d%s" % [
		int(info["slot"]) + 1, "  (automatique)" if bool(info["auto"]) else "",
	]
	if not bool(info["exists"]):
		return "%s\nvide" % head
	return "%s\n%s — %d unité(s)%s, %d or — %s, mort permanente : %s\n%s" % [
		head,
		str(info["chapter_title"]),
		int(info["units"]),
		(" (%d tombée(s))" % int(info["fallen"])) if int(info["fallen"]) > 0 else "",
		int(info["gold"]),
		DIFF.get_level_name(int(info["difficulty"])),
		"oui" if bool(info["permadeath"]) else "non",
		str(info["saved_at"]),
	]


#region Actions
func _write_slot(slot: int, campaign: Node) -> void:
	_pending_delete = -1
	if campaign.save_game(slot):
		_status.text = "Partie sauvegardée dans l'emplacement %d." % (slot + 1)
	else:
		_status.text = "Écriture impossible dans l'emplacement %d." % (slot + 1)
	_refresh()


func _read_slot(slot: int, campaign: Node) -> void:
	_pending_delete = -1
	if not campaign.load_game(slot):
		_status.text = "Emplacement %d illisible." % (slot + 1)
		_refresh()
		return
	_status.text = "Partie chargée."
	slot_loaded.emit()


## Deux clics pour supprimer : le premier arme, le second efface.
func _erase_slot(slot: int, campaign: Node) -> void:
	if _pending_delete != slot:
		_pending_delete = slot
		_status.text = "Supprimer l'emplacement %d ? Clique de nouveau pour confirmer." % (slot + 1)
		_refresh()
		return
	campaign.delete_save(slot)
	_pending_delete = -1
	_status.text = "Emplacement %d supprimé." % (slot + 1)
	_refresh()
#endregion


#region Helpers
func _campaign() -> Node:
	return get_node_or_null("/root/Campaign")


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


func _make_button(text: String, accent: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(160, 44)
	btn.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if accent else C_BUTTON
	style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", C_TEXT)
	return btn
#endregion
