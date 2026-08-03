extends Node
## Campaign (autoload) — roster persistant, progression et sauvegarde solo.
##
## Le roster survit d'un chapitre à l'autre : stats, XP, niveau, morts permanentes.
## La sauvegarde est un JSON lisible dans `user://saves/`, pour rester debuggable
## (et inspectable par Ciel, comme le reste du projet).

const CampaignDBClass = preload("res://data/models/campaign/campaign_db.gd")
const ChapterDataClass = preload("res://data/models/campaign/chapter_data.gd")
const DIFF = preload("res://data/models/world/ai/difficulty.gd")
const ClassDataDBClass = preload("res://data/models/world/stats/class_data.gd")

signal roster_changed()
signal chapter_completed(chapter_id: String, bonuses: Array)

const SAVE_DIR: String = "user://saves"
const SAVE_VERSION: int = 1

## Roster complet du joueur (unités recrutées, vivantes ou tombées)
var roster: Array = []
## Index du chapitre courant
var chapter_index: int = 0
## Or disponible pour la boutique / le recrutement
var gold: int = 0
## Difficulté choisie à la création de la partie
var difficulty: int = DIFF.Level.NORMAL
## Mort permanente (façon Fire Emblem classique)
var permadeath: bool = true
## Identifiants des unités sélectionnées pour la mission
var deployment: Array = []
## Objectifs secondaires réussis, par chapitre
var bonus_history: Dictionary = {}
## Nombre de tours du chapitre en cours
var turn_count: int = 1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


#region Cycle de vie d'une partie
## Démarre une nouvelle campagne avec le roster de départ.
func new_game(diff: int = DIFF.Level.NORMAL, with_permadeath: bool = true) -> void:
	roster.clear()
	for path: String in CampaignDBClass.STARTING_ROSTER:
		var unit: Dictionary = unit_from_resource(path)
		if not unit.is_empty():
			roster.append(unit)
	chapter_index = 0
	gold = 0
	difficulty = diff
	permadeath = with_permadeath
	deployment = _default_deployment()
	bonus_history.clear()
	turn_count = 1
	roster_changed.emit()


## Chapitre courant (null si la campagne est terminée)
func current_chapter() -> ChapterData:
	return CampaignDBClass.get_chapter(chapter_index)


## La campagne est-elle terminée ?
func is_finished() -> bool:
	return chapter_index >= CampaignDBClass.count()


## Enregistre le résultat d'un chapitre gagné puis avance.
## [param bonuses] Résultat de [method ObjectiveDB.evaluate_bonuses]
func complete_chapter(bonuses: Array = []) -> void:
	var chapter: ChapterData = current_chapter()
	if not chapter:
		return
	gold += chapter.reward_gold
	bonus_history[chapter.id] = bonuses
	for b: Dictionary in bonuses:
		if bool(b.get("achieved", false)):
			gold += 100
	for path: String in chapter.recruits:
		recruit(path)
	chapter_completed.emit(chapter.id, bonuses)
	chapter_index += 1
	turn_count = 1
	deployment = _default_deployment()
#endregion


#region Roster
## Convertit un StatsResource (.tres) en entrée de roster.
func unit_from_resource(path: String) -> Dictionary:
	var res: Resource = load(path)
	if not res:
		push_warning("[Campaign] Ressource d'unité introuvable : %s" % path)
		return {}
	var unit_name: String = res.override_name if res.override_name != "" else res.expertise
	return {
		"id": unit_name.to_lower().replace(" ", "_"),
		"name": unit_name,
		"source": path,
		"class_id": res.character_class,
		"level": res.level,
		"exp": res.exp,
		"max_hp": res.hp,
		"hp": res.hp,
		"str": res.str, "mag": res.mag, "skl": res.skl, "spd": res.spd,
		"lck": res.lck, "def": res.def, "res": res.res,
		"movement": res.movement,
		"attack_range": res.attack_range,
		"weapon_type": res.weapon_type,
		"weapon_might": res.weapon_might,
		"is_promoted": res.is_promoted,
		"alive": true,
		"items": [],
	}


## Ajoute une unité au roster (ignorée si déjà présente).
func recruit(path: String) -> bool:
	var unit: Dictionary = unit_from_resource(path)
	if unit.is_empty():
		return false
	for u: Dictionary in roster:
		if str(u.get("id", "")) == str(unit["id"]):
			return false
	roster.append(unit)
	roster_changed.emit()
	return true


## Unités encore disponibles pour le déploiement.
func available_units() -> Array:
	var units: Array = []
	for u: Dictionary in roster:
		if bool(u.get("alive", true)):
			units.append(u)
	return units


## Unité du roster par identifiant (dictionnaire vide si absente).
func get_unit(id: String) -> Dictionary:
	for u: Dictionary in roster:
		if str(u.get("id", "")) == id:
			return u
	return {}


