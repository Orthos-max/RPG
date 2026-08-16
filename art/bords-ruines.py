#!/usr/bin/env python3
"""Les bords des **ruines** : du dallage crevé qui s'arrête, et ce qui commence là.

    python3 art/bords-ruines.py [--audit] [--apercu]

## Pourquoi la ruine n'avait aucun bord

`EDGE_SETS` a reçu tour à tour les terrains de surface (l'eau, le bois, la
plage), puis la montagne, puis la prairie, puis la maçonnerie
(`bords-remparts.py`). La ruine est restée dehors tout ce temps, alors qu'elle
est le terrain le plus présent du chapitre 2 — la brèche du poste avancé. Son
sol tranchait donc au cordeau sur l'herbe : un carré de dallage posé sur la
prairie, avec l'arête du damier pour seule frontière.

Le décor ne suffit pas à la dire. [TacticsProps] y dresse une colonnade ou un
pan de mur et sème des gravats, mais tout cela tient au centre de la case : il
reste, tout autour, une couronne de dalles dont la limite était un trait droit.
C'est elle que ce script habille.

## Ce qui est engendré, et où

- `edges/ruins_{masque}.png` — les seize voisinages sur fond d'**herbe**. C'est
  le repli de [TacticsAutoTiler], celui qu'il prend quand le voisin ne sait pas
  faire fond.
- `edges-pairs/ruins_{B}_{masque}.png` — les quinze voisinages qui montrent un
  voisin, sur chacun des fonds disponibles. `ruins_water_e` se lit « du dallage
  qui s'arrête à l'est, et c'est de l'eau qui commence ».

Le seizième masque, `fill`, n'a pas de paire : une case dont la ruine se
poursuit des quatre côtés n'a aucun voisin à montrer, et le rendu ne pose alors
aucune bande.

## Une main entre la pierre taillée et la lisière

La recette est celle de la neige, du marais, de la prairie et de la maçonnerie
(`bords-synthese.py`, `bords-prairie.py`, `bords-remparts.py`) : la matière
occupe un **rectangle à coins arrondis** dont chaque côté est repoussé hors de
la case tant que le terrain ne s'y arrête pas, sa frontière est bousculée par un
bruit déterministe, et un liseré sombre côté matière la détache du fond.

Trois constantes tiennent le milieu entre le rempart et la rive, et toutes
disent la même chose — c'est de la pierre **qui a cédé**, pas de la pierre
posée :

1. Le **désordre** vaut deux tiers de celui d'une rive, plus du double de celui
   d'un rempart. Un mur debout est au cordeau, une berge serpente ; un dallage
   crevé s'effrite, ce qui n'est ni l'un ni l'autre.
2. Le **rayon** des angles reste petit — c'est encore de la pierre taillée, et
   ses coins ne sont pas des coussins — mais un peu plus large que celui du
   rempart, parce qu'un angle qui s'est écroulé s'arrondit.
3. Le **liseré** est celui de la maçonnerie : l'ombre que l'assise porte sur le
   sol qui l'entoure, plus épaisse et plus sombre qu'une simple séparation.
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
BORDS = SOLS / "edges"
PAIRES = SOLS / "edges-pairs"
TAILLE = 32

## La matière : le dallage crevé, celui que les cases de ruine portent déjà.
##
## Même clé que l'entrée `TacticsAutoTiler.EDGE_SETS` ajoutée le 2026-08-16 : le
## rendu cherche `ruins_water_e` sans rien savoir d'ici.
CLE = "ruins"
MATIERE = "terrain_outdoor_ruins.png"

## Le fond du jeu de repli : l'herbe rase, celle de tous les autres `edges/`.
HERBE = "terrain_outdoor_grass.png"

## Les fonds, et la tuile de remplissage qui les peint.
##
## Ce sont ceux de `TacticsAutoTiler.BACKGROUND_SETS`, la ruine exceptée — un
## terrain ne se borde pas lui-même. Même liste que `bords-remparts.py` et
## `bords-prairie.py`, à qui la ruine a été ajoutée le même jour.
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
    "gate": "terrain_outdoor_gate.png",
    "tower": "terrain_outdoor_tower.png",
    "wall": "terrain_outdoor_wall.png",
}

## Les seize voisinages, écrits dans l'ordre n, e, s, w.
MASQUES = ["fill", "n", "e", "s", "w", "ne", "es", "sw", "nw", "ns", "ew",
           "nes", "esw", "nsw", "new", "nesw"]
## Les quinze qui montrent un voisin. `fill` n'en montre aucun.
MASQUES_PAIRE = [m for m in MASQUES if m != "fill"]

## Largeur de la bande de fond, en pixels — celle des bords du pack.
BANDE = 6.0
## Rayon des angles saillants. Entre le rempart (3) et la lisière (6) : un angle
## de dallage qui s'est écroulé s'arrondit, mais reste de la pierre taillée.
RAYON = 4.0
## Épaisseur du liseré sombre côté matière, et sa force. Celles de la maçonnerie :
## ce n'est pas une séparation, c'est l'ombre de l'assise sur le sol.
LISERE = 3.0
LISERE_FORCE = 0.62
## Amplitude du bruit qui bouscule la frontière, en pixels. Deux tiers de celle
## d'une rive : un dallage crevé s'effrite sans serpenter.
DESORDRE = 0.6
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
    la montagne, la neige, la prairie et la maçonnerie, pour que deux machines
    dessinent les mêmes bords."""
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
    herbe = _sol(HERBE)
    fonds = {cle: _sol(nom) for cle, nom in FONDS.items()}

    if apercu:
        planches = [_tuile("ne", matiere, fonds[f]) for f in FONDS]
        _planche_contact(planches).save("/tmp/bords-ruines.png")
        print("Aperçu : /tmp/bords-ruines.png")
        return 0

    BORDS.mkdir(parents=True, exist_ok=True)
    PAIRES.mkdir(parents=True, exist_ok=True)

    ecrites = 0
    # Le repli d'abord : les seize voisinages sur fond d'herbe.
    for masque in MASQUES:
        _tuile(masque, matiere, herbe).save(BORDS / f"{CLE}_{masque}.png")
        ecrites += 1
    # Puis les paires, quinze par fond.
    for fond_cle, fond in fonds.items():
        for masque in MASQUES_PAIRE:
            _tuile(masque, matiere, fond).save(
                PAIRES / f"{CLE}_{fond_cle}_{masque}.png")
            ecrites += 1
    print(f"  {CLE:<6} {len(MASQUES)} bords sur herbe, "
          f"{len(FONDS) * len(MASQUES_PAIRE)} paires sur {len(FONDS)} fonds")

    print(f"\n{ecrites} tuiles de ruine écrites.")
    print("Contrôle : python3 art/bords-ruines.py --audit")
    return 0


