class_name Stats
extends Node
## Fire Emblem stats container for a character instance
## Imports data from StatsResource and tracks current HP, EXP, level-ups, etc.

const WT = preload("res://data/models/world/stats/weapon_type.gd")
const ClassDataDB = preload("res://data/models/world/stats/class_data.gd")
const ITEMS = preload("res://data/models/world/stats/item_db.gd")
const WEAPONS = preload("res://data/models/world/stats/weapon_db.gd")
const SkillDB = preload("res://data/models/world/stats/skill_db.gd")

#region Identity
var override_name: String
var expertise: String
var character_class: int = 0  ## ClassDB.Id
var level: int = 1
var exp: int = 0              ## Current EXP
var is_promoted: bool = false
var sprite: String
#endregion

#region FE Core Stats
var hp: int           ## Current HP
var max_hp: int       ## Maximum HP
var str: int          ## Strength
var mag: int          ## Magic
var skl: int          ## Skill
var spd: int          ## Speed
var lck: int          ## Luck
var def: int          ## Defense
var res: int          ## Resistance
#endregion

#region Mobility & Weapon
var movement: int     ## Movement points
var jump: int         ## Jump height
var attack_range: int ## Attack range
var weapon_type: int  ## WT.Type enum
var weapon_might: int ## Base weapon damage
## Modificateur de précision apporté par l'arme équipée
var weapon_hit: int = 0
## Modificateur de critique apporté par l'arme équipée
var weapon_crit: int = 0
## Poids de l'arme équipée (freine la vitesse d'attaque, amorti par la force)
var weapon_weight: int = 0
#endregion


#region Arsenal
## Armes transportées (identifiants connus de [WeaponDB]), au plus MAX_WEAPONS
var weapons: Array = []
## Arme actuellement en main ("" = les valeurs brutes de la fiche font foi)
var equipped_weapon: String = ""
#endregion

#region Legacy (for template compatibility)
var attack_power: int ## Flat attack power (computed in FE)
var max_health: int:  ## Alias for max_hp
	get: return max_hp
var curr_health: int: ## Alias for hp
	get: return hp
#endregion

#region Compétences
## Compétences acquises hors classe (récompense, objet, scénario)
var extra_skills: Array = []
## Compétences de classe retirées à la main, dans l'éditeur de personnages.
##
## Sans cette liste, une compétence de classe serait indéracinable : elle se
## déduit de la classe et du niveau, et rien ne saurait dire « pas celle-là ».
var removed_skills: Array = []
#endregion

#region Inventaire & états temporaires
## Consommables transportés (noms connus de [ItemDB])
var items: Array = []
## Bonus temporaires en cours : [{stat, amount, turns}]
var _active_buffs: Array = []
#endregion

#region Growth Rates
var hp_growth: int
var str_growth: int
var mag_growth: int
var skl_growth: int
var spd_growth: int
var lck_growth: int
var def_growth: int
var res_growth: int
#endregion


