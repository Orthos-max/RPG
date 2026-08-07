class_name DeploymentPhase
extends Node
## Placement des unités avant le premier tour : le joueur choisit ses cases.
##
## Jusqu'ici le roster était plaqué sur les pions déjà posés dans la scène, et
## le bonus de terrain — pourtant calculé en combat — ne se jouait pas avant la
## bataille. Cette étape ouvre les cases de départ, laisse déplacer et échanger
## les unités à la souris, puis rend la main à la boucle de tour.
##
## La règle vit dans [DeploymentPlan] (logique pure, testée) ; ce nœud-ci ne
## fait que la relier à la scène : marquage des tuiles, clics, position des pions.

signal finished()

const PLAN = preload("res://data/models/campaign/deployment_plan.gd")
const EXECUTOR = preload("res://data/models/world/ai/ai_executor.gd")
const MapDataRef = preload("res://data/models/world/map/map_data.gd")

## Hauteur du pion au-dessus de sa tuile (même valeur que le miroir réseau)
const PAWN_LIFT: float = 0.5

var level: TacticsLevel = null
## Cases déclarées par le chapitre ([[col, row], …]) — vide : voisinage par défaut
var declared_tiles: Array = []

var plan := PLAN.new()
var _tiles: Dictionary = {}      ## "col,row" → TacticsTile
var _selected: TacticsPawn = null
var _hud: Label = null
var _done: bool = false


func _ready() -> void:
	if not level or not is_instance_valid(level) or not level.arena:
		_abort()
		return

	# La boucle de tour attendra : sans cela, l'adversaire jouerait pendant
	# qu'on installe encore ses propres unités. On la suspend tout de suite,
	# avant même de savoir où sont les pions.
	level.set_physics_process(false)

	# Les pions apprennent sur quelle tuile ils se trouvent par un raycast, qui
	# demande quelques frames de physique après le chargement de la carte.
	if not await _wait_for_tiles():
		_abort()
		return

	_index_tiles()
	_build_plan()
	if plan.slots.is_empty():
		_abort()  # Rien à proposer : on ne bloque pas la partie pour autant.
		return

	_mark_slots(true)
	_build_hud()
	_refresh_hud()


## Abandonne le placement et rend la main comme si de rien n'était.
func _abort() -> void:
	_done = true
	if is_instance_valid(level):
		level.set_physics_process(true)
	finished.emit()
	queue_free()


## Attend que les pions du joueur sachent sur quelle tuile ils sont.
func _wait_for_tiles() -> bool:
	for _i in 120:
		for pawn in _player_pawns():
			if _grid_of(pawn).x >= 0:
				return true
		await get_tree().physics_frame
	return false


## Termine le placement et rend la main à la bataille.
func confirm() -> void:
	if _done:
		return
	_done = true
	_mark_slots(false)
	if is_instance_valid(level):
		level.set_physics_process(true)
	print_rich("[color=cyan]⚑ Déploiement confirmé : %d unité(s) en place[/color]" % plan.placed_count())
	finished.emit()
	queue_free()


#region Construction
func _index_tiles() -> void:
	for tile in TacticsGrid.tiles(level.arena):
		var g: Vector2i = TacticsGrid.tile_to_grid(level.arena, tile)
		_tiles["%d,%d" % [g.x, g.y]] = tile


## Établit les cases ouvertes puis y inscrit les pions là où ils sont déjà.
func _build_plan() -> void:
	var occupied: Array[Vector2i] = []
	for pawn in _player_pawns():
		var g: Vector2i = _grid_of(pawn)
		if g.x >= 0:
			occupied.append(g)

	var candidates: Array = declared_tiles
	if candidates.is_empty():
		candidates = PLAN.default_slots(occupied, TacticsGrid.grid_size(level.arena))

	var usable: Array[Vector2i] = []
	for raw: Variant in candidates:
		var pos: Vector2i = raw if raw is Vector2i else Vector2i(int(raw[0]), int(raw[1]))
		if _is_usable(pos):
			usable.append(pos)
	plan.configure(usable)

	for pawn in _player_pawns():
		var g: Vector2i = _grid_of(pawn)
		if g.x >= 0:
			plan.place(EXECUTOR.display_name(pawn), g)


