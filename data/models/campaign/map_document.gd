class_name MapDocument
extends RefCounted
## Une carte créée par le joueur : terrain, armées, zone de déploiement, objectif.
##
## [MapData] ne décrit que le relief — c'est ce qu'il faut pour dessiner une
## arène, pas pour jouer une bataille. Ce document ajoute ce qui manquait :
## quelles unités, de quel camp, où, ce qu'il faut accomplir, et où le joueur a
## le droit de poser ses troupes. C'est lui que l'éditeur manipule, lui qu'on
## enregistre, et lui qui se transforme en chapitre jouable.
##
## Logique pure, sérialisable en JSON lisible — quelqu'un peut éditer une carte
## à la main, ou en échanger une avec un ami sans passer par Godot.

const OBJ = preload("res://data/models/campaign/objective.gd")
const MapDataClass = preload("res://data/models/world/map/map_data.gd")
const ChapterDataClass = preload("res://data/models/campaign/chapter_data.gd")

## Version du format : un fichier plus récent que le jeu est refusé plutôt que
## mal interprété.
const FORMAT_VERSION: int = 1

## Camps possibles pour une unité posée
const TEAM_PLAYER: String = "player"
const TEAM_OPPONENT: String = "opponent"

## Bornes de grille acceptées à la création
const MIN_SIZE: Vector2i = Vector2i(6, 6)
const MAX_SIZE: Vector2i = Vector2i(32, 24)

## Niveaux acceptés pour une unité posée.
##
## Le plafond est celui de la campagne : au-delà, une unité promue continue de
## monter, mais plus rien ne l'y prépare. Poser un niveau 40 sur une carte
## donnerait un adversaire que rien n'équilibre.
const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 20

## Préfixe d'un personnage écrit dans l'éditeur de personnages, par opposition
## à une fiche `.tres` livrée avec le jeu.
const CUSTOM_PREFIX: String = "user://units/"

var format_version: int = FORMAT_VERSION
var name: String = "Carte sans nom"
var author: String = ""
var grid_size: Vector2i = Vector2i(16, 10)
var tile_size: float = 1.0
## Terrains à plat, index = row * grid_size.x + col
var terrain: Array[int] = []
## Hauteurs à plat, même indexation
var heights: Array[float] = []
## Unités posées : [{path: String, col: int, row: int, team: String, level: int}]
var units: Array = []
## Cases ouvertes au déploiement ([[col, row], …]) — vide : voisinage par défaut
var deploy_tiles: Array = []
## Objectif du chapitre : {kind, turns, target, col, row}
var objective: Dictionary = {"kind": OBJ.Kind.ROUT}
## Places de déploiement offertes au joueur
var deploy_slots: int = 4


## Carte vierge (tout en herbe) aux dimensions demandées.
static func create_empty(map_name: String = "Carte sans nom",
		size: Vector2i = Vector2i(16, 10)) -> MapDocument:
	var doc := MapDocument.new()
	doc.name = map_name
	doc.grid_size = Vector2i(
		clampi(size.x, MIN_SIZE.x, MAX_SIZE.x), clampi(size.y, MIN_SIZE.y, MAX_SIZE.y)
	)
	doc.resize(doc.grid_size)
	return doc


#region Terrain
## Redimensionne la grille en gardant ce qui tient dans les nouvelles bornes.
##
## Rétrécir jette forcément quelque chose : le document dit quoi, pour que
## l'éditeur puisse l'annoncer au lieu de laisser disparaître une armée en
## silence.
## [returns] {size: Vector2i, units_removed: int, deploy_removed: int,
## objective_reset: bool}
func resize(size: Vector2i) -> Dictionary:
	var new_size := Vector2i(
		clampi(size.x, MIN_SIZE.x, MAX_SIZE.x), clampi(size.y, MIN_SIZE.y, MAX_SIZE.y)
	)
	var old_terrain: Array[int] = terrain.duplicate()
	var old_heights: Array[float] = heights.duplicate()
	var old_size: Vector2i = grid_size

	grid_size = new_size
	terrain = []
	heights = []
	terrain.resize(new_size.x * new_size.y)
	heights.resize(new_size.x * new_size.y)

	for row: int in new_size.y:
		for col: int in new_size.x:
			var index: int = row * new_size.x + col
			var old_index: int = row * old_size.x + col
			var inside: bool = col < old_size.x and row < old_size.y \
				and old_index < old_terrain.size()
			terrain[index] = old_terrain[old_index] if inside else MapDataClass.TerrainType.GRASS
			heights[index] = old_heights[old_index] if inside else 0.0

	# Ce qui sort de la nouvelle grille n'a plus lieu d'être.
	var units_before: int = units.size()
	var deploy_before: int = deploy_tiles.size()
	units = units.filter(func(u: Dictionary) -> bool: return in_bounds(_pos_of(u)))
	deploy_tiles = deploy_tiles.filter(func(t: Variant) -> bool: return in_bounds(_to_vec(t)))

	# Un point de commandement hors grille rendrait la carte injouable sans que
	# rien ne le montre : l'objectif retombe sur « vaincre tous les ennemis ».
	var objective_reset: bool = false
	if int(objective.get("kind", OBJ.Kind.ROUT)) == OBJ.Kind.SEIZE and not in_bounds(seize_point()):
		set_objective({"kind": OBJ.Kind.ROUT})
		objective_reset = true

	return {
		"size": grid_size,
		"units_removed": units_before - units.size(),
		"deploy_removed": deploy_before - deploy_tiles.size(),
		"objective_reset": objective_reset,
	}


