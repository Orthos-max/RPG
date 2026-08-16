class_name ChapterMap
extends RefCounted
## Ce que la carte d'un chapitre dit de son terrain — sans monter la bataille.
##
## L'écran de préparation doit montrer où l'on peut se poser **et sur quoi** :
## le bonus défensif d'une case est calculé de bout en bout depuis longtemps,
## mais personne ne pouvait le choisir avant d'engager. Pour cela il faut lire la
## carte du chapitre alors qu'aucun niveau n'est chargé.
##
## Rien n'est instancié : on interroge le [SceneState] de la scène empaquetée,
## c'est-à-dire ce que l'éditeur a écrit sur le disque. Deux raisons de ne pas se
## contenter d'un `instantiate()` suivi d'un `free()` :
##
## 1. hors de l'arbre, `global_position` **rend l'identité** (Godot le dit lui-même
##    par une erreur) — les quatre pions de départ tombaient tous sur la même case ;
## 2. instancier des pions pour les jeter aussitôt réveille le rendu pour rien.
##
## Lire l'état, c'est aussi ce qui rend cette carte disponible en `--headless`,
## là où l'étape de déploiement en jeu ne l'est pas.

const MapDataRef = preload("res://data/models/world/map/map_data.gd")
const PLAN = preload("res://data/models/campaign/deployment_plan.gd")

## Rayon de la zone ouverte autour de la ligne de départ, quand le chapitre
## ne déclare pas ses propres cases. Même valeur que [DeploymentPhase].
const DEFAULT_RADIUS: int = 2


## Lit la carte d'un chapitre.
##
## [returns] {ok: bool, reason: String, grid_size: Vector2i,
##            terrain: Array[int] (aplati, ligne par ligne),
##            heights: Array[float] (même indexation),
##            starts: Array[Vector2i] (ligne de départ du joueur),
##            slots: Array[Vector2i] (cases ouvertes au déploiement)}
static func read(chapter: ChapterData) -> Dictionary:
	var out: Dictionary = {
		"ok": false, "reason": "",
		"grid_size": Vector2i.ZERO, "terrain": [], "heights": [],
		"starts": [], "slots": [],
	}
	if not chapter:
		out["reason"] = "aucun chapitre"
		return out

	var packed: PackedScene = load(chapter.scene_path)
	if not packed:
		out["reason"] = "scène introuvable : %s" % chapter.scene_path
		return out

	var state: SceneState = packed.get_state()
	var map_data: Resource = _find_map_data(state)
	if not map_data:
		out["reason"] = "cette carte ne déclare pas de terrain"
		return out

	out["grid_size"] = map_data.grid_size
	out["terrain"] = map_data.terrain_grid.duplicate()
	out["heights"] = map_data.height_grid.duplicate()
	out["starts"] = _player_starts(state, map_data)
	out["slots"] = _slots_for(chapter, out["starts"], map_data)
	out["ok"] = not out["slots"].is_empty()
	if not out["ok"]:
		out["reason"] = "aucune case de déploiement praticable"

	return out


## Terrain d'une case, lu dans le tableau aplati renvoyé par [method read].
static func terrain_at(map: Dictionary, pos: Vector2i) -> int:
	var gs: Vector2i = map.get("grid_size", Vector2i.ZERO)
	if pos.x < 0 or pos.y < 0 or pos.x >= gs.x or pos.y >= gs.y:
		return MapDataRef.TerrainType.GRASS
	var terrain: Array = map.get("terrain", [])
	var idx: int = pos.y * gs.x + pos.x
	return int(terrain[idx]) if idx < terrain.size() else MapDataRef.TerrainType.GRASS


## Bonus défensif d'une case — le chiffre que le joueur vient chercher ici.
static func defense_at(map: Dictionary, pos: Vector2i) -> int:
	return MapDataRef.get_defense_bonus(terrain_at(map, pos))


## Hauteur déclarée d'une case, lue dans le tableau aplati de [method read].
static func height_at(map: Dictionary, pos: Vector2i) -> float:
	var gs: Vector2i = map.get("grid_size", Vector2i.ZERO)
	if pos.x < 0 or pos.y < 0 or pos.x >= gs.x or pos.y >= gs.y:
		return 0.0
	var heights: Array = map.get("heights", [])
	var idx: int = pos.y * gs.x + pos.x
	return float(heights[idx]) if idx < heights.size() else 0.0


