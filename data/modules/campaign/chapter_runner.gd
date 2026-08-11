class_name ChapterRunner
extends Node
## Pilote un chapitre de campagne à l'intérieur d'un [TacticsLevel].
##
## Trois responsabilités :
##   1. appliquer le roster persistant aux pions du niveau (déploiement) ;
##   2. compter les tours et évaluer l'objectif du chapitre ([ObjectiveDB]) ;
##   3. renvoyer le résultat (victoire/défaite + objectifs secondaires) à [Main].

signal chapter_finished(victory: bool, bonuses: Array, reason: String)

const OBJ = preload("res://data/models/campaign/objective.gd")
const EXECUTOR = preload("res://data/models/world/ai/ai_executor.gd")
const DEPLOYMENT = preload("res://data/modules/campaign/deployment_phase.gd")
const PAWN_SCENE = preload("res://data/modules/tactics/level/pawn/pawn.tscn")
const EXPERTISE_SCENE = preload("res://data/modules/stats/expertise/expertise.tscn")

## Fiche prêtée à une recrue qui n'a pas de `.tres` — un personnage écrit dans
## l'éditeur n'est pas une ressource. Tout y est réécrit par
## [method apply_roster_unit] : seul compte qu'elle existe au `_ready` du pion.
const FALLBACK_SHEET: String = "res://data/models/world/stats/hero/lord.tres"

## Intervalle d'évaluation de l'objectif (secondes)
const CHECK_INTERVAL: float = 0.5

var chapter: ChapterData = null
var level: TacticsLevel = null

var turn: int = 1
var _finished: bool = false
var _accum: float = 0.0
var _turn_counted: bool = false
var _deployed_names: Array = []
## Tuile du point de commandement, quand le chapitre en demande un
var _seize_tile: TacticsTile = null
## Placement des unités en cours : l'objectif ne s'évalue pas avant le tour 1
var _deploying: bool = false

## Dernier état connu de chaque unité du joueur, `id` → instantané.
##
## **C'est la mémoire des morts.** Un pion tombé est rendu invisible, privé de
## ses collisions, puis **libéré une demi-seconde plus tard** ; or le report au
## roster ne lit que les pions encore dans l'arbre, et il n'a lieu qu'à la fin du
## chapitre. Tout ce qui était mort depuis plus d'une demi-seconde n'était donc
## jamais reporté : Lissa, Virion et Chrom tombent, on recommence, et seule
## Lissa est morte — celle qui a chuté en dernier, la seule encore là quand
## l'instantané a été pris. Les deux autres se relevaient intacts.
##
## On retient donc chaque unité **à chaque frame**, tant qu'elle existe. Une
## unité qui disparaît laisse son dernier état, PV à zéro compris.
var _last_seen: Dictionary = {}

## État de chaque unité à son entrée en lice, `id` → instantané.
##
## Le pendant de [member _last_seen] au premier instant : sans ce point de
## départ, le bilan de fin de bataille ne saurait pas dire *combien* d'XP la
## bataille a rapporté — seulement combien chaque unité en porte au total.
var _exp_baseline: Dictionary = {}


## Branche le runner sur un niveau chargé.
func setup(target_level: TacticsLevel, target_chapter: ChapterData) -> void:
	level = target_level
	chapter = target_chapter


func _ready() -> void:
	# Le niveau finit de s'initialiser sur la frame suivante : on attend.
	await get_tree().process_frame
	_apply_roster()
	await _apply_deployment_tiles()
	_mark_seize_point()
	_start_deployment()


