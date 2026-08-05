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

    make_windows_icon "$staging/ciel-emblem.ico"

    local archive="$DIST_DIR/CielEmblem-$VERSION-windows.zip"
    rm -f "$archive"
    make_zip "$staging" "$archive" || return 1
    echo "✔ $archive"

    # L'installeur est un bonus : son absence ne fait pas échouer le packaging,
    # le .zip reste un livrable valable.
    build_windows_installer "$staging" || true
}

# Zippe le contenu d'un dossier. Git Bash (CI Windows) ne fournit pas `zip` :
# on se rabat sur Compress-Archive, toujours présent sous Windows.
make_zip() {
    local src="$1" archive="$2"

    if command -v zip >/dev/null 2>&1; then
        (cd "$src" && zip -qr "$archive" .)
        return $?
    fi

    if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
        powershell.exe -NoProfile -NonInteractive -Command \
            "Compress-Archive -Path '$(cygpath -w "$src")\*' -DestinationPath '$(cygpath -w "$archive")' -Force" \
            >/dev/null 2>&1
        [ -f "$archive" ] && return 0
    fi

    echo "  ✘ Aucun outil de compression disponible (zip / Compress-Archive)." >&2
    return 1
}

# Convertit l'icône du projet en .ico pour l'installeur, si un convertisseur est
# disponible. Sans icône, Inno Setup extrait celle de l'exécutable.
make_windows_icon() {
    local dest="$1"
    local src="$PROJECT_DIR/assets/textures/ui/icons/icon.png"
    [ -f "$src" ] || return 0

    if command -v magick >/dev/null 2>&1; then
        magick "$src" -define icon:auto-resize=256,128,64,48,32,16 "$dest" 2>/dev/null && return 0
    elif command -v convert >/dev/null 2>&1; then
        convert "$src" -define icon:auto-resize=256,128,64,48,32,16 "$dest" 2>/dev/null && return 0
    elif command -v icotool >/dev/null 2>&1; then
        icotool -c -o "$dest" "$src" 2>/dev/null && return 0
    fi
    rm -f "$dest"
    return 0
}

# Localise le compilateur Inno Setup : natif sous Windows, via Wine ailleurs.
# Renseigne ISCC_CMD (tableau) et ISCC_WINE (1 si les chemins doivent être
# traduits en chemins Windows).
find_iscc() {
    ISCC_CMD=()
    ISCC_WINE=0

    # Chemin imposé (CI Windows : Inno Setup est fourni avec l'image, mais hors
    # du PATH de Git Bash). Ailleurs, un ISCC.exe ne s'exécute qu'avec Wine —
    # c'est la branche plus bas qui s'en charge.
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            if [ -n "${ISCC_PATH:-}" ] && [ -f "$ISCC_PATH" ]; then
                ISCC_CMD=("$ISCC_PATH")
                return 0
            fi
            ;;
    esac

    if command -v ISCC.exe >/dev/null 2>&1; then
        ISCC_CMD=("ISCC.exe")
        return 0
    fi
    if command -v iscc >/dev/null 2>&1; then
        ISCC_CMD=("iscc")
        return 0
    fi

    command -v wine >/dev/null 2>&1 || return 1

    # Chemins d'installation habituels d'Inno Setup 6 dans un préfixe Wine.
    local prefix="${WINEPREFIX:-$HOME/.wine}"
    local candidate
    for candidate in \
        "${ISCC_PATH:-}" \
        "$prefix/drive_c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
        "$prefix/drive_c/Program Files/Inno Setup 6/ISCC.exe"
    do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            ISCC_CMD=("wine" "$candidate")
            ISCC_WINE=1
            return 0
        fi
    done
    return 1
}

build_windows_installer() {
    local staging="$1"
    local iss="$PROJECT_DIR/scripts/build/windows/setup.iss"

    if ! find_iscc; then
        echo "  ⓘ Inno Setup introuvable — installeur .exe non généré."
        echo "    Windows : winget install JRSoftware.InnoSetup"
        echo "    macOS/Linux : installer Inno Setup 6 dans un préfixe Wine"
        echo "                  (ou définir ISCC_PATH=/chemin/vers/ISCC.exe)."
        return 1
    fi

    # ISCC ne comprend que des chemins Windows : winepath sous Wine, cygpath
    # sous Git Bash. Sans traduction, il cherche un dossier « /d/a/… » inexistant.
    local iss_arg="$iss" src_arg="$staging" out_arg="$DIST_DIR"
    if [ "$ISCC_WINE" -eq 1 ]; then
        iss_arg="$(winepath -w "$iss" 2>/dev/null || echo "$iss")"
        src_arg="$(winepath -w "$staging" 2>/dev/null || echo "$staging")"
        out_arg="$(winepath -w "$DIST_DIR" 2>/dev/null || echo "$DIST_DIR")"
    elif command -v cygpath >/dev/null 2>&1; then
        iss_arg="$(cygpath -w "$iss")"
        src_arg="$(cygpath -w "$staging")"
        out_arg="$(cygpath -w "$DIST_DIR")"
    fi

    echo "▶ Compilation de l'installeur Windows (Inno Setup)…"
    local log="$BUILD_DIR/iscc.log"
    "${ISCC_CMD[@]}" \
        "/DMyAppVersion=$VERSION" \
        "/DSourceDir=$src_arg" \
        "/DOutputDir=$out_arg" \
        "$iss_arg" >"$log" 2>&1

    local setup="$DIST_DIR/Ciel-Emblem-Setup-$VERSION.exe"
    if [ ! -f "$setup" ]; then
        echo "  ✘ Inno Setup a échoué — 20 dernières lignes :" >&2
        tail -n 20 "$log" >&2
        return 1
    fi
    echo "✔ $setup"
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
