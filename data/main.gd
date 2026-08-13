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
const SaveScreen = preload("res://data/modules/menu/save_screen.gd")
const CharacterEditor = preload("res://data/modules/menu/character_editor.gd")
const NetMirrorClass = preload("res://data/modules/net/net_mirror.gd")
const ScreenFaderClass = preload("res://data/modules/ui/fader.gd")
const MinimapClass = preload("res://data/modules/ui/minimap.gd")
const BattleHistoryClass = preload("res://data/modules/ui/battle_history.gd")
const BattleSpeedClass = preload("res://data/modules/ui/battle_speed.gd")
const ThreatRangeClass = preload("res://data/modules/ui/threat_range.gd")
const EnemyPeekClass = preload("res://data/modules/ui/enemy_peek.gd")
const GridOverlayClass = preload("res://data/modules/ui/grid_overlay.gd")
const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

const MapEditorScene = preload("res://assets/maps/level/map_editor_level.tscn")
const CustomBattleClass = preload("res://data/modules/campaign/custom_battle.gd")

const SKIRMISH_SCENE: String = "res://assets/maps/level/map_level.tscn"
const SAVE_SLOT: int = 0

## Écran d'interface courant (titre, préparation, résultat)
var _ui: CanvasLayer = null
## Niveau chargé (tactics 3D ou prototype 2D)
var _level: Node = null
## Runner du chapitre en cours (null en escarmouche)
var _runner: ChapterRunner = null
## Chapitre en cours de jeu
var _chapter: ChapterData = null
## Carte du joueur en cours d'essai (null hors éditeur) — sert au retour
var _custom_map: MapDocument = null
## Voile de transition, gardé pour toute la partie (voir [ScreenFader])
var _fader: ScreenFader = null


func _ready() -> void:
	# Avant tout écran, sinon le premier serait le seul à ne pas l'avoir.
	CielTheme.apply_to_tree(get_tree())
	get_tree().node_added.connect(CielTheme.adopt)
	_fader = ScreenFaderClass.attach(self)
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

	_play_music("music_title")

	var screen := TitleScreen.new()
	# Les départs vers un autre écran passent par un fondu ; ce qui reste sur le
	# titre (les options audio) n'en a pas besoin.
	screen.new_game_requested.connect(func(difficulty: int, permadeath: bool) -> void:
		_transition(_on_new_game.bind(difficulty, permadeath)))
	screen.continue_requested.connect(func() -> void: _transition(_on_continue))
	screen.load_requested.connect(func() -> void: show_saves(false))
	screen.ciel_mode_requested.connect(func() -> void: _transition(_on_ciel_skirmish))
	screen.host_requested.connect(func() -> void: show_lobby(true))
	screen.join_requested.connect(func() -> void: show_lobby(false))
	screen.editor_requested.connect(func() -> void: _transition(show_editor.bind(null)))
	screen.character_editor_requested.connect(show_character_editor)
	screen.quit_requested.connect(func() -> void: get_tree().quit())
	_mount_ui(screen)
	_fade_in()


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

	_play_music("music_prep")
	_chapter = campaign.current_chapter()
	var screen := PrepScreen.new()
	screen.chapter = _chapter
	screen.battle_requested.connect(func() -> void: _transition(_on_battle_requested))
	screen.back_requested.connect(func() -> void: _transition(show_title))
	screen.save_requested.connect(func() -> void: show_saves(true))
	_mount_ui(screen)
	_fade_in()


## Éditeur de personnages : créer une recrue, l'enregistrer, l'enrôler.
func show_character_editor() -> void:
	unload_level()
	_clear_ui()
	var screen := CharacterEditor.new()
	screen.back_requested.connect(show_title)
	_mount_ui(screen)


## Écran de sauvegarde (`saving`) ou de chargement.
##
## Charger depuis l'écran-titre enchaîne sur la préparation du chapitre repris ;
## sauvegarder depuis la préparation y revient une fois l'écriture faite.
func show_saves(saving: bool) -> void:
	_clear_ui()
	var screen := SaveScreen.new()
	screen.saving = saving
	screen.back_requested.connect(show_prep if saving else show_title)
	screen.slot_loaded.connect(_on_save_loaded)
	_mount_ui(screen)


