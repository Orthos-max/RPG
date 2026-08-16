class_name TacticsAutoTiler
extends RefCounted
## Les transitions entre terrains : rive, lisière, plage, bord de route.
##
## Chaque case portait une texture 32 × 32 unie, découpée sur la limite exacte
## du carreau. Une forêt posée contre une plaine y faisait un mur au cordeau —
## une frontière que rien dans le paysage ne justifie, et qui trahissait le
## damier sous le décor.
##
## Le pack SSCAP est pourtant bâti pour ça : chaque terrain « posé sur de
## l'herbe » y occupe un bloc de seize cellules, une par voisinage possible en
## croix. [code]art/decouper-bords.py[/code] les extrait dans
## [code]assets/textures/terrain/edges/[/code] ; ce service les choisit.
##
## ## La transition appartient au terrain, pas à l'herbe
##
## On attend l'inverse : « cette case d'herbe a de l'eau à l'est, donc elle
## montre une rive à droite ». Le pack impose l'autre sens — la rive est
## dessinée **dans la case d'eau**, sur un fond d'herbe, et c'est plus juste :
## une berge appartient à l'étang, pas à la prairie. Une case d'herbe n'a donc
## jamais rien à afficher de spécial, quels que soient ses voisins, et l'herbe
## reste ce qu'elle est partout — le fond du tableau.
##
## Conséquence pratique : seuls les terrains listés dans [constant EDGE_SETS]
## reçoivent un habillage. Tout le reste — mur, fosse, pont — garde son
## remplissage, et rien n'est à ajouter pour qu'il continue de fonctionner.
##
## ## Sur quel fond la transition se dessine
##
## Le pack ne connaît qu'un fond : l'herbe. Une rive d'eau collée à une plage
## affichait donc **eau | herbe | sable** — six pixels de prairie entre deux
## terrains qui n'en ont jamais vu. Le masque disait pourtant juste ; c'est la
## tuile qui n'avait qu'un voisin possible.
##
## `art/bords-paires.py` engendre le jeu manquant dans
## [constant PAIR_DIR] : le bord de A dessiné sur le fond de B, pour chaque
## couple de terrains. La case lit donc **deux** choses de son voisinage — de
## quels côtés son terrain s'arrête ([method mask_at]), et ce qui commence
## alors ([method neighbors_at]) — et compose `water_sand_n` au lieu de
## `water_n`.
##
## ## Un calque **par côté**, et non un par case
##
## Un seul calque par case ne portait qu'un fond : une plage qui a la mer à l'est
## et un bois à l'ouest choisissait le voisin **dominant** et bordait des deux
## côtés sur la même chose — de l'eau à gauche de la forêt, ou l'inverse. Le
## masque savait pourtant tout ce qu'il fallait ; c'est le calque unique qui ne
## pouvait pas le dire.
##
## Chaque côté porté reçoit donc **sa** bande ([method band_mesh]), texturée de
## la tuile à masque simple de ce côté et du fond de son voisin **réel** :
## `sand_water_e` à droite, `sand_forest_w` à gauche. Le centre de la case n'est
## couvert par rien et garde le matériau de terrain — il n'a pas de transition à
## montrer. `fill`, donc, ne pose plus aucun calque.
##
## ## Une frontière, une seule bande
##
## Chaque case portait alors la sienne, et les deux côtés d'une même frontière
## étaient dessinés deux fois : le sable montrait sa lisière d'eau à l'est
## pendant que la mer montrait sa grève de sable à l'ouest, dos à dos. Deux
## transitions pour une seule limite, donc un double liseré, et deux dessins qui
## ne racontent pas la même chose de la même ligne. Le masque disait « mon
## terrain s'arrête ici » ; les deux voisines le disaient en même temps, et
## toutes deux avaient raison.
##
## Une frontière n'a donc plus qu'un porteur, et [constant TERRAIN_PRIORITY] dit
## lequel : le plus haut des deux terrains. La règle est locale et symétrique —
## les deux cases la lisent chacune de leur côté et en tirent la même conclusion,
## sans avoir à se consulter ni à s'accorder sur un ordre de passage.
##
## Le rang va du terrain qui se pose sur le paysage à celui qui le termine : un
## fortin est bâti sur la prairie, un chemin la traverse, une plage la borde, un
## bois la mange, la neige et le marais la recouvrent, l'eau l'arrête. Le plus
## haut dessine son propre contour, ce qui donne exactement la lecture qu'on
## attend d'un tableau : la rive appartient à l'étang, la lisière au bois, la
## grève à la mer.
##
## La prairie est à zéro et ne porte donc jamais rien, quels que soient ses
## voisins — c'est le parti du pack rappelé plus haut, tenu jusqu'au bout. Un
## terrain sans bords — mur, pont, fosse — ne porte rien non plus (il n'a rien à
## porter), mais il ne dispense pas son voisin : il compte pour moins que tout le
## reste, si bien qu'une plage collée à un rempart borde quand même.
##
## Deux bandes se croisent au coin, et la seconde recouvre la première ; chacune
## est posée un cheveu plus haut que la précédente ([constant SIDE_LIFT]) pour
## que le recouvrement soit décidé une fois pour toutes plutôt que clignoté à
## chaque image. Un coin appartient à deux voisins : il faut bien qu'il en
## trahisse un, et le trahir de façon stable est tout ce qu'on peut promettre.
##
## Toute paire absente — voisin d'herbe, voisin sans fond dessiné, tuile jamais
## engendrée — retombe sur la tuile d'origine à fond d'herbe. C'est le
## comportement d'avant, à l'identique : rien ne peut régresser.
##
## ## Un calque, pas un remplacement
##
## Le dessus de la case reçoit ses quadrilatères à part, posés quelques
## millimètres au-dessus du `BoxMesh`. Deux raisons, et la seconde est la vraie :
##
## 1. Le matériau de terrain est projeté en coordonnées **monde**
##    ([TacticsScenery]) — le motif traverse les cases au lieu de recommencer sur
##    chacune. C'est exactement ce qu'il ne faut pas d'une tuile de bord, qui
##    doit tomber sur SA case, dans SON sens. Le calque porte des UV écrites à
##    la main : `+X` va vers la droite de l'image, `+Z` vers le bas. Aucune
##    convention à deviner, donc aucune rive à l'envers.
## 2. Le surlignage tactique ([TacticsTile]) pose un `material_override` sur le
##    dessus de la case. Un calque séparé se teinte de la même façon et par le
##    même chemin : les cases bleues et rouges restent lisibles par-dessus la
##    rive au lieu d'être recouvertes par elle.

const MapDataClass = preload("res://data/models/world/map/map_data.gd")

## Préfixe des nœuds de calque : un par côté porté, `AutoTile_n`, `AutoTile_e`…
##
## Cherchés et reposés à l'identique d'une bataille à l'autre, et retirés dès que
## leur côté cesse d'être porté — l'éditeur repeint une voisine, la bande s'en va.
const OVERLAY_NODE: String = "AutoTile"

## Terrains qui reçoivent des bords, et le jeu de tuiles qui les porte.
##
## La montagne y est depuis le 2026-08-12 : elle est franchissable (coût 2),
## donc souvent collée à une plaine que l'œil traverse — ses bords sont
## synthétisés par `art/decouper-bords.py` (le pack SSCAP n'en fournit pas).
##
## La prairie y est depuis le 2026-08-16, et c'est un pas de côté par rapport au
## parti du pack rappelé plus haut : l'herbe n'était le fond de personne d'autre
## qu'elle-même, donc ne montrait jamais rien. Elle dit maintenant, elle aussi,
## de quel côté elle s'arrête — ses tuiles sont engendrées par
## `art/bords-prairie.py`, qui n'a que `edges-pairs/` à remplir puisqu'une
## prairie sur fond de prairie n'existe pas.
const EDGE_SETS: Dictionary = {
	MapDataClass.TerrainType.GRASS: "grass",
	MapDataClass.TerrainType.WATER: "water",
	MapDataClass.TerrainType.FOREST: "forest",
	MapDataClass.TerrainType.SAND: "sand",
	MapDataClass.TerrainType.PATH: "path",
	MapDataClass.TerrainType.MOUNTAIN: "mountain",
	MapDataClass.TerrainType.VILLAGE: "village",
	MapDataClass.TerrainType.FORT: "fort",
	MapDataClass.TerrainType.SNOW: "snow",
	MapDataClass.TerrainType.SWAMP: "swamp",
}

