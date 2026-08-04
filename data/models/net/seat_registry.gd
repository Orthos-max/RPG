class_name SeatRegistry
extends RefCounted
## Places gardées pour un joueur distant tombé en cours de partie (hôte).
##
## Logique pure, sans nœud ni réseau : on lui donne l'instant courant, elle dit
## quelles places sont encore réservées et lesquelles ont expiré. [Network] s'en
## sert pour rendre son camp à un invité qui revient dans le délai de grâce —
## et pour laisser l'IA locale le garder définitivement au-delà.
##
## L'horloge est fournie par l'appelant : c'est ce qui rend la règle testable en
## headless sans attendre réellement quatre-vingt-dix secondes.

## Camp → instant d'expiration (secondes Unix)
var _seats: Dictionary = {}
## Camp → contrôleur à rendre au retour de l'invité
var _controllers: Dictionary = {}


## Réserve la place d'un camp pour [param grace] secondes.
##
## [param controller] est le contrôleur d'origine, mémorisé pour être rendu tel
## quel au retour : sans lui, un invité revenu récupérerait un camp devenu « IA
## locale » dans la session.
func reserve(side: int, now: float, grace: float, controller: int = -1) -> void:
	_seats[side] = now + maxf(0.0, grace)
	if controller != -1:
		_controllers[side] = controller


## Ce camp est-il gardé pour quelqu'un ?
func has_seat(side: int) -> bool:
	return _seats.has(side)


## Y a-t-il au moins une place gardée ?
func is_empty() -> bool:
	return _seats.is_empty()


## Secondes restantes avant la perte de la place (0 si aucune réservation).
func remaining(side: int, now: float) -> float:
	if not _seats.has(side):
		return 0.0
	return maxf(0.0, float(_seats[side]) - now)


## Toutes les places gardées : camp → secondes restantes.
func remaining_all(now: float) -> Dictionary:
	var out: Dictionary = {}
	for side: int in _seats:
		out[side] = remaining(side, now)
	return out


## Contrôleur mémorisé pour un camp (-1 si aucun).
func controller_of(side: int) -> int:
	return int(_controllers.get(side, -1))


## Rend sa place au joueur qui revient.
##
## [returns] Le contrôleur à restaurer, ou -1 si aucune place n'était gardée
## (l'appelant sait ainsi distinguer un retour d'une première connexion).
func claim(side: int, now: float) -> int:
	if not _seats.has(side) or remaining(side, now) <= 0.0:
		return -1
	var controller: int = controller_of(side)
	_seats.erase(side)
	_controllers.erase(side)
	return controller


## Première place gardée dont le délai est écoulé, ou -1.
##
## Retire la réservation au passage : chaque expiration n'est signalée qu'une fois.
func take_expired(now: float) -> int:
	for side: int in _seats:
		if float(_seats[side]) <= now:
			_seats.erase(side)
			_controllers.erase(side)
			return side
	return -1


## Oublie toutes les réservations.
func clear() -> void:
	_seats.clear()
	_controllers.clear()
