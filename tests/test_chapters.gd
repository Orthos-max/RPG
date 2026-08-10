extends SceneTree
## Test d'intégration **fenêtre ouverte** : enchaîner deux chapitres.
##
## Lancer : godot --path . --resolution 1280x720 --script res://tests/test_chapters.gd
##
## Pourquoi cette suite existe. Le passage d'un chapitre au suivant a cassé deux
## fois — le 2026-08-06 (la partie détruite) et le 2026-08-07 (plus rien ne
## répondait au clic). Les deux fois, tout ce qui l'entoure était au vert : les
## règles de campagne sont éprouvées en headless depuis longtemps, mais *monter
## une seconde bataille dans la même session* ne l'était pas.
##
## Ce que ça attrape, et que rien d'autre n'attrape : les **ressources
## partagées**. Participant, contrôles et caméra vivent dans `main.tscn` et
## survivent aux niveaux. Ils gardaient des pions et des camps de la bataille
## précédente, libérés depuis. En debug Godot annule ces références et le jeu
## s'en remet ; dans une build exportée elles restent pendantes, et le joueur se
## retrouve devant une partie qui ne répond plus.
##
## D'où la vérification finale : on **clique** une unité, et on exige qu'elle
## soit prise. C'est la seule qui décrit ce que le joueur vit.

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

var _passed: int = 0
var _failed: int = 0
var _lines: Array = []
var _main: Node = null


func _init() -> void:
	print("\n========================================")
	print("  TEST FENÊTRE — enchaîner deux chapitres")
	print("========================================\n")

	if DisplayServer.get_name() == "headless":
		print("⚠ Cette suite exige une vraie fenêtre — lancer sans --headless.")
		quit(2)
		return

	await create_timer(0.3).timeout
	await _run()

	print("\n========================================")
	print("  RÉSULTATS: %d OK / %d ÉCHECS" % [_passed, _failed])
	print("========================================\n")
	for l in _lines:
		print(l)
	await create_timer(0.2).timeout
	quit(0 if _failed == 0 else 1)


func _run() -> void:
	_main = load("res://assets/scene/main.tscn").instantiate()
	root.add_child(_main)
	await physics_frame

	_main._on_new_game(DIFF.Level.NORMAL, true)
	await physics_frame
	_check(_chapter_id() == "ch01", "une partie neuve ouvre au chapitre 1", _chapter_id())

	# --- Chapitre 1 ---
	if not await _open_chapter("chapitre 1"):
		return
	await _check_playable("chapitre 1")

	# --- Le gagner ---
	var level: Node = _find(_main, "TacticsLevel")
	for p in level.opponent.get_children():
		if p is TacticsPawn and p.stats:
			p.stats.curr_health = 0
			p.stats.hp = 0
	for _i in 420:
		await physics_frame

	_check(_campaign_index() == 1,
		"le camp adverse anéanti, la campagne avance d'un chapitre",
		"index %d" % _campaign_index())

	# --- Passer au chapitre 2, comme le bouton de l'écran de victoire ---
	_main.show_prep()
	for _i in 30:
		await physics_frame
	_check(_chapter_id() == "ch02", "l'écran de préparation propose le chapitre 2",
		_chapter_id())

	if not await _open_chapter("chapitre 2"):
		return

	# La carte est bien celle du chapitre 2, et pas celle d'avant restée en place.
	var arena: Node = _find(_main, "TacticsLevel").get("arena")
	_check(arena and arena.grid and arena.grid.dimensions() == Vector2i(10, 20),
		"c'est bien la carte du chapitre 2 qui est montée",
		str(arena.grid.dimensions()) if arena and arena.grid else "aucune grille")

	# --- Et c'est tout l'objet de cette suite ---
	await _check_playable("chapitre 2")


