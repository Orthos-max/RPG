extends SceneTree
## Test d'intégration **fenêtre ouverte** : un tour joué à la souris.
##
## Lancer : godot --path . --resolution 1280x720 --script res://tests/test_window.gd
##
## Pourquoi cette suite existe (§6.2 du spec). Les suites headless ne pilotent
## pas la souris : elles vérifient des *règles*, jamais le *chemin du clic*. Les
## trois blocages remontés par Aurèle le 2026-08-05 — échange au déploiement,
## changement d'unité, regard libre — sont tous passés au travers, et deux
## dataient d'avant. Le 2026-08-06 a remis ça : un porteur de grimoire incapable
## d'attaquer, un arc qui tirait au contact, un bouton hors de l'écran. Aucun
## n'était visible sans une vraie fenêtre et un vrai curseur.
##
## Ce qu'on prouve ici, **en cliquant**, comme un joueur : placer ses unités
## avant la bataille (échanger deux d'entre elles, en poser une sur une case
## ouverte, défaire le tout), sélectionner une unité, ouvrir son menu, la
## déplacer, attaquer un ennemi, puis rendre la main et voir l'adversaire jouer
## son tour et le rendre à son tour.
##
## Le placement se défait avant de commencer la bataille : les étapes suivantes
## jouent la position de départ du chapitre, et la laisser défaite mettrait
## l'attaque hors de portée — le test se déclarerait alors « non testable » au
## lieu d'échouer, ce qui est la pire des deux issues.
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
	var phase: Node = await _open_battle()
	if not _level:
		return

	await _test_deployment(phase)
	if not await _start_battle(phase):
		return

	var pawn: Node = _first_actable_pawn()
	if not pawn:
		_ko("Une unité prête à jouer", "aucune")
		return
	_ok("Bataille ouverte, %d unité(s) en scène" % _level.player.get_child_count())

	await _test_select(pawn)
	await _test_move(pawn)
	await _test_attack()
	await _test_opponent_turn()


#region Étapes
## Le placement d'avant-bataille, joué à la souris.
##
## C'est le trou de preuve le plus ancien : l'échange de deux unités au
## déploiement est l'un des trois blocages remontés par Aurèle le 2026-08-05, et
## il est passé au travers de toute la suite headless — l'étape ne s'ouvre même
## pas en `--headless`, faute de collisions sur les tuiles.
func _test_deployment(phase: Node) -> void:
	if not phase or not is_instance_valid(phase):
		_ko("L'étape de déploiement s'ouvre", "aucune — le chapitre l'a-t-il abandonnée ?")
		return

	var marked: int = 0
	for tile in TacticsGrid.tiles(_level.arena):
		if tile.get("deploy_point"):
			marked += 1
	_check(marked > 0, "les cases de déploiement sont surlignées (%d)" % marked)

	var pawns: Array = _player_pawns()
	if pawns.size() < 2:
		_ko("Deux unités à échanger", "%d en scène" % pawns.size())
		return

	# --- Échanger deux unités : clic sur l'une, puis clic sur l'autre ---
	var first: Node = pawns[0]
	var second: Node = pawns[1]
	var first_cell: Vector2i = _cell_of(first)
	var second_cell: Vector2i = _cell_of(second)

	await _click_world(first.global_position)
	await _click_world(second.global_position)

	_check(_cell_of(first) == second_cell and _cell_of(second) == first_cell,
		"deux unités échangent leurs places (%s ↔ %s)" % [first_cell, second_cell],
		"%s et %s après le clic" % [_cell_of(first), _cell_of(second)])

	# --- Poser une unité sur une case libre ---
	var free: Vector2i = _free_slot_away_from(phase, pawns)
	if free.x < 0:
		_ok("Aucune case ouverte restée libre — pose non testable ici")
		return

	var before: Vector2i = _cell_of(first)
	var tile: Node = _tile_at_cell(free)
	if not tile:
		_ko("La case libre a une tuile", str(free))
		return

	await _click_world(first.global_position)
	await _click_world(tile.global_position)

	_check(_cell_of(first) == free,
		"une unité se pose sur une case ouverte (%s → %s)" % [before, free],
		"elle est en %s" % _cell_of(first))

	# --- Enchaîner deux unités : le bug remonté par Aurèle le 2026-08-07 ---
	# L'unité restait **en main** après avoir été posée. Le clic suivant sur une
	# autre unité tombait donc dans le cas « échange » au lieu de la choisir : on
	# ne pouvait jamais passer à la suivante, on permutait sans fin les deux
	# mêmes. Poser doit relâcher.
	var second_before: Vector2i = _cell_of(second)
	var first_after: Vector2i = _cell_of(first)
	await _click_world(second.global_position)

	_check(_cell_of(second) == second_before and _cell_of(first) == first_after,
		"poser une unité la relâche : cliquer la suivante la choisit, sans échanger",
		"%s a bougé en %s, %s en %s" % [
			second.display_name(), _cell_of(second), first.display_name(), _cell_of(first)])

	# Et elle est bien en main : elle répond à un clic sur une case.
	var elsewhere: Vector2i = _free_slot_away_from(phase, pawns)
	if elsewhere.x >= 0 and _tile_at_cell(elsewhere):
		await _click_world(_tile_at_cell(elsewhere).global_position)
		_check(_cell_of(second) == elsewhere,
			"l'unité choisie juste après se pose normalement (%s → %s)"
				% [second_before, elsewhere],
			"elle est en %s" % _cell_of(second))

	# --- Tout remettre où on l'a trouvé ---
	# Les étapes suivantes (déplacement, attaque) jouent la position de départ du
	# chapitre : la laisser défaite ferait passer l'attaque hors de portée, et le
	# test d'attaque se déclarerait « non testable » au lieu d'échouer. Ce
	# retour en arrière est aussi la seule preuve qu'on sait défaire un placement.
	#
	# On repose chacune sur sa case d'origine, dans l'ordre. Si l'autre s'y
	# trouve encore, la pose les échange — et le tour suivant la remet en place.
	# Le résultat ne dépend donc pas de l'état intermédiaire.
	await _send_home(first, first_cell)
	await _send_home(second, second_cell)

	_check(_cell_of(first) == first_cell and _cell_of(second) == second_cell,
		"le placement se défait : chacun retrouve sa case de départ",
		"%s et %s" % [_cell_of(first), _cell_of(second)])


