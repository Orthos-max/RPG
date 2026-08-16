#!/usr/bin/env python3
"""Dessine l'**avatar de Luna** — portrait buste, pixel art, trois expressions.

    python3 art/avatar-luna.py

## Pourquoi 96 de côté, et pourquoi le fichier fait 192

La fiche de personnage affiche l'avatar dans un `TextureRect` de 96×96, en
`STRETCH_KEEP_ASPECT_CENTERED` et en filtrage **linéaire**
(`data/modules/menu/prep_screen.gd`). Ces trois faits décident tout :

- La grille de travail fait **96 pixels de côté** — la taille d'affichage. Un
  pixel dessiné vaut un pixel à l'écran : c'est le maximum de détail que la
  fiche peut restituer. La version précédente travaillait sur 48 et doublait ;
  à surface égale on dispose ici de **quatre fois plus de pixels**, et c'est là
  qu'est passé le gain de finesse — pas dans un filtre.
- Le fichier livré fait **192×192**, soit exactement le double. Réduit de moitié
  par Godot, un bloc de 2×2 identiques redonne le pixel d'origine : la réduction
  est **exacte**, elle ne moyenne rien. En 256 le rapport serait de 2,67 et
  chaque trait du visage baverait sur ses voisins.
- Le fond est transparent (RGBA), la toile carrée : rien à recadrer.

## La charte de Luna

Cheveux roses longs et ondulés, frange asymétrique plus longue à gauche.
Grandes oreilles de renard dressées, fourrure pâle à l'intérieur, pointes noires
à dents triangulaires. Yeux ambre dorés — jamais violets. Kimono moderne noir
rehaussé d'or : c'est le combo qui la signe. Peau claire et chaude, joues
rosées, sourire confiant.

Tout est ici, en dur : mêmes tables, mêmes couleurs, même image à chaque
exécution. Rien de tiré au hasard, pas de graine à retenir.

## Comment c'est construit

Un `Toile` — un dictionnaire de pixels, pas un canevas Pillow — sert de calque
de travail. On peut y relire une couleur avant d'en poser une autre, ce dont
presque tout dépend : les mèches ne mordent que sur du cheveu, la frange ne
mord que sur du cheveu ou de la peau, les sourcils ne s'écrivent que sur la
peau. Sans cette relecture, chaque calque baverait sur le suivant.

Les silhouettes ne sont plus des tables ligne à ligne mais des **profils** :
une poignée de points de contrôle, interpolés linéairement (`profil`). À 96 de
côté, écrire quatre-vingts rangées à la main produit des bosses ; six points
bien placés produisent une courbe. L'irrégularité voulue — l'onde de la
chevelure — est rajoutée par-dessus, en connaissance de cause.

L'ordre d'empilement fait le relief, faute de profondeur : chevelure, oreilles,
ondulations, visage, tenue, mèches de devant, puis les traits, puis la frange
par-dessus tout, et enfin les reflets. La frange en dernier, pour qu'elle
retombe *sur* le front et y porte son ombre.

Le contour vient à la fin (`cerner`) : chaque pixel qui touche le vide est
repeint dans sa teinte foncée. La silhouette garde sa taille — un contour
ajouté autour l'aurait fait grossir — et chaque matière garde son propre noir :
les cheveux se cernent de prune, la tenue d'encre, la peau de brun. Le bord du
cadre ne compte pas comme du vide : la chevelure sort par le bas, elle ne s'y
arrête pas.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - dépendance d'atelier, pas de jeu
    sys.exit("Pillow manquant : python3 -m pip install Pillow")

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "assets" / "textures" / "avatars"
ATELIER = Path(__file__).resolve().parent
PLANCHE = ATELIER / "planche-avatars.png"
APERCU = ATELIER / "apercu-avatars.png"

COTE = 96  # grille de travail = taille d'affichage dans la fiche
AXE = COTE // 2  # l'axe de symétrie passe entre les colonnes 47 et 48
LIVRE = 192  # le PNG livré : le double, pour un aller-retour exact


def _c(rvb: int, alpha: int = 255) -> tuple[int, int, int, int]:
    """0xRRGGBB -> quadruplet RGBA. Écrire la charte en hexa la rend relisible."""
    return (rvb >> 16 & 0xFF, rvb >> 8 & 0xFF, rvb & 0xFF, alpha)


# --- Palette ---------------------------------------------------------------
# Cinq valeurs par matière plutôt que quatre : à 96 de côté, une zone de peau
# fait vingt pixels de large et supporte une lumière *et* deux ombres. C'est
# l'autre moitié du gain de détail, après la résolution.

ROSE_LUMIERE = _c(0xFFC4DC)
ROSE_CLAIR = _c(0xFF9EC4)
ROSE = _c(0xFF6FA5)  # charte : teinte de référence des cheveux
ROSE_OMBRE = _c(0xC24277)
ROSE_NUIT = _c(0x7A224A)
ROSE_ENCRE = _c(0x4A1430)

FOURRURE_LUMIERE = _c(0xFFF0F5)  # intérieur d'oreille
FOURRURE = _c(0xFFDCE8)
FOURRURE_OMBRE = _c(0xECAFC6)
FOURRURE_NUIT = _c(0xC886A4)
POINTE = _c(0x2A1828)  # motifs triangulaires du haut de l'oreille
POINTE_NUIT = _c(0x140A16)

PEAU_LUMIERE = _c(0xFFF4E8)
PEAU_CLAIR = _c(0xFFEAD8)
PEAU = _c(0xFFD8C4)
PEAU_OMBRE = _c(0xE0A992)
PEAU_NUIT = _c(0xB87F6E)
PEAU_CERNE = _c(0x8E5A50)
JOUE = _c(0xFFA9A4)
JOUE_CLAIR = _c(0xFFC2BA)

AMBRE_LUMIERE = _c(0xFFE09A)
AMBRE_CLAIR = _c(0xFFCB63)
AMBRE = _c(0xF5A623)  # charte : iris
AMBRE_OMBRE = _c(0xD4880F)  # charte : ombre de l'iris
AMBRE_NUIT = _c(0x8E540A)
BLANC_OEIL = _c(0xFFF4F2)
BLANC_OMBRE = _c(0xE6D2D6)
PUPILLE = _c(0x24101A)
CIL = _c(0x331824)
CIL_CLAIR = _c(0x6B3840)
ECLAT = _c(0xFFFFFF)

BOUCHE_CLAIR = _c(0xE88C92)
BOUCHE = _c(0xC85E66)
BOUCHE_OMBRE = _c(0x8E3A46)
BOUCHE_NUIT = _c(0x5A2230)

NOIR_LUMIERE = _c(0x464254)  # kimono, arête d'épaule
NOIR_CLAIR = _c(0x2E2C38)
NOIR = _c(0x1A1A22)  # la pièce principale
NOIR_NUIT = _c(0x0C0B12)
DOUBLURE = _c(0x3A2236)  # couche intérieure, dans le V du col
DOUBLURE_OMBRE = _c(0x241422)

OR_LUMIERE = _c(0xFFE98A)
OR_CLAIR = _c(0xF5C842)  # charte « Velmar » : GOLD
OR = _c(0xD4AF37)  # charte : liserés et broderies
OR_OMBRE = _c(0x8A7028)  # charte « Velmar » : GOLD_DIM
OR_NUIT = _c(0x544216)

## Ce que devient un pixel quand il touche le vide (cf. `cerner`).
CERNE = {
    ROSE_LUMIERE: ROSE_OMBRE,
    ROSE_CLAIR: ROSE_OMBRE,
    ROSE: ROSE_NUIT,
    ROSE_OMBRE: ROSE_NUIT,
    ROSE_NUIT: ROSE_ENCRE,
    FOURRURE_LUMIERE: FOURRURE_OMBRE,
    FOURRURE: FOURRURE_OMBRE,
    FOURRURE_OMBRE: FOURRURE_NUIT,
    POINTE: POINTE_NUIT,
    PEAU_LUMIERE: PEAU_OMBRE,
    PEAU_CLAIR: PEAU_OMBRE,
    PEAU: PEAU_NUIT,
    PEAU_OMBRE: PEAU_NUIT,
    PEAU_NUIT: PEAU_CERNE,
    JOUE: PEAU_NUIT,
    NOIR_LUMIERE: NOIR_NUIT,
    NOIR_CLAIR: NOIR_NUIT,
    NOIR: NOIR_NUIT,
    DOUBLURE: DOUBLURE_OMBRE,
    OR_LUMIERE: OR,
    OR_CLAIR: OR,
    OR: OR_OMBRE,
    OR_OMBRE: OR_NUIT,
}

## Les mèches ne mordent que sur ces teintes : la joue et le col sont protégés.
TEINTES_CHEVEU = {ROSE_LUMIERE, ROSE_CLAIR, ROSE, ROSE_OMBRE, ROSE_NUIT}
## La frange, elle, a le droit de recouvrir le front — mais rien d'autre.
TEINTES_PEAU = {PEAU_LUMIERE, PEAU_CLAIR, PEAU, PEAU_OMBRE, PEAU_NUIT, JOUE, JOUE_CLAIR}
TEINTES_FRANGE = TEINTES_CHEVEU | TEINTES_PEAU


class Toile:
    """Un calque de pixels relisible, à l'échelle de la grille de travail."""

    def __init__(self, cote: int = COTE) -> None:
        self.cote = cote
        self.px: dict[tuple[int, int], tuple[int, int, int, int]] = {}

    def point(self, x: int, y: int, couleur) -> None:
        if 0 <= x < self.cote and 0 <= y < self.cote:
            self.px[(x, y)] = couleur

    def lire(self, x: int, y: int):
        return self.px.get((x, y))

    def sur(self, x: int, y: int, teintes: set, couleur) -> None:
        """Ne pose la couleur que si le pixel est déjà d'une des teintes visées.

        C'est le seul garde-fou dont on ait besoin pour dessiner large : une
        mèche peut déborder sur la joue, elle ne s'y écrira pas.
        """
        if self.px.get((x, y)) in teintes:
            self.point(x, y, couleur)

    def bande(self, x0: int, x1: int, y: int, couleur) -> None:
        for x in range(x0, x1 + 1):
            self.point(x, y, couleur)

    def colonne(self, x: int, y0: int, y1: int, couleur) -> None:
        for y in range(y0, y1 + 1):
            self.point(x, y, couleur)

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, couleur, dans=None) -> None:
        """Un disque aplati, éventuellement restreint à un ensemble de cases.

        Les iris et les pupilles en dépendent : une ellipse tracée puis coupée
        par la fente de l'œil donne le regard, là où une ellipse suivant la
        paupière donnerait un haricot.
        """
        for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
            for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1):
                dx = (x + 0.5 - cx) / rx
                dy = (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0 and (dans is None or (x, y) in dans):
                    self.point(x, y, couleur)

    def image(self) -> Image.Image:
        img = Image.new("RGBA", (self.cote, self.cote), (0, 0, 0, 0))
        img.putdata(
            [
                self.px.get((x, y), (0, 0, 0, 0))
                for y in range(self.cote)
                for x in range(self.cote)
            ]
        )
        return img


def sym(x: int) -> int:
    """La colonne miroir de x."""
    return COTE - 1 - x


def profil(points: list[tuple[int, float]]) -> dict[int, float]:
    """Des points de contrôle (abscisse, valeur) vers une table continue.

    L'interpolation est linéaire : sur six à huit rangées d'écart, une droite
    est déjà une courbe une fois arrondie au pixel, et une spline ajouterait
    des dépassements qu'il faudrait ensuite rattraper à la main.
    """
    table: dict[int, float] = {}
    for (a0, v0), (a1, v1) in zip(points, points[1:]):
        for a in range(a0, a1 + 1):
            table[a] = v0 + (v1 - v0) * (a - a0) / (a1 - a0)
    return table


def gauche(demi: float) -> int:
    """Colonne de gauche d'une forme centrée, de demi-largeur donnée."""
    return AXE - int(round(demi))


def droite(demi: float) -> int:
    return AXE - 1 + int(round(demi))


# --- Profils de silhouette -------------------------------------------------
# Chaque table donne, pour une rangée, une demi-largeur (formes centrées) ou
# une colonne absolue (oreille, qui ne l'est pas). Les valeurs sont en pixels
# de la grille de 96.

## Visage : ovale, pommettes pleines, mâchoire qui fuit vers un petit menton.
## Le maximum est à la rangée 44, hauteur des yeux — c'est ce qui donne le
## visage jeune ; placé plus bas, on obtient une mâchoire d'adulte.
VISAGE = profil([
    (26, 10.0), (29, 12.6), (32, 14.2), (36, 15.3), (40, 15.9), (44, 16.1),
    (48, 16.0), (52, 15.7), (56, 15.0), (59, 14.0), (62, 12.6), (65, 10.8),
    (67, 9.0), (69, 6.8), (71, 4.0),
])

## Masse de cheveux arrière : de la calotte au bas du cadre. Elle sort par en
## bas plutôt que de s'y arrêter — des cheveux « jusqu'aux hanches » ne tiennent
## pas dans un buste, et une pointe rentrée les raccourcirait à l'épaule.
CHEVEUX = profil([
    (14, 6.0), (16, 11.0), (18, 15.0), (20, 18.0), (23, 20.5), (26, 22.0),
    (30, 23.4), (35, 24.6), (40, 25.6), (46, 26.6), (52, 28.0), (58, 30.2),
    (64, 32.8), (70, 35.4), (76, 38.0), (82, 40.6), (88, 43.0), (95, 45.0),
])

## L'onde du bord extérieur : la chevelure n'est pas un cône. Amplitude d'un
## pixel et demi, période longue ; les deux côtés sont déphasés pour que la
## silhouette ne se lise pas comme un miroir.
ONDE_AMPLEUR = 1.6
ONDE_PERIODE = 9.5
ONDE_PHASE = (0.0, 1.9)

## Oreille de renard gauche, en colonnes absolues : (bord extérieur, intérieur).
## Trente rangées de haut pour dix-sept de base, pointe d'un pixel, axe penché
## vers le dehors. Le rapport hauteur/base est ce qui décide de l'animal : à
## deux pour un on lit le renard, à un et demi pour un le chat, et sous ça
## l'ours. C'est aussi pour ça que la fourrure est insérée de trois pixels
## seulement côté extérieur — plus large, elle mangerait le bord et l'oreille
## redeviendrait une aile.
OREILLE_DEHORS = profil([
    (2, 23.0), (8, 20.6), (14, 18.2), (20, 16.2), (26, 14.8), (31, 14.0),
])
OREILLE_DEDANS = profil([
    (2, 23.0), (8, 24.6), (14, 26.0), (20, 27.2), (26, 28.2), (31, 28.6),
])
OREILLE_HAUT, OREILLE_BASE = 2, 31
POINTE_JUSQUA = 12  # au-dessus de cette rangée, l'oreille est noire d'un bloc
FOURRURE_DE, FOURRURE_A = 17, 28
FOURRURE_INSERT = (5, 3)  # retrait de la conque, côté extérieur puis intérieur

## Frange : colonne -> dernière rangée couverte. La raie est vers la colonne 52 ;
## le balayage s'allonge vers la gauche jusqu'à border la joue — quarante rangées
## d'un côté, trente de l'autre. C'est la coupe, pas une négligence de tracé.
## Aucune mèche ne descend au-delà de la colonne 33 côté gauche : au-delà elle
## traverserait l'œil, et une frange qui coupe un œil au format vignette rend le
## visage illisible avant de le rendre stylé.
FRANGE = profil([
    (25, 66), (28, 62), (31, 56), (33, 48), (35, 43), (37, 41), (40, 39),
    (43, 38), (46, 37), (49, 36), (52, 35), (55, 36), (58, 38), (61, 40),
    (63, 43), (65, 47), (68, 55), (71, 61),
])
FRANGE_HAUT = 20

## Séparations entre mèches de frange : colonne de départ, et pente. Une frange
## balayée penche : ses raies dérivent vers la gauche en descendant.
FRANGE_RAIES = (31, 37, 43, 50, 57, 62, 67)
FRANGE_PENTE = 0.18

## Cou et mâchoire.
COU = (42, 53)
COU_HAUT, COU_BAS = 64, 80

## Yeux : dix colonnes par œil, index 0 au coin extérieur. Deux tables — la
## ligne de cils et la paupière basse — suffisent à décrire la fente ; l'iris
## est une ellipse tracée par-dessus puis coupée par elle.
OEIL_DE = 34  # première colonne de l'œil gauche
OEIL_HAUT = [43, 42, 42, 42, 43, 43, 44, 44, 45, 46]
OEIL_BAS = [52, 54, 55, 55, 55, 55, 54, 53, 52, 51]
IRIS_CX, IRIS_CY = 38.5, 49.0
IRIS_RX, IRIS_RY = 4.3, 6.5

## Sourcil gauche : douze colonnes depuis la 33, arqué, extrémités qui tombent.
## Il est écrit *par-dessus* la frange, en prune sur le cheveu et en rose foncé
## sur la peau. C'est la convention du dessin animé japonais, et c'est le seul
## moyen de tenir la charte (« sourcils fins ») avec une frange qui couvre le
## front : un sourcil caché sous les mèches, c'est un visage sans expression.
SOURCIL_DE = 33
SOURCIL = [41, 40, 39, 39, 38, 38, 38, 38, 39, 39, 40, 41]

## Tenue : les épaules d'un buste. Elles ne commencent qu'à la rangée 76, sous
## le cou ; plus haut, le col mangerait la gorge. Elles s'évasent vite : une
## épaule qui n'a que dix rangées pour s'ouvrir se lit comme un cou de bouteille.
TENUE = profil([
    (76, 8.0), (78, 15.0), (80, 22.0), (82, 28.0), (85, 34.0), (88, 39.0),
    (92, 42.0), (95, 44.0),
])

## Col croisé : le V, en demi-largeurs. Il se referme sur la broche rangée 89.
COL = profil([(77, 8.0), (82, 5.4), (86, 3.0), (89, 1.0)])
COL_DE, COL_A = 77, 89

## Mèches de devant : celles qui passent par-dessus l'épaule, en demi-distances
## à l'axe. Elles naissent en pointe à hauteur de tempe, gonflent sur l'épaule,
## puis se resserrent — c'est cette double courbe qui en fait des mèches et non
## deux colonnes. Leur bord extérieur reste en deçà de la masse arrière, sinon
## elles bosselleraient la silhouette au lieu de s'y fondre ; leur bord
## intérieur est tenu loin de l'axe pour laisser voir le kimono, car deux
## mèches jointes sur la poitrine effaceraient la signature noir & or.
MECHE_DEHORS = profil([
    (48, 26.5), (56, 29.2), (64, 32.0), (72, 35.8), (80, 39.4), (88, 43.0), (95, 45.0),
])
MECHE_DEDANS = profil([
    (48, 25.2), (56, 21.5), (64, 20.0), (72, 20.8), (80, 22.4), (88, 24.6), (95, 26.5),
])
MECHE_DE, MECHE_A = 48, 95
MECHE_ONDE = 1.2  # l'arête intérieure ondule, elle aussi
MECHE_PERIODE = 12.0

## Ondulations dans la masse : (colonne, rangée haute, rangée basse, amplitude,
## période, phase, épaisseur, teinte). Le sinus donne l'onde, l'arrondi donne le
## pixel. Le côté droit reprend les mêmes mèches avec un déphasage : mêmes
## cheveux, pas la même retombée.
ONDES = [
    (16, 44, 95, 3.5, 13.0, 0.0, 2, ROSE_OMBRE),
    (24, 52, 95, 3.0, 11.0, 1.2, 2, ROSE_NUIT),
    (30, 60, 95, 2.5, 12.0, 0.4, 1, ROSE_OMBRE),
    (20, 34, 64, 2.5, 12.0, 2.1, 2, ROSE_CLAIR),
    (12, 66, 95, 2.5, 14.0, 0.8, 1, ROSE_CLAIR),
    (35, 74, 95, 2.0, 10.0, 1.6, 1, ROSE_OMBRE),
    (27, 38, 58, 2.0, 10.0, 0.9, 1, ROSE_OMBRE),
]
ONDE_DEPHASAGE = 1.7

## Expressions : (décalage de la ligne de cils, décalage de la paupière basse).
## Abaisser les cils plisse l'œil et durcit le regard ; remonter la paupière
## basse le referme par en bas et l'adoucit. L'iris n'est jamais redessiné.
EXPRESSIONS = {
    "confiante": (0, 0),
    "souriante": (0, -3),
    "serieuse": (3, 0),
}


# --- Parties ---------------------------------------------------------------


def cheveux_arriere(t: Toile) -> None:
    """La masse : calotte, puis chevelure qui s'évase jusqu'au bas du cadre.

    Le bord est ondulé, les deux côtés déphasés. Un dégradé de valeur court du
    centre vers les bords : la masse est un volume, pas une découpe.
    """
    for y, demi in CHEVEUX.items():
        for cote, phase in enumerate(ONDE_PHASE):
            onde = ONDE_AMPLEUR * math.sin(y / ONDE_PERIODE + phase)
            bord = int(round(demi + onde))
            if cote == 0:
                x0, x1 = gauche(bord), AXE - 1
            else:
                x0, x1 = AXE, droite(bord)
            t.bande(x0, x1, y, ROSE)
            # Les deux colonnes extérieures s'enfoncent dans l'ombre : c'est ce
            # qui arrondit la masse au lieu de la laisser plate.
            fuyant = gauche(bord) if cote == 0 else droite(bord)
            pas = 1 if cote == 0 else -1
            t.point(fuyant, y, ROSE_OMBRE)
            t.point(fuyant + pas, y, ROSE_OMBRE)


def oreilles(t: Toile) -> None:
    """Les deux oreilles de renard, dressées et légèrement écartées.

    Bord extérieur foncé, corps rose du cheveu, fourrure pâle en cœur, pointe
    noire sur le tiers haut terminée en dents triangulaires. Elles sont posées
    *après* la chevelure : la fourrure claire est ce qui distingue l'oreille de
    renard d'un simple épi, et la calotte, passée par-dessus, l'aurait mangée.
    """
    for miroir in (False, True):
        pose = sym if miroir else (lambda x: x)

        for y in range(OREILLE_HAUT, OREILLE_BASE + 1):
            dehors = int(round(OREILLE_DEHORS[y]))
            dedans = int(round(OREILLE_DEDANS[y]))
            for x in range(dehors, dedans + 1):
                t.point(pose(x), y, ROSE)
            t.point(pose(dehors), y, ROSE_OMBRE)  # arête extérieure
            t.point(pose(dehors + 1), y, ROSE_OMBRE)
            t.point(pose(dedans), y, ROSE_OMBRE)

            # Cœur de fourrure : inséré de trois pixels, il se resserre tout
            # seul vers le haut puisque les deux bords convergent.
            if FOURRURE_DE <= y <= FOURRURE_A and dedans - dehors >= 7:
                for x in range(dehors + 3, dedans - 1):
                    t.point(pose(x), y, FOURRURE)
                t.point(pose(dehors + 3), y, FOURRURE_OMBRE)
                t.point(pose(dedans - 2), y, FOURRURE_OMBRE)
                if (y - FOURRURE_DE) % 5 == 2:  # veinules de la conque
                    t.point(pose(dehors + 4), y, FOURRURE_OMBRE)

        # Pointe noire pleine, puis sa frange de dents : trois rangées de
        # profondeur variable, période cinq. Un bord droit aurait donné un
        # bonnet ; ce sont les dents qui font le motif de la charte.
        for y in range(OREILLE_HAUT, POINTE_JUSQUA + 1):
            for x in range(int(round(OREILLE_DEHORS[y])), int(round(OREILLE_DEDANS[y])) + 1):
                t.point(pose(x), y, POINTE)
        x0 = int(round(OREILLE_DEHORS[POINTE_JUSQUA + 1]))
        x1 = int(round(OREILLE_DEDANS[POINTE_JUSQUA + 1]))
        for x in range(x0, x1 + 1):
            dent = 4 - 2 * abs(((x - x0) % 5) - 2)  # 0, 2, 4, 2, 0
            for y in range(POINTE_JUSQUA + 1, POINTE_JUSQUA + 1 + dent):
                t.point(pose(x), y, POINTE)

        # Second motif : deux petits triangles sur l'arête extérieure, sous la
        # pointe. Ils répètent le motif du bout et fixent le pelage — sans eux
        # le noir se lit comme un chapeau posé, pas comme une marque.
        for y in range(17, 23):
            dehors = int(round(OREILLE_DEHORS[y]))
            for x in range(dehors + 1, dehors + 1 + (23 - y)):
                t.point(pose(x), y, POINTE)

        # La fourrure s'éteint en bas d'oreille au lieu de buter net sur le
        # cheveu : sans ça, deux pastilles blanches au sommet du crâne.
        for y in range(FOURRURE_A + 1, OREILLE_BASE + 1):
            dehors = int(round(OREILLE_DEHORS[y]))
            dedans = int(round(OREILLE_DEDANS[y]))
            for x in range(dehors + 3, dedans - 1):
                t.point(pose(x), y, FOURRURE_OMBRE if y == FOURRURE_A + 1 else ROSE_OMBRE)


def meches(t: Toile) -> None:
    """Les ondulations de la masse, en mèches sombres et claires qui serpentent.

    La garde sur `TEINTES_CHEVEU` autorise à dessiner large sans se soucier des
    bords : ce qui déborde sur la joue, le col ou le vide n'est pas posé.

    Une mèche ne se pose pas non plus sur la colonne du bord : `cerner` va déjà
    y foncer le pixel, et une mèche sombre qui s'y ajoute creuse une encoche.
    Une onde qui affleure la silhouette la grignote au lieu de la parcourir —
    d'où le second garde-fou, sur les voisins à deux pixels.
    """

    def dans_la_masse(x: int, y: int) -> bool:
        return t.lire(x, y) in TEINTES_CHEVEU and all(
            (x + d, y) in t.px for d in (-2, -1, 1, 2)
        )

    for miroir in (False, True):
        pose = sym if miroir else (lambda x: x)
        decalage = ONDE_DEPHASAGE if miroir else 0.0
        for depart, haut, bas, ampleur, periode, phase, epaisseur, teinte in ONDES:
            for y in range(haut, bas + 1):
                x = depart + int(round(ampleur * math.sin(y / periode + phase + decalage)))
                for e in range(epaisseur):
                    if dans_la_masse(pose(x + e), y):
                        t.point(pose(x + e), y, teinte)


def visage(t: Toile) -> None:
    """Le cou, l'ovale, et les ombres qui les décollent de la chevelure.

    Le cou est posé d'abord et le visage par-dessus : le menton doit mordre sur
    la gorge, pas s'y raccorder bord à bord. L'ombre portée de la mâchoire est
    ensuite repassée sous le menton, en deux valeurs — c'est elle qui met la
    tête devant le corps.
    """
    for y in range(COU_HAUT, COU_BAS + 1):
        t.bande(COU[0], COU[1], y, PEAU)
        t.point(COU[0], y, PEAU_NUIT)
        t.point(COU[1], y, PEAU_NUIT)

    for y, demi in VISAGE.items():
        g, d = gauche(demi), droite(demi)
        t.bande(g, d, y, PEAU)
        t.point(g, y, PEAU_OMBRE)  # les tempes reçoivent moins de lumière
        t.point(d, y, PEAU_OMBRE)
        t.point(g + 1, y, PEAU_OMBRE)
        t.point(d - 1, y, PEAU_OMBRE)

    # Front et pommettes, là où la lumière frappe. Ces zones restent étroites :
    # une lumière qui couvre tout le visage ne l'éclaire pas, elle le délave.
    for y in range(34, 40):
        t.bande(40, 55, y, PEAU_CLAIR)
    for y in range(50, 56):
        demi = VISAGE[y] - 6
        t.bande(gauche(demi), droite(demi), y, PEAU_CLAIR)
    for y in range(52, 57):
        t.bande(45, 50, y, PEAU_LUMIERE)  # arête du nez

    # Ombre portée de la mâchoire sur la gorge : deux valeurs qui s'éclaircissent
    # en descendant. Sans dégradé, le cou se lit comme un tube collé.
    for y in range(70, 72):
        t.bande(COU[0], COU[1], y, PEAU_NUIT)
    for y in range(72, 75):
        t.bande(COU[0], COU[1], y, PEAU_OMBRE)
    for y in range(70, COU_BAS + 1):
        t.point(COU[0], y, PEAU_CERNE)
        t.point(COU[1], y, PEAU_CERNE)


def joues(t: Toile) -> None:
    """Les joues rosées, en deux valeurs et un tramage qui les fait fondre.

    Un aplat franc de rose sur une joue fait une pastille de clown ; le tramage
    en damier sur les rangées d'attaque et de sortie suffit, à cette taille, à
    donner l'impression d'un dégradé.
    """
    for miroir in (False, True):
        pose = sym if miroir else (lambda x: x)
        for y in range(57, 62):
            for x in range(34, 42):
                if y in (57, 61) and (x + y) % 2:
                    continue
                teinte = JOUE_CLAIR if y in (57, 61) else JOUE
                t.sur(pose(x), y, TEINTES_PEAU, teinte)


def oeil(t: Toile, miroir: bool, expression: str) -> None:
    """Un œil : la fente, le blanc, l'iris ambre, la pupille, deux éclats.

    L'iris est une ellipse pleine coupée par la fente — coupée en haut *et* en
    bas. C'est la coupe qui fait le regard : un iris entier flottant dans le
    blanc donne un œil de poupée, un iris qui disparaît sous les deux paupières
    donne un regard.

    Les deux éclats ne sont pas mis en miroir. La lumière vient d'en haut à
    gauche pour tout le portrait ; symétriser les reflets ferait loucher la
    lumière avant de faire loucher Luna.
    """
    dh, db = EXPRESSIONS[expression]
    pose = sym if miroir else (lambda x: x)

    fente: set[tuple[int, int]] = set()
    for i in range(len(OEIL_HAUT)):
        x = pose(OEIL_DE + i)
        haut, bas = OEIL_HAUT[i] + dh, OEIL_BAS[i] + db
        for y in range(haut + 2, bas):
            fente.add((x, y))
            t.point(x, y, BLANC_OEIL)
        t.point(x, haut + 2, BLANC_OMBRE)  # la paupière porte son ombre

    # Iris, puis ses trois valeurs : ombre du haut, base, lumière ramassée en
    # bas. Un iris uni reste plat même à quatre-vingt-seize pixels.
    cx = (COTE - 1 - IRIS_CX) if miroir else IRIS_CX
    t.ellipse(cx, IRIS_CY, IRIS_RX, IRIS_RY, AMBRE, dans=fente)
    t.ellipse(cx, IRIS_CY + 2.2, IRIS_RX - 0.6, IRIS_RY - 2.4, AMBRE_CLAIR, dans=fente)
    t.ellipse(cx, IRIS_CY + 4.0, IRIS_RX - 2.0, IRIS_RY - 4.4, AMBRE_LUMIERE, dans=fente)
    for x, y in list(fente):  # liseré foncé sur le pourtour de l'iris
        if t.lire(x, y) in (AMBRE, AMBRE_CLAIR, AMBRE_LUMIERE):
            voisins = ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
            if any(t.lire(vx, vy) in (BLANC_OEIL, BLANC_OMBRE, None) for vx, vy in voisins):
                t.point(x, y, AMBRE_OMBRE)
    t.ellipse(cx, IRIS_CY - 3.4, IRIS_RX - 1.0, 2.0, AMBRE_NUIT, dans=fente)
    t.ellipse(cx, IRIS_CY, 1.7, 3.0, PUPILLE, dans=fente)

    # Éclats : le gros en haut à gauche de l'iris, le petit en bas à droite.
    for dx, dy, largeur, hauteur in ((-3, -3.5, 2, 2), (2, 3.5, 2, 1)):
        for ex in range(largeur):
            for ey in range(hauteur):
                x = int(cx + dx) + ex
                y = int(IRIS_CY + dy) + ey
                if (x, y) in fente:
                    t.point(x, y, ECLAT)

    # Ligne de cils : deux rangées, trois au coin extérieur, plus la virgule
    # qui déborde de la fente. C'est le trait le plus lourd du visage ; en
    # dessous d'un noir franc, l'œil se délave dès la réduction en vignette.
    for i in range(len(OEIL_HAUT)):
        x = pose(OEIL_DE + i)
        haut, bas = OEIL_HAUT[i] + dh, OEIL_BAS[i] + db
        t.point(x, haut, CIL)
        t.point(x, haut + 1, CIL)
        if i <= 2:
            t.point(x, haut + 2, CIL)
        t.point(x, bas, CIL_CLAIR)  # paupière basse : brun, jamais noir
        t.point(x, bas + 1, PEAU_OMBRE)
    t.point(pose(OEIL_DE - 1), OEIL_HAUT[0] + dh, CIL)  # la virgule du coin
    t.point(pose(OEIL_DE - 2), OEIL_HAUT[0] + dh - 1, CIL)


def sourcils(t: Toile, expression: str) -> None:
    """Les sourcils, fins, posés après la frange et seulement sur la peau.

    Ils s'écrivent aussi bien sur la peau que sur le cheveu, mais pas dans la
    même teinte : rose foncé sur le front, prune sur les mèches. Un sourcil de
    même valeur des deux côtés se couperait en deux au passage de la frange ;
    en s'accordant à ce qu'il traverse, il reste un seul trait continu.
    """
    for miroir in (False, True):
        pose = sym if miroir else (lambda x: x)
        for i, y in enumerate(SOURCIL):
            x = pose(SOURCIL_DE + i)
            if expression == "serieuse":
                y += int(round(i * 0.35)) - 1  # l'intérieur tombe : le regard durcit
            elif expression == "souriante":
                y -= 1
            t.sur(x, y, TEINTES_PEAU, ROSE_OMBRE)
            t.sur(x, y, TEINTES_CHEVEU, ROSE_NUIT)
            # Le trait ne s'épaissit que sur la peau. Doublé sur le cheveu, il
            # cessait d'être un sourcil vu à travers la frange pour devenir une
            # balafre posée dessus.
            if 3 <= i <= 9:
                t.sur(x, y + 1, TEINTES_PEAU, ROSE_NUIT)


def nez(t: Toile) -> None:
    """Le nez : une ombre et une narine, pas un trait.

    De face et à cette taille, tout nez dessiné en ligne se lit comme une
    balafre. Deux valeurs sur le côté gauche de l'arête suffisent à le poser.
    """
    for x, y in ((46, 57), (47, 57), (46, 58), (47, 58), (48, 58)):
        t.sur(x, y, TEINTES_PEAU, PEAU_OMBRE)
    t.sur(45, 58, TEINTES_PEAU, PEAU_NUIT)
    t.sur(50, 58, TEINTES_PEAU, PEAU_NUIT)


def bouche(t: Toile, expression: str) -> None:
    """La bouche — le second porteur d'expression après la ligne de cils.

    Le sourire par défaut est décroché : la ligne des lèvres monte de trois
    pixels de gauche à droite, et le sourire devient un sourire *en coin*.
    Symétrique, il n'aurait dit que « contente ». La canine qui dépasse dans
    l'ouverture est la note taquine de la charte : deux pixels blancs, pas plus.
    """
    if expression == "souriante":
        for x in range(43, 53):
            y = 62 + int(round(1.6 * math.sin(math.pi * (x - 43) / 9)))
            t.point(x, y, BOUCHE_OMBRE)
            if 45 <= x <= 50:
                t.point(x, y + 1, BLANC_OEIL)  # les dents
                t.point(x, y + 2, BOUCHE_NUIT)
                t.point(x, y + 3, BOUCHE)
            if 46 <= x <= 49:
                t.point(x, y + 4, BOUCHE_CLAIR)
        return

    if expression == "serieuse":
        t.bande(44, 51, 64, BOUCHE_OMBRE)
        t.point(43, 65, BOUCHE_NUIT)  # les coins retombent
        t.point(52, 65, BOUCHE_NUIT)
        t.bande(45, 50, 65, BOUCHE)
        t.bande(46, 49, 66, BOUCHE_CLAIR)
        return

    for x in range(43, 53):  # confiante : le sourire en coin de la charte
        y = 64 - int(round((x - 43) * 0.34))
        t.point(x, y, BOUCHE_OMBRE)
        if 45 <= x <= 50:
            t.point(x, y + 1, BOUCHE_NUIT)
            t.point(x, y + 2, BOUCHE)
        if 46 <= x <= 49:
            t.point(x, y + 3, BOUCHE_CLAIR)
    t.point(46, 64, BLANC_OEIL)  # la canine, dans l'ouverture — deux pixels
    t.point(46, 65, BLANC_OEIL)


def meches_devant(t: Toile) -> None:
    """Les deux mèches qui retombent devant les épaules, sur la tenue.

    Leur arête intérieure porte l'ombre, et elle en projette une sur le kimono :
    un pixel d'encre le long du bord. C'est ce pixel qui décolle la mèche du
    noir ; sans lui, cheveux et tissu fusionnent en une seule tache sombre.
    """
    for miroir in (False, True):
        pose = sym if miroir else (lambda x: x)
        onde = MECHE_ONDE if miroir else -MECHE_ONDE
        for y in range(MECHE_DE, MECHE_A + 1):
            dehors = gauche(MECHE_DEHORS[y])
            dedans = gauche(MECHE_DEDANS[y] + onde * math.sin(y / MECHE_PERIODE))
            if dedans < dehors:
                continue
            for x in range(dehors, dedans + 1):
                t.point(pose(x), y, ROSE)
            t.point(pose(dedans), y, ROSE_OMBRE)
            t.point(pose(dedans - 1), y, ROSE_OMBRE)
            t.point(pose(dehors), y, ROSE_OMBRE)
            # L'ombre portée ne se pose que sur le tissu. Sur le cheveu, elle
            # traçait un trait sombre en travers de la masse — une couture là
            # où il ne devait rien y avoir.
            if t.lire(pose(dedans + 1), y) in (NOIR, NOIR_CLAIR, NOIR_LUMIERE):
                t.point(pose(dedans + 1), y, NOIR_NUIT)
            if (y - MECHE_DE) % 11 < 4:  # reflet filant le long de la mèche
                t.point(pose(dedans - 4), y, ROSE_CLAIR)


def frange(t: Toile) -> None:
    """La frange asymétrique, posée en dernier : elle retombe sur le front.

    Elle ne s'écrit que sur du cheveu ou de la peau (`TEINTES_FRANGE`). Cette
    seule restriction lui laisse balayer tout le haut du portrait sans qu'on
    ait à découper son contour : elle ne mangera ni la fourrure des oreilles,
    ni les pointes noires, ni les yeux.

    Suivent les raies entre mèches, puis l'ombre portée sur le front : deux
    rangées sous chaque pointe. Cette ombre est le détail qui met la frange
    *devant* le visage plutôt que peinte dessus.
    """
    for x, bas in FRANGE.items():
        bas = int(round(bas))
        for y in range(FRANGE_HAUT, bas + 1):
            t.sur(x, y, TEINTES_FRANGE, ROSE)
        t.sur(x, bas, TEINTES_CHEVEU, ROSE_OMBRE)  # la pointe de la mèche s'assombrit
        t.sur(x, bas - 1, TEINTES_CHEVEU, ROSE_OMBRE)

    for depart in FRANGE_RAIES:
        for y in range(FRANGE_HAUT + 2, COTE):
            x = depart - int(round((y - FRANGE_HAUT) * FRANGE_PENTE))
            if x not in FRANGE or y > FRANGE[x]:
                break
            t.sur(x, y, TEINTES_CHEVEU, ROSE_OMBRE)

    for x, bas in FRANGE.items():  # ombre portée sur le front
        bas = int(round(bas))
        t.sur(x, bas + 1, TEINTES_PEAU, PEAU_OMBRE)
        t.sur(x, bas + 2, TEINTES_PEAU, PEAU_OMBRE)
        if (x + bas) % 2 == 0:
            t.sur(x, bas + 3, TEINTES_PEAU, PEAU_OMBRE)


def reflet(t: Toile) -> None:
    """L'arc de lumière sur la calotte — la signature du cheveu en pixel art.

    Il suit la courbe du crâne (un sinus sur la largeur), ondule légèrement
    (un second sinus, plus court) et se coupe en tirets. Continu, il ferait un
    bandeau ; ce sont les coupures qui le font lire comme un reflet.
    """
    for x in range(24, 72):
        if (x // 7) % 2 == 1 and x % 7 >= 5:  # les coupures
            continue
        courbe = 4.0 * math.sin(math.pi * (x - 24) / 48)
        onde = 1.4 * math.sin((x - 24) / 4.5)
        y = int(round(30 - courbe + onde))
        t.sur(x, y, TEINTES_CHEVEU, ROSE_LUMIERE)
        t.sur(x, y + 1, TEINTES_CHEVEU, ROSE_CLAIR)
        t.sur(x, y - 1, TEINTES_CHEVEU, ROSE_CLAIR)


def tenue(t: Toile) -> None:
    """Le kimono : noir de la pièce principale, or du col, des broderies, de la
    broche.

    L'or ne couvre rien — il souligne. Un liseré d'un pixel sur le croisé du
    col, une broderie en pointillé qui le double à quatre pixels, une broche à
    la pointe du V, un motif de chevrons sur le devant : quatre accents qui
    portent la signature noir & or sans que le noir cesse d'être la pièce.
    """
    for y, demi in TENUE.items():
        g, d = gauche(demi), droite(demi)
        t.bande(g, d, y, NOIR)
        t.point(g, y, NOIR_NUIT)
        t.point(d, y, NOIR_NUIT)
        t.point(g + 1, y, NOIR_CLAIR)  # arête d'épaule, prise dans la lumière
        t.point(d - 1, y, NOIR_CLAIR)
        if y <= 84:
            t.point(g + 2, y, NOIR_LUMIERE)
            t.point(d - 2, y, NOIR_LUMIERE)

    # Le V du col : gorge sous la clavicule, doublure ensuite, liseré d'or au
    # bord. Le liseré s'éclaircit vers le haut : l'or reçoit la même lumière que
    # le reste, sinon il se lit comme un autocollant.
    for y in range(COL_DE, COL_A + 1):
        g, d = gauche(COL[y]), droite(COL[y])
        if d - g >= 7:
            t.bande(g + 1, g + 3, y, DOUBLURE)
            t.bande(d - 3, d - 1, y, DOUBLURE)
            t.bande(g + 4, d - 4, y, PEAU if y <= 84 else DOUBLURE)
        else:
            t.bande(g + 1, d - 1, y, DOUBLURE)
        teinte = OR_LUMIERE if y <= 82 else OR
        t.point(g, y, teinte)
        t.point(d, y, teinte)
        if (y - COL_DE) % 3 != 2 and d - g >= 11:  # broderie qui double le col
            t.point(g + 5, y, OR_OMBRE)
            t.point(d - 5, y, OR_OMBRE)

    # Ombre de la mâchoire et du menton sur le haut du col.
    for y in range(78, 81):
        for x in range(COU[0], COU[1] + 1):
            if t.lire(x, y) == PEAU:
                t.point(x, y, PEAU_OMBRE)

    # Broche : le V se referme dessus. Un losange de cinq pixels, cœur clair.
    for dx, dy in ((0, -2), (-1, -1), (0, -1), (1, -1), (-2, 0), (-1, 0), (0, 0),
                   (1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)):
        t.point(AXE + dx, COL_A + 1 + dy, OR)
    for dx, dy in ((0, -1), (-1, 0), (0, 0)):
        t.point(AXE + dx, COL_A + 1 + dy, OR_LUMIERE)
    t.point(AXE, COL_A + 3, OR_OMBRE)

    # Broderie d'épaule : un pointillé d'or qui suit l'arête, à quatre pixels
    # du bord. Il court le long de la couture plutôt que de se poser en motif
    # isolé — c'est ce qui le fait lire comme une finition de vêtement.
    for y, demi in TENUE.items():
        if y < 82 or (y - 82) % 3 == 2:
            continue
        for x in (gauche(demi) + 4, droite(demi) - 4):
            if t.lire(x, y) in (NOIR, NOIR_CLAIR, NOIR_LUMIERE):
                t.point(x, y, OR_OMBRE if (y - 82) % 6 < 3 else OR)

    # Chevrons brodés sur le devant, de part et d'autre de la broche.
    for miroir in (False, True):
        pose = sym if miroir else (lambda x: x)
        for base in (86, 92):
            for k in range(5):
                x, y = 33 + k, base + abs(k - 2)
                if t.lire(pose(x), y) in (NOIR, NOIR_CLAIR, NOIR_LUMIERE):
                    t.point(pose(x), y, OR if k == 2 else OR_OMBRE)


def bijoux(t: Toile) -> None:
    """Les boucles d'oreilles dorées : un anneau et sa goutte, contre le cheveu.

    Posées au bord de la mâchoire, là où la chevelure passe derrière le visage.
    L'or sur le rose y tient un contraste suffisant pour survivre à la vignette,
    ce qui ne serait pas le cas sur le noir du kimono.
    """
    for miroir in (False, True):
        pose = sym if miroir else (lambda x: x)
        for x, y, teinte in (
            (30, 58, OR_LUMIERE), (31, 58, OR), (29, 59, OR), (32, 59, OR),
            (29, 60, OR_OMBRE), (32, 60, OR_OMBRE), (30, 61, OR), (31, 61, OR_OMBRE),
            (30, 63, OR_LUMIERE), (31, 63, OR), (30, 64, OR), (31, 64, OR_OMBRE),
            (30, 65, OR_OMBRE), (31, 65, OR_NUIT),
        ):
            t.point(pose(x), y, teinte)


def cerner(t: Toile) -> None:
    """Repeint dans sa teinte foncée tout pixel qui touche le vide.

    Un contour *interne* : la silhouette ne gagne pas un pixel, et chaque
    matière se cerne de son propre foncé plutôt que d'un noir commun qui aurait
    aplati le rose sur le noir de la tenue.

    Le bord du cadre n'est pas du vide. C'est ce qui permet à la chevelure de
    sortir par le bas sans qu'un liseré sombre vienne l'y trancher net.
    """
    bord = {}
    for (x, y), couleur in t.px.items():
        if couleur not in CERNE:
            continue
        voisins = ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
        dehors = any(
            0 <= vx < t.cote and 0 <= vy < t.cote and (vx, vy) not in t.px
            for vx, vy in voisins
        )
        if dehors:
            bord[(x, y)] = CERNE[couleur]
    t.px.update(bord)


def dessiner(expression: str) -> Image.Image:
    """Empile les parties dans l'ordre qui fait le relief."""
    t = Toile()
    cheveux_arriere(t)
    oreilles(t)
    meches(t)
    visage(t)
    tenue(t)
    meches_devant(t)
    joues(t)
    for miroir in (False, True):
        oeil(t, miroir, expression)
    nez(t)
    bouche(t, expression)
    frange(t)
    sourcils(t, expression)
    reflet(t)
    bijoux(t)
    cerner(t)
    return t.image()


# --- Sortie ----------------------------------------------------------------


def planche_contact(avatars: dict[str, Image.Image]) -> None:
    """Une planche d'atelier : les trois expressions côte à côte, agrandies."""
    zoom, marge = 4, 6
    largeur = len(avatars) * (COTE * zoom + marge) + marge
    planche = Image.new("RGBA", (largeur, COTE * zoom + 2 * marge), (24, 20, 34, 255))
    for rang, img in enumerate(avatars.values()):
        gros = img.resize((COTE * zoom, COTE * zoom), Image.NEAREST)
        planche.alpha_composite(gros, (marge + rang * (COTE * zoom + marge), marge))
    planche.save(PLANCHE)


def apercu(avatars: dict[str, Image.Image]) -> None:
    """L'épreuve de lisibilité : chaque expression aux trois tailles réelles.

    De gauche à droite : le fichier livré (192), ce que la fiche en affiche
    (96), la vignette de menu (48). C'est la colonne du milieu qui décide — si
    le visage n'y tient pas, le reste ne sert à rien.
    """
    marge = 8
    largeur = marge * 4 + LIVRE + COTE + 48
    hauteur = marge * (len(avatars) + 1) + LIVRE * len(avatars)
    feuille = Image.new("RGBA", (largeur, hauteur), (24, 20, 34, 255))
    for rang, img in enumerate(avatars.values()):
        haut = marge + rang * (LIVRE + marge)
        feuille.alpha_composite(img.resize((LIVRE, LIVRE), Image.NEAREST), (marge, haut))
        feuille.alpha_composite(img, (marge * 2 + LIVRE, haut))
        feuille.alpha_composite(reduire(img, 48), (marge * 3 + LIVRE + COTE, haut))
    feuille.save(APERCU)


def reduire(img: Image.Image, cote: int) -> Image.Image:
    """Réduit en moyennant les blocs — jamais au plus proche voisin.

    À la réduction, `NEAREST` jette un pixel sur deux : la ligne de cils, qui
    fait deux pixels d'épaisseur, peut y perdre la moitié de sa densité selon
    la parité. `BOX` moyenne, donc conserve la masse de chaque trait. C'est
    aussi ce que fait la fiche, qui affiche en filtrage linéaire.
    """
    return img.resize((cote, cote), Image.BOX)


def verifier(natif: Image.Image, livre: Image.Image) -> int:
    """Contrôle que le PNG livré redonne exactement le dessin une fois réduit.

    C'est le seul argument en faveur du 192 plutôt que du 256 : un agrandissement
    au plus proche voisin par deux, puis une réduction par deux en moyennant,
    est l'identité. Retourne l'écart maximal constaté, qui doit être nul.
    """
    retour = reduire(livre, COTE)
    return max(abs(a - b) for a, b in zip(natif.tobytes(), retour.tobytes()))


def main() -> None:
    SORTIE.mkdir(parents=True, exist_ok=True)
    # `confiante` est la tenue par défaut de la charte : c'est elle qui prend le
    # nom nu, `luna.png`, que le reste du projet ira chercher.
    noms = {"confiante": "luna", "souriante": "luna-souriante", "serieuse": "luna-serieuse"}

    avatars: dict[str, Image.Image] = {}
    ecart = 0
    for expression, nom in noms.items():
        natif = dessiner(expression)
        avatars[expression] = natif
        livre = natif.resize((LIVRE, LIVRE), Image.NEAREST)
        livre.save(SORTIE / f"{nom}.png")
        reduire(natif, 48).save(SORTIE / f"{nom}-48.png")
        ecart = max(ecart, verifier(natif, livre))
        print(f"  {nom}.png ({LIVRE}×{LIVRE}) + {nom}-48.png (48×48)")

    planche_contact(avatars)
    apercu(avatars)
    print(f"Avatars écrits dans {SORTIE.relative_to(RACINE)}")
    print(f"Planche de contact : {PLANCHE.relative_to(RACINE)}")
    print(f"Épreuve de lisibilité : {APERCU.relative_to(RACINE)}")
    print(f"Réduction {LIVRE} → {COTE} : écart maximal {ecart} (0 = aller-retour exact)")


if __name__ == "__main__":
    main()
