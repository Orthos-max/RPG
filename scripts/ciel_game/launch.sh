#!/bin/bash
# Ciel Game Launcher — lance Godot avec le projet tactical-rpg
# Usage: bash scripts/ciel_game/launch.sh

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="/Users/tamilahciel/Applications/Godot-4.3.app/Contents/MacOS/Godot"

if [ ! -f "$GODOT" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
fi

if [ ! -f "$GODOT" ]; then
    echo "Godot introuvable. Chemins testés:"
    echo "  - /Users/tamilahciel/Applications/Godot-4.3.app"
    echo "  - /Applications/Godot.app"
    exit 1
fi

echo "Lancement de Godot avec $PROJECT_DIR..."
echo "Une fois le jeu lancé, CielAI prendra le contrôle du camp adverse."
echo ""

# Lancer Godot avec le projet
"$GODOT" --path "$PROJECT_DIR" "$@"
