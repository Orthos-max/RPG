class_name BattleChests
extends RefCounted
## Les coffres d'une bataille : où ils sont, ce qu'ils contiennent, lesquels
## sont déjà ouverts.
##
## Un chapitre déclare ses trésors ([member ChapterData.chests], nettoyés par
## [ChestData]) ; [ChapterRunner] les arme ici au chargement du niveau. Une unité
## du camp du joueur qui **finit son mouvement** — ou son tour — sur une case à
## coffre fermé l'ouvre : l'or va à la campagne, l'objet dans son sac, et le
## coffre reste ouvert jusqu'à la fin de la bataille.
##
## [b]L'état est local à la bataille[/b], comme [BattleGrid] et pour la même
## raison : « ce coffre est-il ouvert ? » n'a de sens qu'entre le chargement du
## niveau et son déchargement. [member current] tient l'état en cours ;
## [method Main.unload_level] le remet à `null`. Recommencer un chapitre après
## une défaite repose donc les coffres fermés, ce qui est la seule réponse juste :
## l'or de la bataille perdue est reparti avec l'instantané de début de chapitre.
##
## [b]Rien ici n'a besoin d'une scène.[/b] [method open_at] ne manipule que des
## coordonnées ; [method collect] va chercher les autoloads par l'arbre et
## retombe proprement quand ils n'y sont pas. C'est ce qui rend le ramassage
## vérifiable en `--headless`.

const ITEMS = preload("res://data/models/world/stats/item_db.gd")
const ChestDataClass = preload("res://data/models/campaign/chest_data.gd")
const TeamDataClass = preload("res://data/models/world/combat/team/team_data.gd")

## Les coffres de la bataille en cours, ou `null` hors bataille.
static var current: BattleChests = null

## Case → `{gold: int, item: String, opened: bool}`
var _chests: Dictionary = {}


#region Vie d'une bataille
## Arme les coffres d'un chapitre et en fait ceux de la bataille en cours.
##
## [param declared] Les coffres bruts du chapitre : le nettoyage passe par
## [method ChestData.parse], pour que personne n'ait à le refaire.
static func arm(declared: Array) -> BattleChests:
	var chests := BattleChests.new()
	for chest: Dictionary in ChestDataClass.parse(declared):
		chests._chests[chest["cell"]] = {
			"gold": int(chest["gold"]), "item": str(chest["item"]), "opened": false,
		}
	current = chests
	return chests


## Cases portant un coffre, ouvertes comprises.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in _chests:
		out.append(cell)
	return out


## Le coffre d'une case, ou un dictionnaire vide s'il n'y en a pas.
func at(cell: Vector2i) -> Dictionary:
	var chest: Variant = _chests.get(cell)
	return (chest as Dictionary).duplicate() if chest is Dictionary else {}


## Cette case porte-t-elle un coffre encore fermé ?
func is_closed(cell: Vector2i) -> bool:
	var chest: Variant = _chests.get(cell)
	return chest is Dictionary and not bool(chest["opened"])


## Nombre de coffres encore fermés.
func closed_count() -> int:
	var count: int = 0
	for cell: Vector2i in _chests:
		if not bool(_chests[cell]["opened"]):
			count += 1
	return count


## Ouvre le coffre d'une case et rend ce qu'il contenait.
##
## Le seul endroit qui bascule l'état — d'où le nom : ouvrir, c'est cela et rien
## d'autre. Verser la récompense est le travail de [method collect], qui a le
## pion et les autoloads sous la main.
##
## [returns] `{ok, gold, item}` — `ok` à faux si la case n'a pas de coffre, ou
## si celui qui s'y trouve est déjà ouvert.
func open_at(cell: Vector2i) -> Dictionary:
	if not is_closed(cell):
		return {"ok": false, "gold": 0, "item": ""}
	var chest: Dictionary = _chests[cell]
	chest["opened"] = true
	return {"ok": true, "gold": int(chest["gold"]), "item": str(chest["item"])}
#endregion


