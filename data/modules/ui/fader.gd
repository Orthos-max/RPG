class_name ScreenFader
extends CanvasLayer
## Fondu au noir entre deux écrans.
##
## Un seul rectangle noir, posé au-dessus de tout ([constant LAYER]), dont on
## anime l'opacité. [Main] le garde pour toute la partie : le créer à chaque
## changement d'écran laisserait une frame sans voile, c'est-à-dire un clignotement.
##
## **Sans écran, le fondu est instantané.** Les suites headless enchaînent les
## écrans en quelques frames ; un tween d'un quart de seconde y ferait attendre
## des tests qui ne verront jamais l'image. [method fade_in] et [method fade_out]
## restent des coroutines dans les deux cas — on peut donc toujours les `await`,
## elles rendent simplement la main aussitôt.

## Durée d'un fondu, en secondes. Assez court pour ne pas se faire attendre.
const DEFAULT_DURATION: float = 0.25
## Au-dessus des interfaces de jeu (bandeau de tour : 10, minimap : 9).
const LAYER: int = 100

var _rect: ColorRect = null
var _tween: Tween = null


## Y a-t-il un écran à noircir ?
static func animates() -> bool:
	return DisplayServer.get_name() != "headless"


## Crée le voile et l'accroche à [param parent].
static func attach(parent: Node) -> ScreenFader:
	var fader := ScreenFader.new()
	fader.name = "ScreenFader"
	parent.add_child(fader)
	return fader


func _init() -> void:
	# Monté ici et non dans `_ready` : `attach` rend un fondu utilisable tout de
	# suite, y compris si son parent n'est pas encore dans l'arbre.
	layer = LAYER
	_rect = ColorRect.new()
	_rect.name = "Veil"
	_rect.color = Color(0, 0, 0, 0)
	# Un voile transparent qui avalerait les clics rendrait le menu inutilisable.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## Opacité courante du voile (0 = écran visible, 1 = noir complet).
func alpha() -> float:
	return _rect.color.a if is_instance_valid(_rect) else 0.0


## Éteint l'écran. À `await` avant de changer d'écran.
func fade_out(duration: float = DEFAULT_DURATION) -> void:
	await _to(1.0, duration)


## Rallume l'écran depuis le noir.
##
## Part toujours d'un voile opaque : appelé sans [method fade_out] préalable —
## un écran atteint directement, sans passer par un bouton — le nouvel écran
## apparaît quand même en fondu plutôt qu'en coupe franche.
func fade_in(duration: float = DEFAULT_DURATION) -> void:
	_set_alpha(1.0)
	await _to(0.0, duration)


## Amène le voile à [param target], d'un trait ou en tween selon l'écran.
func _to(target: float, duration: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null

	if not is_instance_valid(_rect):
		return
	if not animates() or duration <= 0.0 or not is_inside_tree():
		_set_alpha(target)
		return

	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", target, duration)
	await _tween.finished


func _set_alpha(value: float) -> void:
	if is_instance_valid(_rect):
		_rect.color.a = clampf(value, 0.0, 1.0)
