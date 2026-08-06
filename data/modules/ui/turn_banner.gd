extends CanvasLayer
## Bandeau indiquant quel camp joue — indispensable en réseau, utile ailleurs.
##
## Lit l'état du niveau chaque frame plutôt que d'écouter des signaux : la boucle
## de tour n'en émet pas, et le coût est négligeable devant le rendu.

const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

var level: TacticsLevel = null

var _label: Label
var _last_text: String = ""


func _ready() -> void:
	layer = 10
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -190
	panel.offset_right = 190
	panel.offset_top = 12
	panel.offset_bottom = 48

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.15, 0.85)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(_label)


func _process(_delta: float) -> void:
	if not level or not is_instance_valid(level) or not level.participant:
		return

	var side: int = -1
	if level.player and level.participant.can_act(level.player):
		side = TeamDataClass.Side.PLAYER
	elif level.guest and level.participant.can_act(level.guest):
		side = TeamDataClass.Side.GUEST
	elif level.opponent and level.participant.can_act(level.opponent):
		side = TeamDataClass.Side.OPPONENT
	if side == -1:
		return

	var session: Node = get_node_or_null("/root/GameSession")
	var team: TeamData = session.get_team(side) if session else null
	var label_text: String = "Tour : %s" % (team.display_name if team else "?")
	if team:
		label_text += "  (%s)" % TeamDataClass.controller_name(team.controller)
		_label.add_theme_color_override("font_color", team.color)
	label_text += _absent_notice()

	if label_text != _last_text:
		_last_text = label_text
		_label.text = label_text


## Mention d'un joueur distant absent, place encore gardée (côté hôte).
##
## Sans elle, l'hôte verrait l'IA locale jouer le camp de son ami sans savoir
## qu'il peut encore revenir.
func _absent_notice() -> String:
	var net: Node = get_node_or_null("/root/Network")
	if not net or not net.is_online():
		return ""
	var seats: Dictionary = net.reserved_seats()
	for absent_side: int in seats:
		return "\n⏳ %s déconnecté — place gardée %d s" % [
			TeamDataClass.side_name(absent_side), int(ceilf(float(seats[absent_side])))
		]
	return ""
