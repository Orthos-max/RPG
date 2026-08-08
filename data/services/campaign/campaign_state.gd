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
const ITEMS = preload("res://data/models/world/stats/item_db.gd")
const WEAPONS = preload("res://data/models/world/stats/weapon_db.gd")
const SKILLS = preload("res://data/models/world/stats/skill_db.gd")

signal roster_changed()
signal chapter_completed(chapter_id: String, bonuses: Array)

const SAVE_DIR: String = "user://saves"
const SAVE_VERSION: int = 1
## Emplacements de sauvegarde proposés au joueur.
##
## Le slot 0 est celui que le jeu écrit tout seul (nouvelle partie, fin de
## chapitre) et que « Continuer » relit ; les suivants n'appartiennent qu'au
## joueur, qui y sauvegarde et recharge à la main.
const SAVE_SLOTS: int = 4
## Emplacement écrit automatiquement par la campagne.
const AUTO_SLOT: int = 0

## Prix d'un personnage écrit par le joueur, à l'intendance.
##
## **Gratuit pour l'instant** (choix d'Aurèle, 2026-08-07) : on veut d'abord
## pouvoir jouer ses créations. Le chemin de paiement est en place —
## [method hire_custom] vérifie l'or et le déduit — donc lui donner un prix un
## jour ne demandera que de changer ce chiffre.
const CUSTOM_RECRUIT_COST: int = 0

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
## Case de départ choisie par unité : id → Vector2i.
##
## Choisir sa case, c'est choisir son terrain — donc le bonus défensif que le
## calculateur applique déjà de bout en bout. Ce plan est établi à l'écran de
## préparation, avant tout chargement de niveau, et [ChapterRunner] le pose sur
## les pions au démarrage.
var deployment_tiles: Dictionary = {}
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
	deployment_tiles.clear()
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
	# Les cases appartenaient à la carte précédente : elles ne veulent plus rien
	# dire sur la suivante.
	deployment_tiles.clear()
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
		# L'apparence voyage avec l'unité. Sans elle, une recrue déployée prenait
		# la figurine du pion de la scène qu'elle occupait : Sully et Cordelia
		# entraient en bataille sous les traits de quelqu'un d'autre.
		"sprite": str(res.sprite),
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
		"weapons": _weapons_of(res),
		"weapon": _equipped_of(res),
		# Cette unité est-elle gérée par le catalogue d'armes ? Sans ce marqueur,
		# un fourreau vide serait indistinguable d'une fiche d'avant le catalogue,
		# et revendre ses armes ne coûterait rien : le pion repartirait au combat
		# avec l'arme écrite dans son `.tres`.
		"uses_arsenal": not _weapons_of(res).is_empty(),
	}


## Armes déclarées par une fiche, filtrées sur celles que le catalogue connaît.
func _weapons_of(res: Resource) -> Array:
	var out: Array = []
	var declared: Variant = res.get("weapons")
	if declared is Array:
		for w in declared:
			var key: String = WEAPONS.canonical_id(str(w))
			if not key.is_empty() and not key in out and out.size() < WEAPONS.MAX_WEAPONS:
				out.append(key)
	return out


## Arme en main déclarée par une fiche ("" si aucune, ou si elle n'est pas portée).
func _equipped_of(res: Resource) -> String:
	var declared: Variant = res.get("equipped_weapon")
	if not declared is String:
		return ""
	var key: String = WEAPONS.canonical_id(str(declared))
	return key if key in _weapons_of(res) else ""


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


## Unités que le chapitre courant impose au déploiement.
##
## Filtrées sur celles encore vivantes : une protégée déjà tombée en mort
## permanente ne peut plus être exigée, sinon le chapitre serait injouable.
func required_deployment() -> Array:
	var chapter: ChapterData = current_chapter()
	if not chapter:
		return []
	var out: Array = []
	for id: String in chapter.required_units:
		var unit: Dictionary = get_unit(id)
		if not unit.is_empty() and bool(unit.get("alive", true)):
			out.append(id)
	return out


