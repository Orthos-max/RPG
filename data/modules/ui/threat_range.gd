class_name BattleThreatRange
extends CanvasLayer
## Portée des ennemis — la touche [b]C[/b], maintenue, teinte tout ce qu'ils
## peuvent frapper au tour prochain.
##
## Un tactical se perd toujours de la même façon : on pose une unité sur une case
## qui paraissait sûre, et trois adversaires l'atteignent au tour suivant. Le
## calcul existait déjà dans le jeu — c'est celui qui trace la portée du pion
## qu'on sélectionne ([TacticsArenaService.process_surrounding_tiles]) — mais
## personne ne le faisait tourner pour l'adversaire.
##
## [b]Maintenue, pas basculée[/b], comme l'accélérateur ([BattleSpeed], touche X)
## : la carte rouge écrase les marques du déplacement en cours, elle n'a donc pas
## à survivre au doigt qui la demande. C tenue montre le danger, C relâchée rend
## le plateau.
##
## [b]Ne touche à rien du jeu.[/b] Le parcours se calcule sur un [PathField]
## neuf, jamais sur celui de l'arène — celui-là porte le déplacement du joueur en
## cours, et le recalculer sous ses pieds casserait le trajet qu'il est en train
## de tracer. Seul le drapeau d'affichage [member TacticsTile.threat] est posé,
## puis retiré.
##
## [b]La liste des cases est une fonction pure.[/b] [method threat_cells] prend un
## niveau et rend des coordonnées, sans rien allumer : c'est ce qui rend la
## portée vérifiable en `--headless`, là où l'affichage n'a pas lieu d'être.

const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")
const MapDataClass = preload("res://data/models/world/map/map_data.gd")

## La touche qui montre le danger, maintenue.
const HOLD_KEY: Key = KEY_C
## Son nom, tel qu'il s'affiche.
const HOLD_KEY_LABEL: String = "C"

## Sous l'accélérateur (11) et le journal (12), au-dessus de la minimap (9).
const LAYER: int = 10

## Dénivelé toléré par un tir. Une flèche ne monte pas une falaise à pied : la
## portée d'arme ignore le relief, là où le déplacement s'y heurte (`stats.jump`).
const ATTACK_HEIGHT: float = 999.0

const C_THREAT := Color("#e0559c")

## Le niveau observé.
var level: Node = null

var _badge: Label = null
var _engaged: bool = false
## Les tuiles actuellement teintées — gardées pour savoir quoi éteindre.
var _marked: Array = []


## Y a-t-il un écran où montrer la portée ?
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


#region Calcul de la portée
## Toutes les cases qu'un camp hostile peut frapper au tour prochain.
##
## Union, pour chaque ennemi vivant, des cases à portée d'arme depuis chacune des
## cases où il peut se rendre. C'est la « zone de danger » de Fire Emblem : elle
## prend la portée **maximale** de l'arme et non son plancher, parce qu'un
## ennemi qui ne peut pas frapper au contact peut presque toujours reculer d'un
## pas pour le faire.
##
## [returns] un tableau de [Vector2i], sans doublon, dans un ordre quelconque.
static func threat_cells(from_level: Node) -> Array:
	var grid: BattleGrid = _grid_of(from_level)
	if not grid:
		return []

	var marked: Dictionary = {}
	for pawn: TacticsPawn in enemy_pawns(from_level):
		for coord: Vector2i in _threat_of(grid, pawn):
			marked[coord] = true
	return marked.keys()


## Les pions des camps hostiles au joueur, vivants et posés sur la grille.
##
## Le camp se lit sur le nœud parent ([method TeamData.side_for_camp_node]) et
## non sur le pion, exactement comme la minimap : c'est déjà ainsi que le reste
## du jeu répartit les armées.
static func enemy_pawns(from_level: Node) -> Array:
	var out: Array = []
	if not from_level is TacticsLevel:
		return out
	var participant: Node = (from_level as TacticsLevel).participant
	if not participant or not is_instance_valid(participant):
		return out

	for camp: Node in participant.get_children():
		var side: int = TeamDataClass.side_for_camp_node(camp)
		if side != TeamDataClass.Side.OPPONENT:
			continue
		for child: Node in camp.get_children():
			if not child is TacticsPawn:
				continue
			var pawn: TacticsPawn = child as TacticsPawn
			if not pawn.is_alive() or pawn.is_queued_for_deletion() or not pawn.stats:
				continue
			out.append(pawn)
	return out


## L'index de grille de ce niveau — le sien s'il l'expose, celui en cours sinon.
static func _grid_of(from_level: Node) -> BattleGrid:
	if from_level is TacticsLevel:
		var arena: TacticsArena = (from_level as TacticsLevel).arena
		if arena and arena.grid:
			return arena.grid
	return BattleGrid.current


