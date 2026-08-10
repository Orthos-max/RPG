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
	if md.is_walkable(TERRAIN.MOUNTAIN):     ok = false; print_rich("[color=red]  FAIL: MOUNTAIN should be blocked[/color]")
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
		_MD.TerrainType.MOUNTAIN: "Montagne · infranchissable · 🛡 +3 DÉF",
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
		"trunk": 1, "canopy": 1, "rock": 2, "merlon": 1,
		"house_wall": 1, "house_roof": 1, "keep": 1,
		"pier": 2, "column": 2, "rubble": 1,
		"tower_shaft": 1, "tower_roof": 1,
		"deck": 1, "railing": 2,
		"reed": 3,
	}
	# Herbe, sable et bannières ne se posent qu'une case sur deux ou trois : la
	# case unique de ce test tombe d'un côté ou de l'autre du tirage, on ne fixe
	# donc pas leur compte. Une hampe sans fanion, en revanche, serait un bug.
	for optional: String in ["tuft", "pebble", "pole", "banner"]:
		counts.erase(optional)
	if batches.get("pole", []).size() != batches.get("banner", []).size():
		print_rich("[color=red]  FAIL: %d hampe(s) pour %d bannière(s)[/color]" % [
			batches.get("pole", []).size(), batches.get("banner", []).size()])
		ok = false
	if counts != expected:
		print_rich("[color=red]  FAIL: garniture %s\n           attendu %s[/color]" % [
			str(counts), str(expected)])
		ok = false
	else:
		print_rich("  OK: seize terrains, chacun sa garniture (village → maison, "
			+ "fortin → donjon et bannière, tour → fût et toit, pont → platelage…)")
		print_rich("  OK: eau, chemin, fosse et neige restent nus")

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

	ok = _check_centres_clear(cells, batches, tile_size) and ok

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
func _check_centres_clear(cells: Array, batches: Dictionary, tile_size: float) -> bool:
	# Tronc et frondaison cuisent leur rayon dans le maillage ; tout le reste
	# suit la convention « maillage unitaire, mis à l'échelle par l'instance ».
	var local_half := {"trunk": 0.06, "canopy": 0.22}

	var terrain_by_index := {}
	for entry in cells:
		terrain_by_index[int(round(entry["top"].x / tile_size))] = int(entry["terrain"])

	var offenders: Array[String] = []
	var margin := 99.0
	for kind: String in batches:
		var half: float = float(local_half.get(kind, 0.5))
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

	return ok


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
