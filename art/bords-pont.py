#!/usr/bin/env python3
"""Les bords du **pont** : un platelage qui s'arrête, et ce qui coule dessous.

    python3 art/bords-pont.py [--audit] [--apercu]

## Pourquoi le pont n'avait aucun bord

`EDGE_SETS` a reçu tour à tour les terrains de surface (l'eau, le bois, la
plage), la montagne, la prairie, la maçonnerie (`bords-remparts.py`), puis la
ruine (`bords-ruines.py`). Le pont est resté dehors du premier jour au dernier,
et il est pourtant le terrain dont la limite est la plus **matérielle** de tous :
un platelage de bois posé au-dessus de l'eau, dont le bord n'est pas une
frontière de paysage mais une planche sciée.

Le décor ne suffit pas à le dire. [TacticsProps] y pose un platelage plat
(`_bridge_deck`) et deux garde-corps le long de la travée, mais tout cela tient
au centre de la case : il reste, tout autour, une couronne de planches dont la
limite était l'arête du damier.

Le défaut se voyait surtout **contre l'eau**, et pour une raison qui n'a rien à
voir avec `EDGE_SETS` : le pont n'était pas non plus un fond
(`BACKGROUND_SETS`). Une case d'eau collée à un pont prenait donc `water_n`, sa
rive **sur fond d'herbe** — six pixels de prairie verte entre la rivière et le
platelage qui la franchit. C'est exactement le défaut que `bords-paires.py` a été
écrit pour corriger, resté ouvert sur le seul terrain qui traverse une rivière.

## Ce qui est engendré, et où

- `edges/bridge_{masque}.png` — les seize voisinages sur fond d'**herbe**. C'est
  le repli de [TacticsAutoTiler], celui qu'il prend quand le voisin ne sait pas
  faire fond.
- `edges-pairs/bridge_{B}_{masque}.png` — les quinze voisinages qui montrent un
  voisin, sur chacun des fonds disponibles. `bridge_water_e` se lit « du
  platelage qui s'arrête à l'est, et c'est de l'eau qui commence ».

Le seizième masque, `fill`, n'a pas de paire : une case dont le platelage se
poursuit des quatre côtés n'a aucun voisin à montrer, et le rendu ne pose alors
aucune bande.

Les tuiles **réciproques** — `water_bridge_e`, `path_bridge_n` — ne sont pas
engendrées ici : elles appartiennent au terrain qui borde, et sortent donc des
scripts qui l'habillent (`bords-paires.py`, `bords-prairie.py`,
`bords-remparts.py`, `bords-ruines.py`), à qui le fond `bridge` a été ajouté le
même jour.

## Une main de scie, pas de pinceau

La recette est celle de la neige, du marais, de la prairie, de la maçonnerie et
de la ruine : la matière occupe un **rectangle à coins arrondis** dont chaque
côté est repoussé hors de la case tant que le terrain ne s'y arrête pas, sa
frontière est bousculée par un bruit déterministe, et un liseré sombre côté
matière la détache du fond.

Trois constantes tiennent le pont à l'écart de tous les autres, et toutes disent
la même chose — c'est du bois **scié**, et il est **au-dessus** de son voisin :

1. Le **désordre** est le plus faible de tous les jeux de bords, un quart de
   celui d'une rive et moins encore que celui d'un rempart. Une berge serpente,
   un pied de mur est posé au cordeau ; une planche est *sciée*, et le bruit n'y
   sert plus qu'à casser l'aliasing d'une ligne parfaitement droite.
2. Le **rayon** des angles est le plus petit de tous. Un platelage tourne à
   angle vif : l'arc du rempart lui ferait déjà des coins mous.
3. Le **liseré** est le plus sombre de tous. Ailleurs c'est une séparation, ou
   l'ombre qu'une assise porte sur le sol qui l'entoure ; ici c'est l'ombre que
   le tablier porte **sous lui**, et c'est la seule chose qui dise que le pont
   ne flotte pas sur l'eau mais passe par-dessus.
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

## La matière : le platelage de bois, celui que les cases de pont portent déjà.
##
## Même clé que l'entrée `TacticsAutoTiler.EDGE_SETS` ajoutée le 2026-08-16 : le
## rendu cherche `bridge_water_e` sans rien savoir d'ici.
CLE = "bridge"
MATIERE = "terrain_indoor_planks.png"

## Le fond du jeu de repli : l'herbe rase, celle de tous les autres `edges/`.
HERBE = "terrain_outdoor_grass.png"

## Les fonds, et la tuile de remplissage qui les peint.
##
## Ce sont ceux de `TacticsAutoTiler.BACKGROUND_SETS`, le pont excepté — un
## terrain ne se borde pas lui-même. Même liste que `bords-remparts.py`,
## `bords-prairie.py` et `bords-ruines.py`.
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
}

## Les seize voisinages, écrits dans l'ordre n, e, s, w.
MASQUES = ["fill", "n", "e", "s", "w", "ne", "es", "sw", "nw", "ns", "ew",
           "nes", "esw", "nsw", "new", "nesw"]
## Les quinze qui montrent un voisin. `fill` n'en montre aucun.
MASQUES_PAIRE = [m for m in MASQUES if m != "fill"]

## Largeur de la bande de fond, en pixels — celle des bords du pack.
BANDE = 6.0
## Rayon des angles saillants. Le plus petit de tous les jeux de bords : un
## platelage scié tourne à angle vif, et l'arc du rempart lui ferait déjà des
## coins mous.
RAYON = 2.0
## Épaisseur du liseré sombre côté matière, et sa force.
##
## Le plus sombre de tous. Ailleurs le liseré sépare, ou porte l'ombre d'une
## assise sur le sol qui l'entoure ; ici il porte l'ombre du tablier **sous**
## lui, et c'est la seule chose qui dise que le pont passe au-dessus de l'eau au
## lieu d'y flotter.
LISERE = 3.0
LISERE_FORCE = 0.55
## Amplitude du bruit qui bouscule la frontière, en pixels. Le plus faible de
## tous : une planche est sciée, pas érodée — de quoi casser une ligne trop
## parfaite, pas de quoi la faire serpenter.
DESORDRE = 0.25
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
    la montagne, la neige, la prairie, la maçonnerie et la ruine, pour que deux
    machines dessinent les mêmes bords."""
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
        _planche_contact(planches).save("/tmp/bords-pont.png")
        print("Aperçu : /tmp/bords-pont.png")
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

    print(f"\n{ecrites} tuiles de pont écrites.")
    print("Les réciproques (water_bridge_e…) sortent des autres scripts :")
    print("  python3 art/bords-paires.py && python3 art/bords-prairie.py")
    print("  python3 art/bords-remparts.py && python3 art/bords-ruines.py")
    print("Contrôle : python3 art/bords-pont.py --audit")
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
    """Le pont doit avoir son repli et ses quinze tuiles par fond."""
    print("Audit : 16 bords sur herbe et 15 paires par fond, pour le pont.")
    absents = [f"edges/{CLE}_{m}" for m in MASQUES
               if not (BORDS / f"{CLE}_{m}.png").exists()]
    absents += [f"{CLE}_{f}_{m}" for f in FONDS for m in MASQUES_PAIRE
                if not (PAIRES / f"{CLE}_{f}_{m}.png").exists()]
    attendu = len(MASQUES) + len(FONDS) * len(MASQUES_PAIRE)
    statut = "OK" if not absents else f"manquantes : {len(absents)} ({absents[:3]}…)"
    print(f"  {CLE:<6} {attendu:3} attendues — {statut}")

    # Les réciproques : le pont est aussi un **fond**, et c'est là que se jouait
    # la bande d'herbe entre une rivière et le platelage qui la franchit.
    reciproques = [f"{a}_{CLE}_{m}" for a in _BORDEURS for m in MASQUES_PAIRE
                   if not (PAIRES / f"{a}_{CLE}_{m}.png").exists()]
    print(f"  fond   {len(_BORDEURS) * len(MASQUES_PAIRE):3} réciproques — "
          + ("OK" if not reciproques
             else f"manquantes : {len(reciproques)} ({reciproques[:3]}…)"))

    total = len(absents) + len(reciproques)
    print(f"\n{total} tuile(s) manquante(s)." if total else "\nTout le pont est là.")
    return 1 if total else 0


## Les terrains qui bordent — `TacticsAutoTiler.EDGE_SETS`, le pont excepté.
##
## Ils ne sont pas dessinés ici : l'audit les relit seulement, parce qu'une
## réciproque manquante rendrait au pont la bande d'herbe qu'il vient de perdre.
_BORDEURS = ["grass", "water", "forest", "sand", "path", "mountain", "village",
             "fort", "snow", "swamp", "gate", "tower", "wall", "ruins"]


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--audit", action="store_true",
                         help="relit les tuiles en place, sans rien écrire")
    parseur.add_argument("--apercu", action="store_true",
                         help="dépose une planche de contrôle dans /tmp, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(audit() if args.audit else engendrer(args.apercu))