#region Ramassage
## Le pion ramasse ce qui se trouve sous ses pieds, s'il y a lieu.
##
## Appelée à chaque fin de déplacement ([method TacticsPawnMovementService.check_movement_completion])
## et à chaque fin de tour d'unité ([method TacticsPawn.end_pawn_turn]) : les
## deux, parce qu'un coffre doit se ramasser en marchant dessus **et** en
## attendant dessus, et qu'aucun des deux chemins ne passe par l'autre. Le double
## appel est sans effet : un coffre ouvert ne se rouvre pas.
##
## [b]Le camp du joueur, et lui seul.[/b] Ciel n'ouvre pas les coffres — non par
## faiblesse d'IA, mais parce que l'or et les sacs de la campagne n'appartiennent
## qu'au joueur : il n'y a nulle part où verser le butin d'un squelette.
##
## [returns] `{ok, cell, gold, item, reason}`
static func collect(pawn: TacticsPawn) -> Dictionary:
	var nothing: Dictionary = {"ok": false, "cell": Vector2i(-1, -1),
		"gold": 0, "item": "", "reason": ""}
	if not current or not _is_player_pawn(pawn) or not pawn.stats:
		return nothing

	var cell: Vector2i = _cell_of(pawn)
	if cell.x < 0 or not current.is_closed(cell):
		return nothing

	# Un sac plein laisse le coffre **fermé** plutôt que d'avaler l'objet : le
	# joueur peut boire une potion et revenir. Sans ce refus, le trésor
	# s'évaporerait sans que rien ne le dise.
	var item: String = str(current.at(cell).get("item", ""))
	if not item.is_empty() and pawn.stats.items.size() >= ITEMS.MAX_ITEMS:
		nothing["reason"] = "%s ne peut porter que %d objets" % [
			pawn.display_name(), ITEMS.MAX_ITEMS]
		Toast.post("🧰  Coffre : %s" % nothing["reason"], Toast.C_CRIT)
		return nothing

	var reward: Dictionary = current.open_at(cell)
	if not bool(reward["ok"]):
		return nothing

	if not item.is_empty():
		pawn.stats.add_item(item)
	else:
		var campaign: Node = _autoload("Campaign")
		if campaign:
			campaign.gold = int(campaign.gold) + int(reward["gold"])

	# Le déplacement devient définitif : annuler après avoir vidé un coffre
	# rendrait la case au pion sans lui reprendre le butin. C'est la règle de
	# Fire Emblem pour un village visité, et le même geste ([PawnMoveMemory]).
	if pawn.res:
		pawn.res.move_memory.clear()

	# Le journal dit tout le reste : le bandeau ([Toast]), la ligne d'historique
	# ([BattleHistory]) et l'or du bilan ([BattleStats]) se déduisent de cet
	# événement, et se vérifient donc sans écran.
	var recorder: Node = _autoload("BattleRecorder")
	if recorder:
		recorder.record_chest(pawn.display_name(), cell.x, cell.y,
			int(reward["gold"]), str(reward["item"]))

	# La vignette du plateau suit l'état — sans effet quand rien n'a été posé.
	TacticsChests.mark_opened(cell)

	return {"ok": true, "cell": cell, "gold": int(reward["gold"]),
		"item": str(reward["item"]), "reason": ""}
#endregion


#region Internes
## Ce pion appartient-il au camp du joueur, et est-il encore debout ?
static func _is_player_pawn(pawn: TacticsPawn) -> bool:
	if not pawn or not is_instance_valid(pawn) or not pawn.is_alive():
		return false
	return TeamDataClass.side_for_camp_node(pawn.get_parent()) == TeamDataClass.Side.PLAYER


## Case (colonne, ligne) sous le pion — (-1, -1) hors de toute grille.
static func _cell_of(pawn: TacticsPawn) -> Vector2i:
	var grid: BattleGrid = BattleGrid.current
	if not grid:
		return Vector2i(-1, -1)
	var tile: Node = pawn.get_tile()
	return grid.cell_of(tile) if tile else Vector2i(-1, -1)


## Un autoload par l'arbre plutôt que par son nom global : ce service est chargé
## par la chaîne des pions, qui peut l'être avant que les autoloads existent.
static func _autoload(autoload_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(NodePath(autoload_name))
	return null
#endregion
