class_name EnemyPeekPanel
extends CanvasLayer
## Aperçu des stats d'une unité adverse, au simple survol de la souris.
##
## La fiche complète ([UnitSheetPanel], en bas à gauche) ne s'affiche qu'aux
## étapes où le jeu interroge le survol — choisir une unité, choisir une cible.
## Entre les deux, regarder ce que vaut un ennemi demandait de sélectionner une
## de ses unités, d'ouvrir « Attaquer », puis d'annuler. Cette étiquette-ci suit
## le curseur et répond tout de suite : PV, les cinq stats qui décident d'un
## échange, et l'arme en main.
##
## [b]C'est aussi un bestiaire[/b] : sous les chiffres viennent les compétences
## de l'unité ([method skill_lines_for]) et le flanc par lequel elle encaisse le
## moins ([method weakness_line]). Deux questions qu'on se pose avant chaque
## engagement — « que va-t-elle me faire ? » et « qui dois-je envoyer ? » —
## auxquelles il fallait jusqu'ici répondre de mémoire.
##
## Le codex reste [b]court par construction[/b] : au plus [constant MAX_SKILLS]
## compétences, résumées en une ligne chacune par [method SkillDB.summary], et
## une largeur bornée à [constant CODEX_WIDTH]. Une étiquette de survol qui
## couvre le plateau ne se lit plus, elle se subit.
##
## [b]Elle montre aussi la portée de l'unité pointée[/b] : les cases qu'elle peut
## atteindre au tour prochain s'allument en orange le temps du survol
## ([method BattleThreatRange.cells_for], le même calcul que la touche C mais
## borné à ce pion-ci). Les chiffres disent ce que coûte un échange, l'orange dit
## s'il aura seulement lieu.
##
## [b]Elle ne touche à rien.[/b] Le survol se lit par un rayon à elle, tiré
## depuis la caméra sur le calque des pions — aucun état de sélection n'est
## consulté ni modifié, et le jeu se joue exactement pareil qu'elle soit là ou
## non. La portée n'allume que [member TacticsTile.peek], un drapeau
## d'affichage qui cède le pas aux marques du déplacement en cours : pointer un
## ennemi pendant qu'on trace un trajet n'efface rien de ce trajet.
##
## [b]Rien ne tourne sans écran.[/b] [method available] rend `false` en
## `--headless`, où il n'y a ni souris ni caméra : [Main] ne monte alors pas le
## nœud. Les lignes, elles, se construisent sans nœud ([method lines_for]).

const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")
const ThreatRangeClass = preload("res://data/modules/ui/threat_range.gd")
const SkillDBClass = preload("res://data/models/world/stats/skill_db.gd")

## Calque de collision des pions — le même que celui du clic de sélection.
const PAWN_MASK: int = 2
## Portée du rayon de survol, en mètres.
const RAY_LENGTH: float = 1000.0
## Intervalle entre deux lectures du survol, en secondes.
##
## Un rayon par image serait gratuit pour le moteur mais reconstruirait six
## chaînes de texte à chaque frame ; un dixième de seconde suit la souris sans
## que l'œil voie le retard.
const REFRESH: float = 0.1
## Décalage de l'étiquette par rapport au curseur, en pixels.
const CURSOR_OFFSET := Vector2(20, 20)
## Marge gardée avec le bord de l'écran.
const SCREEN_MARGIN: float = 8.0

## Sous le journal (12) et l'accélérateur (11) : c'est une étiquette de survol,
## elle ne doit rien recouvrir de ce qu'on a ouvert exprès.
const LAYER: int = 8

const C_PANEL := Color(0.05, 0.04, 0.10, 0.9)
const C_ENEMY := Color("#e94560")
const C_TEXT := Color(1, 1, 1, 0.88)
const C_DIM := Color(0.72, 0.74, 0.8)
## Les compétences, dans le violet que le jeu réserve déjà aux ✨.
const C_SKILL := Color("#c9a7ff")
## La faiblesse, dans l'or des conseils : c'est une invitation à agir.
const C_WEAK := Color("#f5c842")

