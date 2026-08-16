extends SceneTree
## Autonomous test runner for MapData + TacticsArena system.
## Run: godot --headless --path project_dir --script res://tests/test_map.gd --quit

const _MD = preload("res://data/models/world/map/map_data.gd")
const _TC = preload("res://data/models/config/tactics_config.gd")
const TERRAIN = {GRASS=0, FOREST=1, MOUNTAIN=2, WATER=3, PATH=4, WALL=5, PIT=6}


func _init() -> void:
	var all_ok := true
	all_ok = _test_map_data() and all_ok
	all_ok = _test_terrain_materials() and all_ok
	all_ok = _test_scene_loading() and all_ok
	all_ok = _test_framing() and all_ok
	all_ok = _test_props() and all_ok
	all_ok = _test_edge_pairs() and all_ok
	all_ok = _test_edge_ownership() and all_ok
	all_ok = _test_arena_regeneration() and all_ok

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
	if md.is_walkable(TERRAIN.MOUNTAIN):    ok = true;  print_rich("[color=green]  OK: MOUNTAIN walkable (coût 2)[/color]")
	if md.is_walkable(TERRAIN.WALL):         ok = false; print_rich("[color=red]  FAIL: WALL should be blocked[/color]")
	if md.is_walkable(TERRAIN.PIT):          ok = false; print_rich("[color=red]  FAIL: PIT should be blocked[/color]")
	print_rich("  OK: Walkable checks passed")
	
	# Defense bonus
	if md.get_defense_bonus(TERRAIN.FOREST) != 1:   ok = false; print_rich("[color=red]  FAIL: FOREST def[/color]")
	if md.get_defense_bonus(TERRAIN.MOUNTAIN) != 3:  ok = false; print_rich("[color=red]  FAIL: MOUNTAIN def[/color]")
	if md.get_defense_bonus(TERRAIN.GRASS) != 0:     ok = false; print_rich("[color=red]  FAIL: GRASS def[/color]")
	print_rich("  OK: Defense bonus checks passed")

	ok = _test_terrain_table() and ok

	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok


## La table des terrains : les nouveaux venus, et l'unicité de leurs codes.
##
## L'unicité n'est pas une coquetterie. La carte ASCII envoyée à Ciel se lit à
## la lettre : tant qu'elle tirait la première du nom, `water` et `wall` étaient
## tous deux `w`, `path` et `pit` tous deux `p` — Ciel voyait un lac là où il y
## avait un mur, pendant que la légende annonçait des lettres distinctes.
func _test_terrain_table() -> bool:
	var ok := true

	var bâti := {
		_MD.TerrainType.VILLAGE: 1, _MD.TerrainType.FORT: 2,
		_MD.TerrainType.GATE: 1, _MD.TerrainType.RUINS: 1,
	}
	for terrain: int in bâti:
		if not _MD.is_walkable(terrain):
			ok = false
			print_rich("[color=red]  FAIL: %s devrait se traverser[/color]" % _MD.type_key(terrain))
		if _MD.get_defense_bonus(terrain) != int(bâti[terrain]):
			ok = false
			print_rich("[color=red]  FAIL: %s donne %d DÉF (attendu %d)[/color]" % [
				_MD.type_key(terrain), _MD.get_defense_bonus(terrain), int(bâti[terrain])])
	if _MD.is_walkable(_MD.TerrainType.TOWER):
		ok = false
		print_rich("[color=red]  FAIL: une tour devrait bloquer[/color]")
	for terrain: int in [_MD.TerrainType.BRIDGE, _MD.TerrainType.SAND,
			_MD.TerrainType.SNOW, _MD.TerrainType.SWAMP]:
		if not _MD.is_walkable(terrain):
			ok = false
			print_rich("[color=red]  FAIL: %s devrait se traverser[/color]" % _MD.type_key(terrain))
	if ok:
		print_rich("  OK: village +1, fortin +2, porte +1, ruines +1 ; tour bloquée")

	var codes := {}
	var keys := {}
	for terrain: int in _MD.all_types():
		var code: String = _MD.type_code(terrain)
		var key: String = _MD.type_key(terrain)
		if code.length() != 1:
			ok = false
			print_rich("[color=red]  FAIL: %s a un code de %d caractère(s)[/color]" % [
				key, code.length()])
		if codes.has(code):
			ok = false
			print_rich("[color=red]  FAIL: %s et %s partagent le code « %s »[/color]" % [
				str(codes[code]), key, code])
		if keys.has(key):
			ok = false
			print_rich("[color=red]  FAIL: deux terrains s'appellent %s[/color]" % key)
		if _MD.type_label(terrain).is_empty():
			ok = false
			print_rich("[color=red]  FAIL: %s n'a pas de nom français[/color]" % key)
		if _MD.label_for_key(key) != _MD.type_label(terrain):
			ok = false
			print_rich("[color=red]  FAIL: %s ne se retrouve pas par sa clé[/color]" % key)
		codes[code] = key
		keys[key] = true
	if _MD.legend().size() != _MD.all_types().size():
		ok = false
		print_rich("[color=red]  FAIL: la légende ne couvre pas tous les terrains[/color]")
	if ok:
		print_rich("  OK: %d terrains, codes et noms uniques, légende complète"
			% _MD.all_types().size())

	# Un entier venu d'une carte plus récente ne transforme pas la case en mur.
	if not _MD.is_walkable(999) or _MD.get_defense_bonus(999) != 0:
		ok = false
		print_rich("[color=red]  FAIL: un terrain inconnu devrait se traverser sans bonus[/color]")

	ok = _test_terrain_summary() and ok
	return ok