## Définit les unités déployées, dans la limite des places du chapitre.
func set_deployment(ids: Array) -> void:
	var chapter: ChapterData = current_chapter()
	var slots: int = chapter.deploy_slots if chapter else 3
	deployment = []
	for id in ids:
		if deployment.size() >= slots:
			break
		if not get_unit(str(id)).is_empty():
			deployment.append(str(id))


## Reporte l'état d'une unité après une bataille (PV, XP, niveau, mort).
## [param snapshot] {id|name, hp, exp, level, is_promoted, class_id, stats…}
func apply_battle_result(snapshot: Dictionary) -> void:
	var id: String = str(snapshot.get("id", str(snapshot.get("name", "")).to_lower().replace(" ", "_")))
	for u: Dictionary in roster:
		if str(u.get("id", "")) != id:
			continue
		var hp: int = int(snapshot.get("hp", u.get("hp", 1)))
		u["exp"] = int(snapshot.get("exp", u.get("exp", 0)))
		u["level"] = int(snapshot.get("level", u.get("level", 1)))
		u["is_promoted"] = bool(snapshot.get("is_promoted", u.get("is_promoted", false)))
		u["class_id"] = int(snapshot.get("class_id", u.get("class_id", 0)))
		for stat in ["max_hp", "str", "mag", "skl", "spd", "lck", "def", "res", "movement"]:
			if snapshot.has(stat):
				u[stat] = int(snapshot[stat])
		if hp <= 0:
			if permadeath:
				u["alive"] = false
				u["hp"] = 0
			else:
				# Sans mort permanente : l'unité se relève avec 1 PV entre deux chapitres.
				u["hp"] = 1
		else:
			# On repart au maximum au chapitre suivant (soins de garnison).
			u["hp"] = int(u.get("max_hp", hp))
		roster_changed.emit()
		return


## Classe lisible d'une unité du roster.
func unit_class_name(unit: Dictionary) -> String:
	return ClassDataDBClass.get_class_name(int(unit.get("class_id", 0)))
#endregion


#region Sauvegarde
func save_path(slot: int = 0) -> String:
	return "%s/campaign_slot%d.json" % [SAVE_DIR, slot]


## Une sauvegarde existe-t-elle dans ce slot ?
func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(save_path(slot))


## Écrit la partie sur disque. Renvoie false en cas d'échec d'écriture.
func save_game(slot: int = 0) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"chapter_index": chapter_index,
		"gold": gold,
		"difficulty": difficulty,
		"permadeath": permadeath,
		"deployment": deployment,
		"bonus_history": bonus_history,
		"roster": roster,
	}
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if not f:
		push_error("[Campaign] Sauvegarde impossible : %s" % save_path(slot))
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return true


## Recharge une partie. Renvoie false si le fichier est absent ou corrompu.
func load_game(slot: int = 0) -> bool:
	if not has_save(slot):
		return false
	var f := FileAccess.open(save_path(slot), FileAccess.READ)
	if not f:
		return false
	var raw: String = f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(raw) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("[Campaign] Sauvegarde corrompue : %s" % save_path(slot))
		return false

	var data: Dictionary = json.data
	if int(data.get("version", 0)) > SAVE_VERSION:
		push_warning("[Campaign] Sauvegarde plus récente que le jeu — chargement partiel.")

	chapter_index = int(data.get("chapter_index", 0))
	gold = int(data.get("gold", 0))
	difficulty = int(data.get("difficulty", DIFF.Level.NORMAL))
	permadeath = bool(data.get("permadeath", true))
	deployment = data.get("deployment", [])
	bonus_history = data.get("bonus_history", {})
	turn_count = 1

	roster = []
	for u in data.get("roster", []):
		if typeof(u) == TYPE_DICTIONARY:
			roster.append(_normalize_unit(u))

	roster_changed.emit()
	return true


## Supprime une sauvegarde.
func delete_save(slot: int = 0) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path(slot)))
#endregion


#region Internes
## Le JSON ne connaît que les floats : on remet les entiers d'aplomb au chargement.
func _normalize_unit(raw: Dictionary) -> Dictionary:
	var u: Dictionary = raw.duplicate(true)
	for key in ["class_id", "level", "exp", "max_hp", "hp", "str", "mag", "skl",
			"spd", "lck", "def", "res", "movement", "attack_range",
			"weapon_type", "weapon_might"]:
		if u.has(key):
			u[key] = int(u[key])
	u["alive"] = bool(u.get("alive", true))
	u["is_promoted"] = bool(u.get("is_promoted", false))
	return u


func _default_deployment() -> Array:
	var chapter: ChapterData = current_chapter()
	var slots: int = chapter.deploy_slots if chapter else 3
	var ids: Array = []
	for u: Dictionary in available_units():
		if ids.size() >= slots:
			break
		ids.append(str(u.get("id", "")))
	return ids
#endregion
