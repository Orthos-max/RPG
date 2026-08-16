class_name BattleSnapshot
extends RefCounted
## L'état d'une bataille en cours, en données pures — la sauvegarde à la volée.
##
## [Campaign] savait sauvegarder une [b]campagne[/b] : le roster, l'or, le
## chapitre atteint. Rien de tout cela ne dit où se tiennent les pions, combien
## il leur reste de PV, ni qui a déjà joué ce tour-ci — l'instantané de début de
## chapitre ([method Campaign.autosave_chapter]) rend d'ailleurs l'état d'
## [i]avant[/i] le premier coup, et c'est exactement ce qu'on lui demande.
## Quitter en pleine bataille coûtait donc la bataille entière.
##
## Ce fichier-ci capture ce qui manquait : par pion, sa case, ses PV, sa fiche,
## son sac, son arme en main et ses droits du tour ; et pour la bataille, le
## numéro du tour et le chapitre joué.
##
## [b]C'est de la donnée, pas un nœud.[/b] [method capture] rend un dictionnaire
## que le JSON sait écrire, [method restore] le repose sur un niveau monté. Les
## deux se vérifient en `--headless`, comme [BattleForecast] ou [UnitSheet].
##
## [b]Deux choses ne sont pas reprises[/b], et c'est délibéré :
## [br]• L'étape en cours ([member TacticsParticipantResource.stage]) — la
##   bataille reprend au choix d'une unité. Reprendre au milieu d'un menu
##   d'attaque demanderait de restaurer une sélection, une cible et un trajet
##   à moitié tracé ; le droit de jouer, lui, est bien repris (voir `can_move`
##   et `can_attack`), donc aucun tour n'est rendu ni volé.
## [br]• L'historique du journal de bataille — il raconte la session, pas l'état.

const EXECUTOR = preload("res://data/models/world/ai/ai_executor.gd")
const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

## Version du format. Un instantané plus récent que le jeu est ignoré plutôt que
## relu de travers : mieux vaut « aucune reprise » qu'une armée mal reposée.
const VERSION: int = 1

## Hauteur du pion au-dessus de sa tuile — la même que [DeploymentPhase].
const PAWN_LIFT: float = 0.5


#region Capture
## Instantané de la bataille montée dans [param level].
##
## [param turn] Numéro du tour, tel que [ChapterRunner] le compte.
## [param chapter_id] Chapitre joué, pour savoir quelle carte recharger.
## [returns] {} si le niveau n'a pas de quoi être décrit.
static func capture(level: Node, turn: int = 1, chapter_id: String = "") -> Dictionary:
	if not level or not is_instance_valid(level):
		return {}

	var pawns: Array = []
	for camp: Node in camps_of(level):
		var team: String = TeamDataClass.state_team_name(
			TeamDataClass.side_for_camp_node(camp))
		for p in camp.get_children():
			if not (p is TacticsPawn and is_instance_valid(p) and p.stats):
				continue
			# Un pion déjà promis à la libération est un mort en sursis : le
			# reprendre le ferait revivre à la reprise.
			if p.is_queued_for_deletion() or not p.is_alive():
				continue
			pawns.append(_capture_pawn(level, p as TacticsPawn, team))

	if pawns.is_empty():
		return {}

	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"chapter": chapter_id,
		"turn": maxi(1, turn),
		"pawns": pawns,
	}


static func _capture_pawn(level: Node, p: TacticsPawn, team: String) -> Dictionary:
	var s: Stats = p.stats
	var cell: Vector2i = cell_of(level, p)
	var pos: Vector3 = p.global_position
	return {
		"team": team,
		"name": EXECUTOR.display_name(p),
		# La case est la vérité lisible (elle se relit dans le JSON) ; la position
		# du monde est la vérité exacte, et sert de repli quand la grille n'a pas
		# reconnu la case — sur une carte posée à la main, cela arrive.
		"col": cell.x, "row": cell.y,
		"pos": [pos.x, pos.y, pos.z],
		"hp": s.hp, "max_hp": s.max_hp,
		"level": s.level, "exp": s.exp,
		"class_id": s.character_class, "is_promoted": s.is_promoted,
		"str": s.str, "mag": s.mag, "skl": s.skl, "spd": s.spd,
		"lck": s.lck, "def": s.def, "res": s.res,
		"movement": s.movement,
		"attack_range": s.attack_range,
		"weapon_type": s.weapon_type, "weapon_might": s.weapon_might,
		"weapon_hit": s.weapon_hit, "weapon_crit": s.weapon_crit,
		"weapon_weight": s.weapon_weight,
		"weapons": s.weapons.duplicate(),
		"equipped_weapon": s.equipped_weapon,
		"items": s.items.duplicate(),
		"extra_skills": s.extra_skills.duplicate(),
		"removed_skills": s.removed_skills.duplicate(),
		"buffs": s.active_buffs(),
		# Ce qui reste à jouer de ce tour-ci : sans ces deux drapeaux, une reprise
		# rendrait son tour à une armée qui venait de l'épuiser.
		"can_move": p.res.can_move if p.res else true,
		"can_attack": p.res.can_attack if p.res else true,
	}
#endregion


#region Reprise
## Repose un instantané sur un niveau monté.
##
## Les pions se retrouvent par leur camp et leur nom affiché — le même couple que
## le miroir réseau ([NetMirror]) et le pont CielAI, et le seul qui survive à un
## rechargement de carte, où les noms de nœuds sont redistribués.
##
## [b]Ce que l'instantané ne mentionne pas est mort[/b] : une unité tombée avant
## la sauvegarde n'y figure pas, et la carte rechargée la fait pourtant renaître.
## Elle est donc retirée, sans quoi la reprise offrirait des renforts gratuits —
## aux deux camps.
##
## [returns] {ok, restored, missing, removed, turn}
static func restore(level: Node, snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"ok": false, "restored": 0, "missing": 0, "removed": 0,
		"turn": int(snapshot.get("turn", 1)),
	}
	if not level or not is_instance_valid(level) or not is_valid(snapshot):
		return result

	# "camp|nom" → entrée, pour que deux camps puissent porter le même nom.
	var wanted: Dictionary = {}
	for entry: Variant in snapshot.get("pawns", []):
		if typeof(entry) == TYPE_DICTIONARY:
			wanted["%s|%s" % [str(entry.get("team", "")), str(entry.get("name", ""))]] = entry

	var seen: Dictionary = {}
	for camp: Node in camps_of(level):
		var team: String = TeamDataClass.state_team_name(
			TeamDataClass.side_for_camp_node(camp))
		for p in camp.get_children():
			if not (p is TacticsPawn and is_instance_valid(p) and p.stats):
				continue
			if p.is_queued_for_deletion():
				continue
			var key: String = "%s|%s" % [team, EXECUTOR.display_name(p)]
			if not wanted.has(key):
				_erase_pawn(p as TacticsPawn)
				result["removed"] = int(result["removed"]) + 1
				continue
			_apply_pawn(level, p as TacticsPawn, wanted[key])
			seen[key] = true
			result["restored"] = int(result["restored"]) + 1

	result["missing"] = wanted.size() - seen.size()
	result["ok"] = int(result["restored"]) > 0
	return result


