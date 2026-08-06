#!/bin/bash
# Double-cliquer pour jouer à Ciel Emblem — sans ouvrir l'éditeur Godot.
#
# Ce n'est pas le jeu exporté : c'est le projet lancé directement par le moteur,
# ce qui suffit pour y jouer sur cette machine. Le vrai `.app` / `.exe`
# autonome (celui qu'on donne à quelqu'un qui n'a pas Godot) sort de
# `scripts/build/package.sh`, une fois les modèles d'exportation installés.
#
# macOS ouvre les fichiers .command dans le Terminal. Si un jour il refuse :
#   chmod +x Jouer.command

cd "$(dirname "$0")" || exit 1
exec bash scripts/ciel_game/launch.sh "$@"