func _process(delta: float) -> void:
	if _finished or _deploying or not chapter or not level or not is_instance_valid(level):
		return

	# À chaque frame, pas toutes les demi-secondes comme l'objectif : un pion
	# n'existe qu'une demi-seconde après sa mort, exactement la période
	# d'évaluation. Retenir au même rythme que ce délai, c'est jouer à pile ou
	# face sur chaque mort.
	_remember_player_units()
	_count_turns()

	_accum += delta
	if _accum < CHECK_INTERVAL:
		return
	_accum = 0.0

	var snapshot: Dictionary = build_snapshot()
	if snapshot["player_units"].is_empty() and snapshot["enemy_units"].is_empty():
		return  # Niveau pas encore peuplé.

	var verdict: Dictionary = OBJ.evaluate(chapter.objective, snapshot)
	var status: int = int(verdict["status"])
	if status == OBJ.Status.IN_PROGRESS:
		return

	_finished = true
	var victory: bool = status == OBJ.Status.VICTORY
	var bonuses: Array = OBJ.evaluate_bonuses(chapter.bonus_objectives, snapshot) if victory else []

	# Le journal ignorait comment une bataille se terminait : ni les replays ni
	# l'audio (qui l'écoute) n'avaient de quoi marquer la victoire.
	var recorder: Node = get_node_or_null("/root/BattleRecorder")
	if recorder:
		recorder.record(recorder.Kind.OBJECTIVE, {
			"status": "victory" if victory else "defeat",
			"reason": str(verdict["reason"]),
			"chapter": chapter.id, "turn": turn,
		})

	chapter_finished.emit(victory, bonuses, str(verdict["reason"]))


## Instantané de la bataille, au format attendu par [ObjectiveDB].
func build_snapshot() -> Dictionary:
	var players: Array = _units_of(level.player)
	return {
		"turn": turn,
		"seized": OBJ.is_seized(chapter.objective, players) if chapter else false,
		"player_units": players,
		"enemy_units": _units_of(level.opponent),
	}


## Point de commandement du chapitre, en coordonnées de grille (-1,-1 si aucun).
func seize_target() -> Vector2i:
	return OBJ.seize_target(chapter.objective) if chapter else Vector2i(-1, -1)


## État des unités du joueur, pour reporter XP/PV dans le roster persistant.
##
## Les unités encore en scène donnent leur état du moment ; celles qui n'y sont
## plus — les mortes, libérées une demi-seconde après leur chute — donnent le
## dernier état retenu par [member _last_seen]. Sans elles, une défaite ne
## coûtait que la dernière mort de la bataille.
func player_unit_snapshots() -> Array:
	_remember_player_units()

	var out: Array = []
	var seen: Dictionary = {}
	if level and level.player and is_instance_valid(level.player):
		for p in level.player.get_children():
			if not p is TacticsPawn or not is_instance_valid(p):
				continue
			var snapshot: Dictionary = _snapshot_of(p)
			seen[str(snapshot["id"])] = true
			out.append(snapshot)

	for id: String in _last_seen:
		if not seen.has(id):
			out.append(_last_seen[id])
	return out


## Bilan chiffré de la bataille, pour l'écran de fin.
##
## Les pertes, les critiques et les dégâts se relisent dans [BattleRecorder] —
## il note déjà chaque assaut et chaque mort ; le nombre de tours et l'XP
## gagnée, eux, n'appartiennent qu'au runner : il compte les uns et connaît
## l'état des unités avant la bataille.
##
## À appeler **avant** de décharger le niveau : les unités encore en scène y
## comptent. L'or, qui relève de la campagne et non de la bataille, est ajouté
## par [Main] (voir [method BattleStats.rows]).
func battle_summary() -> Dictionary:
	_remember_player_units()

	var names: Array = []
	for id: String in _last_seen:
		names.append(str((_last_seen[id] as Dictionary).get("name", "")))

	var recorder: Node = get_node_or_null("/root/BattleRecorder")
	var events: Array = recorder.events if recorder else []
	var summary: Dictionary = BattleStats.from_events(events, names)
	summary["turns"] = turn
	summary["exp_gained"] = _exp_gained()
	return summary


