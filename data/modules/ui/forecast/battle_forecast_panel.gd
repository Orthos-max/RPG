class_name BattleForecastPanel
extends PanelContainer
## Encart de prévision de combat, affiché au survol d'une cible.
##
## Ne calcule rien : il met en forme le dictionnaire produit par
## [BattleForecast]. Toute la logique reste dans `data/services/combat/`.

## Couleurs des états notables (létalité, soin, avertissement).
const COLOR_NEUTRAL: Color = Color(0.92, 0.92, 0.95)
const COLOR_LETHAL: Color = Color(1.0, 0.45, 0.4)
const COLOR_CRIT_LETHAL: Color = Color(1.0, 0.78, 0.35)
const COLOR_HEAL: Color = Color(0.55, 0.92, 0.6)
const COLOR_DIM: Color = Color(0.72, 0.74, 0.8)

@onready var _title: Label = $Margin/VBox/Title
@onready var _damage: Label = $Margin/VBox/Damage
@onready var _rates: Label = $Margin/VBox/Rates
@onready var _health: Label = $Margin/VBox/Health
@onready var _counter: Label = $Margin/VBox/Counter
@onready var _counter_health: Label = $Margin/VBox/CounterHealth
@onready var _bonuses: Label = $Margin/VBox/Bonuses

## Dernière prévision affichée — évite de reconstruire le texte à chaque frame
## (le survol est évalué dans `_physics_process`).
var _last: Dictionary = {}


func _ready() -> void:
	visible = false


## Affiche une prévision ; un dictionnaire vide ou « none » masque l'encart.
func show_forecast(forecast: Dictionary) -> void:
	if forecast.is_empty() or str(forecast.get("kind", "none")) == "none":
		clear_forecast()
		return

	if forecast == _last:
		visible = true
		return
	_last = forecast.duplicate(true)

	_title.text = "%s → %s" % [forecast["attacker_name"], forecast["defender_name"]]

	if str(forecast["kind"]) == "heal":
		_fill_heal(forecast)
	else:
		_fill_attack(forecast)

	visible = true


## Masque l'encart et oublie la dernière prévision.
func clear_forecast() -> void:
	_last = {}
	visible = false


func _fill_heal(f: Dictionary) -> void:
	_damage.text = "Soin +%d PV" % f["heal"]
	_damage.add_theme_color_override("font_color", COLOR_HEAL)
	_rates.text = ""
	_rates.visible = false
	_health.text = "PV %d → %d / %d" % [f["target_hp"], f["target_hp_after"], f["target_max_hp"]]
	_health.add_theme_color_override("font_color", COLOR_HEAL)
	_counter.visible = false
	_counter_health.visible = false
	_bonuses.text = ""
	_bonuses.visible = false


func _fill_attack(f: Dictionary) -> void:
	var dmg: String = "%d dégâts" % f["total"]
	if bool(f["double"]):
		dmg += "  (%d ×2)" % f["damage"]
	if bool(f["lethal"]):
		dmg += "   ☠ LÉTAL"
	elif bool(f["crit_lethal"]):
		dmg += "   ☠ si critique"
	_damage.text = dmg
	_damage.add_theme_color_override("font_color", _damage_color(f))

	_rates.visible = true
	_rates.text = "Précision %d%%     Critique %d%%" % [f["hit"], f["crit"]]
	_rates.add_theme_color_override("font_color", COLOR_NEUTRAL)

	_health.text = "PV %d → %d / %d" % [f["target_hp"], f["target_hp_after"], f["target_max_hp"]]
	_health.add_theme_color_override("font_color", _damage_color(f))

	_fill_counter(f)

	var notes: Array[String] = []
	if int(f["triangle"]) != 0:
		notes.append("Triangle %+d / %+d%%" % [f["triangle"], f["triangle_hit"]])
	if bool(f["effective"]):
		notes.append("Efficace ×%d" % f["effective_mult"])
	if int(f["terrain"]) > 0:
		notes.append("Terrain 🛡 +%d" % f["terrain"])
	if int(f["support_hit"]) > 0 or int(f["support_crit"]) > 0:
		notes.append("Soutien 💬")
	for proc: Dictionary in f["procs"]:
		notes.append("✨ %s %d%%" % [proc["name"], proc["chance"]])

	_bonuses.visible = not notes.is_empty()
	_bonuses.text = "   ".join(notes)
	_bonuses.add_theme_color_override("font_color", COLOR_DIM)


## Ce que la cible rend — la moitié de la prévision qui manquait.
##
## Quand l'assaut tue à coup sûr, la riposte reste affichée mais grisée : elle
## n'aura lieu que si le coup manque, et c'est justement ce risque-là qu'il faut
## voir avant d'engager.
func _fill_counter(f: Dictionary) -> void:
	if not bool(f.get("can_counter", false)):
		_counter.visible = true
		_counter.text = "↩ Aucune riposte" + (
			"  (%s)" % f["counter_reason"] if not str(f.get("counter_reason", "")).is_empty() else ""
		)
		_counter.add_theme_color_override("font_color", COLOR_DIM)
		_counter_health.visible = false
		return

	var expected: bool = bool(f["counter_expected"])
	var line: String = "↩ Riposte %d dégâts" % f["counter_total"]
	if bool(f["counter_double"]):
		line += "  (%d ×2)" % f["counter_damage"]
	line += "   %d%%" % f["counter_hit"]
	if int(f["counter_crit"]) > 0:
		line += "   crit %d%%" % f["counter_crit"]
	if bool(f["counter_lethal"]):
		line += "   ☠ MORTEL"
	elif bool(f["counter_crit_lethal"]):
		line += "   ☠ si critique"
	if not expected:
		line += "   (seulement si le coup manque)"

	_counter.visible = true
	_counter.text = line
	_counter.add_theme_color_override("font_color", _counter_color(f) if expected else COLOR_DIM)

	_counter_health.visible = true
	_counter_health.text = "PV %s %d → %d / %d" % [
		f["attacker_name"], f["attacker_hp"], f["attacker_hp_after"], f["attacker_max_hp"]
	]
	_counter_health.add_theme_color_override("font_color", _counter_color(f) if expected else COLOR_DIM)


## Rouge quand la riposte tue l'assaillant, ambre si seul un critique le tue.
func _counter_color(f: Dictionary) -> Color:
	if bool(f["counter_lethal"]):
		return COLOR_LETHAL
	if bool(f["counter_crit_lethal"]):
		return COLOR_CRIT_LETHAL
	return COLOR_NEUTRAL


## Rouge quand le coup tue, ambre quand seul un critique tue.
func _damage_color(f: Dictionary) -> Color:
	if bool(f["lethal"]):
		return COLOR_LETHAL
	if bool(f["crit_lethal"]):
		return COLOR_CRIT_LETHAL
	return COLOR_NEUTRAL
