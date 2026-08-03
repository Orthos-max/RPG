extends SceneTree
## Test d'intégration headless : campagne → chapitre chargé → pont CielAI.
## Lancer : godot --headless --path . --script test_battle.gd
##
## Vérifie que la chaîne complète tient debout dans un vrai arbre de scène :
## écran-titre → nouvelle partie → déploiement → niveau chargé → état exporté
## → commande invalide rejetée → commande valide acquittée.

const DIFF = preload("res://data/models/world/ai/difficulty.gd")

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

	var player_pawns: int = _count_pawns(level.player)
	var enemy_pawns: int = _count_pawns(level.opponent)
	_check(player_pawns == 2, "roster appliqué : %d pions joueur (déployés)" % player_pawns,
		"attendu 2")
	_check(enemy_pawns > 0, "camp adverse peuplé : %d pions" % enemy_pawns)

	if runner:
		var snapshot: Dictionary = runner.build_snapshot()
		_check(snapshot["player_units"].size() == player_pawns
				and snapshot["enemy_units"].size() == enemy_pawns,
			"instantané d'objectif cohérent")

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

	main.queue_free()
	await physics_frame


#region Helpers
func _count_pawns(team: Node) -> int:
	if not team or not is_instance_valid(team):
		return 0
	var n: int = 0
	for c in team.get_children():
		if c is TacticsPawn and is_instance_valid(c):
			n += 1
	return n


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
