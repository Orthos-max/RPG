class_name TerrainPanel
extends PanelContainer
## Le terrain de la case survolée — son nom, et ce qu'il vaut à qui s'y tient.
##
## Le plateau annonçait ses terrains par la seule couleur de ses cases et la
## silhouette de leur décor. Avec seize terrains dont quatre donnent de la
## défense, reconnaître un fortin d'une ruine à l'œil devenait un pari : on
## décide où poser une unité sans savoir ce que la case lui rend.
##
## Ne calcule rien — [MapData] écrit le résumé, cet encart le recopie. Le même
## texte sert d'infobulle dans l'éditeur de cartes.

## Terrain affiché, pour ne pas réécrire le label soixante fois par seconde :
## le survol est réévalué à chaque frame, la case ne change qu'en bougeant.
var _shown: int = -1

@onready var _label: Label = $Margin/Label


func _ready() -> void:
	visible = false


## Affiche le terrain d'une case. Un entier négatif masque l'encart.
func show_terrain(terrain: int) -> void:
	if terrain < 0:
		clear_terrain()
		return
	visible = true
	if terrain == _shown:
		return
	_shown = terrain
	_label.text = MapData.type_summary(terrain)


func clear_terrain() -> void:
	visible = false
	_shown = -1
