class_name UnitLibrary
extends RefCounted
## Les personnages créés par le joueur, sur son disque.
##
## Même parti pris que [MapLibrary], pour la même raison : `res://` est en
## lecture seule une fois le jeu installé, donc un personnage enregistré là
## serait perdu — ou impossible à écrire. `user://units/` survit aux mises à
## jour, et un personnage y est un simple fichier JSON qu'on peut lire, corriger
## à la main, ou envoyer à quelqu'un.

const DIR: String = "user://units"
const EXTENSION: String = ".json"


## Chemin complet d'un personnage à partir de son identifiant de fichier.
static func path_for(slug: String) -> String:
	return "%s/%s%s" % [DIR, slug, EXTENSION]


## Enregistre un personnage. [returns] {ok, path, error}
##
## Une fiche invalide est refusée : mieux vaut le dire à l'écriture qu'au moment
## où le personnage entre en bataille.
static func save(doc: UnitDocument, overwrite: bool = true) -> Dictionary:
	if not doc:
		return {"ok": false, "path": "", "error": "aucun personnage à enregistrer"}

	var errors: Array[String] = doc.validate()
	if not errors.is_empty():
		return {"ok": false, "path": "", "error": errors[0]}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path: String = path_for(doc.slug())
	if not overwrite and FileAccess.file_exists(path):
		return {"ok": false, "path": path, "error": "un personnage porte déjà ce nom"}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return {"ok": false, "path": path, "error": "écriture impossible : %s" % path}
	f.store_string(JSON.stringify(doc.to_dict(), "\t"))
	f.close()
	return {"ok": true, "path": path, "error": ""}


## Relit un personnage. `null` si le fichier est absent ou illisible.
static func load_unit(slug: String) -> UnitDocument:
	var path: String = path_for(slug)
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return null
	var raw: String = f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(raw) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("[UnitLibrary] Fiche illisible : %s" % path)
		return null
	return UnitDocument.from_dict(json.data)


## Tous les personnages enregistrés : [{slug, name, class_name, level}].
##
## On lit chaque fiche pour la décrire, mais on ne rend que de quoi remplir une
## ligne de liste — l'écran n'a pas besoin de plus, et une fiche corrompue ne
## doit pas empêcher les autres de s'afficher.
static func list_units() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if not dir:
		return out

	const CDB = preload("res://data/models/world/stats/class_data.gd")
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(EXTENSION):
			continue
		var slug: String = file_name.trim_suffix(EXTENSION)
		var doc: UnitDocument = load_unit(slug)
		if not doc:
			continue
		out.append({
			"slug": slug,
			"name": doc.name,
			"class_name": CDB.get_class_name(doc.class_id),
			"level": doc.level,
			"valid": doc.validate().is_empty(),
		})
	return out


## Supprime un personnage.
static func delete_unit(slug: String) -> bool:
	var path: String = path_for(slug)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