## Une partie vient d'être chargée depuis l'écran de chargement.
func _on_save_loaded() -> void:
	var campaign: Node = _campaign()
	var session: Node = _session()
	if campaign and session:
		session.difficulty = campaign.difficulty
		session.chapter_index = campaign.chapter_index
		session.set_mode(session.Mode.SOLO)
	show_prep()


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


## Éditeur de cartes. [param document] reprend une carte en cours d'édition.
func show_editor(document: MapDocument = null) -> void:
	unload_level()
	_clear_ui()
	_leave_network()
	_chapter = null
	_custom_map = null
	_play_music("music_prep")

	# La caméra tactique céderait la vue à l'éditeur, qui a la sienne.
	_enable_3d_camera(false)

	var editor: Node = MapEditorScene.instantiate()
	editor.doc = document
	editor.back_to_menu.connect(show_title)
	editor.play_requested.connect(_on_play_custom_map)

	var world: Node = get_node_or_null("World")
	if world:
		world.add_child(editor)
	else:
		add_child(editor)
	_level = editor

	# Sans ceci, l'éditeur atteint depuis le titre s'ouvre derrière un voile
	# opaque : `_transition` éteint l'écran, et c'est à l'écran d'arrivée de le
	# rallumer. Tous les autres le font (titre, préparation, bataille, bilan) ;
	# celui-ci l'avait oublié, d'où l'écran noir au clic sur « Éditeur de map ».
	_fade_in()


## Essai d'une carte du joueur : elle se joue comme un chapitre.
##
## Rien n'est reporté dans la campagne — ni or, ni XP, ni progression : une
## carte d'essai ne doit pas pouvoir faire avancer une partie en cours.
func _on_play_custom_map(document: MapDocument, with_ciel: bool) -> void:
	var session: Node = _session()
	if session:
		session.set_mode(session.Mode.CIEL if with_ciel else session.Mode.SOLO)
		session.chapter_index = 0

	_custom_map = document
	_chapter = document.to_chapter()
	var level: Node = CustomBattleClass.build(document)
	_load_level("", level)
	# Une fois le niveau dans l'arbre, et pas avant : c'est là que les pions ont
	# des statistiques à recevoir.
	CustomBattleClass.apply_levels(level)


## Écran de fin de bataille (victoire, défaite, fin de campagne).
##
## [param details] Bilan chiffré, `[[libellé, valeur], …]` — tel que
## [method BattleStats.rows] le rend. Vide, l'écran est celui d'avant : un
## titre, un texte, un bouton.
##
## [param extra] Boutons supplémentaires posés à côté de « Continuer »,
## `[[libellé, Callable], …]` — c'est par là que la défaite propose de
## recommencer le chapitre.
func _show_message(title_text: String, body_text: String, next: Callable = Callable(),
		details: Array = [], extra: Array = []) -> void:
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

	# Le récit, puis le bilan, empilés entre le titre et le bouton : sans
	# conteneur, le tableau chiffré aurait fallu positionner à la main sous un
	# texte dont on ne connaît pas la hauteur (l'outro d'un chapitre fait deux
	# lignes, la liste des objectifs autant qu'il y en a).
	var column := VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.offset_left = -360
	column.offset_right = 360
	column.offset_top = 215
	column.offset_bottom = -150  # au-dessus du bouton « Continuer »
	column.add_theme_constant_override("separation", 16)
	layer.add_child(column)

	var body := Label.new()
	body.text = body_text
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	if not details.is_empty():
		column.add_child(_build_summary_table(details))

	# Une barre de boutons plutôt qu'un bouton posé à la main : le second choix
	# n'apparaît que sur certains écrans (la défaite), et deux boutons ancrés
	# chacun de leur côté se décentrent dès qu'il n'y en a qu'un.
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -140
	bar.offset_bottom = -92
	bar.add_theme_constant_override("separation", 16)
	layer.add_child(bar)

	var btn := _message_button("Continuer")
	btn.pressed.connect(func() -> void:
		if next.is_valid():
			next.call()
		else:
			show_title())
	bar.add_child(btn)

	for action: Array in extra:
		var side := _message_button(str(action[0]))
		var callback: Callable = action[1]
		side.pressed.connect(func() -> void:
			if callback.is_valid():
				callback.call())
		bar.add_child(side)

	add_child(layer)
	_ui = layer
	_fade_in()


