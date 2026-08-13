class_name MapEditorLevel
extends Node3D
## Éditeur de cartes en jeu : dessiner un terrain, poser des armées, jouer.
##
## Tout l'état tient dans un [MapDocument] — ce nœud n'est qu'une vue : il
## dessine le document en 3D, traduit les clics en modifications, et rend la
## main. Les règles (ce qui est posable, ce qui rend une carte jouable) vivent
## dans le document, où elles se testent sans ouvrir de fenêtre.
##
## Les cartes sont enregistrées dans `user://maps/` ([MapLibrary]) : le contenu
## du jeu est en lecture seule une fois installé, une carte écrite dans `res://`
## serait perdue à la première mise à jour — ou impossible à écrire.

signal back_to_menu()
## Le joueur veut jouer la carte en cours ([param with_ciel] : camp adverse à Ciel)
signal play_requested(doc: MapDocument, with_ciel: bool)

const UI = preload("res://data/modules/map_editor/map_editor_ui.gd")
const LIBRARY = preload("res://data/services/campaign/map_library.gd")
const MapDataClass = preload("res://data/models/world/map/map_data.gd")

## Épaisseur minimale d'une tuile plate, pour qu'elle reste visible
const MIN_THICKNESS: float = 0.08
## Pas d'élévation d'un clic
const HEIGHT_STEP: float = 0.25

## Carte en cours d'édition
var doc: MapDocument = null

## États successifs de la carte : tout geste qui la modifie s'annule
var _history: MapHistory = null
var _ui: MapEditorUI = null
var _tiles: Dictionary = {}       ## "col,row" → StaticBody3D
var _markers: Node3D = null
var _tool: int = UI.Tool.GRASS
var _unit_paths: Dictionary = {"player": "", "opponent": ""}
## Niveau donné aux prochaines unités posées — un réglage du pinceau.
var _unit_level: int = 1


## Côté du pinceau de terrain, en cases.
var _brush: int = 1


## Le clic peint-il toute la zone d'un seul tenant ?
var _fill: bool = false

# Un trait de pinceau : tout ce qu'un bouton enfoncé peint sans le relâcher.
#
# Peindre au clic-à-clic était le vrai coût de l'éditeur — une rivière de vingt
# cases valait vingt clics. Un trait ne compte que pour **un** coup d'annulation,
# et ne redessine le décor qu'une fois relâché : sans quoi une carte de 32 × 24
# recalculerait ses huit cents cases à chaque pixel parcouru par la souris.
var _stroke_active: bool = false


var _stroke_changed: bool = false


var _stroke_cells: Dictionary = {}

# Caméra orbitale
var _cam_yaw: float = -30.0
var _cam_pitch: float = -50.0
var _cam_dist: float = 14.0
var _cam_target: Vector3 = Vector3.ZERO
var _orbiting: bool = false
var _panning: bool = false
var _mouse_prev: Vector2 = Vector2.ZERO


func _ready() -> void:
	if not doc:
		doc = MapDocument.create_empty("Ma carte", Vector2i(16, 10))
	_unit_paths["player"] = _first_unit_of(MapDocument.TEAM_PLAYER)
	_unit_paths["opponent"] = _first_unit_of(MapDocument.TEAM_OPPONENT)
	_history = MapHistory.started_on(doc.to_dict())

	_build_environment()
	_build_camera()
	_build_ui()
	_ui.show_brush(_brush)
	_rebuild_all()
	_refresh_feedback("Carte « %s » — choisis un outil et dessine sur la grille "
		% doc.name + "(le bouton reste enfoncé : le pinceau suit la souris).")


## Unité proposée d'emblée pour un camp, ou "" si ce camp n'en a aucune.
##
## Le roster se lit sur le disque, et rien ne garantit qu'il rende quelque chose :
## un dossier de fiches introuvable dans une build installée suffirait. La
## première entrée était prise sans regarder, ce qui faisait tomber l'éditeur à
## l'ouverture — jamais en développement, où les fiches sont là. Le reste du code
## sait déjà quoi faire d'un chemin vide : [method MapDocument.place_unit] refuse
## poliment, et le sélecteur d'unité annonce un camp sans unité.
func _first_unit_of(team: String) -> String:
	var roster: Array = UI.roster_of(team)
	return str(roster[0]["path"]) if not roster.is_empty() else ""