## La case est-elle dans la grille ?
func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < grid_size.x and pos.y < grid_size.y


func terrain_at(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return MapDataClass.TerrainType.GRASS
	return terrain[pos.y * grid_size.x + pos.x]


func set_terrain_at(pos: Vector2i, value: int) -> void:
	if in_bounds(pos):
		terrain[pos.y * grid_size.x + pos.x] = value


func height_at(pos: Vector2i) -> float:
	if not in_bounds(pos):
		return 0.0
	return heights[pos.y * grid_size.x + pos.x]


func set_height_at(pos: Vector2i, value: float) -> void:
	if in_bounds(pos):
		heights[pos.y * grid_size.x + pos.x] = snappedf(clampf(value, -1.0, 3.0), 0.25)


## Une unité peut-elle tenir sur cette case ?
func is_placeable(pos: Vector2i) -> bool:
	return in_bounds(pos) and MapDataClass.is_walkable(terrain_at(pos))
#endregion


#region Unités
## Unité posée sur une case (dictionnaire vide si la case est libre).
func unit_at(pos: Vector2i) -> Dictionary:
	for u: Dictionary in units:
		if _pos_of(u) == pos:
			return u
	return {}


## Pose une unité. Remplace celle qui occupait déjà la case.
## [param level] Niveau de départ, borné à [constant MIN_LEVEL]…[constant MAX_LEVEL].
## [returns] {ok: bool, error: String}
func place_unit(path: String, pos: Vector2i, team: String, level: int = 1) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "error": "aucune unité choisie"}
	if not is_placeable(pos):
		return {"ok": false, "error": "case hors carte ou infranchissable"}

	remove_unit(pos)
	units.append({
		"path": path, "col": pos.x, "row": pos.y,
		"team": team if team == TEAM_PLAYER else TEAM_OPPONENT,
		"level": clampi(level, MIN_LEVEL, MAX_LEVEL),
	})
	return {"ok": true, "error": ""}


## L'unité désignée par ce chemin existe-t-elle ?
##
## Deux origines possibles : une fiche `.tres` livrée avec le jeu, ou un
## personnage écrit dans l'éditeur de personnages — un simple JSON de
## `user://units/`, que `ResourceLoader` ne connaît pas.
static func unit_exists(path: String) -> bool:
	if is_custom_unit(path):
		return FileAccess.file_exists(path)
	return ResourceLoader.exists(path)


## Ce chemin désigne-t-il un personnage écrit par le joueur ?
static func is_custom_unit(path: String) -> bool:
	return path.begins_with(CUSTOM_PREFIX) and path.ends_with(".json")


## Retire l'unité d'une case. [returns] vrai si quelque chose a été retiré.
func remove_unit(pos: Vector2i) -> bool:
	var before: int = units.size()
	units = units.filter(func(u: Dictionary) -> bool: return _pos_of(u) != pos)
	return units.size() != before


## Unités d'un camp.
func units_of(team: String) -> Array:
	return units.filter(func(u: Dictionary) -> bool: return str(u.get("team", "")) == team)
#endregion


