class_name SkillUse
extends RefCounted
## Résolution des compétences utilisables — celles qu'on lance depuis le menu.
##
## Le pendant « sort » du bâton de soin. [SkillDB] dit ce qu'une compétence
## [constant SkillDB.Kind.USABLE] [i]est[/i] ; ce service dit ce qu'elle
## [i]fait[/i] à deux fiches ([Stats]), et rien de plus.
##
## [b]Aucun nœud, aucune scène, aucun tirage.[/b] C'est délibéré, et c'est ce qui
## rend le bouton « Compétence » vérifiable en `--headless` : le choix de la
## cible, le chiffre, l'affliction et le coût se contrôlent sur deux [Stats]
## posées côte à côte, sans bataille montée ni caméra. Ce qui a besoin de pions —
## la portée mesurée en cases, les éclats, le journal — vit chez l'appelant
## ([TacticsPawnCombatService.use_skill_on]).
##
## [b]Pourquoi pas de dé.[/b] Une compétence lancée à la main touche toujours :
## elle a déjà coûté le tour de l'unité, et la manquer sur un jet de précision
## rendrait le bouton inutilisable dès qu'il compte. Les procs aléatoires
## ([constant SkillDB.Kind.ACTIVE]) tiennent l'autre bout de ce choix.

const SKILLS = preload("res://data/models/world/stats/skill_db.gd")
const STATUS_DB = preload("res://data/models/world/stats/status_db.gd")
const WT = preload("res://data/models/world/stats/weapon_type.gd")

## Plancher de dégâts d'une compétence offensive.
##
## Comme le triangle des armes dans [FECombatCalculator] : une compétence lancée
## sciemment, qui coûte le tour, ne doit jamais rendre zéro. Sinon le joueur paie
## son tour pour un message vide.
const MIN_DAMAGE: int = 1

## Diviseur de la Magie dans un soin. Le même que celui du bâton
## ([method TacticsPawnCombatService._resolve_heal]) : une clerc ne doit pas
## soigner deux fois mieux selon le bouton qu'elle a pressé.
const HEAL_MAG_DIVISOR: int = 3


#region Ciblage
## Le camp de la cible convient-il à cette compétence ?
##
## [param same_team] La cible est-elle dans le camp du lanceur ?
## Une compétence « self » n'accepte que le lanceur lui-même : c'est
## [method can_target] du dessus qui le vérifie, ici on ne juge que le camp.
static func accepts_side(skill_id: String, same_team: bool) -> bool:
	match SKILLS.target_of(skill_id):
		SKILLS.TARGET_SELF, SKILLS.TARGET_ALLY:
			return same_team
	return not same_team


## La compétence vise-t-elle son lanceur, sans passer par un ciblage ?
static func targets_self(skill_id: String) -> bool:
	return SKILLS.target_of(skill_id) == SKILLS.TARGET_SELF


## Cette cible est-elle légale : bon camp, bonne distance, encore debout ?
##
## [param distance] Distance de grille (Manhattan) entre le lanceur et la cible.
static func can_target(skill_id: String, same_team: bool, distance: int) -> bool:
	if not SKILLS.is_usable(skill_id):
		return false
	if not accepts_side(skill_id, same_team):
		return false
	return distance >= 0 and distance <= SKILLS.range_of(skill_id)
#endregion


#region Chiffres
## Dégâts d'une compétence offensive sur cette cible.
##
## La compétence apporte sa part fixe (`power`), la fiche du lanceur le reste :
## une Frappe venimeuse fait mal parce que le sorcier est puissant, pas parce
## qu'elle est écrite en gros dans le catalogue. La défense opposée est celle du
## calculateur de combat — magique contre RÉS, physique contre DÉF — de sorte
## qu'une compétence ne contourne pas l'armure que l'arme respecte.
##
## [param terrain_def] Bonus défensif de la case occupée par la cible.
static func damage_of(skill_id: String, user: Stats, target: Stats, terrain_def: int = 0) -> int:
	if not user or not target:
		return 0
	var magical: bool = WT.is_magical(user.weapon_type)
	var attack: int = SKILLS.power_of(skill_id) + user.get_attack_stat()
	var defense: int = target.get_defense(magical) + terrain_def
	return maxi(MIN_DAMAGE, attack - defense)


## PV réellement rendus par une compétence de soin (jamais au-delà du plein).
static func heal_of(skill_id: String, user: Stats, target: Stats) -> int:
	if not user or not target:
		return 0
	var amount: int = SKILLS.power_of(skill_id) \
		+ int(user.effective("mag") / float(HEAL_MAG_DIVISOR))
	return mini(amount, maxi(0, target.max_hp - target.hp))
#endregion


