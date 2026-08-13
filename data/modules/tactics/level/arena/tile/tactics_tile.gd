class_name TacticsTile
extends StaticBody3D
## Handles tiles, hover colors, tile state, pathfinding.
## 
## This is ultimately a module, as it is programatically appended onto every tile by way of the TacticsTileService.
## Dependencies: [TacticsTileService] [br]
## Used by: [TacticsArena]

#region: --- Props ---
## Whether the tile is reachable
var reachable: bool = false
## Whether the tile is attackable
var attackable: bool = false
## Whether the tile is being hovered over
var hover: bool = false
## Case menacée par l'adversaire, montrée tant que le joueur tient la touche C
## (voir [BattleThreatRange]). Ce drapeau n'appartient qu'à l'affichage : il ne
## participe à aucune règle, et [method reset_markers] ne le touche pas — c'est
## le nœud qui l'a allumé qui l'éteint, au relâchement de la touche.
var threat: bool = false
## Case à portée de l'ennemi actuellement survolé à la souris (voir
## [EnemyPeekPanel]). Même nature que [member threat] — un drapeau d'affichage,
## posé et retiré par le nœud qui l'allume, ignoré de [method reset_markers] et
## de toute règle.
var peek: bool = false
## Point de commandement à prendre (objectif « prise de point » du chapitre)
var seize_point: bool = false
## Case où le joueur peut poser une unité avant la bataille
var deploy_point: bool = false

## Terrain type for this tile (from MapData.TerrainType)
@export var terrain_type: int = 0
## Base material for terrain (applied when no special state is active)
var terrain_mat: Material = null

## Matériau de surlignage de cette case, pour un état donné.
##
## Les aplats de couleur unie d'avant effaçaient le terrain : une case
## atteignable perdait d'un coup le grain que la passe artistique lui avait
## donné. [TacticsScenery] rend maintenant un matériau **teinté par-dessus le
## terrain de cette case-ci** — d'où le passage par `terrain_type`.
## Matériaux de surlignage déjà résolus pour cette case.
var _highlights: Dictionary = {}

## Calque de transition posé par [TacticsAutoTiler], ou `null` si le terrain de
## cette case n'en reçoit pas (herbe, montagne, tout ce qui sert de fond).
var autotile: MeshInstance3D = null
## Matériau de repos du calque — celui qu'il porte hors surlignage.
var autotile_mat: StandardMaterial3D = null
## Teintes du calque déjà résolues, par état.
var _autotile_highlights: Dictionary = {}


func highlight(state: String) -> StandardMaterial3D:
	# `_process` passe ici à chaque frame, pour chaque tuile : on garde la
	# réponse sous la main plutôt que de reconstruire une clé de cache 200 fois
	# par image.
	var known: Variant = _highlights.get(state)
	if known is StandardMaterial3D:
		return known
	var built: StandardMaterial3D = TacticsScenery.highlight_material(terrain_type, state)
	_highlights[state] = built
	return built


## Enregistre le calque d'auto-tuilage de cette case.
##
## Appelé par [TacticsAutoTiler] à la construction de l'arène. Les teintes déjà
## calculées sont jetées : elles partaient de l'ancien matériau, et une case qui
## change de bord (l'éditeur repeint sa voisine) doit changer de lavis avec lui.
func set_autotile(overlay: MeshInstance3D, base: StandardMaterial3D) -> void:
	autotile = overlay
	autotile_mat = base
	_autotile_highlights.clear()


## Le calque de cette case, passé au lavis d'un état.
func autotile_highlight(state: String) -> StandardMaterial3D:
	var known: Variant = _autotile_highlights.get(state)
	if known is StandardMaterial3D:
		return known
	var built: StandardMaterial3D = TacticsScenery.tinted(autotile_mat, state)
	_autotile_highlights[state] = built
	return built
#endregion

#region: --- Processing ---
func _process(_delta: float) -> void:
	# Get child node named "Tile" and cast it to a MeshInstance3D.
	# If the node doesn't exist, it will be null.
	var tile: MeshInstance3D = get_node_or_null("Tile") as MeshInstance3D
	if not tile:
		return # If the "Tile" node wasn't found, the function exits early to avoid errors.

	tile.visible = true
	var state: String = current_state()

	if state.is_empty():
		if terrain_mat:
			tile.material_override = terrain_mat
	else:
		tile.material_override = highlight(state)

	# Le calque de transition suit le même état que la case qu'il recouvre : sans
	# cela, une rive resterait bleu-mer par-dessus une case atteignable, et le
	# joueur perdrait de vue jusqu'où il peut aller.
	if autotile and is_instance_valid(autotile):
		autotile.material_override = autotile_mat if state.is_empty() else autotile_highlight(state)


