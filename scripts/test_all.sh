#!/bin/bash
# Lance toutes les suites headless, avec le bon binaire Godot.
#
# Usage : bash scripts/test_all.sh
#
# Pourquoi ce script existe — deux raisons, toutes deux payées comptant :
#
# 1. Le `godot` du PATH n'est pas celui du projet. Le projet cible 4.3 ; une
#    machine de développement a souvent une version plus récente, qui sème des
#    `.gd.uid` partout. `_paths.sh` résout le bon binaire.
#
# 2. **Une suite peut afficher « 57 OK / 0 ÉCHECS » pendant qu'un script de
#    production ne compile plus.** Godot imprime l'erreur de parsing et continue ;
#    tant qu'aucun test n'emprunte le fichier cassé, le vert est un mensonge.
#    C'est arrivé le 2026-08-06. Ce script relit donc la sortie du moteur et
#    échoue si une erreur de script y apparaît, quel que soit le compte de tests.
#
# Un garde-fou écrit en GDScript ne suffisait pas : `ResourceLoader.load()` rend
# un script cassé sans broncher, et `GDScript.reload()` échoue sur tout fichier
# portant un `class_name` (94 faux positifs sur 107). C'est la sortie du moteur
# qui dit la vérité, pas le moteur interrogé depuis lui-même.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ciel_game/_paths.sh"

if [ -z "$GODOT" ]; then
    echo "Godot introuvable (voir scripts/ciel_game/_paths.sh)." >&2
    exit 1
fi

SUITES=(test_combat test_features test_battle test_map)
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT

failures=0

echo "Godot  : $GODOT"
echo "Projet : $PROJECT_DIR"
echo ""

for suite in "${SUITES[@]}"; do
    log="$LOG_DIR/$suite.log"
    "$GODOT" --headless --path "$PROJECT_DIR" --script "$suite.gd" >"$log" 2>&1
    code=$?

    # Le compte de tests, tel que la suite le rapporte.
    summary=$(grep -oE "RÉSULTATS: [0-9]+ OK / [0-9]+ ÉCHECS" "$log" | tail -1)
    [ -z "$summary" ] && summary=$(grep -oE "ALL TESTS PASSED|TESTS FAILED" "$log" | tail -1)
    [ -z "$summary" ] && summary="(aucun résumé — la suite s'est-elle arrêtée en route ?)"

    # Les erreurs de script, que le compte de tests ignore.
    parse_errors=$(grep -E "SCRIPT ERROR|Parse Error" "$log" | head -5)

    if [ $code -ne 0 ] || [ -n "$parse_errors" ] || echo "$summary" | grep -qE "/ [1-9][0-9]* ÉCHECS|TESTS FAILED"; then
        failures=$((failures + 1))
        printf '  ❌ %-14s %s\n' "$suite" "$summary"
        if [ -n "$parse_errors" ]; then
            echo "     ⚠ erreurs de script (le compte de tests ne les voit pas) :"
            echo "$parse_errors" | sed 's/^/       /'
        fi
    else
        printf '  ✅ %-14s %s\n' "$suite" "$summary"
    fi
done

echo ""
if [ $failures -eq 0 ]; then
    echo "=== TOUTES LES SUITES SONT AU VERT ==="
    exit 0
fi
echo "=== $failures SUITE(S) EN ÉCHEC ===" >&2
exit 1
