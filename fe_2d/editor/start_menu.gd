extends CanvasLayer
## Menu de démarrage — choix Éditeur / Jeu

signal start_game
signal start_editor

func _ready():
	$VBox/GameBtn.grab_focus()
	
func _on_game_pressed():
	start_game.emit()

func _on_editor_pressed():
	start_editor.emit()

func _input(event: InputEvent):
	if event.is_action_pressed("ui_accept"):
		start_game.emit()
