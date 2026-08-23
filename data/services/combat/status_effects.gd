class_name StatusEffects
extends RefCounted
## Résolution des effets de statut — pose, décompte, dégâts de début de tour.
##
## [b]Logique pure, et c'est tout l'intérêt.[/b] Ce service ne connaît ni pion,
## ni nœud, ni écran : il prend une liste d'afflictions et rend une liste
## d'afflictions. Une affliction est un dictionnaire `{status: String, turns: int}`
## — la même forme que les bonus temporaires de [Stats], et une forme qui traverse
## le JSON d'un instantané de bataille sans y perdre son sens.
##
## Ce découpage est ce qui rend le poison vérifiable en `--headless` : on peut
## empoisonner une liste, la faire vieillir dix tours et lire ce qu'elle est
## devenue, sans monter la moindre scène. [Stats] ne fait ensuite que reporter
## ces décisions sur une unité réelle ([method Stats.apply_status]).
##
## Le catalogue de ce qu'un statut inflige vit dans [StatusDB].

const DB = preload("res://data/models/world/stats/status_db.gd")


#region Lecture
## Remet une liste d'afflictions en état connu : statuts inconnus écartés,
## durées bornées, doublons fondus.
##
## Le point d'entrée obligé de tout ce qui vient du dehors — un instantané relu,
## une commande réseau, une fiche écrite à la main. Rien n'entre sans passer ici.
static func sanitize(entries: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var key: String = DB.canonical_key(str(entry.get("status", "")))
		if key.is_empty():
			continue
		var turns: int = clampi(int(entry.get("turns", 0)), 0, DB.MAX_TURNS)
		if turns <= 0:
			continue
		# Deux fois le même statut dans la même liste : on garde le plus long.
		if seen.has(key):
			var kept: Dictionary = out[int(seen[key])]
			kept["turns"] = maxi(int(kept["turns"]), turns)
			continue
		seen[key] = out.size()
		out.append({"status": key, "turns": turns})
	return out


## L'unité subit-elle ce statut ?
static func has(entries: Array, status: String) -> bool:
	return turns_left(entries, status) > 0


## Tours restants pour un statut donné (0 s'il n'est pas actif).
static func turns_left(entries: Array, status: String) -> int:
	var key: String = DB.canonical_key(status)
	if key.is_empty():
		return 0
	for raw: Variant in entries:
		if typeof(raw) == TYPE_DICTIONARY and str((raw as Dictionary).get("status", "")) == key:
			return int((raw as Dictionary).get("turns", 0))
	return 0


## Dégâts que ces afflictions infligeront au prochain début de tour.
##
## La somme de toutes : un empoisonné qui brûle paie les deux.
static func turn_damage(entries: Array) -> int:
	var total: int = 0
	for raw: Variant in entries:
		if typeof(raw) == TYPE_DICTIONARY:
			total += DB.damage(str((raw as Dictionary).get("status", "")))
	return total


## L'une de ces afflictions prive-t-elle l'unité de son tour ?
##
## Le nom diffère de [method StatusDB.blocks_action] à dessein : le catalogue
## répond pour [i]un[/i] statut, ce service pour la liste entière.
static func is_blocking(entries: Array) -> bool:
	for raw: Variant in entries:
		if typeof(raw) == TYPE_DICTIONARY \
				and DB.blocks_action(str((raw as Dictionary).get("status", ""))):
			return true
	return false


## Malus total appliqué à une statistique par ces afflictions (valeur négative).
static func stat_penalty(entries: Array, stat: String) -> int:
	var total: int = 0
	for raw: Variant in entries:
		if typeof(raw) == TYPE_DICTIONARY:
			total += DB.stat_mod(str((raw as Dictionary).get("status", "")), stat)
	return total


## Les afflictions en une ligne : « ☠ Poison (2)  ·  🔥 Brûlure (1) ».
## Rend "" quand l'unité est saine — l'appelant n'affiche alors aucune ligne.
static func summary(entries: Array) -> String:
	var parts: Array[String] = []
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var text: String = DB.short_label(str(entry.get("status", "")), int(entry.get("turns", 0)))
		if not text.is_empty():
			parts.append(text)
	return "  ·  ".join(parts)
#endregion


#region Pose et levée
## Pose une affliction sur une liste.
##
## [b]Les statuts ne s'empilent pas[/b] : un second coup empoisonné ne double pas
## les dégâts, il rallonge l'agonie. La durée retenue est la plus longue des deux
## — sinon un coup de grâce à une bagatelle de tours viendrait raccourcir un
## poison bien installé, ce qui serait un cadeau et non une aggravation.
##
## [param turns] 0 ou moins : la durée par défaut du catalogue s'applique.
## [returns] {entries, applied: bool, refreshed: bool, status: String, turns: int}
static func apply(entries: Array, status: String, turns: int = 0) -> Dictionary:
	var key: String = DB.canonical_key(status)
	var out: Array = sanitize(entries)
	if key.is_empty():
		return {"entries": out, "applied": false, "refreshed": false,
			"status": "", "turns": 0}

	var wanted: int = turns if turns > 0 else DB.default_turns(key)
	wanted = clampi(wanted, 1, DB.MAX_TURNS)

	for raw: Variant in out:
		var entry: Dictionary = raw
		if str(entry["status"]) != key:
			continue
		var before: int = int(entry["turns"])
		entry["turns"] = maxi(before, wanted)
		return {"entries": out, "applied": true, "refreshed": true,
			"status": key, "turns": int(entry["turns"])}

	out.append({"status": key, "turns": wanted})
	return {"entries": out, "applied": true, "refreshed": false,
		"status": key, "turns": wanted}


## Retire une affliction précise.
## [returns] {entries, removed: bool}
static func remove(entries: Array, status: String) -> Dictionary:
	var key: String = DB.canonical_key(status)
	var out: Array = []
	var removed: bool = false
	for raw: Variant in sanitize(entries):
		if str((raw as Dictionary)["status"]) == key:
			removed = true
			continue
		out.append(raw)
	return {"entries": out, "removed": removed}


## Lève toutes les afflictions — ce que fait un antidote.
## [returns] {entries: [], cured: Array[String]} — `cured` sert au journal.
static func clear(entries: Array) -> Dictionary:
	var cured: Array[String] = []
	for raw: Variant in sanitize(entries):
		cured.append(str((raw as Dictionary)["status"]))
	return {"entries": [], "cured": cured}
#endregion


#region Résolution
## Ce que les afflictions coûtent à l'unité au début de son tour.
##
## L'ordre compte, et il est le suivant :
##
## 1. les dégâts tombent, plafonnés pour ne jamais descendre sous
##    [constant StatusDB.HP_FLOOR] — [b]un statut ne tue pas[/b] ;
## 2. on regarde qui, parmi les afflictions [i]encore actives[/i], prive l'unité
##    de son tour ;
## 3. seulement là, les durées perdent un tour, et ce qui tombe à zéro disparaît.
##
## Décompter avant de résoudre offrirait un tour de grâce à toute affliction
## d'un seul tour : une paralysie serait posée puis balayée sans jamais avoir
## empêché quoi que ce soit.
##
## L'unité déjà tombée (`hp` à zéro) ne subit rien : ni dégâts, ni décompte. On
## n'empoisonne pas un mort, et son état est celui où on l'a laissé.
##
## [param hp] PV courants de l'unité, avant résolution.
## [returns] {
##   entries: Array,      ## la liste après décompte
##   hp: int,             ## PV après dégâts de statut
##   damage: int,         ## PV réellement perdus (plancher compris)
##   blocked: bool,       ## l'unité passe-t-elle son tour ?
##   expired: Array[String],  ## afflictions qui viennent de se dissiper
##   sources: Array,      ## [{status, damage}] — le détail, pour le journal
## }
static func resolve_turn_start(entries: Array, hp: int) -> Dictionary:
	var active: Array = sanitize(entries)
	if hp <= 0 or active.is_empty():
		return {"entries": active, "hp": hp, "damage": 0, "blocked": false,
			"expired": [] as Array[String], "sources": []}

	# 1. Les dégâts, statut par statut, sans jamais franchir le plancher.
	var sources: Array = []
	var remaining: int = hp
	for raw: Variant in active:
		var key: String = str((raw as Dictionary)["status"])
		var bite: int = DB.damage(key)
		if bite <= 0:
			continue
		var dealt: int = mini(bite, maxi(0, remaining - DB.HP_FLOOR))
		remaining -= dealt
		if dealt > 0:
			sources.append({"status": key, "damage": dealt})

	# 2. Ce que l'unité ne pourra pas faire, tant que l'affliction tient.
	var blocked: bool = is_blocking(active)

	# 3. Le temps passe, et ce qui expire s'en va.
	var survivors: Array = []
	var expired: Array[String] = []
	for raw: Variant in active:
		var entry: Dictionary = raw
		entry["turns"] = int(entry["turns"]) - 1
		if int(entry["turns"]) > 0:
			survivors.append(entry)
		else:
			expired.append(str(entry["status"]))

	return {
		"entries": survivors,
		"hp": remaining,
		"damage": hp - remaining,
		"blocked": blocked,
		"expired": expired,
		"sources": sources,
	}
#endregion