#region Résolution
## Ce que la compétence ferait ici, sans rien appliquer.
##
## La prévision et l'exécution passent par la même fonction : sans cela, l'encart
## affiché avant de valider finirait par mentir d'un point ou deux.
##
## [returns] {ok, reason, skill, effect, amount, status, turns, ends_turn}
static func preview(skill_id: String, user: Stats, target: Stats,
		terrain_def: int = 0) -> Dictionary:
	var report: Dictionary = {
		"ok": false, "reason": "", "skill": skill_id,
		"effect": "", "amount": 0, "status": "", "turns": 0,
		"ends_turn": SKILLS.costs_action(skill_id),
	}
	if not SKILLS.is_usable(skill_id):
		report["reason"] = "compétence inconnue ou non utilisable"
		return report
	if not user or not target:
		report["reason"] = "cible manquante"
		return report
	if target.hp <= 0:
		report["reason"] = "la cible est déjà à terre"
		return report

	var effect: String = SKILLS.effect_of(skill_id)
	report["effect"] = effect
	match effect:
		SKILLS.EFFECT_HEAL:
			report["amount"] = heal_of(skill_id, user, target)
		SKILLS.EFFECT_DAMAGE:
			report["amount"] = damage_of(skill_id, user, target, terrain_def)

	# L'affliction voyage avec les dégâts autant qu'elle peut voyager seule : une
	# Frappe venimeuse blesse *et* empoisonne, un sort de paralysie ne fait que
	# paralyser. Une seule clé pour les deux cas, remplie dès que le catalogue
	# nomme un statut connu.
	var status: String = SKILLS.status_of(skill_id)
	if STATUS_DB.exists(status):
		report["status"] = status
		var turns: int = SKILLS.status_turns_of(skill_id)
		report["turns"] = turns if turns > 0 else STATUS_DB.default_turns(status)

	report["ok"] = true
	return report


## Applique la compétence sur les deux fiches, et rend le compte rendu.
##
## L'affliction passe par [method Stats.suffer_status] et non par la porte brute :
## c'est là que le sang-froid ([SkillDB]) a son mot à dire, exactement comme pour
## une arme venimeuse. Une compétence lancée ne doit pas être le seul chemin qui
## ignore les défenses de la cible.
##
## [returns] le dictionnaire de [method preview], enrichi de `hp` (les PV de la
## cible après coup), `warded` et `fell`.
static func resolve(skill_id: String, user: Stats, target: Stats,
		terrain_def: int = 0) -> Dictionary:
	var report: Dictionary = preview(skill_id, user, target, terrain_def)
	report["hp"] = target.hp if target else 0
	report["warded"] = false
	report["fell"] = false
	if not bool(report["ok"]):
		return report

	var amount: int = int(report["amount"])
	match str(report["effect"]):
		SKILLS.EFFECT_HEAL:
			if amount > 0:
				target.apply_to_curr_health(amount)
		SKILLS.EFFECT_DAMAGE:
			if amount > 0:
				target.apply_to_curr_health(-amount)

	# L'affliction après les dégâts, et seulement sur ce qui respire encore :
	# la même règle qu'un coup venimeux ([TacticsPawnCombatService._try_afflict]).
	if not str(report["status"]).is_empty() and target.hp > 0:
		var applied: Dictionary = target.suffer_status(
			str(report["status"]), int(report["turns"]))
		report["warded"] = bool(applied.get("warded", false))
		if bool(applied.get("ok", false)):
			report["turns"] = int(applied["turns"])
		else:
			report["turns"] = 0

	report["hp"] = target.hp
	report["fell"] = target.hp <= 0
	return report
#endregion


## Le compte rendu mis en une ligne, pour le journal et la console.
static func describe(user_name: String, target_name: String, report: Dictionary) -> String:
	if not bool(report.get("ok", false)):
		return "%s ne peut pas lancer %s : %s" % [
			user_name, SKILLS.get_skill_name(str(report.get("skill", ""))),
			str(report.get("reason", "")),
		]

	var skill_name: String = SKILLS.get_skill_name(str(report["skill"]))
	var line: String = ""
	match str(report["effect"]):
		SKILLS.EFFECT_HEAL:
			line = "✨ %s — %s soigne %s de %d PV (%d PV)" % [
				skill_name, user_name, target_name, int(report["amount"]), int(report["hp"])]
		SKILLS.EFFECT_DAMAGE:
			line = "✨ %s — %s frappe %s : %d dégâts (%d PV)" % [
				skill_name, user_name, target_name, int(report["amount"]), int(report["hp"])]
		_:
			line = "✨ %s — %s vise %s" % [skill_name, user_name, target_name]

	var status: String = str(report.get("status", ""))
	if not status.is_empty() and int(report.get("turns", 0)) > 0:
		line += " | %s %s %d tour(s)" % [
			STATUS_DB.glyph(status), STATUS_DB.label(status), int(report["turns"])]
	elif not status.is_empty():
		line += " | 🛡 %s repoussé" % STATUS_DB.label(status)
	return line