## Un bouton de la barre d'un écran de message.
func _message_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 48)
	btn.add_theme_font_size_override("font_size", 18)
	return btn


## Tableau du bilan : deux paires « libellé / valeur » par ligne.
##
## Deux colonnes de paires plutôt qu'une : huit lignes empilées auraient repoussé
## le tableau sous le bouton, et la place perdue à droite d'un écran 16/9 se voit.
func _build_summary_table(details: Array) -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.04)
	style.border_color = Color("#f5c842")
	style.border_width_left = 2
	style.set_content_margin_all(16)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	frame.add_theme_stylebox_override("panel", style)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	frame.add_child(grid)

	for row: Array in details:
		var label := Label.new()
		label.text = "%s " % str(row[0])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size = Vector2(150, 0)
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		grid.add_child(label)

		var value := Label.new()
		value.text = str(row[1])
		value.custom_minimum_size = Vector2(110, 0)
		value.add_theme_font_size_override("font_size", 16)
		value.add_theme_color_override("font_color", Color("#f5c842"))
		grid.add_child(value)

	return frame
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


func _on_battle_requested() -> void:
	if not _chapter:
		show_title()
		return
	var session: Node = _session()
	var campaign: Node = _campaign()
	if session and campaign:
		session.chapter_index = campaign.chapter_index
	# Sauvegarde automatique de début de chapitre, prise ici et pas ailleurs :
	# c'est le dernier instant où l'armée est encore intacte — achats faits,
	# déploiement arrêté, pas un coup échangé. C'est de cet instantané que part
	# « Recommencer le chapitre » après une défaite.
	if campaign:
		campaign.autosave_chapter()
	_load_level(_chapter.scene_path)


func _on_chapter_finished(victory: bool, bonuses: Array, reason: String) -> void:
	# Le bilan se prend **avant** tout déchargement : il compte les unités encore
	# en scène et l'XP qu'elles ont gagnée depuis leur entrée en lice.
	var summary: Dictionary = _runner.battle_summary() if _runner else BattleStats.empty()

	# Une carte d'essai ne touche pas à la campagne : ni XP, ni or, ni progression.
	if _custom_map:
		var document: MapDocument = _custom_map
		unload_level()
		_show_message(
			"⚔️ Victoire — %s" % document.name if victory else "💀 Défaite — %s" % document.name,
			"%s\n\nCarte d'essai : rien n'a été reporté dans ta campagne." % reason,
			func() -> void: show_editor(document),
			BattleStats.rows(summary))
		return

	var campaign: Node = _campaign()
	if not campaign or not _runner:
		show_title()
		return

	# Report des PV/XP/niveaux dans le roster persistant.
	for snapshot: Dictionary in _runner.player_unit_snapshots():
		campaign.apply_battle_result(snapshot)

	# Puis l'armée se repose — victoire ou défaite, c'est pareil, et ce n'est pas
	# négociable : il n'y a plus de soin payant à l'intendance. Placé ici, donc
	# avant les `save_game` des deux branches : la sauvegarde tient des unités
	# entières.
	campaign.rest_army()

	var chapter_title: String = _chapter.title if _chapter else "Chapitre"
	var outro: String = "\n".join(_chapter.outro_lines) if _chapter and victory else ""

	if victory:
		var lines: Array = []
		for b: Dictionary in bonuses:
			lines.append("%s %s" % ["✔" if bool(b["achieved"]) else "✘", str(b["label"])])
		# La récompense du chapitre et les primes d'objectifs sont versées ici :
		# c'est l'écart avant/après qui dit ce que la bataille a rapporté, plutôt
		# que le seul total de la bourse.
		var gold_before: int = campaign.gold
		campaign.complete_chapter(bonuses)
		summary["gold_gained"] = campaign.gold - gold_before
		summary["gold"] = campaign.gold
		campaign.save_game(SAVE_SLOT)
		var session: Node = _session()
		if session:
			session.chapter_index = campaign.chapter_index
		_show_message("⚔️ Victoire — %s" % chapter_title,
			"%s\n\n%s\n\nObjectifs secondaires :\n%s" % [
				reason, outro, "\n".join(lines)
			], show_prep, BattleStats.rows(summary))
	else:
		# Défaite : pas un sou de plus, mais la bourse reste affichée — le joueur
		# retentera le chapitre et voudra savoir avec quoi il repart.
		summary["gold"] = campaign.gold
		campaign.save_game(SAVE_SLOT)

		# Recommencer n'est proposé que si l'instantané de début de chapitre est
		# bien celui de *ce* chapitre : un fichier laissé par une autre partie
		# renverrait le joueur ailleurs, et « recommencer » deviendrait un piège.
		var retry: Array = []
		if campaign.has_chapter_autosave(campaign.chapter_index):
			retry.append(["↻ Recommencer le chapitre",
				func() -> void: _transition(_retry_chapter)])

		_show_message("💀 Défaite — %s" % chapter_title,
			"%s\n\nLes unités tombées le restent si la mort permanente est active.\nTu peux retenter le chapitre." % reason,
			show_prep, BattleStats.rows(summary), retry)

	unload_level()


