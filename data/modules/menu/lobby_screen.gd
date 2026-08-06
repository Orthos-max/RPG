extends Control
## Salon de partie en ligne : créer avec un code, ou rejoindre en le saisissant.
##
## Pas de matchmaking : l'hôte annonce un code de 7 caractères, l'invité le tape.
## L'écran ne fait que piloter [Network] et refléter son état.

signal battle_requested(scene_path: String)
signal back_requested()

const C_BG := Color("#141026")
const C_ACCENT := Color("#e94560")
const C_GOLD := Color("#f5c842")
const C_TEXT := Color("#eeeeee")
const C_BUTTON := Color("#0f3460")

const MAPS: Array[Dictionary] = [
	{"name": "Marches d'Ylisse (procédurale)", "path": "res://assets/maps/level/map_level.tscn"},
	{"name": "Poste avancé (arène sculptée)", "path": "res://assets/maps/level/test_level.tscn"},
]

## true : cet écran héberge — false : il rejoint
var hosting: bool = true

var _status: Label
var _code_label: Label
var _code_input: LineEdit
var _players_label: Label
var _map_picker: OptionButton
var _ciel_toggle: CheckBox
var _start_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

	var net: Node = _net()
	if net:
		net.lobby_updated.connect(_refresh)
		net.connection_failed.connect(_on_failed)
		net.joined.connect(_on_joined)
		net.battle_started.connect(_on_battle_started)

	if hosting:
		_start_hosting()


func _exit_tree() -> void:
	var net: Node = _net()
	if not net:
		return
	for sig in ["lobby_updated", "connection_failed", "joined", "battle_started"]:
		for connection in net.get_signal_connection_list(sig):
			if connection["callable"].get_object() == self:
				net.disconnect(sig, connection["callable"])


#region Construction
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -280
	box.offset_right = 280
	box.offset_top = -200
	box.offset_bottom = 220
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "🌐  CRÉER UNE PARTIE" if hosting else "🔑  REJOINDRE UNE PARTIE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", C_GOLD)
	box.add_child(title)

	if hosting:
		_code_label = Label.new()
		_code_label.text = "…"
		_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_code_label.add_theme_font_size_override("font_size", 42)
		_code_label.add_theme_color_override("font_color", C_ACCENT)
		box.add_child(_code_label)

		var hint := Label.new()
		hint.text = "Transmets ce code à ton adversaire (même réseau local)."
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		box.add_child(hint)

		var renew := _make_button("🔄  Générer un nouveau code", false)
		renew.tooltip_text = "Ferme la partie en cours et en rouvre une avec un code neuf."
		renew.pressed.connect(_regenerate_code)
		box.add_child(renew)

		_map_picker = OptionButton.new()
		_map_picker.custom_minimum_size = Vector2(0, 36)
		for entry: Dictionary in MAPS:
			_map_picker.add_item(str(entry["name"]))
			_map_picker.set_item_metadata(_map_picker.item_count - 1, str(entry["path"]))
		_map_picker.select(0)
		box.add_child(_map_picker)

		# M5 — trois camps : l'hôte et son invité, plus Ciel qui tient le camp
		# rouge. L'armée adverse de la carte est scindée pour armer l'invité.
		_ciel_toggle = CheckBox.new()
		_ciel_toggle.text = "⚡  Inviter Ciel comme troisième camp"
		_ciel_toggle.tooltip_text = "L'armée adverse est partagée : l'invité en prend la moitié, Ciel garde le reste."
		_ciel_toggle.add_theme_font_size_override("font_size", 15)
		_ciel_toggle.add_theme_color_override("font_color", C_TEXT)
		_ciel_toggle.toggled.connect(_on_ciel_toggled)
		box.add_child(_ciel_toggle)
	else:
		_code_input = LineEdit.new()
		_code_input.placeholder_text = "Code à 7 caractères"
		_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_code_input.max_length = 7
		_code_input.custom_minimum_size = Vector2(0, 46)
		_code_input.add_theme_font_size_override("font_size", 26)
		_code_input.text_submitted.connect(func(_t: String) -> void: _try_join())
		box.add_child(_code_input)

		var join := _make_button("Rejoindre", true)
		join.pressed.connect(_try_join)
		box.add_child(join)

	_players_label = Label.new()
	_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_players_label.add_theme_font_size_override("font_size", 15)
	_players_label.add_theme_color_override("font_color", C_TEXT)
	box.add_child(_players_label)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(_status)

	if hosting:
		_start_button = _make_button("⚔️  Lancer la bataille", true)
		_start_button.disabled = true
		_start_button.pressed.connect(_on_start)
		box.add_child(_start_button)

	var back := _make_button("← Retour", false)
	back.pressed.connect(func() -> void:
		var net: Node = _net()
		if net:
			net.leave()
		back_requested.emit())
	box.add_child(back)

	_refresh()
