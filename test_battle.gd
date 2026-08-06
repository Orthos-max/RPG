extends SceneTree
## Test d'intégration headless : campagne → chapitre chargé → pont CielAI.
## Lancer : godot --headless --path . --script test_battle.gd
##
## Vérifie que la chaîne complète tient debout dans un vrai arbre de scène :
## écran-titre → nouvelle partie → déploiement → niveau chargé → état exporté
## → commande invalide rejetée → commande valide acquittée.

const DIFF = preload("res://data/models/world/ai/difficulty.gd")
const CMAP = preload("res://data/models/campaign/chapter_map.gd")
const CAMPAIGN_DB = preload("res://data/models/campaign/campaign_db.gd")

const STATE_FILE: String = "user://ai_state.json"
const CMD_FILE: String = "user://ai_command.json"
const FEEDBACK_FILE: String = "user://ai_feedback.json"

var _passed: int = 0
var _failed: int = 0
var _lines: Array = []


func _init() -> void:
	print("\n========================================")
	print("  TEST INTÉGRATION — bataille & pont")
	print("========================================\n")
	await create_timer(0.2).timeout
	await _run()

	print("\n========================================")
	print("  RÉSULTATS: %d OK / %d ÉCHECS" % [_passed, _failed])
	print("========================================\n")
	for l in _lines:
		print(l)
	await create_timer(0.2).timeout
	quit(0 if _failed == 0 else 1)