## Les cases menacées par un seul pion : où il peut aller, puis ce qu'il y frappe.
static func _threat_of(grid: BattleGrid, pawn: TacticsPawn) -> Array:
	var tile: TacticsTile = pawn.get_tile()
	if not tile or not grid.has_tile(tile):
		return []

	var origin: Vector2i = grid.coord_of(tile)
	var allies: Array = pawn.get_parent().get_children() if pawn.get_parent() else []

	# Un parcours à soi : celui de l'arène porte le déplacement du joueur en cours.
	var field := PathField.new()
	field.expand(grid, origin, pawn.stats.jump,
		func(coord: Vector2i) -> bool: return _passable(grid, coord, allies),
		# Même tarif que le déplacement du joueur, sans quoi l'aperçu promettrait
		# une charge par la montagne que l'ennemi ne peut pas payer.
		func(coord: Vector2i) -> float: return _step_cost(grid, coord))

	var stands: Array[Vector2i] = [origin]
	var movement: float = float(pawn.stats.movement)
	for coord: Vector2i in field.reached():
		if field.distance_at(coord) <= movement:
			stands.append(coord)

	return _spread(grid, stands, maxi(1, int(pawn.stats.attack_range)))


## Une case se traverse-t-elle pour cet ennemi ? Terrain d'abord, occupation ensuite.
##
## Même règle que le déplacement du joueur ([method TacticsArenaService._passable])
## : on passe à travers les siens, jamais à travers l'adversaire.
static func _passable(grid: BattleGrid, coord: Vector2i, allies: Array) -> bool:
	var tile: Node = grid.tile_at(coord)
	if not tile:
		return false
	if not MapDataClass.is_walkable(int(tile.terrain_type)):
		return false
	var occupier: Object = grid.occupant_of(tile)
	return occupier == null or occupier in allies


## Ce que coûte l'entrée sur une case — même tarif que [method
## TacticsArenaService._step_cost].
static func _step_cost(grid: BattleGrid, coord: Vector2i) -> float:
	var tile: Node = grid.tile_at(coord)
	if not tile:
		return 1.0
	return MapDataClass.move_cost(int(tile.terrain_type))


## Toutes les cases à [param reach] pas des cases de départ, celles-ci comprises.
##
## Un parcours en anneaux plutôt qu'un [PathField] par case de départ : la portée
## d'arme ne connaît ni terrain ni occupation (on tire par-dessus les têtes), et
## une seule vague partant de tout le front coûte un parcours au lieu de trente.
static func _spread(grid: BattleGrid, sources: Array[Vector2i], reach: int) -> Array:
	var seen: Dictionary = {}
	var frontier: Array[Vector2i] = []
	for coord: Vector2i in sources:
		if not seen.has(coord):
			seen[coord] = true
			frontier.append(coord)

	for _step: int in reach:
		var next: Array[Vector2i] = []
		for coord: Vector2i in frontier:
			for neighbor: Vector2i in grid.neighbor_coords(coord, ATTACK_HEIGHT):
				if seen.has(neighbor):
					continue
				seen[neighbor] = true
				next.append(neighbor)
		if next.is_empty():
			break
		frontier = next

	return seen.keys()
#endregion


#region Montage
func _ready() -> void:
	layer = LAYER
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "ThreatRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Juste au-dessus du repère d'accélération (bas de l'écran, au centre) :
	# les deux disent la même chose — une touche à tenir.
	_badge = Label.new()
	_badge.name = "ThreatBadge"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_font_size_override("font_size", 14)
	_badge.add_theme_color_override("font_color", C_THREAT)
	_badge.anchor_left = 0.5
	_badge.anchor_right = 0.5
	_badge.anchor_top = 1.0
	_badge.anchor_bottom = 1.0
	_badge.offset_left = -140
	_badge.offset_right = 140
	_badge.offset_top = -56
	_badge.offset_bottom = -34
	root.add_child(_badge)
	_refresh_badge()
#endregion


#region Vie de l'affichage
## C enfoncée montre le danger, C relâchée rend le plateau.
##
## Les répétitions clavier (`echo`) sont ignorées : une touche maintenue en
## produit des dizaines, et chacune aurait relancé le calcul de toute l'armée.
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


## Teinte les cases menacées.
func engage() -> void:
	if _engaged:
		return
	_engaged = true
	_paint()
	_refresh_badge()


## Éteint les cases teintées. Sans effet si rien n'était affiché.
func release() -> void:
	if not _engaged:
		return
	_engaged = false
	_erase()
	_refresh_badge()


## Le danger est-il affiché ?
func is_engaged() -> bool:
	return _engaged


## Nombre de cases actuellement teintées.
func marked_count() -> int:
	return _marked.size()


func _paint() -> void:
	_erase()
	if not level or not is_instance_valid(level):
		return
	var grid: BattleGrid = _grid_of(level)
	if not grid:
		return
	for coord: Vector2i in threat_cells(level):
		var tile: Node = grid.tile_at(coord)
		if tile and tile is TacticsTile:
			(tile as TacticsTile).threat = true
			_marked.append(tile)


func _erase() -> void:
	for tile: Variant in _marked:
		if is_instance_valid(tile):
			(tile as TacticsTile).threat = false
	_marked.clear()


## La bataille se décharge : aucune case ne doit rester rouge.
func _exit_tree() -> void:
	release()


## Alt-Tab en pleine consultation : la touche sera relâchée hors de la fenêtre, et
## le `released` correspondant n'arrivera jamais.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release()


## Le libellé du repère — c'est aussi lui qui fait connaître la touche.
func _refresh_badge() -> void:
	if not _badge or not is_instance_valid(_badge):
		return
	_badge.text = "🩸  Portée ennemie" if _engaged \
		else "🩸  %s : portée ennemie" % HOLD_KEY_LABEL
	_badge.modulate.a = 1.0 if _engaged else 0.4
#endregion
