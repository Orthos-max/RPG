#!/usr/bin/env python3
"""Découpe les planches SSCAP en tuiles de terrain 32 × 32.

    python3 art/decouper-tuiles.py [--verifier]

Le pack SSCAP est un jeu d'**autotuiles** : sur ses 350 cellules, la plupart
sont des bords, des coins ou des morceaux de bâtiment qui n'ont de sens que
collés à leurs voisines. Une seule poignée sont des *remplissages* — une
cellule qui, répétée à l'infini, donne une surface d'herbe, d'eau, de roche.
Ce sont les seules qui intéressent un plateau où chaque case porte une texture
entière et indépendante : le sol des tuiles est un `BoxMesh`, pas une carte
2D continue.

D'où le principe de ce script : **pas de découpe en masse**. Un manifeste
nomme, cellule par cellule, ce qui est extrait et ce que ça représente.
Ajouter une tuile à la bibliothèque, c'est ajouter une ligne au manifeste ; la
nommer, c'est se forcer à savoir ce qu'elle contient.

`--verifier` n'écrit rien : il mesure la « raccordabilité » de chaque tuile du
manifeste (l'écart entre ses bords opposés, rapporté à son grain interne) et
imprime le tableau. En dessous de ~1,5 la répétition ne se voit pas ; au-delà,
la couture apparaît d'une case à l'autre.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - dépendance d'atelier, pas de jeu
    sys.exit("Pillow manquant : python3 -m pip install Pillow")

RACINE = Path(__file__).resolve().parent.parent
PACK = RACINE / "assets" / "packs" / "sscap-srpg-tileset"
SORTIE = RACINE / "assets" / "textures" / "terrain"
TAILLE = 32

# (planche, colonne, rangée, nom de fichier, ce que la tuile montre)
#
# Les coordonnées sont en cellules de 32 px, origine en haut à gauche de la
# planche. Elles ont été relevées à la main sur des planches-contact annotées,
# puis vérifiées en répétition 3 × 3.
MANIFESTE: list[tuple[str, int, int, str, str]] = [
    # --- Outdoor.png : 10 × 35 cellules, le gros de la planche extérieure ---
    ("Outdoor",       0,  0, "terrain_outdoor_grass",     "herbe rase, remplissage franc"),
    ("Outdoor",       0,  3, "terrain_outdoor_forest",    "canopée de conifères serrée"),
    ("Outdoor",       6, 16, "terrain_outdoor_water",     "eau libre, moutons blancs"),
    ("Outdoor",       6,  3, "terrain_outdoor_earth",     "terre battue, sol des hameaux"),
    ("Outdoor",       1, 19, "terrain_outdoor_path",      "chemin de terre tassée, ocre"),
    ("Outdoor",       6,  7, "terrain_outdoor_cobble",    "pavé de pierre grise"),
    ("Outdoor",       1, 23, "terrain_outdoor_pavement",  "dallage clair, cour de fortin"),
    ("Outdoor",       6, 23, "terrain_outdoor_sand",      "sable de désert, grain fin"),
    # --- mountains1.png / mountains v2.png : la roche ---
    ("mountains1",    5,  3, "terrain_mountain_rock",      "roche claire, veines en écailles"),
    ("mountains1",    6,  2, "terrain_mountain_rock_dark", "roche sombre, même veinage"),
    ("mountains v2",  2,  4, "terrain_mountain_void",      "aplat très sombre, fond de fosse"),
    # --- indoor.png : bois et pierre bâtie ---
    ("indoor",        5,  4, "terrain_indoor_planks",     "planches de bois, tablier de pont"),
    ("indoor",        4,  2, "terrain_indoor_moss",       "pierre envahie de mousse, ruines"),
]


def _cellule(planche: str, col: int, rang: int) -> Image.Image:
    source = PACK / f"{planche}.png"
    if not source.exists():
        sys.exit(f"Planche introuvable : {source}")
    image = Image.open(source).convert("RGBA")
    largeur, hauteur = image.size
    x, y = col * TAILLE, rang * TAILLE
    if x + TAILLE > largeur or y + TAILLE > hauteur:
        sys.exit(f"{planche} ({col},{rang}) déborde de la planche {largeur}×{hauteur}")
    return image.crop((x, y, x + TAILLE, y + TAILLE))


def _couture(tuile: Image.Image) -> tuple[float, float, float]:
    """Rend (rapport de couture, écart absolu aux bords, grain interne).

    Le rapport seul se trompe sur les tuiles très plates : l'herbe a un grain
    interne de 5 niveaux, donc le moindre écart de bord fait un rapport de 1,8
    alors qu'à l'œil la répétition est invisible. C'est pourquoi l'écart
    absolu est rendu aussi — une couture ne se voit que si les deux montent.
    """
    px = tuile.load()
    n = TAILLE

    def ecart(a, b) -> float:
        return sum(abs(a[k] - b[k]) for k in range(3)) / 3.0

    interne_h = sum(ecart(px[i, j], px[i + 1, j])
                    for j in range(n) for i in range(n - 1)) / (n * (n - 1))
    interne_v = sum(ecart(px[i, j], px[i, j + 1])
                    for j in range(n - 1) for i in range(n)) / (n * (n - 1))
    bord_h = sum(ecart(px[0, j], px[n - 1, j]) for j in range(n)) / n
    bord_v = sum(ecart(px[i, 0], px[i, n - 1]) for i in range(n)) / n
    grain = (interne_h + interne_v) / 2.0
    absolu = (bord_h + bord_v) / 2.0
    rapport = (bord_h / (interne_h + 1e-6) + bord_v / (interne_v + 1e-6)) / 2.0
    return rapport, absolu, grain


## Une couture se voit quand le rapport ET l'écart absolu montent tous les deux.
SEUIL_RAPPORT = 1.5
SEUIL_ABSOLU = 10.0


def verifier() -> int:
    print(f"{'fichier':<30} {'source':<22} {'rapport':>8} {'écart':>7} {'grain':>7}")
    suspectes = 0
    for planche, col, rang, nom, _quoi in MANIFESTE:
        rapport, absolu, grain = _couture(_cellule(planche, col, rang))
        louche = rapport > SEUIL_RAPPORT and absolu > SEUIL_ABSOLU
        suspectes += int(louche)
        alerte = "  ⚠ couture visible" if louche else ""
        print(f"{nom:<30} {planche + f' ({col},{rang})':<22} "
              f"{rapport:>8.2f} {absolu:>7.1f} {grain:>7.1f}{alerte}")
    print(f"\n{suspectes} tuile(s) au-dessus des deux seuils "
          f"(rapport > {SEUIL_RAPPORT}, écart > {SEUIL_ABSOLU})")
    return 0


def decouper() -> int:
    SORTIE.mkdir(parents=True, exist_ok=True)
    for planche, col, rang, nom, quoi in MANIFESTE:
        tuile = _cellule(planche, col, rang)
        if tuile.getextrema()[3][0] < 255:
            print(f"  ⚠ {nom} : la cellule n'est pas pleinement opaque")
        cible = SORTIE / f"{nom}.png"
        tuile.save(cible)
        print(f"  {cible.relative_to(RACINE)}  ←  {planche} ({col},{rang})  — {quoi}")
    print(f"\n{len(MANIFESTE)} tuiles écrites dans {SORTIE.relative_to(RACINE)}")
    return 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--verifier", action="store_true",
                         help="mesure la raccordabilité sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(verifier() if args.verifier else decouper())
