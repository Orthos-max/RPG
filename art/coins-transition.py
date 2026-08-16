#!/usr/bin/env python3
"""Synthétise les **coins rentrants** des transitions de terrain.

    python3 art/coins-transition.py [--apercu]

`decouper-bords.py` a extrait les seize cellules que le pack dessine par
terrain : celles qui disent « mon terrain s'arrête ici, de ce côté-ci ». Seize
cellules couvrent les seize voisinages **en croix** — nord, est, sud, ouest — et
c'est tout ce qu'un tel jeu peut couvrir.

Il manque donc le cas qui ne se voit qu'en diagonale. Un étang en forme de L a,
au creux du L, une case entourée d'eau des quatre côtés : son masque est `fill`,
elle affiche donc un carré d'eau plein — et l'herbe qui vient mordre ce creux y
dessine un angle droit parfait, exactement le damier qu'on cherchait à effacer.
Les coins *saillants* sont arrondis par le pack, les coins *rentrants* restent
au cordeau.

## La forme, déduite du pack plutôt qu'inventée

Le morceau à poser est une lampée de fond dans un coin de la case. Sa taille
n'est pas choisie : elle est **mesurée** sur la bande que le pack lui-même
dessine (`<terrain>_n.png` contre `<terrain>_fill.png`), pour qu'un coin
rentrant morde aussi profond qu'un bord ordinaire. Un quart de disque de ce
rayon, découpé dans le fond de la cellule de coin (`<terrain>_ne.png`), donne
l'arrondi ; un dégradé d'alpha sur le dernier pixel évite l'escalier.

Les fichiers sortent à côté des bords, nommés `<terrain>_corner_ne.png` —
`ne` étant le coin, pas le côté. [TacticsAutoTiler] les compose par-dessus la
tuile de la case quand elle en a besoin.

`--apercu` n'écrit rien dans le jeu : il dépose dans `/tmp` une planche qui
montre, terrain par terrain, le creux avant et après.
"""

from __future__ import annotations

import argparse
import math
import statistics
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - dépendance d'atelier, pas de jeu
    sys.exit("Pillow manquant : python3 -m pip install Pillow")

RACINE = Path(__file__).resolve().parent.parent
BORDS = RACINE / "assets" / "textures" / "terrain" / "edges"
TAILLE = 32

## Les terrains habillés par [TacticsAutoTiler] — mêmes clés que `EDGE_SETS`.
TERRAINS = ["water", "forest", "sand", "path", "mountain", "fort", "village"]

## Les quatre coins, et le sommet de case d'où part leur quart de disque (px).
COINS: dict[str, tuple[int, int]] = {
    "ne": (TAILLE, 0),
    "es": (TAILLE, TAILLE),
    "sw": (0, TAILLE),
    "nw": (0, 0),
}

## Cellule où lire le fond : l'îlot, qui s'arrête des quatre côtés.
##
## On pourrait lire chaque coin dans la cellule qui porte son nom (`_ne` pour le
## coin nord-est) et c'est ce qui se faisait d'abord — mais les bords de montagne
## sont synthétiques et leur bande de fond ne va pas jusqu'au sommet du carré :
## le coin y ramassait de la roche, donc un creux invisible. L'îlot, lui, est
## entouré de fond sur ses quatre côtés dans **tous** les jeux de bords.
CELLULE_FOND = "nesw"

## Écart quadratique au-delà duquel un pixel n'est plus « le remplissage ».
##
## Relevé sur les quatre planches : le fond d'herbe s'écarte du remplissage de
## plusieurs milliers, le grain interne d'une même tuile de quelques dizaines.
SEUIL_ECART = 1200

## Ce qu'on donne au creux, par rapport à la bande mesurée.
##
## À 1,0 le coin rentrant mord exactement aussi profond qu'un bord droit — c'est
## juste géométriquement, et invisible : un angle droit de trente-deux pixels
## adouci sur cinq se lit encore comme un angle droit. Une moitié de plus suffit
## à ce que l'œil voie une courbe, sans que le creux entame le motif de la case.
RAYON_FACTEUR = 1.5