## XP accumulée par l'ensemble du camp depuis le début de la bataille.
##
## Une unité qui monte de niveau voit ses points repartir de zéro : la
## comparaison passe donc par l'XP totale ([method BattleStats.total_exp]) et
## non par le seul `exp` de la fiche.
func _exp_gained() -> int:
	var total: int = 0
	for id: String in _last_seen:
		var now: Dictionary = _last_seen[id]
		var before: Dictionary = _exp_baseline.get(id, now)
		total += BattleStats.total_exp(int(now.get("level", 1)), int(now.get("exp", 0))) \
			- BattleStats.total_exp(int(before.get("level", 1)), int(before.get("exp", 0)))
	return maxi(total, 0)


## Retient l'état de chaque unité du joueur encore en scène.
func _remember_player_units() -> void:
	if not level or not level.player or not is_instance_valid(level.player):
		return
	for p in level.player.get_children():
		if not p is TacticsPawn or not is_instance_valid(p) or not p.stats:
			continue
		# Un pion déjà promis à la libération ne dit plus rien d'utile : soit il
		# est mort, et son dernier état est retenu depuis une demi-seconde, soit
		# il quitte la scène sans avoir combattu.
		if p.is_queued_for_deletion():
			continue
		var snapshot: Dictionary = _snapshot_of(p)
		var id: String = str(snapshot["id"])
		# Premier regard porté sur cette unité : c'est son état de départ.
		if not _exp_baseline.has(id):
			_exp_baseline[id] = snapshot
		_last_seen[id] = snapshot


func _snapshot_of(p: TacticsPawn) -> Dictionary:
	var s = p.stats
	var unit_name: String = EXECUTOR.display_name(p)
	return {
		"id": unit_name.to_lower().replace(" ", "_"),
		"name": unit_name,
		"hp": s.hp, "max_hp": s.max_hp,
		"exp": s.exp, "level": s.level,
		"class_id": s.character_class, "is_promoted": s.is_promoted,
		"str": s.str, "mag": s.mag, "skl": s.skl, "spd": s.spd,
		"lck": s.lck, "def": s.def, "res": s.res, "movement": s.movement,
	}


#region Internes
## Unités d'un camp, avec leur case : l'objectif « prise de point » a besoin des
## coordonnées, les autres se contentent du nom et des PV.
func _units_of(team: Node) -> Array:
	var units: Array = []
	if not team or not is_instance_valid(team):
		return units
	var arena: Node = level.arena if level else null
	for p in team.get_children():
		if not (p is TacticsPawn and is_instance_valid(p) and p.stats):
			continue
		var tile: Node = p.get_tile() if p.has_method("get_tile") else null
		var g: Vector2i = TacticsGrid.tile_to_grid(arena, tile) if tile else Vector2i(-1, -1)
		units.append({
			"name": EXECUTOR.display_name(p), "hp": p.stats.hp,
			"col": g.x, "row": g.y,
		})
	return units


## Colore la case à prendre, faute de quoi l'objectif serait invisible en jeu.
func _mark_seize_point() -> void:
	var target: Vector2i = seize_target()
	if target.x < 0 or not level or not level.arena:
		return
	_seize_tile = TacticsGrid.find_tile(level.arena, target.x, target.y) as TacticsTile
	if not _seize_tile:
		push_warning("[ChapterRunner] Point de commandement (%d, %d) absent de la carte %s." % [
			target.x, target.y, chapter.scene_path if chapter else "?"
		])
		return
	_seize_tile.seize_point = true
	print_rich("[color=yellow]⚑ Point de commandement : case (%d, %d)[/color]" % [target.x, target.y])


## Un tour complet = les deux camps ont épuisé leurs actions (le niveau les réinitialise).
func _count_turns() -> void:
	if not level.participant or not is_instance_valid(level.participant):
		return
	var anyone_can_act: bool = level.participant.can_act(level.player) \
		or level.participant.can_act(level.opponent)
	if not anyone_can_act:
		if not _turn_counted:
			turn += 1
			_turn_counted = true
	else:
		_turn_counted = false


