#!/bin/bash
# Lit l'état du jeu exporté par CielAI (ai_state.json).
# Usage: bash scripts/ciel_game/state.sh [--watch|--raw|--events|--tiles <nom>]

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_paths.sh"

MODE="${1:-summary}"
ARG="${2:-}"

render() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "Aucun état disponible. Le jeu tourne ?"
        echo "Fichier attendu: $STATE_FILE"
        return 1
    fi
    CIEL_STATE_FILE="$STATE_FILE" CIEL_MODE="$1" CIEL_ARG="${2:-}" python3 <<'PY'
import json, os, sys

path = os.environ["CIEL_STATE_FILE"]
mode = os.environ.get("CIEL_MODE", "summary")
arg = os.environ.get("CIEL_ARG", "")

try:
    with open(path) as fh:
        data = json.load(fh)
except Exception as exc:
    print("Erreur de lecture de l'état (%s). Essaie --raw." % exc)
    sys.exit(1)

pawns = data.get("pawns", [])

def fmt_pawn(p, active):
    marker = "◈ " if active else "  "
    flags = ""
    if not p.get("can_move") and not p.get("can_attack"):
        flags = " [terminé]"
    elif not p.get("can_move"):
        flags = " [attaque seule]"
    elif not p.get("can_attack"):
        flags = " [mouvement seul]"
    head = "║ %s%-18s HP:%2s/%-3s [%s,%s] M:%s R:%s%s" % (
        marker, p.get("name", "?"), p.get("hp", "?"), p.get("max_hp", "?"),
        p.get("grid_col", "?"), p.get("grid_row", "?"),
        p.get("movement", "?"), p.get("attack_range", "?"), flags)
    stats = "║   Str:%-2s Mag:%-2s Skl:%-2s Spd:%-2s Def:%-2s Res:%-2s Lv:%-2s %s" % (
        p.get("str", "?"), p.get("mag", "?"), p.get("skl", "?"), p.get("spd", "?"),
        p.get("def", "?"), p.get("res", "?"), p.get("level", "?"),
        p.get("class_name", ""))
    extra = ""
    terrain = p.get("terrain")
    if terrain:
        extra = "║   Terrain: %s (+%s DEF)" % (terrain, p.get("terrain_def", 0))
    return "\n".join(x for x in [head, stats, extra] if x)

if mode == "--events":
    events = data.get("events", [])
    if not events:
        print("Aucun événement enregistré.")
    for e in events:
        print("#%-4s %-16s %s" % (
            e.get("seq", "?"), e.get("kind_name", "?"),
            ", ".join("%s=%s" % (k, v) for k, v in e.items()
                      if k not in ("seq", "kind", "kind_name", "t"))))
    sys.exit(0)

if mode == "--tiles":
    target = arg.lower()
    for p in pawns:
        if p.get("name", "").lower() != target:
            continue
        print("Portée de %s :" % p.get("name"))
        print("  Déplacement : %s" % ", ".join(
            "(%s,%s)" % (t.get("col"), t.get("row")) for t in p.get("reachable_tiles", [])) or "—")
        print("  Attaque     : %s" % ", ".join(
            "(%s,%s)" % (t.get("col"), t.get("row")) for t in p.get("attack_tiles", [])) or "—")
        sys.exit(0)
    print("Pion introuvable : %s" % arg)
    sys.exit(1)

# --- Résumé ---
grid = data.get("grid_size", {})
print("Turn %s | %s | Stage: %s (%s) | seq %s" % (
    data.get("turn_number", "?"), data.get("turn", "?"),
    data.get("stage_name", "?"), data.get("stage", "?"), data.get("seq", "?")))
print("Mode: %s | Difficulté: %s | Contrôle adverse: %s" % (
    data.get("mode", "?"), data.get("difficulty", "?"), data.get("opponent_controller", "?")))
if data.get("current_pawn"):
    print("Actif: %s" % data["current_pawn"])
if data.get("message"):
    print("Message: %s" % data["message"])
if data.get("last_error"):
    print("⚠️  Dernier rejet: %s" % data["last_error"])
print("Grid: %sx%s | Objectif: %s" % (
    grid.get("x", "?"), grid.get("y", "?"), data.get("objective", "—")))

if not pawns:
    print("\nAucun pion sur le terrain.")
    sys.exit(0)

cp = data.get("current_pawn", "")
players = [p for p in pawns if p.get("team") == "player" and p.get("alive")]
opponents = [p for p in pawns if p.get("team") == "opponent" and p.get("alive")]
dead = [p for p in pawns if not p.get("alive")]

print("\n╔══ PLAYER (%d vivants) ══════════════════════" % len(players))
for p in players:
    print(fmt_pawn(p, p.get("name") == cp))
print("╠══ OPPONENT (%d vivants) ════════════════════" % len(opponents))
for p in opponents:
    print(fmt_pawn(p, p.get("name") == cp))
if dead:
    print("╠══ TOMBÉS ══════════════════════════════════")
    for p in dead:
        print("║   %s (%s)" % (p.get("name"), p.get("team")))
print("╚════════════════════════════════════════════")

events = data.get("events", [])[-5:]
if events:
    print("\nDerniers événements :")
    for e in events:
        if e.get("kind_name") == "attack":
            print("  #%s %s → %s : %s dmg%s%s" % (
                e.get("seq"), e.get("attacker"), e.get("defender"), e.get("damage"),
                " CRIT" if e.get("crit") else "", " (raté)" if not e.get("hit") else ""))
        elif e.get("kind_name") == "death":
            print("  #%s ☠ %s (%s)" % (e.get("seq"), e.get("pawn"), e.get("team")))
        else:
            print("  #%s %s" % (e.get("seq"), e.get("kind_name")))
PY
}

case "$MODE" in
    --watch)
        while true; do
            clear
            echo "=== Ciel Emblem — état du jeu ==="
            echo ""
            render summary || true
            sleep 0.5
        done
        ;;
    --raw)
        cat "$STATE_FILE" 2>/dev/null || echo "{}"
        ;;
    --path)
        echo "userdata : $USERDATA_DIR"
        echo "state    : $STATE_FILE"
        echo "command  : $CMD_FILE"
        echo "feedback : $FEEDBACK_FILE"
        echo "replays  : $REPLAY_DIR"
        ;;
    --events|--tiles)
        render "$MODE" "$ARG"
        ;;
    *)
        render summary
        ;;
esac