#region Construction de la scène
func _build_environment() -> void:
	# Même ciel, même lumière et mêmes ombres qu'en bataille : dessiner une carte
	# qui ne ressemble pas à ce qu'on jouera n'aurait aucun intérêt.
	TacticsScenery.apply_to(self)

	_markers = Node3D.new()
	_markers.name = "EditorMarkers"
	add_child(_markers)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "EditorCamera"
	cam.current = true
	add_child(cam)
	_refresh_camera()


func _build_ui() -> void:
	_ui = UI.new()
	_ui.name = "EditorUI"
	add_child(_ui)

	_ui.tool_selected.connect(_on_tool_selected)
	_ui.brush_size_changed.connect(_on_brush_size)
	_ui.fill_mode_changed.connect(_on_fill_mode)
	_ui.unit_picked.connect(_on_unit_picked)
	_ui.unit_level_changed.connect(func(level: int) -> void: _unit_level = level)
	_ui.export_requested.connect(_on_export)
	_ui.import_requested.connect(_on_import)
	_ui.save_requested.connect(_on_save)
	_ui.load_requested.connect(_on_load)
	_ui.delete_requested.connect(_on_delete)
	_ui.new_requested.connect(_on_new)
	_ui.test_requested.connect(_on_test)
	_ui.settings_requested.connect(func() -> void:
		_ui.open_settings(doc.name, doc.deploy_slots, doc.objective, doc.grid_size))
	_ui.settings_changed.connect(_on_settings)
	_ui.undo_requested.connect(_on_undo)
	_ui.redo_requested.connect(_on_redo)
	_ui.back_requested.connect(func() -> void: back_to_menu.emit())
#endregion


#region Rendu de la carte
## Reconstruit toute la grille (chargement, nouvelle carte, redimensionnement).
func _rebuild_all() -> void:
	for key: String in _tiles:
		var body: Node = _tiles[key]
		if is_instance_valid(body):
			# Sortir de l'arbre avant de libérer : un nœud seulement `queue_free`
			# garde son nom jusqu'à la fin de la frame, et les nouvelles tuiles
			# hériteraient d'un nom maquillé (« @Tile_4_4@31 ») — or c'est le nom
			# qui dit quelle case a été cliquée ([method _pos_of_body]).
			remove_child(body)
			body.queue_free()
	_tiles.clear()

	for row: int in doc.grid_size.y:
		for col: int in doc.grid_size.x:
			var pos := Vector2i(col, row)
			var body: StaticBody3D = _make_tile(pos)
			add_child(body)
			_tiles[_key(pos)] = body

	_cam_target = Vector3.ZERO
	_refresh_camera()
	_rebuild_props()
	_rebuild_markers()


func _make_tile(pos: Vector2i) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Tile_%d_%d" % [pos.x, pos.y]
	body.collision_layer = 1

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BoxMesh.new()
	body.add_child(mesh_instance)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = BoxShape3D.new()
	body.add_child(shape)

	_apply_tile(body, pos)
	return body


## Met une tuile à jour : taille, position, couleur — sans toucher au reste.
func _apply_tile(body: StaticBody3D, pos: Vector2i) -> void:
	var height: float = doc.height_at(pos)
	var thickness: float = maxf(absf(height), MIN_THICKNESS)
	var size := Vector3(doc.tile_size * 0.98, thickness, doc.tile_size * 0.98)

	var mesh_instance: MeshInstance3D = body.get_node("Mesh")
	(mesh_instance.mesh as BoxMesh).size = size
	((body.get_node("Shape") as CollisionShape3D).shape as BoxShape3D).size = size

	body.position = _tile_center(pos, height)

	# Matériau partagé du terrain (grain compris) : celui de la bataille,
	# variante de case comprise — ce qu'on dessine ici est ce qu'on jouera.
	var terrain: int = doc.terrain_at(pos)
	mesh_instance.material_override = TacticsScenery.terrain_material_at(
		terrain, pos, height)


