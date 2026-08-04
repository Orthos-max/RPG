class_name MapHistory
extends RefCounted
## Mémoire des états successifs d'une carte : annuler, rétablir.
##
## L'éditeur est un outil de dessin — un coup de pinceau malheureux ne doit pas
## être définitif. La pile ne retient pas des « actions » (peindre, poser,
## redimensionner) mais des instantanés complets du document
## ([method MapDocument.to_dict]) : un coup de pinceau qui noie une case de
## départ et efface l'unité qui s'y trouvait se défait alors d'un seul geste,
## sans que chaque outil ait à savoir se jouer à l'envers.
##
## Une carte fait au plus 32×24 cases : l'instantané est petit, et la profondeur
## se paie en mémoire, pas en complexité.
##
## Logique pure — se teste sans ouvrir de fenêtre.

## Nombre de coups annulables par défaut
const DEFAULT_DEPTH: int = 60

## Profondeur retenue (les coups plus anciens sont oubliés)
var depth: int = DEFAULT_DEPTH

## État courant de la carte
var _current: Dictionary = {}
## Coups plus anciens, du plus vieux au plus récent
var _past: Array[Dictionary] = []
## Coups annulés, prêts à être rétablis (du plus ancien au plus récent)
var _future: Array[Dictionary] = []


## Historique démarrant sur un état, sans rien à annuler.
static func started_on(snapshot: Dictionary, max_depth: int = DEFAULT_DEPTH) -> MapHistory:
	var history := MapHistory.new()
	history.depth = maxi(1, max_depth)
	history.reset(snapshot)
	return history


## Repart de zéro sur un état donné : plus rien à annuler ni à rétablir.
##
## Sert au chargement et à la création : annuler par-dessus une carte qu'on
## vient d'ouvrir ferait réapparaître la précédente, ce que personne n'attend.
func reset(snapshot: Dictionary) -> void:
	_current = snapshot.duplicate(true)
	_past.clear()
	_future.clear()


## Retient un nouvel état s'il diffère du précédent.
##
## [returns] vrai si quelque chose a changé — un clic sans effet (poser une
## unité sur un mur, refermer une case déjà fermée) n'encombre pas la pile.
func record(snapshot: Dictionary) -> bool:
	if snapshot == _current:
		return false
	_past.append(_current)
	while _past.size() > depth:
		_past.remove_at(0)
	_current = snapshot.duplicate(true)
	# Repartir dans une autre direction rend le futur caduc.
	_future.clear()
	return true


## Revient d'un coup. [returns] l'état à appliquer, vide s'il n'y a rien à annuler.
func undo() -> Dictionary:
	if _past.is_empty():
		return {}
	_future.append(_current)
	_current = _past.pop_back()
	return _current.duplicate(true)


## Refait le coup annulé. [returns] l'état à appliquer, vide s'il n'y a rien.
func redo() -> Dictionary:
	if _future.is_empty():
		return {}
	_past.append(_current)
	_current = _future.pop_back()
	return _current.duplicate(true)


func can_undo() -> bool:
	return not _past.is_empty()


func can_redo() -> bool:
	return not _future.is_empty()


## État courant tel que retenu (copie).
func current() -> Dictionary:
	return _current.duplicate(true)


## Nombre de coups annulables — pour l'affichage et les tests.
func undo_steps() -> int:
	return _past.size()


## Nombre de coups rétablissables.
func redo_steps() -> int:
	return _future.size()
