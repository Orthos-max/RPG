class_name BattleSpeed
extends CanvasLayer
## Accélérateur d'animations de bataille — la touche [b]X[/b], maintenue.
##
## Un tour adverse se regarde : chaque pion glisse jusqu'à sa case, s'élance,
## frappe, et la caméra tremble sur les critiques. C'est ce qui rend le combat
## lisible la première fois, et ce qui le rend long à la vingtième. Plutôt que
## de raccourcir les animations pour tout le monde, on donne au joueur de quoi
## les passer : X enfoncée, le temps du moteur court trois fois plus vite ;
## relâchée, il reprend son cours.
##
## [b]Maintenue, pas basculée.[/b] Un raccourci qui bascule laisse le jeu
## accéléré si le joueur oublie de rappuyer — et [member Engine.time_scale] est
## global : il emporte les tweens, les [Timer], la physique et le reste de la
## partie avec lui. Tant que l'accélération ne dure que le temps d'un doigt
## posé, il n'y a rien à oublier.
##
## [b]Le retour à 1× est garanti à trois portes[/b] : le relâchement de la
## touche, la sortie de l'arbre (fin de bataille, retour au menu) et la perte de
## focus de la fenêtre (Alt-Tab en pleine accélération). Sans elles, une échelle
## de temps oubliée à 3× survivrait à la bataille et rendrait tous les écrans
## suivants frénétiques.
##
## [b]Rien ne tourne sans écran.[/b] [method available] rend `false` en
## `--headless`, où il n'y a ni animation à passer ni touche pour le demander :
## [Main] ne monte alors pas le nœud, et les suites de tests jouent des batailles
## entières à vitesse normale.

## La touche qui accélère, maintenue.
const HOLD_KEY: Key = KEY_X
## Son nom, tel qu'il s'affiche.
const HOLD_KEY_LABEL: String = "X"
## Facteur appliqué à [member Engine.time_scale] pendant l'accélération.
##
## Trois fois : assez pour que le tour adverse défile, pas assez pour que les
## morts et les critiques passent inaperçus — au-delà, on ne voit plus ce qu'on
## accélère, et le journal de bataille (touche H) devient le seul moyen de
## savoir ce qui vient d'arriver.
const SCALE: float = 3.0

## Au-dessus du bandeau de tour (10), sous le fondu de transition (100).
const LAYER: int = 11

const C_GOLD := Color("#f5c842")

## L'accélération est-elle en cours ?
var _engaged: bool = false
## L'échelle de temps d'avant l'accélération, à rendre au relâchement.
var _restore_to: float = 1.0

var _badge: Label = null


## Y a-t-il un écran, et donc des animations à passer ?
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


func _ready() -> void:
	layer = LAYER
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "SpeedRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Bas de l'écran, au centre : la fiche d'unité et l'encart de terrain tiennent
	# le coin bas-gauche, la prévision de combat le haut-droit.
	_badge = Label.new()
	_badge.name = "SpeedBadge"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_font_size_override("font_size", 14)
	_badge.add_theme_color_override("font_color", C_GOLD)
	_badge.anchor_left = 0.5
	_badge.anchor_right = 0.5
	_badge.anchor_top = 1.0
	_badge.anchor_bottom = 1.0
	_badge.offset_left = -110
	_badge.offset_right = 110
	_badge.offset_top = -34
	_badge.offset_bottom = -12
	root.add_child(_badge)
	_refresh_badge()


## X enfoncée accélère, X relâchée rend le temps.
##
## Les répétitions clavier (`echo`) sont ignorées : une touche maintenue en
## produit des dizaines, et chacune aurait relu l'échelle de temps déjà
## accélérée comme si c'était celle d'origine.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.keycode != HOLD_KEY or key.echo:
		return
	if key.pressed:
		engage()
	else:
		release()
	get_viewport().set_input_as_handled()


## Le temps court [constant SCALE] fois plus vite.
func engage() -> void:
	if _engaged:
		return
	_engaged = true
	# Ce qu'on rendra au relâchement : l'échelle du moment, et non 1× en dur —
	# rien n'interdit à une future pause de poser la sienne.
	_restore_to = Engine.time_scale if Engine.time_scale > 0.0 else 1.0
	Engine.time_scale = SCALE
	_refresh_badge()


## Le temps reprend son cours. Sans effet si l'accélération n'était pas en cours.
func release() -> void:
	if not _engaged:
		return
	_engaged = false
	Engine.time_scale = _restore_to
	_restore_to = 1.0
	_refresh_badge()


## L'accélération est-elle en cours ?
func is_engaged() -> bool:
	return _engaged


## La bataille se décharge : le temps ne doit pas rester accéléré sur l'écran de
## bilan, ni sur l'écran-titre derrière lui.
func _exit_tree() -> void:
	release()


## Les deux autres portes de sortie.
##
## [b]Perte de focus[/b] (Alt-Tab en pleine accélération) : la touche sera
## relâchée hors de la fenêtre, et le `released` correspondant n'arrivera jamais.
##
## [b]Destruction[/b] : dernier filet, pour le cas où le nœud est libéré sans
## jamais avoir été dans l'arbre — [method _exit_tree] ne se déclenche pas alors,
## et l'échelle de temps resterait accélérée pour toute la partie.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_PREDELETE:
		release()


## Le libellé du repère, selon l'état — c'est aussi lui qui fait connaître la touche.
func _refresh_badge() -> void:
	if not _badge or not is_instance_valid(_badge):
		return
	_badge.text = "⏩  ×%s" % _speed_text() if _engaged \
		else "⏩  %s : accélérer" % HOLD_KEY_LABEL
	_badge.modulate.a = 1.0 if _engaged else 0.4


## « 3 » plutôt que « 3.0 » : un facteur entier s'écrit sans décimale.
static func _speed_text() -> String:
	return str(int(SCALE)) if is_equal_approx(SCALE, float(int(SCALE))) \
		else "%.1f" % SCALE