## Redessine le décor : arbres, rochers, créneaux, comme en bataille.
##
## L'éditeur décrit ses cases lui-même — ses tuiles sont des corps nus, sans le
## script qui porte le terrain en bataille. Le calcul de la garniture, lui, reste
## celui de [TacticsProps] : ce qu'on dessine ici est ce qu'on jouera.
func _rebuild_props() -> void:
	var cells: Array = []
	for row: int in doc.grid_size.y:
		for col: int in doc.grid_size.x:
			var pos := Vector2i(col, row)
			var height: float = doc.height_at(pos)
			var thickness: float = maxf(absf(height), MIN_THICKNESS)
			var center: Vector3 = _tile_center(pos, height)
			cells.append({
				"cell": pos,
				"terrain": doc.terrain_at(pos),
				"top": Vector3(center.x, center.y + thickness / 2.0, center.z),
			})
	TacticsProps.build(self, cells, doc.tile_size)
	TacticsDecor.build(self, cells, doc.tile_size)


## Redessine les repères posés sur la carte : unités, zone de départ, point à prendre.
func _rebuild_markers() -> void:
	for child in _markers.get_children():
		_markers.remove_child(child)
		child.queue_free()

	for tile: Variant in doc.deploy_tiles:
		var pos := Vector2i(int(tile[0]), int(tile[1]))
		_markers.add_child(_flat_marker(pos, Color("#27d9c5")))

	var seize: Vector2i = doc.seize_point()
	if doc.in_bounds(seize):
		_markers.add_child(_flat_marker(seize, Color("#f5c842")))

	for unit: Dictionary in doc.units:
		_markers.add_child(_unit_marker(unit))


## Pastille posée à plat sur une case (zone de départ, point de commandement).
func _flat_marker(pos: Vector2i, color: Color) -> Node3D:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = doc.tile_size * 0.42
	mesh.bottom_radius = doc.tile_size * 0.42
	mesh.height = 0.04
	marker.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = material

	var height: float = doc.height_at(pos)
	marker.position = _tile_center(pos, height) + Vector3(0, height / 2.0 + 0.04, 0)
	return marker


## Jeton d'unité : couleur du camp, nom lisible au-dessus.
func _unit_marker(unit: Dictionary) -> Node3D:
	var pos := Vector2i(int(unit.get("col", 0)), int(unit.get("row", 0)))
	var is_player: bool = str(unit.get("team", "")) == MapDocument.TEAM_PLAYER

	var root := Node3D.new()
	root.position = _tile_center(pos, doc.height_at(pos)) \
		+ Vector3(0, doc.height_at(pos) / 2.0, 0)

	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 1.1
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#2d6a4f") if is_player else Color("#b71c1c")
	body.material_override = material
	body.position = Vector3(0, 0.6, 0)
	root.add_child(body)

	var label := Label3D.new()
	label.text = MapDocument.unit_display_name(str(unit.get("path", "")))
	label.font_size = 48
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("#e8e6f0") if is_player else Color("#ffb3b3")
	label.position = Vector3(0, 1.4, 0)
	root.add_child(label)
	return root


## Centre monde d'une tuile (même formule que l'arène de jeu).
func _tile_center(pos: Vector2i, height: float) -> Vector3:
	var half := Vector2(float(doc.grid_size.x) / 2.0, float(doc.grid_size.y) / 2.0)
	return Vector3(
		(float(pos.x) - half.x + 0.5) * doc.tile_size,
		height / 2.0,
		(float(pos.y) - half.y + 0.5) * doc.tile_size
	)
#endregion


#region Outils
func _on_tool_selected(tool_id: int) -> void:
	_tool = tool_id
	if tool_id == UI.Tool.UNIT_PLAYER:
		_ui.open_unit_picker(MapDocument.TEAM_PLAYER, _unit_level)
	elif tool_id == UI.Tool.UNIT_OPPONENT:
		_ui.open_unit_picker(MapDocument.TEAM_OPPONENT, _unit_level)
	_refresh_feedback()


func _on_brush_size(size: int) -> void:
	_brush = clampi(size, 1, MapDocument.BRUSH_SIZES[-1])
	_ui.show_brush(_brush)
	_refresh_feedback("Pinceau : %d×%d case(s)." % [_brush, _brush])


func _on_fill_mode(on: bool) -> void:
	_fill = on
	_refresh_feedback("🪣 Remplissage %s." % ("activé — un clic peint toute la zone"
		if on else "désactivé"))


