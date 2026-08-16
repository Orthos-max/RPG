#!/usr/bin/env python3
"""Les bords **par paire de terrains** : une rive d'eau sur du sable, pas sur de l'herbe.

    python3 art/bords-paires.py [--audit] [--apercu]

## Le défaut que ce script corrige

`decouper-bords.py`, `bords-montagne.py` et `bords-synthese.py` produisent tous
leurs seize cellules sur **le même fond** : l'herbe rase du pack, `Outdoor`
(0, 0). C'est le parti du tileset SSCAP, et il tient tant que l'herbe est
partout — c'est bien le fond du tableau.

Il tombe dès que deux terrains habillés se touchent. Une case d'eau collée à
une case de sable affiche sa rive sur fond d'herbe : on lit **eau | herbe |
sable**, une bande verte de six pixels là où il n'y a ni prairie ni raison
d'en voir une. Le masque disait pourtant juste — il sait de quel côté l'eau
s'arrête —, c'est la tuile qui ne connaissait qu'un seul voisin possible.

Ce script engendre le jeu manquant : pour chaque terrain **A** qui a des bords
et chaque fond **B** qui n'est pas l'herbe, les quinze cellules de A dessinées
sur B. `edges-pairs/water_sand_n.png` se lit « de l'eau qui s'arrête au nord,
et c'est du sable qui commence ».

Le seizième masque, `fill`, n'est pas engendré : une case dont le terrain se
poursuit des quatre côtés n'a pas de voisin à montrer. [TacticsAutoTiler]
continue d'y prendre la tuile ordinaire, comme il retombe sur elle pour toute
paire absente d'ici.

## Deux façons de changer un fond, une par façon dont la tuile a été faite

- **`reference`** — montagne, neige, marais. Ces bords-là, nous les avons
  synthétisés nous-mêmes sur la cellule d'herbe de référence : leurs pixels de
  fond lui sont donc **rigoureusement égaux**. On les reconnaît par simple
  comparaison, et on les remplace. Le liseré sombre côté matière, lui, n'est
  égal à rien et survit intact — ce qui n'aurait pas été le cas d'une règle
  fondée sur les couleurs, puisqu'il est né d'un assombrissement de la matière.
- **`palette`** — eau, forêt, sable, chemin, hameau, fortin. Ces bords viennent
  du pack, dessinés à la main : leur herbe n'est pas la cellule de référence.
  On les lit à la **palette** — un pixel qui n'est d'aucune couleur du
  remplissage de A n'appartient pas à A —, on nettoie le résultat d'une
  ouverture morphologique (sans quoi un pixel d'herbe aperçu entre deux sapins
  passerait pour du fond), et on ne garde que ce qui **communique avec un bord
  masqué**. Un creux d'herbe isolé au milieu d'un bois reste donc de l'herbe :
  c'est le sol de la forêt, pas la prairie d'à côté.

Dans les deux cas la silhouette dessinée par la tuile d'origine est gardée
telle quelle : on ne repeint que ce qui était le fond.
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

RACINE = Path(__file__).resolve().parent.parent
PACK = RACINE / "assets" / "packs" / "sscap-srpg-tileset"
SOLS = RACINE / "assets" / "textures" / "terrain"
BORDS = SOLS / "edges"
PAIRES = SOLS / "edges-pairs"
TAILLE = 32

## Cellule d'herbe sur laquelle tous les jeux de bords ont été composés.
FOND = ("Outdoor", 0, 0)

## Les quinze voisinages qui montrent un voisin. `fill` n'en montre aucun.
MASQUES = ["n", "e", "s", "w", "ne", "es", "sw", "nw", "ns", "ew",
           "nes", "esw", "nsw", "new", "nesw"]

## Les terrains habillés, et la façon de reconnaître leur fond.
##
## Mêmes clés que `TacticsAutoTiler.EDGE_SETS` — un terrain ajouté là est à
## ajouter ici, sans quoi il gardera son fond d'herbe quel que soit son voisin.
AVANTS: dict[str, str] = {
    "water": "palette",
    "forest": "palette",
    "sand": "palette",
    "path": "palette",
    "village": "palette",
    "fort": "palette",
    "mountain": "reference",
    "snow": "reference",
    "swamp": "reference",
}

## Les fonds disponibles, et la tuile de remplissage qui les peint.
##
## Mêmes clés que `TacticsAutoTiler.BACKGROUND_SETS` — un fond ajouté là est à
## ajouter ici, sans quoi le rendu ira chercher une paire qui n'existe pas.
##
## L'herbe n'y est pas, et c'est délibéré : elle est le fond des tuiles
## d'origine, donc le cas que le repli couvre déjà. En engendrer la paire
## reviendrait à recopier `edges/` en huit exemplaires.
##
## Le hameau, le fortin et la ruine y sont depuis le 2026-08-16. Les trois
## étaient dans `AVANTS` — ils bordaient les autres — sans être des fonds : un
## bois collé à un hameau montrait donc sa lisière sur de l'herbe, six pixels de
## prairie entre deux terrains qui n'en ont ni l'un ni l'autre. Le défaut était
## exactement celui que ce script a été écrit pour corriger, resté ouvert sur
## trois terrains.
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

## Voisins en croix d'un pixel — l'ouverture et l'inondation s'y tiennent.
VOISINS = ((1, 0), (-1, 0), (0, 1), (0, -1))


#region Lecture
def _cellule_pack(planche: str, col: int, rang: int) -> Image.Image:
    source = PACK / f"{planche}.png"
    if not source.exists():
        sys.exit(f"Planche introuvable : {source}")
    image = Image.open(source).convert("RGB")
    return image.crop((col * TAILLE, rang * TAILLE,
                       (col + 1) * TAILLE, (rang + 1) * TAILLE))


def _bord(terrain: str, masque: str) -> Image.Image:
    chemin = BORDS / f"{terrain}_{masque}.png"
    if not chemin.exists():
        sys.exit(f"Tuile de bord introuvable : {chemin}\n"
                 "Lance d'abord : python3 art/decouper-bords.py, "
                 "bords-montagne.py et bords-synthese.py")
    return Image.open(chemin).convert("RGBA")


def _sol(nom: str) -> Image.Image:
    chemin = SOLS / nom
    if not chemin.exists():
        sys.exit(f"Sol introuvable : {chemin}\n"
                 "Lance d'abord : python3 art/sols-restants.py")
    return Image.open(chemin).convert("RGB")
#endregion


#region Reconnaître le fond
def _semences(masque: str) -> list[tuple[int, int]]:
    """Les pixels de bordure des côtés où le terrain s'arrête."""
    points: list[tuple[int, int]] = []
    if "n" in masque:
        points += [(x, 0) for x in range(TAILLE)]
    if "s" in masque:
        points += [(x, TAILLE - 1) for x in range(TAILLE)]
    if "w" in masque:
        points += [(0, y) for y in range(TAILLE)]
    if "e" in masque:
        points += [(TAILLE - 1, y) for y in range(TAILLE)]
    return points


