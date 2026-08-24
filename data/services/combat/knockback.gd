class_name Knockback
extends RefCounted
## Le repoussement : d'où vient le souffle, et jusqu'où la cible recule.
##
## Logique pure, comme [BattleGrid] dont elle se sert : rien ici ne connaît de
## pion, de scène ni de nœud d'animation. On donne deux coordonnées et un index
## de grille, on obtient la case d'arrivée. C'est ce qui rend la règle du
## repoussement vérifiable en headless, jusqu'au cas tordu du couloir bouché.
##
## [b]Les trois règles.[/b]
##   1. [b]La direction[/b] est celle de l'assaillant vers sa cible, ramenée à un
##      des quatre axes ([method direction]) — on se déplace en croix dans ce jeu,
##      et un souffle en diagonale n'aurait aucune case où pousser.
##   2. [b]On ne traverse rien[/b] : ni une case absente du plateau, ni un terrain
##      infranchissable, ni un autre pion, ni une marche trop haute. Le recul
##      s'arrête à la première case qui refuse ([method can_land]).
##   3. [b]Un recul empêché n'annule pas le coup[/b] : c'est l'appelant qui
##      applique les dégâts, et il les a déjà appliqués quand il demande ici où
##      poser la cible. Une cible acculée à un mur encaisse donc tout et ne bouge
##      pas — être coincé n'a jamais protégé personne.

const MAP_DATA = preload("res://data/models/world/map/map_data.gd")

## Dénivelé qu'un pion repoussé franchit encore, en unités de monde.
##
## Aligné sur le saut d'un pion ordinaire ([StatsResource.jump] vaut 2.0 pour
## l'essentiel du bestiaire) : un souffle ne fait pas escalader une falaise que
## l'on ne saurait pas monter, et ne jette personne dans un précipice qu'il ne
## saurait pas descendre. Les deux sens comptent — c'est une valeur absolue.
const MAX_STEP_HEIGHT: float = 2.0


## L'axe du recul, de [param from] vers [param to], ramené à une case.
##
## Rend [constant Vector2i.ZERO] quand les deux coordonnées se confondent : sans
## écart, il n'y a pas de direction, et l'appelant doit renoncer plutôt que de
## choisir un sens au hasard.
##
## Sur une attaque à distance, l'écart peut être diagonal. On retient alors l'axe
## [b]dominant[/b], et l'abscisse en cas d'égalité parfaite : ce qui compte est
## que la cible s'éloigne de qui l'a frappée, pas la fidélité au trait.
static func direction(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta: Vector2i = to - from
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


## Une case peut-elle recevoir un pion repoussé depuis [param from] ?
##
## Quatre refus, dans l'ordre où ils coûtent le moins cher à vérifier : hors
## plateau, terrain infranchissable, case déjà prise, marche trop haute.
static func can_land(grid: BattleGrid, coord: Vector2i, from: Vector2i) -> bool:
	if grid == null:
		return false
	var tile: Node = grid.tile_at(coord)
	if not tile:
		return false
	if tile.get("terrain_type") != null and not MAP_DATA.is_walkable(int(tile.terrain_type)):
		return false
	if grid.occupant_of(tile) != null:
		return false
	return absf(grid.height_at(coord) - grid.height_at(from)) <= MAX_STEP_HEIGHT


## Où la cible finit, après avoir été poussée d'au plus [param distance] cases.
##
## Le recul est [b]partiel[/b] plutôt que tout ou rien : une cible poussée de deux
## cases vers un mur en fait une et s'arrête. Le contraire — annuler le
## déplacement entier au premier obstacle — donnerait à un pion posté deux cases
## derrière la victime le pouvoir de la clouer sur place, ce qui est exactement
## l'inverse de ce qu'un mur devrait faire.
##
## [param target] La case qu'occupe la cible au moment du coup.
## [returns] {from, to: Vector2i, tiles: int, blocked: bool, path: Array[Vector2i]}
## — `tiles` est le nombre de cases réellement parcourues (0 : la cible n'a pas
## bougé), `blocked` dit que le recul a été écourté, `path` liste les cases
## traversées dans l'ordre.
static func resolve(grid: BattleGrid, target: Vector2i, dir: Vector2i,
		distance: int) -> Dictionary:
	var out: Dictionary = {
		"from": target, "to": target, "tiles": 0, "blocked": false, "path": [],
	}
	if grid == null or dir == Vector2i.ZERO or distance <= 0:
		out["blocked"] = true
		return out

	var current: Vector2i = target
	for _step: int in distance:
		var next: Vector2i = current + dir
		if not can_land(grid, next, current):
			out["blocked"] = true
			break
		out["path"].append(next)
		current = next

	out["to"] = current
	out["tiles"] = out["path"].size()
	return out


## Le recul complet en un appel : direction déduite, puis résolution.
##
## La forme que le service de combat appelle — il connaît deux positions, pas un
## axe. [param attacker] et [param target] sont des coordonnées de grille.
static func push_from(grid: BattleGrid, attacker: Vector2i, target: Vector2i,
		distance: int) -> Dictionary:
	return resolve(grid, target, direction(attacker, target), distance)