func _run() -> void:
	# Un ordre laissé par une exécution précédente fausserait tout le test.
	if FileAccess.file_exists(CMD_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CMD_FILE))

	var main_scene: PackedScene = load("res://assets/scene/main.tscn")
	if not main_scene:
		_ko("Chargement de main.tscn", "introuvable")
		return
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	_ok("main.tscn instanciée")

	# --- Écran-titre ---
	var title_found: bool = _find_by_script(main, "title_screen.gd") != null
	_check(title_found, "écran-titre monté au démarrage")

	# --- Nouvelle partie ---
	var campaign: Node = root.get_node_or_null("Campaign")
	var session: Node = root.get_node_or_null("GameSession")
	if not campaign or not session:
		_ko("Autoloads Campaign/GameSession", "absents")
		return

	main._on_new_game(DIFF.Level.NORMAL, true)
	await physics_frame
	_check(campaign.roster.size() > 0 and not campaign.deployment.is_empty(),
		"nouvelle partie : roster %d, déploiement %d" % [
			campaign.roster.size(), campaign.deployment.size()])
	_check(_find_by_script(main, "prep_screen.gd") != null, "écran de préparation affiché")

	# --- Déploiement restreint volontairement à 2 unités ---
	var ids: Array = []
	for u: Dictionary in campaign.available_units():
		ids.append(str(u["id"]))
	campaign.set_deployment([ids[0], ids[1]])
	_check(campaign.deployment.size() == 2, "déploiement forcé à 2 unités")

	# --- Choix du terrain, fait devant la carte comme le ferait le joueur ---
	# On vise une case défensive : si le choix se propage jusqu'en bataille, c'est
	# tout le trajet préparation → sauvegarde → pion posé qui tient.
	var map: Dictionary = CMAP.read(CAMPAIGN_DB.get_chapter(0))
	var chosen := Vector2i(-1, -1)
	for pos: Vector2i in map.get("slots", []):
		if CMAP.defense_at(map, pos) > 0:
			chosen = pos
			break
	_check(chosen.x >= 0, "case défensive repérée en préparation : %s" % chosen)
	if chosen.x >= 0:
		campaign.set_deployment_tile(str(ids[0]), chosen)

	# --- Chargement du chapitre ---
	main._on_battle_requested()
	# Le niveau s'initialise sur plusieurs frames (arène, pions, roster).
	for _i in 60:
		await physics_frame

	var level: Node = _find_class(main, "TacticsLevel")
	_check(level != null, "niveau du chapitre 1 chargé")
	if not level:
		return

	var runner: Node = level.get_node_or_null("ChapterRunner")
	_check(runner != null, "ChapterRunner attaché au niveau")
	await _settle_deployment(runner)

	var player_pawns: int = _count_pawns(level.player)
	var enemy_pawns: int = _count_pawns(level.opponent)
	_check(player_pawns == 2, "roster appliqué : %d pions joueur (déployés)" % player_pawns,
		"attendu 2")
	_check(enemy_pawns > 0, "camp adverse peuplé : %d pions" % enemy_pawns)

	# --- La case choisie devant la carte est bien celle occupée en bataille ---
	if chosen.x >= 0:
		var posted: Node = _find_pawn_by_id(level.player, str(ids[0]))
		var target_tile: Node3D = TacticsGrid.find_tile(level.arena, chosen.x, chosen.y)
		_check(posted != null and target_tile != null,
			"unité et case retrouvées en scène (%s)" % chosen)
		if posted and target_tile:
			# On compare au sol : le moteur recentre le pion sur sa tuile et lui
			# reprend la hauteur du déploiement, ce qui ne regarde pas la case.
			var here := Vector2(posted.global_position.x, posted.global_position.z)
			var there := Vector2(target_tile.global_position.x, target_tile.global_position.z)
			var gap: float = here.distance_to(there)
			_check(gap < 0.05,
				"l'unité se tient sur la case choisie en préparation (écart %.3f)" % gap,
				"pion %s en %s, tuile en %s" % [
					posted.display_name(), posted.global_position, target_tile.global_position])
			# Et le bonus promis devant la carte est celui que la tuile porte.
			_check(TacticsGrid.terrain_defense(target_tile) == CMAP.defense_at(map, chosen),
				"le bonus de terrain annoncé en préparation (+%d) est celui de la tuile" % \
					CMAP.defense_at(map, chosen),
				"tuile : +%d" % TacticsGrid.terrain_defense(target_tile))

	if runner:
		var snapshot: Dictionary = runner.build_snapshot()
		_check(snapshot["player_units"].size() == player_pawns
				and snapshot["enemy_units"].size() == enemy_pawns,
			"instantané d'objectif cohérent")

	_check_arena_binding(main, level)
	await _check_framing(main, level)

	# --- Export d'état pour Ciel ---
	session.set_ciel_enabled(true)
	for _i in 20:
		await physics_frame

	var state: Dictionary = _read_json(STATE_FILE)
	_check(not state.is_empty() and int(state.get("protocol_version", 0)) == 1,
		"ai_state.json écrit (protocole v%s)" % str(state.get("protocol_version", "?")))
	_check(state.has("pawns") and state["pawns"].size() == player_pawns + enemy_pawns,
		"état : %d pions exportés" % (state["pawns"].size() if state.has("pawns") else -1))
	_check(state.has("terrain") and state["terrain"].has("rows"),
		"état : carte des terrains exportée")
	_check(state.has("stage_actions"), "état : actions légales exposées")

	if state.has("pawns") and not state["pawns"].is_empty():
		var p: Dictionary = state["pawns"][0]
		_check(p.has("class_name") and p.has("items") and p.has("terrain_def"),
			"état : pion enrichi (classe, objets, terrain)")

	# --- Commande invalide : rejetée proprement ---
	_write_command('{"action": "nawak"}')
	for _i in 30:
		await physics_frame
	var feedback: Dictionary = _read_json(FEEDBACK_FILE)
	_check(not bool(feedback.get("ok", true)) and str(feedback.get("code_name", "")) == "UNKNOWN_ACTION",
		"commande inconnue rejetée : %s" % str(feedback.get("error", "?")))
	_check(not FileAccess.file_exists(CMD_FILE), "fichier de commande consommé (pas de boucle)")
	_check(_find_class(main, "TacticsLevel") != null, "moteur toujours debout après rejet")

	# --- Commande malformée : rejetée aussi ---
	_write_command('{"action": ')
	for _i in 30:
		await physics_frame
	feedback = _read_json(FEEDBACK_FILE)
	_check(str(feedback.get("code_name", "")) == "MALFORMED_JSON",
		"JSON malformé rejeté : %s" % str(feedback.get("code_name", "?")))

	# --- Toggle : bascule vers l'IA locale ---
	_write_command('{"action": "toggle", "enabled": false}')
	for _i in 30:
		await physics_frame
	_check(not session.is_ciel_controlled(), "toggle off → camp adverse à l'IA locale")

	# --- Sauvegarde ---
	_check(campaign.save_game(99) and campaign.has_save(99), "sauvegarde de campagne écrite")
	campaign.delete_save(99)

	await _run_seize_chapter(main, campaign, session)
	await _run_custom_map(main, campaign)

	main.queue_free()
	await physics_frame