## Définit les unités déployées, dans la limite des places du chapitre.
##
## Les unités imposées par le chapitre passent d'abord et ne peuvent pas être
## écartées : c'est ce qui rend un objectif « protéger » tenable.
func set_deployment(ids: Array) -> void:
	var chapter: ChapterData = current_chapter()
	var slots: int = chapter.deploy_slots if chapter else 3
	deployment = []

	for id: String in required_deployment():
		if deployment.size() >= slots:
			break
		deployment.append(id)

	for id in ids:
		if deployment.size() >= slots:
			break
		if str(id) in deployment:
			continue
		if not get_unit(str(id)).is_empty():
			deployment.append(str(id))

	# Une unité écartée du déploiement n'a plus de case : la garder ferait
	# réapparaître son pion à un endroit choisi pour une bataille qu'elle ne fera pas.
	for id in deployment_tiles.keys():
		if not id in deployment:
			deployment_tiles.erase(id)


## Fixe la case de départ d'une unité. Une case déjà prise fait échanger les deux
## unités — c'est la règle de [DeploymentPlan], et le geste attendu quand on
## réarrange une ligne de départ.
func set_deployment_tile(unit_id: String, pos: Vector2i) -> void:
	for other: String in deployment_tiles.keys():
		if other != unit_id and deployment_tiles[other] == pos:
			var previous: Variant = deployment_tiles.get(unit_id)
			if previous == null:
				deployment_tiles.erase(other)
			else:
				deployment_tiles[other] = previous
			break
	deployment_tiles[unit_id] = pos


## Case de départ d'une unité — (-1, -1) si elle n'en a pas choisi.
func deployment_tile(unit_id: String) -> Vector2i:
	return deployment_tiles.get(unit_id, Vector2i(-1, -1))


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
			# Les blessures persistent : les soigner coûte de l'or à l'intendance.
			u["hp"] = clampi(hp, 1, int(u.get("max_hp", hp)))
		roster_changed.emit()
		return


## Classe lisible d'une unité du roster.
func unit_class_name(unit: Dictionary) -> String:
	return ClassDataDBClass.get_class_name(int(unit.get("class_id", 0)))


## Compétences d'une entrée de roster, telles qu'elle les aura au combat.
##
## Une fiche écrite à la main porte sa propre liste — compétences de classe
## retirées comprises. Les autres se déduisent de leur classe et de leur niveau,
## exactement comme [method Stats.get_skills] le fera en entrant en scène. Sans
## ce partage, l'écran de préparation annonçait des compétences que l'unité
## n'avait pas et taisait celles qu'on venait de lui donner.
func unit_skills(unit: Dictionary) -> Array:
	if unit.get("skills") is Array:
		return (unit["skills"] as Array).duplicate()
	return ClassDataDBClass.unlocked_skills(
		int(unit.get("class_id", 0)), int(unit.get("level", 1)))
#endregion


#region Intendance (économie entre chapitres)
## Remet toute l'armée d'aplomb, sans rien coûter.
##
## Le repos entre deux batailles, **quelle qu'en soit l'issue** : gagnée ou
## perdue, on repart entier. C'est le seul soin du jeu, et il n'est pas
## négociable — l'intendance n'en vend plus. Payer pour se relever tirait la
## difficulté dans le mauvais sens : l'or manque justement quand ça va mal.
##
## Ne ressuscite personne : une unité tombée en mort permanente le reste.
## [returns] le nombre d'unités qui en avaient besoin.
func rest_army() -> int:
	var healed: int = 0
	for unit: Dictionary in roster:
		if not bool(unit.get("alive", true)):
			continue
		var max_hp: int = int(unit.get("max_hp", 0))
		if int(unit.get("hp", max_hp)) >= max_hp:
			continue
		unit["hp"] = max_hp
		healed += 1
	if healed > 0:
		roster_changed.emit()
	return healed


