class_name TacticsAIExecutor
extends RefCounted
## Passerelle entre la scène 3D et l'IA heuristique ([LocalAIBrain]).
##
## Traduit les pions en dictionnaires, demande une décision, puis rend au moteur
## la tuile de destination et la cible retenues. Utilisée par deux appelants :
##   * [TacticsOpponentService] — le camp adverse en mode IA locale ;
##   * CielAI — repli automatique quand Ciel ne répond pas (verrou anti-blocage).

const BRAIN = preload("res://data/models/world/ai/local_ai.gd")
const WT = preload("res://data/models/world/stats/weapon_type.gd")
const CD = preload("res://data/models/world/stats/class_data.gd")


## Convertit un pion en unité exploitable par le cerveau heuristique.
static func pawn_to_unit(arena: Node, pawn: Node, team: String) -> Dictionary:
	var tile: Node = pawn.get_tile() if pawn.has_method("get_tile") else null
	var g: Vector2i = TacticsGrid.tile_to_grid(arena, tile) if tile else Vector2i(-1, -1)
	var stats = pawn.stats
	return BRAIN.make_unit({
		"name": display_name(pawn),
		"team": team,
		"col": g.x, "row": g.y,
		"hp": stats.hp, "max_hp": stats.max_hp,
		"atk": stats.get_total_attack(),
		"def": stats.def, "res": stats.res,
		"movement": stats.movement,
		"attack_range": stats.attack_range,
		"is_magical": WT.is_magical(stats.weapon_type),
		"terrain_def": TacticsGrid.terrain_defense(tile),
	})


## Toutes les unités vivantes d'un camp.
static func collect_units(arena: Node, team_node: Node, team: String) -> Array:
	var units: Array = []
	if not team_node or not is_instance_valid(team_node):
		return units
	for p in team_node.get_children():
		if p is TacticsPawn and is_instance_valid(p) and p.is_alive():
			units.append(pawn_to_unit(arena, p, team))
	return units


## Nom affiché d'un pion — unique au sein de son camp (voir [method TacticsPawn.display_name]).
static func display_name(pawn: Node) -> String:
	if pawn and pawn.has_method("display_name"):
		return pawn.display_name()
	return ""


## Calcule un plan d'action pour un pion.
## Marque au passage les tuiles atteignables (nécessaire au pathfinding du moteur).
## [returns] {
##   action: "attack"|"move"|"wait", decision: Dictionary,
##   target: TacticsPawn|null, tile: TacticsTile|null, needs_move: bool
## }
static func plan(arena: Node, pawn: Node, allies_node: Node, enemies_node: Node,
		difficulty: int) -> Dictionary:
	var empty: Dictionary = {"action": "wait", "decision": {}, "target": null,
		"tile": null, "needs_move": false}
	if not arena or not pawn or not is_instance_valid(pawn) or not pawn.is_alive():
		return empty

	var actor: Dictionary = pawn_to_unit(arena, pawn, "opponent")
	var allies: Array = collect_units(arena, allies_node, "opponent")
	var enemies: Array = collect_units(arena, enemies_node, "player")
	if enemies.is_empty():
		return empty

	# Portée de déplacement du tour : le moteur en a besoin pour le pathfinding.
	var reachable: Array = []
	if pawn.res.can_move and pawn.get_tile():
		arena.res.reset_all_tile_markers()
		arena.process_surrounding_tiles(pawn.get_tile(), pawn.stats.jump,
			allies_node.get_children() if allies_node else [])
		arena.mark_reachable_tiles(pawn.get_tile(), pawn.stats.movement)
		reachable = TacticsGrid.reachable_tiles(arena)

	var decision: Dictionary = BRAIN.decide(actor, allies, enemies, reachable, difficulty)

	var dest: Node = null
	var needs_move: bool = int(decision.get("col", actor["col"])) != int(actor["col"]) \
		or int(decision.get("row", actor["row"])) != int(actor["row"])
	if needs_move:
		dest = TacticsGrid.find_tile(arena, int(decision["col"]), int(decision["row"]))
		if not dest:
			needs_move = false

	var target: Node = null
	if str(decision.get("action", "")) == "attack":
		target = find_pawn_by_name(enemies_node, str(decision.get("target", "")))

	return {
		"action": str(decision.get("action", "wait")),
		"decision": decision,
		"target": target,
		"tile": dest,
		"needs_move": needs_move,
	}


## Retrouve un pion vivant par son nom affiché dans un camp donné.
static func find_pawn_by_name(team_node: Node, pawn_name: String) -> Node:
	if not team_node or not is_instance_valid(team_node) or pawn_name.is_empty():
		return null
	for p in team_node.get_children():
		if p is TacticsPawn and is_instance_valid(p) and p.is_alive():
			if display_name(p) == pawn_name:
				return p
	return null


## Tuile la plus sûre pour fuir : maximise la distance au premier ennemi.
static func safest_retreat_tile(arena: Node, pawn: Node, enemies_node: Node) -> Node:
	var enemies: Array = collect_units(arena, enemies_node, "player")
	if enemies.is_empty():
		return null

	var best: Node = null
	var best_score: int = -1
	for tile in TacticsGrid.tiles(arena):
		if not tile.get("reachable"):
			continue
		var g: Vector2i = TacticsGrid.tile_to_grid(arena, tile)
		var spot: Dictionary = {"col": g.x, "row": g.y}
		var nearest: int = 9999
		for e: Dictionary in enemies:
			nearest = mini(nearest, BRAIN.distance(spot, e))
		if nearest > best_score:
			best_score = nearest
			best = tile
	return best