## Chapitre à « prise de point » : la case existe, elle est marquée, et Ciel la voit.
##
## Le pion ne peut pas réellement s'y poser en headless (pas de collisions de
## tuiles, donc pas de déplacement), mais tout le reste de la chaîne se vérifie :
## coordonnées → tuile de la carte → marquage → export dans `ai_state.json`.
func _run_seize_chapter(main: Node, campaign: Node, session: Node) -> void:
	var index: int = CampaignDB.index_of("ch04")
	if index < 0:
		_ko("Chapitre à prise de point", "aucun chapitre SEIZE dans CampaignDB")
		return

	campaign.chapter_index = index
	session.chapter_index = index
	main.show_prep()
	await physics_frame
	main._on_battle_requested()
	for _i in 60:
		await physics_frame

	var level: Node = _find_class(main, "TacticsLevel")
	var runner: Node = level.get_node_or_null("ChapterRunner") if level else null
	_check(runner != null, "chapitre 4 chargé avec son runner")
	if not runner:
		return

	await _settle_deployment(runner)

	var target: Vector2i = runner.seize_target()
	_check(target.x >= 0, "objectif « prise de point » reconnu %s" % str(target))

	var tile: Node = TacticsGrid.find_tile(level.arena, target.x, target.y)
	_check(tile != null, "la case à prendre existe sur la carte %s" % str(target))
	_check(tile != null and bool(tile.get("seize_point")),
		"la case à prendre est marquée en jeu")

	var snapshot: Dictionary = runner.build_snapshot()
	_check(not bool(snapshot["seized"]), "point non tenu au premier tour")
	_check(snapshot["player_units"].is_empty()
			or snapshot["player_units"][0].has("col"),
		"instantané : les unités portent leur case")

	# L'état n'est exporté que si Ciel tient le camp adverse (coupé plus haut).
	session.set_ciel_enabled(true)
	for _i in 30:
		await physics_frame
	var state: Dictionary = _read_json(STATE_FILE)
	var point: Dictionary = state.get("objective_point", {})
	_check(int(point.get("col", -1)) == target.x and int(point.get("row", -1)) == target.y,
		"Ciel reçoit la case à défendre", str(point))