## Bornes du rayon, en pixels.
##
## Un rayon nul rendrait le fichier inutile, un rayon de plus d'un tiers de case
## mangerait la case au lieu d'en adoucir l'angle.
RAYON_MIN = 6
RAYON_MAX = 11


def _tuile(terrain: str, masque: str) -> Image.Image:
    chemin = BORDS / f"{terrain}_{masque}.png"
    if not chemin.exists():
        sys.exit(f"Tuile de bord introuvable : {chemin}\n"
                 "Lance d'abord : python3 art/decouper-bords.py")
    return Image.open(chemin).convert("RGBA")


def _ecart(a, b) -> int:
    return sum((a[k] - b[k]) ** 2 for k in range(3))


def _epaisseur_bande(terrain: str) -> int:
    """Profondeur, en pixels, de la bande de fond que le pack dessine au nord.

    Colonne par colonne : combien de pixels du haut diffèrent du remplissage.
    On garde la **médiane** — une lisière de forêt a des trouées et des
    débordements, et une moyenne les suivrait.
    """
    bord = _tuile(terrain, "n").convert("RGB").load()
    plein = _tuile(terrain, "fill").convert("RGB").load()

    profondeurs: list[int] = []
    for x in range(TAILLE):
        profondeur = 0
        for y in range(TAILLE):
            if _ecart(bord[x, y], plein[x, y]) < SEUIL_ECART:
                break
            profondeur += 1
        profondeurs.append(profondeur)

    mediane = statistics.median(profondeurs) * RAYON_FACTEUR
    return max(RAYON_MIN, min(RAYON_MAX, int(round(mediane))))


def _coin(terrain: str, coin: str, rayon: int) -> Image.Image:
    """Le quart de disque de fond à poser dans un coin de la case."""
    cx, cy = COINS[coin]
    source = _tuile(terrain, CELLULE_FOND).convert("RGB").load()

    image = Image.new("RGBA", (TAILLE, TAILLE), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(TAILLE):
        for x in range(TAILLE):
            distance = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if distance >= rayon:
                continue
            # Le dernier pixel s'évanouit : sans lui l'arrondi redevient un
            # escalier, et on aurait remplacé un angle droit par douze.
            alpha = 255 if distance <= rayon - 1.0 else int(255 * (rayon - distance))
            r, g, b = source[x, y]
            pixels[x, y] = (r, g, b, alpha)
    return image


def _apercu(terrain: str, rayon: int) -> Image.Image:
    """Trois cases côte à côte : le creux nu, le coin seul, le creux adouci."""
    plein = _tuile(terrain, "fill")
    coin = _coin(terrain, "ne", rayon)
    adouci = plein.copy()
    adouci.alpha_composite(coin)

    damier = Image.new("RGBA", (TAILLE * 3 + 8, TAILLE), (40, 40, 40, 255))
    for i, tuile in enumerate([plein, coin, adouci]):
        damier.alpha_composite(tuile, (i * (TAILLE + 4), 0))
    return damier


def main(apercu: bool) -> int:
    planches: list[Image.Image] = []
    ecrites = 0

    for terrain in TERRAINS:
        rayon = _epaisseur_bande(terrain)
        print(f"{terrain:<9} bande mesurée à {rayon} px")
        if apercu:
            planches.append(_apercu(terrain, rayon))
            continue
        for coin in COINS:
            _coin(terrain, coin, rayon).save(BORDS / f"{terrain}_corner_{coin}.png")
            ecrites += 1
        print(f"  4 coins → {BORDS.relative_to(RACINE)}/{terrain}_corner_*.png")

    if apercu:
        largeur = max(p.width for p in planches)
        planche = Image.new("RGBA", (largeur, sum(p.height + 4 for p in planches)))
        y = 0
        for p in planches:
            planche.alpha_composite(p, (0, y))
            y += p.height + 4
        zoom = planche.resize((planche.width * 8, planche.height * 8), Image.NEAREST)
        zoom.save("/tmp/coins-transition.png")
        print("\nAperçu : /tmp/coins-transition.png")
        return 0

    print(f"\n{ecrites} coins rentrants écrits dans {BORDS.relative_to(RACINE)}")
    return 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--apercu", action="store_true",
                         help="dépose une planche de contrôle dans /tmp, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(main(args.apercu))
