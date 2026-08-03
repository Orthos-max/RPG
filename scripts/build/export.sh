#!/bin/bash
# Build de Ciel Emblem — exporte le jeu pour une ou plusieurs plateformes.
#
# Usage:
#   bash scripts/build/export.sh              # plateforme courante
#   bash scripts/build/export.sh macos windows linux
#   bash scripts/build/export.sh --debug macos
#   GODOT_BIN=/chemin/Godot bash scripts/build/export.sh
#
# Prérequis : les modèles d'export Godot 4.3 doivent être installés
# (Éditeur → Éditeur → Gérer les modèles d'exportation).

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../ciel_game/_paths.sh"

BUILD_DIR="$PROJECT_DIR/build"
MODE="release"

if [ "${1:-}" = "--debug" ]; then
    MODE="debug"
    shift
fi

if [ -z "$GODOT" ]; then
    echo "Godot introuvable. Définis GODOT_BIN=/chemin/vers/Godot." >&2
    exit 1
fi

# Plateforme par défaut : celle de la machine
default_target() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "linux" ;;
    esac
}

preset_for() {
    case "$1" in
        macos)   echo "macOS" ;;
        windows) echo "Windows Desktop" ;;
        linux)   echo "Linux" ;;
        *)       echo "" ;;
    esac
}

output_for() {
    case "$1" in
        macos)   echo "$BUILD_DIR/macos/CielEmblem.zip" ;;
        windows) echo "$BUILD_DIR/windows/CielEmblem.exe" ;;
        linux)   echo "$BUILD_DIR/linux/CielEmblem.x86_64" ;;
        *)       echo "" ;;
    esac
}

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("$(default_target)")
fi

FAILED=0
for target in "${TARGETS[@]}"; do
    PRESET="$(preset_for "$target")"
    OUTPUT="$(output_for "$target")"
    if [ -z "$PRESET" ]; then
        echo "Cible inconnue : $target (macos|windows|linux)" >&2
        FAILED=1
        continue
    fi

    mkdir -p "$(dirname "$OUTPUT")"
    echo "▶ Export $PRESET ($MODE) → $OUTPUT"

    if [ "$MODE" = "debug" ]; then
        "$GODOT" --headless --path "$PROJECT_DIR" --export-debug "$PRESET" "$OUTPUT"
    else
        "$GODOT" --headless --path "$PROJECT_DIR" --export-release "$PRESET" "$OUTPUT"
    fi

    if [ $? -ne 0 ] || [ ! -e "$OUTPUT" ]; then
        echo "✘ Échec de l'export $PRESET (modèles d'exportation installés ?)" >&2
        FAILED=1
    else
        echo "✔ $OUTPUT"
        # Le pont CielAI est copié à côté du binaire : il reste utilisable
        # sur une machine sans Godot ni dépôt source.
        cp -R "$PROJECT_DIR/scripts/ciel_game" "$(dirname "$OUTPUT")/ciel_game" 2>/dev/null || true
    fi
done

if [ $FAILED -ne 0 ]; then
    echo ""
    echo "Un ou plusieurs exports ont échoué. Voir docs/INSTALL.md." >&2
    exit 1
fi

echo ""
echo "Builds disponibles dans : $BUILD_DIR"
