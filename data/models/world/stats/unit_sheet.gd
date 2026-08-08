class_name UnitSheet
extends RefCounted
## Fiche d'unité — ce que le joueur lit en survolant un pion.
##
## Même parti pris que [BattleForecast] : la mise en forme est une logique pure,
## sans le moindre nœud, donc vérifiable en headless. Le panneau d'affichage ne
## fait ensuite que recopier des chaînes déjà écrites.
##
## Les chiffres exposés sont ceux qui décident d'un combat — précision, esquive,
## critique, vitesse d'attaque — et non les seules stats brutes : c'est la
## différence entre une fiche décorative et une fiche qui aide à jouer.

const WT = preload("res://data/models/world/stats/weapon_type.gd")
const WEAPONS = preload("res://data/models/world/stats/weapon_db.gd")
const CD = preload("res://data/models/world/stats/class_data.gd")
const SkillDBRef = preload("res://data/models/world/stats/skill_db.gd")


const MapDataRef = preload("res://data/models/world/map/map_data.gd")


## Construit la fiche d'une unité.
##
## [param opts] {"terrain": String, "terrain_def": int, "team": String}
## [returns] {
##   name, title, hp, max_hp, hp_ratio, level, class_name, promoted,
##   stats: [{label, value}], combat: [{label, value}],
##   weapon, movement, range, terrain, skills: [String], items: [String]
## }
static func build(stats: Stats, opts: Dictionary = {}) -> Dictionary:
	if not stats:
		return {}

	var unit_name: String = stats.override_name if not stats.override_name.is_empty() \
		else stats.expertise
	var class_label: String = CD.get_class_name(stats.character_class)
	var terrain_def: int = int(opts.get("terrain_def", 0))

	return {
		"name": unit_name,
		"title": "%s — %s  Niv. %d" % [unit_name, class_label, stats.level],
		"team": str(opts.get("team", "")),
		"hp": stats.hp,
		"max_hp": stats.max_hp,
		"hp_ratio": float(stats.hp) / float(maxi(1, stats.max_hp)),
		"level": stats.level,
		"class_name": class_label,
		"promoted": stats.is_promoted,
		"stats": [
			{"label": "FOR", "value": stats.str},
			{"label": "MAG", "value": stats.mag},
			{"label": "HAB", "value": stats.skl},
			{"label": "VIT", "value": stats.spd},
			{"label": "CHA", "value": stats.lck},
			{"label": "DÉF", "value": stats.def + terrain_def},
			{"label": "RÉS", "value": stats.res},
		],
		"combat": [
			{"label": "Att", "value": stats.get_total_attack()},
			{"label": "Préc", "value": stats.get_base_hit()},
			{"label": "Esq", "value": stats.get_avoid()},
			{"label": "Crit", "value": stats.get_crit()},
			{"label": "VitAtt", "value": stats.get_attack_speed()},
		],
		"weapon": _weapon_label(stats),
		"weapon_might": stats.weapon_might,
		"movement": stats.movement,
		"range": stats.attack_range,
		"terrain": str(opts.get("terrain", "")),
		"terrain_def": terrain_def,
		"skills": _skill_names(stats),
		"items": _item_names(stats),
	}


## Nom de l'arme montrée sur la fiche : celle qui est réellement en main quand
## l'unité en porte une, sinon le type d'arme brut de sa fiche.
static func _weapon_label(stats: Stats) -> String:
	var equipped: Variant = stats.get("equipped_weapon")
	if equipped is String and not str(equipped).is_empty():
		return WEAPONS.label(str(equipped))
	return WT.get_weapon_label(stats.weapon_type)


## Nom lisible d'un terrain, depuis la clé technique de [TacticsGrid].
##
## Les noms vivent avec les terrains, dans [MapData] : une case de village
## ajoutée là s'affiche ici sans qu'on y revienne.
static func terrain_label(key: String) -> String:
	return MapDataRef.label_for_key(key)


## Ligne des stats principales, séparées par des espaces.
static func stats_line(sheet: Dictionary) -> String:
	return _join_pairs(sheet.get("stats", []))


## Ligne des valeurs de combat dérivées.
static func combat_line(sheet: Dictionary) -> String:
	return _join_pairs(sheet.get("combat", []))


## Ligne de contexte : arme, mouvement, portée, terrain occupé.
static func context_line(sheet: Dictionary) -> String:
	if sheet.is_empty():
		return ""
	var parts: Array[String] = [
		"%s (%d)" % [sheet["weapon"], sheet["weapon_might"]],
		"Mvt %d" % sheet["movement"],
		"Portée %d" % sheet["range"],
	]
	if not str(sheet["terrain"]).is_empty():
		var terrain: String = str(sheet["terrain"])
		if int(sheet["terrain_def"]) > 0:
			terrain += " 🛡+%d" % int(sheet["terrain_def"])
		parts.append(terrain)
	return "     ".join(parts)


## Ligne des compétences ("" si l'unité n'en a aucune).
static func skills_line(sheet: Dictionary) -> String:
	var skills: Array = sheet.get("skills", [])
	return "✨ " + "  ·  ".join(skills) if not skills.is_empty() else ""


#region Internes
static func _join_pairs(pairs: Array) -> String:
	var parts: Array[String] = []
	for p: Dictionary in pairs:
		parts.append("%s %d" % [p["label"], p["value"]])
	return "   ".join(parts)


static func _skill_names(stats: Stats) -> Array[String]:
	var out: Array[String] = []
	for skill_id: String in stats.get_skills():
		var label: String = SkillDBRef.get_skill_name(skill_id)
		out.append(label if not label.is_empty() else skill_id)
	return out


static func _item_names(stats: Stats) -> Array[String]:
	var out: Array[String] = []
	for item: Variant in stats.items:
		out.append(str(item))
	return out
#endregion
