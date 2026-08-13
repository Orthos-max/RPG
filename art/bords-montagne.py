#!/usr/bin/env python3
"""Synthétise les seize bords de la **montagne**, que le pack ne dessine pas.

    python3 art/bords-montagne.py [--audit]

`decouper-bords.py` découpe les blocs de seize cellules que le tileset SSCAP
fournit : la rive, la lisière, la plage, le bord de route. La roche n'y a pas
de bloc — elle n'était pas censée border quoi que ce soit dans le jeu d'origine.
Chez nous, la montagne est franchissable (coût 2) : elle touche donc des plaines
en permanence, et il lui faut ses bords comme aux autres.

## Pourquoi ce script existe

Un jeu de bords de montagne existait déjà dans `edges/`, sans script pour le
produire. Il était faux, et de deux façons qu'un audit rend visibles
(`--audit`) :

- les quatre cellules à un seul côté étaient **retournées d'un demi-tour** —
  `mountain_n`, qui dit « la roche s'arrête au nord », portait son herbe au
  sud ;
- les douze autres n'étaient que du remplissage : un îlot de roche entouré
  d'herbe des quatre côtés s'affichait comme un carré de roche plein.

## Ce que celui-ci dessine

La zone de roche est un **rectangle à coins arrondis** : ses bords tombent où le
terrain s'arrête, ses angles saillants sont adoucis d'un rayon égal à la largeur
de bande. C'est ce que fait le pack sur ses propres transitions, et c'est ce qui
empêche une chaîne de montagnes d'avoir l'air taillée à l'équerre.

La frontière est ensuite **bousculée d'un pixel**, par un bruit déterministe :
une arête parfaitement lisse trahit la géométrie qui l'a produite, là où le
reste du plateau est dessiné à la main. Un liseré sombre côté roche finit de la
détacher de l'herbe — le pack en pose un sur le sable et le chemin.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - dépendance d'atelier, pas de jeu
    sys.exit("Pillow manquant : python3 -m pip install Pillow")

RACINE = Path(__file__).resolve().parent.parent
PACK = RACINE / "assets" / "packs" / "sscap-srpg-tileset"
BORDS = RACINE / "assets" / "textures" / "terrain" / "edges"
TAILLE = 32

## Clé du jeu de bords, et les deux tuiles dont il est fait.
CLE = "mountain"
ROCHE = RACINE / "assets" / "textures" / "terrain" / "terrain_mountain_rock.png"
## Cellule de fond : l'herbe rase de `Outdoor` (0, 0), celle de tous les autres
## jeux de bords — une transition de montagne doit tomber sur la même herbe.
FOND = ("Outdoor", 0, 0)

## Les seize voisinages, écrits dans l'ordre n, e, s, w.
MASQUES = ["fill", "n", "e", "s", "w", "ne", "es", "sw", "nw", "ns", "ew",
           "nes", "esw", "nsw", "new", "nesw"]

## Largeur de la bande d'herbe, en pixels — celle des bords du pack.
BANDE = 6.0
## Rayon des angles saillants. Égal à la bande : l'arc rejoint les deux bords
## sans cassure, ce qu'un rayon plus petit ne fait pas.
RAYON = 6.0
## Amplitude du désordre de frontière, en pixels.
DESORDRE = 0.9
## Profondeur du liseré sombre côté roche, en pixels.
LISERE = 1.4
## Ce qu'il reste de la roche sous le liseré.
LISERE_FORCE = 0.74

## Demi-étendue d'un côté que le terrain ne quitte pas — assez grande pour que
## le rectangle déborde largement de la case, assez petite pour rester un float.
LOIN = 1000.0


def _planche(nom: str) -> Image.Image:
    source = PACK / f"{nom}.png"
    if not source.exists():
        sys.exit(f"Planche introuvable : {source}")
    return Image.open(source).convert("RGBA")


def _cellule(planche: str, col: int, rang: int) -> Image.Image:
    image = _planche(planche)
    return image.crop((col * TAILLE, rang * TAILLE,
                       (col + 1) * TAILLE, (rang + 1) * TAILLE))


def _bruit(x: int, y: int) -> float:
    """Désordre déterministe dans [-1, 1] — le même à chaque exécution."""
    melange = (x * 73856093) ^ (y * 19349663) ^ 0x9E3779B9
    return (abs(melange) % 2003) / 2003.0 * 2.0 - 1.0


def _distance(masque: str, x: float, y: float) -> float:
    """Distance signée au bord de la roche : négative dedans, positive dehors.

    La roche occupe un rectangle à coins arrondis dont chaque côté est repoussé
    hors de la case tant que le terrain ne s'y arrête pas — d'où [constant LOIN].
    """
    gauche = BANDE if "w" in masque else -LOIN
    droite = TAILLE - BANDE if "e" in masque else TAILLE + LOIN
    haut = BANDE if "n" in masque else -LOIN
    bas = TAILLE - BANDE if "s" in masque else TAILLE + LOIN

    centre_x, centre_y = (gauche + droite) / 2.0, (haut + bas) / 2.0
    demi_x, demi_y = (droite - gauche) / 2.0, (bas - haut) / 2.0

    # Rectangle à coins arrondis : le rectangle est d'abord rétréci du rayon,
    # puis la distance obtenue est repoussée d'autant. L'arc naît de là.
    qx = abs(x - centre_x) - max(demi_x - RAYON, 0.0)
    qy = abs(y - centre_y) - max(demi_y - RAYON, 0.0)
    dehors = math.hypot(max(qx, 0.0), max(qy, 0.0))
    dedans = min(max(qx, qy), 0.0)
    return dehors + dedans - RAYON


def _tuile(masque: str, roche: Image.Image, herbe: Image.Image) -> Image.Image:
    image = Image.new("RGBA", (TAILLE, TAILLE))
    px_roche, px_herbe, px = roche.load(), herbe.load(), image.load()

    for y in range(TAILLE):
        for x in range(TAILLE):
            distance = _distance(masque, x + 0.5, y + 0.5) \
                + _bruit(x, y) * DESORDRE
            if distance > 0.0:
                px[x, y] = px_herbe[x, y]
            elif distance > -LISERE:
                r, g, b, a = px_roche[x, y]
                px[x, y] = (int(r * LISERE_FORCE), int(g * LISERE_FORCE),
                            int(b * LISERE_FORCE), a)
            else:
                px[x, y] = px_roche[x, y]
    return image


def _cotes_herbe(image: Image.Image) -> str:
    """Les côtés où l'herbe borde la case, lus sur les pixels."""
    px = image.convert("RGB").load()
    herbe = _cellule(*FOND).convert("RGB").load()
    reference = herbe[16, 16]

    bandes = {
        "n": [(x, y) for y in range(4) for x in range(TAILLE)],
        "e": [(x, y) for x in range(TAILLE - 4, TAILLE) for y in range(TAILLE)],
        "s": [(x, y) for y in range(TAILLE - 4, TAILLE) for x in range(TAILLE)],
        "w": [(x, y) for x in range(4) for y in range(TAILLE)],
    }
    cotes = ""
    for cote, points in bandes.items():
        vus = sum(1 for x, y in points
                  if sum((px[x, y][k] - reference[k]) ** 2 for k in range(3)) < 3000)
        if vus / len(points) > 0.4:
            cotes += cote
    return cotes or "fill"


