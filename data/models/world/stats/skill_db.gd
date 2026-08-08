class_name SkillDB
extends RefCounted
## Compétences de classe — passives conditionnelles et compétences à déclenchement.
##
## Logique pure : le calculateur de combat demande l'agrégat des modificateurs
## pour un contexte donné (attaque/défense, PV restants, terrain, cible volante)
## et applique le résultat. Les compétences se débloquent par classe et par niveau
## dans [ClassDataDB].

enum Kind {
	PASSIVE = 0,  ## Modificateurs permanents ou conditionnels
	ACTIVE = 1,   ## Déclenchement aléatoire pendant le combat (proc)
}

enum Trigger {
	ALWAYS = 0,          ## Toujours actif
	WHEN_ATTACKING = 1,  ## Seulement quand l'unité initie l'attaque
	WHEN_DEFENDING = 2,  ## Seulement quand l'unité subit l'attaque
	WHEN_HP_LOW = 3,     ## PV sous un seuil (ratio)
	WHEN_HP_FULL = 4,    ## PV au maximum
	ON_TERRAIN = 5,      ## Sur une case au bonus défensif
	VS_FLYING = 6,       ## Contre une unité volante
}

## Modificateurs reconnus par le calculateur de combat
const MOD_KEYS: Array[String] = ["hit", "crit", "avoid", "crit_avoid", "damage", "defense"]

static var DATA: Dictionary = {
	"duelist": {
		"name": "Duelliste",
		"desc": "+10 de précision quand l'unité engage le combat.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.WHEN_ATTACKING,
		"mods": {"hit": 10},
	},
	"charge": {
		"name": "Charge",
		"desc": "+2 de dégâts quand l'unité engage le combat.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.WHEN_ATTACKING,
		"mods": {"damage": 2},
	},
	"guardian": {
		"name": "Gardien",
		"desc": "+2 de défense quand l'unité est attaquée.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.WHEN_DEFENDING,
		"mods": {"defense": 2},
	},
	"wrath": {
		"name": "Fureur",
		"desc": "+20 de critique sous 50% de PV.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.WHEN_HP_LOW,
		"threshold": 0.5,
		"mods": {"crit": 20},
	},
	"focus": {
		"name": "Concentration",
		"desc": "+10 de précision et +5 de critique à pleins PV.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.WHEN_HP_FULL,
		"mods": {"hit": 10, "crit": 5},
	},
	"terrain_affinity": {
		"name": "Affinité terrain",
		"desc": "+15 d'esquive et +1 de défense sur un terrain défensif.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.ON_TERRAIN,
		"mods": {"avoid": 15, "defense": 1},
	},
	"serenity": {
		"name": "Sérénité",
		"desc": "+10 d'évitement de critique en permanence.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.ALWAYS,
		"mods": {"crit_avoid": 10},
	},
	"bulwark": {
		"name": "Rempart",
		"desc": "+1 de défense en permanence.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.ALWAYS,
		"mods": {"defense": 1},
	},
	"falcon_eye": {
		"name": "Œil de faucon",
		"desc": "+20 de précision et +3 de dégâts contre les unités volantes.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.VS_FLYING,
		"mods": {"hit": 20, "damage": 3},
	},
	"luna": {
		"name": "Lune",
		"desc": "Peut ignorer la moitié de la défense adverse (chance = Adresse %).",
		"kind": Kind.ACTIVE,
		"trigger": Trigger.WHEN_ATTACKING,
		"proc": "pierce",
		"chance_stat": "skl",
		"chance_ratio": 1.0,
	},
	"astra": {
		"name": "Astre",
		"desc": "Peut enchaîner une frappe supplémentaire (chance = Adresse / 2 %).",
		"kind": Kind.ACTIVE,
		"trigger": Trigger.WHEN_ATTACKING,
		"proc": "extra_hit",
		"chance_stat": "skl",
		"chance_ratio": 0.5,
	},
}


## La compétence existe-t-elle ?
static func exists(skill_id: String) -> bool:
	return DATA.has(skill_id)


## Définition d'une compétence (dictionnaire vide si inconnue)
static func get_skill(skill_id: String) -> Dictionary:
	return DATA.get(skill_id, {})


## Nom affichable
static func get_skill_name(skill_id: String) -> String:
	return str(DATA.get(skill_id, {}).get("name", skill_id))


## Description affichable
static func describe(skill_id: String) -> String:
	return str(DATA.get(skill_id, {}).get("desc", ""))


