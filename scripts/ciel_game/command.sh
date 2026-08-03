#!/bin/bash
# Envoie une commande à CielAI (jeu Ciel Emblem).
# Le protocole complet est décrit dans docs/CIEL_PROTOCOL.md
#
# Usage:
#   bash scripts/ciel_game/command.sh select_pawn Skeleton
#   bash scripts/ciel_game/command.sh move 5 3
#   bash scripts/ciel_game/command.sh attack Lord
#   bash scripts/ciel_game/command.sh heal Skeleton
#   bash scripts/ciel_game/command.sh use_item Vulnerary
#   bash scripts/ciel_game/command.sh promote [Classe]
#   bash scripts/ciel_game/command.sh guard|wait|flee|end_pawn|end_turn
#   bash scripts/ciel_game/command.sh toggle on|off

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_paths.sh"

ACTION="${1:-}"

# Encode une chaîne pour JSON (guillemets, antislashes, accents).
json_str() {
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

usage() {
    cat <<'EOF'
Usage: command.sh <action> [args...]

Actions de pion (pendant le tour adverse) :
  select_pawn <name>       Sélectionne un pion adverse
  move <col> <row>         Déplace le pion sélectionné
  attack <name>            Attaque une unité du camp d'en face
  heal <name>              Soigne un allié (bâton/objet)
  use_item <item> [name]   Utilise un objet, éventuellement sur une cible
  promote [classe]         Promeut le pion sélectionné (classe au choix si embranchement)
  flee                     Fuit la mêlée (s'éloigne au maximum)
  guard                    Se met en garde (termine le tour en défense)
  wait                     Termine l'action du pion sans attaquer
  end_pawn                 Termine le tour du pion actif
  end_turn                 Termine le tour adverse complet

Actions globales :
  toggle on|off            Active/désactive le contrôle Ciel (IA locale sinon)

Voir l'état : bash scripts/ciel_game/state.sh [--watch|--raw|--events]
EOF
}

case "$ACTION" in
    select_pawn|attack|heal)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 $ACTION <name>" >&2
            exit 1
        fi
        JSON="{\"action\": \"$ACTION\", \"name\": $(json_str "$2")}"
        ;;
    move)
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: $0 move <col> <row>" >&2
            exit 1
        fi
        case "$2$3" in
            *[!0-9]*) echo "col et row doivent être des entiers positifs" >&2; exit 1 ;;
        esac
        JSON="{\"action\": \"move\", \"col\": $2, \"row\": $3}"
        ;;
    use_item)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 use_item <item> [target]" >&2
            exit 1
        fi
        if [ -n "${3:-}" ]; then
            JSON="{\"action\": \"use_item\", \"item\": $(json_str "$2"), \"name\": $(json_str "$3")}"
        else
            JSON="{\"action\": \"use_item\", \"item\": $(json_str "$2")}"
        fi
        ;;
    promote)
        if [ -n "${2:-}" ]; then
            JSON="{\"action\": \"promote\", \"class\": $(json_str "$2")}"
        else
            JSON='{"action": "promote"}'
        fi
        ;;
    flee|guard|wait|end_pawn|end_turn)
        JSON="{\"action\": \"$ACTION\"}"
        ;;
    toggle)
        if [ "${2:-on}" = "off" ]; then
            JSON='{"action": "toggle", "enabled": false}'
            echo "Désactivation de CielAI (l'IA locale reprend le camp adverse)..."
        else
            JSON='{"action": "toggle", "enabled": true}'
            echo "Activation de CielAI..."
        fi
        ;;
    ""|-h|--help|help)
        usage
        exit 0
        ;;
    *)
        echo "Action inconnue : $ACTION" >&2
        echo "" >&2
        usage >&2
        exit 1
        ;;
esac

printf '%s' "$JSON" > "$CMD_FILE"
echo "Commande envoyée: $JSON"

# Feedback : Godot écrit le motif d'un éventuel rejet dans ai_feedback.json
if [ "$ACTION" != "toggle" ]; then
    sleep 1.5
    if [ -f "$FEEDBACK_FILE" ]; then
        REJECTED=$(python3 -c "
import json
try:
    d = json.load(open('$FEEDBACK_FILE'))
    if not d.get('ok', True):
        print('⚠️  Rejetée [%s] %s' % (d.get('code_name', d.get('code')), d.get('error', '')))
except Exception:
    pass
" 2>/dev/null)
        if [ -n "$REJECTED" ]; then
            echo "$REJECTED"
        fi
    fi
    echo ""
    bash "$(dirname "${BASH_SOURCE[0]}")/state.sh" 2>/dev/null || true
fi
