#!/usr/bin/env python3
"""Fabrique les **décorations au sol** et leur ombre portée.

    python3 art/dessiner-decor.py

Les cases avaient leur texture, leurs variantes, leurs bords — et rien dessus.
Une plaine restait une plaine unie sur trente cases, un sable un aplat ocre.
Ce script produit les petits sprites que [TacticsDecor] sème dessus : fleurs,
herbes hautes, cailloux, champignons, buissons, rochers, plus l'ombre douce qui
les pose sur le sol.

## Deux provenances, une seule sortie

Ce qui existe dans le pack en est **découpé** — la planche
`desert-ornaments.png` du tileset SSCAP porte un buisson, une touffe d'herbe et
un semis de cailloux déjà dessinés, dans la même main que les tuiles de
terrain. Les mettre au rebut pour les redessiner en PIL aurait fait cohabiter
deux styles sur la même case.

Ce qui n'y est pas — fleur, champignon, rocher gris, ombre — est **dessiné**
ici, pixel par pixel, dans la palette du pack (verts sourds, ocres, gris
bleutés). Une trentaine de pixels chacun : c'est la taille à laquelle ils sont
vus sous la caméra tactique, pas une contrainte de style.

## Rognage

Chaque sprite est rogné à son contenu (`getbbox`). C'est [TacticsDecor] qui le
pose *par sa base* : un sprite qui traîne huit rangées de pixels transparents
sous ses pétales flotterait de huit rangées au-dessus de sa case.

L'ombre, elle, n'est pas rognée : son dégradé va jusqu'au bord de l'image, et
c'est ce qui lui donne son bord flou.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - dépendance d'atelier, pas de jeu
    sys.exit("Pillow manquant : python3 -m pip install Pillow")

RACINE = Path(__file__).resolve().parent.parent
PACK = RACINE / "assets" / "packs" / "sscap-srpg-tileset"
SORTIE = RACINE / "assets" / "textures" / "decor"
TAILLE = 32

## (nom, planche, colonne, rangée) — ce que le pack fournit déjà.
DECOUPES: list[tuple[str, str, int, int]] = [
    ("bush", "desert-ornaments", 1, 1),      # buisson touffu — sous-bois
    ("blades", "desert-ornaments", 2, 1),    # touffe d'herbes hautes
    ("pebbles", "desert-ornaments", 2, 2),   # semis de cailloux
]

## Palette : celle du pack, relevée sur ses tuiles d'herbe et de roche.
VERT_TIGE = (74, 112, 46, 255)
VERT_SOMBRE = (52, 84, 34, 255)
ROUGE_PETALE = (196, 66, 58, 255)
BLANC_PETALE = (232, 226, 206, 255)
JAUNE_COEUR = (226, 186, 74, 255)
ROUGE_CHAPEAU = (170, 54, 46, 255)
CREME_PIED = (222, 210, 182, 255)
GRIS_ROCHE = (138, 134, 126, 255)
GRIS_CLAIR = (170, 166, 156, 255)
GRIS_SOMBRE = (94, 92, 88, 255)


def _planche(nom: str) -> Image.Image:
    source = PACK / f"{nom}.png"
    if not source.exists():
        sys.exit(f"Planche introuvable : {source}")
    return Image.open(source).convert("RGBA")


def _rogner(image: Image.Image) -> Image.Image:
    """Le sprite ramené à ses pixels visibles — sa base devient son bas."""
    boite = image.getbbox()
    return image.crop(boite) if boite else image


def _neuf(largeur: int, hauteur: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (largeur, hauteur), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def fleur() -> Image.Image:
    """Trois tiges, trois corolles : le grain d'une prairie, pas un bouquet.

    Les hampes montent d'un même pied — c'est ce qui fait lire « une touffe de
    fleurs » plutôt que trois fleurs posées côte à côte par hasard.
    """
    image, dessin = _neuf(14, 16)
    pied = (7, 15)
    hampes = [((4, 6), ROUGE_PETALE), ((7, 3), BLANC_PETALE), ((10, 7), ROUGE_PETALE)]
    for (x, y), petale in hampes:
        dessin.line([pied, (x, y)], fill=VERT_TIGE)
        # Une corolle de quatre pixels autour d'un cœur : en dessous elle
        # disparaît, au-dessus elle devient un champignon.
        dessin.point([(x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1)], fill=petale)
        dessin.point([(x, y)], fill=JAUNE_COEUR)
    # Deux feuilles au pied, sans quoi les tiges flottent sur l'herbe.
    dessin.line([(5, 14), (3, 13)], fill=VERT_SOMBRE)
    dessin.line([(9, 14), (11, 13)], fill=VERT_SOMBRE)
    return _rogner(image)


def champignon() -> Image.Image:
    """Chapeau rouge moucheté sur un pied crème — deux chapeaux, l'un plus bas."""
    image, dessin = _neuf(14, 12)
    for (cx, cy, rayon) in [(5, 5, 4), (10, 7, 3)]:
        dessin.line([(cx, cy), (cx, 11)], fill=CREME_PIED)
        dessin.chord([cx - rayon, cy - rayon, cx + rayon, cy + rayon], 180, 360,
                     fill=ROUGE_CHAPEAU)
        dessin.point([(cx - 1, cy - 2), (cx + 2, cy - 1)], fill=CREME_PIED)
    return _rogner(image)