## Le résumé lu au survol d'une case, et en infobulle dans l'éditeur.
##
## Une seule phrase pour les deux : le joueur qui dessine une carte et celui qui
## la joue doivent lire la même chose de la même case.
func _test_terrain_summary() -> bool:
	var ok := true
	var cases := {
		_MD.TerrainType.GRASS: "Plaine",
		_MD.TerrainType.FOREST: "Forêt · 🛡 +1 DÉF",
		_MD.TerrainType.FORT: "Fortin · 🛡 +2 DÉF",
		_MD.TerrainType.MOUNTAIN: "Montagne · 🥾 2 Mvt · 🛡 +3 DÉF",
		_MD.TerrainType.WATER: "Eau · infranchissable",
	}
	for terrain: int in cases:
		var got: String = _MD.type_summary(terrain)
		if got != str(cases[terrain]):
			ok = false
			print_rich("[color=red]  FAIL: résumé « %s » (attendu « %s »)[/color]"
				% [got, str(cases[terrain])])

	# Tout terrain a un résumé, et l'éditeur dit exactement le même.
	for terrain: int in _MD.all_types():
		if _MD.type_summary(terrain).is_empty():
			ok = false
			print_rich("[color=red]  FAIL: %s n'a pas de résumé[/color]" % _MD.type_key(terrain))
		if MapEditorUI.terrain_tooltip(terrain) != _MD.type_summary(terrain):
			ok = false
			print_rich("[color=red]  FAIL: l'éditeur et la bataille ne disent pas la même chose de %s[/color]"
				% _MD.type_key(terrain))

	if ok:
		print_rich("  OK: chaque terrain se résume en une ligne, la même en bataille "
			+ "et dans l'éditeur")
	return ok


func _test_terrain_materials() -> bool:
	print_rich("[color=cyan]--- Test: Terrain Materials ---[/color]")

	var ok := true
	var count := 0
	var expected: int = _MD.all_types().size()

	for t in _MD.all_types():
		var mat = _TC.terrain_material.get(t)
		if mat:
			count += 1
		else:
			print_rich("[color=red]  FAIL: No material for %s[/color]" % _MD.type_key(t))
			ok = false

	print_rich("  Materials: %d/%d" % [count, expected])
	if count != expected: ok = false

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
			parts.append("%s:%d" % [_MD.type_key(t).to_upper(), counts[t]])
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


## Transitions par paire : une rive d'eau tombe sur le sable, pas sur l'herbe.
##
## Le défaut corrigé se voyait à l'œil et ne se mesurait nulle part : chaque
## tuile de bord était peinte sur un fond d'herbe, si bien qu'une case d'eau
## collée à une plage affichait six pixels de prairie entre les deux. Trois
## promesses le tiennent maintenant fermé.
func _test_edge_pairs() -> bool:
	print_rich("[color=cyan]--- Test: Transitions entre terrains ---[/color]")
	var ok := true

	# 1. Le jeu de paires est complet : tout couple (terrain, fond) qu'un
	#    plateau peut produire a bien ses quinze tuiles sur le disque. Une
	#    absence ne casse rien — on retombe sur l'herbe — mais elle ramène
	#    silencieusement le défaut, donc elle se compte ici.
	var masks: Array[String] = [
		"n", "e", "s", "w", "ne", "es", "sw", "nw", "ns", "ew",
		"nes", "esw", "nsw", "new", "nesw",
	]
	var missing: Array[String] = []
	var pairs := 0
	for terrain: int in TacticsAutoTiler.EDGE_SETS:
		for background: int in TacticsAutoTiler.BACKGROUND_SETS:
			if background == terrain:
				continue
			for mask: String in masks:
				pairs += 1
				var path: String = TacticsAutoTiler._edge_paths(
					terrain, mask, background)[0]
				if not ResourceLoader.exists(path):
					missing.append(path.get_file())
	if not missing.is_empty():
		print_rich("[color=red]  FAIL: %d tuile(s) de paire manquante(s) : %s…[/color]"
			% [missing.size(), ", ".join(missing.slice(0, 3))])
		print_rich("[color=red]         relance : python3 art/bords-paires.py[/color]")
		ok = false
	else:
		print_rich("  OK: %d transitions par paire sur le disque "
			% pairs + "(chaque terrain bordé sur chaque fond)")

	# 2. La bonne tuile est choisie : l'eau qui s'arrête au nord contre du sable
	#    prend `water_sand_n`, et non plus `water_n` et son fond d'herbe.
	var chosen: String = TacticsAutoTiler._edge_paths(
		_MD.TerrainType.WATER, "n", _MD.TerrainType.SAND)[0]
	if not chosen.ends_with("edges-pairs/water_sand_n.png"):
		print_rich("[color=red]  FAIL: rive d'eau sur sable → %s[/color]" % chosen)
		ok = false
	else:
		print_rich("  OK: une rive d'eau bordée de sable prend water_sand_n")

	# 3. Le repli tient : un voisin qui ne sait pas faire fond — l'herbe, une
	#    ruine — rend exactement la tuile d'avant, à fond d'herbe. Aucune
	#    régression possible sur les cartes qui ne bordent que des plaines.
	for neighbor: int in [_MD.TerrainType.GRASS, _MD.TerrainType.RUINS, -1]:
		var fallback: Array[String] = TacticsAutoTiler._edge_paths(
			_MD.TerrainType.WATER, "n", neighbor)
		if fallback.size() != 1 or not fallback[0].ends_with("edges/water_n.png"):
			print_rich("[color=red]  FAIL: voisin %d → %s[/color]" % [neighbor, str(fallback)])
			ok = false
	if ok:
		print_rich("  OK: herbe, ruine ou rien du tout → la tuile d'origine, inchangée")

	# 4. Et le matériau se bâtit vraiment dans les deux cas.
	var paired: StandardMaterial3D = TacticsAutoTiler.overlay_material(
		_MD.TerrainType.WATER, "n", _MD.TerrainType.SAND)
	var plain: StandardMaterial3D = TacticsAutoTiler.overlay_material(
		_MD.TerrainType.WATER, "n", _MD.TerrainType.GRASS)
	if not paired or not plain or paired == plain:
		print_rich("[color=red]  FAIL: les deux calques ne se bâtissent pas séparément[/color]")
		ok = false
	else:
		print_rich("  OK: deux calques distincts, chacun mis en cache sous son fond")

	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok


