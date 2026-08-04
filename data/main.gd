extends Node
## Main — orchestration des écrans de Ciel Emblem.
##
## Écran-titre → préparation du chapitre → bataille → résultat → sauvegarde.
## Les écrans ne se connaissent pas entre eux : ils émettent des signaux, ce
## script décide de la suite. Le mode escarmouche CielAI court-circuite la
## campagne et charge directement une carte.

const TitleScreen = preload("res://data/modules/menu/title_screen.gd")
const PrepScreen = preload("res://data/modules/menu/prep_screen.gd")
const ChapterRunnerClass = preload("res://data/modules/campaign/chapter_runner.gd")
const TurnBanner = preload("res://data/modules/ui/turn_banner.gd")
const LobbyScreen = preload("res://data/modules/menu/lobby_screen.gd")
const NetMirrorClass = preload("res://data/modules/net/net_mirror.gd")
const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

const SKIRMISH_SCENE: String = "res://assets/maps/level/map_level.tscn"
const FE2D_SCENE: String = "res://fe_2d/fe_level.tscn"
const FE2D_EDITOR_SCENE: String = "res://fe_2d/editor/map_editor.tscn"
const SAVE_SLOT: int = 0

## Écran d'interface courant (titre, préparation, résultat)
var _ui: CanvasLayer = null
## Niveau chargé (tactics 3D ou prototype 2D)
var _level: Node = null
## Runner du chapitre en cours (null en escarmouche)
var _runner: ChapterRunner = null
## Chapitre en cours de jeu
var _chapter: ChapterData = null


func _ready() -> void:
	var network: Node = get_node_or_null("/root/Network")
	if network:
		network.battle_started.connect(_on_net_battle_started)
	show_title()


## L'hôte (re)désigne la carte de la bataille.
##
## Au premier lancement c'est le salon qui charge le niveau ; ici on ne traite
## que le cas du retour après coupure — l'invité recharge la carte pour repartir
## d'un miroir propre, que l'état diffusé juste après remplit.
func _on_net_battle_started(map_path: String) -> void:
	var network: Node = get_node_or_null("/root/Network")
	if not network or network.role != 2:  # Role.CLIENT
		return
	if not _level or not is_instance_valid(_level):
		return
	print_rich("[color=cyan]↺ Reprise de la bataille après reconnexion.[/color]")
	_chapter = null
	_load_level(map_path)


#region Écrans
## Affiche l'écran-titre (et décharge ce qui tourne).
func show_title() -> void:
	unload_level()
	_clear_ui()
	_leave_network()

	var screen := TitleScreen.new()
	screen.new_game_requested.connect(_on_new_game)
	screen.continue_requested.connect(_on_continue)
	screen.ciel_mode_requested.connect(_on_ciel_skirmish)
	screen.hotseat_requested.connect(_on_hotseat)
	screen.host_requested.connect(func() -> void: show_lobby(true))
	screen.join_requested.connect(func() -> void: show_lobby(false))
	screen.editor_requested.connect(func() -> void: _load_2d_scene(FE2D_EDITOR_SCENE))
	screen.fe2d_requested.connect(func() -> void: _load_2d_scene(FE2D_SCENE))
	screen.quit_requested.connect(func() -> void: get_tree().quit())
	_mount_ui(screen)


## Alias attendu par le service de combat en fin de bataille.
func _show_menu() -> void:
	show_title()


## Affiche l'écran de préparation du chapitre courant.
func show_prep() -> void:
	unload_level()
	_clear_ui()

	var campaign: Node = _campaign()
	if not campaign:
		show_title()
		return

	if campaign.is_finished():
		_show_message("🏆 Campagne terminée !",
			"Tous les chapitres sont franchis. Merci d'avoir joué.")
		return

	_chapter = campaign.current_chapter()
	var screen := PrepScreen.new()
	screen.chapter = _chapter
	screen.battle_requested.connect(_on_battle_requested)
	screen.back_requested.connect(show_title)
	_mount_ui(screen)


