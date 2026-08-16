class_name CustomBattle
extends RefCounted
## Transforme une carte du joueur ([MapDocument]) en niveau jouable.
##
## Aucune scène n'est créée de toutes pièces : on part de la carte procédurale
## du jeu, on lui substitue le relief du document et on repeuple les camps.
## Tout ce qui suit — boucle de tour, IA, pont CielAI, objectif, déploiement —
## fonctionne alors exactement comme pour un chapitre de la campagne.
##
## À appeler **avant** d'ajouter le niveau à l'arbre : l'arène génère ses tuiles
## dans `_ready`, à partir du relief qu'elle trouve à ce moment-là.

const LEVEL_SCENE = preload("res://assets/maps/level/map_level.tscn")
const PAWN_SCENE = preload("res://data/modules/tactics/level/pawn/pawn.tscn")
const EXPERTISE_SCENE = preload("res://data/modules/stats/expertise/expertise.tscn")

## Hauteur du pion au-dessus du dessus de sa tuile
const PAWN_LIFT: float = 0.5

## Fiche prêtée à un personnage écrit par le joueur, le temps qu'il entre en
## scène. Tout y est réécrit ensuite : seul compte qu'elle existe.
const CUSTOM_UNIT_TEMPLATE: String = "res://data/models/world/stats/hero/lord.tres"


## Construit un niveau jouable à partir d'une carte. Renvoie null si elle est vide.
static func build(doc: MapDocument) -> Node:
	if not doc:
		return null

	var level: Node = LEVEL_SCENE.instantiate()
	_apply_terrain(level, doc)
	_populate(level, doc)
	return level


## Substitue le relief du document à celui de la carte de départ.
##
## La ressource d'arène est dupliquée : elle est partagée par toutes les scènes
## du jeu, la modifier en place abîmerait la carte d'origine pour la session.
static func _apply_terrain(level: Node, doc: MapDocument) -> void:
	var arena: Node = level.get_node_or_null("TacticsArena")
	if not arena:
		push_error("[CustomBattle] La scène de niveau n'a pas d'arène.")
		return
	var res: Resource = arena.get("res")
	if not res:
		push_error("[CustomBattle] L'arène n'a pas de ressource de configuration.")
		return

	var copy: Resource = res.duplicate(true)
	copy.map_data = doc.to_map_data()
	arena.set("res", copy)


## Vide les camps de la carte de départ et y pose les unités du document.
static func _populate(level: Node, doc: MapDocument) -> void:
	var camps: Dictionary = {
		MapDocument.TEAM_PLAYER: level.get_node_or_null("TacticsParticipant/TacticsPlayer"),
		MapDocument.TEAM_OPPONENT: level.get_node_or_null("TacticsParticipant/TacticsOpponent"),
	}

	for team: String in camps:
		var camp: Node = camps[team]
		if not camp:
			continue
		for child in camp.get_children():
			camp.remove_child(child)
			child.free()  # Hors de l'arbre : libération immédiate, pas de frame à attendre.

	var counters: Dictionary = {MapDocument.TEAM_PLAYER: 0, MapDocument.TEAM_OPPONENT: 0}
	for unit: Dictionary in doc.units:
		var team: String = str(unit.get("team", MapDocument.TEAM_OPPONENT))
		var camp: Node = camps.get(team, null)
		if not camp:
			continue
		var path: String = str(unit.get("path", ""))
		if not ResourceLoader.exists(path):
			push_warning("[CustomBattle] Unité introuvable, ignorée : %s" % path)
			continue

		counters[team] = int(counters[team]) + 1
		var pawn: Node3D = _make_pawn(path, int(counters[team]))
		# Ce que le pion doit devenir une fois en scène. Rien ne peut s'appliquer
		# ici : `Stats` n'existe qu'au `_ready` du pion, et le niveau n'est pas
		# encore dans l'arbre. Voir [method apply_levels].
		pawn.set_meta("start_level", clampi(int(unit.get("level", 1)),
			MapDocument.MIN_LEVEL, MapDocument.MAX_LEVEL))
		if MapDocument.is_custom_unit(path):
			pawn.set_meta("custom_unit", path)
		camp.add_child(pawn)
		# Position locale : le niveau n'est pas encore dans l'arbre, `global_position`
		# n'y voudrait rien dire — d'où le décalage des camps retranché à la main.
		var target: Vector3 = world_position(
			doc, Vector2i(int(unit.get("col", 0)), int(unit.get("row", 0)))
		)
		pawn.position = target - camp_offset(camp, level)


