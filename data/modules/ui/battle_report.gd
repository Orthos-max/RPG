class_name BattleReport
extends CanvasLayer
## Bilan détaillé d'une bataille, unité par unité — le tableau qu'ouvre le bouton
## « Détails de la bataille » de l'écran de fin de chapitre.
##
## L'écran de fin donnait des totaux d'armée ([BattleStats]) : tant de dégâts
## infligés, tant d'ennemis vaincus. Il ne disait pas [i]par qui[/i]. Or c'est la
## seule question qui intéresse un joueur entre deux chapitres — qui porte
## l'armée, qui encaisse, qui n'a rien fait de la bataille — et c'est celle qui
## décide du déploiement suivant.
##
## Rien de neuf n'est compté en cours de bataille : [BattleRecorder] note déjà
## chaque assaut, chaque soin et chaque chute avec les noms des deux parties. Ce
## script relit ce journal après coup, comme [BattleStats] le fait pour les
## totaux — aucun compteur à tenir à jour dans le service de combat, donc aucun
## compteur à oublier de remettre à zéro.
##
## [b]L'agrégation est une fonction pure.[/b] [method aggregate] prend un journal
## et rend un tableau de lignes, sans le moindre nœud — c'est ce qui la rend
## vérifiable en `--headless`, là où le panneau lui-même n'a pas lieu d'être
## ([method available]). Même partage des rôles que [BattleHistory].

const ClassDataClass = preload("res://data/models/world/stats/class_data.gd")
const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

## Camps, tels que [BattleRecorder] les écrit dans les morts.
const TEAM_PLAYER: String = "player"
const TEAM_OPPONENT: String = "opponent"
const TEAM_GUEST: String = "guest"

## Classe d'une unité que le roster de bataille ne nomme pas (un ennemi tombé
## avant qu'on ait relevé sa fiche, un replay relu sans la scène qui va avec).
const UNKNOWN_CLASS: String = "—"

## Au-dessus de l'écran de fin (couche 0), sous le fondu (100).
const LAYER: int = 20

## La touche qui referme le tableau.
const CLOSE_KEY: Key = KEY_ESCAPE

const PANEL_SIZE := Vector2(880, 460)

const C_BACKDROP := Color(0.02, 0.02, 0.05, 0.75)
const C_PANEL := Color(0.05, 0.04, 0.10, 0.97)
const C_GOLD := Color("#f5c842")
const C_TEXT := Color(1, 1, 1, 0.85)
const C_DIM := Color(1, 1, 1, 0.45)
const C_HEAL := Color(0.55, 0.9, 0.6)
const C_FALLEN := Color("#e94560")

## Lignes à afficher, telles que [method aggregate] les rend.
##
## À renseigner avant l'entrée du nœud dans l'arbre : c'est du `_ready` que part
## le montage du tableau.
var entries: Array = []

var _root: Control = null
var _panel: PanelContainer = null


## Y a-t-il un écran où afficher le bilan ?
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


#region Agrégation (pure)
## Ligne vierge d'une unité — sert de gabarit : toutes les clés existent toujours.
static func blank(unit_name: String) -> Dictionary:
	return {
		"name": unit_name,
		"team": "",
		"class_id": -1,
		"class_name": UNKNOWN_CLASS,
		"damage_dealt": 0,
		"damage_taken": 0,
		"healing_done": 0,
		"healing_received": 0,
		"kills": 0,
		"deaths": 0,
		"attacks_made": 0,
		"attacks_taken": 0,
		"hits": 0,
		"misses": 0,
		"crits": 0,
		"alive": true,
	}