#endregion


#region Actions
func _start_hosting() -> void:
	var net: Node = _net()
	if not net:
		return
	var selected_map: String = str(MAPS[0]["path"])
	if _map_picker and _map_picker.selected >= 0:
		selected_map = str(_map_picker.get_item_metadata(_map_picker.selected))

	var result: Dictionary = net.host_game(selected_map)
	if not bool(result["ok"]):
		_status.text = "Impossible d'héberger : %s" % str(result["reason"])
		return
	_code_label.text = str(result["code"])
	_status.text = "En attente d'un joueur… (adresse %s, port %d)" % [
		str(result["ip"]), net.PORT
	]
	_refresh()


## Rouvre le salon avec un code d'allure neuve.
##
## Le code est l'adresse de cette machine écrite en sept caractères : le bouton
## rebat les cartes du salon (un invité déjà là est déconnecté) mais ne révoque
## pas l'ancien code, et le statut le dit sans détour.
func _regenerate_code() -> void:
	var net: Node = _net()
	if not net:
		return

	var selected_map: String = str(MAPS[0]["path"])
	if _map_picker and _map_picker.selected >= 0:
		selected_map = str(_map_picker.get_item_metadata(_map_picker.selected))

	var result: Dictionary = net.renew_code(selected_map)
	if not bool(result["ok"]):
		_status.text = "Impossible de rouvrir la partie : %s" % str(result["reason"])
		return

	_code_label.text = str(result["code"])
	_status.text = "Nouveau code : %s — le salon est reparti à zéro.\n" % str(result["code"]) \
		+ "L'ancien code mène toujours à cette machine : il n'est pas révoqué."
	_refresh()


## L'hôte invite (ou renvoie) Ciel dans la partie.
func _on_ciel_toggled(pressed: bool) -> void:
	var net: Node = _net()
	if net:
		net.set_three_way(pressed)
	_refresh()


func _try_join() -> void:
	var net: Node = _net()
	if not net or not _code_input:
		return
	_status.text = "Connexion…"
	var result: Dictionary = net.join_game(_code_input.text)
	if not bool(result["ok"]):
		_status.text = "Échec : %s" % str(result["reason"])
		return
	_status.text = "Connexion vers %s…" % str(result["ip"])


func _on_start() -> void:
	var net: Node = _net()
	if not net:
		return
	var selected_map: String = str(MAPS[0]["path"])
	if _map_picker and _map_picker.selected >= 0:
		selected_map = str(_map_picker.get_item_metadata(_map_picker.selected))
	net.start_battle(selected_map)


func _on_joined() -> void:
	_status.text = "Connecté ! En attente du lancement par l'hôte…"
	_refresh()


func _on_failed(reason: String) -> void:
	_status.text = "Connexion perdue : %s" % reason
	_refresh()


func _on_battle_started(map_path: String) -> void:
	battle_requested.emit(map_path)


func _refresh() -> void:
	var net: Node = _net()
	if not net or not _players_label:
		return
	var humans: int = maxi(1, net.players.size())
	if bool(net.three_way):
		_players_label.text = "Joueurs connectés : %d / 2  —  + Ciel (3 camps)" % humans
	else:
		_players_label.text = "Joueurs connectés : %d / 2" % humans
	if _start_button:
		_start_button.disabled = net.players.size() < 2
#endregion


#region Helpers
func _net() -> Node:
	return get_node_or_null("/root/Network")


func _make_button(text: String, accent: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 44)
	btn.add_theme_font_size_override("font_size", 17)
	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if accent else C_BUTTON
	style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", C_TEXT)
	return btn
#endregion
