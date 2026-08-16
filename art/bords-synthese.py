#!/usr/bin/env python3
"""Synthétise les seize bords de la **neige** et du **marais**, que le pack ne
dessine pas — même logique que `bords-montagne.py`.

    python3 art/bords-synthese.py [--audit]

`decouper-bords.py` découpe les blocs de seize cellules que le tileset SSCAP
fournit : la rive, la lisière, la plage, le bord de route. Ni la neige ni le
marais n'ont de bloc dans le pack — ce sont des terrains de surface qui
bordent en permanence les plaines, et il leur faut leurs bords comme aux
autres.

## Ce que le script dessine

Pour chaque terrain, la zone de matière est un **rectangle à coins arrondis**
(posé sur le fond d'herbe rase du pack, la même que tous les autres jeux de
bords) : ses bords tombent où le terrain s'arrête, ses angles saillants sont
adoucis d'un rayon égal à la largeur de bande. La frontière est bousculée
d'un pixel par un bruit déterministe, et un liseré sombre côté matière la
détache de l'herbe — exactement la recette de la montagne.
"""

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

## Les terrains à synthétiser : clé du jeu de bords, et sa tuile de matière.
## Le fond est l'herbe rase de `Outdoor` (0, 0), celle de tous les autres jeux.
TERRAINS = {
    "snow": RACINE / "assets" / "textures" / "terrain" / "terrain_outdoor_snow.png",
    "swamp": RACINE / "assets" / "textures" / "terrain" / "terrain_outdoor_swamp.png",
}
FOND = ("Outdoor", 0, 0)

## Les seize voisinages, écrits dans l'ordre n, e, s, w.
MASQUES = ["fill", "n", "e", "s", "w", "ne", "es", "sw", "nw", "ns", "ew",
           "nes", "esw", "nsw", "new", "nesw"]

## Largeur de la bande de fond, en pixels — celle des bords du pack.
BANDE = 6.0
## Rayon des angles saillants. Égal à la bande : l'arc rejoint les deux bords
## sans cassure, ce qu'un rayon plus petit ne fait pas.
RAYON = 6.0
## Épaisseur du liseré sombre côté matière, et sa force.
LISERE = 2.0
LISERE_FORCE = 0.72
## Amplitude du bruit qui bouscule la frontière, en pixels.
DESORDRE = 0.9
## Distance du côté d'un rectangle qui ne s'arrête pas : assez loin pour que
## la matière couvre toute la case.
LOIN = 999.0


def _cellule(planche: str, col: int, rang: int) -> Image.Image:
    """La cellule (col, rang) de la planche du pack, en 32×32."""
    source = PACK / f"{planche}.png"
    planche_image = Image.open(source).convert("RGBA")
    return planche_image.crop((col * TAILLE, rang * TAILLE,
                               (col + 1) * TAILLE, (rang + 1) * TAILLE))


def _bruit(x: int, y: int) -> float:
    """Bruit déterministe dans [-1, 1], propre à un pixel — la même formule
    que la montagne, pour que deux machines dessinent les mêmes bords."""
    melange = (x * 73856093) ^ (y * 19349663) ^ (0x9E3779B9)
    return ((melange & 0xFFFF) / 32767.5) - 1.0


def _distance(masque: str, x: float, y: float) -> float:
    """Distance signée au bord de la matière : négative dedans, positive dehors.

    La matière occupe un rectangle à coins arrondis dont chaque côté est
    repoussé hors de la case tant que le terrain ne s'y arrête pas — d'où
    [constant LOIN]. Même formule que la montagne, pour des bords frères.
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


def _tuile(masque: str, matiere: Image.Image, fond: Image.Image) -> Image.Image:
    image = Image.new("RGBA", (TAILLE, TAILLE))
    px_mat, px_fond, px = matiere.load(), fond.load(), image.load()

    for y in range(TAILLE):
        for x in range(TAILLE):
            distance = _distance(masque, x + 0.5, y + 0.5) \
                + _bruit(x, y) * DESORDRE
            if distance > 0.0:
                px[x, y] = px_fond[x, y]
            elif distance > -LISERE:
                r, g, b, a = px_mat[x, y]
                px[x, y] = (int(r * LISERE_FORCE), int(g * LISERE_FORCE),
                            int(b * LISERE_FORCE), a)
            else:
                px[x, y] = px_mat[x, y]
    return image


def main(faire_audit: bool) -> int:
    if faire_audit:
        print("Audit : chaque jeu de bords doit avoir ses 16 tuiles.")
        for cle in TERRAINS:
            presentes = sorted(BORDS.glob(f"{cle}_*.png"))
            noms = {p.stem.removeprefix(f"{cle}_") for p in presentes}
            manquants = [m for m in MASQUES if m not in noms]
            statut = "OK" if not manquants else f"manquants : {manquants}"
            print(f"  {cle}: {len(presentes)} tuiles — {statut}")
        return 0

    fond = _cellule(*FOND).convert("RGBA")
    BORDS.mkdir(parents=True, exist_ok=True)
    for cle, tuile_path in TERRAINS.items():
        if not tuile_path.exists():
            sys.exit(f"Tuile introuvable : {tuile_path}\n"
                     "Lance d'abord : python3 art/sols-restants.py")
        matiere = Image.open(tuile_path).convert("RGBA")
        for masque in MASQUES:
            _tuile(masque, matiere, fond).save(BORDS / f"{cle}_{masque}.png")
        print(f"16 bords de {cle} écrits dans {BORDS.relative_to(RACINE)}/{cle}_*.png")
    print("Contrôle : python3 art/bords-synthese.py --audit")
    return 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--audit", action="store_true",
                         help="relit les tuiles en place, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(main(args.audit))
