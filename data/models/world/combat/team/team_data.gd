class_name TeamData
extends Resource
## Un camp de la bataille et la façon dont il est piloté (M1 du chantier multijoueur).
##
## Le gameplay ne doit plus supposer « joueur humain local vs IA » : il demande à
## [GameSession] quel [enum Controller] pilote un camp. Ajouter le hotseat (M2) ou
## le réseau (M3) revient alors à changer le contrôleur, pas la boucle de tour.

enum Side {
	PLAYER = 0,   ## Camp bleu, joueur 1
	OPPONENT = 1, ## Camp rouge
	GUEST = 2,    ## Camp vert — troisième armée (M5 : Ciel et un ami dans la même bataille)
}

enum Controller {
	LOCAL_PLAYER = 0,  ## Humain sur cette machine (souris/clavier/manette)
	LOCAL_AI = 1,      ## IA heuristique embarquée ([LocalAIBrain])
	CIEL_AI = 2,       ## Ciel, via le pont JSON
	REMOTE_PLAYER = 3, ## Humain sur une autre machine (ENet)
}

## Camp concerné
@export var side: int = Side.PLAYER
## Nom affiché (écran d'attente, journal de combat)
@export var display_name: String = "Joueur"
## Qui prend les décisions pour ce camp
@export var controller: int = Controller.LOCAL_PLAYER
## Couleur d'équipe (UI, marqueurs de tuiles)
@export var color: Color = Color(0.35, 0.55, 1.0)
## Identifiant du pair réseau (0 = local/hôte). Réservé à M3.
@export var peer_id: int = 0


## Nom lisible d'un camp
static func side_name(side_id: int) -> String:
	match side_id:
		Side.PLAYER: return "Joueur"
		Side.OPPONENT: return "Adversaire"
		Side.GUEST: return "Troisième camp"
		_: return "Inconnu"


## Couleur d'un camp (UI, marqueurs de tuiles)
static func side_color(side_id: int) -> Color:
	match side_id:
		Side.PLAYER: return Color(0.35, 0.55, 1.0)
		Side.OPPONENT: return Color(0.9, 0.35, 0.35)
		Side.GUEST: return Color(0.4, 0.85, 0.45)
		_: return Color(0.7, 0.7, 0.7)


## Nom du nœud de camp dans la scène de bataille.
##
## C'est le seul endroit qui fait le lien entre un [enum Side] et l'arbre :
## la boucle de tour et le pont CielAI passent tous les deux par ici.
static func camp_node_name(side_id: int) -> String:
	match side_id:
		Side.PLAYER: return "TacticsPlayer"
		Side.OPPONENT: return "TacticsOpponent"
		Side.GUEST: return "TacticsGuest"
		_: return ""


## Camp correspondant à un nœud de la scène (−1 si inconnu).
static func side_for_camp_node(node: Node) -> int:
	if not node:
		return -1
	match String(node.name):
		"TacticsPlayer": return Side.PLAYER
		"TacticsOpponent": return Side.OPPONENT
		"TacticsGuest": return Side.GUEST
		_: return -1


## Étiquette d'équipe utilisée dans `ai_state.json` (contrat CielAI).
static func state_team_name(side_id: int) -> String:
	match side_id:
		Side.PLAYER: return "player"
		Side.OPPONENT: return "opponent"
		Side.GUEST: return "guest"
		_: return "unknown"


## Nom lisible d'un contrôleur
static func controller_name(ctrl: int) -> String:
	match ctrl:
		Controller.LOCAL_PLAYER: return "Joueur local"
		Controller.LOCAL_AI: return "IA locale"
		Controller.CIEL_AI: return "CielAI"
		Controller.REMOTE_PLAYER: return "Joueur distant"
		_: return "Inconnu"


## Ce camp est-il piloté par un humain (local ou distant) ?
func is_human() -> bool:
	return controller == Controller.LOCAL_PLAYER or controller == Controller.REMOTE_PLAYER


## Ce camp est-il piloté par une IA (locale ou Ciel) ?
func is_ai() -> bool:
	return controller == Controller.LOCAL_AI or controller == Controller.CIEL_AI


## Les décisions de ce camp sont-elles prises sur cette machine ?
func is_local_authority() -> bool:
	return controller != Controller.REMOTE_PLAYER


## Construit un camp prêt à l'emploi
static func create(side_id: int, ctrl: int, label: String = "") -> TeamData:
	var t := TeamData.new()
	t.side = side_id
	t.controller = ctrl
	t.display_name = label if not label.is_empty() else side_name(side_id)
	t.color = side_color(side_id)
	return t