## Achète un objet et le remet à une unité.
## [returns] {ok, cost, reason}
func buy_item(unit_id: String, item_name: String) -> Dictionary:
	var key: String = ITEMS.canonical_name(item_name)
	if key.is_empty():
		return {"ok": false, "reason": "objet inconnu : %s" % item_name}
	var unit: Dictionary = get_unit(unit_id)
	if unit.is_empty():
		return {"ok": false, "reason": "unité inconnue"}

	var price: int = ITEMS.price(key)
	if gold < price:
		return {"ok": false, "reason": "il manque %d or" % (price - gold)}

	var inventory: Array = unit.get("items", [])
	if inventory.size() >= ITEMS.MAX_ITEMS:
		return {"ok": false, "reason": "%s ne peut porter que %d objets" % [
			str(unit.get("name", "")), ITEMS.MAX_ITEMS
		]}

	gold -= price
	inventory.append(key)
	unit["items"] = inventory
	roster_changed.emit()
	return {"ok": true, "cost": price, "reason": ""}


## Revend un objet (moitié prix).
func sell_item(unit_id: String, item_name: String) -> Dictionary:
	var key: String = ITEMS.canonical_name(item_name)
	var unit: Dictionary = get_unit(unit_id)
	if key.is_empty() or unit.is_empty():
		return {"ok": false, "reason": "objet ou unité inconnu"}

	var inventory: Array = unit.get("items", [])
	if not key in inventory:
		return {"ok": false, "reason": "%s ne porte pas de %s" % [str(unit.get("name", "")), key]}

	inventory.erase(key)
	unit["items"] = inventory
	var earned: int = ITEMS.resale_price(key)
	gold += earned
	roster_changed.emit()
	return {"ok": true, "earned": earned, "reason": ""}


## Consomme un objet à effet permanent depuis l'intendance (hors combat).
func use_booster(unit_id: String, item_name: String) -> Dictionary:
	var key: String = ITEMS.canonical_name(item_name)
	var unit: Dictionary = get_unit(unit_id)
	if key.is_empty() or unit.is_empty():
		return {"ok": false, "reason": "objet ou unité inconnu"}
	if not ITEMS.is_boost(key):
		return {"ok": false, "reason": "%s ne s'utilise qu'en combat" % key}

	var inventory: Array = unit.get("items", [])
	if not key in inventory:
		return {"ok": false, "reason": "%s ne porte pas de %s" % [str(unit.get("name", "")), key]}

	var item: Dictionary = ITEMS.get_item(key)
	var stat: String = str(item.get("stat", "str"))
	var amount: int = int(item.get("amount", 2))
	unit[stat] = int(unit.get(stat, 0)) + amount
	if stat == "max_hp":
		unit["hp"] = int(unit.get("hp", 0)) + amount
	inventory.erase(key)
	unit["items"] = inventory
	roster_changed.emit()
	return {"ok": true, "stat": stat, "amount": amount, "reason": ""}


#region Armes
## Achète une arme et la range dans le fourreau d'une unité.
##
## L'arme achetée par une unité qui n'en portait aucune lui est mise en main
## d'office — sinon l'achat n'aurait aucun effet en bataille.
## [returns] {ok, cost, equipped, reason}
func buy_weapon(unit_id: String, weapon_id: String) -> Dictionary:
	var key: String = WEAPONS.canonical_id(weapon_id)
	if key.is_empty():
		return {"ok": false, "reason": "arme inconnue : %s" % weapon_id}
	var unit: Dictionary = get_unit(unit_id)
	if unit.is_empty():
		return {"ok": false, "reason": "unité inconnue"}

	var arsenal: Array = unit.get("weapons", [])
	if key in arsenal:
		return {"ok": false, "reason": "%s porte déjà %s" % [
			str(unit.get("name", "")), WEAPONS.label(key)
		]}
	if arsenal.size() >= WEAPONS.MAX_WEAPONS:
		return {"ok": false, "reason": "%s ne peut porter que %d armes" % [
			str(unit.get("name", "")), WEAPONS.MAX_WEAPONS
		]}

	var cost: int = WEAPONS.price(key)
	if gold < cost:
		return {"ok": false, "reason": "il manque %d or" % (cost - gold)}

	gold -= cost
	arsenal.append(key)
	unit["weapons"] = arsenal
	var equipped: bool = false
	if str(unit.get("weapon", "")).is_empty():
		unit["weapon"] = key
		equipped = true
	roster_changed.emit()
	return {"ok": true, "cost": cost, "equipped": equipped, "reason": ""}


