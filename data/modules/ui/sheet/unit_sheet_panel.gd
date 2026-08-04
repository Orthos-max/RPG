class_name UnitSheetPanel
extends PanelContainer
## Fiche de l'unité survolée — stats, valeurs de combat, terrain, compétences.
##
## Ne calcule rien : il recopie les lignes déjà mises en forme par [UnitSheet],
## exactement comme [BattleForecastPanel] le fait pour la prévision de combat.

## Couleur de la barre de PV selon l'état de l'unité
const COLOR_HEALTHY: Color = Color(0.55, 0.92, 0.6)
const COLOR_HURT: Color = Color(1.0, 0.78, 0.35)
const COLOR_CRITICAL: Color = Color(1.0, 0.45, 0.4)
const COLOR_DIM: Color = Color(0.72, 0.74, 0.8)

## En dessous de ces seuils, la barre change de couleur
const HURT_RATIO: float = 0.6
const CRITICAL_RATIO: float = 0.3

@onready var _title: Label = $Margin/VBox/Title
@onready var _health: Label = $Margin/VBox/Health
@onready var _stats: Label = $Margin/VBox/Stats
@onready var _combat: Label = $Margin/VBox/Combat
@onready var _context: Label = $Margin/VBox/Context
@onready var _skills: Label = $Margin/VBox/Skills

## Dernière fiche affichée — le survol est évalué à chaque frame, inutile de
## reconstruire six chaînes tant que l'unité ne change pas.
var _last: Dictionary = {}


func _ready() -> void:
	visible = false


## Affiche une fiche ; un dictionnaire vide masque l'encart.
func show_sheet(sheet: Dictionary) -> void:
	if sheet.is_empty():
		clear_sheet()
		return

	if sheet == _last:
		visible = true
		return
	_last = sheet.duplicate(true)

	_title.text = str(sheet["title"])

	var ratio: float = float(sheet["hp_ratio"])
	_health.text = "PV %d / %d" % [sheet["hp"], sheet["max_hp"]]
	_health.add_theme_color_override("font_color", _health_color(ratio))

	_stats.text = UnitSheet.stats_line(sheet)
	_combat.text = UnitSheet.combat_line(sheet)

	_context.text = UnitSheet.context_line(sheet)
	_context.add_theme_color_override("font_color", COLOR_DIM)

	var skills: String = UnitSheet.skills_line(sheet)
	_skills.visible = not skills.is_empty()
	_skills.text = skills
	_skills.add_theme_color_override("font_color", COLOR_DIM)

	visible = true


## Masque l'encart et oublie la dernière fiche.
func clear_sheet() -> void:
	_last = {}
	visible = false


func _health_color(ratio: float) -> Color:
	if ratio <= CRITICAL_RATIO:
		return COLOR_CRITICAL
	if ratio <= HURT_RATIO:
		return COLOR_HURT
	return COLOR_HEALTHY
