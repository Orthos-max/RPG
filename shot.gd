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
## `prep` accepte un troisième argument — `equip` ou `shop` — pour ouvrir
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
		"range":
			# Une unité en main, sa portée de déplacement affichée : c'est le seul
			# moyen de juger le surlignage autrement qu'en lisant du code.
			await _open_battle(main, int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 1)
			await _show_range(main)
		"chars":
			main.show_character_editor()
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