## Cases où l'on peut poser le pied, en (colonne, ligne) → altitude perçue.
##
## Deux traductions, et elles comptent :
##
## 1. **Le terrain filtre avant le relief.** Un lac et un rempart ne sont pas des
##    marches trop hautes, ce sont des cases où l'on ne va pas — c'est ce que
##    fait le parcours ([TacticsArenaService.process_surrounding_tiles]), qui
##    écarte l'infranchissable avant même de regarder la dénivellation.
## 2. **L'altitude vaut la moitié de la hauteur rendue.** Une case engendrée
##    depuis [MapData] est un volume dont le centre est posé à `hauteur / 2` — et
##    c'est ce centre que [BattleGrid] retient, donc lui que le jeu compare d'une
##    case à l'autre. Comparer les hauteurs brutes ferait paraître les marches
##    deux fois plus hautes qu'elles ne sont. Et c'est bien la hauteur *rendue*
##    ([method MapData.elevation]) : une montagne se dresse d'une unité quoi
##    qu'en dise la carte, et cette marche-là existe pour de bon.
static func walkable_cells(map: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var gs: Vector2i = map.get("grid_size", Vector2i.ZERO)
	for row: int in gs.y:
		for col: int in gs.x:
			var pos := Vector2i(col, row)
			var terrain: int = terrain_at(map, pos)
			if MapDataRef.is_walkable(terrain):
				out[pos] = MapDataRef.elevation(terrain, height_at(map, pos)) / 2.0
	return out


## Nombre de zones franchissables d'une carte lue par [method read].
##
## Le pendant de [method zone_count] pour une carte engendrée depuis [MapData] :
## deux zones, et les deux camps ne peuvent pas se rejoindre.
static func walkable_zones(map: Dictionary, max_step: float) -> int:
	return zone_count(walkable_cells(map), max_step)


## Hauteur de chaque case d'une carte posée à la main, lue dans la scène.
##
## Les cartes de chapitre passent par [MapData] ; celles écrites à la main (le
## chapitre 2) posent leurs tuiles une par une dans la scène de l'arène. C'est
## la seule façon de mesurer leur relief sans monter la bataille.
##
## [returns] {Vector2i (colonne, ligne) → hauteur}
static func scene_tiles(scene_path: String) -> Dictionary:
	var out: Dictionary = {}
	var packed: PackedScene = load(scene_path)
	if not packed:
		return out
	var found: Dictionary = _tiles_of_state(packed.get_state())
	for cell: Vector2i in found:
		out[cell] = found[cell]
	return out


## Nombre de zones où l'on circule sans jamais franchir plus de `max_step`.
##
## Deux zones, c'est une carte coupée en deux : chaque camp reste de son côté et
## la bataille ne peut pas avoir lieu. C'est arrivé au chapitre 2, dont le relief
## a été aplati le 2026-08-06.
static func zone_count(cells: Dictionary, max_step: float) -> int:
	const STEPS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	var seen: Dictionary = {}
	var zones: int = 0
	for start: Vector2i in cells:
		if seen.has(start):
			continue
		zones += 1
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var current: Vector2i = stack.pop_back()
			for step: Vector2i in STEPS:
				var next: Vector2i = current + step
				if not cells.has(next) or seen.has(next):
					continue
				if absf(float(cells[next]) - float(cells[current])) <= max_step:
					seen[next] = true
					stack.append(next)
	return zones


#region Internes
## Tuiles d'un état de scène, en (colonne, ligne) → hauteur.
##
## On descend aussi dans les scènes imbriquées : le niveau instancie son arène,
## et ce sont les tuiles de l'arène qui nous intéressent.
static func _tiles_of_state(state: SceneState, prefix: Transform3D = Transform3D()) -> Dictionary:
	var out: Dictionary = {}
	if not state:
		return out

	var locals: Dictionary = _local_transforms(state)
	for i: int in state.get_node_count():
		var path: String = str(state.get_node_path(i))
		var nested: PackedScene = state.get_node_instance(i)
		if nested:
			var here: Transform3D = prefix * _global_transform(path, locals)
			out.merge(_tiles_of_state(nested.get_state(), here))
			continue
		# Une tuile est un enfant direct du nœud « Tiles ». Les chemins rendus par
		# `SceneState` commencent par « ./ » — l'oublier ne rapporte aucune tuile.
		var relative: String = path.trim_prefix("./")
		if not relative.begins_with("Tiles/") or relative.trim_prefix("Tiles/").contains("/"):
			continue
		var world: Transform3D = prefix * _global_transform(path, locals)
		out[Vector2i(floori(world.origin.x + 0.5), floori(world.origin.z + 0.5))] = world.origin.y
	return out


## Transformation cumulée d'un nœud, parents compris.
static func _global_transform(path: String, locals: Dictionary) -> Transform3D:
	var total := Transform3D()
	var walked: String = ""
	for part: String in path.split("/"):
		walked = part if walked.is_empty() else "%s/%s" % [walked, part]
		total = total * (locals.get(walked, Transform3D()) as Transform3D)
	return total

## Cherche la ressource de terrain dans l'état de la scène, où qu'elle soit.
##
## Elle vit sur l'arène, elle-même scène instanciée à l'intérieur du niveau : on
## descend donc aussi dans les scènes imbriquées, plutôt que de coder un chemin
## en dur qu'un rangement différent invaliderait.
static func _find_map_data(state: SceneState) -> Resource:
	if not state:
		return null
	for i: int in state.get_node_count():
		var res: Variant = _property(state, i, "res")
		if res is Resource:
			var md: Variant = res.get("map_data")
			if md is Resource:
				return md
		var nested: PackedScene = state.get_node_instance(i)
		if nested:
			var found: Resource = _find_map_data(nested.get_state())
			if found:
				return found
	return null


## Valeur d'une propriété posée à l'édition sur un nœud (null si absente).
static func _property(state: SceneState, index: int, wanted: String) -> Variant:
	for j: int in state.get_node_property_count(index):
		if str(state.get_node_property_name(index, j)) == wanted:
			return state.get_node_property_value(index, j)
	return null


## Cases occupées par les pions du joueur à l'ouverture de la carte.
static func _player_starts(state: SceneState, map_data: Resource) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var team_path: String = _player_team_path(state)
	if team_path.is_empty():
		return out

	var locals: Dictionary = _local_transforms(state)
	for i: int in state.get_node_count():
		var path: String = str(state.get_node_path(i))
		# Les pions sont les enfants directs du camp, rien de plus profond
		# (chaque pion porte une « Expertise » qui n'est pas une unité).
		if not path.begins_with(team_path + "/") or path.trim_prefix(team_path + "/").contains("/"):
			continue
		var pos: Vector2i = _to_grid(_global_origin(path, locals), map_data)
		if pos.x >= 0 and not out.has(pos):
			out.append(pos)
	return out


## Chemin du camp du joueur, reconnu à son script — le nom du nœud peut changer.
static func _player_team_path(state: SceneState) -> String:
	for i: int in state.get_node_count():
		var script: Variant = _property(state, i, "script")
		if script is Script and str(script.resource_path).ends_with("tactics_player.gd"):
			return str(state.get_node_path(i))
	return ""


## Transformations locales déclarées par la scène, par chemin de nœud.
## Un nœud sans `transform` écrit n'a pas bougé : l'identité fait l'affaire.
static func _local_transforms(state: SceneState) -> Dictionary:
	var out: Dictionary = {}
	for i: int in state.get_node_count():
		var value: Variant = _property(state, i, "transform")
		out[str(state.get_node_path(i))] = value if value is Transform3D else Transform3D()
	return out


## Position monde d'un nœud, en composant les transformations de ses parents —
## ce que `global_position` refuse de faire hors de l'arbre.
static func _global_origin(path: String, locals: Dictionary) -> Vector3:
	return _global_transform(path, locals).origin


## Conversion monde → grille, même formule que [TacticsGrid.tile_to_grid] : la
## grille est centrée sur l'origine, une case vaut `tile_size`.
static func _to_grid(world: Vector3, map_data: Resource) -> Vector2i:
	var gs: Vector2i = map_data.grid_size
	var ts: float = map_data.tile_size
	if ts <= 0.0:
		return Vector2i(-1, -1)
	var col: int = int(round((world.x / ts) + (float(gs.x) / 2.0) - 0.5))
	var row: int = int(round((world.z / ts) + (float(gs.y) / 2.0) - 0.5))
	if col < 0 or row < 0 or col >= gs.x or row >= gs.y:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


## Cases ouvertes : celles que le chapitre déclare, sinon le voisinage de la
## ligne de départ. Les cases infranchissables sont écartées dans les deux cas —
## déployer dans un lac n'a jamais été une option.
static func _slots_for(chapter: ChapterData, starts: Array[Vector2i],
		map_data: Resource) -> Array[Vector2i]:
	var candidates: Array = chapter.deploy_tiles
	if candidates.is_empty():
		candidates = PLAN.default_slots(starts, map_data.grid_size, DEFAULT_RADIUS)

	var out: Array[Vector2i] = []
	for raw: Variant in candidates:
		var pos: Vector2i = raw if raw is Vector2i else Vector2i(int(raw[0]), int(raw[1]))
		if pos.x < 0 or pos.y < 0 or pos.x >= map_data.grid_size.x or pos.y >= map_data.grid_size.y:
			continue
		if not MapDataRef.is_walkable(map_data.get_terrain(pos.x, pos.y)):
			continue
		if not out.has(pos):
			out.append(pos)

	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return out
#endregion
