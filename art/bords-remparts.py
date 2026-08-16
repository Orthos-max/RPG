#!/usr/bin/env python3
"""Les bords de la **maçonnerie** : porte, tour et mur, qui n'en avaient aucun.

    python3 art/bords-remparts.py [--audit] [--apercu]

## Pourquoi ces trois-là n'avaient pas de bords

`EDGE_SETS` habillait les terrains de **surface** — ceux qu'on traverse, dont la
limite est une ligne du paysage. La porte, la tour et le mur portent en plus un
volume ([TacticsProps]) : un rempart, un fût octogonal, deux piliers. On a
longtemps tenu que le volume disait la coupure à lui seul, et que la case
n'avait rien à ajouter.

C'est faux dès qu'on regarde le sol. Le volume ne couvre pas toute la case — le
socle d'un mur en prend les deux tiers, l'assise d'une tour un peu moins, les
piliers d'une porte quasiment rien : il reste, tout autour, une couronne de
dallage qui tranchait au cordeau sur la prairie ou sur l'eau. La bâtisse était
en volume et son emprise au sol restait un carré. Ce script dessine ce qui
manquait : la maçonnerie qui s'arrête, et ce qui commence là.

## Ce qui est engendré, et où

- `edges/{A}_{masque}.png` — les seize voisinages sur fond d'**herbe**. C'est le
  repli de [TacticsAutoTiler], celui qu'il prend quand le voisin ne sait pas
  faire fond. Sans eux, un mur bordant une prairie ne montrerait rien du tout.
- `edges-pairs/{A}_{B}_{masque}.png` — les quinze voisinages qui montrent un
  voisin, sur chacun des fonds disponibles. `wall_water_e` se lit « de la
  maçonnerie qui s'arrête à l'est, et c'est de l'eau qui commence ».

Le seizième masque, `fill`, n'a pas de paire : une case dont la maçonnerie se
poursuit des quatre côtés n'a aucun voisin à montrer, et le rendu ne pose alors
aucune bande.

## Une main plus sèche que celle des terrains de surface

La recette est celle de la neige, du marais et de la prairie
(`bords-synthese.py`, `bords-prairie.py`) : la matière occupe un **rectangle à
coins arrondis** dont chaque côté est repoussé hors de la case tant que le
terrain ne s'y arrête pas, et un liseré sombre côté matière la détache du fond.

Trois constantes changent, et toutes disent la même chose — c'est de la pierre
taillée, pas une lisière :

1. Le **désordre** tombe à un tiers. Une rive d'étang serpente ; un pied de
   rempart est posé au cordeau, et le bruit n'y sert plus qu'à casser l'aliasing
   d'une ligne parfaitement droite.
2. Le **rayon** des angles tombe de moitié. Un mur tourne à angle vif ; l'arc
   large de la neige lui ferait des coins de coussin.
3. Le **liseré** est plus épais et plus sombre : ce n'est plus une simple
   séparation, c'est l'**ombre portée** de l'assise sur le sol qui l'entoure. Une
   bâtisse pose une ombre à son pied, et c'est ce qui la fait tenir debout au
   lieu de flotter sur sa case.

## Ce que la bande montre vraiment, une fois le volume posé

Les bandes sont posées sur le **dessus** de la case, sous les props. Le socle
d'un mur (`wall_base`) couvre 64 % de la case en travers de son cours : il en
masque donc l'intérieur de la bande, et laisse voir ses six premiers pixels —
exactement la largeur de [constant BANDE], c'est-à-dire la part de la tuile
occupée par le sol du voisin. L'assise d'une tour (70 %) et les piliers d'une
porte (16 %) en laissent voir davantage encore.

Ce qui reste visible est donc précisément ce qu'on veut voir : la terre, l'eau
ou la neige du voisin qui vient buter contre la pierre, et l'ombre de la pierre
dessus. La partie cachée est le cœur du dallage — que le volume remplace
avantageusement.
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

## Les trois maçonneries, et la tuile de matière qui les peint.
##
## Mêmes clés que les entrées de `TacticsAutoTiler.EDGE_SETS` ajoutées le
## 2026-08-16 : le rendu cherche `wall_water_e` sans rien savoir d'ici.
MATIERES: dict[str, str] = {
    "gate": "terrain_outdoor_gate.png",
    "tower": "terrain_outdoor_tower.png",
    "wall": "terrain_outdoor_wall.png",
}

## Le fond du jeu de repli : l'herbe rase, celle de tous les autres `edges/`.
HERBE = "terrain_outdoor_grass.png"

## Les fonds, et la tuile de remplissage qui les peint.
##
## Mêmes clés que `TacticsAutoTiler.BACKGROUND_SETS` — les seules que le rendu
## ira chercher. Le hameau et le fortin y étaient d'avance, engendrés le jour où
## le jeu ne savait pas encore s'en servir comme fond ; ils en sont depuis le
## 2026-08-16, la ruine avec eux, et le pont le même jour — c'est lui qui
## laissait une bande d'herbe entre une rivière et le platelage qui la franchit.
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
    "ruins": "terrain_outdoor_ruins.png",
    "gate": "terrain_outdoor_gate.png",
    "tower": "terrain_outdoor_tower.png",
    "wall": "terrain_outdoor_wall.png",
    "bridge": "terrain_indoor_planks.png",
}

## Les seize voisinages, écrits dans l'ordre n, e, s, w.
MASQUES = ["fill", "n", "e", "s", "w", "ne", "es", "sw", "nw", "ns", "ew",
           "nes", "esw", "nsw", "new", "nesw"]
## Les quinze qui montrent un voisin. `fill` n'en montre aucun.
MASQUES_PAIRE = [m for m in MASQUES if m != "fill"]

## Largeur de la bande de fond, en pixels — celle des bords du pack.
BANDE = 6.0
## Rayon des angles saillants. Moitié de celui des terrains de surface : la
## pierre taillée tourne à angle vif, l'arc large lui ferait des coins mous.
RAYON = 3.0
## Épaisseur du liseré sombre côté matière, et sa force.
##
## Plus épais et plus sombre qu'ailleurs : ce n'est pas une séparation, c'est
## l'ombre que l'assise porte sur le sol qui l'entoure.
LISERE = 3.0
LISERE_FORCE = 0.62
## Amplitude du bruit qui bouscule la frontière, en pixels. Un tiers de celle
## d'une rive : de quoi casser une ligne trop parfaite, pas de quoi la faire
## serpenter.
DESORDRE = 0.3
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
    la montagne, la neige et la prairie, pour que deux machines dessinent les
    mêmes bords."""
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
    matieres = {cle: _sol(nom) for cle, nom in MATIERES.items()}
    herbe = _sol(HERBE)
    fonds = {cle: _sol(nom) for cle, nom in FONDS.items()}
    if not apercu:
        BORDS.mkdir(parents=True, exist_ok=True)
        PAIRES.mkdir(parents=True, exist_ok=True)

    planches: list[Image.Image] = []
    ecrites = 0
    for cle, matiere in matieres.items():
        if apercu:
            planches += [_tuile("ne", matiere, fonds[f]) for f in FONDS]
            continue

        # Le repli d'abord : les seize voisinages sur fond d'herbe.
        for masque in MASQUES:
            _tuile(masque, matiere, herbe).save(BORDS / f"{cle}_{masque}.png")
            ecrites += 1
        # Puis les paires, quinze par fond.
        for fond_cle, fond in fonds.items():
            for masque in MASQUES_PAIRE:
                _tuile(masque, matiere, fond).save(
                    PAIRES / f"{cle}_{fond_cle}_{masque}.png")
                ecrites += 1
        print(f"  {cle:<6} {len(MASQUES)} bords sur herbe, "
              f"{len(FONDS) * len(MASQUES_PAIRE)} paires sur {len(FONDS)} fonds")

    if apercu:
        _planche_contact(planches).save("/tmp/bords-remparts.png")
        print("\nAperçu : /tmp/bords-remparts.png")
        return 0

    print(f"\n{ecrites} tuiles de maçonnerie écrites.")
    print("Contrôle : python3 art/bords-remparts.py --audit")
    return 0


