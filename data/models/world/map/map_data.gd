class_name MapData
extends Resource
## Grid-based map definition. Each cell defines terrain type and tile height.
## Used by TacticsArena to procedurally generate the 3D arena.

enum TerrainType {
	GRASS = 0,   ## Walkable plain, green
	FOREST = 1,  ## Walkable forest, dark green, +1 DEF bonus
	MOUNTAIN = 2,## Walkable mountain peak, brown/rock — 2 points de mouvement, +3 DEF
	WATER = 3,   ## Impassable water, blue
	PATH = 4,    ## Walkable dirt path, beige
	WALL = 5,    ## Impassable wall, dark grey
	PIT = 6,     ## Impassable pit/chasm, black
	VILLAGE = 7,   ## Hameau franchissable, +1 DEF
	FORT = 8,      ## Fortin franchissable, +2 DEF
	GATE = 9,      ## Porte franchissable, +1 DEF — la case qu'on vient prendre
	RUINS = 10,    ## Ruines franchissables, +1 DEF
	TOWER = 11,    ## Tour de guet infranchissable
	BRIDGE = 12,   ## Pont franchissable, planches au-dessus de l'eau
	SAND = 13,     ## Sable franchissable
	SNOW = 14,     ## Neige franchissable
	SWAMP = 15,    ## Marais franchissable
}

## Tout ce qu'un terrain est, en un seul endroit.
##
## Chaque terrain était décrit cinq fois : ici pour sa franchissabilité, dans
## [TacticsScenery] pour sa teinte, dans [TacticsGrid] pour son nom technique,
## dans [UnitSheet] pour son nom français, dans [CielAI] pour sa légende. En
## ajouter un demandait de visiter les cinq et d'en oublier un.
##
## - `key` : nom technique — pont CielAI, fiches d'unité.
## - `label` : nom français affiché au joueur.
## - `code` : la lettre de la carte ASCII envoyée à Ciel. **Unique** : c'est ce
##   qui manquait, la première lettre confondait `water` avec `wall` et `path`
##   avec `pit`, alors que la légende annonçait des lettres distinctes.
## - `walk` : la case se traverse-t-elle.
## - `def` : bonus de défense pour qui s'y tient.
## - `cost` : points de mouvement dépensés pour **entrer** sur la case. Un partout,
##   sauf la montagne : y grimper coûte le double, et c'est tout le choix qu'elle
##   pose — la contourner, ou payer le prix pour tenir ses +3 DÉF. Sans objet
##   quand `walk` est faux : on n'entre pas.
const TERRAINS: Dictionary = {
	TerrainType.GRASS:    {"key": "grass",    "label": "Plaine",   "code": "g", "walk": true,  "def": 0, "cost": 1},
	TerrainType.FOREST:   {"key": "forest",   "label": "Forêt",    "code": "f", "walk": true,  "def": 1, "cost": 1},
	TerrainType.MOUNTAIN: {"key": "mountain", "label": "Montagne", "code": "m", "walk": true,  "def": 3, "cost": 2},
	TerrainType.WATER:    {"key": "water",    "label": "Eau",      "code": "w", "walk": false, "def": 0, "cost": 1},
	TerrainType.PATH:     {"key": "path",     "label": "Chemin",   "code": "p", "walk": true,  "def": 0, "cost": 1},
	TerrainType.WALL:     {"key": "wall",     "label": "Mur",      "code": "#", "walk": false, "def": 0, "cost": 1},
	TerrainType.PIT:      {"key": "pit",      "label": "Fosse",    "code": "x", "walk": false, "def": 0, "cost": 1},
	TerrainType.VILLAGE:  {"key": "village",  "label": "Village",  "code": "v", "walk": true,  "def": 1, "cost": 1},
	TerrainType.FORT:     {"key": "fort",     "label": "Fortin",   "code": "F", "walk": true,  "def": 2, "cost": 1},
	TerrainType.GATE:     {"key": "gate",     "label": "Porte",    "code": "G", "walk": true,  "def": 1, "cost": 1},
	TerrainType.RUINS:    {"key": "ruins",    "label": "Ruines",   "code": "r", "walk": true,  "def": 1, "cost": 1},
	TerrainType.TOWER:    {"key": "tower",    "label": "Tour",     "code": "T", "walk": false, "def": 0, "cost": 1},
	TerrainType.BRIDGE:   {"key": "bridge",   "label": "Pont",     "code": "b", "walk": true,  "def": 0, "cost": 1},
	TerrainType.SAND:     {"key": "sand",     "label": "Sable",    "code": "s", "walk": true,  "def": 0, "cost": 1},
	TerrainType.SNOW:     {"key": "snow",     "label": "Neige",    "code": "n", "walk": true,  "def": 0, "cost": 1},
	TerrainType.SWAMP:    {"key": "swamp",    "label": "Marais",   "code": "~", "walk": true,  "def": 0, "cost": 1},
}

## Altitude minimale qu'un terrain s'impose, quoi qu'en dise la carte.
##
## La montagne y est seule, et à une unité pleine. Elle était rendue à la hauteur
## déclarée par le `height_grid` — le plus souvent la même que la plaine d'à côté,
## ou 0,45 sur les cartes qui la surélèvent un peu : un aplat de roche posé au ras
## de l'herbe, qu'aucun relief ne distinguait. Or c'est le seul terrain dont le
## nom **est** une altitude, et le seul qui coûte deux points de mouvement pour
## cette raison-là. Le plateau doit le dire avant la légende.
##
## Une unité, et pas plus : le pas le plus faible du jeu vaut 2
## ([member StatsRes.jump]), une case s'élève de sa hauteur / 2 (son volume monte
## de 0 à `height`, et c'est son **centre** que [BattleGrid] retient), donc une
## montagne contre une plaine fait une marche de 0,5 — franchissable par tout le
## monde, y compris le plus lourd des chevaliers.
##
## Le plancher ne touche pas la donnée : [member height_grid] garde ce que la
## carte a écrit, et [method elevation] le relève à la lecture. Une carte qui
## dresse déjà sa montagne plus haut garde sa hauteur.
const TERRAIN_FLOOR: Dictionary = {
	TerrainType.MOUNTAIN: 1.0,
}

## Grid dimensions (columns × rows)
@export var grid_size: Vector2i = Vector2i(16, 10)

## Size of each tile in world units
@export var tile_size: float = 1.0

## Flattened 2D array of terrain types (int, matching TerrainType enum).
## Index = row * grid_size.x + col
@export var terrain_grid: Array[int] = []

## Flattened 2D array of tile heights (float, in world units).
## 0.0 = ground level, positive = elevated
@export var height_grid: Array[float] = []


## Initialize a default blank map (all grass, height 0)
func init_default() -> void:
	var total: int = grid_size.x * grid_size.y
	terrain_grid.resize(total)
	height_grid.resize(total)
	for i in total:
		terrain_grid[i] = TerrainType.GRASS
		height_grid[i] = 0.0


## Get terrain at grid position
func get_terrain(col: int, row: int) -> int:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= terrain_grid.size():
		return TerrainType.GRASS
	return terrain_grid[idx]


## Set terrain at grid position
func set_terrain(col: int, row: int, terrain: int) -> void:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= terrain_grid.size():
		return
	terrain_grid[idx] = terrain


## Get height at grid position
func get_height(col: int, row: int) -> float:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= height_grid.size():
		return 0.0
	return height_grid[idx]


## Set height at grid position
func set_height(col: int, row: int, h: float) -> void:
	var idx: int = row * grid_size.x + col
	if idx < 0 or idx >= height_grid.size():
		return
	height_grid[idx] = h


#region Traits d'un terrain
## Check if a terrain type is walkable
##
## Un entier inconnu se traverse : une carte écrite par une version plus récente
## du jeu doit rester jouable, pas se transformer en labyrinthe de murs.
static func is_walkable(terrain: int) -> bool:
	return bool(traits_of(terrain).get("walk", true))


## Check if a terrain type provides a defense bonus
static func get_defense_bonus(terrain: int) -> int:
	return int(traits_of(terrain).get("def", 0))


## Points de mouvement dépensés pour entrer sur cette case.
##
## Un terrain inconnu coûte un pas, pour la même raison qu'il se traverse : une
## carte écrite par une version plus récente du jeu doit rester jouable.
##
## Le plancher à 1 n'est pas décoratif — [method PathField.expand] avance de
## proche en proche, et une case gratuite (ou négative) y ferait tourner le
## parcours en rond au lieu de le terminer.
static func move_cost(terrain: int) -> float:
	return maxf(1.0, float(traits_of(terrain).get("cost", 1)))


