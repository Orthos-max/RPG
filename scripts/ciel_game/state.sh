#!/bin/bash
# Lit l'état du jeu exporté par CielAI
# Usage: bash scripts/ciel_game/state.sh [--watch]

STATE_FILE="$HOME/Library/Application Support/Godot/app_userdata/Godot Tactical RPG/ai_state.json"

if [ "$1" = "--watch" ]; then
    # Mode watch : affiche l'état toutes les 0.5s
    while true; do
        clear
        echo "=== CielAI Game State ==="
        echo ""
        if [ -f "$STATE_FILE" ]; then
            python3 -m json.tool "$STATE_FILE" 2>/dev/null || cat "$STATE_FILE"
        else
            echo "(en attente du fichier d'état...)"
        fi
        sleep 0.5
    done
elif [ "$1" = "--raw" ]; then
    cat "$STATE_FILE" 2>/dev/null || echo "{}"
else
    if [ -f "$STATE_FILE" ]; then
        python3 -c "
import json, sys
data = json.load(open('$STATE_FILE'))

# Turn info
turn = data.get('turn', '?')
stage = data.get('stage_name', '?')
cp = data.get('current_pawn', '')
grid = data.get('grid_size', {})
message = data.get('message', '')

print(f'Turn: {turn} | Stage: {stage} ({data.get(\"stage\", \"?\")})')
if cp:
    print(f'Active: {cp}')
if message:
    print(f'Message: {message}')
print(f'Grid: {grid.get(\"x\", \"?\")}×{grid.get(\"y\", \"?\")}')

# Pawns
pawns = data.get('pawns', [])
if pawns:
    player_pawns = [p for p in pawns if p['team'] == 'player' and p['alive']]
    opponent_pawns = [p for p in pawns if p['team'] == 'opponent' and p['alive']]
    dead_pawns = [p for p in pawns if not p['alive']]
    
    print(f'\n╔══ PLAYER ({len(player_pawns)} alive) ═══════════════════════')
    for p in player_pawns:
        marker = '◈ ' if p['name'] == cp else '  '
        print(f'║ {marker}{p[\"name\"]:<18} HP:{p[\"hp\"]:>2}/{p[\"max_hp\"]:<2}  [{p[\"grid_col\"]},{p[\"grid_row\"]}]  M:{p[\"movement\"]} R:{p[\"attack_range\"]}')
        print(f'║   Str:{p[\"str\"]:<2} Mag:{p[\"mag\"]:<2} Skl:{p[\"skl\"]:<2} Spd:{p[\"spd\"]:<2} Def:{p[\"def\"]:<2} Res:{p[\"res\"]:<2}')
    
    print(f'╠══ OPPONENT ({len(opponent_pawns)} alive) ════════════════════')
    for p in opponent_pawns:
        marker = '◈ ' if p['name'] == cp else '  '
        can = ''
        if not p['can_move'] and not p['can_attack']:
            can = ' [done]'
        elif not p['can_move']:
            can = ' [atk only]'
        elif not p['can_attack']:
            can = ' [move only]'
        print(f'║ {marker}{p[\"name\"]:<18} HP:{p[\"hp\"]:>2}/{p[\"max_hp\"]:<2}  [{p[\"grid_col\"]},{p[\"grid_row\"]}]  M:{p[\"movement\"]} R:{p[\"attack_range\"]}{can}')
        print(f'║   Str:{p[\"str\"]:<2} Mag:{p[\"mag\"]:<2} Skl:{p[\"skl\"]:<2} Spd:{p[\"spd\"]:<2} Def:{p[\"def\"]:<2} Res:{p[\"res\"]:<2}')
    
    if dead_pawns:
        print(f'╠══ DEAD ══════════════════════════════════════')
        for p in dead_pawns:
            print(f'║   {p[\"name\"]} ({p[\"team\"]})')
    
    print(f'╚═══════════════════════════════════════════════════')
else:
    print('\nAucun pion sur le terrain.')
" 2>/dev/null || echo "Erreur parsing JSON. Utilise --raw pour voir le contenu brut."
    else
        echo "Aucun état disponible. Le jeu tourne ?"
        echo "Fichier attendu: $STATE_FILE"
    fi
fi
