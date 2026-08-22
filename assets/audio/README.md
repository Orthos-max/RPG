# Sons de Ciel Emblem

> Les 20 sons du jeu sont fournis (SFX combat, UI, musiques) — générés
> procéduralement (numpy + soundfile, OGG Vorbis 44,1 kHz). Aucun droit
> d'auteur, aucune dépendance externe.

## Contenu

| Dossier | Fichiers |
|---|---|
| `sfx/` | hit, hit_crit, miss, heal, death_ally, death_enemy, level_up, promotion, turn_player, turn_enemy, move, victory, defeat |
| `ui/` | select, confirm, cancel, refused |
| `music/` | title, battle, prep (boucles stéréo) |

Vérifier qu'il ne manque rien, en jeu ou en headless :

```gdscript
print(Audio.missing_cues())   # [] = tout est fourni
```

## Régénération

```bash
python3 /tmp/gen_ciel_audio.py   # ou le script d'origine (skill procedural-game-audio)
```

## Format

| | |
|---|---|
| Format | **`.ogg`** (Vorbis) — boucle proprement sous Godot |
| Fréquence | 44,1 kHz |
| Bruitages | mono, courts (< 1,5 s), sans silence en tête |
| Musiques | stéréo, bouclables (le service active la boucle automatiquement) |
| Niveau | normalisé ~ −3 dBFS ; les écarts se règlent dans `SoundDB.CUES`, pas dans le fichier |

Le volume et la variation de hauteur de chaque son se règlent dans
`data/models/config/sound_db.gd` (champ `volume_db` / `pitch_min` / `pitch_max`).
