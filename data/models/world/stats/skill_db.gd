class_name SkillDB
extends RefCounted
## Compétences de classe — passives conditionnelles et compétences à déclenchement.
##
## Logique pure : le calculateur de combat demande l'agrégat des modificateurs
## pour un contexte donné (attaque/défense, PV restants, terrain, cible volante)
## et applique le résultat. Les compétences se débloquent par classe et par niveau
## dans [ClassDataDB].
##
## Certaines compétences débordent de la table des modificateurs : elles posent
## une affliction ([StatusDB]), en raccourcissent une, ou rendent des PV entre
## deux tours. Elles restent déclarées ici, avec leurs propres clés — `status`,
## `status_ward`, `regen` — et leurs propres agrégateurs plus bas.
##
## [b]Trois natures, un seul catalogue.[/b] Une passive pèse sur chaque calcul,
## une compétence à déclenchement se tire au sort pendant l'échange, et une
## compétence [i]utilisable[/i] ([constant Kind.USABLE]) ne fait rien tant que le
## joueur ne la lance pas depuis le menu d'actions. Les trois cohabitent ici parce
## qu'elles se débloquent de la même façon, s'affichent sur la même fiche et se
## cochent dans le même éditeur ; ce qui les sépare, c'est [b]qui les appelle[/b].
## Une utilisable n'est jamais agrégée ni tirée : son déclencheur
## ([constant Trigger.ON_COMMAND]) n'est vrai dans aucun contexte de combat, donc
## [method is_active] la refuse partout. Sa résolution vit dans [SkillUse].

const STATUS_DB = preload("res://data/models/world/stats/status_db.gd")

enum Kind {
	PASSIVE = 0,  ## Modificateurs permanents ou conditionnels
	ACTIVE = 1,   ## Déclenchement aléatoire pendant le combat (proc)
	USABLE = 2,   ## Lancée à la demande, depuis le menu d'actions
}

enum Trigger {
	ALWAYS = 0,          ## Toujours actif
	WHEN_ATTACKING = 1,  ## Seulement quand l'unité initie l'attaque
	WHEN_DEFENDING = 2,  ## Seulement quand l'unité subit l'attaque
	WHEN_HP_LOW = 3,     ## PV sous un seuil (ratio)
	WHEN_HP_FULL = 4,    ## PV au maximum
	ON_TERRAIN = 5,      ## Sur une case au bonus défensif
	VS_FLYING = 6,       ## Contre une unité volante
	ON_COMMAND = 7,      ## Jamais d'elle-même : le joueur la lance
}

#region Compétences utilisables
## Ce qu'une compétence utilisable ([constant Kind.USABLE]) vise.
const TARGET_SELF: String = "self"
const TARGET_ALLY: String = "ally"
const TARGET_ENEMY: String = "enemy"

## Ce qu'elle fait à sa cible. `damage` peut poser une affliction en plus, quand
## la compétence déclare un `status` — c'est le cas de « Frappe venimeuse ».
const EFFECT_DAMAGE: String = "damage"
const EFFECT_HEAL: String = "heal"
const EFFECT_STATUS: String = "status"

## Ce qu'elle coûte. `action` clôt le tour de l'unité, comme frapper ou soigner ;
## une compétence sans coût déclaré ne prend que le droit d'attaquer.
const COST_ACTION: String = "action"
#endregion

## Modificateurs reconnus par le calculateur de combat
const MOD_KEYS: Array[String] = ["hit", "crit", "avoid", "crit_avoid", "damage", "defense"]

## Abréviation de chaque modificateur, pour les affichages serrés.
##
## Les mêmes mots que la fiche d'unité ([UnitSheet]) : « Préc », « Crit », « Esq ».
## L'étiquette de survol ([EnemyPeekPanel]) n'a la place que de ceux-là.
const MOD_SHORT: Dictionary = {
	"hit": "Préc", "crit": "Crit", "avoid": "Esq", "crit_avoid": "ÉvCrit",
	"damage": "Dég", "defense": "Déf",
}