def rocher() -> Image.Image:
    """Bloc gris facetté : trois tons, aucune courbe — la pierre est anguleuse."""
    image, dessin = _neuf(16, 13)
    dessin.polygon([(1, 12), (3, 5), (8, 2), (14, 6), (15, 12)], fill=GRIS_ROCHE)
    # La facette éclairée regarde la lumière du plateau (nord-ouest, cf.
    # TacticsScenery.configure_light) ; l'autre reste dans son ombre.
    dessin.polygon([(3, 5), (8, 2), (10, 6), (5, 8)], fill=GRIS_CLAIR)
    dessin.polygon([(10, 6), (14, 6), (15, 12), (11, 12)], fill=GRIS_SOMBRE)
    return _rogner(image)


## Palette des terrains bâtis : la paille d'un hameau, le bois d'un tonneau,
## la pierre taillée d'un fortin. Relevée sur les tuiles que `sols-batis.py`
## dérive — un décor de hameau doit avoir la couleur du sol qui le porte.
JAUNE_PAILLE = (214, 186, 112, 255)
JAUNE_CLAIR = (236, 214, 152, 255)
OCRE_OMBRE = (150, 122, 62, 255)
BOIS_DOUVE = (128, 90, 52, 255)
BOIS_SOMBRE = (92, 62, 36, 255)
FER_CERCLE = (86, 82, 78, 255)
DALLE_CLAIRE = (162, 158, 150, 255)
DALLE_SOMBRE = (108, 104, 98, 255)


def botte() -> Image.Image:
    """Botte de paille : un dôme de brins, avec la corde qui les tient.

    Un dôme plutôt qu'un cube. Vue de trois quarts sous la caméra tactique, une
    botte cubique se confond avec une caisse, et le hameau se met à ressembler
    à un entrepôt.
    """
    image, dessin = _neuf(15, 11)
    dessin.chord([0, 1, 14, 15], 180, 360, fill=JAUNE_PAILLE)
    dessin.rectangle([0, 8, 14, 10], fill=JAUNE_PAILLE)
    # Les brins : quelques traits obliques, sans quoi le dôme est un galet jaune.
    for x, y in ((3, 5), (6, 3), (9, 4), (12, 6), (4, 8), (10, 8)):
        dessin.line([(x, y), (x + 2, y + 2)], fill=JAUNE_CLAIR)
    dessin.line([(1, 10), (13, 10)], fill=OCRE_OMBRE)
    # La corde, en travers : c'est elle qui dit « botte » plutôt que « tas ».
    dessin.line([(7, 2), (7, 10)], fill=OCRE_OMBRE)
    return _rogner(image)