## Revend une arme (moitié prix). Celle qui était en main est remplacée par la
## suivante du fourreau, faute de quoi l'unité partirait désarmée sans le savoir.
func sell_weapon(unit_id: String, weapon_id: String) -> Dictionary:
	var key: String = WEAPONS.canonical_id(weapon_id)
	var unit: Dictionary = get_unit(unit_id)
	if key.is_empty() or unit.is_empty():
		return {"ok": false, "reason": "arme ou unité inconnue"}

	var arsenal: Array = unit.get("weapons", [])
	if not key in arsenal:
		return {"ok": false, "reason": "%s ne porte pas %s" % [
			str(unit.get("name", "")), WEAPONS.label(key)
		]}

	arsenal.erase(key)
	unit["weapons"] = arsenal
	if str(unit.get("weapon", "")) == key:
		unit["weapon"] = str(arsenal[0]) if not arsenal.is_empty() else ""

	var earned: int = WEAPONS.resale_price(key)
	gold += earned
	roster_changed.emit()
	return {"ok": true, "earned": earned, "reason": ""}


## Met une arme du fourreau en main.
func equip_weapon(unit_id: String, weapon_id: String) -> Dictionary:
	var key: String = WEAPONS.canonical_id(weapon_id)
	var unit: Dictionary = get_unit(unit_id)
	if key.is_empty() or unit.is_empty():
		return {"ok": false, "reason": "arme ou unité inconnue"}
	if not key in unit.get("weapons", []):
		return {"ok": false, "reason": "%s ne porte pas %s" % [
			str(unit.get("name", "")), WEAPONS.label(key)
		]}

	unit["weapon"] = key
	roster_changed.emit()
	return {"ok": true, "weapon": key, "reason": ""}


## Armes d'une unité, décrites pour le menu d'équipement :
## [{id, label, description, equipped}]
func unit_arsenal(unit_id: String) -> Array:
	var unit: Dictionary = get_unit(unit_id)
	if unit.is_empty():
		return []
	var equipped: String = str(unit.get("weapon", ""))
	var out: Array = []
	for id in unit.get("weapons", []):
		out.append({
			"id": str(id),
			"label": WEAPONS.label(str(id)),
			"description": WEAPONS.describe(str(id)),
			"equipped": str(id) == equipped,
		})
	return out
#endregion


## Verse un personnage créé par le joueur dans l'armée.
##
## Il entre par la même porte que les autres — une entrée de roster — mais sans
## `.tres` derrière lui : c'est [UnitDocument] qui décrit sa fiche. Gratuit et
## sans condition, contrairement au recrutement : c'est du contenu que le joueur
## écrit, pas une récompense de campagne.
##
## [returns] {ok, id, reason}
func enlist_custom(doc: UnitDocument) -> Dictionary:
	if not doc:
		return {"ok": false, "reason": "aucun personnage"}
	var errors: Array[String] = doc.validate()
	if not errors.is_empty():
		return {"ok": false, "reason": errors[0]}

	var unit: Dictionary = doc.to_roster_unit()
	for u: Dictionary in roster:
		if str(u.get("id", "")) == str(unit["id"]):
			return {"ok": false, "reason": "%s est déjà dans l'armée" % str(unit["name"])}

	roster.append(unit)
	roster_changed.emit()
	return {"ok": true, "id": str(unit["id"]), "reason": ""}