## Applique le roster persistant aux pions du niveau et retire les non-déployés.
func _apply_roster() -> void:
	if chapter and not chapter.use_roster:
		return  # Carte du joueur : ses unités sont celles qu'elle déclare.
	var campaign: Node = get_node_or_null("/root/Campaign")
	if not campaign or not level or not level.player or campaign.roster.is_empty():
		return

	_deployed_names.clear()
	# Les identifiants déjà représentés par un pion de la carte : ce qui manque
	# à l'appel une fois cette boucle finie doit être monté de toutes pièces.
	var present: Dictionary = {}
	for p in level.player.get_children():
		if not p is TacticsPawn or not is_instance_valid(p) or not p.stats:
			continue
		var unit_name: String = EXECUTOR.display_name(p)
		var id: String = unit_name.to_lower().replace(" ", "_")
		var unit: Dictionary = campaign.get_unit(id)

		if unit.is_empty():
			continue  # Pion propre au niveau (PNJ, invité) : on n'y touche pas.

		if not bool(unit.get("alive", true)) or not id in campaign.deployment:
			# Non déployé (ou tombé) : il ne participe pas. On le sort de l'arbre
			# **avant** de le libérer — un nœud seulement `queue_free` reste
			# enfant jusqu'à la fin de la frame, et tout ce qui parcourt
			# `level.player` le compte encore : l'objectif, l'export vers Ciel, et
			# la mémoire des morts, qui inscrivait ainsi au roster des unités
			# jamais entrées en lice.
			level.player.remove_child(p)
			p.queue_free()
			continue

		present[id] = true
		_deployed_names.append(unit_name)
		apply_roster_unit(p.stats, unit)

	_spawn_missing_units(campaign, present)

	print_rich("[color=cyan]📋 Déploiement : %s[/color]" % (
		", ".join(_deployed_names) if not _deployed_names.is_empty() else "roster par défaut du niveau"
	))
	_check_protected_present()


## Fait entrer en scène les unités déployées que la carte ne porte pas.
##
## Un chapitre pose ses pions dans son `.tscn` ; [method _apply_roster] ne faisait
## que les **reconnaître au nom** pour leur verser la fiche du roster. Une recrue
## écrite dans l'éditeur de personnages n'a, elle, aucun pion à reconnaître : elle
## n'existe que dans le roster. L'intendance l'enrôlait, l'écran de préparation la
## retenait au déploiement, et elle n'apparaissait jamais sur le plateau —
## silencieusement, puisque rien ne cherchait ce qui manquait à l'appel.
##
## Les vraies recrues (`source` pointe un `.tres`) partent de leur propre fiche ;
## un personnage écrit à la main emprunte [constant FALLBACK_SHEET], entièrement
## réécrite ensuite. C'est le même détour que [CustomBattle] prend pour l'éditeur
## de cartes.
func _spawn_missing_units(campaign: Node, present: Dictionary) -> void:
	var camp: Node = level.player
	var occupied: Array[Vector2i] = _occupied_cells()
	var index: int = _highest_pawn_index(camp)

	for raw in campaign.deployment:
		var id: String = str(raw)
		if present.has(id):
			continue
		var unit: Dictionary = campaign.get_unit(id)
		if unit.is_empty() or not bool(unit.get("alive", true)):
			continue

		index += 1
		var pawn: Node3D = _make_pawn(str(unit.get("source", "")), index)
		if not pawn:
			continue

		var cell: Vector2i = _free_cell(campaign, id, occupied)
		# Dans l'arbre d'abord : le pion passe son `_ready` ici, donc c'est
		# seulement après cet appel qu'il a des statistiques à recevoir — et une
		# `global_position` qui veuille dire quelque chose.
		camp.add_child(pawn)
		if cell.x >= 0:
			occupied.append(cell)
			_place_on_cell(pawn, cell)
		if pawn.get("stats"):
			apply_roster_unit(pawn.stats, unit)
		_deployed_names.append(EXECUTOR.display_name(pawn))


