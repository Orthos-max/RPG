#!/bin/bash
# Test réseau à deux processus : lance un hôte, puis un invité qui le rejoint
# avec le code d'accès, et vérifie le relais d'ordre et la diffusion d'état.
#
# Usage : bash scripts/test_net.sh

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ciel_game/_paths.sh"

if [ -z "$GODOT" ]; then
    echo "Godot introuvable (définir GODOT_BIN)." >&2
    exit 1
fi

# Test en boucle locale : sur une machine à plusieurs interfaces (VPN, VM…),
# l'adresse annoncée peut ne pas être joignable depuis elle-même.
export CIEL_HOST_IP="${CIEL_HOST_IP:-127.0.0.1}"

TMP="${TMPDIR:-/tmp}/ciel_net_test"
mkdir -p "$TMP"
HOST_LOG="$TMP/host.log"
CLIENT_LOG="$TMP/client.log"
rm -f "$HOST_LOG" "$CLIENT_LOG"

echo "▶ Démarrage de l'hôte…"
"$GODOT" --headless --path "$PROJECT_DIR" --script res://tests/test_net.gd -- host > "$HOST_LOG" 2>&1 &
HOST_PID=$!

# Attente du code d'accès (5 s max)
CODE=""
for _ in $(seq 1 25); do
    CODE=$(grep -o 'NET_CODE=[A-Z0-9]*' "$HOST_LOG" 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$CODE" ] && break
    sleep 0.2
done

if [ -z "$CODE" ]; then
    echo "✘ L'hôte n'a pas publié de code :" >&2
    cat "$HOST_LOG" >&2
    kill $HOST_PID 2>/dev/null
    exit 1
fi
echo "  code d'accès : $CODE"

echo "▶ Connexion de l'invité…"
"$GODOT" --headless --path "$PROJECT_DIR" --script res://tests/test_net.gd -- client "$CODE" > "$CLIENT_LOG" 2>&1
CLIENT_STATUS=$?

wait $HOST_PID 2>/dev/null
HOST_STATUS=$?

check() {
    if grep -q "$2" "$1"; then
        echo "  ✅ $3"
        return 0
    fi
    echo "  ❌ $3"
    return 1
}

echo ""
echo "Résultats :"
FAILED=0
check "$HOST_LOG"   "NET_DECODE_OK=true"       "code d'accès : encodage/décodage cohérents" || FAILED=1
check "$HOST_LOG"   "NET_PEER_CONNECTED=true"  "l'invité s'est connecté à l'hôte" || FAILED=1
check "$CLIENT_LOG" "NET_JOINED=true"          "l'invité confirme la connexion" || FAILED=1
check "$CLIENT_LOG" "NET_STATE_RECEIVED=true"  "l'état de l'hôte est reçu par l'invité" || FAILED=1
check "$HOST_LOG"   "NET_COMMAND_RELAYED=true" "l'ordre de l'invité atteint la validation de l'hôte" || FAILED=1
check "$CLIENT_LOG" "NET_FEEDBACK_OK="         "l'invité reçoit un acquittement" || FAILED=1
check "$HOST_LOG"   "NET_SEAT_RESERVED=true"   "coupure : l'hôte garde la place de l'invité" || FAILED=1
check "$CLIENT_LOG" "NET_RECONNECTING=true"    "l'invité retente la connexion tout seul" || FAILED=1
check "$CLIENT_LOG" "NET_RECONNECTED=true"     "l'invité est revenu dans le délai de grâce" || FAILED=1
check "$HOST_LOG"   "NET_SEAT_RESTORED=true"   "l'hôte rend son camp au revenant" || FAILED=1
check "$CLIENT_LOG" "NET_STATE_RESYNCED=true"  "l'état complet est renvoyé au revenant" || FAILED=1

echo ""
if [ $FAILED -eq 0 ] && [ $CLIENT_STATUS -eq 0 ] && [ $HOST_STATUS -eq 0 ]; then
    echo "=== TEST RÉSEAU OK ==="
    exit 0
fi

echo "=== TEST RÉSEAU EN ÉCHEC (hôte=$HOST_STATUS invité=$CLIENT_STATUS) ===" >&2
echo "--- host.log ---" >&2; tail -20 "$HOST_LOG" >&2
echo "--- client.log ---" >&2; tail -20 "$CLIENT_LOG" >&2
exit 1