def _inonde(candidats: set, masque: str) -> set:
    """Ce qui, parmi les candidats, communique avec un bord masqué.

    C'est ce qui distingue le fond d'à côté d'un trou intérieur : une clairière
    au milieu d'un bois n'est pas la prairie voisine, et repeindre l'une en
    sable parce que l'autre l'est saupoudrerait la forêt.
    """
    file = deque(p for p in _semences(masque) if p in candidats)
    vus = set(file)
    while file:
        x, y = file.popleft()
        for dx, dy in VOISINS:
            voisin = (x + dx, y + dy)
            if voisin in candidats and voisin not in vus:
                vus.add(voisin)
                file.append(voisin)
    return vus


def _ouvre(candidats: set) -> set:
    """Ouverture morphologique : érosion puis dilatation, en croix.

    Elle efface les pixels isolés et les chapelets d'un pixel de large — le
    grain d'herbe aperçu entre deux sapins — sans entamer une bande de six
    pixels. Le bord de l'image compte comme candidat : une bande qui touche le
    cadre ne doit pas maigrir par le seul fait d'y toucher.
    """
    dedans = lambda p: 0 <= p[0] < TAILLE and 0 <= p[1] < TAILLE
    erode = {p for p in candidats
             if all(not dedans((p[0] + dx, p[1] + dy))
                    or (p[0] + dx, p[1] + dy) in candidats for dx, dy in VOISINS)}
    return {p for p in candidats
            if p in erode or any((p[0] + dx, p[1] + dy) in erode for dx, dy in VOISINS)}