## Un pion complet (scène de pion + expertise), avant son entrée dans l'arbre.
##
## L'ordre compte : [TacticsPawn] lit `$Expertise/Stats` dans son `_ready`, donc
## l'expertise doit être en place avant que le pion rejoigne la scène.
func _make_pawn(sheet_path: String, index: int) -> Node3D:
	var path: String = sheet_path if ResourceLoader.exists(sheet_path) else FALLBACK_SHEET
	var sheet: Resource = load(path)
	if not sheet:
		push_warning("[ChapterRunner] Fiche de départ introuvable : %s" % path)
		return null

	var pawn: Node3D = PAWN_SCENE.instantiate()
	# Le suffixe du nom affiché vient du nom de nœud : « Pawn », « Pawn2 »…
	pawn.name = "Pawn" if index <= 1 else "Pawn%d" % index
	var expertise: Node = EXPERTISE_SCENE.instantiate()
	expertise.name = "Expertise"
	expertise.starting_stats = sheet
	pawn.add_child(expertise)
	return pawn


## Indice le plus élevé déjà porté par un pion du camp ("Pawn3" → 3).
##
## Les noms de nœuds servent à départager les homonymes ([method TacticsPawn.display_name]) :
## repartir de zéro donnerait deux « Pawn2 », et Godot en renommerait un dans son dos.
func _highest_pawn_index(camp: Node) -> int:
	var highest: int = 0
	for child: Node in camp.get_children():
		var digits: String = String(child.name).lstrip("Pawn")
		highest = maxi(highest, int(digits) if digits.is_valid_int() else 1)
	return highest


## Cases actuellement tenues par un pion, tous camps confondus.
func _occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for camp: Node3D in level.camps:
		if not is_instance_valid(camp):
			continue
		for p in camp.get_children():
			if not (p is TacticsPawn) or not is_instance_valid(p) or p.is_queued_for_deletion():
				continue
			var tile: Node = p.get_tile()
			if not tile:
				continue
			var cell: Vector2i = TacticsGrid.tile_to_grid(level.arena, tile)
			if cell.x >= 0 and not cell in cells:
				cells.append(cell)
	return cells


## Où poser une unité qui n'a pas de pion sur la carte — (-1,-1) si nulle part.
##
## Trois recours, du plus intentionnel au plus mécanique : la case choisie par le
## joueur à l'écran de préparation, une case de déploiement déclarée par le
## chapitre, puis n'importe quelle case libre de la carte. La dernière n'est pas
## un beau placement, mais une unité mal posée reste jouable — et déplaçable dès
## la phase de déploiement — là où une unité absente ne l'est pas.
func _free_cell(campaign: Node, unit_id: String, occupied: Array[Vector2i]) -> Vector2i:
	var chosen: Vector2i = campaign.deployment_tile(unit_id)
	if chosen.x >= 0 and not chosen in occupied:
		return chosen

	for raw: Variant in (chapter.deploy_tiles if chapter else []):
		var pos: Vector2i = raw if raw is Vector2i else Vector2i(int(raw[0]), int(raw[1]))
		if not pos in occupied and TacticsGrid.find_tile(level.arena, pos.x, pos.y):
			return pos

	var size: Vector2i = TacticsGrid.grid_size(level.arena)
	for row: int in size.y:
		for col: int in size.x:
			var pos := Vector2i(col, row)
			if not pos in occupied and TacticsGrid.find_tile(level.arena, col, row):
				return pos

	push_warning("[ChapterRunner] Aucune case libre pour %s : elle entre là où la scène l'a posée."
		% unit_id)
	return Vector2i(-1, -1)


## Pose un pion sur une case de la grille.
func _place_on_cell(pawn: Node3D, cell: Vector2i) -> void:
	var tile: Node3D = TacticsGrid.find_tile(level.arena, cell.x, cell.y)
	if not tile:
		return
	pawn.global_position = tile.global_position + Vector3(0, DEPLOYMENT.PAWN_LIFT, 0)