## Initialize stats from a StatsResource
func import_stats(stats: StatsResource) -> void:
	# Identity
	override_name = stats.override_name
	expertise = stats.expertise
	character_class = stats.character_class
	level = stats.level
	exp = stats.exp
	is_promoted = stats.is_promoted
	sprite = stats.sprite
	
	# Core FE stats
	max_hp = stats.hp
	hp = max_hp
	str = stats.str
	mag = stats.mag
	skl = stats.skl
	spd = stats.spd
	lck = stats.lck
	def = stats.def
	res = stats.res
	
	# Mobility & weapon
	movement = stats.movement
	stats.set_jump()
	jump = stats.jump
	attack_range = stats.attack_range
	weapon_type = stats.weapon_type
	weapon_might = stats.weapon_might
	
	# Growth rates
	hp_growth = stats.hp_growth
	str_growth = stats.str_growth
	mag_growth = stats.mag_growth
	skl_growth = stats.skl_growth
	spd_growth = stats.spd_growth
	lck_growth = stats.lck_growth
	def_growth = stats.def_growth
	res_growth = stats.res_growth

	# Inventaire
	items = []
	var res_items: Variant = stats.get("items")
	if res_items is Array:
		for i in res_items:
			if items.size() < ITEMS.MAX_ITEMS:
				items.append(str(i))

	# Arsenal : une fiche muette garde ses `weapon_type` / `weapon_might` bruts,
	# ce qui laisse intactes toutes les unités écrites avant le catalogue d'armes.
	weapons = []
	weapon_hit = 0
	weapon_crit = 0
	weapon_weight = 0
	equipped_weapon = ""
	var res_weapons: Variant = stats.get("weapons")
	if res_weapons is Array:
		for w in res_weapons:
			add_weapon(str(w))
	var res_equipped: Variant = stats.get("equipped_weapon")
	if res_equipped is String and not str(res_equipped).is_empty():
		equip(str(res_equipped))

	# Croissances de classe : par défaut, class_data.gd fait autorité (P1).
	if stats.get("use_class_growths") == null or bool(stats.use_class_growths):
		apply_class_growths(character_class)

	# Legacy compat — depuis l'arsenal, c'est l'arme en main qui décide, pas la
	# fiche : `get_total_attack()` doit être lu sur l'unité vivante.
	attack_power = get_total_attack()


## Aligne les taux de croissance sur ceux de la classe donnée.
## Sans effet si la classe est inconnue de [ClassDataDB].
func apply_class_growths(class_id: int) -> bool:
	var growths: Dictionary = ClassDataDB.get_growths(class_id)
	if growths.is_empty():
		return false
	hp_growth = int(growths.get("hp", hp_growth))
	str_growth = int(growths.get("str", str_growth))
	mag_growth = int(growths.get("mag", mag_growth))
	skl_growth = int(growths.get("skl", skl_growth))
	spd_growth = int(growths.get("spd", spd_growth))
	lck_growth = int(growths.get("lck", lck_growth))
	def_growth = int(growths.get("def", def_growth))
	res_growth = int(growths.get("res", res_growth))
	return true


## Taux de croissance effectifs, sous forme de dictionnaire.
func get_growths() -> Dictionary:
	return {
		"hp": hp_growth, "str": str_growth, "mag": mag_growth, "skl": skl_growth,
		"spd": spd_growth, "lck": lck_growth, "def": def_growth, "res": res_growth,
	}


## Apply damage or healing. Negative value = damage, positive = healing.
func apply_to_curr_health(amount: int) -> void:
	print("Target initial health: ", hp, " - Applying: ", amount)
	hp = clamp(hp + amount, 0, max_hp)
	print("Target final health: ", hp)


## Get the effective attack stat (Str for physical, Mag for magical)
func get_attack_stat() -> int:
	if WT.is_magical(weapon_type):
		return mag
	return str


## Get total attack power (stat + weapon might)
func get_total_attack() -> int:
	return get_attack_stat() + weapon_might


## Get base hit rate (arme comprise)
func get_base_hit() -> int:
	return skl * 2 + int(lck / 2.0) + weapon_hit


## Get avoid rate
func get_avoid() -> int:
	return spd * 2 + lck


## Get critical hit rate (arme comprise)
func get_crit() -> int:
	return int(skl / 2.0) + weapon_crit


## Get critical evade (reduces enemy crit rate)
func get_crit_evade() -> int:
	return lck


## Get attack speed — la vitesse, moins ce que l'arme coûte à porter.
func get_attack_speed() -> int:
	return spd - speed_penalty()


## Malus de vitesse d'attaque dû au poids de l'arme.
##
## La force amortit le poids : à bras égal, une hache d'acier ralentit un mage et
## laisse un guerrier intact. C'est ce qui empêche « la plus grosse arme » d'être
## toujours le bon choix, et donne son intérêt au menu d'équipement.
func speed_penalty() -> int:
	return maxi(0, weapon_weight - str)