## Relance le chapitre en cours tel qu'il a commencé.
##
## La bataille perdue a déjà tout reporté dans la campagne — morts permanentes,
## blessures, XP — et l'emplacement automatique en porte l'état. Repartir de la
## mémoire vive rejouerait donc le chapitre avec une armée déjà entamée, ce qui
## n'est pas « recommencer ». On relit l'instantané pris à l'entrée en lice
## ([method Campaign.autosave_chapter]) : le roster, l'or et le déploiement d'
## avant le premier coup.
func _retry_chapter() -> void:
	var campaign: Node = _campaign()
	if not campaign or not campaign.restore_chapter():
		_show_message("Reprise impossible",
			"Aucune sauvegarde de début de chapitre n'a été retrouvée.\n"
			+ "Repasse par l'écran de préparation.", show_prep)
		return

	var session: Node = _session()
	if session:
		session.difficulty = campaign.difficulty
		session.chapter_index = campaign.chapter_index
		session.set_mode(session.Mode.SOLO)

	# `_on_battle_requested` recharge le niveau, qui nettoie l'écran de bilan et
	# reprend l'instantané au passage : le chapitre repart de zéro, filet compris.
	_chapter = campaign.current_chapter()
	_on_battle_requested()
#endregion


#region Chargement de niveau
## Charge une bataille.
##
## [param prebuilt] permet de fournir un niveau déjà bâti — c'est le cas d'une
## carte du joueur, montée à la volée par [CustomBattle] plutôt que chargée
## depuis un fichier de scène.
func _load_level(scene_path: String, prebuilt: Node = null) -> void:
	_clear_ui()
	unload_level()

	var scene: PackedScene = load(scene_path) if not prebuilt else null
	if not scene and not prebuilt:
		push_error("[Main] Scène introuvable : %s" % scene_path)
		show_title()
		return

	_play_music("music_battle")
	_enable_3d_camera(true)
	_level = prebuilt if prebuilt else scene.instantiate()
	var world: Node = get_node_or_null("World")
	if world:
		world.add_child(_level)
	else:
		add_child(_level)

	var recorder: Node = get_node_or_null("/root/BattleRecorder")
	if recorder:
		recorder.start_battle({
			"scene": scene_path if not scene_path.is_empty() else "carte du joueur",
			"chapter": _chapter.id if _chapter else "skirmish",
		})

	# Bandeau « à qui de jouer » — vital en réseau, informatif ailleurs.
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

	# Vue d'ensemble du plateau, dans le coin haut-droit (touche M).
	if _level is TacticsLevel and MinimapClass.available():
		var minimap: CanvasLayer = MinimapClass.new()
		minimap.name = "BattleMinimap"
		minimap.level = _level
		_level.add_child(minimap)

	# Historique des coups portés, dans le coin bas-droit (touche H). Monté après
	# `start_battle` : il se branche sur le journal et reprend ce qu'il y trouve.
	if _level is TacticsLevel and BattleHistoryClass.available():
		var history: CanvasLayer = BattleHistoryClass.new()
		history.name = "BattleHistory"
		_level.add_child(history)

	# Accélérateur d'animations (touche X maintenue). Enfant du niveau, donc
	# libéré avec lui : c'est ce qui rend l'échelle de temps à 1× en fin de
	# bataille, quoi qu'il arrive.
	if _level is TacticsLevel and BattleSpeedClass.available():
		var speed: CanvasLayer = BattleSpeedClass.new()
		speed.name = "BattleSpeed"
		_level.add_child(speed)

	# Portée des ennemis (touche C maintenue). Enfant du niveau, donc libéré avec
	# lui : c'est ce qui garantit qu'aucune case ne reste teintée en rouge une fois
	# la bataille finie (voir [BattleThreatRange._exit_tree]).
	if _level is TacticsLevel and ThreatRangeClass.available():
		var threat: CanvasLayer = ThreatRangeClass.new()
		threat.name = "BattleThreatRange"
		threat.level = _level
		_level.add_child(threat)

	# Aperçu d'une unité adverse au survol de la souris — ses stats, et les cases
	# qu'elle peut frapper. Enfant du niveau pour la même raison que la portée
	# ci-dessus : il teinte des cases, et les rend en partant.
	if _level is TacticsLevel and EnemyPeekClass.available():
		var peek: CanvasLayer = EnemyPeekClass.new()
		peek.name = "EnemyPeekPanel"
		peek.level = _level
		_level.add_child(peek)

	# Quadrillage du plateau (touche G). Enfant du niveau lui aussi : il bâtit son
	# maillage sur les tuiles de CETTE arène. L'état, lui, survit d'une bataille à
	# l'autre — il vit dans un statique de la classe, pas dans le nœud.
	if _level is TacticsLevel and GridOverlayClass.available():
		var grid_overlay: Node3D = GridOverlayClass.new()
		grid_overlay.name = "BattleGridOverlay"
		_level.add_child(grid_overlay)

	# En campagne, le runner applique le roster et surveille l'objectif.
	if _chapter and _level is TacticsLevel:
		_runner = ChapterRunnerClass.new()
		_runner.name = "ChapterRunner"
		_runner.setup(_level, _chapter)
		_runner.chapter_finished.connect(_on_chapter_finished)
		_level.add_child(_runner)

	_fade_in()