## Ce que fait une compétence à déclenchement, en deux mots.
const PROC_SHORT: Dictionary = {
	"pierce": "perce l'armure",
	"extra_hit": "frappe en plus",
	"inflict": "afflige la cible",
}

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

	# --- Compétences affligeantes ---
	# Même mécanique que « Lune » et « Astre » : un `proc` tiré à chaque coup
	# porté. Seul l'effet change — au lieu d'ajouter des dégâts immédiats, il pose
	# une affliction ([StatusDB]) qui survit à l'échange.
	#
	# La chance est ici **fixe** (`chance`) et non calculée sur l'Adresse : un
	# poison qui tomberait deux fois plus souvent sur un bretteur que sur un mage
	# ferait de la compétence une prime à l'Adresse, alors que ce qu'elle apporte
	# — du temps volé à l'adversaire — vaut la même chose pour tout le monde.
	#
	# Les durées sont plus courtes que celles des armes équivalentes : la
	# compétence est acquise pour de bon, l'arme se paie et s'use.
	"venom": {
		"name": "Venin",
		"desc": "35 % de chances d'empoisonner la cible pour 3 tours.",
		"kind": Kind.ACTIVE,
		"trigger": Trigger.WHEN_ATTACKING,
		"proc": "inflict",
		"status": "poison",
		"status_turns": 3,
		"chance": 35,
	},
	"ember": {
		"name": "Braise",
		"desc": "35 % de chances de brûler la cible pour 2 tours.",
		"kind": Kind.ACTIVE,
		"trigger": Trigger.WHEN_ATTACKING,
		"proc": "inflict",
		"status": "burn",
		"status_turns": 2,
		"chance": 35,
	},
	# La paralysie vole un tour entier : elle tombe rarement, comme pour la lance
	# fulgurante ([WeaponDB]), sans quoi elle déciderait seule de la bataille.
	"jolt": {
		"name": "Décharge",
		"desc": "20 % de chances de paralyser la cible pour 1 tour.",
		"kind": Kind.ACTIVE,
		"trigger": Trigger.WHEN_ATTACKING,
		"proc": "inflict",
		"status": "paralyze",
		"status_turns": 1,
		"chance": 20,
	},

	# --- Compétences utilisables ---
	# Ni permanentes ni tirées au sort : le joueur les lance depuis le menu
	# d'actions, choisit sa cible, et l'unité y passe son tour. C'est le pendant
	# « sort » du bâton de soin — sauf qu'il ne demande aucune arme, seulement
	# d'avoir appris la compétence.
	#
	# Le contrat est le même pour toutes : `target` dit qui est visable, `effect`
	# ce qui arrive à la cible, `power` la part fixe du chiffre (le reste vient de
	# la fiche du lanceur), `range` la portée en cases, `cost` ce que ça coûte.
	# [SkillUse] est seul à savoir les résoudre ; ici on ne fait que les déclarer.
	"venom_strike": {
		"name": "Frappe venimeuse",
		"desc": "Frappe un ennemi adjacent et l'empoisonne pour 3 tours.",
		"kind": Kind.USABLE,
		"trigger": Trigger.ON_COMMAND,
		"target": TARGET_ENEMY,
		"effect": EFFECT_DAMAGE,
		"power": 6,
		"range": 1,
		"status": "poison",
		"status_turns": 3,
		"cost": COST_ACTION,
	},
	"mend": {
		"name": "Soin",
		"desc": "Rend des PV à un allié adjacent, sans dépenser de bâton.",
		"kind": Kind.USABLE,
		"trigger": Trigger.ON_COMMAND,
		"target": TARGET_ALLY,
		"effect": EFFECT_HEAL,
		"power": 8,
		"range": 1,
		"cost": COST_ACTION,
	},

	# --- Compétences défensives hors table de modificateurs ---
	"cold_blood": {
		"name": "Sang-froid",
		"desc": "Toute affliction subie dure un tour de moins ; celle d'un seul tour ne prend pas.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.ALWAYS,
		"mods": {},
		"status_ward": 1,
	},
	"regeneration": {
		"name": "Régénération",
		"desc": "Rend 3 PV au début de chaque tour, sous 50 % de PV.",
		"kind": Kind.PASSIVE,
		"trigger": Trigger.WHEN_HP_LOW,
		"threshold": 0.5,
		"mods": {},
		"regen": 3,
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


#region Compétences utilisables — lecture du catalogue
## La compétence se lance-t-elle à la demande ?
static func is_usable(skill_id: String) -> bool:
	return int(get_skill(skill_id).get("kind", Kind.PASSIVE)) == Kind.USABLE


## Celles de [param skill_ids] qui se lancent à la demande, dans l'ordre donné.
##
## C'est ce que le menu d'actions liste, et ce qui décide si le bouton
## « Compétence » a lieu d'exister pour cette unité.
static func usable_ids(skill_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in skill_ids:
		var skill_id: String = str(id)
		if is_usable(skill_id) and not skill_id in out:
			out.append(skill_id)
	return out


## Qui la compétence peut viser : "self", "ally" ou "enemy" (ennemi par défaut).
static func target_of(skill_id: String) -> String:
	return str(get_skill(skill_id).get("target", TARGET_ENEMY))


## Ce qu'elle fait à sa cible : "damage", "heal" ou "status".
static func effect_of(skill_id: String) -> String:
	return str(get_skill(skill_id).get("effect", EFFECT_DAMAGE))


## Part fixe du chiffre — dégâts ou PV rendus avant l'apport de la fiche.
static func power_of(skill_id: String) -> int:
	return int(get_skill(skill_id).get("power", 0))


## Portée en cases (1 = au contact).
static func range_of(skill_id: String) -> int:
	return maxi(1, int(get_skill(skill_id).get("range", 1)))


## L'affliction posée, "" si la compétence n'en pose aucune.
static func status_of(skill_id: String) -> String:
	return str(get_skill(skill_id).get("status", ""))


## Durée de l'affliction posée (0 : celle du catalogue des statuts).
static func status_turns_of(skill_id: String) -> int:
	return int(get_skill(skill_id).get("status_turns", 0))


## La compétence coûte-t-elle le tour entier, ou seulement le droit de frapper ?
static func costs_action(skill_id: String) -> bool:
	return str(get_skill(skill_id).get("cost", "")) == COST_ACTION
#endregion


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
		Trigger.ON_COMMAND:
			return "Sur ordre, depuis le menu d'actions"
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
	match int(skill.get("kind", Kind.PASSIVE)):
		Kind.ACTIVE:
			lines.append("⟶ Déclenchement aléatoire, une chance par coup porté.")
		Kind.USABLE:
			lines.append("⟶ Portée %d · %s" % [range_of(skill_id), _target_label(skill_id)])
			lines.append("⟶ %s" % ("Consomme le tour" if costs_action(skill_id)
				else "Consomme l'attaque"))
	return "\n".join(lines)


## Qui la compétence vise, en toutes lettres.
static func _target_label(skill_id: String) -> String:
	match target_of(skill_id):
		TARGET_SELF:
			return "sur soi"
		TARGET_ALLY:
			return "sur un allié"
	return "sur un ennemi"


## Effet chiffré d'une compétence, en une poignée de caractères.
##
## « +10 Préc +5 Crit » pour une passive, « perce l'armure » pour une compétence
## à déclenchement. C'est [method describe] compressé : la phrase entière tient
## dans une info-bulle qu'on ouvre, pas dans une étiquette qui suit le curseur.
##
## Rend "" pour une compétence inconnue — l'appelant n'affiche alors aucune ligne.
static func short_effect(skill_id: String) -> String:
	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return ""

	# Une compétence utilisable se lit à son chiffre et à sa portée : c'est tout
	# ce qu'il faut pour décider de la lancer ou non depuis le menu d'actions.
	if int(skill.get("kind", Kind.PASSIVE)) == Kind.USABLE:
		var bits: Array[String] = []
		match effect_of(skill_id):
			EFFECT_HEAL:
				bits.append("+%d PV" % power_of(skill_id))
			EFFECT_DAMAGE:
				bits.append("%d dégâts" % power_of(skill_id))
		var afflicts: String = status_of(skill_id)
		if STATUS_DB.exists(afflicts):
			bits.append("%s %s" % [STATUS_DB.glyph(afflicts), STATUS_DB.label(afflicts)])
		bits.append("portée %d" % range_of(skill_id))
		return " ".join(bits)

	if int(skill.get("kind", Kind.PASSIVE)) == Kind.ACTIVE:
		# Une compétence affligeante se lit à son affliction, pas à son verbe :
		# « ☠ Poison 35 % » dit tout ce qu'il faut savoir avant d'engager, là où
		# « afflige la cible » obligerait à ouvrir la bulle pour savoir quoi.
		var status: String = str(skill.get("status", ""))
		if str(skill.get("proc", "")) == "inflict" and STATUS_DB.exists(status):
			return "%s %s %d%%" % [
				STATUS_DB.glyph(status), STATUS_DB.label(status), proc_chance(skill_id, 0),
			]
		return str(PROC_SHORT.get(str(skill.get("proc", "")), "effet spécial"))

	var mods: Dictionary = skill.get("mods", {})
	var parts: Array[String] = []
	# Dans l'ordre du catalogue, pas dans celui du dictionnaire : deux unités
	# portant la même compétence doivent la lire de la même façon.
	for key: String in MOD_KEYS:
		if mods.has(key):
			parts.append("%+d %s" % [int(mods[key]), str(MOD_SHORT[key])])

	# Les effets qui ne se comptent ni en points de précision ni en points de
	# dégâts. Ils n'ont pas leur place dans [constant MOD_KEYS] — un tour n'est
	# pas un point — mais ils doivent se lire quelque part.
	var ward: int = int(skill.get("status_ward", 0))
	if ward > 0:
		parts.append("−%d tour%s d'affliction" % [ward, "" if ward <= 1 else "s"])
	var regen: int = int(skill.get("regen", 0))
	if regen > 0:
		parts.append("+%d PV/tour" % regen)
	return " ".join(parts)


## Quand la compétence joue, en un mot — "" quand elle joue toujours.
##
## Le pendant court de [method trigger_label] : « attaque », « défense »,
## « PV < 50 % ». Une passive permanente ne dit rien, sa ligne serait du bruit.
static func short_trigger(skill_id: String) -> String:
	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return ""
	match int(skill.get("trigger", Trigger.ALWAYS)):
		Trigger.WHEN_ATTACKING:
			return "attaque"
		Trigger.WHEN_DEFENDING:
			return "défense"
		Trigger.WHEN_HP_LOW:
			return "PV < %d %%" % int(round(float(skill.get("threshold", 0.5)) * 100.0))
		Trigger.WHEN_HP_FULL:
			return "PV pleins"
		Trigger.ON_TERRAIN:
			return "terrain"
		Trigger.VS_FLYING:
			return "vs vol"
		Trigger.ON_COMMAND:
			return "sur ordre"
	return ""


## Une compétence en une ligne : nom, effet, condition.
##
## « Duelliste  +10 Préc · attaque ». C'est la forme que lit le bestiaire
## ([EnemyPeekPanel]) : de quoi juger un échange d'un coup d'œil, sans ouvrir la
## fiche complète. "" pour une compétence inconnue.
static func summary(skill_id: String) -> String:
	var skill: Dictionary = get_skill(skill_id)
	if skill.is_empty():
		return ""
	var line: String = str(skill.get("name", skill_id))
	var effect: String = short_effect(skill_id)
	if not effect.is_empty():
		line += "  %s" % effect
	var when: String = short_trigger(skill_id)
	if not when.is_empty():
		line += " · %s" % when
	return line


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


## Probabilité de déclenchement d'une compétence, en pourcents (0 à 100).
##
## Deux façons de la déclarer, et une seule règle pour les départager : une
## compétence qui porte `chance` a un taux [b]fixe[/b], les autres tirent le leur
## de l'Adresse ([param skl] × `chance_ratio`). Les deux voies existent parce que
## les deux effets ne se valent pas — un coup mieux porté récompense l'adresse,
## un poison ne récompense rien, il dure.
static func proc_chance(skill_id: String, skl: int) -> int:
	var skill: Dictionary = get_skill(skill_id)
	if skill.has("chance"):
		return clampi(int(skill["chance"]), 0, 100)
	return clampi(int(round(float(skl) * float(skill.get("chance_ratio", 1.0)))), 0, 100)


## Compétences à déclenchement disponibles dans ce contexte, avec leur chance.
## [param skl] Skill de l'unité — sert au calcul de la probabilité.
## [returns] [{id, proc, chance, status, status_turns}] — les deux derniers champs
## ne portent quelque chose que pour un `proc` « inflict ».
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
			"chance": proc_chance(skill_id, skl),
			"status": str(skill.get("status", "")),
			"status_turns": int(skill.get("status_turns", 0)),
		})
	return procs