## Les stats montrées, dans l'ordre — celles qui décident d'un échange.
const SHOWN_STATS: Array[String] = ["FOR", "MAG", "VIT", "DÉF", "RÉS"]

## Compétences détaillées au plus, avant de compter les suivantes.
##
## Quatre lignes tiennent sous les chiffres sans les noyer ; une promue en porte
## rarement plus, et le surplus se dit d'un « … et 2 autres ».
const MAX_SKILLS: int = 4

## Largeur du codex, en pixels. Elle borne l'étiquette entière : les lignes de
## chiffres, elles, sont plus courtes.
const CODEX_WIDTH: float = 300.0

## Écart DÉF/RÉS à partir duquel un flanc devient un conseil.
##
## En deçà de trois points, envoyer le mage plutôt que le lancier ne change rien
## au nombre de coups nécessaires : l'annoncer serait un faux conseil.
const WEAKNESS_GAP: int = 3

## Le niveau observé — sert à retrouver la grille où teinter la portée.
var level: Node = null

var _root: Control = null
var _frame: PanelContainer = null
var _title: Label = null
var _health: Label = null
var _stats: Label = null
var _weapon: Label = null
var _skills: Label = null
var _weakness: Label = null
## Le filet qui sépare les chiffres du codex — masqué quand le codex est vide.
var _rule: HSeparator = null

var _since_refresh: float = 0.0
var _shown: TacticsPawn = null

## Les cases teintées pour l'unité survolée — gardées pour savoir quoi éteindre.
var _range_tiles: Array = []
## L'unité dont la portée est affichée, et la case d'où elle a été calculée.
##
## Le couple sert de cache : tant que ni l'une ni l'autre ne change, le parcours
## n'est pas refait. Sans lui, le survol relancerait un calcul de portée dix fois
## par seconde sur une scène qui n'a pas bougé.
var _range_of: TacticsPawn = null
var _range_from: Object = null


## Y a-t-il un écran, et donc une souris pour survoler ?
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


#region Contenu
## Ce pion est-il une unité adverse encore en vie ?
##
## Le camp se lit sur le nœud parent ([method TeamData.side_for_camp_node]),
## comme partout ailleurs dans le jeu.
static func is_enemy(pawn: Object) -> bool:
	if not pawn is TacticsPawn or not is_instance_valid(pawn):
		return false
	var unit: TacticsPawn = pawn as TacticsPawn
	if not unit.stats or not unit.is_alive():
		return false
	return TeamDataClass.side_for_camp_node(unit.get_parent()) == TeamDataClass.Side.OPPONENT


## Les quatre lignes de l'étiquette : titre, PV, stats, arme.
##
## Rien n'est calculé ici : [UnitSheet] met déjà en forme tout ce qu'on montre,
## et c'est lui que lit la fiche complète — les deux doivent dire la même chose.
static func lines_for(stats: Stats) -> Array[String]:
	if not stats:
		return ["", "", "", ""]
	var sheet: Dictionary = UnitSheet.build(stats)

	var shown: Array[String] = []
	for entry: Dictionary in sheet.get("stats", []):
		if str(entry.get("label", "")) in SHOWN_STATS:
			shown.append("%s %d" % [str(entry["label"]), int(entry["value"])])

	return [
		str(sheet.get("title", "")),
		"PV %d / %d" % [int(sheet.get("hp", 0)), int(sheet.get("max_hp", 0))],
		"   ".join(shown),
		"%s (%d)     Portée %d" % [
			str(sheet.get("weapon", "")), int(sheet.get("weapon_might", 0)),
			int(sheet.get("range", 1)),
		],
	]


## Les compétences de l'unité, une par ligne — vide si elle n'en a aucune.
##
## Une ligne par compétence ([method SkillDB.summary]) : le nom, l'effet chiffré,
## et la condition qui le déclenche. Au-delà de [constant MAX_SKILLS], le reste
## est compté plutôt que déroulé — le survol doit rester une étiquette.
##
## Les identifiants inconnus du catalogue sont écartés : une fiche peut porter
## une compétence retirée du jeu, et une ligne vide sous les chiffres ne dirait
## rien à personne.
static func skill_lines_for(stats: Stats) -> Array[String]:
	var lines: Array[String] = []
	if not stats:
		return lines

	var known: Array[String] = []
	for id: Variant in stats.get_skills():
		var summary: String = SkillDBClass.summary(str(id))
		if not summary.is_empty():
			known.append(summary)

	for i: int in range(mini(known.size(), MAX_SKILLS)):
		lines.append("✨ %s" % known[i])
	if known.size() > MAX_SKILLS:
		lines.append("… et %d autre(s)" % (known.size() - MAX_SKILLS))
	return lines