def _fond_reference(tuile: Image.Image, reference: Image.Image) -> set:
    """Les pixels rigoureusement égaux à la cellule d'herbe de référence."""
    px, ref = tuile.convert("RGB").load(), reference.load()
    return {(x, y) for y in range(TAILLE) for x in range(TAILLE)
            if px[x, y] == ref[x, y]}


def _fond_palette(tuile: Image.Image, remplissage: Image.Image, masque: str) -> set:
    """Les pixels d'aucune couleur du remplissage, nettoyés puis inondés."""
    px, plein = tuile.convert("RGB").load(), remplissage.convert("RGB").load()
    couleurs = {plein[x, y] for y in range(TAILLE) for x in range(TAILLE)}
    candidats = {(x, y) for y in range(TAILLE) for x in range(TAILLE)
                 if px[x, y] not in couleurs}
    return _inonde(_ouvre(candidats), masque)


def _fond(terrain: str, masque: str, tuile: Image.Image,
          remplissage: Image.Image, reference: Image.Image) -> set:
    if AVANTS[terrain] == "reference":
        return _fond_reference(tuile, reference)
    return _fond_palette(tuile, remplissage, masque)
#endregion


#region Écriture
def _repeint(tuile: Image.Image, fond: set, sol: Image.Image) -> Image.Image:
    image = tuile.copy()
    px, motif = image.load(), sol.load()
    for x, y in fond:
        px[x, y] = motif[x, y] + (255,)
    return image


def engendrer(apercu: bool) -> int:
    reference = _cellule_pack(*FOND)
    sols = {cle: _sol(nom) for cle, nom in FONDS.items()}
    if not apercu:
        PAIRES.mkdir(parents=True, exist_ok=True)

    planches: list[Image.Image] = []
    ecrites = 0
    for terrain in AVANTS:
        remplissage = _bord(terrain, "fill")
        arriere = [cle for cle in FONDS if cle != terrain]
        for masque in MASQUES:
            tuile = _bord(terrain, masque)
            fond = _fond(terrain, masque, tuile, remplissage, reference)
            for cle in arriere:
                paire = _repeint(tuile, fond, sols[cle])
                if apercu and masque == "ne":
                    planches.append(paire)
                elif not apercu:
                    paire.save(PAIRES / f"{terrain}_{cle}_{masque}.png")
                    ecrites += 1
        couverture = len(_fond(terrain, "n", _bord(terrain, "n"),
                               remplissage, reference))
        print(f"{terrain:<9} {AVANTS[terrain]:<9} "
              f"fond du masque « n » : {couverture:3} px sur {TAILLE * TAILLE}")

    if apercu:
        _planche_contact(planches).save("/tmp/bords-paires.png")
        print("\nAperçu : /tmp/bords-paires.png")
        return 0

    print(f"\n{ecrites} tuiles de paire écrites dans {PAIRES.relative_to(RACINE)}")
    print("Contrôle : python3 art/bords-paires.py --audit")
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
    """Chaque paire doit avoir ses quinze tuiles ; on ne remesure rien d'autre."""
    print("Audit : chaque paire (terrain, fond) doit avoir ses 15 tuiles.")
    manquantes = 0
    for terrain in AVANTS:
        attendu = [cle for cle in FONDS if cle != terrain]
        absents = [f"{cle}:{m}" for cle in attendu for m in MASQUES
                   if not (PAIRES / f"{terrain}_{cle}_{m}.png").exists()]
        manquantes += len(absents)
        statut = "OK" if not absents else f"manquantes : {len(absents)} ({absents[:3]}…)"
        print(f"  {terrain:<9} {len(attendu) * len(MASQUES):3} attendues — {statut}")
    print(f"\n{manquantes} tuile(s) manquante(s)." if manquantes
          else "\nToutes les paires sont là.")
    return 1 if manquantes else 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--audit", action="store_true",
                         help="relit les tuiles en place, sans rien écrire")
    parseur.add_argument("--apercu", action="store_true",
                         help="dépose une planche de contrôle dans /tmp, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(audit() if args.audit else engendrer(args.apercu))