## Toutes les compétences du catalogue, dans l'ordre de déclaration.
static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in DATA:
		ids.append(str(id))
	return ids


## Quand la compétence s'applique, en une phrase.
##
## Le déclencheur est la moitié de ce qu'il faut savoir : « +2 de défense » ne
## dit pas si l'unité en profite quand elle charge ou quand elle encaisse.
static func trigger_label(skill_id: String) -> String:
	match int(get_skill(skill_id).get("trigger", Trigger.ALWAYS)):
		Trigger.ALWAYS:
			return "En permanence"
		Trigger.WHEN_ATTACKING:
			return "Quand l'unité engage le combat"
		Trigger.WHEN_DEFENDING:
			return "Quand l'unité est attaquée"
		Trigger.WHEN_HP_LOW:
			var threshold: float = float(get_skill(skill_id).get("threshold", 0.5))
			return "Sous %d%% de PV" % int(round(threshold * 100.0))
		Trigger.WHEN_HP_FULL:
			return "À pleins PV"
		Trigger.ON_TERRAIN:
			return "Sur une case qui donne un bonus de défense"
		Trigger.VS_FLYING:
			return "Contre une unité volante"
	return ""


## Info-bulle complète : le nom, l'effet, et la condition qui le déclenche.
## Rend "" pour une compétence inconnue — un Control n'affiche alors aucune bulle.
static func tooltip(skill_id: String) -> String:
	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return ""
	var lines: Array[String] = [
		"✨ %s" % str(skill.get("name", skill_id)),
		"",
		str(skill.get("desc", "")),
		"",
		"⟶ %s" % trigger_label(skill_id),
	]
	if int(skill.get("kind", Kind.PASSIVE)) == Kind.ACTIVE:
		lines.append("⟶ Déclenchement aléatoire, une chance par coup porté.")
	return "\n".join(lines)


## La compétence s'applique-t-elle dans ce contexte ?
## [param ctx] {attacking: bool, hp_ratio: float, terrain_def: int, vs_flying: bool}
static func is_active(skill_id: String, ctx: Dictionary) -> bool:
	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return false

	match int(skill.get("trigger", Trigger.ALWAYS)):
		Trigger.ALWAYS:
			return true
		Trigger.WHEN_ATTACKING:
			return bool(ctx.get("attacking", false))
		Trigger.WHEN_DEFENDING:
			return not bool(ctx.get("attacking", false))
		Trigger.WHEN_HP_LOW:
			return float(ctx.get("hp_ratio", 1.0)) <= float(skill.get("threshold", 0.5))
		Trigger.WHEN_HP_FULL:
			return float(ctx.get("hp_ratio", 1.0)) >= 1.0
		Trigger.ON_TERRAIN:
			return int(ctx.get("terrain_def", 0)) > 0
		Trigger.VS_FLYING:
			return bool(ctx.get("vs_flying", false)) and bool(ctx.get("attacking", false))
	return false


## Somme des modificateurs des compétences actives dans ce contexte.
## [returns] {hit, crit, avoid, crit_avoid, damage, defense}
static func aggregate(skill_ids: Array, ctx: Dictionary) -> Dictionary:
	var total: Dictionary = {}
	for key: String in MOD_KEYS:
		total[key] = 0

	for id in skill_ids:
		var skill_id: String = str(id)
		if not is_active(skill_id, ctx):
			continue
		var mods: Dictionary = get_skill(skill_id).get("mods", {})
		for key in mods:
			if total.has(key):
				total[key] = int(total[key]) + int(mods[key])
	return total


## Compétences à déclenchement disponibles dans ce contexte, avec leur chance.
## [param skl] Skill de l'unité — sert au calcul de la probabilité.
## [returns] [{id, proc, chance}]
static func active_procs(skill_ids: Array, ctx: Dictionary, skl: int) -> Array:
	var procs: Array = []
	for id in skill_ids:
		var skill_id: String = str(id)
		var skill: Dictionary = get_skill(skill_id)
		if skill.is_empty() or int(skill.get("kind", Kind.PASSIVE)) != Kind.ACTIVE:
			continue
		if not is_active(skill_id, ctx):
			continue
		procs.append({
			"id": skill_id,
			"proc": str(skill.get("proc", "")),
			"chance": clampi(int(round(float(skl) * float(skill.get("chance_ratio", 1.0)))), 0, 100),
		})
	return procs