## Une case est utilisable si elle existe, se franchit, et n'est pas tenue par
## un autre camp — déployer sur un ennemi n'aurait aucun sens.
func _is_usable(pos: Vector2i) -> bool:
	var tile: Node = _tiles.get("%d,%d" % [pos.x, pos.y], null)
	if not tile:
		return false
	var terrain: Variant = tile.get("terrain_type")
	if terrain != null and not MapDataRef.is_walkable(int(terrain)):
		return false
	for camp: Node3D in level.camps:
		if camp == level.player or not is_instance_valid(camp):
			continue
		for p in camp.get_children():
			if p is TacticsPawn and is_instance_valid(p) and _grid_of(p) == pos:
				return false
	return true
#endregion


#region Interaction
func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			confirm()
		return

	if not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var pawn: Node = _raycast(2)
	if pawn is TacticsPawn and pawn.get_parent() == level.player:
		_click_on_pawn(pawn)
		return

	var tile: Node = _raycast(1)
	if tile is TacticsTile:
		_drop_on(TacticsGrid.tile_to_grid(level.arena, tile))


## Un clic sur une unité du joueur.
##
## Trois cas, et l'ordre compte. Un pion masque toujours sa case au rayon : on ne
## peut pas cliquer « la case sous une unité », donc c'est le clic sur l'unité
## elle-même qui doit porter l'échange.
##
## Le piège d'avant (remonté par Aurèle le 2026-08-07) : l'unité **restait en
## main** après avoir été posée. Le clic suivant, sur une autre unité, tombait
## donc dans le cas « échange » au lieu de simplement la choisir — impossible de
## passer à l'unité suivante, on permutait sans arrêt les deux mêmes. Poser une
## unité la relâche désormais ([method _drop_on]), et l'échange ne se déclenche
## que si l'on tient délibérément quelqu'un.
func _click_on_pawn(pawn: Node) -> void:
	# Reprendre celle qu'on tient déjà : on la relâche. Sans cela, on ne pouvait
	# pas revenir sur un choix sans poser l'unité quelque part.
	if _selected == pawn:
		_selected = null
		_set_hud_line("%s repose. Choisis une unité." % EXECUTOR.display_name(pawn))
		return

	if is_instance_valid(_selected):
		_drop_on(_grid_of(pawn))
		return

	_selected = pawn
	_refresh_hud()


## Pose l'unité en main sur une case (échange si elle est déjà prise).
##
## Poser **relâche** l'unité : le geste est terminé, et le clic suivant doit
## pouvoir en désigner une autre.
func _drop_on(pos: Vector2i) -> void:
	if not is_instance_valid(_selected):
		_set_hud_line("Choisis d'abord une unité, puis sa case.")
		return

	var mover: String = EXECUTOR.display_name(_selected)
	var origin: Vector2i = plan.position_of(mover)
	var result: Dictionary = plan.place(mover, pos)
	if not bool(result["ok"]):
		# Le refus garde l'unité en main : elle vient d'être choisie, la lui
		# retirer parce qu'on a visé à côté serait puni deux fois.
		_set_hud_line("⛔ %s" % str(result["error"]))
		return

	_move_pawn(_selected, pos)
	var swapped: String = str(result["swapped"])
	if not swapped.is_empty() and origin.x >= 0:
		var other: Node = EXECUTOR.find_pawn_by_name(level.player, swapped)
		if other:
			_move_pawn(other, origin)

	var placed: String = mover
	_selected = null
	_refresh_hud("%s en place%s." % [
		placed, " — échange avec %s" % swapped if not swapped.is_empty() else ""])


