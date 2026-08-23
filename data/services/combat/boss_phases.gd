class_name BossPhases
extends RefCounted
## Bascules de phase d'un boss — quand elles tombent, et une seule fois chacune.
##
## [b]Logique pure, et c'est tout l'intérêt.[/b] Ce service ne connaît ni pion, ni
## nœud, ni écran : il prend des PV et une liste de phases déjà franchies, et rend
## les phases que ce coup-ci vient de franchir. On peut donc dérouler un boss
## entier en `--headless` — le mordre à 61 %, puis à 59 %, puis à 10 % — et lire
## exactement ce qui se serait déclenché, sans monter la moindre bataille.
##
## Le même découpage que les afflictions : [BossDB] dit ce qu'un boss [i]est[/i],
## ce service dit [i]quand[/i] ses phases tombent, et [method Stats.advance_boss_phases]
## reporte ces décisions sur une unité réelle.
##
## [b]Une phase franchie l'est pour toujours.[/b] L'état tient dans une liste
## d'indices — la même forme que les afflictions de [StatusEffects] et pour la
## même raison : elle traverse le JSON d'un instantané de bataille sans y perdre
## son sens, et un boss soigné au-dessus de son seuil ne rejoue pas sa rage.

const DB = preload("res://data/models/world/stats/boss_db.gd")
const SKILL_DB = preload("res://data/models/world/stats/skill_db.gd")

## Seuil le plus haut recevable. Une phase à 1.0 tomberait au premier coup —
## avant même qu'on ait vu le boss encaisser quoi que ce soit.
const MAX_THRESHOLD: float = 0.99

## Fraction maximale de PV qu'une phase peut rendre.
##
## Un boss qui se rend tous ses PV n'est pas un boss, c'est un mur : le combat
## repart à zéro et rien de ce que le joueur a fait ne compte plus.
const MAX_HEAL: float = 0.5


#region Lecture du catalogue
## Remet une liste de phases en état connu : seuils bornés et triés du plus haut
## au plus bas, gains filtrés, compétences inconnues écartées.
##
## Le point d'entrée obligé de tout ce qui vient du dehors — le catalogue, un
## chapitre, une fiche écrite à la main. Rien n'entre sans passer ici.
##
## Le tri décroissant n'est pas cosmétique : c'est lui qui donne son indice à
## chaque phase, et cet indice est ce qu'on mémorise comme « déjà franchie ».
## Deux phases écrites dans le désordre donneraient sinon deux numérotations
## différentes selon l'ordre de lecture.
static func sanitize(entries: Array) -> Array:
	var out: Array = []
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var phase: Dictionary = raw
		var threshold: float = clampf(float(phase.get("threshold", 0.0)), 0.0, MAX_THRESHOLD)
		if threshold <= 0.0:
			continue  # Une phase sous zéro PV ne tombe jamais.

		var gains: Dictionary = {}
		var declared: Variant = phase.get("gains", {})
		if declared is Dictionary:
			for key: String in DB.GAIN_KEYS:
				var amount: int = int((declared as Dictionary).get(key, 0))
				if amount != 0:
					gains[key] = amount

		var skills: Array[String] = []
		var wanted: Variant = phase.get("skills", [])
		if wanted is Array:
			for id: Variant in wanted:
				var skill_id: String = str(id)
				if SKILL_DB.exists(skill_id) and not skill_id in skills:
					skills.append(skill_id)

		out.append({
			"threshold": threshold,
			"label": str(phase.get("label", "")),
			"message": str(phase.get("message", "")),
			"gains": gains,
			"heal": clampf(float(phase.get("heal", 0.0)), 0.0, MAX_HEAL),
			"skills": skills,
			"cure": bool(phase.get("cure", false)),
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["threshold"]) > float(b["threshold"]))
	if out.size() > DB.MAX_PHASES:
		out = out.slice(0, DB.MAX_PHASES)

	# L'indice est posé après le tri : c'est l'identité durable de la phase.
	for i: int in out.size():
		out[i]["index"] = i
	return out


## Phases d'un boss du catalogue, triées et nettoyées. Vide s'il est inconnu.
static func phases_of(boss_id: String) -> Array:
	return sanitize(DB.raw_phases(boss_id))


## Nombre de phases déclarées pour ce boss (0 = ce n'en est pas un).
static func phase_count(boss_id: String) -> int:
	return phases_of(boss_id).size()


## Cet identifiant désigne-t-il un boss réellement doté de phases ?
##
## Plus strict que [method BossDB.exists] à dessein : une entrée de catalogue
## sans phase recevable ne mérite pas de couronne, et surtout ne doit pas faire
## afficher « Phase 1/0 » sur une fiche d'unité.
static func is_boss(boss_id: String) -> bool:
	return phase_count(boss_id) > 0