func _on_unit_picked(path: String) -> void:
	var team: String = MapDocument.TEAM_PLAYER if _tool == UI.Tool.UNIT_PLAYER \
		else MapDocument.TEAM_OPPONENT
	_unit_paths[team] = path
	_refresh_feedback("Unité choisie : %s (niveau %d)" % [
		MapDocument.unit_display_name(path), _unit_level])


## Applique l'outil courant à une case, et retient le coup s'il a changé la carte.
##
## Un clic sans effet (unité posée dans un lac, case déjà fermée) n'entre pas
## dans l'historique : annuler doit défaire un vrai geste, pas un clic raté.
func _use_tool(pos: Vector2i) -> void:
	var message: String = _apply_tool(pos)
	_remember()
	_refresh_feedback(message)


## Le geste de l'outil courant. [returns] le message à afficher ("" = état par défaut).
func _apply_tool(pos: Vector2i) -> String:
	match _tool:
		UI.Tool.RAISE, UI.Tool.LOWER:
			var step: float = HEIGHT_STEP if _tool == UI.Tool.RAISE else -HEIGHT_STEP
			var raised: Array[Vector2i] = doc.brush_cells(pos, _brush)
			for cell: Vector2i in raised:
				doc.set_height_at(cell, doc.height_at(cell) + step)
			_refresh_cells(raised)

		UI.Tool.UNIT_PLAYER, UI.Tool.UNIT_OPPONENT:
			var team: String = MapDocument.TEAM_PLAYER if _tool == UI.Tool.UNIT_PLAYER \
				else MapDocument.TEAM_OPPONENT
			var result: Dictionary = doc.place_unit(
				str(_unit_paths[team]), pos, team, _unit_level)
			if not bool(result["ok"]):
				return "⛔ %s" % str(result["error"])
			_rebuild_markers()

		UI.Tool.ERASE:
			if not doc.remove_unit(pos):
				return "Aucune unité sur cette case."
			_rebuild_markers()

		UI.Tool.DEPLOY:
			var was_open: bool = doc.is_deploy_tile(pos)
			var opened: bool = doc.toggle_deploy_tile(pos)
			# Refermer est toujours permis ; ouvrir exige un terrain franchissable.
			if not opened and not was_open:
				return "⛔ Case de départ impossible sur ce terrain."
			_rebuild_markers()
			return "Case de départ %s (%d, %d)" % [
				"ouverte" if opened else "fermée", pos.x, pos.y]

		UI.Tool.SEIZE:
			if not doc.set_seize_point(pos):
				return "⛔ Point de commandement impossible sur ce terrain."
			_rebuild_markers()
			return "Objectif : prendre la case (%d, %d)." % [pos.x, pos.y]

		_:
			return _paint_terrain(pos)

	return ""


## Peint le terrain courant : quelques cases sous le pinceau, ou toute la zone.
func _paint_terrain(pos: Vector2i) -> String:
	var cells: Array[Vector2i] = doc.region_of(pos) if _fill \
		else doc.brush_cells(pos, _brush)

	var message: String = ""
	for cell: Vector2i in cells:
		doc.set_terrain_at(cell, _tool)
		# Un terrain devenu infranchissable ne peut plus porter ce qui s'y trouve.
		if not MapDataClass.is_walkable(_tool):
			var loss: String = _clear_blocked(cell)
			if not loss.is_empty():
				message = loss
	_refresh_cells(cells)

	if _fill and message.is_empty():
		return "🪣 %d case(s) en %s." % [cells.size(), MapDataClass.type_label(_tool)]
	return message


## Retire ce qu'une case infranchissable ne peut plus accueillir.
func _clear_blocked(pos: Vector2i) -> String:
	var message: String = ""
	var changed: bool = doc.remove_unit(pos)
	if doc.is_deploy_tile(pos):
		doc.toggle_deploy_tile(pos)  # La case redevient fermée.
		changed = true
	if doc.seize_point() == pos:
		doc.set_objective({"kind": MapDocument.OBJ.Kind.ROUT})
		changed = true
		message = "Le point de commandement était ici : objectif remis à « vaincre tous les ennemis »."
	if changed:
		_rebuild_markers()
	return message


