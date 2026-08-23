class_name BossDB
extends RefCounted
## Catalogue des boss — qui ils sont, et ce qui leur arrive quand on les entame.
##
## Un boss est une unité ordinaire à une chose près : elle porte des [b]phases[/b].
## Une phase est un seuil de PV et ce qui se déclenche en le franchissant — un
## gain de statistiques, un soin, une compétence apprise, une réplique. Le
## commandant qui rugit à mi-vie et se soigne à l'agonie, c'est cela et rien
## d'autre.
##
## Logique pure, comme [StatusDB] et [SkillDB] : ce fichier dit ce qu'un boss
## [i]est[/i], [BossPhases] dit quand ses phases tombent, et [Stats] les porte sur
## une unité vivante. Aucun nœud, aucune scène — donc vérifiable en `--headless`.
##
## [b]Un boss n'est pas une fiche, c'est un rôle.[/b] `skeleton_cpn.tres` sert de
## capitaine sur sept cartes ; en faire un boss dans le `.tres` sacrerait les sept
## d'un coup. C'est donc le [b]chapitre[/b] qui couronne son boss
## ([member ChapterData.boss]), et [ChapterRunner] qui pose l'identifiant sur le
## pion nommé au chargement du niveau.

## Statistiques qu'une phase peut faire monter, définitivement.
##
## Les mêmes que [method Stats.apply_buff] — mais ce que donne une phase ne
## s'éteint pas au tour suivant : le boss enragé le reste jusqu'à sa chute. Ni
## PV maximum ni croissances : une phase change un rapport de force, elle ne
## refait pas la fiche.
const GAIN_KEYS: Array[String] = ["str", "mag", "skl", "spd", "lck", "def", "res"]

## Nombre maximum de phases par boss.
##
## Garde-fou de lisibilité plus que de technique : au-delà de quatre bascules, le
## joueur ne relie plus le message à la barre de PV qui vient de descendre.
const MAX_PHASES: int = 4

## Le catalogue.
##
## `phases` se lit du seuil le plus haut au plus bas — [method BossPhases.sanitize]
## s'en assure, l'ordre d'écriture ici n'engage à rien. Chaque phase porte :
##
## - `threshold` : ratio de PV sous lequel elle tombe (0.5 = la moitié) ;
## - `label` : son nom, montré sur la fiche d'unité (« Rage ») ;
## - `message` : ce que le journal annonce quand elle se déclenche ;
## - `gains` : montées de statistiques définitives ([constant GAIN_KEYS]) ;
## - `heal` : fraction des PV maximum rendue au passage (0.0 = rien) ;
## - `skills` : compétences apprises à cet instant ([SkillDB]) ;
## - `cure` : la bascule lève-t-elle les afflictions en cours ?
static var DATA: Dictionary = {
	"garrick": {
		"name": "Garrick",
		"title": "Chef pillard",
		"phases": [
			{
				"threshold": 0.6,
				"label": "Rage",
				"message": "Garrick entre en rage — ses coups redoublent de violence !",
				"gains": {"str": 3, "skl": 2},
				"heal": 0.0,
				"skills": ["wrath"],
				"cure": false,
			},
			{
				"threshold": 0.3,
				"label": "Désespoir",
				"message": "Acculé, Garrick panse ses plaies et refuse de tomber !",
				"gains": {"def": 2, "spd": 2},
				"heal": 0.25,
				"skills": ["cold_blood", "regeneration"],
				"cure": true,
			},
		],
	},
}


## Ce boss existe-t-il au catalogue ?
static func exists(boss_id: String) -> bool:
	return not boss_id.is_empty() and DATA.has(boss_id)


## Fiche brute d'un boss (dictionnaire vide s'il est inconnu).
static func get_boss(boss_id: String) -> Dictionary:
	return DATA.get(boss_id, {})


## Nom propre du boss — celui qu'un chapitre vise dans son objectif.
static func boss_name(boss_id: String) -> String:
	return str(get_boss(boss_id).get("name", ""))


## Titre affiché sous le nom (« Chef pillard »), "" s'il n'en a pas.
static func title(boss_id: String) -> String:
	return str(get_boss(boss_id).get("title", ""))


## Phases telles qu'elles sont écrites ici, sans tri ni nettoyage.
##
## Personne ne devrait les lire directement : [method BossPhases.phases_of] les
## rend triées et bornées, et c'est cette liste-là qui fait foi.
static func raw_phases(boss_id: String) -> Array:
	var phases: Variant = get_boss(boss_id).get("phases", [])
	return phases if phases is Array else []


## Tous les identifiants du catalogue.
static func all_ids() -> Array:
	return DATA.keys()