## Éditeur de cartes : dessiner, poser, jouer — puis vérifier que la campagne
## est restée intacte.
func _run_custom_map(main: Node, campaign: Node) -> void:
	const LORD: String = "res://data/models/world/stats/hero/lord.tres"
	const SKELETON: String = "res://data/models/world/stats/mob/skeleton.tres"

	var gold_before: int = campaign.gold
	var chapter_before: int = campaign.chapter_index

	# --- L'éditeur s'ouvre et dessine ce qu'on lui demande ---
	main.show_editor()
	for _i in 20:
		await physics_frame

	var editor: Node = _find_class_named(main, "MapEditorLevel")
	_check(editor != null, "éditeur de cartes ouvert")
	if not editor:
		return
	_check(editor.doc != null, "l'éditeur démarre sur une carte vierge")

	var tiles_built: int = 0
	for child in editor.get_children():
		if String(child.name).begins_with("Tile_"):
			tiles_built += 1
	_check(tiles_built == editor.doc.grid_size.x * editor.doc.grid_size.y,
		"grille dessinée : %d tuiles" % tiles_built)

	# Peindre, élever, poser : les outils passent bien par le document.
	editor._tool = MapEditorUI.Tool.FOREST
	editor._use_tool(Vector2i(4, 4))
	_check(editor.doc.terrain_at(Vector2i(4, 4)) == MapData.TerrainType.FOREST,
		"outil pinceau : le terrain change")

	editor._tool = MapEditorUI.Tool.RAISE
	editor._use_tool(Vector2i(4, 4))
	_check(editor.doc.height_at(Vector2i(4, 4)) > 0.0, "outil élévation")

	editor._tool = MapEditorUI.Tool.UNIT_PLAYER
	editor._unit_paths["player"] = LORD
	editor._use_tool(Vector2i(2, 2))
	editor._tool = MapEditorUI.Tool.UNIT_OPPONENT
	editor._unit_paths["opponent"] = SKELETON
	editor._use_tool(Vector2i(12, 7))
	_check(editor.doc.units.size() == 2, "deux unités posées à la souris")

	editor._tool = MapEditorUI.Tool.DEPLOY
	editor._use_tool(Vector2i(2, 2))
	editor._use_tool(Vector2i(3, 2))
	_check(editor.doc.deploy_tiles.size() == 2, "zone de déploiement dessinée")

	# Un terrain devenu infranchissable ne peut plus porter ce qu'on y avait mis.
	editor._tool = MapEditorUI.Tool.WATER
	editor._use_tool(Vector2i(3, 2))
	_check(not editor.doc.is_deploy_tile(Vector2i(3, 2)),
		"noyer une case de départ la referme")

	# --- Annuler / rétablir : le coup de pinceau malheureux se défait ---
	_check(editor._history != null and editor._history.can_undo(),
		"les gestes de l'éditeur sont annulables")
	editor._on_undo()
	_check(editor.doc.is_deploy_tile(Vector2i(3, 2))
			and editor.doc.terrain_at(Vector2i(3, 2)) != MapData.TerrainType.WATER,
		"annuler rend la case de départ noyée")
	editor._on_redo()
	_check(not editor.doc.is_deploy_tile(Vector2i(3, 2)),
		"rétablir remet le lac et referme la case")

	# Un clic sans effet ne consomme pas un cran d'annulation.
	var steps_before: int = editor._history.undo_steps()
	editor._tool = MapEditorUI.Tool.ERASE
	editor._use_tool(Vector2i(9, 9))  # aucune unité ici
	_check(editor._history.undo_steps() == steps_before,
		"un clic sans effet n'entre pas dans l'historique")

	# --- Redimensionner depuis les réglages ---
	editor._tool = MapEditorUI.Tool.UNIT_PLAYER
	editor._use_tool(Vector2i(14, 8))
	var far_unit: int = editor.doc.units.size()
	editor._on_settings("Carte de test", 4, Vector2i(14, 10), editor.doc.objective)
	_check(editor.doc.grid_size == Vector2i(14, 10),
		"la grille suit les réglages %s" % str(editor.doc.grid_size))
	var tiles_after: int = 0
	for child in editor.get_children():
		if String(child.name).begins_with("Tile_") and is_instance_valid(child) \
				and not child.is_queued_for_deletion():
			tiles_after += 1
	_check(tiles_after == 140, "la vue 3D est rebâtie à la nouvelle taille (%d tuiles)" % tiles_after)
	_check(editor.doc.units.size() == far_unit - 1, "l'unité hors grille est retirée")

	editor._on_undo()
	_check(editor.doc.grid_size == Vector2i(16, 10) and editor.doc.units.size() == far_unit,
		"annuler le redimensionnement rend la grille et l'unité")
	editor._tool = MapEditorUI.Tool.ERASE
	editor._use_tool(Vector2i(14, 8))

	editor.doc.name = "Carte de test"
	_check(editor.doc.validate().is_empty(), "carte d'essai jugée jouable",
		str(editor.doc.validate()))

	# --- Jouer la carte ---
	var document = editor.doc
	main._on_play_custom_map(document, false)
	for _i in 60:
		await physics_frame

	var level: Node = _find_class(main, "TacticsLevel")
	_check(level != null, "la carte du joueur devient un niveau jouable")
	if not level:
		return

	_check(_count_pawns(level.player) == 1 and _count_pawns(level.opponent) == 1,
		"les unités de la carte sont en scène (%d joueur, %d adverse)" % [
			_count_pawns(level.player), _count_pawns(level.opponent)])
	_check(TacticsGrid.grid_size(level.arena) == document.grid_size,
		"l'arène adopte la grille de la carte %s" % str(TacticsGrid.grid_size(level.arena)))

	_check_battle_grid(level, document.grid_size)

	var runner: Node = level.get_node_or_null("ChapterRunner")
	_check(runner != null, "la carte est pilotée comme un chapitre")
	await _settle_deployment(runner)

	# Le roster de campagne ne doit pas s'inviter sur une carte du joueur.
	var names: Array = []
	for p in level.player.get_children():
		if p is TacticsPawn and is_instance_valid(p):
			names.append(p.display_name())
	_check(names.size() == 1 and str(names[0]) == MapDocument.unit_display_name(LORD),
		"le roster de campagne ne remplace pas les unités de la carte : %s" % str(names))

	_check(campaign.gold == gold_before and campaign.chapter_index == chapter_before,
		"jouer une carte d'essai ne touche pas à la campagne")

	main.show_title()
	await physics_frame