## Téléporte un pion sur sa case : avant la bataille, pas de trajet à jouer.
func _move_pawn(pawn: Node, pos: Vector2i) -> void:
	var tile: Node3D = _tiles.get("%d,%d" % [pos.x, pos.y], null)
	if not tile:
		return
	pawn.res.pathfinding_tilestack = []
	pawn.global_position = tile.global_position + Vector3(0, PAWN_LIFT, 0)
#endregion


#region Affichage
func _mark_slots(enabled: bool) -> void:
	for pos: Vector2i in plan.slots:
		var tile: Node = _tiles.get("%d,%d" % [pos.x, pos.y], null)
		if tile:
			tile.deploy_point = enabled


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)

	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hud.offset_top = -96
	_hud.offset_bottom = -16
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color("#27d9c5"))
	layer.add_child(_hud)

	var btn := Button.new()
	btn.text = "Commencer la bataille  (Entrée)"
	btn.custom_minimum_size = Vector2(280, 40)
	btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_left = -300
	btn.offset_right = -20
	btn.offset_top = -150
	btn.offset_bottom = -110
	btn.pressed.connect(confirm)
	layer.add_child(btn)


## Remet le bandeau à jour, et marque la case de l'unité en main.
## [param message] Ligne à afficher à la place de l'état courant (facultatif).
func _refresh_hud(message: String = "") -> void:
	_mark_held()
	if not message.is_empty():
		_set_hud_line(message)
		return

	if is_instance_valid(_selected):
		_set_hud_line("%s en main — clique sa case." % EXECUTOR.display_name(_selected))
		return
	_set_hud_line("Choisis une unité.  %d case(s) ouverte(s), %d libre(s)." % [
		plan.slots.size(), plan.free_slots().size()
	])


## Signale sous les pieds de l'unité en main la case qu'elle occupe.
##
## Sans repère, rien ne distinguait « j'ai choisi une unité » de « je n'ai rien
## choisi » : les deux montraient le même plateau. Le survol seul ne suffit pas,
## il ne dit pas *qui* on tient.
func _mark_held() -> void:
	for tile: Variant in TacticsGrid.tiles(level.arena):
		if tile is TacticsTile:
			(tile as TacticsTile).hover = false
	if not is_instance_valid(_selected):
		return
	var cell: Vector2i = _grid_of(_selected)
	var tile: Node = _tiles.get("%d,%d" % [cell.x, cell.y], null)
	if tile:
		tile.hover = true


func _set_hud_line(text: String) -> void:
	if _hud:
		_hud.text = "%s\nUne unité, puis sa case. Cliquer une autre unité les échange ; recliquer la sienne la repose. Entrée pour commencer." % text
#endregion


#region Utilitaires
func _player_pawns() -> Array:
	var out: Array = []
	if not level.player or not is_instance_valid(level.player):
		return out
	for p in level.player.get_children():
		# Les unités non déployées viennent d'être libérées par le runner : elles
		# sont encore dans l'arbre pour une frame et occuperaient une case pour rien.
		if p is TacticsPawn and is_instance_valid(p) and not p.is_queued_for_deletion():
			out.append(p)
	return out


func _grid_of(pawn: Node) -> Vector2i:
	var tile: Node = pawn.get_tile() if pawn.has_method("get_tile") else null
	return TacticsGrid.tile_to_grid(level.arena, tile) if tile else Vector2i(-1, -1)


## Raycast depuis la caméra vers le curseur, sur un masque de collision donné.
func _raycast(mask: int) -> Object:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null
	if not camera:
		return null
	var mouse: Vector2 = viewport.get_mouse_position()
	var params := PhysicsRayQueryParameters3D.create(
		camera.project_ray_origin(mouse),
		camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * 1000.0
	)
	params.collision_mask = mask
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(params)
	return hit.get("collider", null)
#endregion