#region Zone de déploiement et objectif
## Ouvre ou ferme une case au déploiement. [returns] son nouvel état.
##
## Refermer est toujours permis : une case ouverte puis noyée sous un lac doit
## pouvoir être retirée, sinon la carte resterait injouable sans recours.
## Seule l'ouverture exige un terrain franchissable.
func toggle_deploy_tile(pos: Vector2i) -> bool:
	for i: int in deploy_tiles.size():
		if _to_vec(deploy_tiles[i]) == pos:
			deploy_tiles.remove_at(i)
			return false
	if not is_placeable(pos):
		return false
	deploy_tiles.append([pos.x, pos.y])
	return true


func is_deploy_tile(pos: Vector2i) -> bool:
	for t: Variant in deploy_tiles:
		if _to_vec(t) == pos:
			return true
	return false


## Définit l'objectif principal de la carte.
## [param data] {kind, turns, target, col, row} — les clés inutiles sont ignorées.
func set_objective(data: Dictionary) -> void:
	var kind: int = int(data.get("kind", OBJ.Kind.ROUT))
	var out: Dictionary = {"kind": kind}
	match kind:
		OBJ.Kind.SURVIVE:
			out["turns"] = maxi(1, int(data.get("turns", 8)))
		OBJ.Kind.DEFEAT_BOSS, OBJ.Kind.PROTECT:
			out["target"] = str(data.get("target", ""))
			if kind == OBJ.Kind.PROTECT:
				out["turns"] = maxi(1, int(data.get("turns", 10)))
		OBJ.Kind.SEIZE:
			out["col"] = int(data.get("col", 0))
			out["row"] = int(data.get("row", 0))
	objective = out


## Place le point de commandement (bascule l'objectif sur « prise de point »).
func set_seize_point(pos: Vector2i) -> bool:
	if not is_placeable(pos):
		return false
	set_objective({"kind": OBJ.Kind.SEIZE, "col": pos.x, "row": pos.y})
	return true


## Case à prendre, ou (-1, -1).
func seize_point() -> Vector2i:
	return OBJ.seize_target(objective)
#endregion


#region Validation
## Tout ce qui empêcherait la carte d'être jouée. Vide = carte jouable.
##
## L'éditeur s'en sert pour refuser d'enregistrer une carte injouable et pour
## dire au créateur ce qui manque : une carte sans ennemi ou dont le point de
## commandement est dans un mur ne serait découverte qu'en jouant.
func validate() -> Array[String]:
	var errors: Array[String] = []

	if terrain.size() != grid_size.x * grid_size.y:
		errors.append("La grille de terrain ne correspond pas à la taille de la carte.")
	if name.strip_edges().is_empty():
		errors.append("La carte n'a pas de nom.")

	if units_of(TEAM_PLAYER).is_empty():
		errors.append("Aucune unité du joueur : pose au moins un héros.")
	if units_of(TEAM_OPPONENT).is_empty():
		errors.append("Aucun adversaire : la bataille serait gagnée d'emblée.")

	var seen: Dictionary = {}
	for u: Dictionary in units:
		var pos: Vector2i = _pos_of(u)
		var key: String = "%d,%d" % [pos.x, pos.y]
		if seen.has(key):
			errors.append("Deux unités occupent la case (%d, %d)." % [pos.x, pos.y])
		seen[key] = true
		if not in_bounds(pos):
			errors.append("Une unité est posée hors de la carte (%d, %d)." % [pos.x, pos.y])
		elif not MapDataClass.is_walkable(terrain_at(pos)):
			errors.append("Une unité est posée sur un terrain infranchissable (%d, %d)."
				% [pos.x, pos.y])
		if not unit_exists(str(u.get("path", ""))):
			errors.append("Unité inconnue : %s" % str(u.get("path", "")))
		var level: int = int(u.get("level", 1))
		if level < MIN_LEVEL or level > MAX_LEVEL:
			errors.append("Niveau hors bornes (%d) pour l'unité en (%d, %d)."
				% [level, pos.x, pos.y])

	for t: Variant in deploy_tiles:
		var pos: Vector2i = _to_vec(t)
		if not in_bounds(pos):
			errors.append("Case de déploiement hors de la carte (%d, %d)." % [pos.x, pos.y])
		elif not MapDataClass.is_walkable(terrain_at(pos)):
			errors.append("Case de déploiement infranchissable (%d, %d)." % [pos.x, pos.y])

	if not deploy_tiles.is_empty() and deploy_tiles.size() < units_of(TEAM_PLAYER).size():
		errors.append("Moins de cases de déploiement (%d) que d'unités du joueur (%d)."
			% [deploy_tiles.size(), units_of(TEAM_PLAYER).size()])

	errors.append_array(_validate_objective())
	return errors