## Traverse la phase de placement quand elle existe.
##
## Elle ne s'ouvre que fenêtre ouverte : sans rendu, les tuiles n'ont pas de
## collision et les pions ne savent pas où ils se tiennent. Ce test tourne dans
## les deux modes, d'où la condition — en `--headless`, il n'y a rien à faire.
func _settle_deployment(runner: Node) -> void:
	if not runner:
		return
	var phase: Node = null
	for _i in 30:
		phase = runner.get_node_or_null("DeploymentPhase")
		if phase and not phase.plan.slots.is_empty():
			break
		await physics_frame

	if not phase or not is_instance_valid(phase):
		_check(DisplayServer.get_name() == "headless",
			"placement des unités : absent seulement en headless", DisplayServer.get_name())
		return

	_check(not phase.plan.slots.is_empty(),
		"placement : %d case(s) ouverte(s)" % phase.plan.slots.size())
	_check(phase.plan.placed_count() > 0,
		"placement : les unités déployées sont sur des cases ouvertes")

	# Un déplacement volontaire vers une case libre, comme un clic du joueur.
	var free: Array = phase.plan.free_slots()
	var units: Array = phase.plan.assignments().keys()
	if not free.is_empty() and not units.is_empty():
		var moved: String = str(units[0])
		var result: Dictionary = phase.plan.place(moved, free[0])
		_check(bool(result["ok"]) and phase.plan.position_of(moved) == free[0],
			"placement : une unité change de case", str(result))

	phase.confirm()
	await physics_frame
	_check(runner.get_node_or_null("DeploymentPhase") == null,
		"placement confirmé : la bataille reprend la main")


#region Helpers
## Les contrôles s'adressent-ils à l'arène réellement en scène ?
##
## Contrôles et caméra vivent dans `main.tscn` et survivent aux niveaux ; l'arène
## arrive avec la carte. Les contrôles chargeaient donc une ressource d'arène par
## défaut — celle d'aucune carte de chapitre, qui passent par `map_arena.tres`.
## Deux instances distinctes : tous les signaux d'arène émis par les contrôles
## partaient dans le vide, y compris le calcul du trajet, qui rendait une pile
## vide. **Déplacer une unité à la souris était impossible**, et le pion revenait
## au menu sans avoir bougé.
##
## Rien ne le signalait : le pont CielAI et l'IA locale appellent le nœud arène
## directement, donc toute la suite passait au vert sur un jeu injouable.
func _check_arena_binding(main: Node, level: Node) -> void:
	var controls: Node = main.get_node_or_null("TacticsControls")
	_check(controls != null, "contrôles montés dans main.tscn")
	if not controls or not level or not level.arena:
		return

	_check(controls.arena == level.arena.res,
		"les contrôles visent l'arène de ce niveau",
		"deux ressources distinctes : les signaux d'arène se perdent")
	_check(level.arena.res.is_connected("called_get_pathfinding_tilestack",
			Callable(level.arena, "get_pathfinding_tilestack")),
		"le calcul de trajet est bien relié à l'arène")

	# Et il rend un trajet, pas une pile vide.
	var start: Node3D = TacticsGrid.find_tile(level.arena, 4, 4)
	var goal: Node3D = TacticsGrid.find_tile(level.arena, 6, 4)
	if start and goal:
		level.arena.process_surrounding_tiles(start, 10.0, [])
		var path: Array = controls.arena.get_pathfinding_tilestack(goal)
		_check(path.size() >= 2,
			"un trajet demandé par les contrôles fait %d étape(s)" % path.size(),
			"pile vide : le pion ne bougerait pas")
		level.arena.reset_all_tile_markers()