#region Compétences
## Compétences actives de l'unité : celles de sa classe débloquées à son niveau,
## plus les compétences acquises hors classe.
func get_skills() -> Array:
	var ids: Array = ClassDataDB.unlocked_skills(character_class, level)
	for id in extra_skills:
		if not id in ids:
			ids.append(id)
	var kept: Array = []
	for id in ids:
		if not id in removed_skills:
			kept.append(id)
	return kept


## Accorde une compétence hors classe. Refusée si inconnue ou déjà présente.
##
## Rendre une compétence retirée à la main la réactive : c'est la même intention,
## et laisser la suppression gagner sur l'acquisition serait un piège.
func learn_skill(skill_id: String) -> bool:
	if not SkillDB.exists(skill_id):
		return false
	var was_removed: bool = skill_id in removed_skills
	removed_skills.erase(skill_id)
	if skill_id in get_skills():
		return was_removed
	extra_skills.append(skill_id)
	return true


## Retire une compétence, qu'elle vienne de la classe ou d'un acquis.
##
## [returns] false si l'unité ne l'avait pas.
func forget_skill(skill_id: String) -> bool:
	if not skill_id in get_skills():
		return false
	extra_skills.erase(skill_id)
	if not skill_id in removed_skills:
		removed_skills.append(skill_id)
	return true


## Impose la liste exacte des compétences de l'unité.
##
## Ce que l'éditeur de personnages écrit sur une fiche est une liste définitive,
## pas une addition : on la traduit ici en acquis et en retraits par rapport à ce
## que la classe donne déjà. Écrire les deux listes à la main depuis l'appelant
## ferait fatalement diverger les deux moitiés du calcul.
func set_skills(ids: Array) -> void:
	var wanted: Array = []
	for id in ids:
		var skill_id: String = str(id)
		if SkillDB.exists(skill_id) and not skill_id in wanted:
			wanted.append(skill_id)

	extra_skills = []
	removed_skills = []
	var from_class: Array = ClassDataDB.unlocked_skills(character_class, level)
	for id in wanted:
		if not id in from_class:
			extra_skills.append(id)
	for id in from_class:
		if not id in wanted:
			removed_skills.append(id)


## Contexte de combat de cette unité, pour l'évaluation des compétences.
func skill_context(attacking: bool, terrain_def: int = 0, vs_flying: bool = false) -> Dictionary:
	return {
		"attacking": attacking,
		"hp_ratio": float(hp) / float(maxi(1, max_hp)),
		"terrain_def": terrain_def,
		"vs_flying": vs_flying,
	}
#endregion


#region Arsenal
## Ajoute une arme au fourreau.
##
## La première arme rangée est aussi équipée : une unité qui vient d'acheter son
## épée ne doit pas partir au combat les mains vides parce qu'elle a oublié de
## l'empoigner.
##
## [returns] false si l'arme est inconnue, déjà portée, ou le fourreau plein.
func add_weapon(weapon_id: String) -> bool:
	var key: String = WEAPONS.canonical_id(weapon_id)
	if key.is_empty() or key in weapons or weapons.size() >= WEAPONS.MAX_WEAPONS:
		return false
	weapons.append(key)
	if equipped_weapon.is_empty():
		equip(key)
	return true


## Retire une arme du fourreau. Si c'était celle en main, l'unité empoigne la
## suivante — ou revient à mains nues, ce que la prévision de combat dira.
func drop_weapon(weapon_id: String) -> bool:
	var key: String = WEAPONS.canonical_id(weapon_id)
	if key.is_empty() or not key in weapons:
		return false
	weapons.erase(key)
	if equipped_weapon == key:
		equipped_weapon = ""
		if weapons.is_empty():
			unequip()
		else:
			equip(str(weapons[0]))
	return true