## Redessine les cases touchées par un geste.
##
## Décor et repères se recalculent pour toute la carte, pas case par case : la
## garniture d'une case dépend de ses voisines (une porte s'aligne sur son
## rempart). Pendant un trait de pinceau, on s'en dispense — [method _end_stroke]
## le fait une fois, au relâchement.
func _refresh_cells(cells: Array[Vector2i]) -> void:
	for pos: Vector2i in cells:
		var body: Node = _tiles.get(_key(pos), null)
		if body:
			_apply_tile(body as StaticBody3D, pos)
	if _stroke_active:
		return
	_rebuild_props()
	_rebuild_markers()


## Remet à jour outil affiché, message d'état et bilan de validation.
func _refresh_feedback(message: String = "") -> void:
	if not _ui:
		return
	var team: String = MapDocument.TEAM_PLAYER if _tool == UI.Tool.UNIT_PLAYER \
		else MapDocument.TEAM_OPPONENT
	var unit_name: String = ""
	if _tool == UI.Tool.UNIT_PLAYER or _tool == UI.Tool.UNIT_OPPONENT:
		unit_name = MapDocument.unit_display_name(str(_unit_paths[team]))

	_ui.show_tool(_tool, unit_name)
	_ui.show_errors(doc.validate())
	_ui.show_history(_history != null and _history.can_undo(),
		_history != null and _history.can_redo())
	if not message.is_empty():
		_ui.show_status(message)
	else:
		_ui.show_status("%s — %dx%d · %d unité(s) · %s%s" % [
			doc.name, doc.grid_size.x, doc.grid_size.y, doc.units.size(),
			MapDocument.OBJ.describe(doc.objective),
			"  ·  🪣 remplissage" if _fill else ("  ·  ▦ %d×%d" % [_brush, _brush] \
				if _brush > 1 else ""),
		])
#endregion


#region Annulation
## Retient l'état de la carte après un geste, s'il l'a vraiment changée.
func _remember() -> void:
	if _history:
		_history.record(doc.to_dict())


## Repart d'une carte neuve : annuler ne doit pas ramener la précédente.
func _forget_history() -> void:
	if _history:
		_history.reset(doc.to_dict())


func _on_undo() -> void:
	_restore(_history.undo() if _history else {}, "↶ Changement annulé.", "Rien à annuler.")


func _on_redo() -> void:
	_restore(_history.redo() if _history else {}, "↷ Changement rétabli.", "Rien à rétablir.")


## Remet la carte dans un état retenu, et redessine tout.
##
## La grille a pu changer de taille entre deux états : on reconstruit au lieu de
## rafraîchir case par case.
func _restore(snapshot: Dictionary, done_message: String, empty_message: String) -> void:
	if snapshot.is_empty() or not doc.apply_dict(snapshot):
		_refresh_feedback(empty_message)
		return
	_rebuild_all()
	_refresh_feedback(done_message)
#endregion


#region Fichiers
func _on_save() -> void:
	var result: Dictionary = LIBRARY.save(doc)
	if not bool(result["ok"]):
		_refresh_feedback("⛔ Enregistrement refusé : %s" % str(result["error"]))
		return
	_refresh_feedback("💾 Carte enregistrée : %s" % str(result["path"]))


func _on_load(path: String) -> void:
	var loaded: MapDocument = LIBRARY.load_map(path)
	if not loaded:
		_refresh_feedback("⛔ Carte illisible : %s" % path)
		return
	doc = loaded
	_forget_history()
	_rebuild_all()
	_refresh_feedback("📂 Carte « %s » chargée." % doc.name)


## Sort la carte du jeu : vers le presse-papiers, ou vers un fichier choisi.
func _on_export(to_clipboard: bool, path: String) -> void:
	if to_clipboard:
		DisplayServer.clipboard_set(LIBRARY.to_json(doc))
		_refresh_feedback("📋 Carte copiée — colle-la où tu veux, c'est du texte.")
		return

	var result: Dictionary = LIBRARY.export_to(doc, path)
	if not bool(result["ok"]):
		_refresh_feedback("⛔ Export refusé : %s" % str(result["error"]))
		return
	_refresh_feedback("📤 Carte exportée : %s" % str(result["path"]))