## Le flanc par lequel l'unité encaisse le moins — "" quand elle est équilibrée.
##
## Les deux chiffres sont déjà sur la ligne des stats ; ce qui manquait, c'est la
## conclusion. Un chevalier à DÉF 14 / RÉS 3 se prend au sortilège, un mage à
## l'inverse : le dire évite de compter l'écart de tête à chaque survol.
static func weakness_line(stats: Stats) -> String:
	if not stats:
		return ""
	if stats.res <= stats.def - WEAKNESS_GAP:
		return "⚡ Faible au magique — RÉS %d / DÉF %d" % [stats.res, stats.def]
	if stats.def <= stats.res - WEAKNESS_GAP:
		return "🗡 Faible au physique — DÉF %d / RÉS %d" % [stats.def, stats.res]
	return ""


## Le codex complet d'une unité : ses compétences, puis sa faiblesse.
##
## Une seule fonction pour ce que le panneau montre sous les chiffres — c'est
## elle que lisent les tests, faute d'écran où survoler quoi que ce soit.
static func codex_lines(stats: Stats) -> Array[String]:
	var lines: Array[String] = skill_lines_for(stats)
	var weakness: String = weakness_line(stats)
	if not weakness.is_empty():
		lines.append(weakness)
	return lines
#endregion


#region Montage
func _ready() -> void:
	layer = LAYER
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "PeekRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_frame = PanelContainer.new()
	_frame.name = "PeekPanel"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_ENEMY
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_frame.add_theme_stylebox_override("panel", style)
	_root.add_child(_frame)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	_frame.add_child(column)

	_title = _make_label(column, 14, C_ENEMY)
	_health = _make_label(column, 13, C_TEXT)
	_stats = _make_label(column, 13, C_TEXT)
	_weapon = _make_label(column, 12, C_DIM)

	# Le codex ouvre sur un filet : sans lui, compétences et chiffres se lisent
	# comme un seul bloc de texte.
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	_skills = _make_label(column, 12, C_SKILL, CODEX_WIDTH)
	_weakness = _make_label(column, 12, C_WEAK, CODEX_WIDTH)
	_rule = rule


