#!/bin/bash
# Envoie une commande à CielAI (Godot tactical-rpg)
# Usage:
#   bash scripts/ciel_game/command.sh select_pawn Skeleton
#   bash scripts/ciel_game/command.sh move 5 3
#   bash scripts/ciel_game/command.sh attack Lord
#   bash scripts/ciel_game/command.sh end_pawn
#   bash scripts/ciel_game/command.sh end_turn
#   bash scripts/ciel_game/command.sh toggle on|off

CMD_FILE="$HOME/Library/Application Support/Godot/app_userdata/Godot Tactical RPG/ai_command.json"
STATE_FILE="$HOME/Library/Application Support/Godot/app_userdata/Godot Tactical RPG/ai_state.json"

ACTION="$1"

case "$ACTION" in
    select_pawn)
        if [ -z "$2" ]; then
            echo "Usage: $0 select_pawn <name>"
            exit 1
        fi
        JSON=$(python3 -c "import json; print(json.dumps({'action': 'select_pawn', 'name': '$2'}))")
        ;;
    move)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 move <col> <row>"
            exit 1
        fi
        JSON=$(python3 -c "import json; print(json.dumps({'action': 'move', 'col': $2, 'row': $3}))")
        ;;
    attack)
        if [ -z "$2" ]; then
            echo "Usage: $0 attack <target_name>"
            exit 1
        fi
        JSON=$(python3 -c "import json; print(json.dumps({'action': 'attack', 'name': '$2'}))")
        ;;
    end_pawn)
        JSON='{"action": "end_pawn"}'
        ;;
    end_turn)
        JSON='{"action": "end_turn"}'
        ;;
    wait)
        JSON='{"action": "wait"}'
        ;;
    toggle)
        if [ "$2" = "off" ]; then
            JSON='{"action": "toggle", "enabled": false}'
            echo "Désactivation de CielAI..."
        else
            JSON='{"action": "toggle", "enabled": true}'
            echo "Activation de CielAI..."
        fi
        ;;
    *)
        echo "Usage: $0 <action> [args...]"
        echo ""
        echo "Actions:"
        echo "  select_pawn <name>      Sélectionne un pion adverse"
        echo "  move <col> <row>         Déplace le pion sélectionné"
        echo "  attack <target_name>     Attaque la cible nommée"
        echo "  end_pawn                 Termine le tour du pion actif"
        echo "  end_turn                 Termine le tour de tous les pions"
        echo "  wait                     Attend sans rien faire"
        echo "  toggle [on|off]          Active/désactive CielAI"
        echo ""
        echo "Astuce: utiliser 'bash scripts/ciel_game/state.sh' pour voir l'état du jeu"
        exit 1
        ;;
esac

echo "$JSON" > "$CMD_FILE"
echo "Commande envoyée: $JSON"

# Feedback instantané (lit le nouvel état après un court délai)
if [ "$ACTION" != "toggle" ]; then
    sleep 1.5
    echo ""
    bash "$(dirname "$0")/state.sh" 2>/dev/null || true
fi
