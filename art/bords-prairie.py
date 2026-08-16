#!/usr/bin/env python3
"""Les bords de la **prairie** : de l'herbe qui s'arrête, et ce qui commence là.

    python3 art/bords-prairie.py [--audit] [--apercu]

## Pourquoi l'herbe n'avait pas de bords

Le pack SSCAP tient tout entier sur un parti : l'herbe est le fond du tableau,
et **la transition appartient au terrain, pas à l'herbe**. Une rive est dessinée
dans la case d'eau, sur un fond d'herbe ; la case d'herbe d'à côté, elle, n'a
jamais rien de spécial à montrer. C'est pour ça que `decouper-bords.py` ne
découpe aucun bloc de prairie, et que `grass` est absent d'`EDGE_SETS` depuis
l'origine.

Le joueur veut l'autre sens en plus : qu'une prairie qui borde un lac le dise
elle aussi. Ce script engendre donc ce qui n'existait pas — les quinze
voisinages de l'herbe, sur chaque fond disponible. `grass_water_e` se lit « de
l'herbe qui s'arrête à l'est, et c'est de l'eau qui commence ».

Les tuiles vont dans `edges-pairs/` et se nomment comme celles de
`bords-paires.py`, `{A}_{B}_{masque}.png` : [TacticsAutoTiler] les y cherche
sans rien savoir de leur origine. Le seizième masque, `fill`, n'est pas
engendré — une case dont l'herbe se poursuit des quatre côtés n'a pas de voisin
à montrer, et le rendu ne pose alors aucune bande.

## Comment elles sont dessinées

Faute d'un bloc à découper, la même recette que la neige et le marais
(`bords-synthese.py`) : la matière — ici l'herbe rase — occupe un **rectangle à
coins arrondis** dont chaque côté est repoussé hors de la case tant que le
terrain ne s'y arrête pas, sa frontière est bousculée d'un pixel par un bruit
déterministe, et un liseré sombre côté matière la détache du fond. Mêmes
constantes, donc mêmes bords : une lisière de prairie contre la neige et une
lisière de neige contre la prairie se ressemblent parce qu'elles ont été
dessinées de la même main.
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
SOLS = RACINE / "assets" / "textures" / "terrain"
PAIRES = SOLS / "edges-pairs"
TAILLE = 32

## La matière : l'herbe rase, celle que le décor pose sur les cases de plaine.
MATIERE = "terrain_outdoor_grass.png"

## Les fonds, et la tuile de remplissage qui les peint.
##
## Les sept premiers sont ceux de `bords-paires.py` — donc ceux de
## `TacticsAutoTiler.BACKGROUND_SETS`, les seuls que le rendu ira chercher.
## Le hameau et le fortin suivent : le jeu ne sait pas encore s'en servir comme
## fond (il faudrait les mêmes paires pour les huit autres terrains, et le test
## de complétude les exigerait), mais l'herbe, elle, les borde déjà — les tuiles
## attendent leur tour plutôt que d'être à réengendrer le jour venu.
FONDS: dict[str, str] = {
    "water": "terrain_outdoor_water.png",
    "forest": "terrain_outdoor_forest.png",
    "sand": "terrain_outdoor_sand.png",
    "path": "terrain_outdoor_path.png",
    "snow": "terrain_outdoor_snow.png",
    "swamp": "terrain_outdoor_swamp.png",
    "mountain": "terrain_mountain_rock.png",
    "village": "terrain_outdoor_hamlet.png",
    "fort": "terrain_outdoor_flagstone.png",
}

## Les quinze voisinages qui montrent un voisin. `fill` n'en montre aucun.
MASQUES = ["n", "e", "s", "w", "ne", "es", "sw", "nw", "ns", "ew",
           "nes", "esw", "nsw", "new", "nesw"]

## Largeur de la bande de fond, en pixels — celle des bords du pack.
BANDE = 6.0
## Rayon des angles saillants. Égal à la bande : l'arc rejoint les deux bords
## sans cassure, ce qu'un rayon plus petit ne fait pas.
RAYON = 6.0
## Épaisseur du liseré sombre côté matière, et sa force.
LISERE = 2.0
LISERE_FORCE = 0.78
## Amplitude du bruit qui bouscule la frontière, en pixels.
DESORDRE = 0.9
## Distance du côté d'un rectangle qui ne s'arrête pas : assez loin pour que
## la matière couvre toute la case.
LOIN = 999.0


#region Lecture
def _sol(nom: str) -> Image.Image:
    chemin = SOLS / nom
    if not chemin.exists():
        sys.exit(f"Sol introuvable : {chemin}\n"
                 "Lance d'abord : python3 art/sols-restants.py")
    return Image.open(chemin).convert("RGBA")
#endregion


#region Dessin
def _bruit(x: int, y: int) -> float:
    """Bruit déterministe dans [-1, 1], propre à un pixel — la même formule que
    la montagne et la neige, pour que deux machines dessinent les mêmes bords."""
    melange = (x * 73856093) ^ (y * 19349663) ^ (0x9E3779B9)
    return ((melange & 0xFFFF) / 32767.5) - 1.0


def _distance(masque: str, x: float, y: float) -> float:
    """Distance signée au bord de la matière : négative dedans, positive dehors.

    La matière occupe un rectangle à coins arrondis dont chaque côté est
    repoussé hors de la case tant que le terrain ne s'y arrête pas — d'où
    [constant LOIN].
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
            distance = _distance(masque, x + 0.5, y + 0.5) + _bruit(x, y) * DESORDRE
            if distance > 0.0:
                px[x, y] = px_fond[x, y]
            elif distance > -LISERE:
                r, g, b, a = px_mat[x, y]
                px[x, y] = (int(r * LISERE_FORCE), int(g * LISERE_FORCE),
                            int(b * LISERE_FORCE), a)
            else:
                px[x, y] = px_mat[x, y]
    return image