## Unités recrutables encore absentes du roster : [{path, cost, name, class}]
func available_recruits() -> Array:
	var out: Array = []
	for entry: Dictionary in CampaignDBClass.RECRUITS:
		var path: String = str(entry.get("path", ""))
		var preview: Dictionary = unit_from_resource(path)
		if preview.is_empty() or not get_unit(str(preview["id"])).is_empty():
			continue
		out.append({
			"path": path,
			"cost": int(entry.get("cost", 0)),
			"name": str(preview["name"]),
			"class": unit_class_name(preview),
			"level": int(preview["level"]),
		})
	return out


## Recrute une unité contre de l'or.
## Personnages écrits par le joueur, encore absents de l'armée.
##
## Même forme que [method available_recruits] : l'intendance les affiche sur la
## même ligne, avec le même bouton, et n'a pas à savoir d'où ils viennent.
## [returns] [{slug, name, class, level, cost}]
func custom_recruits() -> Array:
	var out: Array = []
	for entry: Dictionary in UnitLibrary.list_units():
		# Une fiche invalide entrerait en bataille sans qu'on sache quoi en faire.
		if not bool(entry.get("valid", false)):
			continue
		var slug: String = str(entry["slug"])
		if not get_unit(slug).is_empty():
			continue  # déjà enrôlé
		out.append({
			"slug": slug,
			"name": str(entry.get("name", slug)),
			"class": str(entry.get("class_name", "")),
			"level": int(entry.get("level", 1)),
			"cost": CUSTOM_RECRUIT_COST,
		})
	return out


## Enrôle un personnage écrit par le joueur, contre son prix.
##
## Le prix vit dans [constant CUSTOM_RECRUIT_COST] et vaut zéro pour l'instant :
## le chemin de paiement est en place, il ne reste qu'à poser un chiffre le jour
## où l'on voudra que ça coûte.
## [returns] {ok, cost, id, reason}
func hire_custom(slug: String) -> Dictionary:
	var doc: UnitDocument = UnitLibrary.load_unit(slug)
	if not doc:
		return {"ok": false, "cost": 0, "reason": "personnage introuvable : %s" % slug}
	if gold < CUSTOM_RECRUIT_COST:
		return {"ok": false, "cost": CUSTOM_RECRUIT_COST,
			"reason": "il manque %d or" % (CUSTOM_RECRUIT_COST - gold)}

	var result: Dictionary = enlist_custom(doc)
	if not bool(result.get("ok", false)):
		result["cost"] = 0
		return result

	gold -= CUSTOM_RECRUIT_COST
	result["cost"] = CUSTOM_RECRUIT_COST
	return result


func hire(path: String) -> Dictionary:
	var cost: int = 0
	var found: bool = false
	for entry: Dictionary in CampaignDBClass.RECRUITS:
		if str(entry.get("path", "")) == path:
			cost = int(entry.get("cost", 0))
			found = true
			break
	if not found:
		return {"ok": false, "reason": "unité non recrutable"}
	if gold < cost:
		return {"ok": false, "reason": "il manque %d or" % (cost - gold)}
	if not recruit(path):
		return {"ok": false, "reason": "unité déjà dans l'armée"}

	gold -= cost
	return {"ok": true, "cost": cost, "reason": ""}
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
		"deployment_tiles": _tiles_to_json(),
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
	_tiles_from_json(data.get("deployment_tiles", {}))
	bonus_history = data.get("bonus_history", {})
	turn_count = 1

	roster = []
	for u in data.get("roster", []):
		if typeof(u) == TYPE_DICTIONARY:
			roster.append(_normalize_unit(u))

	roster_changed.emit()
	return true


