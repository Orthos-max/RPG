class_name UnitDocument
extends RefCounted
## Un personnage écrit par le joueur — la donnée, et rien d'autre.
##
## Les unités du jeu sont des `.tres` versionnés avec le code : parfaits pour du
## contenu livré, inutilisables pour du contenu créé après l'installation. Une
## fois le jeu installé, `res://` est en lecture seule ; un personnage enregistré
## là serait perdu, ou impossible à écrire.
##
## Cette classe est donc à [StatsResource] ce que [MapDocument] est à une carte :
## une description en mémoire, validable, sérialisable en JSON lisible, que
## [UnitLibrary] range dans `user://units/`.
##
## Aucun nœud, aucune scène : tout est éprouvable en headless.

const CDB = preload("res://data/models/world/stats/class_data.gd")
const WEAPONS = preload("res://data/models/world/stats/weapon_db.gd")
const ITEMS = preload("res://data/models/world/stats/item_db.gd")

## Bornes des statistiques, pour qu'une fiche reste jouable.
const MIN_STAT: int = 0
const MAX_STAT: int = 60
const MIN_HP: int = 1
const MAX_HP: int = 99
const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 20
const MAX_MOVEMENT: int = 12
const MAX_NAME: int = 24

## Statistiques de combat, dans l'ordre où l'éditeur les présente.
const STATS: Array[String] = ["str", "mag", "skl", "spd", "lck", "def", "res"]

var name: String = "Nouvelle recrue"
var class_id: int = CDB.Id.LORD
var level: int = 1
var max_hp: int = 20
var movement: int = 5
## Statistiques de combat : "str", "mag", "skl", "spd", "lck", "def", "res"
var stats: Dictionary = {}
## Croissances personnalisées (0-100). Vides : celles de la classe font foi.
var growths: Dictionary = {}
## Armes portées (identifiants de [WeaponDB]), la première étant en main.
var weapons: Array[String] = []
## Consommables de départ (noms connus d'[ItemDB]).
var items: Array[String] = []
## Figurine portée sur le plateau. Vide : celle de la classe fait foi.
##
## Une fiche écrite à la main n'avait aucune apparence : elle empruntait celle du
## pion qu'elle remplaçait, et deux créations se ressemblaient forcément.
var sprite: String = ""


## Dossiers où l'on va chercher les figurines disponibles.
const SPRITE_DIRS: Array[String] = [
	"res://assets/textures/actor/character",
	"res://assets/textures/actor/mob",
]


## Toutes les figurines livrées avec le jeu : `[{path, label}]`.
##
## Lues sur le disque, comme le roster de l'éditeur de cartes : déposer une
## planche suffit à la rendre choisissable, sans toucher au code. Ce que
## `assets/textures/actor/README.md` promet à qui en fournira.
static func available_sprites() -> Array:
	var out: Array = []
	for folder: String in SPRITE_DIRS:
		var dir := DirAccess.open(folder)
		if not dir:
			continue
		var files: PackedStringArray = dir.get_files()
		files.sort()
		for file_name: String in files:
			# Une planche exportée est livrée en `.import` / `.remap` : c'est le nom
			# d'origine qu'il faut, sinon la liste est vide dans le jeu installé.
			var clean: String = file_name.trim_suffix(".remap").trim_suffix(".import")
			if not clean.ends_with(".png") or _has(out, "%s/%s" % [folder, clean]):
				continue
			out.append({
				"path": "%s/%s" % [folder, clean],
				"label": clean.trim_prefix("chr_pawn_").trim_suffix(".png").capitalize(),
			})
	return out


static func _has(entries: Array, path: String) -> bool:
	for e: Dictionary in entries:
		if str(e["path"]) == path:
			return true
	return false


## Figurine réellement portée : celle choisie, sinon celle de la classe.
func effective_sprite() -> String:
	if not sprite.is_empty() and ResourceLoader.exists(sprite):
		return sprite
	return CDB.get_sprite(class_id)


## Fiche neuve, calquée sur les bases de sa classe.
##
## Partir des bases de la classe plutôt que de zéros : un personnage créé sans
## rien toucher doit déjà être jouable, pas être une coquille à 0 partout.
static func from_class(id: int) -> UnitDocument:
	var doc := UnitDocument.new()
	doc.class_id = id
	doc.apply_class_bases()
	return doc


## Recopie les statistiques de base de la classe (sans toucher au nom).
func apply_class_bases() -> void:
	var base: Dictionary = CDB.get_base_stats(class_id)
	max_hp = int(base.get("hp", 20))
	movement = int(base.get("mov", 5))
	stats = {}
	for key: String in STATS:
		stats[key] = int(base.get(key, 0))

	# Une arme cohérente avec la classe, pour que la fiche parte armée.
	weapons = []
	var allowed: Array = CDB.get_weapons(class_id)
	for id: String in WEAPONS.all_weapons():
		if WEAPONS.weapon_type(id) in allowed:
			weapons.append(id)
			break