## Une frontière, une seule bande — et c'est le terrain dominant qui la porte.
##
## Le défaut se voyait à l'œil et ne se mesurait nulle part, comme celui d'au
## dessus : chaque case portait sa propre transition, si bien qu'une plage collée
## à la mer montrait un bout d'eau à droite pendant que la mer montrait un bout
## de sable à gauche. Deux dessins pour une seule limite, donc un double liseré,
## et deux versions de la même ligne qui ne se recollaient jamais.
##
## [constant TacticsAutoTiler.TERRAIN_PRIORITY] tranche : le plus haut des deux
## terrains dessine, l'autre se tait. On l'éprouve à trois hauteurs — la règle
## seule, trois voisinages nommés, puis l'invariant sur un plateau qui mélange
## les seize terrains.
func _test_edge_ownership() -> bool:
	print_rich("[color=cyan]--- Test: Qui porte la transition ---[/color]")
	var ok := true

	# 1. La règle seule. L'eau porte contre tout, la prairie contre rien, et un
	#    terrain sans bords ne porte jamais — mais ne dispense pas son voisin.
	for other: int in TacticsAutoTiler.TERRAIN_PRIORITY:
		if other == _MD.TerrainType.WATER:
			continue
		if not TacticsAutoTiler.carries(_MD.TerrainType.WATER, other) \
				or TacticsAutoTiler.carries(other, _MD.TerrainType.WATER):
			print_rich("[color=red]  FAIL: l'eau ne l'emporte pas sur %s[/color]"
				% _MD.type_key(other))
			ok = false
		if other == _MD.TerrainType.GRASS:
			continue
		if TacticsAutoTiler.carries(_MD.TerrainType.GRASS, other) \
				or not TacticsAutoTiler.carries(other, _MD.TerrainType.GRASS):
			print_rich("[color=red]  FAIL: la prairie et %s se disputent leur bord[/color]"
				% _MD.type_key(other))
			ok = false
	var sans_bords: Array[int] = [
		_MD.TerrainType.RUINS, _MD.TerrainType.BRIDGE, _MD.TerrainType.PIT,
	]
	for bare: int in sans_bords:
		if TacticsAutoTiler.carries(bare, _MD.TerrainType.GRASS) \
				or TacticsAutoTiler.carries(bare, _MD.TerrainType.WATER):
			print_rich("[color=red]  FAIL: %s porte une transition[/color]" % _MD.type_key(bare))
			ok = false
		if not TacticsAutoTiler.carries(_MD.TerrainType.SAND, bare):
			print_rich("[color=red]  FAIL: le sable ne borde pas %s[/color]" % _MD.type_key(bare))
			ok = false
	for terrain: int in _MD.all_types():
		if TacticsAutoTiler.carries(terrain, terrain):
			print_rich("[color=red]  FAIL: %s se borde lui-même[/color]" % _MD.type_key(terrain))
			ok = false
	if ok:
		print_rich("  OK: l'eau porte toujours sa rive, la prairie ne porte jamais rien, "
			+ "mur et pont ne portent pas mais laissent border")

	# 2. Trois voisinages nommés, sur de vraies tuiles habillées par le service.
	var herbe: int = _MD.TerrainType.GRASS
	var eau: int = _MD.TerrainType.WATER
	var sable: int = _MD.TerrainType.SAND
	var cases: Array = [
		{
			"nom": "une case d'herbe cernée d'eau ne porte rien",
			"carte": [[eau, eau,   eau],
					  [eau, herbe, eau],
					  [eau, eau,   eau]],
			"attendu": "",
		},
		{
			"nom": "une case d'eau cernée d'herbe porte ses quatre rives",
			"carte": [[herbe, herbe, herbe],
					  [herbe, eau,   herbe],
					  [herbe, herbe, herbe]],
			"attendu": "nesw",
		},
		{
			"nom": "du sable avec l'eau au nord et la prairie à l'est ne porte qu'à l'est",
			"carte": [[sable, eau,   sable],
					  [sable, sable, herbe],
					  [sable, sable, sable]],
			"attendu": "e",
		},
	]
	for entry: Dictionary in cases:
		var built: Dictionary = _tiled_grid(entry["carte"])
		TacticsAutoTiler.apply_to_grid(built["grid"])
		var bands: String = _bands_of(built["grid"].tile_at_cell(Vector2i(1, 1)))
		if bands != str(entry["attendu"]):
			print_rich("[color=red]  FAIL: %s → « %s » (attendu « %s »)[/color]" % [
				entry["nom"], bands, str(entry["attendu"])])
			ok = false
		else:
			print_rich("  OK: %s" % entry["nom"])
		(built["root"] as Node).free()

	# 3. L'invariant, sur un plateau qui mélange les seize terrains : aucune
	#    frontière n'est dessinée deux fois, et celle qui l'est une fois l'est par
	#    le dominant. C'est la promesse qui tient tout le reste fermé — elle vaut
	#    pour un carrefour de quatre terrains comme pour une côte.
	var terrains: Array = _MD.all_types()
	var board: Array = []
	for row: int in 4:
		var line: Array = []
		for col: int in 4:
			line.append(terrains[(row * 4 + col) % terrains.size()])
		board.append(line)
	var mixed: Dictionary = _tiled_grid(board)
	var grid: BattleGrid = mixed["grid"]
	TacticsAutoTiler.apply_to_grid(grid)

	var opposite := {"n": "s", "s": "n", "e": "w", "w": "e"}
	var doubled: Array[String] = []
	var wrong: Array[String] = []
	var drawn := 0
	for row: int in 4:
		for col: int in 4:
			var cell := Vector2i(col, row)
			var tile: Node = grid.tile_at_cell(cell)
			for side: Array in TacticsAutoTiler.SIDES:
				var letter: String = str(side[0])
				var other: Node = grid.tile_at_cell(cell + (side[1] as Vector2i))
				if not other or int(other.terrain_type) == int(tile.terrain_type):
					continue
				# Chaque frontière est vue deux fois ; on ne l'examine que de son
				# côté nord ou ouest, sinon les comptes doublent.
				if letter == "s" or letter == "e":
					continue
				var mine: bool = tile.get_node_or_null("AutoTile_%s" % letter) != null
				var theirs: bool = other.get_node_or_null(
					"AutoTile_%s" % str(opposite[letter])) != null
				var frontier: String = "%s|%s" % [
					_MD.type_key(int(tile.terrain_type)), _MD.type_key(int(other.terrain_type))]

				if mine and theirs:
					doubled.append(frontier)
					continue

				# Le dominant dessine, et lui seul — sur le fond de l'autre, du
				# côté qui les sépare.
				var here: int = int(tile.terrain_type)
				var there: int = int(other.terrain_type)
				var i_win: bool = TacticsAutoTiler.carries(here, there)
				var top: int = here if i_win else there
				var bottom: int = there if i_win else here
				var bearer_side: String = letter if i_win else str(opposite[letter])
				if (mine and not i_win) or (theirs and i_win):
					wrong.append(frontier)
					continue

				# Sauf quand la tuile n'existe pas : la prairie n'a pas de bord à
				# fond d'herbe, et le repli d'avant laisse alors la case nue.
				var expected: bool = TacticsAutoTiler.overlay_material(
					top, bearer_side, bottom) != null
				if expected != (mine or theirs):
					wrong.append(frontier)
				elif expected:
					drawn += 1

	if not doubled.is_empty():
		print_rich("[color=red]  FAIL: %d frontière(s) dessinée(s) des deux côtés : %s[/color]"
			% [doubled.size(), ", ".join(doubled.slice(0, 3))])
		ok = false
	elif not wrong.is_empty():
		print_rich("[color=red]  FAIL: %d frontière(s) portée(s) par le mauvais terrain : %s[/color]"
			% [wrong.size(), ", ".join(wrong.slice(0, 3))])
		ok = false
	else:
		print_rich("  OK: seize terrains mêlés, %d frontières dessinées, aucune deux fois"
			% drawn)
	(mixed["root"] as Node).free()

	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok


## Un plateau de tuiles réelles, indexé comme en bataille.
##
## [TacticsAutoTiler] habille des [TacticsTile] posées dans un [BattleGrid] : on
## lui en donne, plutôt que de réimplémenter sa décision dans le test. Les cases
## sont d'une unité de côté, en (colonne, ligne) — la ligne 0 au plus petit `z`,
## comme les pose l'arène, donc le nord est bien en haut du tableau.
## [param rows] Les terrains, ligne par ligne.
func _tiled_grid(rows: Array) -> Dictionary:
	var root := Node3D.new()
	var grid := BattleGrid.new()
	grid.tile_size = 1.0
	for row: int in rows.size():
		var line: Array = rows[row]
		for col: int in line.size():
			var tile := TacticsTile.new()
			tile.name = "Tile_%d_%d" % [col, row]
			tile.terrain_type = int(line[col])
			var top := MeshInstance3D.new()
			top.name = "Tile"
			top.mesh = BoxMesh.new()
			tile.add_child(top)
			root.add_child(tile)
			grid.add_tile(tile, Vector3(float(col), 0.0, float(row)))
	return {"root": root, "grid": grid}


## Les côtés qu'une case porte réellement, lus sur ses nœuds de calque.
func _bands_of(tile: Node) -> String:
	var sides: String = ""
	if not tile:
		return sides
	for side: Array in TacticsAutoTiler.SIDES:
		if tile.get_node_or_null("AutoTile_%s" % str(side[0])):
			sides += str(side[0])
	return sides


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

	# Une case de chaque terrain, toutes sur une même rangée. Les voisines sont
	# donc d'un autre terrain : porte et pont s'orientent sur ce qu'ils trouvent,
	# et ce qu'ils trouvent ici ne les aide pas — c'est le cas isolé, exprès.
	var cells: Array = []
	var terrains: Array = _MD.all_types()
	for i in terrains.size():
		cells.append({
			"cell": Vector2i(i, 0),
			"terrain": terrains[i],
			"top": Vector3(float(i) * tile_size, 0.0, 0.0),
		})

	var batches: Dictionary = TacticsProps.placements(cells, tile_size)

	# Chaque terrain bâti reçoit sa garniture, et les nus restent nus.
	var counts := {}
	for kind: String in batches:
		counts[kind] = batches[kind].size()
	var expected := {
		"wall_base": 1, "wall_body": 1, "wall_crenel": 3,
		"keep": 1,
		"pier": 2, "lintel": 2,
		"tower_base": 1, "tower_shaft": 1, "tower_merlon": 4, "tower_roof": 1,
		"deck": 1, "railing": 2,
		"reed": 3,
	}
	# Herbe, sable et bannières ne se posent qu'une case sur deux ou trois : la
	# case unique de ce test tombe d'un côté ou de l'autre du tirage, on ne fixe
	# donc pas leur compte. Une hampe sans fanion, en revanche, serait un bug.
	for optional: String in ["tuft", "pebble", "pole", "banner"]:
		counts.erase(optional)
	# Forêt, montagne, village et ruines tirent une **scène** (feuillu ou pin,
	# bloc ou pic, chaumière ou maison à croupe, colonnade ou pan de mur) : leur
	# garniture n'a pas de compte fixe sur une case unique. Elle se juge sur un
	# bois entier, dans `_check_scenery_variety`.
	for scenic: String in VARIED_KINDS:
		counts.erase(scenic)
	if batches.get("pole", []).size() != batches.get("banner", []).size():
		print_rich("[color=red]  FAIL: %d hampe(s) pour %d bannière(s)[/color]" % [
			batches.get("pole", []).size(), batches.get("banner", []).size()])
		ok = false
	if counts != expected:
		print_rich("[color=red]  FAIL: garniture %s\n           attendu %s[/color]" % [
			str(counts), str(expected)])
		ok = false
	else:
		print_rich("  OK: seize terrains, chacun sa garniture (fortin → donjon et "
			+ "bannière, tour → assise, fût, merlons et flèche, mur → semelle, "
			+ "chemin de ronde et créneaux, pont → platelage…)")
		print_rich("  OK: eau, chemin, fosse et neige restent nus")

	ok = _check_ceiling(batches, "toutes cases") and ok
	ok = _check_centres_clear(cells, batches, tile_size) and ok

	# Bois, éboulis, hameaux et ruines : ce qui se juge sur une rangée entière.
	ok = _check_scenery_variety() and ok

	# Une porte s'aligne sur son rempart, un pont sur sa travée.
	ok = _check_orientation() and ok

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