## Rang d'un terrain absent de [constant TERRAIN_PRIORITY] : sous la prairie.
##
## Mur, porte, tour, ruine, pont, fosse : ils n'ont pas de bords, donc rien à
## porter. Les mettre en dessous de tout plutôt que hors du jeu est ce qui fait
## qu'une plage bordant un rempart borde quand même — leur voisin, lui, a bien
## une transition à montrer, et personne d'autre ne la montrera.
const NO_PRIORITY: int = -1

## Qui, de deux terrains voisins, dessine la frontière qui les sépare.
##
## Les deux cases lisent cette table chacune de son côté : celle qui a le rang le
## plus haut porte la bande, l'autre ne montre rien de ce côté-là. C'est ce qui
## garantit une seule transition par limite au lieu des deux qui se recouvraient.
##
## L'ordre va du terrain posé sur le paysage à celui qui l'arrête. La prairie
## ouvre à zéro et ne porte donc jamais rien : elle est le fond de tout le monde.
## L'eau ferme la marche et porte donc toujours sa rive, y compris contre un
## marais ou de la neige — c'est le terrain dont la limite est la plus nette à
## l'œil, et celui qu'on regarde en premier sur une carte.
const TERRAIN_PRIORITY: Dictionary = {
	MapDataClass.TerrainType.GRASS: 0,
	MapDataClass.TerrainType.FORT: 1,
	MapDataClass.TerrainType.VILLAGE: 2,
	MapDataClass.TerrainType.PATH: 3,
	MapDataClass.TerrainType.SAND: 4,
	MapDataClass.TerrainType.FOREST: 5,
	MapDataClass.TerrainType.MOUNTAIN: 6,
	MapDataClass.TerrainType.SNOW: 7,
	MapDataClass.TerrainType.SWAMP: 8,
	MapDataClass.TerrainType.WATER: 9,
}

## Dossier des tuiles de bord, à fond d'herbe — le repli de toute paire absente.
const EDGE_DIR: String = "res://assets/textures/terrain/edges/"

## Dossier des tuiles de bord **par paire**, `{A}_{B}_{masque}.png`.
const PAIR_DIR: String = "res://assets/textures/terrain/edges-pairs/"

## Terrains qui savent servir de **fond** à la transition d'un voisin.
##
## Ce sont les surfaces qu'`art/bords-paires.py` sait peindre derrière un bord.
## L'herbe n'y est pas, bien qu'elle ait maintenant ses propres bords : c'est
## déjà le fond des tuiles de [constant EDGE_DIR], donc le cas que le repli
## couvre — l'y ajouter demanderait de recopier `edges/` en neuf exemplaires
## sous un autre nom. Un terrain absent d'ici — un mur, un pont, une ruine —
## laisse son voisin border sur de l'herbe, comme avant.
const BACKGROUND_SETS: Dictionary = {
	MapDataClass.TerrainType.WATER: "water",
	MapDataClass.TerrainType.FOREST: "forest",
	MapDataClass.TerrainType.SAND: "sand",
	MapDataClass.TerrainType.PATH: "path",
	MapDataClass.TerrainType.SNOW: "snow",
	MapDataClass.TerrainType.SWAMP: "swamp",
	MapDataClass.TerrainType.MOUNTAIN: "mountain",
}

## Décalage vertical du calque au-dessus du dessus de la case.
##
## Assez pour que le rendu tranche entre les deux surfaces au lieu de les faire
## clignoter l'une dans l'autre, assez peu pour qu'aucune caméra du jeu ne voie
## le calque flotter.
const OVERLAY_LIFT: float = 0.006

## Écart entre deux bandes voisines, dans l'ordre n, e, s, w.
##
## Deux bandes qui se croisent au coin sont coplanaires : la carte de profondeur
## n'y départage rien et le coin scintille au moindre mouvement de caméra. Un
## cheveu d'écart tranche à la place — l'ouest passe devant le nord, toujours.
const SIDE_LIFT: float = 0.0008

## Part de la case couverte par la bande d'un côté.
##
## Mesurée sur les tuiles elles-mêmes : le fond du voisin y descend jusqu'au
## neuvième pixel sur trente-deux (le bord ouest du fortin, le plus profond de
## tous), et le liseré sombre qui l'accompagne d'un ou deux de plus. Dix pixels
## couvrent donc toute transition dessinée — en couper une plus court laisserait
## reparaître, sous la bande, la bande d'herbe que les paires ont fait
## disparaître.
const BAND_RATIO: float = 0.3125