func _make_label(parent: Node, font_size: int, color: Color, max_width: float = 0.0) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# Une largeur imposée est ce qui borne l'étiquette : un Label ne revient à la
	# ligne que s'il sait où s'arrêter. Elle ne s'applique qu'au codex, et un
	# Label masqué ne pèse rien dans la colonne — l'étiquette d'une unité sans
	# compétence garde donc la largeur de ses chiffres.
	if max_width > 0.0:
		label.custom_minimum_size = Vector2(max_width, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
#endregion


#region Vie de l'étiquette
func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < REFRESH:
		# L'étiquette suit quand même le curseur : la relecture est cadencée, pas
		# le placement — sinon elle sauterait par à-coups derrière la souris.
		_follow_cursor()
		return
	_since_refresh = 0.0

	var hovered: Object = _pawn_under_cursor()
	if is_enemy(hovered):
		show_for(hovered as TacticsPawn)
	else:
		clear_peek()
	_follow_cursor()


## Le pion sous la souris, ou `null`.
func _pawn_under_cursor() -> Object:
	var viewport: Viewport = get_viewport()
	if not viewport:
		return null
	var camera: Camera3D = viewport.get_camera_3d()
	if not camera:
		return null

	var pointer: Vector2 = viewport.get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(pointer)
	var to: Vector3 = from + camera.project_ray_normal(pointer) * RAY_LENGTH
	var world: World3D = viewport.find_world_3d()
	if not world:
		return null

	var query := PhysicsRayQueryParameters3D.create(from, to, PAWN_MASK, [])
	return world.direct_space_state.intersect_ray(query).get("collider")


## Affiche l'aperçu d'une unité (sans rien reconstruire si c'est déjà la sienne).
func show_for(pawn: TacticsPawn) -> void:
	if not _frame:
		return
	# La portée se rafraîchit même quand l'étiquette ne bouge pas : l'unité
	# pointée peut avoir changé de case entre-temps — au tour adverse, par
	# exemple, souris immobile.
	_show_range(pawn)
	if pawn == _shown and _frame.visible:
		return
	_shown = pawn

	var lines: Array[String] = lines_for(pawn.stats)
	_title.text = lines[0]
	_health.text = lines[1]
	_stats.text = lines[2]
	_weapon.text = lines[3]
	_fill_codex(pawn.stats)
	_frame.visible = true


## Pose les lignes du bestiaire, et efface le bloc s'il n'y a rien à dire.
##
## Masquer plutôt que vider : un Label vide garderait la largeur imposée au
## codex, et une unité sans compétence traînerait une étiquette trois fois plus
## large que ses chiffres.
func _fill_codex(stats: Stats) -> void:
	var skills: Array[String] = skill_lines_for(stats)
	var weakness: String = weakness_line(stats)

	_skills.text = "\n".join(skills)
	_skills.visible = not skills.is_empty()
	_weakness.text = weakness
	_weakness.visible = not weakness.is_empty()
	if _rule:
		_rule.visible = _skills.visible or _weakness.visible

	# La colonne vient de changer de hauteur : sans ce recalcul, l'étiquette
	# garderait la taille de l'unité précédente le temps d'une image, et
	# `_follow_cursor` la placerait à partir d'une mesure périmée.
	_frame.reset_size()


## Masque l'aperçu : la souris a quitté l'unité.
func clear_peek() -> void:
	_shown = null
	if _frame:
		_frame.visible = false
	_hide_range()


## L'unité actuellement montrée, ou `null`.
func shown_pawn() -> TacticsPawn:
	return _shown


## Nombre de cases actuellement teintées par le survol.
func range_count() -> int:
	return _range_tiles.size()


## Teinte les cases que l'unité pointée peut frapper au tour prochain.
##
## Le calcul est celui de la touche C, borné à ce pion
## ([method BattleThreatRange.cells_for]), et il ne se refait que si l'unité ou
## sa case change — c'est le même parti pris que l'étiquette, qui ne reconstruit
## ses lignes que sur changement.
func _show_range(pawn: TacticsPawn) -> void:
	var tile: Object = pawn.get_tile()
	if pawn == _range_of and tile == _range_from and not _range_tiles.is_empty():
		return
	_hide_range()

	var grid: BattleGrid = ThreatRangeClass.grid_of(level)
	if not grid:
		return
	_range_of = pawn
	_range_from = tile

	for coord: Vector2i in ThreatRangeClass.cells_for(pawn, level):
		var cell: Node = grid.tile_at(coord)
		if cell is TacticsTile:
			(cell as TacticsTile).peek = true
			_range_tiles.append(cell)


## Éteint les cases teintées. Sans effet si rien n'était affiché.
func _hide_range() -> void:
	for cell: Variant in _range_tiles:
		if is_instance_valid(cell):
			(cell as TacticsTile).peek = false
	_range_tiles.clear()
	_range_of = null
	_range_from = null


## La bataille se décharge : aucune case ne doit rester orange.
func _exit_tree() -> void:
	_hide_range()


## Pose l'étiquette près du curseur, sans la laisser déborder de l'écran.
func _follow_cursor() -> void:
	if not _frame or not _frame.visible or not _root:
		return
	var wanted: Vector2 = get_viewport().get_mouse_position() + CURSOR_OFFSET
	var bounds: Vector2 = _root.size - _frame.size - Vector2(SCREEN_MARGIN, SCREEN_MARGIN)
	_frame.position = Vector2(
		clampf(wanted.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, bounds.x)),
		clampf(wanted.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, bounds.y)))
#endregion