## Vérifie que la protégée d'un objectif « protéger » est bien entrée en scène.
##
## Le déploiement l'impose ([member ChapterData.required_units]) ; si elle
## manque quand même, le chapitre serait perdu au premier tour sans que rien ne
## l'explique. Mieux vaut le dire fort dans le journal.
func _check_protected_present() -> void:
	var target: String = OBJ.protected_target(chapter.objective) if chapter else ""
	if target.is_empty() or _deployed_names.is_empty():
		return
	if target in _deployed_names:
		print_rich("[color=yellow]🛡 À protéger : %s[/color]" % target)
		return
	push_warning("[ChapterRunner] %s doit être protégée mais n'est pas déployée — "
		% target + "ajoute son identifiant à `required_units` du chapitre %s."
		% (chapter.id if chapter else "?"))


## Pose chaque unité sur la case choisie à l'écran de préparation.
##
## C'est le pendant en scène du choix de terrain : sans cela, la case sélectionnée
## devant la carte serait restée une intention dans la sauvegarde, et le pion
## serait entré en jeu là où l'éditeur l'avait laissé.
##
## Contrairement à [DeploymentPhase], ceci marche **aussi en headless** : poser un
## pion sur une tuile connue ne demande ni collision ni rayon, juste sa position.
##
## Un pion savait sur quelle case il se tient par un `RayCast3D` dirigé vers le
## bas, dont le résultat datait de la frame précédente : le téléporter ne
## suffisait pas, il se recentrait à la frame suivante sur la tuile que le rayon
## croyait encore avoir sous lui. Il fallait forcer le rayon à la main juste
## après. Depuis que la case se lit dans [BattleGrid] (2026-08-07), la position
## suffit — et ce rattrapage a disparu.
func _apply_deployment_tiles() -> void:
	var campaign: Node = get_node_or_null("/root/Campaign")
	if not campaign or not level or not level.player or not level.arena:
		return
	var plan: Dictionary = campaign.deployment_tiles
	if plan.is_empty():
		return

	await get_tree().physics_frame
	if not is_instance_valid(level) or not is_instance_valid(level.player):
		return

	var placed: int = 0
	for p in level.player.get_children():
		if not p is TacticsPawn or not is_instance_valid(p) or p.is_queued_for_deletion():
			continue
		var id: String = EXECUTOR.display_name(p).to_lower().replace(" ", "_")
		if not plan.has(id):
			continue
		var pos: Vector2i = plan[id]
		var tile: Node3D = TacticsGrid.find_tile(level.arena, pos.x, pos.y)
		if not tile:
			push_warning("[ChapterRunner] Case de départ (%d, %d) absente de la carte." % [pos.x, pos.y])
			continue
		p.res.pathfinding_tilestack = []
		p.velocity = Vector3.ZERO
		p.global_position = tile.global_position + Vector3(0, DEPLOYMENT.PAWN_LIFT, 0)
		placed += 1

	if placed > 0:
		print_rich("[color=cyan]⚑ %d unité(s) posée(s) sur la case choisie en préparation[/color]" % placed)


## Ouvre le placement des unités avant le premier tour.
##
## Sans fenêtre (tests headless), les tuiles n'ont pas de collision : le pion ne
## sait pas sur quelle case il se tient et le placement n'aurait aucun sens. On
## laisse alors la bataille démarrer comme avant.
func _start_deployment() -> void:
	if not level or not level.player or not chapter:
		return
	if DisplayServer.get_name() == "headless":
		return

	var phase := DEPLOYMENT.new()
	phase.name = "DeploymentPhase"
	phase.level = level
	phase.declared_tiles = chapter.deploy_tiles
	phase.finished.connect(func() -> void:
		_deploying = false
		# La bataille commence ici. Ce que la scène portait avant — les pions que
		# le roster n'a pas retenus, ceux d'avant le déploiement — n'a rien à
		# faire dans la mémoire des morts : ils n'ont pas combattu.
		_last_seen.clear()
		# Ni dans le bilan : l'XP se compte à partir d'ici.
		_exp_baseline.clear())
	_deploying = true
	add_child(phase)