## Relit un journal de bataille et en rend une ligne par unité.
##
## [param events] Les événements de [BattleRecorder] — ceux de la partie en cours
## ou ceux d'un replay relu depuis son JSON : ils sont lus par leur `kind_name`
## et non par l'énumération [enum BattleRecorder.Kind], donc les deux se résument
## exactement pareil.
##
## [param roster] Qui a pris part à la bataille : `nom affiché` →
## `{"team": …, "class_id": …}`, tel que [method ChapterRunner.battle_roster] le
## rend. Le journal ne connaît que des noms : sans ce roster, on ne saurait ni la
## classe d'une unité ni son camp — et une unité qui n'a ni frappé ni été frappée
## n'aurait aucune ligne, alors qu'un bilan doit aussi montrer celles qui n'ont
## rien fait. Une unité que le journal nomme sans qu'elle y figure garde quand
## même sa ligne : son camp se déduit de sa mort, ou à défaut la met chez
## l'adversaire — même convention que [method BattleStats.from_events].
##
## Le tri : les alliés d'abord, les invités ensuite, l'adversaire en dernier ;
## dans chaque camp, du plus au moins de dégâts infligés.
static func aggregate(events: Array, roster: Dictionary = {}) -> Array:
	var by_name: Dictionary = {}
	for unit_name: Variant in roster:
		_entry(by_name, str(unit_name))

	# Dernier assaillant à avoir touché chaque unité. Le journal note un `killer`,
	# mais il peut être vide (mort constatée hors échange, replay d'une version
	# antérieure) : le coup qui précède la chute désigne alors le tueur.
	var last_hitter: Dictionary = {}

	for event: Dictionary in events:
		match str(event.get("kind_name", "")):
			"attack":
				_apply_attack(by_name, last_hitter, event)
			"heal":
				_apply_heal(by_name, event)
			"death":
				_apply_death(by_name, last_hitter, event)
			"move":
				# Une unité qui n'a fait que bouger a droit à sa ligne : « elle n'a
				# rien fait de la bataille » est une réponse, pas une absence.
				_entry(by_name, str(event.get("pawn", "")))

	var out: Array = []
	for unit_name: String in by_name:
		var line: Dictionary = by_name[unit_name]
		var profile: Dictionary = roster.get(unit_name, {})
		# Le roster fait foi sur le camp : il a vu les pions dans leur camp, là où
		# le journal ne l'écrit que dans les morts.
		var team: String = str(profile.get("team", ""))
		if team.is_empty():
			team = str(line["team"])
		line["team"] = team if not team.is_empty() else TEAM_OPPONENT
		if profile.has("class_id"):
			line["class_id"] = int(profile["class_id"])
			line["class_name"] = ClassDataClass.get_class_name(int(profile["class_id"]))
		line["alive"] = int(line["deaths"]) == 0
		out.append(line)

	out.sort_custom(compare)
	return out


## Un assaut : ce qu'il coûte au défenseur, ce qu'il rapporte à l'assaillant.
static func _apply_attack(by_name: Dictionary, last_hitter: Dictionary,
		event: Dictionary) -> void:
	var attacker: String = str(event.get("attacker", ""))
	var defender: String = str(event.get("defender", ""))
	var hit: bool = bool(event.get("hit", false))
	# Un coup manqué ne fait pas de dégâts — le journal en note quand même,
	# puisqu'il écrit ce que l'échange aurait donné.
	var damage: int = int(event.get("damage", 0)) if hit else 0

	var a: Dictionary = _entry(by_name, attacker)
	if not a.is_empty():
		a["attacks_made"] = int(a["attacks_made"]) + 1
		a["damage_dealt"] = int(a["damage_dealt"]) + damage
		if hit:
			a["hits"] = int(a["hits"]) + 1
			if bool(event.get("crit", false)):
				a["crits"] = int(a["crits"]) + 1
		else:
			a["misses"] = int(a["misses"]) + 1

	var d: Dictionary = _entry(by_name, defender)
	if not d.is_empty():
		d["attacks_taken"] = int(d["attacks_taken"]) + 1
		d["damage_taken"] = int(d["damage_taken"]) + damage

	if hit and not defender.is_empty() and not attacker.is_empty():
		last_hitter[defender] = attacker


## Un soin : il compte des deux côtés du bâton.
static func _apply_heal(by_name: Dictionary, event: Dictionary) -> void:
	var amount: int = int(event.get("amount", 0))
	var h: Dictionary = _entry(by_name, str(event.get("healer", "")))
	if not h.is_empty():
		h["healing_done"] = int(h["healing_done"]) + amount
	var t: Dictionary = _entry(by_name, str(event.get("target", "")))
	if not t.is_empty():
		t["healing_received"] = int(t["healing_received"]) + amount