## Côtés du masque, dans l'ordre où les lettres s'écrivent, et leur direction
## en coordonnées de grille.
##
## `n` est le côté qui regarde les lignes décroissantes, `s` les croissantes :
## c'est le sens dans lequel [TacticsArena] pose ses cases (la ligne 0 au plus
## petit `z`), et celui dans lequel une image se lit (la première rangée de
## pixels en haut). Les deux coïncident, donc `n` est bien le haut de l'image.
const SIDES: Array[Array] = [
	["n", Vector2i(0, -1)],
	["e", Vector2i(1, 0)],
	["s", Vector2i(0, 1)],
	["w", Vector2i(-1, 0)],
]

## Matériaux de calque déjà bâtis, par « terrain:masque:fond ».
static var _material_cache: Dictionary = {}
## Quadrilatères déjà bâtis, par côté (deux tailles de case suffisent en pratique).
static var _quad_cache: Dictionary = {}


#region Pose
## Habille toutes les cases d'une grille.
##
## Appelée une fois la grille bâtie, donc une fois les terrains connus. Elle est
## idempotente : relancée sur une arène déjà habillée, elle remplace le matériau
## de chaque calque au lieu d'en empiler un second. L'éditeur de cartes s'en
## sert pour rafraîchir le plateau après un coup de pinceau.
static func apply_to_grid(grid: BattleGrid) -> void:
	if not grid:
		return
	var span: Vector2i = grid.dimensions()
	for row: int in span.y:
		for col: int in span.x:
			var cell := Vector2i(col, row)
			var tile: Node = grid.tile_at_cell(cell)
			if tile is TacticsTile:
				apply_to_tile(grid, cell, tile as TacticsTile)


## Habille une case : une bande par côté porté, chacune sur le fond de son voisin.
##
## Les côtés qu'elle ne porte plus — parce qu'ils ne bordent rien, parce que le
## voisin l'emporte désormais, ou parce que la tuile manque — perdent la leur :
## l'éditeur repeint une voisine, et la rive s'efface sans laisser de calque
## orphelin derrière elle.
static func apply_to_tile(grid: BattleGrid, cell: Vector2i, tile: TacticsTile) -> void:
	var top: MeshInstance3D = tile.get_node_or_null("Tile") as MeshInstance3D
	if not top or not top.mesh:
		return
	var box: AABB = top.mesh.get_aabb()

	var terrain: int = int(tile.terrain_type)
	var mask: String = mask_at(grid, cell, terrain)
	var backgrounds: Dictionary = neighbors_at(grid, cell, terrain)

	var layers: Array[MeshInstance3D] = []
	var materials: Array[StandardMaterial3D] = []
	for rank: int in SIDES.size():
		var side: String = str(SIDES[rank][0])
		var node_name: String = "%s_%s" % [OVERLAY_NODE, side]
		var overlay: MeshInstance3D = tile.get_node_or_null(node_name) as MeshInstance3D

		var material: StandardMaterial3D = null
		if mask.contains(side):
			material = overlay_material(terrain, side, int(backgrounds.get(side, -1)))
		if not material:
			# Terrain sans bords, côté qui ne borde plus, ou tuile manquante du
			# dossier `edges/`. Sortir de l'arbre avant de libérer : un nœud
			# seulement `queue_free` garde son nom jusqu'à la fin de l'image, et
			# c'est le nom qui retrouve la bande d'un côté.
			if overlay:
				tile.remove_child(overlay)
				overlay.queue_free()
			continue

		if not overlay:
			overlay = MeshInstance3D.new()
			overlay.name = node_name
			# Le calque ne projette pas d'ombre : il double le dessus de la case, et
			# deux surfaces à six millièmes l'une de l'autre s'ombrageraient l'une
			# l'autre en un moiré de bandes sombres.
			overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tile.add_child(overlay)

		overlay.mesh = band_mesh(box.size.x, box.size.z, side)
		overlay.position = Vector3(box.get_center().x,
			box.end.y + OVERLAY_LIFT + float(rank) * SIDE_LIFT, box.get_center().z)
		overlay.material_override = material
		layers.append(overlay)
		materials.append(material)

	tile.set_autotile(layers, materials)
#endregion


#region Choix de la tuile
## Le rang d'un terrain dans la règle du porteur.
##
## [constant NO_PRIORITY] pour tout terrain sans bords : il ne l'emporte sur
## personne, pas même sur un autre terrain sans bords.
static func priority_of(terrain: int) -> int:
	return int(TERRAIN_PRIORITY.get(terrain, NO_PRIORITY))