def _planche_contact(tuiles: list[Image.Image]) -> Image.Image:
    colonnes = min(len(tuiles), 6)
    lignes = (len(tuiles) + colonnes - 1) // colonnes
    planche = Image.new("RGBA", (colonnes * (TAILLE + 2), lignes * (TAILLE + 2)),
                        (40, 40, 40, 255))
    for i, tuile in enumerate(tuiles):
        planche.alpha_composite(tuile, ((i % colonnes) * (TAILLE + 2),
                                        (i // colonnes) * (TAILLE + 2)))
    return planche.resize((planche.width * 6, planche.height * 6), Image.NEAREST)
#endregion


def audit() -> int:
    """La ruine doit avoir son repli et ses quinze tuiles par fond."""
    print("Audit : 16 bords sur herbe et 15 paires par fond, pour la ruine.")
    absents = [f"edges/{CLE}_{m}" for m in MASQUES
               if not (BORDS / f"{CLE}_{m}.png").exists()]
    absents += [f"{CLE}_{f}_{m}" for f in FONDS for m in MASQUES_PAIRE
                if not (PAIRES / f"{CLE}_{f}_{m}.png").exists()]
    attendu = len(MASQUES) + len(FONDS) * len(MASQUES_PAIRE)
    statut = "OK" if not absents else f"manquantes : {len(absents)} ({absents[:3]}…)"
    print(f"  {CLE:<6} {attendu:3} attendues — {statut}")
    print(f"\n{len(absents)} tuile(s) manquante(s)." if absents
          else "\nToute la ruine est là.")
    return 1 if absents else 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--audit", action="store_true",
                         help="relit les tuiles en place, sans rien écrire")
    parseur.add_argument("--apercu", action="store_true",
                         help="dépose une planche de contrôle dans /tmp, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(audit() if args.audit else engendrer(args.apercu))