## Reporte une entrée de roster sur les statistiques d'un pion.
##
## Publique et statique : l'éditeur de cartes en a besoin lui aussi, pour poser
## sur une carte un personnage écrit à la main. Sans cela il faudrait deux
## chemins d'application, et deux occasions de diverger.
static func apply_roster_unit(stats: Stats, unit: Dictionary) -> void:
	stats.level = int(unit.get("level", stats.level))
	stats.exp = int(unit.get("exp", stats.exp))
	stats.character_class = int(unit.get("class_id", stats.character_class))
	stats.is_promoted = bool(unit.get("is_promoted", stats.is_promoted))
	stats.max_hp = int(unit.get("max_hp", stats.max_hp))
	stats.hp = clampi(int(unit.get("hp", stats.max_hp)), 1, stats.max_hp)
	stats.str = int(unit.get("str", stats.str))
	stats.mag = int(unit.get("mag", stats.mag))
	stats.skl = int(unit.get("skl", stats.skl))
	stats.spd = int(unit.get("spd", stats.spd))
	stats.lck = int(unit.get("lck", stats.lck))
	stats.def = int(unit.get("def", stats.def))
	stats.res = int(unit.get("res", stats.res))
	stats.movement = int(unit.get("movement", stats.movement))
	stats.apply_class_growths(stats.character_class)
	_apply_arsenal(stats, unit)
	# Les compétences ne sont imposées que si le roster en porte une liste : une
	# unité de campagne ordinaire n'en a pas, et garde donc celles de sa classe.
	if unit.get("skills") is Array:
		stats.set_skills(unit["skills"])

	# Toniques bus à l'intendance. Entre deux chapitres il n'y a pas de tours pour
	# les faire vieillir : ils attendent sur la fiche et se versent ici, à l'entrée
	# en lice, où [method Stats.tick_buffs] les décomptera. Bus une fois, versés une
	# fois — la réserve se vide en même temps.
	for buff in unit.get("buffs", []):
		if typeof(buff) == TYPE_DICTIONARY:
			stats.apply_buff(str(buff.get("stat", "")), int(buff.get("amount", 0)),
				int(buff.get("turns", 1)))
	unit.erase("buffs")

	stats.attack_power = stats.get_total_attack()

	# L'apparence, et le nom qui va avec. Le pion a déjà monté sa figurine à son
	# `_ready` : la changer maintenant demande de la lui faire relire.
	var look: String = str(unit.get("sprite", ""))
	if not look.is_empty():
		stats.sprite = look
	stats.override_name = str(unit.get("name", stats.override_name))
	_refresh_look(stats)


## Fait relire au pion sa figurine et son nom, après coup.
static func _refresh_look(stats: Stats) -> void:
	var pawn: Node = stats.get_parent()
	while pawn and not (pawn is TacticsPawn):
		pawn = pawn.get_parent()
	if pawn and pawn.character and pawn.character.has_method("setup"):
		pawn.character.setup(stats, pawn.expertise)


## Reporte l'arsenal du roster sur le pion : sans cela, l'arme achetée et
## équipée à l'écran de préparation restait dans la sauvegarde et le pion
## entrait en scène avec l'arme brute de sa fiche.
static func _apply_arsenal(stats: Stats, unit: Dictionary) -> void:
	var arsenal: Array = unit.get("weapons", [])
	# Un fourreau vide veut dire deux choses opposées selon l'unité : « fiche
	# d'avant le catalogue, ses valeurs brutes font foi » ou « elle a tout
	# revendu, elle part à mains nues ». Le marqueur du roster tranche — sans
	# lui, revendre ses armes ne coûterait rien.
	if arsenal.is_empty() and not bool(unit.get("uses_arsenal", false)):
		return

	stats.weapons = []
	stats.unequip()
	for id in arsenal:
		stats.add_weapon(str(id))

	var equipped: String = str(unit.get("weapon", ""))
	if not equipped.is_empty():
		stats.equip(equipped)
#endregion
