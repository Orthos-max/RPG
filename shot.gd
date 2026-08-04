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
## Écrans : title, battle, editor.

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
		_:
			await _open_battle(main)

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


## Nouvelle partie → chapitre 1 → déploiement confirmé.
func _open_battle(main: Node) -> void:
	main._on_new_game(DIFF.Level.NORMAL, true)
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

	# La caméra perd sa cible une fois le déploiement confirmé et reste braquée
	# sur le vide : pour une capture, on la recale sur un pion du joueur.
	if level and level.camera:
		for pawn in level.player.get_children():
			if pawn is Node3D:
				level.camera.target = pawn
				break
	for _i in 40:
		await physics_frame


## Caméra d'observation : cadre toute l'arène, sans dépendre de celle du jeu.
##
## La caméra tactique est contrainte (rayon de déplacement, cible qui s'annule
## une fois atteinte) : impossible d'en tirer un cadrage reproductible. Celle-ci
## est posée en orthographique, inclinée, et regarde le centre de la grille —
## c'est aussi le banc d'essai du cadrage « Awakening ».
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
