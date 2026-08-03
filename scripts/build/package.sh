#!/bin/bash
# Packaging de Ciel Emblem : transforme les exports en livrables distribuables.
#
#   macOS   → CielEmblem.dmg (create-dmg si présent, sinon hdiutil)
#   Windows → CielEmblem-windows.zip (exe + pont CielAI + notice)
#   Linux   → CielEmblem-linux.tar.gz (binaire + .desktop + install.sh)
#
# Usage :
#   bash scripts/build/package.sh                 # plateforme courante
#   bash scripts/build/package.sh macos windows linux
#   bash scripts/build/package.sh --no-export macos   # empaquette sans réexporter

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../ciel_game/_paths.sh"

BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$BUILD_DIR/dist"
VERSION="$(grep -m1 '^config/version=' "$PROJECT_DIR/project.godot" | cut -d'"' -f2)"
VERSION="${VERSION:-0.0.0}"
RUN_EXPORT=1

if [ "${1:-}" = "--no-export" ]; then
    RUN_EXPORT=0
    shift
fi

default_target() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "linux" ;;
    esac
}

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("$(default_target)")
fi

mkdir -p "$DIST_DIR"

# Notice glissée dans chaque archive, pour un joueur non technique.
write_readme() {
    local dest="$1"
    cat > "$dest" <<EOF
Ciel Emblem $VERSION
====================

Tactical RPG au tour par tour. Le camp adverse peut être joué par une IA
externe (Ciel) via un simple échange de fichiers JSON.

Lancer le jeu
-------------
  macOS   : double-cliquer sur Ciel Emblem.app
            (premier lancement : clic droit -> Ouvrir -> Ouvrir)
  Windows : double-cliquer sur CielEmblem.exe
  Linux   : ./CielEmblem.x86_64  (ou bash install.sh)

Modes
-----
  Nouvelle partie        campagne solo (3 chapitres)
  Escarmouche CielAI     l'IA externe tient le camp adverse
  Duel local             deux joueurs sur la même machine
  Partie en ligne        l'hôte annonce un code, l'invité le saisit

Piloter l'IA externe
--------------------
  bash ciel_game/state.sh            état de la partie
  bash ciel_game/command.sh ...      envoyer un ordre
  bash ciel_game/state.sh --path     où sont les fichiers d'échange

Documentation complète : docs/INSTALL.md et docs/CIEL_PROTOCOL.md du dépôt.
EOF
}

package_macos() {
    local app_zip="$BUILD_DIR/macos/CielEmblem.zip"
    if [ ! -f "$app_zip" ]; then
        echo "✘ Export macOS introuvable ($app_zip)." >&2
        return 1
    fi

    local staging="$BUILD_DIR/macos/staging"
    rm -rf "$staging"
    mkdir -p "$staging"
    unzip -q "$app_zip" -d "$staging" || return 1

    cp -R "$PROJECT_DIR/scripts/ciel_game" "$staging/ciel_game"
    write_readme "$staging/LISEZ-MOI.txt"

    local dmg="$DIST_DIR/CielEmblem-$VERSION-macos.dmg"
    rm -f "$dmg"

    if command -v create-dmg >/dev/null 2>&1; then
        create-dmg --volname "Ciel Emblem" --app-drop-link 480 180 \
            "$dmg" "$staging" >/dev/null 2>&1 || true
    fi
    if [ ! -f "$dmg" ]; then
        # Repli sans dépendance : hdiutil est fourni avec macOS.
        hdiutil create -quiet -volname "Ciel Emblem" -srcfolder "$staging" \
            -ov -format UDZO "$dmg" || return 1
    fi

    echo "✔ $dmg"
}

package_windows() {
    local exe="$BUILD_DIR/windows/CielEmblem.exe"
    if [ ! -f "$exe" ]; then
        echo "✘ Export Windows introuvable ($exe)." >&2
        return 1
    fi

    local staging="$BUILD_DIR/windows/staging"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp "$exe" "$staging/"
    [ -f "$BUILD_DIR/windows/CielEmblem.pck" ] && cp "$BUILD_DIR/windows/CielEmblem.pck" "$staging/"
    cp -R "$PROJECT_DIR/scripts/ciel_game" "$staging/ciel_game"
    write_readme "$staging/LISEZ-MOI.txt"

    local archive="$DIST_DIR/CielEmblem-$VERSION-windows.zip"
    rm -f "$archive"
    (cd "$staging" && zip -qr "$archive" .) || return 1
    echo "✔ $archive"
}

package_linux() {
    local bin="$BUILD_DIR/linux/CielEmblem.x86_64"
    if [ ! -f "$bin" ]; then
        echo "✘ Export Linux introuvable ($bin)." >&2
        return 1
    fi

    local staging="$BUILD_DIR/linux/staging"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp "$bin" "$staging/"
    chmod +x "$staging/CielEmblem.x86_64"
    [ -f "$BUILD_DIR/linux/CielEmblem.pck" ] && cp "$BUILD_DIR/linux/CielEmblem.pck" "$staging/"
    cp -R "$PROJECT_DIR/scripts/ciel_game" "$staging/ciel_game"
    write_readme "$staging/LISEZ-MOI.txt"

    # Raccourci de bureau + installateur minimal, sans dépendance à Godot.
    cat > "$staging/ciel-emblem.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Ciel Emblem
Comment=Tactical RPG au tour par tour
Exec=%INSTALL_DIR%/CielEmblem.x86_64
Icon=%INSTALL_DIR%/icon.png
Categories=Game;StrategyGame;
Terminal=false
EOF
    cp "$PROJECT_DIR/assets/textures/ui/icons/icon.png" "$staging/icon.png" 2>/dev/null || true

    cat > "$staging/install.sh" <<'EOF'
#!/bin/bash
# Installe Ciel Emblem dans ~/.local et pose un raccourci.
set -euo pipefail
INSTALL_DIR="${1:-$HOME/.local/share/ciel-emblem}"
mkdir -p "$INSTALL_DIR" "$HOME/.local/share/applications"
cp -R "$(dirname "$0")"/* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/CielEmblem.x86_64"
sed "s|%INSTALL_DIR%|$INSTALL_DIR|g" "$INSTALL_DIR/ciel-emblem.desktop" \
    > "$HOME/.local/share/applications/ciel-emblem.desktop"
echo "Ciel Emblem installé dans $INSTALL_DIR"
echo "Lancement : $INSTALL_DIR/CielEmblem.x86_64 (ou via le menu des applications)"
EOF
    chmod +x "$staging/install.sh"

    local archive="$DIST_DIR/CielEmblem-$VERSION-linux.tar.gz"
    rm -f "$archive"
    tar -czf "$archive" -C "$staging" . || return 1
    echo "✔ $archive"
}

FAILED=0
for target in "${TARGETS[@]}"; do
    if [ $RUN_EXPORT -eq 1 ]; then
        bash "$(dirname "${BASH_SOURCE[0]}")/export.sh" "$target" || { FAILED=1; continue; }
    fi
    case "$target" in
        macos)   package_macos   || FAILED=1 ;;
        windows) package_windows || FAILED=1 ;;
        linux)   package_linux   || FAILED=1 ;;
        *)       echo "Cible inconnue : $target" >&2; FAILED=1 ;;
    esac
done

echo ""
if [ $FAILED -ne 0 ]; then
    echo "Packaging incomplet — voir docs/INSTALL.md." >&2
    exit 1
fi
echo "Livrables dans : $DIST_DIR"