#endregion


#region Bascules
## Remet une liste d'indices franchis en état connu : entiers, hors bornes
## écartés, doublons fondus, triés.
static func sanitize_cleared(cleared: Array, total: int) -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in cleared:
		var index: int = int(raw)
		if index >= 0 and index < total and not index in out:
			out.append(index)
	out.sort()
	return out


## Les phases que ces PV viennent de franchir, et rien d'autre.
##
## Une phase tombe quand les PV passent [b]sous ou sur[/b] son seuil et qu'elle
## n'était pas déjà franchie. Un seul coup peut en franchir plusieurs — un
## critique qui emmène le boss de 70 % à 20 % déclenche les deux, dans l'ordre :
## masquer la première parce que la seconde est tombée volerait au joueur la
## moitié de ce qu'il vient de provoquer.
##
## [b]Un boss mort ne bascule pas.[/b] Le coup de grâce n'a pas à réveiller une
## rage : la phase ne servirait qu'à faire mentir le journal, et le soin qu'elle
## porte ressusciterait une unité que tout le reste du jeu tient pour tombée.
##
## [param cleared] Indices des phases déjà franchies.
## [returns] {
##   phases: Array,       ## celles qui viennent de tomber, du seuil haut au bas
##   cleared: Array[int], ## la liste à mémoriser en retour
##   ratio: float,        ## PV restants, en fraction
## }
static func triggered(boss_id: String, hp: int, max_hp: int, cleared: Array) -> Dictionary:
	var phases: Array = phases_of(boss_id)
	var known: Array[int] = sanitize_cleared(cleared, phases.size())
	var ratio: float = float(hp) / float(maxi(1, max_hp))

	if phases.is_empty() or hp <= 0:
		return {"phases": [], "cleared": known, "ratio": maxf(0.0, ratio)}

	var fired: Array = []
	for phase: Dictionary in phases:
		var index: int = int(phase["index"])
		if index in known:
			continue
		if ratio > float(phase["threshold"]):
			continue
		known.append(index)
		fired.append(phase.duplicate(true))

	known.sort()
	return {"phases": fired, "cleared": known, "ratio": ratio}


## Numéro de la forme courante, à partir des phases déjà franchies.
##
## 1 est la forme initiale : un boss à trois phases déclarées se lit donc
## « 1/3 » tant qu'il n'a rien franchi, et « 3/3 » une fois tout tombé.
static func phase_number(cleared: Array, total: int) -> int:
	return sanitize_cleared(cleared, total).size() + 1


## Ce que la fiche d'unité affiche : « Phase 2/3 — Rage ».
##
## Rend "" pour qui n'est pas un boss — l'appelant n'écrit alors aucune ligne,
## comme [method StatusEffects.summary] pour une unité saine.
static func label_for(boss_id: String, cleared: Array) -> String:
	var phases: Array = phases_of(boss_id)
	if phases.is_empty():
		return ""

	var known: Array[int] = sanitize_cleared(cleared, phases.size())
	var total: int = phases.size() + 1  # Les bascules, plus la forme initiale.
	var line: String = "Phase %d/%d" % [known.size() + 1, total]

	# Le nom de la dernière phase franchie, quand elle en porte un : c'est lui
	# qui dit au joueur *pourquoi* les chiffres qu'il lit ont changé. On le prend
	# à l'indice le plus haut et non au compte : les deux coïncident tant que les
	# bascules tombent dans l'ordre, mais un instantané relu n'a pas à en dépendre.
	if not known.is_empty():
		var last: String = str(phases[known[known.size() - 1]]["label"])
		if not last.is_empty():
			line += " — %s" % last
	return line


## Ce qu'une phase apporte, en une ligne : « FOR +3  ·  HAB +2  ·  ✨ Fureur ».
##
## Le pendant de [method StatusEffects.summary] : le journal et la console y
## lisent le détail sans avoir à le recomposer chacun de son côté.
static func effects_summary(phase: Dictionary) -> String:
	var parts: Array[String] = []
	var gains: Dictionary = phase.get("gains", {})
	for key: String in DB.GAIN_KEYS:
		if gains.has(key):
			parts.append("%s %+d" % [key.to_upper(), int(gains[key])])
	if float(phase.get("heal", 0.0)) > 0.0:
		parts.append("PV +%d%%" % int(round(float(phase["heal"]) * 100.0)))
	for skill_id: Variant in phase.get("skills", []):
		parts.append("✨ %s" % SKILL_DB.get_skill_name(str(skill_id)))
	if bool(phase.get("cure", false)):
		parts.append("afflictions levées")
	return "  ·  ".join(parts)
#endregion