## Un pion complet : la scène de pion et son expertise, avant l'entrée en scène.
##
## L'ordre compte — `TacticsPawn` lit `$Expertise/Stats` dans son `_ready`, donc
## l'expertise doit être en place avant que le pion rejoigne l'arbre.
static func _make_pawn(stats_path: String, index: int) -> Node3D:
	var pawn: Node3D = PAWN_SCENE.instantiate()
	# Le suffixe du nom affiché vient du nom de nœud : « Pawn », « Pawn2 »…
	pawn.name = "Pawn" if index <= 1 else "Pawn%d" % index

	var expertise: Node = EXPERTISE_SCENE.instantiate()
	expertise.name = "Expertise"
	# Un personnage écrit par le joueur n'est pas une ressource : il n'a pas de
	# `.tres` à charger. On lui prête une fiche de départ, entièrement réécrite
	# ensuite par [method apply_levels] — le pion a besoin de *quelque chose* à
	# lire dans son `_ready`, pas de la bonne chose.
	expertise.starting_stats = load(
		CUSTOM_UNIT_TEMPLATE if MapDocument.is_custom_unit(stats_path) else stats_path)
	pawn.add_child(expertise)
	return pawn


## Applique aux pions ce qui ne pouvait pas l'être avant leur entrée en scène :
## la fiche d'un personnage écrit à la main, puis le niveau de départ.
##
## À appeler une fois le niveau dans l'arbre — c'est là seulement que chaque pion
## a passé son `_ready`, donc qu'il a des statistiques à modifier.
static func apply_levels(level: Node) -> void:
	if not level or not is_instance_valid(level):
		return
	for pawn: Node in _pawns_of(level):
		var stats: Object = pawn.get("stats")
		if not stats:
			continue

		# La fiche d'abord : elle remplace classe, statistiques et arsenal. Monter
		# en niveau avant elle ferait grandir la mauvaise unité.
		if pawn.has_meta("custom_unit"):
			var slug: String = str(pawn.get_meta("custom_unit")) \
				.trim_prefix(MapDocument.CUSTOM_PREFIX).trim_suffix(".json")
			var doc: UnitDocument = UnitLibrary.load_unit(slug)
			if doc:
				ChapterRunner.apply_roster_unit(stats, doc.to_roster_unit())

		var target: int = int(pawn.get_meta("start_level", 1))
		if target > stats.level:
			stats.raise_to_level(target)


static func _pawns_of(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children():
		if child is TacticsPawn:
			out.append(child)
		else:
			out.append_array(_pawns_of(child))
	return out


## Décalage cumulé d'un camp par rapport à la racine du niveau.
##
## Les scènes de carte décalent `TacticsParticipant` d'une demi-case : c'est ce
## qui fait tomber leurs pions, posés à des coordonnées entières, au centre des
## tuiles. Un pion placé à la main doit retrancher ce décalage, sinon il atterrit
## au coin de quatre tuiles — là où le rayon qui cherche le sol ne touche rien,
## et où l'unité ne sait plus sur quelle case elle se tient.
static func camp_offset(camp: Node, level: Node) -> Vector3:
	var offset: Vector3 = Vector3.ZERO
	var node: Node = camp
	while node and node != level:
		if node is Node3D:
			offset += (node as Node3D).position
		node = node.get_parent()
	return offset


## Position monde du dessus d'une case, prête à recevoir un pion.
##
## Reprend la formule de génération de l'arène : grille centrée sur l'origine,
## tuile s'élevant de 0 à sa hauteur.
static func world_position(doc: MapDocument, pos: Vector2i) -> Vector3:
	var ts: float = doc.tile_size
	var half := Vector2(float(doc.grid_size.x) / 2.0, float(doc.grid_size.y) / 2.0)
	# Le plancher du terrain compris : une montagne se dresse d'une unité même
	# quand la carte la laisse au ras de l'herbe ([method MapData.elevation]), et
	# un pion posé à la hauteur déclarée y naîtrait sous la roche.
	var height: float = MapData.elevation(doc.terrain_at(pos), doc.height_at(pos))
	return Vector3(
		(float(pos.x) - half.x + 0.5) * ts,
		height + PAWN_LIFT,
		(float(pos.y) - half.y + 0.5) * ts
	)