## L'instantané est-il exploitable ? (format connu, au moins un pion)
static func is_valid(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or int(snapshot.get("version", 0)) > VERSION:
		return false
	var pawns: Variant = snapshot.get("pawns", [])
	return pawns is Array and not (pawns as Array).is_empty()


## Résumé d'un instantané, pour un bouton de menu ou un bandeau.
static func describe(snapshot: Dictionary) -> String:
	if not is_valid(snapshot):
		return ""
	return "%s — tour %d, %d unité(s)" % [
		str(snapshot.get("chapter", "bataille")),
		int(snapshot.get("turn", 1)),
		(snapshot.get("pawns", []) as Array).size(),
	]


static func _apply_pawn(level: Node, p: TacticsPawn, entry: Dictionary) -> void:
	var s: Stats = p.stats

	s.max_hp = int(entry.get("max_hp", s.max_hp))
	s.hp = clampi(int(entry.get("hp", s.hp)), 0, s.max_hp)
	s.level = int(entry.get("level", s.level))
	s.exp = int(entry.get("exp", s.exp))
	s.character_class = int(entry.get("class_id", s.character_class))
	s.is_promoted = bool(entry.get("is_promoted", s.is_promoted))
	for stat: String in ["str", "mag", "skl", "spd", "lck", "def", "res", "movement"]:
		s.set(stat, int(entry.get(stat, s.get(stat))))

	s.items = _string_list(entry.get("items", []))
	s.extra_skills = _string_list(entry.get("extra_skills", []))
	s.removed_skills = _string_list(entry.get("removed_skills", []))
	s.set_active_buffs(entry.get("buffs", []))
	_apply_arsenal(s, entry)

	# Le droit de jouer, puis la place sur le plateau.
	if p.res:
		p.res.can_move = bool(entry.get("can_move", true))
		p.res.can_attack = bool(entry.get("can_attack", true))
		# Un trajet à moitié parcouru ferait repartir le pion tout seul.
		p.res.pathfinding_tilestack = []
		p.res.is_moving = false
		p.res.move_memory.clear()
	p.velocity = Vector3.ZERO
	p.global_position = _position_for(level, entry, p.global_position)


## L'arsenal tel qu'il était en main.
##
## L'équipement se rejoue par [method Stats.equip] — c'est lui qui accorde type,
## portée, poids et bonus —, puis les chiffres bruts sont reposés par-dessus :
## une fiche sans arme du catalogue (un mob écrit à la main) n'a que ceux-là, et
## ils doivent revenir identiques.
static func _apply_arsenal(s: Stats, entry: Dictionary) -> void:
	s.weapons = []
	for id: String in _string_list(entry.get("weapons", [])):
		s.add_weapon(id)

	var equipped: String = str(entry.get("equipped_weapon", ""))
	if not equipped.is_empty():
		s.equip(equipped)
	elif not s.weapons.is_empty():
		s.unequip()  # L'unité avait rangé son arme : elle la garde rangée.

	s.attack_range = int(entry.get("attack_range", s.attack_range))
	s.weapon_type = int(entry.get("weapon_type", s.weapon_type))
	s.weapon_might = int(entry.get("weapon_might", s.weapon_might))
	s.weapon_hit = int(entry.get("weapon_hit", s.weapon_hit))
	s.weapon_crit = int(entry.get("weapon_crit", s.weapon_crit))
	s.weapon_weight = int(entry.get("weapon_weight", s.weapon_weight))
	s.attack_power = s.get_total_attack()


## Où reposer le pion : sa case si la grille la connaît, sa position sinon.
static func _position_for(level: Node, entry: Dictionary, fallback: Vector3) -> Vector3:
	var cell := Vector2i(int(entry.get("col", -1)), int(entry.get("row", -1)))
	if cell.x >= 0 and cell.y >= 0 and level.get("arena"):
		var tile: Node3D = TacticsGrid.find_tile(level.arena, cell.x, cell.y)
		if tile:
			return tile.global_position + Vector3(0, PAWN_LIFT, 0)

	var raw: Variant = entry.get("pos", [])
	if raw is Array and (raw as Array).size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback


## Retire un pion que l'instantané ne connaît pas — il était mort.
##
## Même geste que la mort en combat ([TacticsPawnCombatService]) : PV à zéro,
## invisible, sans collision, puis libéré. Mais tout de suite, et sans gerbe ni
## ligne au journal : personne ne vient de le tuer, il n'a jamais dû renaître.
static func _erase_pawn(p: TacticsPawn) -> void:
	if p.stats:
		p.stats.hp = 0
	if p.res:
		p.res.can_move = false
		p.res.can_attack = false
	p.visible = false
	for child: Node in p.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	if p.get_parent():
		p.get_parent().remove_child(p)
	p.queue_free()
#endregion


#region Repères
## Les camps du niveau, y compris le troisième (M5) quand il existe.
static func camps_of(level: Node) -> Array:
	var out: Array = []
	var camps: Variant = level.get("camps")
	if camps is Array:
		for camp: Variant in camps:
			if camp is Node and is_instance_valid(camp):
				out.append(camp)
	if not out.is_empty():
		return out

	# Repli : un niveau qui n'a pas fini de s'initialiser n'a pas encore sa liste.
	for key: String in ["player", "opponent", "guest"]:
		var camp: Variant = level.get(key)
		if camp is Node and is_instance_valid(camp):
			out.append(camp)
	return out


## Case (colonne, ligne) d'un pion, ou (-1, -1) si la grille l'ignore.
static func cell_of(level: Node, p: TacticsPawn) -> Vector2i:
	var tile: Node3D = p.get_tile() if p.has_method("get_tile") else null
	if not tile or not level.get("arena"):
		return Vector2i(-1, -1)
	return TacticsGrid.tile_to_grid(level.arena, tile)


## La bataille montée dans l'arbre, ou `null` s'il n'y en a aucune.
##
## Les raccourcis clavier vivent dans `main.tscn`, qui survit aux niveaux : ils
## ne peuvent pas tenir le niveau par une référence, il faut le retrouver.
static func live_level(tree: SceneTree) -> Node:
	if not tree or not tree.root:
		return null
	return _first_level(tree.root)


static func _first_level(node: Node) -> Node:
	for child: Node in node.get_children():
		if child is TacticsLevel:
			return child
		var found: Node = _first_level(child)
		if found:
			return found
	return null


static func _string_list(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for v: Variant in raw:
			out.append(str(v))
	return out
#endregion
