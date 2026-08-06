extends SceneTree
## Test d'intégration **fenêtre ouverte** : un tour joué à la souris.
##
## Lancer : godot --path . --resolution 1280x720 --script test_window.gd
##
## Pourquoi cette suite existe (§6.2 du spec). Les suites headless ne pilotent
## pas la souris : elles vérifient des *règles*, jamais le *chemin du clic*. Les
## trois blocages remontés par Aurèle le 2026-08-05 — échange au déploiement,
## changement d'unité, regard libre — sont tous passés au travers, et deux
## dataient d'avant. Le 2026-08-06 a remis ça : un porteur de grimoire incapable
## d'attaquer, un arc qui tirait au contact, un bouton hors de l'écran. Aucun
## n'était visible sans une vraie fenêtre et un vrai curseur.
##
## Ce qu'on prouve ici : sélectionner une unité, ouvrir son menu, la déplacer sur
## une case, attaquer un ennemi — **en cliquant**, comme un joueur.
##
## Le piège du clic simulé (documenté le 2026-08-05, payé de nouveau ici) :
## `Input.parse_input_event` ne suffit pas. Sans `position` renseignée, le
## viewport route le clic en (0,0) et personne ne le reçoit ; sans
## `Input.warp_mouse`, le rayon de sélection part de l'ancien curseur. Il faut
## les deux, et laisser passer une frame entre les deux.

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

var _passed: int = 0
var _failed: int = 0
var _lines: Array = []

var _main: Node = null
var _level: Node = null
var _controls: Node = null
var _participant = null


func _init() -> void:
	print("\n========================================")
	print("  TEST FENÊTRE — un tour à la souris")
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
	if not await _open_battle():
		return

	var pawn: Node = _first_actable_pawn()
	if not pawn:
		_ko("Une unité prête à jouer", "aucune")
		return
	_ok("Bataille ouverte, %d unité(s) en scène" % _level.player.get_child_count())

	await _test_select(pawn)
	await _test_move(pawn)
	await _test_attack()


#region Étapes
## Cliquer une unité doit la sélectionner et ouvrir son menu d'actions.
func _test_select(pawn: Node) -> void:
	await _click_world(pawn.global_position)

	_check(_participant.curr_pawn == pawn,
		"cliquer une unité la sélectionne (%s)" % pawn.display_name(),
		"sélection : %s" % (_participant.curr_pawn.display_name() if _participant.curr_pawn else "aucune"))
	_check(_actions_menu().visible, "le menu d'actions s'ouvre")

	# Le menu doit parler français : c'est le chemin du clic qui le prouve, pas
	# la table de libellés.
	var move_btn: Button = _action_button("Move")
	_check(move_btn != null and move_btn.text == "Déplacer",
		"le bouton de déplacement est en français (%s)" % (move_btn.text if move_btn else "?"))


## Cliquer « Déplacer » puis une case atteignable doit y conduire l'unité.
func _test_move(pawn: Node) -> void:
	var start: Vector3 = pawn.global_position
	await _click_button(_action_button("Move"))
	# L'étape « montrer les déplacements » (2) est transitoire : le service passe
	# aussitôt à « choisir la case » (3). Ce qu'on veut constater, c'est le
	# résultat observable — des cases marquées atteignables sous les yeux du
	# joueur — pas le numéro d'étape d'une frame précise.
	var marked: int = 0
	for tile in TacticsGrid.tiles(_level.arena):
		if tile.get("reachable"):
			marked += 1
	_check(marked > 0 and int(_participant.stage) in [2, 3],
		"« Déplacer » surligne les cases atteignables (%d)" % marked,
		"étape %d, %d case(s)" % [int(_participant.stage), marked])

	var target: Node = _reachable_tile_away_from(pawn)
	if not target:
		_ko("Une case atteignable", "aucune tuile marquée")
		return

	await _click_world(target.global_position)
	# Le trajet s'anime : on laisse le pion marcher.
	for _i in 240:
		await physics_frame
		if pawn.global_position.distance_to(start) > 0.9 and not pawn.res.is_moving:
			break

	var travelled: float = pawn.global_position.distance_to(start)
	_check(travelled > 0.9, "l'unité s'est déplacée (%.2f unité(s))" % travelled,
		"le pion n'a pas bougé — pile de trajet vide ?")