## Prend une arme en main : type, puissance, portée, précision, critique, poids.
##
## [returns] {ok: bool, weapon: String, reason: String}
func equip(weapon_id: String) -> Dictionary:
	var key: String = WEAPONS.canonical_id(weapon_id)
	if key.is_empty():
		return {"ok": false, "weapon": "", "reason": "arme inconnue : %s" % weapon_id}
	if not key in weapons:
		return {"ok": false, "weapon": key, "reason": "%s ne porte pas cette arme" % display_name()}

	var w: Dictionary = WEAPONS.get_weapon(key)
	equipped_weapon = key
	weapon_type = int(w["type"])
	weapon_might = int(w["might"])
	attack_range = int(w["range"])
	weapon_hit = int(w["hit"])
	weapon_crit = int(w["crit"])
	weapon_weight = int(w["weight"])
	attack_power = get_total_attack()
	return {"ok": true, "weapon": key, "reason": ""}


## Repose l'arme : l'unité ne frappe plus que de ses poings.
##
## Elle retombe au contact (portée 1) et ne riposte plus — `Type.NONE` n'engage
## aucun combat. Se battre à mains nues reste possible, mais ne vaut rien : c'est
## ce qui donne un prix à revendre son arme.
func unequip() -> void:
	equipped_weapon = ""
	weapon_type = WT.Type.NONE
	weapon_might = 0
	weapon_hit = 0
	weapon_crit = 0
	weapon_weight = 0
	attack_range = 1
	attack_power = get_total_attack()


## Armes portées, décrites pour l'affichage :
## [{id, label, description, equipped, might, range, hit, crit, weight}]
func arsenal() -> Array:
	var out: Array = []
	for id: String in weapons:
		var w: Dictionary = WEAPONS.get_weapon(id)
		out.append({
			"id": id,
			"label": WEAPONS.label(id),
			"description": WEAPONS.describe(id),
			"equipped": id == equipped_weapon,
			"might": int(w.get("might", 0)),
			"range": int(w.get("range", 1)),
			"hit": int(w.get("hit", 0)),
			"crit": int(w.get("crit", 0)),
			"weight": int(w.get("weight", 0)),
			"speed_penalty": maxi(0, int(w.get("weight", 0)) - str),
		})
	return out


## Nom lisible de l'unité (le même que partout ailleurs).
func display_name() -> String:
	return override_name if override_name else expertise
#endregion


#region Inventaire
## Ajoute un consommable (refusé si inconnu ou inventaire plein).
func add_item(item_name: String) -> bool:
	var key: String = ITEMS.canonical_name(item_name)
	if key.is_empty() or items.size() >= ITEMS.MAX_ITEMS:
		return false
	items.append(key)
	return true


## L'unité transporte-t-elle cet objet ?
func has_item(item_name: String) -> bool:
	var key: String = ITEMS.canonical_name(item_name)
	return not key.is_empty() and key in items


## Consomme un objet de l'inventaire.
## [returns] {ok: bool, item: String, effect: String, amount: int, reason: String}
func use_item(item_name: String) -> Dictionary:
	var key: String = ITEMS.canonical_name(item_name)
	if key.is_empty():
		return {"ok": false, "reason": "objet inconnu : %s" % item_name}
	if not key in items:
		return {"ok": false, "reason": "%s ne transporte pas de %s" % [
			override_name if override_name else expertise, key
		]}

	var item: Dictionary = ITEMS.get_item(key)
	items.erase(key)

	match int(item.get("kind", ITEMS.Kind.HEAL)):
		ITEMS.Kind.HEAL:
			var before: int = hp
			apply_to_curr_health(int(item.get("amount", 10)))
			return {"ok": true, "item": key, "effect": "heal",
				"amount": hp - before, "reason": ""}
		ITEMS.Kind.BUFF:
			var stat: String = str(item.get("stat", "def"))
			var amount: int = int(item.get("amount", 2))
			apply_buff(stat, amount, int(item.get("turns", 2)))
			return {"ok": true, "item": key, "effect": "buff",
				"amount": amount, "stat": stat, "reason": ""}
		ITEMS.Kind.BOOST:
			# Gain permanent : les PV max augmentent aussi les PV courants.
			var stat: String = str(item.get("stat", "str"))
			var amount: int = int(item.get("amount", 2))
			set(stat, int(get(stat)) + amount)
			if stat == "max_hp":
				hp += amount
			attack_power = get_total_attack()
			return {"ok": true, "item": key, "effect": "boost",
				"amount": amount, "stat": stat, "reason": ""}

	return {"ok": false, "reason": "effet non supporté"}
#endregion


#region Bonus temporaires
## Applique un bonus de stat pour un nombre de tours donné (garde, tonique…).
func apply_buff(stat: String, amount: int, turns: int = 1) -> void:
	if not stat in ["str", "mag", "skl", "spd", "lck", "def", "res"]:
		return
	set(stat, int(get(stat)) + amount)
	_active_buffs.append({"stat": stat, "amount": amount, "turns": turns})
	attack_power = get_total_attack()


## Fait vieillir les bonus d'un tour et retire ceux qui expirent.
func tick_buffs() -> void:
	var still_active: Array = []
	for buff: Dictionary in _active_buffs:
		buff["turns"] = int(buff["turns"]) - 1
		if int(buff["turns"]) > 0:
			still_active.append(buff)
		else:
			set(str(buff["stat"]), int(get(str(buff["stat"]))) - int(buff["amount"]))
	_active_buffs = still_active
	attack_power = get_total_attack()


## Bonus temporaires en cours (lecture seule, pour l'UI et l'export CielAI).
func active_buffs() -> Array:
	return _active_buffs.duplicate(true)
#endregion


## Grant EXP to this character. Automatically checks for level up.
## [param rng] RNG optionnel : passer un générateur graine fixe rend la montée
## de niveau déterministe (utilisé par les tests headless).
## Returns: { gained_exp, leveled_up, new_level, stat_gains }
func gain_exp(amount: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var gained: int = amount
	exp += gained
	
	var result: Dictionary = {
		"gained_exp": gained,
		"leveled_up": false,
		"new_level": level,
		"stat_gains": {},
		"promoted": false,
	}
	
	# Check for level up (may trigger multiple if enough EXP)
	while EXPCalculator.can_level_up(level, exp):
		var needed: int = EXPCalculator.exp_for_next_level(level)
		exp -= needed
		var gains: Dictionary = _perform_level_up(rng)
		result["leveled_up"] = true
		result["new_level"] = level
		# Merge stat gains across multiple levels
		for stat in gains:
			result["stat_gains"][stat] = result["stat_gains"].get(stat, 0) + gains[stat]
	
	return result


## Amène l'unité au niveau demandé, en lui faisant gravir les échelons.
##
## Une carte de l'éditeur pose des unités à un niveau choisi. Leur donner
## directement `level = 8` mentirait : elles auraient les statistiques d'une
## recrue avec l'étiquette d'une vétérane. Elles montent donc réellement, par
## les croissances de leur classe — même chemin que la campagne.
##
## Le tirage est **graine fixe**, dérivée du nom et du niveau visé : rouvrir une
## carte donne la même adversaire, et les deux machines d'une partie en réseau
## la voient identique sans rien s'échanger. C'est la même exigence que le décor
## ([TacticsProps]).
##
## [returns] le niveau réellement atteint.
func raise_to_level(target: int) -> int:
	if target <= level:
		return level

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [override_name if override_name else expertise, target])
	while level < target:
		_perform_level_up(rng)
	return level


