#!/usr/bin/env python3
"""Fabrique les deux sprites d'un **coffre** posé sur une case.

    python3 art/dessiner-coffres.py

Les cartes portaient du décor ([TacticsDecor]) et des volumes de terrain
([TacticsProps]) : rien qu'on puisse ramasser. [BattleChests] pose maintenant
des coffres sur des cases choisies par le chapitre, et il lui faut deux images —
fermé, puis ouvert, parce qu'un coffre qui disparaît une fois vidé ne dit pas au
joueur qu'il est passé par là.

## Dessinés, pas découpés

Contrairement au buisson ou aux cailloux de `dessiner-decor.py`, le pack SSCAP
ne fournit aucun coffre : celui-ci est donc dessiné pixel par pixel, dans la
palette que ce script-là a relevée sur les tuiles du pack — le bois d'un
tonneau, le fer de ses cercles — plus l'or du jeu (`Toast.C_GOLD`, `#f5c842`),
qui est déjà la couleur de tout ce qui se gagne.

## Deux règles héritées de `dessiner-decor.py`

- **Rogné à son contenu** (`getbbox`) : [TacticsChests] pose le sprite par sa
  base, donc une rangée de pixels transparents sous le coffre le ferait léviter.
- **La lumière vient du nord-ouest**, comme celle du plateau
  ([method TacticsScenery.configure_light]) : le dessus des ferrures capte le
  jour, la face avant reste plus sourde.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - dépendance d'atelier, pas de jeu
    sys.exit("Pillow manquant : python3 -m pip install Pillow")

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "assets" / "textures" / "chests"

## Palette : le bois et le fer de `dessiner-decor.py`, l'or des bandeaux du jeu.
BOIS_DOUVE = (128, 90, 52, 255)
BOIS_SOMBRE = (92, 62, 36, 255)
BOIS_CLAIR = (160, 118, 70, 255)
FER_CERCLE = (86, 82, 78, 255)
OR_VIF = (245, 200, 66, 255)
OR_SOMBRE = (186, 142, 40, 255)
OR_PALE = (252, 232, 150, 255)
NOIR_FOND = (38, 26, 18, 255)


def _neuf(largeur: int, hauteur: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (largeur, hauteur), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def _rogner(image: Image.Image) -> Image.Image:
    """Le sprite ramené à ses pixels visibles — sa base devient son bas."""
    boite = image.getbbox()
    return image.crop(boite) if boite else image


def _caisse(dessin: ImageDraw.ImageDraw, haut: int) -> None:
    """Le corps du coffre : deux douves, deux ferrures d'angle, un pied sombre.

    `haut` est la rangée où la face avant commence — le couvercle occupe ce qui
    est au-dessus, et il n'est pas au même endroit selon que le coffre est
    ouvert.
    """
    dessin.rectangle([2, haut, 13, 15], fill=BOIS_DOUVE)
    # Les douves : deux traits verticaux suffisent à ce que la face ne se lise
    # pas comme une planche unique.
    for x in (6, 10):
        dessin.line([(x, haut + 1), (x, 14)], fill=BOIS_SOMBRE)
    # Les ferrures d'angle, et le pied qui pose la caisse au sol.
    dessin.rectangle([2, haut, 3, 15], fill=FER_CERCLE)
    dessin.rectangle([12, haut, 13, 15], fill=FER_CERCLE)
    dessin.line([(2, 15), (13, 15)], fill=NOIR_FOND)


def coffre_ferme() -> Image.Image:
    """Coffre fermé : couvercle bombé, sangle d'or, serrure au milieu."""
    image, dessin = _neuf(16, 16)
    _caisse(dessin, 9)

    # Le couvercle : un demi-cylindre posé sur la caisse. C'est le bombement qui
    # distingue un coffre d'une caisse — une caisse à couvercle plat ne s'ouvre
    # pas. Il déborde d'un pixel de chaque côté, comme un vrai couvercle.
    dessin.chord([1, 3, 14, 13], 180, 360, fill=BOIS_CLAIR)
    dessin.rectangle([1, 8, 14, 9], fill=BOIS_CLAIR)
    # Le jour vient du nord-ouest : la crête gauche capte la lumière, le bas du
    # couvercle et sa jointure avec la caisse restent dans l'ombre.
    dessin.arc([1, 3, 14, 13], 190, 265, fill=OR_PALE)
    dessin.line([(1, 9), (14, 9)], fill=NOIR_FOND)
    dessin.line([(1, 8), (1, 9)], fill=BOIS_SOMBRE)
    dessin.line([(14, 8), (14, 9)], fill=BOIS_SOMBRE)

    # La sangle d'or, du haut du couvercle au pied, et la serrure qu'elle porte.
    dessin.line([(7, 4), (7, 15)], fill=OR_SOMBRE)
    dessin.line([(8, 4), (8, 15)], fill=OR_VIF)
    dessin.rectangle([6, 9, 9, 12], fill=OR_VIF)
    dessin.rectangle([6, 9, 9, 12], outline=OR_SOMBRE)
    dessin.point([(7, 11), (8, 11)], fill=NOIR_FOND)
    return _rogner(image)


def coffre_ouvert() -> Image.Image:
    """Coffre ouvert : couvercle rabattu en arrière, fond vidé de son or.

    Il reste deux ou trois pièces au fond plutôt qu'un trou noir : à la taille
    où le joueur le voit, un coffre vide et une caisse renversée se ressemblent
    trop — et c'est justement le coffre qu'on veut reconnaître de loin, pour ne
    pas y revenir.
    """
    image, dessin = _neuf(16, 16)
    _caisse(dessin, 9)

    # Le couvercle rabattu : il pivote sur la charnière (l'arête haute de la
    # caisse) et part vers l'arrière, donc vers le haut de l'image sous cette
    # caméra. Trapèze plutôt que rectangle : c'est la fuite qui dit qu'il est
    # couché et non dressé.
    dessin.polygon([(2, 8), (13, 8), (11, 3), (4, 3)], fill=BOIS_SOMBRE)
    dessin.line([(4, 3), (11, 3)], fill=BOIS_CLAIR)
    dessin.line([(2, 8), (13, 8)], fill=FER_CERCLE)

    # L'intérieur béant, sous la charnière, et ce qu'il en reste au fond.
    dessin.rectangle([3, 9, 12, 11], fill=NOIR_FOND)
    dessin.point([(5, 10), (9, 10), (11, 11)], fill=OR_SOMBRE)
    dessin.point([(6, 11), (10, 10)], fill=OR_VIF)
    return _rogner(image)


def main() -> int:
    SORTIE.mkdir(parents=True, exist_ok=True)
    for nom, fabrique in (("chest", coffre_ferme), ("chest_open", coffre_ouvert)):
        image = fabrique()
        image.save(SORTIE / f"{nom}.png")
        print(f"  ✓ {nom}.png  ({image.width}×{image.height})")
    print(f"Coffres écrits dans {SORTIE.relative_to(RACINE)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