## Décharge le niveau courant (appelé aussi par le service de combat).
func unload_level() -> void:
	_runner = null
	if _level and is_instance_valid(_level):
		_level.queue_free()
	_level = null

	# L'index de grille est un statique : il survivrait au niveau, en désignant
	# des tuiles qui n'existent plus. Une bataille à la fois, et hors bataille
	# aucune — c'est ce que `BattleGrid.current` doit dire.
	BattleGrid.current = null


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


## Passe d'un écran à l'autre par un fondu au noir.
##
## Le voile s'éteint, **puis** [param change] monte l'écran suivant — qui se
## termine par [method _fade_in] et rallume. Sans écran (tests headless), le
## fondu se résout dans la frame : `change` s'exécute aussitôt, comme avant.
##
## Les écrans, eux, restent synchrones : c'est ici, au moment où le joueur
## clique, que la transition s'insère. `show_prep()` appelé directement — par un
## test, par la fin d'une bataille — monte toujours son écran sur-le-champ.
func _transition(change: Callable) -> void:
	if _fader and is_instance_valid(_fader):
		await _fader.fade_out()
	change.call()


## Rallume l'écran (depuis le noir). Appelé par chaque écran une fois monté.
func _fade_in() -> void:
	if _fader and is_instance_valid(_fader):
		_fader.fade_in()


## Change la musique d'ambiance selon l'écran.
##
## Sans fichier audio, l'appel ne fait rien : le service reste silencieux tant
## que les assets ne sont pas déposés (voir `assets/audio/README.md`).
func _play_music(cue: String) -> void:
	var audio: Node = get_node_or_null("/root/Audio")
	if audio:
		audio.play_music(cue)


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