## Une chute : elle marque le tombé, et crédite qui l'a mis à terre.
static func _apply_death(by_name: Dictionary, last_hitter: Dictionary,
		event: Dictionary) -> void:
	var pawn: String = str(event.get("pawn", ""))
	var fallen: Dictionary = _entry(by_name, pawn)
	if not fallen.is_empty():
		fallen["deaths"] = 1
		var team: String = str(event.get("team", ""))
		if not team.is_empty():
			fallen["team"] = team

	var killer: String = str(event.get("killer", ""))
	if killer.is_empty():
		killer = str(last_hitter.get(pawn, ""))
	# Une unité ne se tue pas elle-même : si le dernier coup vient d'elle (un
	# poison, une riposte mal lue), le kill n'appartient à personne.
	if killer.is_empty() or killer == pawn:
		return
	var k: Dictionary = _entry(by_name, killer)
	if not k.is_empty():
		k["kills"] = int(k["kills"]) + 1


## La ligne d'une unité, créée au besoin — `{}` pour un nom vide.
##
## Le dictionnaire rendu est bien celui qui est rangé dans [param by_name] (et
## non une copie) : les compteurs s'incrémentent dessus directement.
static func _entry(by_name: Dictionary, unit_name: String) -> Dictionary:
	if unit_name.is_empty():
		return {}
	if not by_name.has(unit_name):
		by_name[unit_name] = blank(unit_name)
	return by_name[unit_name]


## Ordre d'affichage de deux lignes : camp, puis dégâts, puis kills, puis nom.
static func compare(a: Dictionary, b: Dictionary) -> bool:
	var ra: int = team_rank(str(a.get("team", "")))
	var rb: int = team_rank(str(b.get("team", "")))
	if ra != rb:
		return ra < rb
	var da: int = int(a.get("damage_dealt", 0))
	var db: int = int(b.get("damage_dealt", 0))
	if da != db:
		return da > db
	var ka: int = int(a.get("kills", 0))
	var kb: int = int(b.get("kills", 0))
	if ka != kb:
		return ka > kb
	return str(a.get("name", "")) < str(b.get("name", ""))


## Rang d'un camp dans le tableau : le joueur lit son armée en premier.
static func team_rank(team: String) -> int:
	match team:
		TEAM_PLAYER: return 0
		TEAM_GUEST: return 1
	return 2
#endregion


#region Libellés (purs)
## En-têtes du tableau, dans l'ordre des colonnes.
static func headers() -> Array:
	return ["Unité", "Classe", "Dégâts infligés", "Dégâts subis", "Soins", "Kills", "Statut"]


## Une ligne du tableau, prête à afficher — même longueur que [method headers].
static func row(entry: Dictionary) -> Array:
	return [
		str(entry.get("name", "?")),
		str(entry.get("class_name", UNKNOWN_CLASS)),
		str(int(entry.get("damage_dealt", 0))),
		str(int(entry.get("damage_taken", 0))),
		heal_cell(entry),
		str(int(entry.get("kills", 0))),
		status_label(entry),
	]


## La colonne « Soins » : ce que l'unité a prodigué, et ce qu'elle a reçu.
##
## Les deux dans la même case : une colonne de plus pour les soins reçus aurait
## été vide pour presque toute l'armée, et le chiffre n'a de sens qu'à côté de
## l'autre — un soigneur qui a reçu autant qu'il a donné n'a rien tenu.
static func heal_cell(entry: Dictionary) -> String:
	var done: int = int(entry.get("healing_done", 0))
	var received: int = int(entry.get("healing_received", 0))
	if received <= 0:
		return str(done)
	return "%d (+%d reçus)" % [done, received]


## « En vie » ou « Tombé » — la seule colonne qui ne soit pas un chiffre.
static func status_label(entry: Dictionary) -> String:
	return "En vie" if bool(entry.get("alive", true)) else "Tombé"


## Le détail d'une unité, pour l'infobulle de sa ligne.
##
## Les coups portés, touchés et manqués n'ont pas leur colonne — sept en font
## déjà un tableau large — mais ils répondent à « pourquoi si peu de dégâts ? ».
static func tooltip(entry: Dictionary) -> String:
	return "%s — %s (%s)\nAttaques portées : %d (%d touchées, %d manquées, %d critiques)\nAttaques subies : %d\nSoins prodigués : %d — soins reçus : %d" % [
		str(entry.get("name", "?")), str(entry.get("class_name", UNKNOWN_CLASS)),
		team_label(str(entry.get("team", ""))),
		int(entry.get("attacks_made", 0)), int(entry.get("hits", 0)),
		int(entry.get("misses", 0)), int(entry.get("crits", 0)),
		int(entry.get("attacks_taken", 0)),
		int(entry.get("healing_done", 0)), int(entry.get("healing_received", 0)),
	]


