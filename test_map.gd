extends SceneTree
## Autonomous test runner for MapData + TacticsArena system.
## Run: godot --headless --path project_dir --script res://test_map.gd --quit

const _MD = preload("res://data/models/world/map/map_data.gd")
const _TC = preload("res://data/models/config/tactics_config.gd")
const TERRAIN = {GRASS=0, FOREST=1, MOUNTAIN=2, WATER=3, PATH=4, WALL=5, PIT=6}
const TERRAIN_NAMES = ["GRASS", "FOREST", "MOUNTAIN", "WATER", "PATH", "WALL", "PIT"]


func _init() -> void:
	var all_ok := true
	all_ok = _test_map_data() and all_ok
	all_ok = _test_terrain_materials() and all_ok
	all_ok = _test_scene_loading() and all_ok

	if all_ok:
		print_rich("[color=green][b]=== ALL TESTS PASSED ===[/b][/color]")
	else:
		print_rich("[color=red][b]=== SOME TESTS FAILED ===[/b][/color]")

	# Always quit after tests (headless mode)
	await create_timer(0.3).timeout
	quit(0 if all_ok else 1)


func _test_map_data() -> bool:
	print_rich("[color=cyan]--- Test: MapData Resource ---[/color]")
	
	var md = _MD.new()
	md.grid_size = Vector2i(16, 10)
	md.tile_size = 1.0
	md.init_default()
	
	var ok := true
	
	if md.terrain_grid.size() != 160:
		print_rich("[color=red]  FAIL: terrain_grid size = %d (expected 160)[/color]" % md.terrain_grid.size())
		ok = false
	else:
		print_rich("  OK: terrain_grid has 160 cells")
	
	if md.height_grid.size() != 160:
		print_rich("[color=red]  FAIL: height_grid size = %d[/color]" % md.height_grid.size())
		ok = false
	
	if md.get_terrain(0, 0) != TERRAIN.GRASS:
		print_rich("[color=red]  FAIL: default terrain = %d (expected 0=GRASS)[/color]" % md.get_terrain(0, 0))
		ok = false
	else:
		print_rich("  OK: default terrain is GRASS")
	
	md.set_terrain(3, 2, TERRAIN.FOREST)
	if md.get_terrain(3, 2) != TERRAIN.FOREST:
		print_rich("[color=red]  FAIL: set_terrain/get_terrain mismatch[/color]")
		ok = false
	
	md.set_height(5, 5, 1.5)
	if md.get_height(5, 5) != 1.5:
		print_rich("[color=red]  FAIL: height set/get mismatch[/color]")
		ok = false
	
	# Walkable checks
	if not md.is_walkable(TERRAIN.GRASS):    ok = false; print_rich("[color=red]  FAIL: GRASS walkable[/color]")
	if not md.is_walkable(TERRAIN.FOREST):   ok = false; print_rich("[color=red]  FAIL: FOREST walkable[/color]")
	if not md.is_walkable(TERRAIN.PATH):     ok = false; print_rich("[color=red]  FAIL: PATH walkable[/color]")
	if md.is_walkable(TERRAIN.WATER):        ok = false; print_rich("[color=red]  FAIL: WATER should be blocked[/color]")
	if md.is_walkable(TERRAIN.MOUNTAIN):     ok = false; print_rich("[color=red]  FAIL: MOUNTAIN should be blocked[/color]")
	if md.is_walkable(TERRAIN.WALL):         ok = false; print_rich("[color=red]  FAIL: WALL should be blocked[/color]")
	if md.is_walkable(TERRAIN.PIT):          ok = false; print_rich("[color=red]  FAIL: PIT should be blocked[/color]")
	print_rich("  OK: Walkable checks passed")
	
	# Defense bonus
	if md.get_defense_bonus(TERRAIN.FOREST) != 1:   ok = false; print_rich("[color=red]  FAIL: FOREST def[/color]")
	if md.get_defense_bonus(TERRAIN.MOUNTAIN) != 3:  ok = false; print_rich("[color=red]  FAIL: MOUNTAIN def[/color]")
	if md.get_defense_bonus(TERRAIN.GRASS) != 0:     ok = false; print_rich("[color=red]  FAIL: GRASS def[/color]")
	print_rich("  OK: Defense bonus checks passed")
	
	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok


func _test_terrain_materials() -> bool:
	print_rich("[color=cyan]--- Test: Terrain Materials ---[/color]")
	
	var ok := true
	var count := 0
	
	for t in range(7):
		var mat = _TC.terrain_material.get(t)
		if mat:
			count += 1
		else:
			print_rich("[color=red]  FAIL: No material for %s[/color]" % TERRAIN_NAMES[t])
			ok = false
	
	print_rich("  Materials: %d/7" % count)
	if count != 7: ok = false
	
	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok


func _test_scene_loading() -> bool:
	print_rich("[color=cyan]--- Test: Map Content ---[/color]")
	
	var ok := true
	
	# Test demo_map content directly (no scene chain)
	var demo = load("res://data/models/world/map/demo_map.tres")
	if not demo:
		print_rich("[color=red]  FAIL: demo_map.tres[/color]")
		return false
	
	print_rich("  OK: demo_map.tres loads")
	
	# Count terrain types
	var counts = {}
	for t in demo.terrain_grid:
		counts[t] = counts.get(t, 0) + 1
	
	var grass_only = counts.get(TERRAIN.GRASS, 0) >= demo.terrain_grid.size()
	if grass_only:
		print_rich("[color=red]  FAIL: All tiles are GRASS[/color]")
		ok = false
	else:
		var parts = []
		for t in counts:
			if t < TERRAIN_NAMES.size():
				parts.append("%s:%d" % [TERRAIN_NAMES[t], counts[t]])
		print_rich("  Terrain mix: %s" % ", ".join(parts))
	
	# Check heights
	var has_height = false
	var max_h = 0.0
	for h in demo.height_grid:
		if abs(h) > max_h: max_h = abs(h)
		if abs(h) > 0.01: has_height = true
	if has_height:
		print_rich("  OK: Height variations (max: %.1f)" % max_h)
	else:
		print_rich("[color=yellow]  WARN: No height variation[/color]")
	
	# Quick grid size check
	if demo.grid_size == Vector2i(16, 10):
		print_rich("  OK: grid_size = 16x10")
	else:
		print_rich("[color=red]  FAIL: wrong grid size[/color]")
		ok = false
	
	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok
