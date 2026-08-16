#!/bin/bash
# release.sh — Crée une release GitHub avec l'installateur Windows attaché.
# Usage : bash scripts/release.sh v0.3.2 "Titre de la release" "Notes en une ligne"
# Prérequis : build Windows déjà fait (export.sh + package.sh) + gh auth.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?Usage: release.sh <version> <titre> <notes>}"
TITLE="${2:?Titre manquant}"
NOTES="${3:?Notes manquantes}"
ZIP="build/dist/CielEmblem-0.1.0-windows.zip"

[ -f "$ZIP" ] || { echo "✘ $ZIP introuvable — lance d'abord export.sh + package.sh"; exit 1; }

echo "📦 Attache : $ZIP ($(du -h "$ZIP" | cut -f1))"

# Crée la release avec les notes dans un fichier temporaire (les emojis
# dans --notes déclenchent parfois des scans de sécurité inutiles).
NOTES_FILE=$(mktemp)
echo "$NOTES" > "$NOTES_FILE"

if gh release view "$VERSION" --repo Orthos-max/RPG > /dev/null 2>&1; then
  echo "♻️  Release $VERSION existe déjà — mise à jour + re-upload du zip"
  gh release edit "$VERSION" --repo Orthos-max/RPG --title "$TITLE" --notes-file "$NOTES_FILE" --draft=false
else
  echo "🆕 Création de la release $VERSION"
  gh release create "$VERSION" --repo Orthos-max/RPG --title "$TITLE" --notes-file "$NOTES_FILE"
fi

# Upload avec retry : le zip fait ~44 Mo et les connexions lentes peuvent
# faire timeout. On relance tant que l'asset n'est pas visible.
for attempt in 1 2 3; do
  echo "⬆️  Upload (tentative $attempt/3)..."
  if gh release upload "$VERSION" "$ZIP" --repo Orthos-max/RPG --clobber; then
    break
  fi
  [ "$attempt" -lt 3 ] && { echo "⚠️ Échec, nouvelle tentative dans 5s..."; sleep 5; }
done

rm -f "$NOTES_FILE"

# Vérification finale : l'asset doit être visible.
if gh release view "$VERSION" --repo Orthos-max/RPG --json assets -q '.assets[].name' 2>/dev/null | grep -q "CielEmblem-0.1.0-windows.zip"; then
  echo "✅ Release $VERSION publiée avec l'installateur : https://github.com/Orthos-max/RPG/releases/tag/$VERSION"
else
  echo "⚠️ Release créée mais asset non confirmé — vérifie manuellement la page."
fi