## Ce qui empêche cette fiche d'entrer en jeu. Tableau vide : elle est bonne.
##
## On valide plutôt que de corriger en silence : un personnage à 300 de force
## est probablement une faute de frappe, et le dire vaut mieux que de la ramener
## discrètement à 60.
func validate() -> Array[String]:
	var errors: Array[String] = []

	if name.strip_edges().is_empty():
		errors.append("le personnage n'a pas de nom")
	elif name.length() > MAX_NAME:
		errors.append("le nom dépasse %d caractères" % MAX_NAME)

	if CDB.get_class_name(class_id) == "Unknown":
		errors.append("classe inconnue (%d)" % class_id)

	if level < MIN_LEVEL or level > MAX_LEVEL:
		errors.append("le niveau doit tenir entre %d et %d" % [MIN_LEVEL, MAX_LEVEL])
	if max_hp < MIN_HP or max_hp > MAX_HP:
		errors.append("les PV doivent tenir entre %d et %d" % [MIN_HP, MAX_HP])
	if movement < 1 or movement > MAX_MOVEMENT:
		errors.append("le mouvement doit tenir entre 1 et %d" % MAX_MOVEMENT)

	for key: String in STATS:
		var value: int = int(stats.get(key, 0))
		if value < MIN_STAT or value > MAX_STAT:
			errors.append("%s hors bornes (%d–%d)" % [key.to_upper(), MIN_STAT, MAX_STAT])

	for key: String in growths:
		var g: int = int(growths[key])
		if g < 0 or g > 100:
			errors.append("croissance %s hors bornes (0–100)" % str(key).to_upper())

	if weapons.size() > WEAPONS.MAX_WEAPONS:
		errors.append("pas plus de %d armes" % WEAPONS.MAX_WEAPONS)
	for id: String in weapons:
		if not WEAPONS.exists(id):
			errors.append("arme inconnue : %s" % id)
		elif not CDB.can_use_weapon(class_id, WEAPONS.weapon_type(id)):
			errors.append("%s ne sait pas manier %s" % [
				CDB.get_class_name(class_id), WEAPONS.label(id)])

	if items.size() > ITEMS.MAX_ITEMS:
		errors.append("pas plus de %d objets" % ITEMS.MAX_ITEMS)
	for item: String in items:
		if not ITEMS.exists(item):
			errors.append("objet inconnu : %s" % item)

	return errors


## Identifiant de fichier et de roster, dérivé du nom.
func slug() -> String:
	var out: String = ""
	for c: String in name.strip_edges().to_lower():
		out += c if c.is_valid_identifier() or c.is_valid_int() else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "recrue"


#region Sérialisation
func to_dict() -> Dictionary:
	return {
		"version": 1,
		"name": name,
		"class_id": class_id,
		"level": level,
		"max_hp": max_hp,
		"movement": movement,
		"stats": stats.duplicate(),
		"growths": growths.duplicate(),
		"weapons": weapons.duplicate(),
		"items": items.duplicate(),
		"sprite": sprite,
	}


static func from_dict(data: Dictionary) -> UnitDocument:
	var doc := UnitDocument.new()
	doc.name = str(data.get("name", "Recrue"))
	doc.sprite = str(data.get("sprite", ""))
	doc.class_id = int(data.get("class_id", CDB.Id.LORD))
	doc.level = int(data.get("level", 1))
	doc.max_hp = int(data.get("max_hp", 20))
	doc.movement = int(data.get("movement", 5))

	doc.stats = {}
	var raw_stats: Variant = data.get("stats", {})
	if raw_stats is Dictionary:
		for key: String in STATS:
			doc.stats[key] = int(raw_stats.get(key, 0))

	doc.growths = {}
	var raw_growths: Variant = data.get("growths", {})
	if raw_growths is Dictionary:
		for key in raw_growths:
			doc.growths[str(key)] = int(raw_growths[key])

	# Armes et objets inconnus sont écartés plutôt que de faire échouer la
	# lecture : un fichier écrit par une version plus riche reste utilisable.
	doc.weapons = []
	for w in data.get("weapons", []):
		var key: String = WEAPONS.canonical_id(str(w))
		if not key.is_empty() and not key in doc.weapons:
			doc.weapons.append(key)

	doc.items = []
	for i in data.get("items", []):
		var item: String = ITEMS.canonical_name(str(i))
		if not item.is_empty():
			doc.items.append(item)

	return doc
#endregion


#region Passerelle vers le jeu
## Entrée de roster, au format qu'attend [Campaign].
##
## C'est le seul point de contact entre un personnage écrit à la main et la
## campagne : il en ressort une unité comme les autres, avec son arsenal et ses
## objets. Le champ `source` reste vide — cette fiche ne vient d'aucun `.tres`.
func to_roster_unit() -> Dictionary:
	var unit: Dictionary = {
		"id": slug(),
		"name": name.strip_edges(),
		"source": "",
		"custom": true,
		"class_id": class_id,
		"level": level,
		"exp": 0,
		"max_hp": max_hp,
		"hp": max_hp,
		"movement": movement,
		"attack_range": 1,
		"is_promoted": CDB.is_promoted(class_id),
		"alive": true,
		"items": items.duplicate(),
		"weapons": weapons.duplicate(),
		"weapon": weapons[0] if not weapons.is_empty() else "",
		"uses_arsenal": not weapons.is_empty(),
		"sprite": effective_sprite(),
	}
	for key: String in STATS:
		unit[key] = int(stats.get(key, 0))

	# Portée et type d'arme suivent l'arme en main : sans cela, une unité créée
	# avec un arc partirait au combat à portée 1.
	if not weapons.is_empty():
		var w: Dictionary = WEAPONS.get_weapon(weapons[0])
		unit["attack_range"] = int(w.get("range", 1))
		unit["weapon_type"] = int(w.get("type", 0))
		unit["weapon_might"] = int(w.get("might", 0))
	return unit


## Croissances effectives : les personnalisées, complétées par celles de la classe.
func effective_growths() -> Dictionary:
	var out: Dictionary = CDB.get_growths(class_id).duplicate()
	for key in growths:
		out[str(key)] = int(growths[key])
	return out
#endregion
