# CielAI — Pont Godot ↔ Ciel

Ciel contrôle le camp adverse de **Ciel Emblem** via un échange de fichiers JSON.
Le contrat complet (schémas, codes d'erreur, garanties) est dans
[`docs/CIEL_PROTOCOL.md`](../../docs/CIEL_PROTOCOL.md).

## Architecture

```
┌─────────────┐     ai_state.json      ┌──────────────┐
│   Godot     │ ──────────────────────►│    Ciel      │
│  (CielAI)   │◄────────────────────── │  (analyse +  │
│             │     ai_command.json    │   décision)  │
│             │ ──────────────────────►│              │
└─────────────┘     ai_feedback.json   └──────────────┘
```

Les chemins sont résolus automatiquement selon l'OS (`_paths.sh`) :

```bash
bash scripts/ciel_game/state.sh --path      # où sont les fichiers
export CIEL_USERDATA=/chemin/perso          # pour forcer un dossier
export GODOT_BIN=/chemin/vers/Godot         # pour forcer un binaire
```

## Lancement

```bash
bash scripts/ciel_game/launch.sh
```

Le camp adverse est piloté par Ciel en mode **Escarmouche CielAI** (écran-titre)
ou dès que `toggle on` est envoyé.

## Commandes

```bash
bash scripts/ciel_game/command.sh <action> [args...]
```

| Action | Args | Description |
|--------|------|-------------|
| `select_pawn` | `<name>` | Sélectionne un pion adverse |
| `move` | `<col> <row>` | Déplace le pion vers une case atteignable |
| `attack` | `<name>` | Attaque une unité du camp d'en face |
| `heal` | `<name>` | Soigne un allié (porteur de bâton) |
| `use_item` | `<item> [cible]` | Consomme un objet (Vulnerary, Elixir…) |
| `promote` | `[classe]` | Promeut le pion ; `classe` choisit la branche |
| `flee` | — | Repli loin des ennemis (renonce à attaquer) |
| `guard` | — | +2 DÉF/RÉS pendant 2 tours, termine l'action |
| `wait` / `end_pawn` | — | Termine l'action du pion |
| `end_turn` | — | Termine le tour adverse |
| `toggle` | `on\|off` | Bascule entre Ciel et l'IA locale |

## Voir l'état

```bash
bash scripts/ciel_game/state.sh            # résumé formaté
bash scripts/ciel_game/state.sh --watch    # temps réel (0.5 s)
bash scripts/ciel_game/state.sh --raw      # JSON brut
bash scripts/ciel_game/state.sh --events   # journal des événements
bash scripts/ciel_game/state.sh --tiles Skeleton   # portées d'un pion
```

## Comment Ciel joue

1. **Lire l'état** → `state.sh` (et surtout `stage_actions` : les coups légaux ici et maintenant)
2. **Décider** → positions (`grid_col`/`grid_row`), PV, portées, terrain, événements récents
3. **Agir** → `command.sh …`
4. **Vérifier** → `ai_feedback.json` dit si l'ordre est passé, sinon pourquoi
5. **Répéter** jusqu'à `end_turn`

Garanties du moteur :
* un ordre invalide est **rejeté** (jamais appliqué) et **consommé** (pas de boucle) ;
* sans ordre valide pendant ~10 s, **l'IA locale joue le tour** : la partie ne se fige pas ;
* `toggle off` rend définitivement le camp adverse à l'IA locale.