def tonneau() -> Image.Image:
    """Tonneau : des douves bombées, deux cercles de fer."""
    image, dessin = _neuf(11, 14)
    dessin.ellipse([0, 0, 10, 13], fill=BOIS_DOUVE)
    # Les douves, en trois traits verticaux — le bombement vient de l'ellipse.
    for x in (2, 5, 8):
        dessin.line([(x, 2), (x, 11)], fill=BOIS_SOMBRE)
    for y in (4, 9):
        dessin.line([(1, y), (9, y)], fill=FER_CERCLE)
    # Le couvercle capte la lumière du plateau (nord-ouest).
    dessin.arc([0, 0, 10, 4], 180, 360, fill=JAUNE_CLAIR)
    return _rogner(image)


def pile_dalles() -> Image.Image:
    """Pile de dalles taillées : la réserve d'un fortin qu'on répare.

    Trois assises décalées, la plus haute la plus courte : une pile d'aplomb se
    lit comme un bloc, et un fortin n'a pas de bloc qui traîne dans sa cour.
    """
    image, dessin = _neuf(15, 11)
    assises = [(0, 8, 14, 10), (1, 5, 12, 7), (3, 2, 10, 4)]
    for index, (x0, y0, x1, y1) in enumerate(assises):
        dessin.rectangle([x0, y0, x1, y1], fill=DALLE_SOMBRE)
        # Le dessus de chaque assise prend le jour ; le joint reste dans l'ombre.
        dessin.line([(x0, y0), (x1, y0)], fill=DALLE_CLAIRE)
        if index:
            dessin.point([(x0 + 2, y0 + 1), (x1 - 3, y1)], fill=GRIS_SOMBRE)
    return _rogner(image)


## Côté de la texture d'ombre, en pixels.
OMBRE_TAILLE = 32
## Opacité au centre de l'ombre (le bord tombe à zéro).
OMBRE_ALPHA = 190


def ombre() -> Image.Image:
    """Ellipse noire au bord fondu : ce qui pose un décor sur sa case.

    Le dégradé est calculé au pixel plutôt que dessiné en anneaux concentriques :
    une ombre en escalier se voit tout de suite sous la caméra tactique, qui la
    regarde de trois quarts et l'étire.

    L'alpha suit un carré du rayon (`1 - r²`) et non le rayon lui-même : le
    cœur reste franc, le bord s'évanouit — une ombre linéaire fait une flaque
    grise à bord net.
    """
    n = OMBRE_TAILLE
    image = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    pixels = image.load()
    centre = (n - 1) / 2.0
    for y in range(n):
        for x in range(n):
            dx = (x - centre) / centre
            dy = (y - centre) / centre
            reste = 1.0 - (dx * dx + dy * dy)
            if reste <= 0.0:
                continue
            pixels[x, y] = (0, 0, 0, int(OMBRE_ALPHA * reste))
    return image


## Ce qui est dessiné ici, faute d'équivalent dans le pack.
DESSINS = {
    "flower": fleur,
    "mushroom": champignon,
    "rock": rocher,
    "hay": botte,
    "barrel": tonneau,
    "stack": pile_dalles,
    "shadow": ombre,
}


def main() -> int:
    SORTIE.mkdir(parents=True, exist_ok=True)
    ecrites = 0

    for nom, planche, col, rang in DECOUPES:
        image = _planche(planche)
        cellule = image.crop((col * TAILLE, rang * TAILLE,
                              (col + 1) * TAILLE, (rang + 1) * TAILLE))
        rogne = _rogner(cellule)
        rogne.save(SORTIE / f"{nom}.png")
        print(f"  {nom:<9} découpé  {planche} ({col},{rang}) → {rogne.size[0]}×{rogne.size[1]}")
        ecrites += 1

    for nom, fabrique in DESSINS.items():
        image = fabrique()
        image.save(SORTIE / f"{nom}.png")
        print(f"  {nom:<9} dessiné              → {image.size[0]}×{image.size[1]}")
        ecrites += 1

    print(f"\n{ecrites} sprites de décor écrits dans {SORTIE.relative_to(RACINE)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