## Internal level up using RNG growth rates
## [param rng] Générateur optionnel (graine fixe = résultat reproductible)
func _perform_level_up(rng: RandomNumberGenerator = null) -> Dictionary:
	level += 1
	var gains: Dictionary = {}
	if not rng:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var growths = get_growths()

	var stat_count: int = 0
	for stat in growths:
		var roll = rng.randi_range(1, 100)
		if roll <= growths[stat]:
			gains[stat] = 1
			stat_count += 1
			match stat:
				"hp":  max_hp += 1; hp += 1
				"str": str += 1
				"mag": mag += 1
				"skl": skl += 1
				"spd": spd += 1
				"lck": lck += 1
				"def": def += 1
				"res": res += 1
		else:
			gains[stat] = 0
	
	# Update attack_power alias
	attack_power = get_total_attack()
	
	var char_name: String = override_name if override_name else expertise
	print_rich("[color=gold]⬆ LEVEL UP! %s → Lv.%d [+%d stats][/color]" % [char_name, level, stat_count])
	for s in gains:
		if gains[s] > 0:
			print("  +1 ", s.to_upper())
	
	# Promotion : automatique seulement s'il n'y a pas d'embranchement.
	# Sinon le choix revient au joueur (ou à Ciel via la commande `promote`).
	if can_promote_now() and not ClassDataDB.has_branching_promotion(character_class):
		promote_to(ClassDataDB.get_promotion(character_class))

	return gains


## L'unité remplit-elle les conditions de promotion ?
func can_promote_now() -> bool:
	return not is_promoted \
		and ClassDataDB.can_promote(character_class) \
		and level >= ClassDataDB.get_promo_level(character_class)


## Promeut l'unité vers une classe avancée.
## [param choice] Id de classe, nom de classe, ou null pour la branche par défaut.
## [returns] { promoted: bool, from, to, bonuses, reason }
func promote_to(choice: Variant = null) -> Dictionary:
	var result: Dictionary = {"promoted": false, "from": character_class, "to": -1,
		"bonuses": {}, "reason": ""}

	if is_promoted:
		result["reason"] = "déjà promue"
		return result
	if not ClassDataDB.can_promote(character_class):
		result["reason"] = "classe sans promotion"
		return result
	if level < ClassDataDB.get_promo_level(character_class):
		result["reason"] = "niveau %d requis" % ClassDataDB.get_promo_level(character_class)
		return result

	var new_class: int = ClassDataDB.resolve_promotion(character_class, choice)
	if new_class == -1:
		result["reason"] = "promotion invalide pour %s" % ClassDataDB.get_class_name(character_class)
		return result

	var old_class: int = character_class
	var old_name: String = ClassDataDB.get_class_name(old_class)

	# Bonus de promotion = écart de stats de base entre l'ancienne et la nouvelle classe.
	var bonuses: Dictionary = ClassDataDB.promotion_bonuses(old_class, new_class)
	max_hp += int(bonuses.get("hp", 0))
	hp = mini(hp + int(bonuses.get("hp", 0)), max_hp)
	str += int(bonuses.get("str", 0))
	mag += int(bonuses.get("mag", 0))
	skl += int(bonuses.get("skl", 0))
	spd += int(bonuses.get("spd", 0))
	lck += int(bonuses.get("lck", 0))
	def += int(bonuses.get("def", 0))
	res += int(bonuses.get("res", 0))
	movement = int(ClassDataDB.get_base_stats(new_class).get("mov", movement))

	character_class = new_class
	is_promoted = true
	# La classe promue impose ses propres croissances.
	apply_class_growths(new_class)
	attack_power = get_total_attack()

	result["promoted"] = true
	result["to"] = new_class
	result["bonuses"] = bonuses

	var char_name: String = override_name if override_name else expertise
	print_rich("[color=lime]🎖 PROMOTION! %s: %s → %s![/color]" % [
		char_name, old_name, ClassDataDB.get_class_name(new_class)
	])
	return result


## Deprecated: direct level up without EXP. Use gain_exp() instead.
func level_up(rng: RandomNumberGenerator = null) -> Dictionary:
	return _perform_level_up(rng)