## Ce que contient un emplacement, sans charger la partie.
##
## L'écran de sauvegarde a besoin de décrire quatre emplacements d'un coup :
## les charger pour les lire écraserait la partie en cours. On relit donc
## l'en-tête du JSON et on n'en garde que de quoi remplir une ligne.
##
## [returns] {exists, slot, auto, saved_at, chapter_index, chapter_title,
##            gold, units, fallen, difficulty, permadeath}
func slot_info(slot: int) -> Dictionary:
	var out: Dictionary = {
		"exists": false, "slot": slot, "auto": slot == AUTO_SLOT,
		"saved_at": "", "chapter_index": 0, "chapter_title": "",
		"gold": 0, "units": 0, "fallen": 0,
		"difficulty": DIFF.Level.NORMAL, "permadeath": true,
	}
	if not has_save(slot):
		return out

	var f := FileAccess.open(save_path(slot), FileAccess.READ)
	if not f:
		return out
	var raw: String = f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(raw) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return out

	var data: Dictionary = json.data
	out["exists"] = true
	out["saved_at"] = str(data.get("saved_at", ""))
	out["chapter_index"] = int(data.get("chapter_index", 0))
	out["gold"] = int(data.get("gold", 0))
	out["difficulty"] = int(data.get("difficulty", DIFF.Level.NORMAL))
	out["permadeath"] = bool(data.get("permadeath", true))

	var chapter: ChapterData = CampaignDBClass.get_chapter(out["chapter_index"])
	out["chapter_title"] = chapter.title if chapter else "Campagne terminée"

	for u in data.get("roster", []):
		if typeof(u) != TYPE_DICTIONARY:
			continue
		if bool(u.get("alive", true)):
			out["units"] = int(out["units"]) + 1
		else:
			out["fallen"] = int(out["fallen"]) + 1
	return out


## Résumé de tous les emplacements, dans l'ordre.
func all_slots() -> Array:
	var out: Array = []
	for slot: int in range(SAVE_SLOTS):
		out.append(slot_info(slot))
	return out


## Supprime une sauvegarde.
func delete_save(slot: int = 0) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path(slot)))
#endregion


#region Internes
## Les cases de départ, sous une forme que le JSON sait écrire : id → [col, row].
func _tiles_to_json() -> Dictionary:
	var out: Dictionary = {}
	for id: String in deployment_tiles:
		var pos: Vector2i = deployment_tiles[id]
		out[id] = [pos.x, pos.y]
	return out


## Relecture des cases de départ. Les entrées mal formées sont écartées plutôt
## que de faire réapparaître un pion hors de la carte.
func _tiles_from_json(raw: Variant) -> void:
	deployment_tiles.clear()
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for id in raw:
		var pair: Variant = raw[id]
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
			continue
		deployment_tiles[str(id)] = Vector2i(int(pair[0]), int(pair[1]))


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

	# Arsenal : une sauvegarde d'avant le catalogue d'armes n'en contient pas, et
	# une arme retirée du catalogue ne doit pas ressusciter par le JSON.
	var arsenal: Array = []
	for w in u.get("weapons", []):
		var key: String = WEAPONS.canonical_id(str(w))
		if not key.is_empty() and not key in arsenal:
			arsenal.append(key)
	u["weapons"] = arsenal
	var equipped: String = WEAPONS.canonical_id(str(u.get("weapon", "")))
	u["weapon"] = equipped if equipped in arsenal else ""
	# Absent des sauvegardes d'avant le catalogue : elles gardent leurs valeurs brutes.
	u["uses_arsenal"] = bool(u.get("uses_arsenal", false))

	# Compétences d'une fiche écrite à la main. Même règle que l'arsenal : une
	# compétence retirée du catalogue ne doit pas ressusciter par le JSON, et la
	# clé absente veut dire « celles de la classe », pas « aucune ».
	if u.has("skills"):
		var learnt: Array = []
		for s in u.get("skills", []):
			var skill_id: String = str(s)
			if SKILLS.exists(skill_id) and not skill_id in learnt:
				learnt.append(skill_id)
		u["skills"] = learnt
	return u


func _default_deployment() -> Array:
	var chapter: ChapterData = current_chapter()
	var slots: int = chapter.deploy_slots if chapter else 3
	var ids: Array = required_deployment()
	for u: Dictionary in available_units():
		if ids.size() >= slots:
			break
		var id: String = str(u.get("id", ""))
		if not id in ids:
			ids.append(id)
	return ids
#endregion