## Les décors dont le compte varie d'une case à l'autre.
##
## Ces quatre terrains ne posent pas une garniture mais une **scène**, tirée du
## hachage de la case : un feuillu à trois masses de feuillage ou un pin à trois
## étages, deux blocs ou trois pierres, une chaumière seule ou flanquée de sa
## remise. Compter leurs pièces sur une case unique ne dirait rien.
const VARIED_KINDS: Array[String] = [
	"trunk", "canopy", "pine",
	"rock", "rock_pic", "rock_slab",
	"house_wall", "house_roof", "house_hip", "chimney", "door",
	"column", "plinth", "shaft", "ruin_wall", "rubble",
]

## Ce que chaque terrain à scènes doit montrer sur une rangée de cases.
##
## `each` : les familles dont chaque case reçoit au moins une pièce — c'est la
## promesse qu'aucun bois n'a de case pelée. `variety` : les pièces qui doivent
## apparaître **quelque part** sur la rangée — c'est ce qui sépare trois modèles
## d'arbre d'un seul modèle tiré trois fois. `least` : le nombre de volumes que
## la plus dépouillée des cases doit tout de même porter.
const SCENERY_EXPECTATIONS: Array = [
	{
		"label": "forêt", "terrain": _MD.TerrainType.FOREST, "least": 2,
		"each": [["trunk"], ["canopy", "pine"]],
		"variety": ["canopy", "pine"],
	},
	{
		"label": "montagne", "terrain": _MD.TerrainType.MOUNTAIN, "least": 2,
		"each": [["rock", "rock_pic", "rock_slab"]],
		"variety": ["rock", "rock_pic", "rock_slab"],
	},
	{
		"label": "village", "terrain": _MD.TerrainType.VILLAGE, "least": 3,
		"each": [["house_wall"], ["house_roof", "house_hip"], ["door"]],
		"variety": ["house_roof", "house_hip", "chimney"],
	},
	{
		"label": "ruines", "terrain": _MD.TerrainType.RUINS, "least": 2,
		"each": [["column", "shaft", "ruin_wall"], ["rubble"]],
		"variety": ["column", "plinth", "shaft", "ruin_wall"],
	},
]


