# Protocole CielAI — v1

> Contrat d'échange entre le moteur (Godot / **Ciel Emblem**) et l'IA externe (**Ciel**).
> Ce document fait foi : toute évolution du pont doit être répercutée ici **et** dans
> `data/models/world/ai/ciel_command.gd` (qui implémente la validation).

---

## 1. Vue d'ensemble

```
┌──────────────┐   ai_state.json     ┌──────────────┐
│    Godot     │ ──────────────────► │     Ciel     │
│   (CielAI)   │ ◄────────────────── │  (décision)  │
│              │   ai_command.json   │              │
│              │ ──────────────────► │              │
└──────────────┘   ai_feedback.json  └──────────────┘
```

| Fichier | Sens | Écrit par | Description |
|---|---|---|---|
| `ai_state.json` | Godot → Ciel | Godot | État complet du champ de bataille. Réécrit à chaque changement. |
| `ai_command.json` | Ciel → Godot | Ciel | Un ordre, un fichier. **Supprimé par Godot dès la lecture**, valide ou non. |
| `ai_feedback.json` | Godot → Ciel | Godot | Acquittement ou motif de rejet du dernier ordre lu. |
| `replays/*.json` | Godot | Godot | Journal complet d'une bataille (analyse a posteriori). |

### Emplacement des fichiers

Dossier `user://` de Godot pour l'application **Ciel Emblem** :