## Fait entrer une carte dans l'éditeur, en remplacement de celle en cours.
##
## On passe par `apply_dict` plutôt que de remplacer le document : l'historique
## tient déjà celui-ci par référence, et un import raté ou regretté doit pouvoir
## s'annuler comme n'importe quel autre geste.
func _on_import(from_clipboard: bool, path: String) -> void:
	var result: Dictionary = LIBRARY.from_json(DisplayServer.clipboard_get()) \
		if from_clipboard else LIBRARY.import_from(path)
	if not bool(result["ok"]):
		_refresh_feedback("⛔ Import refusé : %s" % str(result["error"]))
		return

	var incoming: MapDocument = result["doc"]
	if not doc.apply_dict(incoming.to_dict()):
		_refresh_feedback("⛔ Cette carte n'a pas pu être reprise.")
		return

	_remember()
	_rebuild_all()
	_refresh_feedback("📥 Carte « %s » importée (Ctrl+Z pour revenir en arrière)." % doc.name)


func _on_delete(path: String) -> void:
	if LIBRARY.delete(path):
		_refresh_feedback("Carte supprimée.")
	else:
		_refresh_feedback("⛔ Suppression impossible.")


func _on_new(map_name: String, size: Vector2i) -> void:
	doc = MapDocument.create_empty(map_name, size)
	_forget_history()
	_rebuild_all()
	_refresh_feedback("Nouvelle carte « %s » (%dx%d)." % [doc.name, size.x, size.y])


## Tout le panneau de réglages d'un coup : nom, places, taille de grille, objectif.
func _on_settings(map_name: String, slots: int, size: Vector2i,
		objective: Dictionary) -> void:
	if not map_name.strip_edges().is_empty():
		doc.name = map_name.strip_edges()
	doc.deploy_slots = maxi(1, slots)
	doc.set_objective(objective)

	var message: String = "Objectif : %s" % MapDocument.OBJ.describe(doc.objective)
	if size != doc.grid_size:
		# Redimensionner peut faire sortir le point de commandement de la grille :
		# l'objectif se pose avant, pour que le document arbitre les deux ensemble.
		var report: Dictionary = doc.resize(size)
		message = "Carte redimensionnée en %dx%d.%s" % [
			doc.grid_size.x, doc.grid_size.y, _resize_losses(report)]
		_rebuild_all()
	else:
		_rebuild_markers()

	_remember()
	_refresh_feedback(message)


## Ce que le redimensionnement a fait disparaître, dit en clair.
func _resize_losses(report: Dictionary) -> String:
	var losses: Array[String] = []
	var units_removed: int = int(report.get("units_removed", 0))
	var deploy_removed: int = int(report.get("deploy_removed", 0))
	if units_removed > 0:
		losses.append("%d unité(s)" % units_removed)
	if deploy_removed > 0:
		losses.append("%d case(s) de départ" % deploy_removed)
	if bool(report.get("objective_reset", false)):
		losses.append("le point de commandement")
	if losses.is_empty():
		return ""
	return " Hors grille, donc perdu%s : %s (Ctrl+Z pour revenir)." % [
		"s" if losses.size() > 1 else "", " et ".join(losses)]


func _on_test(with_ciel: bool) -> void:
	var errors: Array[String] = doc.validate()
	if not errors.is_empty():
		_refresh_feedback("⛔ Carte injouable : %s" % errors[0])
		return
	play_requested.emit(doc, with_ciel)
#endregion


#region Caméra et entrées
func _refresh_camera() -> void:
	var cam := get_node_or_null("EditorCamera") as Camera3D
	if not cam:
		return
	var yaw: float = deg_to_rad(_cam_yaw)
	var pitch: float = deg_to_rad(_cam_pitch)
	cam.position = _cam_target + Vector3(
		_cam_dist * cos(pitch) * sin(yaw),
		-_cam_dist * sin(pitch),
		_cam_dist * cos(pitch) * cos(yaw)
	)
	cam.look_at(_cam_target)