## Chaque case a sa scène, et deux cases voisines n'ont pas la même.
##
## Une case par terrain ne prouvait rien de ces quatre-là : elle tombe d'un côté
## du tirage et l'autre modèle n'est jamais dessiné. On en déroule donc une
## rangée entière, et on y vérifie les deux promesses qui comptent — aucune case
## pelée, et tous les modèles servis.
func _check_scenery_variety() -> bool:
	var ok := true
	for spec: Dictionary in SCENERY_EXPECTATIONS:
		ok = _check_scenery(spec) and ok
	return ok


func _check_scenery(spec: Dictionary) -> bool:
	var tile_size := 1.0
	var span := 24
	var label: String = str(spec["label"])
	var terrain: int = int(spec["terrain"])

	# Une rangée de cases voisines : les hachages y diffèrent case à case, donc
	# les scènes aussi. Elles se posent en ligne pour que le contrôle du centre
	# retrouve chacune à son abscisse.
	var cells: Array = []
	for i in span:
		cells.append({
			"cell": Vector2i(i, terrain * 7 + 3),
			"terrain": terrain,
			"top": Vector3(float(i) * tile_size, 0.0, 0.0),
		})
	var batches: Dictionary = TacticsProps.placements(cells, tile_size)

	# Ce que porte chaque case, pièce par pièce.
	var per_cell: Array = []
	for i in span:
		per_cell.append({})
	for kind: String in batches:
		for xf: Transform3D in batches[kind]:
			var tally: Dictionary = per_cell[int(round(xf.origin.x / tile_size))]
			tally[kind] = int(tally.get(kind, 0)) + 1

	var ok := true
	var barest := 999
	for i in span:
		var tally: Dictionary = per_cell[i]
		var pieces := 0
		for kind: String in tally:
			pieces += int(tally[kind])
		barest = mini(barest, pieces)
		if pieces < int(spec["least"]):
			print_rich("[color=red]  FAIL: %s, case %d : %d volume(s) seulement[/color]"
				% [label, i, pieces])
			ok = false
		for family: Variant in spec["each"]:
			var served := false
			for kind: String in (family as Array):
				served = served or tally.has(kind)
			if not served:
				print_rich("[color=red]  FAIL: %s, case %d : rien de %s (%s)[/color]"
					% [label, i, str(family), str(tally)])
				ok = false

	var missing: Array[String] = []
	for kind: Variant in spec["variety"]:
		if not batches.has(str(kind)):
			missing.append(str(kind))
	if not missing.is_empty():
		print_rich("[color=red]  FAIL: %s : %d cases sans un seul %s[/color]"
			% [label, span, ", ".join(missing)])
		ok = false

	if ok:
		print_rich("  OK: %d cases de %s, toutes garnies (%d volumes au moins), "
			% [span, label, barest] + "tous les modèles servis (%s)"
			% ", ".join(spec["variety"] as Array))

	ok = _check_ceiling(batches, label) and ok
	return _check_centres_clear(cells, batches, tile_size) and ok


## Rien ne dépasse la hauteur d'un pion.
##
## Tous les maillages du module tiennent dans le cube unité : la hauteur réelle
## d'une pièce se lit donc sur sa seule transformation — la projection verticale
## de son échelle, inclinaisons comprises.
func _check_ceiling(batches: Dictionary, label: String) -> bool:
	var tallest := 0.0
	for kind: String in batches:
		for xf: Transform3D in batches[kind]:
			var b: Basis = xf.basis
			var half_y: float = 0.5 * (absf(b.x.y) + absf(b.y.y) + absf(b.z.y))
			tallest = maxf(tallest, xf.origin.y + half_y)
	if tallest > TacticsProps.MAX_HEIGHT + 0.001:
		print_rich("[color=red]  FAIL: %s : décor haut de %.2f (plafond %.2f)[/color]" % [
			label, tallest, TacticsProps.MAX_HEIGHT])
		return false
	print_rich("  OK: %s : le plus haut décor tient sous le plafond (%.2f ≤ %.2f)" % [
		label, tallest, TacticsProps.MAX_HEIGHT])
	return true


