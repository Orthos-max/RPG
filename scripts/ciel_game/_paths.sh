#!/bin/bash
# Résolution portable des chemins du pont CielAI.
# Sourcé par command.sh / state.sh / launch.sh — ne s'exécute pas seul.
#
# Ordre de résolution du dossier user:// :
#   1. $CIEL_USERDATA          (surcharge explicite, ex. build packagée)
#   2. dossier standard Godot de l'OS pour "Ciel Emblem"
#   3. ancien dossier "Godot Tactical RPG" (compat avant le rebranding)

GAME_NAME="${CIEL_GAME_NAME:-Ciel Emblem}"
LEGACY_GAME_NAME="Godot Tactical RPG"

_ciel_platform_userdata_root() {
    case "$(uname -s)" in
        Darwin)
            echo "$HOME/Library/Application Support/Godot/app_userdata"
            ;;
        Linux)
            echo "${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "${APPDATA:-$HOME/AppData/Roaming}/Godot/app_userdata"
            ;;
        *)
            echo "$HOME/.local/share/godot/app_userdata"
            ;;
    esac
}

_ciel_resolve_userdata() {
    if [ -n "${CIEL_USERDATA:-}" ]; then
        echo "${CIEL_USERDATA}"
        return
    fi

    local root current legacy
    root="$(_ciel_platform_userdata_root)"
    current="$root/$GAME_NAME"
    legacy="$root/$LEGACY_GAME_NAME"

    # Si le nouveau dossier n'existe pas encore mais que l'ancien est là, on le garde.
    if [ ! -d "$current" ] && [ -d "$legacy" ]; then
        echo "$legacy"
    else
        echo "$current"
    fi
}

USERDATA_DIR="$(_ciel_resolve_userdata)"
STATE_FILE="$USERDATA_DIR/ai_state.json"
CMD_FILE="$USERDATA_DIR/ai_command.json"
FEEDBACK_FILE="$USERDATA_DIR/ai_feedback.json"
REPLAY_DIR="$USERDATA_DIR/replays"

# Le dossier est créé au besoin : Ciel peut déposer une commande avant même
# que Godot n'ait écrit son premier état.
mkdir -p "$USERDATA_DIR" 2>/dev/null || true

# Binaire Godot (surchargeable via $GODOT_BIN)
_ciel_resolve_godot() {
    if [ -n "${GODOT_BIN:-}" ] && [ -x "${GODOT_BIN}" ]; then
        echo "${GODOT_BIN}"
        return
    fi
    local candidates=(
        "$HOME/Applications/Godot-4.3.app/Contents/MacOS/Godot"
        "/Applications/Godot-4.3.app/Contents/MacOS/Godot"
        "/Applications/Godot.app/Contents/MacOS/Godot"
        "$(command -v godot 2>/dev/null)"
        "$(command -v godot4 2>/dev/null)"
    )
    for c in "${candidates[@]}"; do
        if [ -n "$c" ] && [ -x "$c" ]; then
            echo "$c"
            return
        fi
    done
    echo ""
}

GODOT="$(_ciel_resolve_godot)"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
