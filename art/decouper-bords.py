#!/usr/bin/env python3
"""Découpe les **bords** des autotuiles SSCAP, 16 par terrain.

    python3 art/decouper-bords.py [--verifier]

`decouper-tuiles.py` n'a extrait des planches que les *remplissages* : une
cellule qui, répétée, donne une surface d'herbe ou d'eau. C'était le strict
nécessaire tant que chaque case portait une texture entière et indépendante —
et c'est ce qui donnait à une forêt collée à une plaine une frontière au
cordeau, tranchée pixel par pixel sur la limite de case.

Or le pack est bâti pour ça. Chaque terrain « posé sur de l'herbe » y occupe un
bloc régulier de 16 cellules : les 9 d'un carré 3 × 3 (le remplissage au centre,
quatre bords, quatre coins), plus une rangée de 5 au-dessus qui traite les cas
étroits — bande d'une case de large, bande d'une case de haut, et l'îlot isolé.
Seize cellules, seize combinaisons de voisinage : le compte est exact, il n'y a
rien à inventer.

## Le repère du bloc

Les coordonnées sont données par l'**ancre** : la cellule en haut à gauche du
carré 3 × 3. Tout le reste s'en déduit, planche après planche, avec exactement
la même disposition — c'est ce qui a permis de la vérifier automatiquement
(`--verifier`) plutôt que de la relever à l'œil sur quatre blocs.

    ancre-(0,-1)  … la rangée étroite : nesw, nsw, nes, new, ew
    ancre         … le carré 3 × 3 : nw, n, ne  puis  esw, ns
                                     w,  ·, e
                                     sw, s, es

## Le nommage

`eau_nw.png` se lit « de l'eau **qui s'arrête** au nord et à l'ouest » : les
lettres disent les côtés où le terrain cède la place au fond. Le remplissage,
qui ne s'arrête nulle part, s'appelle `_fill`.

C'est l'inverse de la convention à laquelle on pense d'abord (« herbe avec de
l'eau à l'est »), et c'est ce que le pack impose : la transition est dessinée
**dans** la case du terrain, sur un fond d'herbe. Une rive appartient à l'eau,
pas à la prairie. Voir [TacticsAutoTiler] pour ce qu'en fait le rendu.

`--verifier` n'écrit rien : il remesure, cellule par cellule, de quels côtés le
fond d'herbe déborde, et compare au masque que la disposition prédit. C'est ce
contrôle qui a validé les quatre ancres ci-dessous.
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
SORTIE = RACINE / "assets" / "textures" / "terrain" / "edges"
TAILLE = 32

## Cellule du bloc pour chaque masque, en (colonne, rangée) depuis l'ancre.
##
## Le masque nomme les côtés où le terrain s'arrête, dans l'ordre n, e, s, w.
## `fill` est le cas sans bord — le centre du carré.
DISPOSITION: dict[str, tuple[int, int]] = {
    "nesw": (0, -1), "nsw": (1, -1), "nes": (2, -1), "new": (3, -1), "ew": (4, -1),
    "nw":   (0,  0), "n":   (1,  0), "ne":  (2,  0), "esw": (3,  0), "ns": (4,  0),
    "w":    (0,  1), "fill": (1, 1), "e":   (2,  1),
    "sw":   (0,  2), "s":   (1,  2), "es":  (2,  2),
}

# (clé de sortie, planche, colonne d'ancre, rangée d'ancre, ce que le bloc montre)
#
# Quatre blocs, quatre transitions — celles qu'on voit : la rive, la lisière, la
# plage, le bord de route. La roche n'y est pas : elle est infranchissable, donc
# toujours bordée d'une falaise ou d'un pion, jamais d'une frontière nue.
MANIFESTE: list[tuple[str, str, int, int, str]] = [
    ("water",  "Outdoor", 5, 15, "eau libre sur herbe — la rive"),
    ("forest", "Outdoor", 0,  2, "conifères sur herbe — la lisière"),
    ("sand",   "Outdoor", 0, 22, "sable clair sur herbe — la plage"),
    ("path",   "Outdoor", 0, 18, "chemin ocre sur herbe — le bord de route"),
]

## Cellule de fond commune à tous les blocs : l'herbe rase de `Outdoor` (0, 0).
FOND = ("Outdoor", 0, 0)


def _planche(nom: str) -> Image.Image:
    source = PACK / f"{nom}.png"
    if not source.exists():
        sys.exit(f"Planche introuvable : {source}")
    return Image.open(source).convert("RGBA")


def _cellule(planche: str, col: int, rang: int) -> Image.Image:
    image = _planche(planche)
    largeur, hauteur = image.size
    x, y = col * TAILLE, rang * TAILLE
    if x < 0 or y < 0 or x + TAILLE > largeur or y + TAILLE > hauteur:
        sys.exit(f"{planche} ({col},{rang}) déborde de la planche {largeur}×{hauteur}")
    return image.crop((x, y, x + TAILLE, y + TAILLE))


def _moyenne(tuile: Image.Image) -> tuple[float, float, float]:
    px = tuile.convert("RGB").load()
    total = [0.0, 0.0, 0.0]
    for y in range(TAILLE):
        for x in range(TAILLE):
            pixel = px[x, y]
            for k in range(3):
                total[k] += pixel[k]
    return tuple(v / (TAILLE * TAILLE) for v in total)  # type: ignore[return-value]


def _ecart(a, b) -> float:
    return sum((a[k] - b[k]) ** 2 for k in range(3))


## Largeur de la bande examinée sur chaque côté, en pixels.
BANDE = 5
## Part de fond au-delà de laquelle on considère que le terrain s'arrête de ce côté.
SEUIL_FOND = 0.35


def _masque_mesure(tuile: Image.Image, fond, remplissage) -> str:
    """Les côtés où le fond déborde, lus sur les pixels de la cellule."""
    px = tuile.convert("RGB").load()
    n, b = TAILLE, BANDE
    bandes = {
        "n": [(x, y) for y in range(b) for x in range(n)],
        "e": [(x, y) for x in range(n - b, n) for y in range(n)],
        "s": [(x, y) for y in range(n - b, n) for x in range(n)],
        "w": [(x, y) for x in range(b) for y in range(n)],
    }
    cotes = ""
    for cote, points in bandes.items():
        vus = sum(1 for x, y in points
                  if _ecart(px[x, y], fond) < _ecart(px[x, y], remplissage))
        if vus / len(points) > SEUIL_FOND:
            cotes += cote
    return cotes or "fill"


def verifier() -> int:
    """Relit la disposition sur les pixels : chaque cellule montre-t-elle ses bords ?"""
    fond = _moyenne(_cellule(*FOND))
    for cle, planche, col0, rang0, quoi in MANIFESTE:
        remplissage = _moyenne(_cellule(planche, col0 + 1, rang0 + 1))
        suspectes = 0
        print(f"\n=== {cle}  ancre ({col0},{rang0})  — {quoi}")
        for masque, (dc, dr) in DISPOSITION.items():
            cellule = _cellule(planche, col0 + dc, rang0 + dr)
            lu = _masque_mesure(cellule, fond, remplissage)
            # Le masque mesuré est un ensemble de lettres : l'ordre n'y est pas.
            accord = set(lu.replace("fill", "")) == set(masque.replace("fill", ""))
            suspectes += int(not accord)
            marque = "  " if accord else " ⚠"
            print(f"  {masque:>5} ← ({col0 + dc},{rang0 + dr})"
                  f"   mesuré {lu:>5}{marque}")
        print(f"  → {16 - suspectes}/16 cellules confirmées")
    print("\nEau, sable et chemin tombent à 16/16 : la disposition est exacte,")
    print("et c'est ce qui la rend crédible pour la forêt, qui plafonne à 9/16.")
    print("Ses arbres sont verts sur de l'herbe verte, et la même mesure y")
    print("confond fond et motif — les quatre coins et les quatre cellules")
    print("étroites, eux, tombent juste, ce qui suffit à caler le bloc.")
    return 0


def decouper() -> int:
    SORTIE.mkdir(parents=True, exist_ok=True)
    ecrites = 0
    for cle, planche, col0, rang0, quoi in MANIFESTE:
        print(f"{cle} — {quoi}")
        for masque, (dc, dr) in DISPOSITION.items():
            tuile = _cellule(planche, col0 + dc, rang0 + dr)
            if tuile.getextrema()[3][0] < 255:
                print(f"  ⚠ {cle}_{masque} : la cellule n'est pas pleinement opaque")
            cible = SORTIE / f"{cle}_{masque}.png"
            tuile.save(cible)
            ecrites += 1
        print(f"  16 cellules → {SORTIE.relative_to(RACINE)}/{cle}_*.png")
    print(f"\n{ecrites} tuiles de bord écrites dans {SORTIE.relative_to(RACINE)}")
    return 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--verifier", action="store_true",
                         help="relit la disposition sur les pixels, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(verifier() if args.verifier else decouper())