## Nom lisible d'un camp — même traduction que [method BattleHistory.team_label].
static func team_label(team: String) -> String:
	match team:
		TEAM_PLAYER: return TeamDataClass.side_name(TeamDataClass.Side.PLAYER)
		TEAM_OPPONENT: return TeamDataClass.side_name(TeamDataClass.Side.OPPONENT)
		TEAM_GUEST: return TeamDataClass.side_name(TeamDataClass.Side.GUEST)
	return "Inconnu"


## Couleur du nom d'une unité : celle de son camp, éteinte si elle est tombée.
static func tint(entry: Dictionary) -> Color:
	var color: Color = TeamDataClass.side_color(_side_of(str(entry.get("team", ""))))
	if not bool(entry.get("alive", true)):
		return color.lerp(C_FALLEN, 0.5) * Color(1, 1, 1, 0.65)
	return color


static func _side_of(team: String) -> int:
	match team:
		TEAM_PLAYER: return TeamDataClass.Side.PLAYER
		TEAM_GUEST: return TeamDataClass.Side.GUEST
	return TeamDataClass.Side.OPPONENT
#endregion


#region Montage
func _ready() -> void:
	layer = LAYER
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "ReportRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Un voile sombre : le tableau se lit par-dessus l'écran de fin, et sans ce
	# fond le titre du chapitre transparaîtrait entre les colonnes.
	var backdrop := ColorRect.new()
	backdrop.color = C_BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.name = "ReportPanel"
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)

	var title := Label.new()
	title.text = "📊  Bilan de la bataille"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_GOLD)
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = headers().size()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	_fill(grid)

	var close := Button.new()
	close.text = "Fermer (Échap)"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(200, 40)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_panel)
	column.add_child(close)


## Remplit le tableau : l'en-tête, puis une ligne par unité.
func _fill(grid: GridContainer) -> void:
	for header: String in headers():
		grid.add_child(_cell(header, C_GOLD, 14, true))

	if entries.is_empty():
		# Une bataille sans un coup échangé : le dire, plutôt qu'un tableau vide
		# qu'on prendrait pour un bug.
		grid.add_child(_cell("Aucun fait d'armes à rapporter.", C_DIM, 14))
		for _i: int in headers().size() - 1:
			grid.add_child(_cell("", C_DIM, 14))
		return

	for entry: Dictionary in entries:
		var cells: Array = row(entry)
		var detail: String = tooltip(entry)
		var alive: bool = bool(entry.get("alive", true))
		for i: int in cells.size():
			var color: Color = tint(entry) if i == 0 else (C_TEXT if alive else C_DIM)
			if i == 4 and int(entry.get("healing_done", 0)) > 0:
				color = C_HEAL
			if i == 6 and not alive:
				color = C_FALLEN
			var cell: Label = _cell(str(cells[i]), color, 14, i == 0)
			cell.tooltip_text = detail
			grid.add_child(cell)


## Une case du tableau. La première colonne s'aligne à gauche (des noms), les
## autres à droite (des chiffres qu'on compare d'un coup d'œil vertical).
func _cell(text: String, color: Color, size: int, leading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if leading \
		else HORIZONTAL_ALIGNMENT_RIGHT
	label.custom_minimum_size = Vector2(150 if leading else 110, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label
#endregion


#region Vie du panneau
func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == CLOSE_KEY:
		close_panel()
		get_viewport().set_input_as_handled()


## Le tableau est-il à l'écran ?
func is_open() -> bool:
	return _root != null and _root.visible


## Ouvre ou referme le tableau. Le nœud reste : le bouton de l'écran de fin le
## rappelle sans avoir à le reconstruire.
func toggle() -> void:
	if _root:
		_root.visible = not _root.visible


func close_panel() -> void:
	if _root:
		_root.visible = false


## Nombre d'unités affichées.
func unit_count() -> int:
	return entries.size()
#endregion
