extends SceneTree
## Capture d'écran automatisée — regarder le jeu sans le jouer.
##
## Le rendu ne se teste pas en `--headless` : le pilote factice ne dessine rien.
## Cet outil ouvre une vraie fenêtre, va jusqu'à l'écran demandé, attend que
## tout soit en place, et enregistre une image. C'est ce qui permet de juger
## une passe artistique autrement qu'en lisant du code.
##
## Lancer :
##   godot --path . --resolution 1600x900 --script shot.gd -- battle out.png
##
## Écrans : title, battle, editor, prep.
##
## `prep` accepte un troisième argument — `equip`, `shop` ou `detail` — pour ouvrir
## directement le panneau à regarder. (`positions` a disparu avec son écran le
## 2026-08-07 : les cases de départ se choisissent sur le plateau.)

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

## Frames laissées au niveau pour se monter (arène, pions, roster)
const SETTLE_FRAMES: int = 90


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var screen: String = args[0] if args.size() > 0 else "battle"
	var out_path: String = args[1] if args.size() > 1 else "user://shot.png"

	await create_timer(0.2).timeout
	var main: Node = load("res://assets/scene/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame

	var free_camera: bool = args.size() > 2 and args[2] == "free"

	match screen:
		"title":
			pass
		"editor":
			main.show_editor()
			# `editor units` ouvre le sélecteur d'unité : c'est le seul moyen de
			# juger cette liste-là autrement qu'en lisant du code.
			if args.size() > 2 and args[2] == "units":
				for _i in 20:
					await physics_frame
				var editor: Node = main._level
				if editor and editor.has_node("EditorUI"):
					editor.get_node("EditorUI").open_unit_picker("opponent", 8)
				else:
					push_error("[shot] éditeur introuvable pour ouvrir le sélecteur")
			# `editor terrains` charge une carte qui montre les seize terrains à la
			# fois : une carte vierge ne dit rien d'une passe artistique.
			elif args.size() > 2 and args[2] == "terrains":
				for _i in 20:
					await physics_frame
				await _show_terrains(main)
		"range":
			# Une unité en main, sa portée de déplacement affichée : c'est le seul
			# moyen de juger le surlignage autrement qu'en lisant du code.
			await _open_battle(main, int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 1)
			await _show_range(main)
		"chars":
			main.show_character_editor()
			for _i in 10:
				await physics_frame
			# `bas` déroule le formulaire : armes, objets et compétences vivent
			# sous la ligne de flottaison, et une capture du haut ne les montre
			# jamais.
			if args.size() > 2 and args[2] == "bas":
				var form: ScrollContainer = _first_scroll(main)
				if form:
					form.scroll_vertical = 100000
				for _i in 10:
					await physics_frame
		"prep":
			await _open_prep(main, args[2] if args.size() > 2 else "")
		"saves":
			# Une partie d'abord, sinon les emplacements seraient tous vides.
			main._on_new_game(DIFF.Level.NORMAL, true)
			for _i in 5:
				await physics_frame
			main.show_saves(args.size() > 2 and args[2] == "save")
			for _i in 5:
				await physics_frame
		_:
			var chapter: int = int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 1
			await _open_battle(main, chapter)

	for _i in SETTLE_FRAMES:
		await physics_frame
	if free_camera:
		_frame_arena(main)
		await physics_frame
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	var error: int = image.save_png(out_path)
	if error == OK:
		print("[shot] %s → %s (%dx%d)" % [screen, out_path, image.get_width(), image.get_height()])
	else:
		printerr("[shot] échec de l'enregistrement : %d" % error)
	quit(0 if error == OK else 1)


## Charge dans l'éditeur une carte qui montre tous les terrains à la fois.
##
## Une carte vierge ne dit rien d'une passe artistique : elle est verte d'un bord
## à l'autre. Celle-ci met un hameau, un rempart percé d'une porte, une tour, des
## ruines, une rivière franchie par un pont, un marais, du sable et de la neige
## dans le même cadre — de quoi juger l'ensemble d'un coup d'œil.
## Premier ScrollContainer de l'arbre (null s'il n'y en a aucun).
func _first_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found: ScrollContainer = _first_scroll(child)
		if found:
			return found
	return null


func _show_terrains(main: Node) -> void:
	var editor: Node = main._level
	if not editor or not editor.get("doc"):
		push_error("[shot] éditeur introuvable pour charger la carte de démonstration")
		return

	var T := MapData.TerrainType
	var doc: MapDocument = MapDocument.create_empty("Les seize terrains", Vector2i(20, 12))

	# Un relief doux, pour que les ombres portées aient de quoi mordre.
	for row: int in 12:
		for col: int in 20:
			if col < 4 and row < 4:
				doc.set_height_at(Vector2i(col, row), 0.5)

	var paint := func(rect: Rect2i, terrain: int) -> void:
		for row: int in range(rect.position.y, rect.end.y):
			for col: int in range(rect.position.x, rect.end.x):
				doc.set_terrain_at(Vector2i(col, row), terrain)

	paint.call(Rect2i(0, 0, 4, 3), T.MOUNTAIN)      # massif au nord-ouest
	paint.call(Rect2i(0, 3, 3, 3), T.FOREST)        # bois à son pied
	paint.call(Rect2i(0, 9, 4, 3), T.SAND)          # grève au sud-ouest
	paint.call(Rect2i(16, 0, 4, 3), T.SNOW)         # névé au nord-est
	paint.call(Rect2i(5, 8, 3, 3), T.SWAMP)         # marais au sud

	# Un hameau au bord du chemin, à l'ouest.
	paint.call(Rect2i(2, 6, 1, 12 - 6), T.PATH)
	for cell: Vector2i in [Vector2i(3, 6), Vector2i(1, 7), Vector2i(3, 8)]:
		doc.set_terrain_at(cell, T.VILLAGE)

	# La rivière et son pont, au milieu.
	paint.call(Rect2i(9, 0, 2, 12), T.WATER)
	paint.call(Rect2i(2, 5, 7, 1), T.PATH)
	paint.call(Rect2i(9, 5, 2, 1), T.BRIDGE)
	paint.call(Rect2i(11, 5, 3, 1), T.PATH)

	# Un fort à l'est : rempart percé d'une porte, tours d'angle, ruines dehors.
	paint.call(Rect2i(14, 2, 1, 7), T.WALL)
	doc.set_terrain_at(Vector2i(14, 5), T.GATE)
	doc.set_terrain_at(Vector2i(14, 2), T.TOWER)
	doc.set_terrain_at(Vector2i(14, 8), T.TOWER)
	paint.call(Rect2i(16, 4, 2, 3), T.FORT)
	paint.call(Rect2i(12, 8, 2, 2), T.RUINS)
	doc.set_terrain_at(Vector2i(19, 11), T.WATER)

	editor.doc = doc
	editor._forget_history()
	editor._rebuild_all()
	# Reculer : le cadrage par défaut est réglé pour une carte de 16 × 10.
	editor._cam_dist = 21.0
	editor._cam_pitch = -46.0
	editor._refresh_camera()
	for _i in 10:
		await physics_frame


## Nouvelle partie → écran de préparation, panneau demandé ouvert.
##
## L'équipement d'armes et le choix des cases de départ ne se jugent pas en
## lisant du code : ils se regardent.
func _open_prep(main: Node, panel: String) -> void:
	main._on_new_game(DIFF.Level.NORMAL, true)
	for _i in 10:
		await physics_frame

	var prep: Node = _find_by_script(main, "prep_screen.gd")
	if not prep:
		printerr("[shot] écran de préparation introuvable")
		return

	match panel:
		"equip":
			prep._toggle_equipment()
		"shop":
			prep._toggle_shop()
		"detail":
			prep._toggle_detail()
		_:
			pass
	for _i in 10:
		await physics_frame


## Sélectionne la première unité jouable et affiche sa portée de déplacement.
func _show_range(main: Node) -> void:
	var level: Node = _find_class(main, "TacticsLevel")
	if not level:
		printerr("[shot] niveau introuvable")
		return
	var controls: Node = _find_by_script(main, "controls.gd")
	if not controls:
		printerr("[shot] contrôles introuvables")
		return

	# Marquer les tuiles à la main ne tient pas : la boucle de tour les remet à
	# zéro à chaque frame. On met l'unité en main et on demande l'étape « choisir
	# la case » — c'est le jeu lui-même qui surligne alors sa portée.
	for p in level.player.get_children():
		if not (p is TacticsPawn and is_instance_valid(p) and p.can_act()):
			continue
		controls.curr_pawn = p
		controls.participant.curr_pawn = p
		controls.participant.stage = 2
		break
	for _i in 30:
		await physics_frame

	# L'encart de terrain ne s'allume qu'au survol, et il n'y a pas de souris ici :
	# on lui désigne une case défensive à la main, comme le ferait un curseur.
	var arena: Node = level.arena
	for terrain: int in [MapData.TerrainType.FOREST, MapData.TerrainType.MOUNTAIN,
			MapData.TerrainType.RUINS, MapData.TerrainType.GRASS]:
		var found: Node = null
		for tile in TacticsGrid.tiles(arena):
			if int(tile.get("terrain_type")) == terrain:
				found = tile
				break
		if found:
			controls.set_terrain(terrain)
			break
	await physics_frame


## Premier nœud portant un script donné.
func _find_by_script(node: Node, suffix: String) -> Node:
	var script: Script = node.get_script()
	if script and str(script.resource_path).ends_with(suffix):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_by_script(child, suffix)
		if found:
			return found
	return null


## Nouvelle partie → chapitre demandé → déploiement confirmé.
##
## Le numéro de chapitre se passe en troisième argument (`battle out.png 2`) :
## regarder une carte précise est le seul moyen de juger son relief et son décor.
func _open_battle(main: Node, chapter: int = 1) -> void:
	main._on_new_game(DIFF.Level.NORMAL, true)
	await physics_frame
	if chapter > 1:
		var campaign: Node = root.get_node_or_null("Campaign")
		if campaign:
			campaign.chapter_index = chapter - 1
			campaign.deployment = campaign._default_deployment()
			# `Main` retient le chapitre au moment où il ouvre la préparation :
			# changer l'index sans rouvrir cet écran chargerait la carte du
			# chapitre précédent, et la capture montrerait la mauvaise carte.
			main.show_prep()
			await physics_frame
	main._on_battle_requested()
	for _i in 60:
		await physics_frame

	# La phase de déploiement suspend la bataille tant qu'on n'a pas confirmé.
	var level: Node = _find_class(main, "TacticsLevel")
	var runner: Node = level.get_node_or_null("ChapterRunner") if level else null
	var phase: Node = runner.get_node_or_null("DeploymentPhase") if runner else null
	if phase and phase.has_method("confirm"):
		phase.confirm()
	for _i in 30:
		await physics_frame

	# Plus rien à recaler ici : [TacticsFraming] pose la caméra sur le plateau à
	# l'ouverture du niveau. L'outil photographie donc bien ce que voit un
	# joueur — c'était le contraire tant qu'il fallait lui remettre une cible.
	for _i in 40:
		await physics_frame


## Caméra d'observation : cadre toute l'arène, sans dépendre de celle du jeu.
##
## La caméra tactique suit le jeu — elle se pose sur le pion qu'on sélectionne,
## le joueur la promène : son cadrage n'est pas reproductible d'une capture à
## l'autre. Celle-ci ne bouge jamais, et sert donc à comparer deux passes de
## rendu. Le cadrage « Awakening » qu'elle prototypait vit maintenant dans le
## jeu ([TacticsFraming]) ; les valeurs ci-dessous n'ont plus à s'y accorder.
func _frame_arena(main: Node) -> void:
	var level: Node = _find_class(main, "TacticsLevel")
	var arena: Node = level.arena if level else null
	var grid: Vector2i = TacticsGrid.grid_size(arena) if arena else Vector2i(16, 10)
	var tile: float = TacticsGrid.tile_size(arena) if arena else 1.0

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Assez pour tenir la diagonale de la grille inclinée, avec un peu d'air.
	cam.size = maxf(float(grid.y) * tile, float(grid.x) * tile * 0.62) + 3.0
	cam.far = 200.0
	root.add_child(cam)
	cam.current = true

	var yaw: float = deg_to_rad(-30.0)
	var pitch: float = deg_to_rad(-52.0)
	var distance: float = 40.0
	cam.position = Vector3(
		distance * cos(pitch) * sin(yaw),
		-distance * sin(pitch),
		distance * cos(pitch) * cos(yaw)
	)
	cam.look_at(Vector3.ZERO)


func _find_class(node: Node, class_wanted: String) -> Node:
	if node.get_class() == class_wanted or (node.get_script() and \
			str(node.get_script().get_global_name()) == class_wanted):
		return node
	for child in node.get_children():
		var found: Node = _find_class(child, class_wanted)
		if found:
			return found
	return null