## L'altitude à laquelle une case se dresse vraiment, plancher du terrain compris.
##
## Un seul endroit où la règle est écrite, et tous les rendus y passent : la
## bataille ([TacticsArena]), l'éditeur de cartes ([MapEditorLevel]), les pions
## posés sur une carte personnalisée ([CustomBattle]) et la lecture d'avance du
## relief ([ChapterMap]). La carte dessinée est ainsi la carte jouée — c'était
## déjà la promesse des transitions, elle vaut aussi pour le relief.
##
## Un terrain sans plancher rend sa hauteur telle quelle, négative comprise : une
## fosse creusée reste creuse.
## [param terrain] Le terrain de la case.
## [param declared] La hauteur écrite dans la carte.
static func elevation(terrain: int, declared: float) -> float:
	if not TERRAIN_FLOOR.has(terrain):
		return declared
	return maxf(declared, float(TERRAIN_FLOOR[terrain]))


## Nom technique d'un terrain (`grass`, `forest`, …).
static func type_key(terrain: int) -> String:
	return str(traits_of(terrain).get("key", "unknown"))


## Nom français d'un terrain, tel qu'on le montre au joueur.
static func type_label(terrain: int) -> String:
	return str(traits_of(terrain).get("label", ""))


## Lettre du terrain sur la carte ASCII envoyée à Ciel.
static func type_code(terrain: int) -> String:
	return str(traits_of(terrain).get("code", "?"))


## Ce qu'une case vaut, en une ligne : son nom, ce qu'elle donne, ce qu'elle interdit.
##
## « Forêt · 🛡 +1 DÉF », « Montagne · 🥾 2 Mvt · 🛡 +3 DÉF », « Plaine ».
## Un seul endroit pour le dire, que la question vienne du survol en bataille ou
## d'une infobulle de l'éditeur : le joueur doit lire la même chose des deux côtés.
##
## Le coût ne s'affiche que s'il dépasse le pas ordinaire : écrire « 1 Mvt » sur
## les quinze autres terrains n'apprendrait rien et noierait le seul qui compte.
static func type_summary(terrain: int) -> String:
	var parts: Array[String] = [type_label(terrain)]
	if not is_walkable(terrain):
		parts.append("infranchissable")
	elif move_cost(terrain) > 1.0:
		parts.append("🥾 %d Mvt" % int(move_cost(terrain)))
	var bonus: int = get_defense_bonus(terrain)
	if bonus > 0:
		parts.append("🛡 +%d DÉF" % bonus)
	return " · ".join(parts)


## Nom français depuis le nom technique (`forest` → « Forêt »). "" si inconnu.
static func label_for_key(key: String) -> String:
	for terrain: int in TERRAINS:
		if str(TERRAINS[terrain]["key"]) == key:
			return str(TERRAINS[terrain]["label"])
	return ""


## Tous les types de terrain, dans l'ordre de l'énumération.
static func all_types() -> Array[int]:
	var out: Array[int] = []
	for terrain: int in TERRAINS:
		out.append(terrain)
	return out


## Légende de la carte ASCII : `{lettre: "nom (bonus)"}`.
static func legend() -> Dictionary:
	var out: Dictionary = {}
	for terrain: int in TERRAINS:
		var t: Dictionary = TERRAINS[terrain]
		var line: String = str(t["key"])
		if int(t["def"]) > 0:
			line += " (+%d DEF)" % int(t["def"])
		if not bool(t["walk"]):
			line += " (bloqué)"
		elif move_cost(terrain) > 1.0:
			# Ciel planifie ses déplacements sur cette légende : sans le coût, elle
			# compterait la montagne comme un pas et promettrait des marches qu'elle
			# ne peut pas faire.
			line += " (coût %d)" % int(move_cost(terrain))
		out[str(t["code"])] = line
	return out


## Traits d'un terrain, ou un dictionnaire vide s'il est inconnu.
static func traits_of(terrain: int) -> Dictionary:
	return TERRAINS.get(terrain, {})


#endregion
