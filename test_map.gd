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
	all_ok = _test_framing() and all_ok
	all_ok = _test_props() and all_ok

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


## Cadrage de bataille : la géométrie qui décide de ce que le joueur voit.
##
## Calcul pur, donc vérifiable sans monter une scène — et il vaut mieux, parce
## qu'une erreur ici ne se voit pas dans un journal : elle se voit à l'écran,
## sous la forme d'un plateau à moitié hors champ.
func _test_framing() -> bool:
	print_rich("[color=cyan]--- Test: Cadrage de bataille ---[/color]")
	var ok := true

	# Un plateau vu en diagonale se projette pareil qu'il soit posé en large ou
	# en long : c'est la somme de ses côtés qui compte, pas leur répartition.
	var wide := TacticsFraming.fit_size(Vector2(15, 9))
	var tall := TacticsFraming.fit_size(Vector2(9, 15))
	if not is_equal_approx(wide, tall):
		print_rich("[color=red]  FAIL: cadrage asymétrique (%.3f vs %.3f)[/color]" % [wide, tall])
		ok = false
	else:
		print_rich("  OK: 15×9 et 9×15 demandent le même cadrage (%.2f)" % wide)

	# La carte du chapitre 1 tient à l'écran, marge comprise.
	if not is_equal_approx(snappedf(wide, 0.001), 16.873):
		print_rich("[color=red]  FAIL: cadrage du 16×10 = %.3f (attendu 16.873)[/color]" % wide)
		ok = false
	else:
		print_rich("  OK: le 16×10 du chapitre 1 tient dans 16.87 unités de haut")

	# Une carte plus grande demande plus de recul, jamais moins.
	if TacticsFraming.fit_size(Vector2(31, 31)) <= wide:
		print_rich("[color=red]  FAIL: une grande carte ne demande pas plus de recul[/color]")
		ok = false
	else:
		print_rich("  OK: le cadrage croît avec le plateau")

	# Le cadrage d'ouverture reste dans des bornes lisibles, quelle que soit la
	# carte : une immense ne doit pas réduire les unités à des pixels.
	var huge := clampf(TacticsFraming.fit_size(Vector2(60, 60)),
		TacticsFraming.MIN_OPENING_SIZE, TacticsFraming.MAX_OPENING_SIZE)
	if huge != TacticsFraming.MAX_OPENING_SIZE:
		print_rich("[color=red]  FAIL: cadrage d'ouverture non borné (%.2f)[/color]" % huge)
		ok = false
	else:
		print_rich("  OK: l'ouverture reste bornée à [%.0f, %.0f]" % [
			TacticsFraming.MIN_OPENING_SIZE, TacticsFraming.MAX_OPENING_SIZE])

	# Sans tuile — arène pas encore montée — rien ne doit exploser.
	var empty: Dictionary = TacticsFraming.board_bounds(null)
	if empty["center"] != Vector3.ZERO or empty["size"] != Vector2.ZERO:
		print_rich("[color=red]  FAIL: une arène absente devrait mesurer zéro[/color]")
		ok = false
	else:
		print_rich("  OK: une arène absente ne fait pas dérailler la mesure")

	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok


## Décor des cases : ce qui pousse dessus, et ce qui ne doit jamais gêner.
##
## Trois promesses tenues ici plutôt qu'à l'œil : chaque terrain reçoit ce qui
## lui revient, rien ne dépasse la hauteur d'un pion, et le centre d'une case
## praticable reste dégagé. La dernière est la seule qui se voie en jouant —
## un feuillage sur la tête d'une unité — et la plus facile à casser en
## élargissant une frondaison.
##
## Tout passe par [method TacticsProps.placements] : le décor posé, lui, ne se
## laisse pas interroger sans écran (un `MultiMesh` y rend l'identité).
func _test_props() -> bool:
	print_rich("[color=cyan]--- Test: Décor des cases ---[/color]")
	var ok := true
	var tile_size := 1.0

	var cells: Array = []
	var terrains := [TERRAIN.FOREST, TERRAIN.MOUNTAIN, TERRAIN.WALL,
		TERRAIN.GRASS, TERRAIN.WATER, TERRAIN.PATH, TERRAIN.PIT]
	for i in terrains.size():
		cells.append({
			"cell": Vector2i(i, 0),
			"terrain": terrains[i],
			"top": Vector3(float(i) * tile_size, 0.0, 0.0),
		})

	var batches: Dictionary = TacticsProps.placements(cells, tile_size)

	# Chaque terrain reçoit sa garniture — et les autres n'en reçoivent aucune.
	var counts := {}
	for kind: String in batches:
		counts[kind] = batches[kind].size()
	var expected := {"trunk": 1, "canopy": 1, "rock": 2, "merlon": 1}
	if counts != expected:
		print_rich("[color=red]  FAIL: garniture %s (attendu %s)[/color]" % [str(counts), str(expected)])
		ok = false
	else:
		print_rich("  OK: forêt → arbre, montagne → 2 rochers, mur → créneau")
		print_rich("  OK: herbe, eau, chemin et fosse restent nus")

	# Rien ne dépasse la hauteur d'un pion. Tous les maillages font une unité de
	# haut : la composante verticale de l'échelle est donc la hauteur réelle.
	var tallest := 0.0
	for kind: String in batches:
		for xf: Transform3D in batches[kind]:
			var b: Basis = xf.basis
			var half_y: float = 0.5 * (absf(b.x.y) + absf(b.y.y) + absf(b.z.y))
			tallest = maxf(tallest, xf.origin.y + half_y)
	if tallest > TacticsProps.MAX_HEIGHT + 0.001:
		print_rich("[color=red]  FAIL: décor haut de %.2f (plafond %.2f)[/color]" % [
			tallest, TacticsProps.MAX_HEIGHT])
		ok = false
	else:
		print_rich("  OK: le plus haut décor tient sous le plafond (%.2f ≤ %.2f)" % [
			tallest, TacticsProps.MAX_HEIGHT])

	# Le centre d'une case praticable reste dégagé : la forêt se traverse.
	#
	# Tronc et frondaison sont des solides de révolution : leur emprise au sol est
	# un disque, dont le rayon ne dépend pas de l'orientation — l'encadrer par une
	# boîte tournée le surestimerait de 40 % et condamnerait un décor correct.
	var covered := false
	var margin := 1.0
	var radii := {"trunk": 0.06, "canopy": 0.22}
	for kind: String in radii:
		for xf: Transform3D in batches.get(kind, []):
			var radius: float = float(radii[kind]) * tile_size * xf.basis.x.length()
			var offset: float = Vector2(xf.origin.x, xf.origin.z).length()
			if offset <= radius:
				covered = true
			else:
				margin = minf(margin, 1.0 - radius / offset)
	if covered:
		print_rich("[color=red]  FAIL: le décor recouvre le centre d'une case praticable[/color]")
		ok = false
	else:
		print_rich("  OK: le centre d'une case de forêt reste libre (marge : %.0f %%)" % [margin * 100.0])

	# Deux calculs successifs donnent exactement le même bois.
	var again: Dictionary = TacticsProps.placements(cells, tile_size)
	if str(again) != str(batches):
		print_rich("[color=red]  FAIL: décor non déterministe[/color]")
		ok = false
	else:
		print_rich("  OK: recalculé à l'identique")

	# Et la pose, elle, ne s'empile pas : un seul nœud d'accueil.
	var host := Node3D.new()
	TacticsProps.build(host, cells, tile_size)
	TacticsProps.build(host, cells, tile_size)
	var hosts := 0
	for child in host.get_children():
		if child.name == "Props":
			hosts += 1
	if hosts != 1:
		print_rich("[color=red]  FAIL: %d nœuds « Props » empilés[/color]" % hosts)
		ok = false
	else:
		print_rich("  OK: reposer le décor remplace l'ancien au lieu de l'empiler")
	host.free()

	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok
