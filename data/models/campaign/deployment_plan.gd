class_name DeploymentPlan
extends RefCounted
## Où le joueur pose ses unités avant que la bataille commence.
##
## Logique pure : la carte n'apparaît ici que sous forme de coordonnées. Elle
## connaît les cases ouvertes au déploiement, qui occupe quoi, et ce qui se
## passe quand on pose une unité sur une case déjà prise (on échange). Le nœud
## de scène ne fait qu'appliquer le résultat aux pions.

## Cases ouvertes au déploiement
var slots: Array[Vector2i] = []

## "col,row" → nom d'unité
var _by_slot: Dictionary = {}
## nom d'unité → Vector2i
var _by_unit: Dictionary = {}


## Définit les cases ouvertes (les doublons sont ignorés).
func configure(tiles: Array) -> void:
	slots.clear()
	_by_slot.clear()
	_by_unit.clear()
	for t: Variant in tiles:
		var pos: Vector2i = t if t is Vector2i else Vector2i(int(t[0]), int(t[1]))
		if not slots.has(pos):
			slots.append(pos)


## Cette case accueille-t-elle un déploiement ?
func is_slot(pos: Vector2i) -> bool:
	return slots.has(pos)


## Nom de l'unité posée sur une case ("" si libre).
func occupant(pos: Vector2i) -> String:
	return str(_by_slot.get(_key(pos), ""))


## Case d'une unité (-1, -1 si elle n'est pas encore posée).
func position_of(unit_name: String) -> Vector2i:
	return _by_unit.get(unit_name, Vector2i(-1, -1))


## Unités posées, dans l'ordre des cases : nom → case.
func assignments() -> Dictionary:
	return _by_unit.duplicate()


## Nombre d'unités posées.
func placed_count() -> int:
	return _by_unit.size()


## Cases encore libres.
func free_slots() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for pos: Vector2i in slots:
		if occupant(pos).is_empty():
			out.append(pos)
	return out


## Pose une unité sur une case.
##
## Si la case est déjà prise, les deux unités échangent leurs positions — c'est
## le geste attendu quand on réarrange une ligne de départ, et ça évite d'avoir
## à vider une case avant d'en remplir une autre.
##
## [returns] {ok: bool, swapped: String, error: String}
func place(unit_name: String, pos: Vector2i) -> Dictionary:
	if unit_name.is_empty():
		return {"ok": false, "swapped": "", "error": "unité inconnue"}
	if not is_slot(pos):
		return {"ok": false, "swapped": "", "error": "case fermée au déploiement"}

	var previous: Vector2i = position_of(unit_name)
	var other: String = occupant(pos)
	if other == unit_name:
		return {"ok": true, "swapped": "", "error": ""}

	if not other.is_empty():
		if previous.x < 0:
			# L'unité qui arrive n'avait pas de case : celle qui part n'en a plus.
			_by_unit.erase(other)
		else:
			_by_slot[_key(previous)] = other
			_by_unit[other] = previous
	elif previous.x >= 0:
		_by_slot.erase(_key(previous))

	_by_slot[_key(pos)] = unit_name
	_by_unit[unit_name] = pos
	return {"ok": true, "swapped": other, "error": ""}


## Retire une unité du plan (elle ne sera pas déployée).
func remove(unit_name: String) -> void:
	var pos: Vector2i = position_of(unit_name)
	if pos.x < 0:
		return
	_by_slot.erase(_key(pos))
	_by_unit.erase(unit_name)


## Cases de déploiement par défaut, autour des positions de départ du niveau.
##
## Toutes les cartes n'en déclarent pas : plutôt que d'interdire le placement
## là où le chapitre est muet, on ouvre le voisinage immédiat de la ligne de
## départ. Le joueur réarrange sa formation sans pouvoir se téléporter au
## contact de l'ennemi.
##
## [param occupied] Cases des pions du joueur à l'ouverture de la carte.
## [param grid] Taille de la grille (pour rester dans les bornes).
## [param radius] Distance de Manhattan autour de la ligne de départ.
static func default_slots(occupied: Array, grid: Vector2i, radius: int = 2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for raw: Variant in occupied:
		var center: Vector2i = raw if raw is Vector2i else Vector2i(int(raw[0]), int(raw[1]))
		for d_row: int in range(-radius, radius + 1):
			var span: int = radius - absi(d_row)
			for d_col: int in range(-span, span + 1):
				var pos := Vector2i(center.x + d_col, center.y + d_row)
				if pos.x < 0 or pos.y < 0 or pos.x >= grid.x or pos.y >= grid.y:
					continue
				if not out.has(pos):
					out.append(pos)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return out


func _key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]
