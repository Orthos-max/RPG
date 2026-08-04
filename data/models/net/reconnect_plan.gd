class_name ReconnectPlan
extends RefCounted
## Côté invité : quand retenter la connexion après une coupure, et jusqu'à quand.
##
## Logique pure, même esprit que [SeatRegistry] : l'horloge vient de l'appelant,
## donc la règle se teste en headless sans attendre. [Network] se contente de
## demander « dois-je retenter maintenant ? » à chaque frame.
##
## Le code d'accès est conservé ici parce qu'il est ce qu'il faut pour revenir :
## une coupure ferme le pair, mais l'adresse de l'hôte, elle, n'a pas changé.

## Code d'accès à réutiliser ("" si aucune reconnexion en cours)
var code: String = ""
## Nombre de tentatives déjà faites
var attempt: int = 0
## Intervalle entre deux tentatives (secondes)
var interval: float = 3.0

var _deadline: float = 0.0
var _next_try: float = 0.0


## Démarre les tentatives : [param window] secondes pour revenir.
##
## La première tentative est immédiate — une coupure passagère (Wi-Fi qui saute
## une seconde) doit se rattraper sans attendre l'intervalle complet.
func start(join_code: String, now: float, window: float, retry_interval: float = 3.0) -> void:
	code = join_code
	interval = maxf(0.1, retry_interval)
	attempt = 0
	_deadline = now + maxf(0.0, window)
	_next_try = now


## Une reconnexion est-elle en cours ?
func is_active() -> bool:
	return not code.is_empty()


## Le délai de retour est-il écoulé ?
func is_expired(now: float) -> bool:
	return is_active() and now >= _deadline


## Secondes restantes pour revenir (0 hors reconnexion).
func remaining(now: float) -> float:
	if not is_active():
		return 0.0
	return maxf(0.0, _deadline - now)


## Faut-il retenter maintenant ? Décale l'échéance suivante et compte la tentative.
func consume_attempt(now: float) -> bool:
	if not is_active() or now < _next_try or is_expired(now):
		return false
	attempt += 1
	_next_try = now + interval
	return true


## Abandonne : plus aucune tentative.
func cancel() -> void:
	code = ""
	attempt = 0
	_deadline = 0.0
	_next_try = 0.0