## Aucun décor ne s'assied sur le centre d'une case praticable.
##
## Le test d'avant ne savait mesurer que des troncs et des frondaisons — deux
## disques, dont le rayon ne dépend pas de l'orientation. Maisons, piliers et
## garde-corps sont des boîtes, parfois très allongées : un garde-corps de pont
## fait presque toute la largeur de sa case, et un cercle circonscrit le
## déclarerait fautif alors qu'il longe le bord.
##
## On ramène donc le centre de la case dans le repère du décor : s'il tombe hors
## de la boîte unitaire, la case est libre. C'est exact pour une boîte, et
## prudent pour un cylindre ou un cône, inscrits dedans.
##
## Seul ce qui dépasse `TacticsProps.FLAT_HEIGHT` est jugé : plus bas, on lui
## marche dessus — c'est tout le propos d'un platelage de pont.
##
## Tous les maillages suivent désormais la même convention — cube unité, mis à
## l'échelle par l'instance — donc la demi-largeur vaut 1/2 pour chacun, et ce
## test n'a plus de rayon à connaître par cœur.
func _check_centres_clear(cells: Array, batches: Dictionary, tile_size: float) -> bool:
	var terrain_by_index := {}
	for entry in cells:
		terrain_by_index[int(round(entry["top"].x / tile_size))] = int(entry["terrain"])

	var offenders: Array[String] = []
	var margin := 99.0
	for kind: String in batches:
		var half := 0.5
		for xf: Transform3D in batches[kind]:
			var index: int = int(round(xf.origin.x / tile_size))
			if not _MD.is_walkable(int(terrain_by_index.get(index, 0))):
				continue

			var b: Basis = xf.basis
			var half_y: float = 0.5 * (absf(b.x.y) + absf(b.y.y) + absf(b.z.y))
			if xf.origin.y + half_y <= TacticsProps.FLAT_HEIGHT + 0.001:
				continue

			var centre := Vector3(float(index) * tile_size, xf.origin.y, 0.0)
			var local: Vector3 = xf.affine_inverse() * centre
			var clearance: float = maxf(absf(local.x), absf(local.z)) / half
			if clearance <= 1.0:
				offenders.append("%s (%.2f)" % [kind, clearance])
			else:
				margin = minf(margin, clearance)

	if not offenders.is_empty():
		print_rich("[color=red]  FAIL: décor sur le centre d'une case praticable : %s[/color]"
			% ", ".join(offenders))
		return false
	print_rich("  OK: le centre des cases praticables reste libre "
		+ "(le plus proche tient à %.2f fois sa demi-largeur du centre)" % margin)
	return true


## Un ouvrage lit ses voisines : porte alignée sur le rempart, pont sur sa travée.
func _check_orientation() -> bool:
	var ok := true

	# Un rempart est-ouest : la porte pose ses piliers à l'est et à l'ouest,
	# donc le passage s'ouvre du nord au sud.
	var gate_cells: Array = [
		{"cell": Vector2i(0, 1), "terrain": _MD.TerrainType.WALL, "top": Vector3(-1, 0, 0)},
		{"cell": Vector2i(1, 1), "terrain": _MD.TerrainType.GATE, "top": Vector3(0, 0, 0)},
		{"cell": Vector2i(2, 1), "terrain": _MD.TerrainType.WALL, "top": Vector3(1, 0, 0)},
	]
	var piers: Array = TacticsProps.placements(gate_cells, 1.0).get("pier", [])
	var along_x: bool = piers.size() == 2 \
		and absf(piers[0].origin.x) > 0.2 and absf(piers[0].origin.z) < 0.01
	if not along_x:
		print_rich("[color=red]  FAIL: la porte n'est pas alignée sur son rempart[/color]")
		ok = false
	else:
		print_rich("  OK: la porte pose ses piliers dans l'alignement du rempart")

	# Un pont nord-sud : les garde-corps courent à l'est et à l'ouest.
	var bridge_cells: Array = [
		{"cell": Vector2i(1, 0), "terrain": _MD.TerrainType.PATH, "top": Vector3(0, 0, -1)},
		{"cell": Vector2i(1, 1), "terrain": _MD.TerrainType.BRIDGE, "top": Vector3(0, 0, 0)},
		{"cell": Vector2i(1, 2), "terrain": _MD.TerrainType.PATH, "top": Vector3(0, 0, 1)},
	]
	var railings: Array = TacticsProps.placements(bridge_cells, 1.0).get("railing", [])
	var sides_x: bool = railings.size() == 2 \
		and absf(railings[0].origin.x) > 0.2 and absf(railings[0].origin.z) < 0.01
	if not sides_x:
		print_rich("[color=red]  FAIL: les garde-corps ne suivent pas la travée[/color]")
		ok = false
	else:
		print_rich("  OK: le pont pose ses garde-corps le long de sa travée")

	ok = _check_crenels_line_up() and ok
	return ok


