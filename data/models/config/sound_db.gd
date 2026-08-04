class_name SoundDB
extends RefCounted
## Catalogue des sons du jeu : quel événement joue quoi, et à quel volume.
##
## Aucun fichier audio n'est encore fourni — ce catalogue existe pour que le
## jour où ils arrivent, il n'y ait rien à recâbler : il suffit de déposer les
## fichiers aux chemins déclarés ici. [Audio] joue le silence en attendant et
## sait dire lesquels manquent (`Audio.missing_cues()`).
##
## Logique pure : la traduction « événement de bataille → son » se teste en
## headless, sans le moindre lecteur audio. C'est elle qui décide qu'un coup
## critique ne sonne pas comme un coup normal, et qu'un raté a son propre bruit.

## Bus audio créés au démarrage par [Audio] (en plus de Master)
const BUS_SFX: String = "SFX"
const BUS_MUSIC: String = "Music"
const BUS_UI: String = "UI"

## Dossier où déposer les fichiers (voir `assets/audio/README.md`)
const AUDIO_DIR: String = "res://assets/audio"

## Catalogue : clé de son → réglages.
##
## `file` est relatif à [constant AUDIO_DIR]. `pitch_min`/`pitch_max` donnent la
## variation aléatoire de hauteur : sans elle, dix squelettes frappés d'affilée
## sonnent comme une boucle cassée.
const CUES: Dictionary = {
	# --- Combat ---
	"hit": {"file": "sfx/hit.ogg", "bus": BUS_SFX, "volume_db": 0.0,
		"pitch_min": 0.94, "pitch_max": 1.06},
	"hit_crit": {"file": "sfx/hit_crit.ogg", "bus": BUS_SFX, "volume_db": 2.0,
		"pitch_min": 0.98, "pitch_max": 1.02},
	"miss": {"file": "sfx/miss.ogg", "bus": BUS_SFX, "volume_db": -3.0,
		"pitch_min": 0.95, "pitch_max": 1.05},
	"heal": {"file": "sfx/heal.ogg", "bus": BUS_SFX, "volume_db": -1.0,
		"pitch_min": 0.98, "pitch_max": 1.03},
	"death_ally": {"file": "sfx/death_ally.ogg", "bus": BUS_SFX, "volume_db": 1.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"death_enemy": {"file": "sfx/death_enemy.ogg", "bus": BUS_SFX, "volume_db": 0.0,
		"pitch_min": 0.96, "pitch_max": 1.04},

	# --- Progression ---
	"level_up": {"file": "sfx/level_up.ogg", "bus": BUS_SFX, "volume_db": 0.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"promotion": {"file": "sfx/promotion.ogg", "bus": BUS_SFX, "volume_db": 0.0,
		"pitch_min": 1.0, "pitch_max": 1.0},

	# --- Déroulé de la partie ---
	"turn_player": {"file": "sfx/turn_player.ogg", "bus": BUS_SFX, "volume_db": -2.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"turn_enemy": {"file": "sfx/turn_enemy.ogg", "bus": BUS_SFX, "volume_db": -2.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"move": {"file": "sfx/move.ogg", "bus": BUS_SFX, "volume_db": -6.0,
		"pitch_min": 0.92, "pitch_max": 1.08},
	"victory": {"file": "sfx/victory.ogg", "bus": BUS_SFX, "volume_db": 0.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"defeat": {"file": "sfx/defeat.ogg", "bus": BUS_SFX, "volume_db": 0.0,
		"pitch_min": 1.0, "pitch_max": 1.0},

	# --- Interface ---
	"ui_select": {"file": "ui/select.ogg", "bus": BUS_UI, "volume_db": -4.0,
		"pitch_min": 0.98, "pitch_max": 1.02},
	"ui_confirm": {"file": "ui/confirm.ogg", "bus": BUS_UI, "volume_db": -2.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"ui_cancel": {"file": "ui/cancel.ogg", "bus": BUS_UI, "volume_db": -4.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"ui_refused": {"file": "ui/refused.ogg", "bus": BUS_UI, "volume_db": -2.0,
		"pitch_min": 1.0, "pitch_max": 1.0},

	# --- Musiques (jouées en boucle sur le bus Music) ---
	"music_title": {"file": "music/title.ogg", "bus": BUS_MUSIC, "volume_db": -6.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"music_battle": {"file": "music/battle.ogg", "bus": BUS_MUSIC, "volume_db": -8.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
	"music_prep": {"file": "music/prep.ogg", "bus": BUS_MUSIC, "volume_db": -8.0,
		"pitch_min": 1.0, "pitch_max": 1.0},
}


## Toutes les clés du catalogue.
static func keys() -> Array:
	return CUES.keys()


## Réglages d'un son (dictionnaire vide si la clé est inconnue).
static func cue(key: String) -> Dictionary:
	return CUES.get(key, {})


## Chemin complet du fichier d'un son ("" si la clé est inconnue).
static func path_of(key: String) -> String:
	var entry: Dictionary = cue(key)
	if entry.is_empty():
		return ""
	return "%s/%s" % [AUDIO_DIR, str(entry["file"])]


## Ce son est-il une musique (jouée en boucle, un seul à la fois) ?
static func is_music(key: String) -> bool:
	return str(cue(key).get("bus", "")) == BUS_MUSIC


## Son correspondant à un événement du journal de bataille.
##
## C'est le cœur du système : [BattleRecorder] émet déjà tout ce qui se passe,
## il suffit de traduire. Renvoie "" quand l'événement n'a pas de son (une
## commande rejetée par Ciel ne concerne pas le joueur, par exemple).
##
## [param event] Entrée de [BattleRecorder] : {kind_name, crit, hit, team…}
static func cue_for_event(event: Dictionary) -> String:
	match str(event.get("kind_name", "")):
		"attack":
			if not bool(event.get("hit", true)):
				return "miss"
			return "hit_crit" if bool(event.get("crit", false)) else "hit"
		"heal":
			return "heal"
		"death":
			# Perdre une unité et en abattre une ne s'entendent pas pareil.
			return "death_ally" if str(event.get("team", "")) == "player" else "death_enemy"
		"level_up":
			return "level_up"
		"promotion":
			return "promotion"
		"turn_start":
			return "turn_player" if str(event.get("team", "")) == "player" else "turn_enemy"
		"move":
			return "move"
		"objective":
			var status: String = str(event.get("status", ""))
			if status == "victory":
				return "victory"
			if status == "defeat":
				return "defeat"
	return ""
