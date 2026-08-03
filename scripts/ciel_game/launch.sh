#!/bin/bash
# Lance Ciel Emblem depuis les sources Godot.
# Usage: bash scripts/ciel_game/launch.sh [args godot...]
#
# Surcharges possibles :
#   GODOT_BIN=/chemin/vers/Godot   binaire Godot à utiliser
#   CIEL_USERDATA=/chemin          dossier d'échange du pont CielAI

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_paths.sh"

if [ -z "$GODOT" ]; then
    echo "Godot introuvable. Chemins testés :" >&2
    echo "  - \$GODOT_BIN" >&2
    echo "  - ~/Applications/Godot-4.3.app" >&2
    echo "  - /Applications/Godot-4.3.app, /Applications/Godot.app" >&2
    echo "  - godot / godot4 dans le PATH" >&2
    exit 1
fi

echo "Godot   : $GODOT"
echo "Projet  : $PROJECT_DIR"
echo "Userdata: $USERDATA_DIR"
echo ""
echo "Une fois le jeu lancé, le camp adverse est piloté par Ciel"
echo "(bascule possible à tout moment : command.sh toggle off)."
echo ""

exec "$GODOT" --path "$PROJECT_DIR" "$@"