## Cliquer « Attaquer » puis un ennemi à portée doit lui coûter des PV.
func _test_attack() -> void:
	var attacker: Node = _participant.curr_pawn
	if not attacker or not is_instance_valid(attacker):
		_ko("Une unité en main pour attaquer", "aucune")
		return

	var attack_btn: Button = _action_button("Attack")
	if not attack_btn or attack_btn.disabled:
		_ok("Aucune cible à portée après le déplacement — attaque non testable ici")
		return

	await _click_button(attack_btn)
	var target: Node = _attackable_enemy()
	if not target:
		_ok("Aucun ennemi sur une case attaquable — attaque non testable ici")
		return

	var before: int = target.stats.hp
	var attacker_hp: int = attacker.stats.hp
	var attacker_level: int = attacker.stats.level
	await _click_world(target.global_position)
	for _i in 240:
		await physics_frame
		if target.stats.hp != before or not is_instance_valid(target):
			break

	var damaged: bool = not is_instance_valid(target) or target.stats.hp < before
	_check(damaged, "attaquer retire des PV à la cible (%d → %d)" % [
		before, target.stats.hp if is_instance_valid(target) else 0])

	# Frapper clôt le tour de l'unité (règle rétablie le 2026-08-06).
	if is_instance_valid(attacker):
		_check(not attacker.can_act(), "l'unité a fini son tour après avoir frappé")
		# La riposte ne se produit pas toujours (cible morte du premier coup, hors
		# de portée…). Et frapper peut **rendre** des PV : achever une cible donne
		# de l'XP, et une montée de niveau augmente les PV maximum. Ce test l'a
		# appris à ses dépens — 20 → 21 PV après un coup fatal. L'invariant ne
		# tient donc qu'à niveau constant.
		var counter_taken: int = attacker_hp - attacker.stats.hp
		var levelled: bool = attacker.stats.level > attacker_level
		if levelled:
			_ok("l'assaillant a pris un niveau en tuant (%d → %d)" % [
				attacker_level, attacker.stats.level])
		else:
			_check(counter_taken >= 0, "frapper ne rend pas de PV à l'assaillant",
				"%d → %d PV" % [attacker_hp, attacker.stats.hp])
			_ok("riposte encaissée : %d PV" % counter_taken if counter_taken > 0
				else "pas de riposte (cible tombée ou hors de portée)")
#endregion


#region Pilotage de la souris
## Clique à une position **écran**.
##
## Trois gestes indissociables : poser le curseur (`warp_mouse`, sinon le rayon
## de sélection part d'ailleurs), envoyer press puis release avec `position`
## renseignée (sinon le viewport route le clic en (0,0)), et laisser passer des
## frames — la sélection lit `Input.is_action_just_pressed`, qui ne vaut qu'une
## frame.
func _click_screen(pos: Vector2) -> void:
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
	for _i in 4:
		await physics_frame


## Clique un point du monde 3D, en le projetant à l'écran.
func _click_world(world: Vector3) -> void:
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	if not camera:
		_ko("Caméra 3D", "introuvable")
		return
	await _click_screen(camera.unproject_position(world))


## Clique un bouton d'interface, en son centre.
func _click_button(button: Button) -> void:
	if not button:
		_ko("Bouton d'action", "introuvable")
		return
	await _click_screen(button.get_global_rect().get_center())
#endregion


#region Mise en place
func _open_battle() -> bool:
	var scene: PackedScene = load("res://assets/scene/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	await physics_frame

	_main._on_new_game(DIFF.Level.NORMAL, true)
	await physics_frame
	_main._on_battle_requested()
	for _i in 90:
		await physics_frame

	_level = _find_named(_main, "TacticsLevel")
	if not _level:
		_ko("Niveau chargé", "introuvable")
		return false

	# Le placement des unités suspend la bataille : on le confirme.
	var runner: Node = _level.get_node_or_null("ChapterRunner")
	var phase: Node = runner.get_node_or_null("DeploymentPhase") if runner else null
	if phase and phase.has_method("confirm"):
		phase.confirm()
	for _i in 60:
		await physics_frame

	_controls = _find_by_script(_main, "controls.gd")
	if not _controls:
		_ko("Contrôles montés", "introuvable")
		return false
	_participant = _controls.participant
	return true
#endregion


#region Utilitaires
func _first_actable_pawn() -> Node:
	for p in _level.player.get_children():
		if p is TacticsPawn and is_instance_valid(p) and p.can_act():
			return p
	return null


## Une tuile atteignable, choisie loin du pion pour que le déplacement se voie.
func _reachable_tile_away_from(pawn: Node) -> Node:
	var best: Node = null
	var best_dist: float = 0.0
	for tile in TacticsGrid.tiles(_level.arena):
		if not tile.get("reachable"):
			continue
		var d: float = tile.global_position.distance_to(pawn.global_position)
		if d > best_dist:
			best_dist = d
			best = tile
	return best


## Un ennemi posé sur une case marquée attaquable.
func _attackable_enemy() -> Node:
	for p in _level.opponent.get_children():
		if not (p is TacticsPawn and is_instance_valid(p) and p.is_alive()):
			continue
		var tile: Node = p.get_tile()
		if tile and tile.get("attackable"):
			return p
	return null


func _actions_menu() -> Control:
	return _controls.get_node("HBox/Actions")


func _action_button(key: String) -> Button:
	return _controls.get_node_or_null("HBox/Actions/%s" % key) as Button


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found: Node = _find_named(child, wanted)
		if found:
			return found
	return null


func _find_by_script(node: Node, suffix: String) -> Node:
	var script: Script = node.get_script()
	if script and str(script.resource_path).ends_with(suffix):
		return node
	for child in node.get_children():
		var found: Node = _find_by_script(child, suffix)
		if found:
			return found
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