func _validate_objective() -> Array[String]:
	var errors: Array[String] = []
	var kind: int = int(objective.get("kind", OBJ.Kind.ROUT))

	match kind:
		OBJ.Kind.SEIZE:
			var point: Vector2i = seize_point()
			if not in_bounds(point):
				errors.append("Le point de commandement est hors de la carte.")
			elif not MapDataClass.is_walkable(terrain_at(point)):
				errors.append("Le point de commandement est sur un terrain infranchissable.")
			elif not unit_at(point).is_empty() \
					and str(unit_at(point).get("team", "")) == TEAM_PLAYER:
				errors.append("Le point de commandement est déjà tenu au départ.")

		OBJ.Kind.DEFEAT_BOSS:
			if not _has_unit_named(str(objective.get("target", "")), TEAM_OPPONENT):
				errors.append("Aucun adversaire ne s'appelle « %s » : l'objectif « vaincre le commandant » serait gagné d'emblée."
					% str(objective.get("target", "")))

		OBJ.Kind.PROTECT:
			if not _has_unit_named(str(objective.get("target", "")), TEAM_PLAYER):
				errors.append("Aucune unité du joueur ne s'appelle « %s » : la protégée doit être sur la carte."
					% str(objective.get("target", "")))

		OBJ.Kind.SURVIVE:
			if int(objective.get("turns", 0)) <= 0:
				errors.append("Le nombre de tours à tenir doit être positif.")

	return errors


## Nom affiché d'une unité posée (celui que verra l'objectif).
##
## Reproduit [method TacticsPawn.base_name] : nom propre s'il existe, sinon la
## classe. Sans quoi l'éditeur validerait une cible que le moteur ne reconnaît pas.
static func unit_display_name(path: String) -> String:
	if is_custom_unit(path):
		var doc: UnitDocument = UnitLibrary.load_unit(
			path.trim_prefix(CUSTOM_PREFIX).trim_suffix(".json"))
		return doc.name.strip_edges() if doc else ""
	if not ResourceLoader.exists(path):
		return ""
	var res: Resource = load(path)
	if not res:
		return ""
	var override: String = str(res.get("override_name"))
	return override if not override.is_empty() else str(res.get("expertise"))


func _has_unit_named(unit_name: String, team: String) -> bool:
	if unit_name.is_empty():
		return false
	for u: Dictionary in units_of(team):
		if unit_display_name(str(u.get("path", ""))) == unit_name:
			return true
	return false
#endregion


#region Conversions
## Relief exploitable par [TacticsArena].
func to_map_data() -> MapData:
	var md := MapDataClass.new()
	md.grid_size = grid_size
	md.tile_size = tile_size
	md.terrain_grid = terrain.duplicate()
	md.height_grid = heights.duplicate()
	return md


## Reprend le relief d'une carte existante (import d'une carte du jeu).
func from_map_data(md: MapData) -> void:
	grid_size = md.grid_size
	tile_size = md.tile_size
	terrain = md.terrain_grid.duplicate()
	heights = md.height_grid.duplicate()


## Chapitre jouable correspondant à cette carte.
##
## Une carte du joueur emprunte exactement la machinerie de la campagne :
## objectif, zone de déploiement, places. Rien de spécifique à maintenir.
func to_chapter() -> ChapterData:
	var chapter := ChapterDataClass.new()
	chapter.id = "custom_%s" % slug()
	chapter.index = 0
	chapter.title = name
	chapter.subtitle = "Carte de %s" % author if not author.is_empty() else "Carte personnalisée"
	chapter.scene_path = ""  # Le niveau est bâti à la volée, pas chargé d'un fichier.
	chapter.objective = objective.duplicate(true)
	chapter.deploy_slots = maxi(1, deploy_slots)
	chapter.deploy_tiles = deploy_tiles.duplicate(true)
	chapter.reward_gold = 0
	# Les unités de la carte sont celles que son auteur a posées : le roster de
	# campagne n'a rien à y remplacer, ni personne à retirer du terrain.
	chapter.use_roster = false
	return chapter


## Identifiant de fichier tiré du nom (sans accent ni espace).
func slug() -> String:
	var out: String = ""
	for c: String in name.strip_edges().to_lower():
		if c.is_valid_identifier() or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
		elif c in "àâä":
			out += "a"
		elif c in "éèêë":
			out += "e"
		elif c in "îï":
			out += "i"
		elif c in "ôö":
			out += "o"
		elif c in "ùûü":
			out += "u"
		elif c == "ç":
			out += "c"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().lstrip("_").rstrip("_")
	return out if not out.is_empty() else "carte"