| OS | Chemin |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/Ciel Emblem/` |
| Linux | `~/.local/share/godot/app_userdata/Ciel Emblem/` |
| Windows | `%APPDATA%\Godot\app_userdata\Ciel Emblem\` |

Surcharge possible : `CIEL_USERDATA=/chemin` (utilisée par les scripts `scripts/ciel_game/`).
Le chemin résolu est affiché par `bash scripts/ciel_game/state.sh --path`.

---

## 2. `ai_state.json` — état exporté

```jsonc
{
  "protocol_version": 1,
  "seq": 42,                    // Incrémenté à chaque écriture ; curseur de fraîcheur
  "timestamp": 1785312000.0,    // Epoch Unix (secondes)
  "turn": "opponent",           // "player" | "opponent" | "unknown"
  "turn_number": 3,             // Tour de jeu complet (joueur + adversaire)
  "stage": 1,                   // Étape de la machine à états du tour
  "stage_name": "show_actions",
  "stage_actions": ["attack", "end_pawn", "..."],  // Commandes légales ICI et MAINTENANT
  "current_pawn": "Skeleton",   // Pion adverse sélectionné ("" si aucun)
  "mode": "ciel",               // solo | ciel | hotseat | network
  "difficulty": "Normal",
  "opponent_controller": "CielAI",
  "objective": "Vaincre tous les ennemis",   // Absent hors campagne
  "last_error": "",             // Motif du dernier rejet ("" si tout va bien)
  "last_error_code": 0,
  "tile_size": 1.0,
  "grid_size": {"x": 16, "y": 10},
  "terrain": {
    "legend": {"g": "grass", "f": "forest (+1 DEF)", "m": "mountain (bloqué)", "...": "..."},
    "rows": ["ggggffgggggggggg", "..."]   // Une chaîne par rangée, un caractère par case
  },
  "pawns": [ /* voir ci-dessous */ ],
  "events": [ /* voir §4 */ ],
  "event_cursor": 87            // Dernier `seq` d'événement connu du moteur
}
```

### Objet `pawn`

```jsonc
{
  "name": "Skeleton",           // Identifiant utilisé dans les commandes
  "team": "opponent",           // "player" | "opponent"
  "grid_col": 5, "grid_row": 3,
  "hp": 14, "max_hp": 20,
  "level": 3, "exp": 40,
  "class_name": "Brigand",
  "is_promoted": false,
  "is_flying": false,           // Les volants prennent x3 des arcs
  "str": 7, "mag": 0, "skl": 4, "spd": 5, "lck": 2, "def": 3, "res": 0,
  "movement": 5, "attack_range": 1,
  "weapon_type": 2, "weapon_name": "Axe", "weapon_might": 5, "is_magical": false,
  "items": ["Vulnerary"],
  "buffs": [{"stat": "def", "amount": 2, "turns": 1}],
  "terrain": "forest", "terrain_def": 1,
  "can_move": true, "can_attack": true, "alive": true,

  // Uniquement pour le pion actif :
  "reachable_tiles": [{"col": 5, "row": 4, "def_bonus": 0, "terrain": "grass"}],
  "attack_tiles":    [{"col": 6, "row": 3}]
}
```

### Étapes (`stage`)

| Valeur | `stage_name` | Ciel peut agir ? |
|---|---|---|
| 0 | `select_pawn` | Oui — choisir un pion ou finir le tour |
| 1 | `show_actions` | Oui — déplacer, attaquer, soigner, utiliser un objet… |
| 2 | `show_movements` | Non — animation de déplacement en cours |
| 3 | `select_location` | Oui — attaquer/soigner après déplacement |
| 4 | `move_pawn` | Non — résolution du combat |

---

## 3. `ai_command.json` — ordres acceptés

Un seul objet JSON, champ `action` obligatoire.

| Action | Arguments | Étapes autorisées | Effet |
|---|---|---|---|
| `select_pawn` | `name` (string) | 0 | Sélectionne un pion adverse capable d'agir |
| `move` | `col`, `row` (int) | 1 | Déplace le pion actif vers une case **atteignable** |
| `attack` | `name` (string) | 1, 3 | Attaque une unité du camp d'en face à portée |
| `heal` | `name` (string) | 1, 3 | Soigne un allié (porteur de bâton uniquement) |
| `use_item` | `item` (string), `name` (string, opt.) | 1, 3 | Consomme un objet (soi-même par défaut) |
| `promote` | `class` (string, opt.) | 1 | Promeut le pion actif ; `class` choisit la branche |
| `flee` | — | 1 | Repli vers la case la plus éloignée des ennemis (renonce à attaquer) |
| `guard` | — | 1, 3 | Se met en garde : +2 DÉF/RÉS pendant 2 tours, termine l'action |
| `wait` | — | 1, 3 | Termine l'action du pion sans attaquer |
| `end_pawn` | — | 1, 3 | Termine le tour du pion actif |
| `end_turn` | — | 0, 1, 3 | Termine le tour adverse complet |
| `toggle` | `enabled` (bool) | *toutes* | Active/désactive le contrôle Ciel (l'IA locale prend le relais) |

Exemples :

```json
{"action": "select_pawn", "name": "Skeleton"}
{"action": "move", "col": 5, "row": 3}
{"action": "attack", "name": "Lord"}
{"action": "promote", "class": "Berserker"}
{"action": "toggle", "enabled": false}
```

> Les entiers peuvent être écrits `5` ou `5.0` (JSON ne distingue pas) ; `5.4` est rejeté.

---

## 4. Journal d'événements (`events`)

Les 20 derniers événements sont inclus dans `ai_state.json` ; le replay complet est
écrit en fin de bataille dans `replays/`.

```jsonc
{"seq": 12, "kind_name": "attack", "attacker": "Skeleton", "defender": "Lord",
 "damage": 7, "hit": true, "crit": false, "double": false, "defender_hp": 11}
{"seq": 13, "kind_name": "death", "pawn": "Skeleton", "team": "opponent"}
{"seq": 14, "kind_name": "command_rejected", "action": "move", "code": 7,
 "reason": "(9,9) hors de portée de Skeleton (MOV 5)"}
