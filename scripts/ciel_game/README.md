# CielAI — Pont Godot ↔ Ciel

Système de jeu autonome pour le tactical RPG. Ciel contrôle le camp adverse via des fichiers JSON.

## Architecture

```
┌─────────────┐     ai_state.json      ┌──────────────┐
│   Godot     │ ──────────────────────→ │    Ciel      │
│  (CielAI)   │ ←────────────────────── │  (analyse +  │
│             │     ai_command.json     │   décision)  │
└─────────────┘                         └──────────────┘
```

## Lancement

```bash
bash scripts/ciel_game/launch.sh
```

Ouvre Godot 4.3 avec le projet. Une fois le jeu lancé, le camp adverse est automatiquement contrôlé par Ciel.

## Commandes

```bash
bash scripts/ciel_game/command.sh <action> [args...]
```

| Action | Args | Description |
|--------|------|-------------|
| `select_pawn` | `<name>` | Sélectionne un pion adverse par son nom |
| `move` | `<col> <row>` | Déplace le pion sélectionné vers la case |
| `attack` | `<name>` | Attaque une unité alliée par son nom |
| `end_pawn` | — | Termine le tour du pion actif |
| `end_turn` | — | Termine le tour adverse complet |
| `toggle` | `on\|off` | Active/désactive le contrôle Ciel |

## Voir l'état

```bash
# Résumé formaté
bash scripts/ciel_game/state.sh

# Mode temps réel
bash scripts/ciel_game/state.sh --watch

# JSON brut
bash scripts/ciel_game/state.sh --raw
```

## Comment Ciel joue

1. **Lire l'état** → `bash scripts/ciel_game/state.sh`
2. **Décider** → analyser les positions, stats, menaces
3. **Agir** → `bash scripts/ciel_game/command.sh ...`
4. **Répéter** jusqu'à `end_turn`

Le fichier de commande est supprimé après lecture par Godot.