## La bataille s'ouvre-t-elle sur le plateau, et y reste-t-elle ?
##
## La caméra vit au-dessus des niveaux et leur survit : entrer en bataille la
## laissait là où l'écran précédent l'avait posée, puis le panoramique de bord —
## déclenché par un curseur hors fenêtre, ou par la position (0,0) que rend un
## serveur d'affichage sans souris — l'emmenait jusqu'à sa limite de
## déplacement. Le joueur ouvrait sa première bataille sur un morceau de ciel.
## Rien ne le signalait : aucun test ne regardait où pointait la vue.
func _check_framing(main: Node, level: Node) -> void:
	var camera: Node = main.get_node_or_null("Camera/TacticsCamera")
	_check(camera != null, "caméra tactique montée dans main.tscn")
	if not camera or not level:
		return

	var cam_node: Camera3D = camera.cam_node
	_check(cam_node.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"cadrage orthographique (« Awakening »)",
		"projection = %d" % cam_node.projection)
	_check(is_equal_approx(snappedf(camera.t_pivot.rotation_degrees.x, 0.1),
			TacticsFraming.PITCH_DEGREES),
		"inclinaison fixée à %.0f°" % TacticsFraming.PITCH_DEGREES,
		"inclinaison = %.1f°" % camera.t_pivot.rotation_degrees.x)

	var bounds: Dictionary = TacticsFraming.board_bounds(level.arena)
	var board: Vector2 = bounds["size"]
	_check(board.x > 0.0 and board.y > 0.0,
		"étendue du plateau mesurée sur les tuiles : %.0f × %.0f" % [board.x, board.y])
	_check(cam_node.size >= TacticsFraming.fit_size(board) - 0.01,
		"le cadrage d'ouverture tient le plateau entier (size = %.1f)" % cam_node.size,
		"il en faudrait %.1f" % TacticsFraming.fit_size(board))

	# Le plateau reste sous la vue le temps que la boucle de tour s'installe :
	# c'est la fuite elle-même que l'on cherche, pas la position d'une image.
	var strayed: float = 0.0
	for _i in 120:
		await physics_frame
		strayed = maxf(strayed, camera.global_position.distance_to(bounds["center"]))
	var allowed: float = TacticsFraming.pan_radius(level.arena)
	_check(strayed <= allowed,
		"la vue reste sur le plateau (écart max %.1f ≤ %.1f)" % [strayed, allowed],
		"la caméra a fui à %.1f du centre" % strayed)
	# Une caméra collée à sa limite est déjà en train de dériver : la fuite
	# précédente s'arrêtait pile là, faute de pouvoir aller plus loin.
	_check(strayed < allowed - 0.5,
		"et sans venir buter sur sa limite de déplacement")


## L'index de grille répond-il vraiment, et dit-il la même chose que la formule
## qu'il remplace ? Le repli sur les rayons 3D masquerait une régression : ces
## vérifications échouent s'il prend le relais.
func _check_battle_grid(level: Node, expected_size: Vector2i) -> void:
	var grid: BattleGrid = BattleGrid.current
	_check(grid != null and grid.size() == expected_size.x * expected_size.y,
		"l'index de grille couvre les %d cases" % (expected_size.x * expected_size.y),
		"index = %s" % ("absent" if not grid else str(grid.size())))
	if not grid:
		return

	# Parité avec l'ancienne conversion, tuile par tuile.
	var mismatches: int = 0
	var scanned: int = 0
	for tile: Node in TacticsGrid.tiles(level.arena):
		if not tile is Node3D:
			continue
		scanned += 1
		var by_index: Vector2i = grid.cell_of(tile)
		var by_formula: Vector2i = _legacy_tile_to_grid(level.arena, tile as Node3D, expected_size)
		if by_index != by_formula:
			mismatches += 1
	_check(scanned > 0 and mismatches == 0,
		"index et ancienne formule s'accordent sur les %d tuiles" % scanned,
		"%d désaccords" % mismatches)

	# Adjacence : une case du milieu a bien ses quatre voisines, sans rayon.
	var middle: Node3D = TacticsGrid.find_tile(level.arena, expected_size.x / 2, expected_size.y / 2)
	_check(middle != null and grid.neighbors_of(middle, 10.0).size() == 4,
		"une case centrale a 4 voisines par la donnée seule")

	# Occupation : les pions en scène sont retrouvés sur leurs cases.
	grid.refresh_occupancy(true)
	var occupied: int = 0
	for tile: Node in TacticsGrid.tiles(level.arena):
		if grid.is_taken(tile):
			occupied += 1
	_check(occupied == _count_pawns(level.player) + _count_pawns(level.opponent),
		"chaque pion occupe une case dans l'index (%d)" % occupied)

	_check_reachability_headless(level, grid)


