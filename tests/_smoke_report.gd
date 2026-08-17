extends SceneTree

const REPORT = preload("res://data/modules/ui/battle_report.gd")

func _init() -> void:
	await create_timer(0.2).timeout
	var events: Array = [
		{"kind_name": "attack", "attacker": "Elyan", "defender": "Brigand", "damage": 12, "hit": true, "crit": true},
		{"kind_name": "heal", "healer": "Lyra", "target": "Elyan", "amount": 8},
		{"kind_name": "death", "pawn": "Brigand", "team": "opponent", "killer": "Elyan"},
	]
	var roster := {
		"Elyan": {"team": "player", "class_id": 0},
		"Lyra": {"team": "player", "class_id": 6},
		"Brigand": {"team": "opponent", "class_id": 10},
	}
	print("available = ", REPORT.available())
	var panel: CanvasLayer = REPORT.new()
	panel.entries = REPORT.aggregate(events, roster)
	root.add_child(panel)
	await process_frame
	await process_frame
	var grid: Node = panel.find_child("*", true, false)
	print("ouvert = ", panel.is_open(), " unités = ", panel.unit_count())
	var cells := 0
	for n in _walk(panel):
		if n is Label:
			cells += 1
	print("labels = ", cells)
	panel.toggle()
	print("après toggle, ouvert = ", panel.is_open())
	await create_timer(0.2).timeout
	quit(0)

func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
