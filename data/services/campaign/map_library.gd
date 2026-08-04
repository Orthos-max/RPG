class_name MapLibrary
extends RefCounted
## Les cartes créées par le joueur, sur son disque.
##
## Elles vivent dans `user://maps/` et non dans `res://` : le contenu du jeu est
## en lecture seule une fois installé, une carte enregistrée là serait perdue —
## ou impossible à écrire. `user://` survit aux mises à jour et se partage
## facilement (un simple fichier JSON qu'on envoie à un ami).
##
## Format JSON lisible, comme les sauvegardes et les replays du projet : on peut
## ouvrir une carte dans un éditeur de texte, la corriger, la relire.

const DIR: String = "user://maps"
const EXTENSION: String = ".json"


## Chemin complet d'une carte à partir de son identifiant de fichier.
static func path_for(slug: String) -> String:
	return "%s/%s%s" % [DIR, slug, EXTENSION]


## Enregistre une carte. [returns] {ok, path, error}
##
## Une carte injouable est refusée : mieux vaut le dire à la création qu'au
## moment où quelqu'un essaie d'y jouer.
static func save(doc: MapDocument, overwrite: bool = true) -> Dictionary:
	if not doc:
		return {"ok": false, "path": "", "error": "aucune carte à enregistrer"}

	var errors: Array[String] = doc.validate()
	if not errors.is_empty():
		return {"ok": false, "path": "", "error": errors[0]}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path: String = path_for(doc.slug())
	if not overwrite and FileAccess.file_exists(path):
		return {"ok": false, "path": path, "error": "une carte porte déjà ce nom"}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return {"ok": false, "path": path, "error": "écriture impossible dans %s" % DIR}
	f.store_string(JSON.stringify(doc.to_dict(), "\t"))
	f.close()
	return {"ok": true, "path": path, "error": ""}


## Relit une carte (null si le fichier est absent, illisible ou trop récent).
static func load_map(path: String) -> MapDocument:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_warning("[MapLibrary] Carte illisible : %s" % path)
		return null
	return MapDocument.from_dict(parsed)


## Cartes disponibles, la plus récente d'abord.
## [returns] [{name, slug, path, units, grid, playable}]
static func list_maps() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if not dir:
		return out

	for file: String in dir.get_files():
		if not file.ends_with(EXTENSION):
			continue
		var path: String = "%s/%s" % [DIR, file]
		var doc: MapDocument = load_map(path)
		if not doc:
			continue
		out.append({
			"name": doc.name,
			"slug": file.trim_suffix(EXTENSION),
			"path": path,
			"units": doc.units.size(),
			"grid": doc.grid_size,
			"playable": doc.validate().is_empty(),
			"modified": FileAccess.get_modified_time(path),
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["modified"]) > int(b["modified"]))
	return out


## Supprime une carte.
static func delete(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


## Y a-t-il au moins une carte enregistrée ?
static func has_maps() -> bool:
	return not list_maps().is_empty()