## Le gain attendu du refactor : calculer où un pion peut aller, sans fenêtre.
## Le parcours part des voisines et de l'occupation — l'un et l'autre sont
## désormais de la donnée, donc plus rien n'exige de moteur physique monté.
func _check_reachability_headless(level: Node, grid: BattleGrid) -> void:
	var pawn: TacticsPawn = null
	for child: Node in level.player.get_children():
		if child is TacticsPawn and is_instance_valid(child):
			pawn = child
			break
	if not pawn:
		_check(false, "un pion du joueur sert de point de départ")
		return

	var from: Node = null
	for tile: Node in TacticsGrid.tiles(level.arena):
		if grid.occupant_of(tile) == pawn:
			from = tile
			break
	_check(from != null, "le pion est retrouvé sur sa case par l'index seul")
	if not from:
		return

	var movement: float = float(pawn.stats.movement)
	level.arena.reset_all_tile_markers()
	level.arena.process_surrounding_tiles(from, float(pawn.stats.jump))
	level.arena.mark_reachable_tiles(from, movement)

	var origin: Vector2i = grid.cell_of(from)
	var reachable: int = 0
	var too_far: int = 0
	for tile: Node in TacticsGrid.tiles(level.arena):
		if not tile.get("reachable"):
			continue
		reachable += 1
		var cell: Vector2i = grid.cell_of(tile)
		if absi(cell.x - origin.x) + absi(cell.y - origin.y) > int(movement):
			too_far += 1

	_check(reachable > 1, "la portée de déplacement se calcule sans fenêtre (%d cases)" % reachable)
	_check(too_far == 0, "aucune case atteignable au-delà des %d points de mouvement" % int(movement),
		"%d cases trop loin" % too_far)


## La conversion d'avant le refactor, gardée ici comme témoin.
func _legacy_tile_to_grid(_arena: Node, tile: Node3D, gs: Vector2i) -> Vector2i:
	var pos: Vector3 = tile.global_position
	var col: int = int(round(pos.x + (float(gs.x) / 2.0) - 0.5))
	var row: int = int(round(pos.z + (float(gs.y) / 2.0) - 0.5))
	return Vector2i(clampi(col, 0, gs.x - 1), clampi(row, 0, gs.y - 1))


## Pion d'un camp portant l'identifiant de roster donné (null s'il est absent).
func _find_pawn_by_id(team: Node, unit_id: String) -> Node:
	if not team or not is_instance_valid(team):
		return null
	for p in team.get_children():
		if not (p is TacticsPawn and is_instance_valid(p)):
			continue
		if p.display_name().to_lower().replace(" ", "_") == unit_id:
			return p
	return null


func _count_pawns(team: Node) -> int:
	if not team or not is_instance_valid(team):
		return 0
	var n: int = 0
	for c in team.get_children():
		if c is TacticsPawn and is_instance_valid(c):
			n += 1
	return n


## Retrouve un nœud d'après le nom de sa classe de script (class_name).
func _find_class_named(node: Node, script_class: String) -> Node:
	var script: Script = node.get_script() as Script
	if script and script.get_global_name() == script_class:
		return node
	for c in node.get_children():
		var found: Node = _find_class_named(c, script_class)
		if found:
			return found
	return null


func _find_class(node: Node, class_str: String) -> Node:
	if node.is_class(class_str) or (node.get_script() and node is TacticsLevel and class_str == "TacticsLevel"):
		return node
	for c in node.get_children():
		var found: Node = _find_class(c, class_str)
		if found:
			return found
	return null


func _find_by_script(node: Node, script_suffix: String) -> Node:
	var script: Script = node.get_script()
	if script and script.resource_path.ends_with(script_suffix):
		return node
	for c in node.get_children():
		var found: Node = _find_by_script(c, script_suffix)
		if found:
			return found
	return null


func _write_command(payload: String) -> void:
	var f := FileAccess.open(CMD_FILE, FileAccess.WRITE)
	if f:
		f.store_string(payload)
		f.close()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


func _ok(label: String) -> void:
	_passed += 1
	_lines.append("  ✅ %s" % label)


func _ko(label: String, detail: String = "") -> void:
	_failed += 1
	_lines.append("  ❌ %s — %s" % [label, detail])


func _check(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		_ok(label)
	else:
		_ko(label, detail)
#endregion