## Salon de partie en ligne : hôte (génère un code) ou invité (saisit un code).
func show_lobby(as_host: bool) -> void:
	unload_level()
	_clear_ui()
	# Une session en cours ne doit pas survivre au changement d'écran :
	# sans cela, un hôte qui repart vers « Rejoindre » laisserait son port ouvert.
	_leave_network()

	var screen := LobbyScreen.new()
	screen.hosting = as_host
	screen.battle_requested.connect(_on_network_battle)
	screen.back_requested.connect(show_title)
	_mount_ui(screen)


## L'hôte a lancé la bataille : les deux machines chargent la même carte.
func _on_network_battle(map_path: String) -> void:
	_chapter = null
	_load_level(map_path)


## Écran de fin de bataille (victoire, défaite, fin de campagne).
func _show_message(title_text: String, body_text: String, next: Callable = Callable()) -> void:
	_clear_ui()

	var layer := CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color("#141026")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f5c842"))
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 160
	title.offset_left = -400
	title.offset_right = 400
	title.offset_bottom = 220
	layer.add_child(title)

	var body := Label.new()
	body.text = body_text
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	body.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	body.offset_top = 230
	body.offset_left = -360
	body.offset_right = 360
	body.offset_bottom = 460
	layer.add_child(body)

	var btn := Button.new()
	btn.text = "Continuer"
	btn.custom_minimum_size = Vector2(240, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	btn.offset_top = -140
	btn.offset_bottom = -92
	btn.offset_left = -120
	btn.offset_right = 120
	btn.pressed.connect(func() -> void:
		if next.is_valid():
			next.call()
		else:
			show_title())
	layer.add_child(btn)

	add_child(layer)
	_ui = layer
#endregion


#region Campagne
func _on_new_game(difficulty: int, permadeath: bool) -> void:
	var campaign: Node = _campaign()
	var session: Node = _session()
	if not campaign or not session:
		return

	campaign.new_game(difficulty, permadeath)
	session.difficulty = difficulty
	session.chapter_index = 0
	session.set_mode(session.Mode.SOLO)
	campaign.save_game(SAVE_SLOT)
	show_prep()


func _on_continue() -> void:
	var campaign: Node = _campaign()
	var session: Node = _session()
	if not campaign or not session:
		return
	if not campaign.load_game(SAVE_SLOT):
		_show_message("Sauvegarde illisible",
			"Impossible de charger la partie. Lance une nouvelle campagne.")
		return
	session.difficulty = campaign.difficulty
	session.chapter_index = campaign.chapter_index
	session.set_mode(session.Mode.SOLO)
	show_prep()


func _on_ciel_skirmish() -> void:
	var session: Node = _session()
	if session:
		session.set_mode(session.Mode.CIEL)
	_chapter = null
	_load_level(SKIRMISH_SCENE)


## Duel local : les deux camps sont joués à la main, sur la même machine (M2).
func _on_hotseat() -> void:
	var session: Node = _session()
	if session:
		session.set_mode(session.Mode.HOTSEAT)
	_chapter = null
	_load_level(SKIRMISH_SCENE)


func _on_battle_requested() -> void:
	if not _chapter:
		show_title()
		return
	var session: Node = _session()
	var campaign: Node = _campaign()
	if session and campaign:
		session.chapter_index = campaign.chapter_index
	_load_level(_chapter.scene_path)


func _on_chapter_finished(victory: bool, bonuses: Array, reason: String) -> void:
	var campaign: Node = _campaign()
	if not campaign or not _runner:
		show_title()
		return

	# Report des PV/XP/niveaux dans le roster persistant.
	for snapshot: Dictionary in _runner.player_unit_snapshots():
		campaign.apply_battle_result(snapshot)

	var chapter_title: String = _chapter.title if _chapter else "Chapitre"
	var outro: String = "\n".join(_chapter.outro_lines) if _chapter and victory else ""

	if victory:
		var lines: Array = []
		for b: Dictionary in bonuses:
			lines.append("%s %s" % ["✔" if bool(b["achieved"]) else "✘", str(b["label"])])
		campaign.complete_chapter(bonuses)
		campaign.save_game(SAVE_SLOT)
		var session: Node = _session()
		if session:
			session.chapter_index = campaign.chapter_index
		_show_message("⚔️ Victoire — %s" % chapter_title,
			"%s\n\n%s\n\nObjectifs secondaires :\n%s\n\nOr : %d" % [
				reason, outro, "\n".join(lines), campaign.gold
			], show_prep)
	else:
		campaign.save_game(SAVE_SLOT)
		_show_message("💀 Défaite — %s" % chapter_title,
			"%s\n\nLes unités tombées le restent si la mort permanente est active.\nTu peux retenter le chapitre." % reason,
			show_prep)

	unload_level()
#endregion


#region Chargement de niveau
func _load_level(scene_path: String) -> void:
	_clear_ui()
	unload_level()

	var scene: PackedScene = load(scene_path)
	if not scene:
		push_error("[Main] Scène introuvable : %s" % scene_path)
		show_title()
		return

	_enable_3d_camera(true)
	_level = scene.instantiate()
	var world: Node = get_node_or_null("World")
	if world:
		world.add_child(_level)
	else:
		add_child(_level)

	var recorder: Node = get_node_or_null("/root/BattleRecorder")
	if recorder:
		recorder.start_battle({
			"scene": scene_path,
			"chapter": _chapter.id if _chapter else "skirmish",
		})

	# Bandeau « à qui de jouer » — vital en hotseat, informatif ailleurs.
	if _level is TacticsLevel:
		var banner: CanvasLayer = TurnBanner.new()
		banner.name = "TurnBanner"
		banner.level = _level
		_level.add_child(banner)

	# Côté invité, la partie n'est qu'un reflet : l'hôte fait autorité.
	var network: Node = get_node_or_null("/root/Network")
	if network and network.role == 2 and _level is TacticsLevel:  # Role.CLIENT
		var mirror := NetMirrorClass.new()
		mirror.name = "NetMirror"
		mirror.level = _level
		_level.add_child(mirror)

	# En campagne, le runner applique le roster et surveille l'objectif.
	if _chapter and _level is TacticsLevel:
		_runner = ChapterRunnerClass.new()
		_runner.name = "ChapterRunner"
		_runner.setup(_level, _chapter)
		_runner.chapter_finished.connect(_on_chapter_finished)
		_level.add_child(_runner)


func _load_2d_scene(scene_path: String) -> void:
	_clear_ui()
	unload_level()
	_enable_3d_camera(false)
	var scene: PackedScene = load(scene_path)
	if not scene:
		push_error("[Main] Scène introuvable : %s" % scene_path)
		show_title()
		return
	_level = scene.instantiate()
	add_child(_level)


## Décharge le niveau courant (appelé aussi par le service de combat).
func unload_level() -> void:
	_runner = null
	if _level and is_instance_valid(_level):
		_level.queue_free()
	_level = null


func _enable_3d_camera(enabled: bool) -> void:
	var cam: Node = get_node_or_null("Camera/TacticsCamera")
	if not cam:
		return
	var cam3d: Node = cam.get_node_or_null("TwistPivot/PitchPivot/Camera3D")
	if cam3d and cam3d is Camera3D:
		cam3d.current = enabled
#endregion


#region Utilitaires
func _mount_ui(control: Control) -> void:
	var layer := CanvasLayer.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(control)
	add_child(layer)
	_ui = layer


func _clear_ui() -> void:
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


func _campaign() -> Node:
	return get_node_or_null("/root/Campaign")


func _session() -> Node:
	return get_node_or_null("/root/GameSession")


## Ferme proprement une éventuelle partie en ligne.
func _leave_network() -> void:
	var network: Node = get_node_or_null("/root/Network")
	if network and network.is_online():
		network.leave()


func _input(event: InputEvent) -> void:
	# Échap pendant une bataille : retour à l'écran-titre.
	if event.is_action_pressed("ui_cancel") and _level:
		show_title()
#endregion
