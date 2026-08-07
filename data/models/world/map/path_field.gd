class_name PathField
extends RefCounted
## Le parcours d'une unité, en données pures : d'où l'on vient, en combien de pas.
##
## Cet état vivait sur les tuiles — deux propriétés `pf_root` et `pf_distance`
## posées sur des `StaticBody3D`. Le calcul était juste, mais il s'accrochait à
## la scène : impossible d'éprouver un parcours sans monter une arène 3D, et
## impossible de laisser les tuiles ne faire que de l'affichage.
##
## Ici, tout est indexé par coordonnée de grille. Une tuile n'est plus qu'une
## chose à regarder ; le chemin, lui, se calcule et se vérifie sans elle.
##
## Ce que la classe ne fait pas : décider si une case se franchit. Cette
## question mêle terrain, occupation et camp — elle arrive par un `Callable`,
## ce qui garde ce parcours-ci indifférent aux règles du jour.

## Ce que le parcours a atteint : Vector2i → nombre de pas depuis l'origine.
var _distance: Dictionary = {}
## D'où l'on vient : Vector2i → Vector2i. L'origine n'y figure pas.
var _root: Dictionary = {}


## Oublie tout parcours calculé.
func clear() -> void:
	_distance.clear()
	_root.clear()


## Calcule le parcours depuis une case, de proche en proche.
##
## [param grid] L'index de la grille — il donne les voisines et leur altitude.
## [param origin] La case de départ. Elle est atteinte à distance zéro et n'a
## pas de provenance : c'est ce qui termine [method path_to].
## [param max_step] Dénivelé franchissable d'une case à l'autre (le saut).
## [param passable] `func(coord: Vector2i) -> bool` — la case se traverse-t-elle ?
## L'origine n'y est jamais soumise : on part toujours d'où l'on est.
func expand(grid: BattleGrid, origin: Vector2i, max_step: float, passable: Callable) -> void:
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var next_distance: float = distance_at(current) + 1.0
		for neighbor: Vector2i in grid.neighbor_coords(current, max_step):
			# Une case déjà pourvue d'une provenance a été atteinte par un chemin
			# au moins aussi court : la revisiter ne peut que l'allonger. Et
			# l'origine n'en reçoit jamais, sans quoi le chemin bouclerait.
			if neighbor == origin or _root.has(neighbor):
				continue
			if not passable.call(neighbor):
				continue
			_root[neighbor] = current
			_distance[neighbor] = next_distance
			queue.push_back(neighbor)


## Nombre de pas jusqu'à une case. Zéro si le parcours ne l'a pas atteinte —
## c'est aussi la valeur de l'origine, que les appelants distinguent par
## [method has_root].
func distance_at(coord: Vector2i) -> float:
	return float(_distance.get(coord, 0.0))


## Le parcours est-il passé par cette case ? Faux pour l'origine et pour tout
## ce qu'il n'a pas atteint.
func has_root(coord: Vector2i) -> bool:
	return _root.has(coord)


## Case d'où l'on vient. À n'appeler qu'après [method has_root].
func root_of(coord: Vector2i) -> Vector2i:
	return _root.get(coord, coord)


## Le chemin jusqu'à une case, de l'origine vers elle, celle-ci comprise.
##
## Une case hors du parcours ne rend qu'elle-même : c'est ce que faisait la
## remontée de `pf_root`, et le déplacement s'en sert pour ne pas bouger.
func path_to(coord: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [coord]
	var walked: Vector2i = coord
	while _root.has(walked):
		walked = _root[walked]
		out.push_front(walked)
	return out


## Les cases atteintes, l'origine exclue.
func reached() -> Array:
	return _root.keys()