#endregion


#region Écriture
def engendrer(apercu: bool) -> int:
    matiere = _sol(MATIERE)
    fonds = {cle: _sol(nom) for cle, nom in FONDS.items()}
    if not apercu:
        PAIRES.mkdir(parents=True, exist_ok=True)

    planches: list[Image.Image] = []
    ecrites = 0
    for cle, fond in fonds.items():
        for masque in MASQUES:
            tuile = _tuile(masque, matiere, fond)
            if apercu:
                if masque == "ne":
                    planches.append(tuile)
                continue
            tuile.save(PAIRES / f"grass_{cle}_{masque}.png")
            ecrites += 1
        print(f"  grass sur {cle:<9} {len(MASQUES)} masques")

    if apercu:
        _planche_contact(planches).save("/tmp/bords-prairie.png")
        print("\nAperçu : /tmp/bords-prairie.png")
        return 0

    print(f"\n{ecrites} tuiles de prairie écrites dans {PAIRES.relative_to(RACINE)}")
    print("Contrôle : python3 art/bords-prairie.py --audit")
    return 0


def _planche_contact(tuiles: list[Image.Image]) -> Image.Image:
    colonnes = min(len(tuiles), 5)
    lignes = (len(tuiles) + colonnes - 1) // colonnes
    planche = Image.new("RGBA", (colonnes * (TAILLE + 2), lignes * (TAILLE + 2)),
                        (40, 40, 40, 255))
    for i, tuile in enumerate(tuiles):
        planche.alpha_composite(tuile, ((i % colonnes) * (TAILLE + 2),
                                        (i // colonnes) * (TAILLE + 2)))
    return planche.resize((planche.width * 6, planche.height * 6), Image.NEAREST)
#endregion


def audit() -> int:
    """Chaque fond doit avoir ses quinze tuiles ; on ne remesure rien d'autre."""
    print("Audit : la prairie doit avoir ses 15 tuiles sur chaque fond.")
    manquantes = 0
    for cle in FONDS:
        absents = [m for m in MASQUES
                   if not (PAIRES / f"grass_{cle}_{m}.png").exists()]
        manquantes += len(absents)
        statut = "OK" if not absents else f"manquants : {absents}"
        print(f"  {cle:<9} {len(MASQUES):3} attendues — {statut}")
    print(f"\n{manquantes} tuile(s) manquante(s)." if manquantes
          else "\nToute la prairie est là.")
    return 1 if manquantes else 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--audit", action="store_true",
                         help="relit les tuiles en place, sans rien écrire")
    parseur.add_argument("--apercu", action="store_true",
                         help="dépose une planche de contrôle dans /tmp, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(audit() if args.audit else engendrer(args.apercu))