## Cette case dessine-t-elle la frontière qui la sépare de ce voisin ?
##
## Le seul juge de « qui porte quoi », et le seul endroit où la question se
## tranche. L'éditeur de cartes l'appelle aussi ([MapEditorLevel]) : la même règle
## écrite deux fois aurait divergé au premier terrain ajouté, et la carte peinte
## aurait cessé de ressembler à la carte jouée.
##
## Faux quand les deux terrains sont le même — leurs rangs sont égaux, et une
## frontière entre une case et son semblable n'existe pas.
static func carries(terrain: int, neighbor: int) -> bool:
	return priority_of(terrain) > priority_of(neighbor)


## Le masque d'une case : les côtés dont **elle** porte la bande.
##
## C'étaient les côtés où son terrain s'arrête, ce qui en faisait dessiner deux
## par frontière. Ce sont maintenant ceux où il s'arrête **et** l'emporte sur ce
## qui commence ([method carries]) : la case d'eau porte sa rive, la plage d'en
## face ne porte rien, et la limite n'est tracée qu'une fois.
##
## Les lettres sortent dans l'ordre n, e, s, w — celui des noms de fichiers.
## `fill` quand la case n'a aucun côté à porter, qu'elle soit au milieu de son
## terrain ou cernée de plus fort qu'elle.
##
## **Hors grille ne se porte pas.** Une rive dessinée au bord du plateau
## montrerait de l'herbe là où il n'y a rien du tout : le damier s'arrête sur le
## vide, et le flanc de la case dit déjà la coupure.
static func mask_at(grid: BattleGrid, cell: Vector2i, terrain: int) -> String:
	if not grid or not EDGE_SETS.has(terrain):
		return "fill"

	var mask: String = ""
	for side: Array in SIDES:
		var neighbor: Node = grid.tile_at_cell(cell + (side[1] as Vector2i))
		if neighbor and carries(terrain, int(neighbor.terrain_type)):
			mask += str(side[0])
	return mask if not mask.is_empty() else "fill"


## Ce qui borde une case, **côté par côté** : `{"n": WATER, "w": FOREST}`.
##
## [method mask_at] dit quels côtés la case porte ; celui-ci dit ce qui commence
## de l'autre côté, et le dit pour chacun. C'était un seul terrain — le voisin
## dominant — tant qu'une case n'avait qu'un calque : une plage entre mer et
## bois bordait alors des deux côtés sur le même fond, et l'un des deux voisins
## était toujours démenti.
##
## Il répond pour **tous** les côtés qui bordent autre chose, portés ou non : le
## fond d'une bande est le voisin réel de ce côté, et savoir qui dessine la
## frontière est l'affaire de [method carries], pas la sienne.
##
## Le terrain est rendu tel quel, sans regarder [constant BACKGROUND_SETS] : un
## voisin qui ne sait pas faire fond — un mur, une porte — n'est pas une absence
## de voisin, c'est un fond qui n'a pas été dessiné, et [method _edge_paths]
## retombe alors sur la tuile à fond d'herbe. Les côtés qui ne bordent rien sont
## absents du dictionnaire, comme ils sont absents du masque.
static func neighbors_at(grid: BattleGrid, cell: Vector2i, terrain: int) -> Dictionary:
	var found: Dictionary = {}
	if not grid or not EDGE_SETS.has(terrain):
		return found

	for side: Array in SIDES:
		var tile: Node = grid.tile_at_cell(cell + (side[1] as Vector2i))
		if not tile:
			continue
		var other: int = int(tile.terrain_type)
		if other != terrain:
			found[str(side[0])] = other
	return found


## Matériau du calque d'un terrain pour un masque, ou `null` s'il n'en a pas.
##
## Le chargement passe par [method ResourceLoader.exists] pour la même raison
## que [method TacticsScenery.terrain_texture] : une image que Godot n'a pas
## encore importée ne doit pas emporter la scène, seulement priver la case de
## son bord. Les absences sont mises en cache comme les présences.
## [param neighbor] terrain qui borde la case, ou `-1` pour border sur l'herbe.
static func overlay_material(terrain: int, mask: String,
		neighbor: int = -1) -> StandardMaterial3D:
	var key: String = "%d:%s:%d" % [terrain, mask, neighbor]
	var cached: Variant = _material_cache.get(key)
	if cached != null:
		return cached as StandardMaterial3D
	if _material_cache.has(key):
		return null

	var material: StandardMaterial3D = _build_material(terrain, mask, neighbor)
	_material_cache[key] = material
	return material