```

Types : `turn_start`, `move`, `attack`, `heal`, `death`, `level_up`, `promotion`,
`command_rejected`, `objective`.

Pour ne traiter que le nouveau : mémoriser `event_cursor` et ignorer les `seq` inférieurs.

---

## 5. `ai_feedback.json` — acquittement

Écrit après **chaque** ordre lu :

```jsonc
{
  "protocol_version": 1,
  "action": "move",
  "ok": false,
  "code": 7,
  "code_name": "OUT_OF_RANGE",
  "error": "(9,9) hors de portée de Skeleton (MOV 5)",
  "seq": 42,
  "at": "2026-08-03T21:14:07"
}
```

### Codes d'erreur

| Code | Nom | Cause |
|---|---|---|
| 0 | `OK` | Ordre accepté |
| 1 | `MALFORMED_JSON` | Fichier illisible (JSON invalide) |
| 2 | `NOT_A_DICT` | Le JSON n'est pas un objet |
| 3 | `MISSING_ACTION` | Champ `action` absent ou vide |
| 4 | `UNKNOWN_ACTION` | Action hors protocole |
| 5 | `MISSING_ARG` | Argument obligatoire absent (ou nom vide) |
| 6 | `BAD_ARG_TYPE` | Argument du mauvais type |
| 7 | `OUT_OF_RANGE` | Case hors grille, hors portée, cible absente |
| 8 | `WRONG_STAGE` | Action interdite à l'étape courante |
| 9 | `OUT_OF_TURN` | Ce n'est pas le tour du camp adverse |

**Garanties du moteur** — un ordre rejeté :
* n'est **jamais** appliqué (aucun état de jeu modifié) ;
* est consommé (le fichier est supprimé : pas de boucle de rejet infinie) ;
* est journalisé (console, `events`, `ai_feedback.json`, `last_error` dans l'état).

---

## 6. Verrou anti-blocage

Si aucun ordre **valide** n'arrive pendant ~10 s (600 frames physiques) alors que
c'est le tour adverse, l'IA locale ([`LocalAIBrain`](../data/models/world/ai/local_ai.gd))
joue le pion à la place de Ciel, puis rend la main. Le tour ne peut donc pas se figer,
que Ciel soit lent, absent, ou en train d'envoyer des ordres invalides.

De la même façon, `{"action": "toggle", "enabled": false}` bascule le camp adverse sur
l'IA locale : la partie reste jouable sans le pont.

> `ai_state.json` n'est mis à jour **que** lorsque le camp adverse est confié à Ciel
> (mode « Escarmouche CielAI », ou après `toggle on`). En mode solo pur, le fichier
> conserve son dernier contenu — c'est normal, personne n'écoute.

---

## 7. Boucle type côté Ciel

```bash
# 1. Lire l'état (résumé lisible, JSON brut, ou événements)
bash scripts/ciel_game/state.sh
bash scripts/ciel_game/state.sh --raw
bash scripts/ciel_game/state.sh --events
bash scripts/ciel_game/state.sh --tiles Skeleton   # portées du pion

# 2. Décider, puis agir
bash scripts/ciel_game/command.sh select_pawn Skeleton
bash scripts/ciel_game/command.sh move 5 3
bash scripts/ciel_game/command.sh attack Lord
bash scripts/ciel_game/command.sh end_pawn

# 3. Répéter jusqu'à end_turn
bash scripts/ciel_game/command.sh end_turn
```

Règles de bonne conduite :
1. **Toujours relire `stage_actions`** avant d'envoyer un ordre — c'est la liste exacte
   des actions légales à l'instant présent.
2. **Un ordre à la fois** : attendre le changement de `seq` (ou lire `ai_feedback.json`)
   avant d'écrire le suivant.
3. **`grid_col`/`grid_row` font foi** pour les distances (distance de Manhattan).
4. **Vérifier `reachable_tiles`** avant un `move` : une case atteignable en ligne droite
   ne l'est pas forcément (terrain infranchissable, pions).

---

## 8. Compatibilité & versionnage

`protocol_version` figure dans l'état et le feedback. Une évolution **cassante**
(argument obligatoire ajouté, action renommée) incrémente ce numéro. Les ajouts de
champs facultatifs ne l'incrémentent pas : Ciel doit ignorer les champs inconnus.

Implémentation de référence :
* validation — `data/models/world/ai/ciel_command.gd`
* pont & export — `data/modules/ai/ciel_ai.gd`
* journal/replay — `data/services/combat/battle_log.gd`
* tests — `test_features.gd` (section « validation des commandes »)
