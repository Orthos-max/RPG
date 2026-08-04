class_name PawnMoveMemory
extends RefCounted
## Mémoire du dernier déplacement d'un pion, pour pouvoir l'annuler.
##
## Fire Emblem laisse revenir sur un déplacement tant qu'on n'a rien fait
## d'autre : c'est ce qui rend le jeu lisible, puisqu'on ne découvre les portées
## ennemies qu'en s'avançant. La règle tient en trois conditions, réunies ici
## pour être vérifiées sans scène : on a bougé, on n'a pas encore agi, on est
## vivant.
##
## Ne connaît ni tuile ni nœud — juste une position monde et deux drapeaux.

## Position d'où le pion est parti
var origin: Vector3 = Vector3.ZERO
## Un déplacement est-il en mémoire ?
var has_moved: bool = false


## Retient le point de départ, juste avant que le pion s'élance.
func record(from: Vector3) -> void:
	origin = from
	has_moved = true


## Le déplacement peut-il encore être annulé ?
##
## [param can_attack] Le pion a-t-il encore son action ? Attaquer, soigner ou
## attendre la consomme : le déplacement devient alors définitif.
func can_undo(can_attack: bool, alive: bool = true) -> bool:
	return has_moved and can_attack and alive


## Rend le point de départ et oublie le déplacement.
##
## Renvoie [member origin] même si rien n'est en mémoire : l'appelant est censé
## avoir demandé [method can_undo] d'abord.
func consume() -> Vector3:
	var from: Vector3 = origin
	has_moved = false
	return from


## Oublie le déplacement (fin de tour, nouveau tour, mort).
func clear() -> void:
	origin = Vector3.ZERO
	has_moved = false