func _process(delta: float) -> void:
	var cam := get_node_or_null("EditorCamera") as Camera3D
	if not cam or (_ui and _ui.get_viewport().gui_get_focus_owner() is LineEdit):
		return

	var pan: float = _cam_dist * 3.0 * delta
	var rotation_speed: float = 90.0 * delta
	var moved: bool = false

	var forward: Vector3 = -cam.global_basis.z
	forward.y = 0.0
	var right: Vector3 = cam.global_basis.x
	right.y = 0.0

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_cam_target += forward.normalized() * pan
		moved = true
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_cam_target -= forward.normalized() * pan
		moved = true
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_cam_target -= right.normalized() * pan
		moved = true
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_cam_target += right.normalized() * pan
		moved = true
	if Input.is_key_pressed(KEY_Q):
		_cam_yaw -= rotation_speed
		moved = true
	if Input.is_key_pressed(KEY_E):
		_cam_yaw += rotation_speed
		moved = true

	if moved:
		_refresh_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_ui.close_panel()
		back_to_menu.emit()
		return

	# Ctrl+Z / Ctrl+Maj+Z (Cmd sur macOS) : les raccourcis attendus d'un outil de
	# dessin. Un champ de saisie a le focus ? Il consomme la touche avant nous.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.is_command_or_control_pressed():
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					_on_redo()
				else:
					_on_undo()
				return
			KEY_Y:
				_on_redo()
				return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = event.pressed
				_panning = false
				_mouse_prev = event.position
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				_orbiting = false
				_mouse_prev = event.position
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_click(event.position)
				else:
					_end_stroke()
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist = maxf(4.0, _cam_dist - 1.0)
				_refresh_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist = minf(40.0, _cam_dist + 1.0)
				_refresh_camera()
		return

	if event is InputEventMouseMotion:
		var delta: Vector2 = event.position - _mouse_prev
		_mouse_prev = event.position
		# Un bouton relâché au-dessus d'un panneau ne redescend jamais jusqu'ici :
		# le trait resterait ouvert, et la souris peindrait sans qu'on lui demande.
		# C'est l'état réel du bouton qui tranche, pas le seul événement reçu.
		if _stroke_active and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_end_stroke()
		if _stroke_active:
			_click(event.position)
		elif _orbiting:
			_cam_yaw -= delta.x * 0.3
			_cam_pitch = clampf(_cam_pitch - delta.y * 0.3, -89.0, -5.0)
			_refresh_camera()
		elif _panning:
			var cam := get_node_or_null("EditorCamera") as Camera3D
			if cam:
				var speed: float = _cam_dist * 0.003
				_cam_target += cam.global_basis.x * (-delta.x * speed)
				_cam_target += cam.global_basis.y * (delta.y * speed)
				_refresh_camera()


## Traduit un clic écran en case de la grille, puis applique l'outil.
func _click(screen_pos: Vector2) -> void:
	var cam := get_node_or_null("EditorCamera") as Camera3D
	if not cam:
		return

	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + cam.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1

	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var body: Object = hit.get("collider", null)
	if not body is Node:
		return
	var pos: Vector2i = _pos_of_body(body as Node)
	if pos.x < 0:
		return

	# Poser une unité, ouvrir une case de départ, planter le point de
	# commandement : des gestes uniques, retenus tout de suite. Peindre, non —
	# ça se traîne, et ça ne compte que pour un coup d'annulation.
	if not _is_stroke_tool():
		_use_tool(pos)
		return

	if not _stroke_active:
		_stroke_active = true
		_stroke_changed = false
		_stroke_cells.clear()
	_paint_stroke_cell(pos)


## Un outil qui se traîne sur la carte, par opposition à un geste unique.
##
## Le remplissage n'en est pas : il repeint toute une zone d'un coup, le
## promener n'ajouterait rien qu'une carte unie et un historique illisible. Il
## ne concerne en revanche **que** le terrain — élever le sol se traîne toujours,
## que la case à remplir soit cochée ou non.
func _is_stroke_tool() -> bool:
	if _tool == UI.Tool.RAISE or _tool == UI.Tool.LOWER:
		return true
	return UI.is_terrain_tool(_tool) and not _fill


## Une case de plus dans le trait en cours, si le trait ne l'a pas déjà couverte.
func _paint_stroke_cell(pos: Vector2i) -> void:
	if _stroke_cells.has(pos):
		return
	_stroke_cells[pos] = true
	_stroke_changed = true
	_refresh_feedback(_apply_tool(pos))


## Fin du trait : le décor se repose, et l'historique retient un seul coup.
func _end_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	if not _stroke_changed:
		return
	_rebuild_props()
	_rebuild_markers()
	_remember()
	_refresh_feedback()


## Retrouve la case d'une tuile depuis son nom de nœud (Tile_col_row).
func _pos_of_body(body: Node) -> Vector2i:
	var parts: PackedStringArray = String(body.name).split("_")
	if parts.size() != 3:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]), int(parts[2]))


func _key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]
#endregion