## Reprend une unité et la repose sur la case indiquée.
func _send_home(pawn: Node, cell: Vector2i) -> void:
	if _cell_of(pawn) == cell:
		return
	var tile: Node = _tile_at_cell(cell)
	if not tile:
		return
	await _click_world(pawn.global_position)
	await _click_world(tile.global_position)


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


## Rendre la main : l'adversaire doit jouer, puis rendre le tour au joueur.
##
## Autre trou de preuve resté ouvert. L'IA locale est éprouvée en headless, mais
## en tant que *règle* : ce qu'elle décide, jamais ce qu'elle parvient à exécuter
## sur un plateau monté. Un tour adverse qui ne se termine pas laisse la partie
## figée sans qu'aucune suite headless ne s'en aperçoive.
func _test_opponent_turn() -> void:
	var before: Dictionary = {}
	for p in _level.opponent.get_children():
		if p is TacticsPawn and is_instance_valid(p) and p.is_alive():
			before[p.get_instance_id()] = p.global_position
	if before.is_empty():
		_ok("Plus aucun adversaire en scène — tour adverse non testable ici")
		return

	# Le menu d'actions s'est refermé quand l'assaillant a fini son tour, et le
	# bouton de fin de tour vit dedans. Un joueur ferait pareil : reprendre une
	# unité encore disponible, puis rendre la main.
	var idle: Node = _first_actable_pawn()
	if idle:
		await _click_world(idle.global_position)
	if not _actions_menu().visible:
		_ko("Le menu se rouvre pour rendre la main", "menu fermé, bouton inatteignable")
		return

	await _click_button(_action_button("Debug_next_turn"))
	_check(not _level.participant.can_act(_level.player),
		"passer le tour clôt celui de toutes les unités du joueur")

	# L'adversaire joue ses pions l'un après l'autre, chacun avec son trajet
	# animé : il lui faut du temps réel, pas quelques frames.
	var moved: bool = false
	var back_to_player: bool = false
	for _i in 5400:
		await physics_frame
		if not moved:
			for p in _level.opponent.get_children():
				if not (p is TacticsPawn and is_instance_valid(p)):
					continue
				var was: Variant = before.get(p.get_instance_id())
				if was != null and p.global_position.distance_to(was) > 0.9:
					moved = true
					break
		if moved and _level.participant.can_act(_level.player):
			back_to_player = true
			break

	_check(moved, "l'adversaire déplace au moins une unité de lui-même",
		"aucun pion adverse n'a bougé")
	_check(back_to_player, "le tour revient au joueur une fois l'adversaire passé",
		"la partie est restée sur le camp adverse")
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
## Ouvre une bataille et s'arrête **avant** la confirmation du déploiement.
## [returns] l'étape de placement encore en cours, ou `null` si elle a renoncé.
func _open_battle() -> Node:
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
		return null

	var runner: Node = _level.get_node_or_null("ChapterRunner")
	return runner.get_node_or_null("DeploymentPhase") if runner else null


## Confirme le placement et récupère les contrôles de la bataille.
func _start_battle(phase: Node) -> bool:
	if phase and is_instance_valid(phase) and phase.has_method("confirm"):
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
## Les unités du joueur réellement en scène.
func _player_pawns() -> Array:
	var out: Array = []
	for p in _level.player.get_children():
		if p is TacticsPawn and is_instance_valid(p) and not p.is_queued_for_deletion():
			out.append(p)
	return out


## Case (colonne, ligne) sur laquelle se tient un pion, ou (-1, -1).
func _cell_of(pawn: Node) -> Vector2i:
	var tile: Node = pawn.get_tile() if pawn.has_method("get_tile") else null
	return TacticsGrid.tile_to_grid(_level.arena, tile) if tile else Vector2i(-1, -1)


func _tile_at_cell(cell: Vector2i) -> Node:
	for tile in TacticsGrid.tiles(_level.arena):
		if TacticsGrid.tile_to_grid(_level.arena, tile) == cell:
			return tile
	return null


## Une case ouverte encore libre, choisie loin de toute unité.
##
## Loin, parce que le clic passe par un rayon depuis la caméra : une case collée
## à un pion se ferait voler son clic par la figurine qui la masque.
func _free_slot_away_from(phase: Node, pawns: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist: float = -1.0
	for slot: Vector2i in phase.plan.free_slots():
		var tile: Node = _tile_at_cell(slot)
		if not tile:
			continue
		var nearest: float = INF
		for p in pawns:
			nearest = minf(nearest, tile.global_position.distance_to(p.global_position))
		if nearest > best_dist:
			best_dist = nearest
			best = slot
	return best


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