#region Étapes
## Demande la bataille et confirme le placement.
func _open_chapter(label: String) -> bool:
	_main._on_battle_requested()
	for _i in 120:
		await physics_frame

	var level: Node = _find(_main, "TacticsLevel")
	if not level:
		_ko("%s : niveau monté" % label, "aucun TacticsLevel")
		return false

	var runner: Node = level.get_node_or_null("ChapterRunner")
	var phase: Node = runner.get_node_or_null("DeploymentPhase") if runner else null
	if phase and phase.has_method("confirm"):
		phase.confirm()
	for _i in 60:
		await physics_frame

	# Le placement suspend la boucle de tour ; la confirmer doit la rendre.
	# Sans cela la bataille est un décor : rien ne bouge, rien ne répond.
	_check(level.is_physics_processing(),
		"%s : la boucle de tour tourne une fois le placement confirmé" % label)
	return true


## Une unité se laisse-t-elle prendre au clic ?
func _check_playable(label: String) -> void:
	var level: Node = _find(_main, "TacticsLevel")
	var controls: Node = _by_script(_main, "controls.gd")
	if not controls:
		_ko("%s : contrôles montés" % label, "introuvable")
		return

	# L'état d'ouverture, et pas « la référence est-elle valide ? » : en debug,
	# un nœud libéré se lit comme `null`, donc une garde de validité ne
	# distinguerait pas une ressource propre d'une ressource périmée. L'étape,
	# elle, se voit : une bataille qui s'ouvre attend qu'on choisisse une unité,
	# jamais qu'on agisse avec celle d'avant.
	var participant = controls.participant
	_check(participant.stage == participant.STAGE_SELECT_PAWN,
		"%s : la bataille s'ouvre sur un état neuf" % label,
		"étape %d — état de la bataille précédente ?" % participant.stage)

	var stale_camps: int = 0
	for camp: Variant in participant.hostile_camps:
		if not is_instance_valid(camp) or not level.is_ancestor_of(camp):
			stale_camps += 1
	_check(stale_camps == 0,
		"%s : aucun camp d'un autre niveau n'est resté en mémoire" % label,
		"%d camp(s) étranger(s)" % stale_camps)

	var target: Node = null
	for p in level.player.get_children():
		if p is TacticsPawn and p.can_act():
			target = p
			break
	if not target:
		_ko("%s : une unité prête à jouer" % label, "aucune")
		return

	await _click_world(target.global_position)
	var picked = participant.curr_pawn
	_check(picked == target,
		"%s : cliquer une unité la sélectionne (%s)" % [label, target.display_name()],
		"sélection : %s" % (picked.display_name() if is_instance_valid(picked) else "aucune"))
	_check(controls.get_node("HBox/Actions").visible,
		"%s : le menu d'actions s'ouvre" % label)
#endregion


#region Utilitaires
func _click_world(world: Vector3) -> void:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if not cam:
		_ko("Caméra 3D", "introuvable")
		return
	var pos: Vector2 = cam.unproject_position(world)
	Input.warp_mouse(pos)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await physics_frame
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = pos
		click.global_position = pos
		Input.parse_input_event(click)
		await physics_frame
	for _i in 6:
		await physics_frame


func _chapter_id() -> String:
	return _main._chapter.id if _main._chapter else "aucun"


func _campaign_index() -> int:
	var c: Node = _main.get_node_or_null("/root/Campaign")
	return int(c.chapter_index) if c else -1


func _find(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var f: Node = _find(child, wanted)
		if f:
			return f
	return null


func _by_script(node: Node, suffix: String) -> Node:
	var s: Script = node.get_script()
	if s and str(s.resource_path).ends_with(suffix):
		return node
	for child in node.get_children():
		var f: Node = _by_script(child, suffix)
		if f:
			return f
	return null
#endregion


#region Rapport
func _ok(label: String) -> void:
	_passed += 1
	_lines.append("  ✅ %s" % label)
	print("  ✅ %s" % label)


func _ko(label: String, detail: String = "") -> void:
	_failed += 1
	_lines.append("  ❌ %s — %s" % [label, detail])
	print("  ❌ %s — %s" % [label, detail])


func _check(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		_ok(label)
	else:
		_ko(label, detail)
#endregion