def audit() -> int:
    """Relit les seize tuiles présentes : montrent-elles le bord qu'elles annoncent ?"""
    justes = 0
    for masque in MASQUES:
        chemin = BORDS / f"{CLE}_{masque}.png"
        if not chemin.exists():
            print(f"  {masque:>5} … absente")
            continue
        lu = _cotes_herbe(Image.open(chemin).convert("RGBA"))
        accord = set(lu.replace("fill", "")) == set(masque.replace("fill", ""))
        justes += int(accord)
        print(f"  {masque:>5} → herbe mesurée au {lu:>5} {'' if accord else '⚠'}")
    print(f"\n  {justes}/{len(MASQUES)} cellules conformes")
    return 0


def main(faire_audit: bool) -> int:
    if faire_audit:
        return audit()

    if not ROCHE.exists():
        sys.exit(f"Tuile de roche introuvable : {ROCHE}\n"
                 "Lance d'abord : python3 art/decouper-tuiles.py")

    roche = Image.open(ROCHE).convert("RGBA")
    herbe = _cellule(*FOND).convert("RGBA")

    BORDS.mkdir(parents=True, exist_ok=True)
    for masque in MASQUES:
        _tuile(masque, roche, herbe).save(BORDS / f"{CLE}_{masque}.png")
    print(f"16 bords de montagne écrits dans {BORDS.relative_to(RACINE)}/{CLE}_*.png")
    print("Contrôle : python3 art/bords-montagne.py --audit")
    return 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--audit", action="store_true",
                         help="relit les tuiles en place, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(main(args.audit))