def _planche_contact(tuiles: list[Image.Image]) -> Image.Image:
    colonnes = len(FONDS)
    lignes = (len(tuiles) + colonnes - 1) // colonnes
    planche = Image.new("RGBA", (colonnes * (TAILLE + 2), lignes * (TAILLE + 2)),
                        (40, 40, 40, 255))
    for i, tuile in enumerate(tuiles):
        planche.alpha_composite(tuile, ((i % colonnes) * (TAILLE + 2),
                                        (i // colonnes) * (TAILLE + 2)))
    return planche.resize((planche.width * 6, planche.height * 6), Image.NEAREST)
#endregion


def audit() -> int:
    """Chaque maçonnerie doit avoir son repli et ses quinze tuiles par fond."""
    print("Audit : 16 bords sur herbe et 15 paires par fond, par maçonnerie.")
    manquantes = 0
    for cle in MATIERES:
        absents = [f"edges/{cle}_{m}" for m in MASQUES
                   if not (BORDS / f"{cle}_{m}.png").exists()]
        absents += [f"{cle}_{f}_{m}" for f in FONDS for m in MASQUES_PAIRE
                    if not (PAIRES / f"{cle}_{f}_{m}.png").exists()]
        manquantes += len(absents)
        attendu = len(MASQUES) + len(FONDS) * len(MASQUES_PAIRE)
        statut = "OK" if not absents else f"manquantes : {len(absents)} ({absents[:3]}…)"
        print(f"  {cle:<6} {attendu:3} attendues — {statut}")
    print(f"\n{manquantes} tuile(s) manquante(s)." if manquantes
          else "\nToute la maçonnerie est là.")
    return 1 if manquantes else 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--audit", action="store_true",
                         help="relit les tuiles en place, sans rien écrire")
    parseur.add_argument("--apercu", action="store_true",
                         help="dépose une planche de contrôle dans /tmp, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(audit() if args.audit else engendrer(args.apercu))