## L'état que cette case doit afficher, ou une chaîne vide pour son terrain nu.
##
## L'ordre est celui du jeu, du plus fugace au plus permanent :
##
## 1. ce qui dépend du pion en cours — survol, portée de déplacement, portée
##    d'arme — parce que c'est ce que le joueur est en train de lire ;
## 2. la portée de l'ennemi sous la souris, qui ne dure que le survol ;
## 3. la portée adverse entière, montrée le temps d'une touche tenue, et demandée
##    justement pour être lue ;
## 4. les marques de scénario — point à prendre, case de déploiement — qui
##    restent affichées tout un chapitre et peuvent donc céder le pas.
##
## Le survol passe avant la touche C, et non l'inverse : quand les deux sont
## affichés, l'orange découpe dans le rose la part d'un seul adversaire — c'est
## précisément la question qu'on pose en pointant un ennemi.
func current_state() -> String:
	if attackable or reachable or hover:
		if hover:
			if reachable:
				return "reachable_hover"
			if attackable:
				return "hover_attackable"
			return "hover"
		if reachable:
			return "reachable"
		return "attackable"

	if peek:
		return "peek"
	if threat:
		return "threat"
	if deploy_point:
		return "deploy"
	if seize_point:
		return "seize"
	return ""
#endregion

#region: --- Methods ---
# Getters
## Returns all 4 directly adjacent tiles
##
## L'index de grille répond seul depuis le 2026-08-07. Le repli sur les rayons
## 3D a disparu : toute tuile existante passe par [TacticsTileService], donc par
## l'index bâti dans la foulée — il n'y avait plus de cas à rattraper.
func get_neighbors(height: float) -> Array:
	var grid: BattleGrid = BattleGrid.current
	return grid.neighbors_of(self, height) if grid else []


## Returns the pawn standing on this tile, if any
func get_tile_occupier() -> Object:
	var grid: BattleGrid = BattleGrid.current
	return grid.occupant_of(self) if grid else null


## Return whether target tile is occupied
func is_taken() -> bool:
	return get_tile_occupier() != null


# Setters
## Remet à zéro ce que la tuile affiche d'un parcours (atteignable, attaquable).
##
## Le parcours lui-même — d'où l'on vient, en combien de pas — ne vit plus ici :
## il est dans [PathField], indexé par coordonnée. La tuile ne garde que ce
## qu'elle dessine.
func reset_markers() -> void:
	reachable = false
	attackable = false


## Initializes tile (disable hover & reset state)
##
## Les terrains qui déclinent leur tuile ou qui bougent
## ([method TacticsScenery.needs_tile_material]) passent par le matériau de leur
## case, pas par celui — partagé — de leur terrain : sans cela, cette fonction
## effacerait la variante que [TacticsArena] vient de poser si elle était
## rappelée en cours de bataille.
##
## L'arène reste la source la plus sûre : elle connaît la coordonnée de carte et
## l'altitude que le [MapData] déclare. Ici on ne dispose que de la position du
## corps de la tuile — assez pour tirer une variante stable, et c'est ce qui
## fait qu'une arène posée à la main dans une `.tscn` en profite aussi.
func configure_tile() -> void:
	hover = false
	# Set terrain material
	if TacticsScenery.needs_tile_material(terrain_type):
		terrain_mat = TacticsScenery.terrain_material_at(terrain_type, tile_coord(), position.y)
	elif TacticsConfig.terrain_material.has(terrain_type):
		terrain_mat = TacticsConfig.terrain_material[terrain_type]
	reset_markers() # Reset tile markers


## La coordonnée de damier de cette case, telle que le décor peut la hacher.
##
## La grille répond quand elle connaît la tuile. Elle ne la connaît pas encore à
## la conversion des tuiles — elle se bâtit après —, d'où le repli sur la
## position : peu importe que la coordonnée soit celle de la carte, il suffit
## qu'elle soit **stable** et distincte d'une case à l'autre.
func tile_coord() -> Vector2i:
	var grid: BattleGrid = BattleGrid.current
	if grid and grid.has_tile(self):
		return grid.coord_of(self)
	return Vector2i(roundi(position.x), roundi(position.z))
#endregion