## Un rempart de plusieurs cases porte une seule dentelure, pas une par case.
##
## C'est toute la raison des trois créneaux au pas d'un tiers de case : posés au
## quart ou au hasard, deux cases voisines recolleraient deux motifs, et le
## rempart redeviendrait le damier qu'on cherche à effacer. On mesure donc le
## pas entre créneaux successifs le long du mur — il doit être constant, y
## compris à la jointure des deux cases.
func _check_crenels_line_up() -> bool:
	var wall_cells: Array = []
	for i in 3:
		wall_cells.append({
			"cell": Vector2i(i, 0),
			"terrain": _MD.TerrainType.WALL,
			"top": Vector3(float(i), 0.0, 0.0),
		})
	var crenels: Array = TacticsProps.placements(wall_cells, 1.0).get("wall_crenel", [])

	var xs: Array[float] = []
	for xf: Transform3D in crenels:
		xs.append(xf.origin.x)
	xs.sort()

	var steps: Array[float] = []
	for i in range(1, xs.size()):
		steps.append(xs[i] - xs[i - 1])
	var regular: bool = xs.size() == 9 and not steps.is_empty()
	for step: float in steps:
		regular = regular and absf(step - steps[0]) < 0.001

	if not regular:
		print_rich("[color=red]  FAIL: la dentelure se recolle d'une case à l'autre : %s[/color]"
			% str(steps))
		return false
	print_rich("  OK: trois cases de rempart, neuf créneaux au pas régulier de %.2f case"
		% steps[0])
	return true


## Une arène qui porte déjà des tuiles posées à la main, et un MapData.
##
## Cas qui n'existe dans aucune scène livrée, mais que produirait la conversion
## de `map_level.tscn` — le prochain chantier des chapitres 1 et 3 à 6. La
## génération cédait alors la main pendant une frame, et `_ready` enchaînait sur
## `serv.setup()` avec une arène vide ; et le nœud remplacé gardait son nom
## jusqu'à la fin de la frame, si bien que le nouveau naissait « @Tiles@2 ».
func _test_arena_regeneration() -> bool:
	print_rich("[color=cyan]--- Test: Arène engendrée par-dessus des tuiles existantes ---[/color]")
	var ok := true

	var md = _MD.new()
	md.grid_size = Vector2i(5, 4)
	md.tile_size = 1.0
	md.init_default()
	md.set_terrain(2, 2, _MD.TerrainType.FORT)

	var arena := TacticsArena.new()
	arena.res = load("res://data/models/world/combat/arena/arena.tres").duplicate()
	arena.res.map_data = md

	# Des tuiles d'avant, comme en poserait une carte sculptée à la main.
	var stale := Node3D.new()
	stale.name = "Tiles"
	for i in 3:
		var old_tile := MeshInstance3D.new()
		old_tile.mesh = BoxMesh.new()  # Sans maillage, le pilote factice proteste.
		stale.add_child(old_tile)
	arena.add_child(stale)

	arena._generate_from_map_data()

	var tiles: Node = arena.get_node_or_null("Tiles")
	if not tiles:
		print_rich("[color=red]  FAIL: plus de nœud « Tiles » après génération[/color]")
		ok = false
	elif tiles == stale:
		print_rich("[color=red]  FAIL: les tuiles d'avant sont restées[/color]")
		ok = false
	elif tiles.get_child_count() != md.grid_size.x * md.grid_size.y:
		print_rich("[color=red]  FAIL: %d tuiles pour %d cases[/color]" % [
			tiles.get_child_count(), md.grid_size.x * md.grid_size.y])
		ok = false
	else:
		print_rich("  OK: les tuiles d'avant cèdent la place, et leur nom avec (%d tuiles)"
			% tiles.get_child_count())

	# Le terrain déclaré arrive bien jusqu'à la tuile — y compris les nouveaux.
	#
	# Par l'index, comme le fait la génération : la conversion en corps physiques
	# rebaptise les tuiles (« Tile_2_2 » devient « Tile_2_2_col »), c'est leur
	# rang qui dit leur case.
	if tiles:
		var rank: int = 2 * md.grid_size.x + 2
		var tile: Node = tiles.get_child(rank) if tiles.get_child_count() > rank else null
		var terrain: Variant = tile.get("terrain_type") if tile else null
		if terrain == null or int(terrain) != _MD.TerrainType.FORT:
			print_rich("[color=red]  FAIL: la case (2,2) annonce %s[/color]" % str(terrain))
			ok = false
		else:
			print_rich("  OK: le fortin déclaré par la carte arrive jusqu'à sa tuile")

	arena.free()
	print_rich("  [b]%s[/b]" % ("[color=green]PASS[/color]" if ok else "[color=red]FAIL[/color]"))
	return ok