#endregion


#region Sérialisation
func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"name": name,
		"author": author,
		"grid_size": {"x": grid_size.x, "y": grid_size.y},
		"tile_size": tile_size,
		"terrain": terrain.duplicate(),
		"heights": heights.duplicate(),
		"units": units.duplicate(true),
		"deploy_tiles": deploy_tiles.duplicate(true),
		"objective": objective.duplicate(true),
		"deploy_slots": deploy_slots,
	}


## Relit un document. Renvoie null si le fichier vient d'une version plus récente
## ou si la grille est inexploitable.
static func from_dict(data: Dictionary) -> MapDocument:
	if int(data.get("format_version", 1)) > FORMAT_VERSION:
		push_warning("[MapDocument] Carte enregistrée par une version plus récente du jeu.")
		return null

	var doc := MapDocument.new()
	doc.format_version = int(data.get("format_version", FORMAT_VERSION))
	doc.name = str(data.get("name", "Carte sans nom"))
	doc.author = str(data.get("author", ""))
	var size: Dictionary = data.get("grid_size", {})
	doc.grid_size = Vector2i(int(size.get("x", 16)), int(size.get("y", 10)))
	doc.tile_size = float(data.get("tile_size", 1.0))
	doc.deploy_slots = int(data.get("deploy_slots", 4))

	var expected: int = doc.grid_size.x * doc.grid_size.y
	if expected <= 0:
		return null

	doc.terrain = []
	for value: Variant in data.get("terrain", []):
		doc.terrain.append(int(value))
	doc.heights = []
	for value: Variant in data.get("heights", []):
		doc.heights.append(float(value))

	# Un fichier tronqué (ou bricolé à la main) se complète plutôt que d'échouer :
	# le reste de la carte reste jouable.
	while doc.terrain.size() < expected:
		doc.terrain.append(MapDataClass.TerrainType.GRASS)
	while doc.heights.size() < expected:
		doc.heights.append(0.0)
	doc.terrain.resize(expected)
	doc.heights.resize(expected)

	for u: Variant in data.get("units", []):
		if not u is Dictionary:
			continue
		doc.units.append({
			"path": str(u.get("path", "")),
			"col": int(u.get("col", 0)),
			"row": int(u.get("row", 0)),
			"team": TEAM_PLAYER if str(u.get("team", "")) == TEAM_PLAYER else TEAM_OPPONENT,
			# Une carte d'avant les niveaux n'en déclare pas : ses unités valent 1,
			# ce qu'elles étaient déjà.
			"level": clampi(int(u.get("level", MIN_LEVEL)), MIN_LEVEL, MAX_LEVEL),
		})

	for t: Variant in data.get("deploy_tiles", []):
		var pos: Vector2i = _static_to_vec(t)
		if pos.x >= 0:
			doc.deploy_tiles.append([pos.x, pos.y])

	doc.set_objective(data.get("objective", {"kind": OBJ.Kind.ROUT}))
	return doc


## Recharge ce document depuis un instantané, sans en créer un autre.
##
## L'annulation remet une carte dans un état passé : elle doit le faire *sur ce
## document-là*, que l'éditeur, la bibliothèque et l'essai en cours tiennent
## déjà par référence. Remplacer l'objet les laisserait sur l'ancien.
## [returns] faux si l'instantané est illisible — le document reste intact.
func apply_dict(data: Dictionary) -> bool:
	var other: MapDocument = from_dict(data)
	if not other:
		return false
	format_version = other.format_version
	name = other.name
	author = other.author
	grid_size = other.grid_size
	tile_size = other.tile_size
	terrain = other.terrain
	heights = other.heights
	units = other.units
	deploy_tiles = other.deploy_tiles
	objective = other.objective
	deploy_slots = other.deploy_slots
	return true
#endregion


#region Internes
func _pos_of(unit: Dictionary) -> Vector2i:
	return Vector2i(int(unit.get("col", -1)), int(unit.get("row", -1)))


func _to_vec(raw: Variant) -> Vector2i:
	return _static_to_vec(raw)


static func _static_to_vec(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	if raw is Dictionary:
		return Vector2i(int(raw.get("col", -1)), int(raw.get("row", -1)))
	return Vector2i(-1, -1)
#endregion