## Tours retranchés à une affliction entrante par ces compétences.
##
## Le pendant défensif de [method active_procs] : là où une compétence
## affligeante ajoute des tours d'agonie, une compétence de sang-froid en retire.
## Le total est la somme de toutes celles qui jouent dans ce contexte.
static func status_ward(skill_ids: Array, ctx: Dictionary) -> int:
	var total: int = 0
	for id in skill_ids:
		var skill_id: String = str(id)
		if is_active(skill_id, ctx):
			total += int(get_skill(skill_id).get("status_ward", 0))
	return total


## Durée réellement subie d'une affliction, une fois le sang-froid déduit.
##
## Rend 0 quand l'affliction est entièrement repoussée : une paralysie d'un seul
## tour ne prend pas sur qui en retranche un. C'est délibérément une immunité
## partielle — elle protège de ce qui est bref, pas de ce qui s'installe.
##
## [param turns] Durée voulue, déjà résolue : à l'appelant d'avoir remplacé un 0
## par la durée par défaut du catalogue, ce service-ci ne connaît pas le tempo
## de chaque affliction.
static func warded_turns(skill_ids: Array, ctx: Dictionary, turns: int) -> int:
	if turns <= 0:
		return 0
	return maxi(0, turns - status_ward(skill_ids, ctx))


## PV rendus au début du tour par les compétences de régénération.
static func regeneration(skill_ids: Array, ctx: Dictionary) -> int:
	var total: int = 0
	for id in skill_ids:
		var skill_id: String = str(id)
		if is_active(skill_id, ctx):
			total += int(get_skill(skill_id).get("regen", 0))
	return total
