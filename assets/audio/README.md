# Sons de Ciel Emblem — liste de courses

> Le système audio est en place et **attend ses fichiers**. Rien à recâbler :
> dépose un fichier au chemin indiqué, il sera joué au bon moment.
> Tant qu'un fichier manque, l'appel est silencieux — jamais une erreur.

Pour savoir ce qui manque encore, en jeu ou en headless :

```gdscript
print(Audio.missing_cues())   # liste des sons non fournis
```

---

## Format

| | |
|---|---|
| Format | **`.ogg`** (Vorbis) — Godot le boucle proprement, contrairement au `.wav` |
| Fréquence | 44,1 kHz |
| Bruitages | mono, courts (< 1,5 s), sans silence en tête |
| Musiques | stéréo, bouclables (le service active la boucle automatiquement) |
| Niveau | normalisé à −3 dBFS ; les écarts se règlent dans `SoundDB.CUES`, pas dans le fichier |

Le volume et la variation de hauteur de chaque son se règlent dans
`data/models/config/sound_db.gd` (`CUES`) — inutile de retoucher les fichiers
pour qu'un critique claque plus fort qu'un coup normal.

---

## Fichiers attendus

### `sfx/` — combat et déroulé (bus SFX)

| Fichier | Joué quand | Intention |
|---|---|---|
| `hit.ogg` | un coup touche | impact franc, hauteur variée ±6 % |
| `hit_crit.ogg` | coup critique | plus lourd, +2 dB, hauteur fixe |
| `miss.ogg` | l'attaque rate | souffle, lame dans le vide |
| `heal.ogg` | un soin est appliqué | clair, montant |
| `death_ally.ogg` | une de tes unités tombe | grave, marquant — c'est une perte |
| `death_enemy.ogg` | un ennemi tombe | sec, sans pathos |
| `level_up.ogg` | montée de niveau | court motif ascendant |
| `promotion.ogg` | promotion de classe | plus solennel que la montée de niveau |
| `turn_player.ogg` | début de ton tour | signal net |
| `turn_enemy.ogg` | début du tour adverse | même signal, plus sombre |
| `move.ogg` | un pion se déplace | pas discrets, −6 dB |
| `victory.ogg` | chapitre gagné | fanfare courte |
| `defeat.ogg` | chapitre perdu | descente |

### `ui/` — interface (bus UI)

| Fichier | Joué quand |
|---|---|
| `select.ogg` | choix d'une action (Move, Attack) |
| `confirm.ogg` | validation (Wait) |
| `cancel.ogg` | annulation, retour, annulation d'un déplacement |
| `refused.ogg` | action impossible |

### `music/` — ambiances (bus Music, en boucle)

| Fichier | Écran |
|---|---|
| `title.ogg` | écran-titre |
| `prep.ogg` | préparation du chapitre et intendance |
| `battle.ogg` | bataille |

---

## Comment c'est branché

- **`SoundDB`** (`data/models/config/sound_db.gd`) — le catalogue, et la
  traduction « événement de bataille → son ». Logique pure, testée.
- **`Audio`** (autoload, `data/services/audio/audio_service.gd`) — crée les bus
  `SFX` / `Music` / `UI` sous Master, garde 8 voix de bruitage, joue les
  musiques en boucle, retient les volumes dans `user://settings.json`.
- Le service écoute **`BattleRecorder.event_recorded`** : tout ce que le journal
  de bataille enregistre (coup, soin, mort, montée de niveau, fin de chapitre)
  déclenche déjà le bon son. Aucun appel à ajouter dans le gameplay.

Régler le volume :

```gdscript
Audio.set_volume("Music", 0.4)   # 0.0 → 1.0
Audio.save_settings()
```

---

## Où trouver des sons libres

Rien n'est fourni avec le dépôt pour ne pas y embarquer de licence tierce.
Pistes classiques : [freesound.org](https://freesound.org) (filtrer CC0),
[OpenGameArt](https://opengameart.org), ou des banques achetées. Vérifie la
licence avant de commiter un fichier — une fois dans le dépôt, il part avec le
jeu dans les builds.