## La tuile à poser : celle de la paire si elle a été engendrée, sinon celle à
## fond d'herbe.
##
## L'ordre est un ordre de préférence, pas une hiérarchie de secours : une paire
## manquante n'est pas une panne, c'est le cas ordinaire d'un voisin d'herbe.
static func _edge_paths(terrain: int, mask: String, neighbor: int) -> Array[String]:
	var set_name: String = str(EDGE_SETS[terrain])
	var paths: Array[String] = []
	if BACKGROUND_SETS.has(neighbor) and neighbor != terrain:
		paths.append("%s%s_%s_%s.png" % [
			PAIR_DIR, set_name, str(BACKGROUND_SETS[neighbor]), mask])
	paths.append("%s%s_%s.png" % [EDGE_DIR, set_name, mask])
	return paths


static func _build_material(terrain: int, mask: String,
		neighbor: int) -> StandardMaterial3D:
	if not EDGE_SETS.has(terrain):
		return null

	var texture: Texture2D = null
	for path: String in _edge_paths(terrain, mask, neighbor):
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
		if texture:
			break
	if not texture:
		return null

	var grain: Dictionary = TacticsScenery.TERRAIN_GRAIN.get(
		terrain, TacticsScenery.TERRAIN_GRAIN[MapDataClass.TerrainType.GRASS])

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# La réponse à la lumière reste celle du terrain : l'eau accroche le soleil,
	# le sable non. C'est ce qui empêche le calque de se détacher du plateau.
	material.roughness = float(grain["roughness"])
	material.metallic = float(grain["metallic"])
	# Le pixel art filtré linéairement devient une purée ; les mipmaps évitent le
	# grésillement des cases lointaines sous la caméra tactique.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# Le quadrilatère n'a qu'une face utile, et l'orientation d'une face dépend
	# d'un ordre de sommets qu'on n'a pas envie de devoir démontrer. On désactive
	# l'élimination : le calque est visible de partout, et il est plat.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
#endregion


#region Géométrie
## La bande d'un côté du dessus d'une case, UV écrites à la main.
##
## `u` suit `+X`, `v` suit `+Z` : le coin de l'image en haut à gauche tombe sur
## le coin de la case au plus petit `x` et au plus petit `z`. C'est toute la
## convention, et elle tient en une ligne parce qu'elle est posée ici plutôt que
## déduite d'un `PlaneMesh` ou d'une projection triplanaire.
##
## La bande ne prend qu'une lisière de la case, et **la même** de la tuile : le
## quadrilatère nord couvre le dixième supérieur du carreau et n'y lit que le
## dixième supérieur de l'image. C'est ce qui permet à quatre bandes de porter
## quatre tuiles différentes sans qu'aucune ne mente sur son côté.
## [param side] `n`, `e`, `s` ou `w` ; toute autre valeur rend la case entière.
static func band_mesh(width: float, depth: float, side: String) -> ArrayMesh:
	var key: String = "%.4f:%.4f:%s" % [width, depth, side]
	var cached: Variant = _quad_cache.get(key)
	if cached is ArrayMesh:
		return cached

	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var x0: float = -half_x
	var x1: float = half_x
	var z0: float = -half_z
	var z1: float = half_z
	var u0: float = 0.0
	var u1: float = 1.0
	var v0: float = 0.0
	var v1: float = 1.0
	match side:
		"n":
			z1 = -half_z + depth * BAND_RATIO
			v1 = BAND_RATIO
		"s":
			z0 = half_z - depth * BAND_RATIO
			v0 = 1.0 - BAND_RATIO
		"w":
			x1 = -half_x + width * BAND_RATIO
			u1 = BAND_RATIO
		"e":
			x0 = half_x - width * BAND_RATIO
			u0 = 1.0 - BAND_RATIO

	var vertices := PackedVector3Array([
		Vector3(x0, 0.0, z0),
		Vector3(x1, 0.0, z0),
		Vector3(x1, 0.0, z1),
		Vector3(x0, 0.0, z1),
	])
	var uvs := PackedVector2Array([
		Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_quad_cache[key] = mesh
	return mesh
#endregion
