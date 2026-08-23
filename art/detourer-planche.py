#!/usr/bin/env python3
"""Détoure une planche de figurine : rend transparent le fond opaque qui l'entoure.

    python3 art/detourer-planche.py assets/textures/pawns/elfe_rousse_v2_pawn.png
    python3 art/detourer-planche.py --verifier <planche.png>

## Pourquoi ce script existe

Le format des planches est « `.png`, **fond transparent** »
(`assets/textures/actor/README.md`). Une planche dessinée hors de l'atelier — à
la commande, dans un éditeur qui aplatit ses calques, ou par une IA d'images —
arrive régulièrement avec un **rectangle de fond opaque** sous le personnage :
transparente sur ses marges, blanche derrière lui. Rien ne le signale à
l'import, et les vérifications rapides (« les coins sont bien à alpha 0 ? »)
passent au vert.

En jeu, le résultat est un pion posé sur un carton clair, au milieu d'un plateau
où toutes les autres figurines sont détourées. C'était le cas de la planche de
l'elfe rousse : 4 228 pixels blancs opaques, soit 40 % de sa surface dessinée.

## Ce qu'il fait, et ce qu'il ne fait pas

Un **remplissage par diffusion depuis les bords** : on part des quatre bordures
de l'image et on avance de proche en proche (4-connexité) tant qu'on traverse
du transparent ou du fond ; ce qui est atteint devient transparent.

C'est ce qui distingue le fond du personnage. Une teinte de fond peut très bien
servir aussi au dessin — le blanc du chemisier de l'elfe est le même blanc que
son carton — et un simple « tous les pixels blancs deviennent transparents »
percerait des trous dans le vêtement. La diffusion, elle, s'arrête au contour :
sur la planche de l'elfe, 3 896 pixels de carton partent, les 332 pixels blancs
du chemisier et des yeux restent.

Le fond est **reconnu à sa couleur** (`--fond`, blanc pur par défaut) et à son
opacité : rien n'est deviné, une planche déjà propre ressort inchangée.

`--verifier` n'écrit rien : il compte ce qui partirait. C'est de quoi passer une
planche en revue avant de l'accepter dans `assets/`.
"""

from __future__ import annotations

import argparse
import sys
from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - dépendance d'atelier, pas de jeu
    sys.exit("Pillow manquant : python3 -m pip install Pillow")

## Écart toléré sur chaque canal pour reconnaître la couleur de fond.
##
## Le pixel art ne lisse pas ses bords : le fond est d'une seule teinte, à la
## valeur près. Une tolérance large mordrait sur le dessin.
TOLERANCE = 5


def _est_fond(pixel: tuple[int, int, int, int], fond: tuple[int, int, int]) -> bool:
    """Ce pixel peut-il faire partie du fond — déjà transparent, ou de sa teinte ?"""
    rouge, vert, bleu, alpha = pixel
    if alpha == 0:
        return True
    return all(abs(a - b) <= TOLERANCE for a, b in zip((rouge, vert, bleu), fond))


def carton(image: Image.Image, fond: tuple[int, int, int]) -> set[tuple[int, int]]:
    """Les pixels **opaques** du fond, atteints depuis les bords de la planche."""
    largeur, hauteur = image.size
    pixels = image.load()

    vus: set[tuple[int, int]] = set()
    file: deque[tuple[int, int]] = deque()

    def semer(x: int, y: int) -> None:
        if (x, y) not in vus and _est_fond(pixels[x, y], fond):
            vus.add((x, y))
            file.append((x, y))

    for x in range(largeur):
        semer(x, 0)
        semer(x, hauteur - 1)
    for y in range(hauteur):
        semer(0, y)
        semer(largeur - 1, y)

    while file:
        x, y = file.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < largeur and 0 <= ny < hauteur:
                semer(nx, ny)

    return {(x, y) for (x, y) in vus if pixels[x, y][3] != 0}


def detourer(chemin: Path, fond: tuple[int, int, int], ecrire: bool) -> int:
    """Détoure une planche et rend le nombre de pixels de fond trouvés."""
    image = Image.open(chemin).convert("RGBA")
    a_effacer = carton(image, fond)
    if ecrire and a_effacer:
        pixels = image.load()
        for x, y in a_effacer:
            pixels[x, y] = (0, 0, 0, 0)
        image.save(chemin)
    return len(a_effacer)


def _couleur(texte: str) -> tuple[int, int, int]:
    valeur = int(texte.lstrip("#"), 16)
    return (valeur >> 16) & 0xFF, (valeur >> 8) & 0xFF, valeur & 0xFF


def main() -> int:
    parseur = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parseur.add_argument("planches", nargs="+", type=Path, help="les .png à détourer")
    parseur.add_argument("--fond", type=_couleur, default=(255, 255, 255),
                         metavar="RRGGBB", help="couleur du fond (défaut : blanc pur)")
    parseur.add_argument("--verifier", action="store_true",
                         help="ne rien écrire, seulement compter")
    args = parseur.parse_args()

    total = 0
    for planche in args.planches:
        if not planche.is_file():
            print(f"  ⚠ {planche} : introuvable")
            continue
        efface = detourer(planche, args.fond, not args.verifier)
        total += efface
        verbe = "à détourer" if args.verifier else "détourés"
        etat = f"{efface} pixels de fond {verbe}" if efface else "déjà propre"
        print(f"  {'·' if efface else '✓'} {planche} : {etat}")
    return 0 if (args.verifier or total >= 0) else 1


if __name__ == "__main__":
    sys.exit(main())
