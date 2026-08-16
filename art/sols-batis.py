#!/usr/bin/env python3
"""Les sols **bâtis** : la cour d'un fortin, la terre battue d'un hameau.

    python3 art/sols-batis.py [--apercu]

Fortin et hameau étaient les deux parents pauvres du plateau. Le premier
empruntait `terrain_outdoor_pavement` — qui, malgré son nom, est le
remplissage de sable clair du pack ; le second `terrain_outdoor_earth`, une
plaque de terre unie. Ni l'un ni l'autre n'avait de bord : un fortin posé au
milieu d'une prairie s'y découpait au carré, comme au massicot.

Ce script leur donne les deux choses qui manquaient.

## Un motif, pas un aplat

Les deux sols sont **dérivés** de la cellule de remplissage du pack, jamais
peints à côté : ils héritent donc de son grain et de sa gamme, et se raccordent
d'eux-mêmes aux terrains voisins.

- **Le fortin** reçoit un appareillage de dalles à joints croisés. La pierre du
  pack est un blocage de moellons — juste pour une ruine, trop désordonné pour
  une cour qu'on a pavée exprès. Chaque dalle est donc aplanie vers sa propre
  moyenne, bordée d'un joint sombre et d'un chanfrein clair : le moellon reste
  visible *dans* la dalle, mais c'est la dalle qu'on lit.
- **Le hameau** reçoit ce qu'on piétine devant une porte : de la paille, des
  plaques tassées plus claires, quelques pierres enfoncées dans la boue.

Tout est tracé **modulo la tuile** : un brin de paille qui sort à droite rentre
à gauche. C'est la condition pour que la case se répète sans couture, la tuile
étant projetée en coordonnées monde à raison d'une par case.

## Des bords que le pack dessine déjà

Le pack range chaque terrain « posé sur de l'herbe » en bloc de seize cellules
(voir `decouper-bords.py`). Deux de ces blocs n'avaient jamais été découpés :
le blocage de pierre (ancre 5, 6) et la terre battue (ancre 5, 2). Ils sont
exactement les transitions qui manquaient au fortin et au hameau.

Plutôt que de synthétiser une frontière — ce qu'il a fallu faire pour la
montagne, faute de bloc —, on **rhabille** celui du pack : l'herbe de la
cellule est gardée telle quelle, et tout le reste est repeint avec le sol
enrichi. La silhouette dessinée à la main survit, le motif change. Un liseré
sombre est rendu à la lisière, parce que c'est le trait noir du pack qui
détachait la pierre de l'herbe et que le repeindre l'aurait effacé.

`--apercu` n'écrit rien dans le jeu : il dépose dans `/tmp` les deux sols et
leurs seize bords, agrandis, pour juger à l'œil.
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - dépendance d'atelier, pas de jeu
    sys.exit("Pillow manquant : python3 -m pip install Pillow")

RACINE = Path(__file__).resolve().parent.parent
PACK = RACINE / "assets" / "packs" / "sscap-srpg-tileset"
SOLS = RACINE / "assets" / "textures" / "terrain"
BORDS = SOLS / "edges"
TAILLE = 32

## Cellule du bloc pour chaque masque, en (colonne, rangée) depuis l'ancre.
##
## Identique à `decouper-bords.py` — c'est la disposition du pack, vérifiée
## cellule par cellule sur les pixels.
DISPOSITION: dict[str, tuple[int, int]] = {
    "nesw": (0, -1), "nsw": (1, -1), "nes": (2, -1), "new": (3, -1), "ew": (4, -1),
    "nw":   (0,  0), "n":   (1,  0), "ne":  (2,  0), "esw": (3,  0), "ns": (4,  0),
    "w":    (0,  1), "fill": (1, 1), "e":   (2,  1),
    "sw":   (0,  2), "s":   (1,  2), "es":  (2,  2),
}

# (clé de bord, nom du sol, planche, ancre, recette, liseré, écarts de disposition)
#
# Le bloc de pierre transpose ses deux cellules étroites par rapport aux quatre
# autres blocs de la planche : sa bande horizontale est en (9,5) et sa bande
# verticale en (9,6), l'inverse de la disposition commune. Mesuré sur les
# pixels, pas supposé — d'où l'écart déclaré ici plutôt qu'un silence.
MANIFESTE: list[tuple[str, str, str, tuple[int, int], str, float, dict]] = [
    ("fort",    "terrain_outdoor_flagstone", "Outdoor", (5, 6), "dalles", 0.58,
     {"ew": (4, 0), "ns": (4, -1)}),
    ("village", "terrain_outdoor_hamlet",    "Outdoor", (5, 2), "battue", 0.74, {}),
]

## Profondeur du liseré sombre, en pixels, à la lisière du sol et de l'herbe.
LISERE = 2

## Côté d'une dalle de la cour, en pixels — deux assises de deux dalles.
DALLE = 16
## Décalage de l'assise du bas : des joints croisés, jamais alignés.
DECALAGE = 8
## Ce qu'il reste du moellon dans une dalle aplanie (0 = dalle unie).
GRAIN_DALLE = 0.55
## Amplitude de la variation de ton d'une dalle à l'autre, par canal.
TON_DALLE = 9


#region Palette
def _palette(tuile: Image.Image) -> list[tuple[int, int, int]]:
    """Les couleurs de la tuile, triées de la plus sombre à la plus claire."""
    return sorted({px[:3] for px in tuile.convert("RGBA").getdata()},
                  key=lambda c: c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114)


def _quantile(palette: list[tuple[int, int, int]], part: float) -> tuple[int, int, int]:
    index = min(len(palette) - 1, max(0, round(part * (len(palette) - 1))))
    return palette[index]


def _melange(a, b, part: float) -> tuple[int, int, int]:
    return tuple(round(a[k] + (b[k] - a[k]) * part) for k in range(3))  # type: ignore[return-value]


def _ecarte(couleur, delta: int) -> tuple[int, int, int]:
    return tuple(min(255, max(0, c + delta)) for c in couleur)  # type: ignore[return-value]
#endregion


#region Lecture du pack
def _cellule(planche: str, col: int, rang: int) -> Image.Image:
    source = PACK / f"{planche}.png"
    if not source.exists():
        sys.exit(f"Planche introuvable : {source}")
    image = Image.open(source).convert("RGBA")
    x, y = col * TAILLE, rang * TAILLE
    if x < 0 or y < 0 or x + TAILLE > image.width or y + TAILLE > image.height:
        sys.exit(f"{planche} ({col},{rang}) déborde de la planche")
    return image.crop((x, y, x + TAILLE, y + TAILLE))


def _est_herbe(pixel) -> bool:
    """Ce pixel appartient-il au fond d'herbe du pack ?

    Un test de **teinte**, pas de distance à une couleur moyenne : l'herbe du
    pack est le seul vert franc de ces blocs, et la moyenne d'un blocage de
    pierre tombe si près du gris médian que la moitié des pixels d'herbe s'en
    réclamait. Le vert, lui, ne trompe pas.
    """
    r, g, b = pixel[:3]
    return g > r + 12 and g > b + 25
#endregion


#region Les deux sols
def _dalles(tuile: Image.Image, rng: random.Random) -> Image.Image:
    """La cour d'un fortin : des dalles taillées, à joints croisés.

    Le moellon du pack reste sous la dalle ([constant GRAIN_DALLE]) : sans lui
    la cour deviendrait un carrelage, et le fortin cesserait d'appartenir à la
    même planche que le reste du plateau.
    """
    source = tuile.convert("RGBA").load()
    palette = _palette(tuile)
    joint = _ecarte(_quantile(palette, 0.04), -10)
    chanfrein = _ecarte(_quantile(palette, 0.92), 12)
    ombre = _ecarte(_quantile(palette, 0.20), -14)

    def dalle_de(x: int, y: int) -> tuple[int, int, int, int]:
        """(assise, rang de dalle, abscisse dans la dalle, ordonnée dans la dalle)."""
        assise = y // DALLE
        sx = (x + (DECALAGE if assise else 0)) % TAILLE
        return assise, sx // DALLE, sx % DALLE, y % DALLE

    # Le ton moyen de chaque dalle, relevé sur les pixels qu'elle couvre.
    sommes: dict[tuple[int, int], list[int]] = {}
    for y in range(TAILLE):
        for x in range(TAILLE):
            assise, rang, _ox, _oy = dalle_de(x, y)
            total = sommes.setdefault((assise, rang), [0, 0, 0, 0])
            for k in range(3):
                total[k] += source[x, y][k]
            total[3] += 1

    tons: dict[tuple[int, int], tuple[int, int, int]] = {}
    for cle, total in sommes.items():
        moyen = tuple(total[k] // total[3] for k in range(3))
        tons[cle] = _ecarte(moyen, rng.randint(-TON_DALLE, TON_DALLE))

    image = Image.new("RGBA", (TAILLE, TAILLE))
    px = image.load()
    for y in range(TAILLE):
        for x in range(TAILLE):
            assise, rang, ox, oy = dalle_de(x, y)
            if ox == 0 or oy == 0:
                px[x, y] = joint + (255,)
                continue
            couleur = _melange(tons[(assise, rang)], source[x, y][:3], GRAIN_DALLE)
            # La lumière du plateau vient du nord-ouest : le chanfrein éclairé
            # se pose en haut et à gauche de la dalle, son ombre en bas à droite.
            if ox == 1 or oy == 1:
                couleur = _melange(couleur, chanfrein, 0.45)
            elif ox == DALLE - 1 or oy == DALLE - 1:
                couleur = _melange(couleur, ombre, 0.40)
            px[x, y] = couleur + (255,)
    return image


## Les deux encres du hameau, mêlées à la terre du pack plutôt que posées dessus.
##
## La cellule de terre battue du pack tient dans cinq niveaux d'ocre : ses
## quantiles clairs et sombres sont trop proches pour qu'un « éclaircir un peu »
## se voie. Les plaques tassées et les flaques séchées se mélangent donc vers ces
## deux couleurs-ci, franches, à faible dose ([constant PART_PLAQUE]) — c'est ce
## qui donne du modelé sans faire sortir la case de sa gamme.
POUSSIERE = (176, 154, 96)
TERRE_HUMIDE = (74, 58, 24)

## Part de l'encre dans une plaque (0 = la terre nue du pack).
PART_PLAQUE = 0.30


def _battue(tuile: Image.Image, rng: random.Random) -> Image.Image:
    """La terre battue d'un hameau : tassée, jonchée de paille, semée de pierres.

    Le sol d'un hameau n'est pas un champ : c'est ce qu'on piétine devant une
    porte. Il se lit en trois couches — les plaques que le passage a tassées ou
    détrempées, la poussière qui les grène, puis ce qui traîne dessus (paille,
    pierres). L'ordre compte : la paille est jetée sur la terre, pas dessous.
    """
    image = tuile.convert("RGBA").copy()
    px = image.load()
    palette = _palette(tuile)
    clair = _quantile(palette, 0.90)
    sombre = _quantile(palette, 0.12)
    paille = _melange(clair, (226, 202, 130), 0.72)
    pierre = _melange(sombre, (156, 150, 140), 0.60)

    def poser(x: int, y: int, couleur) -> None:
        px[x % TAILLE, y % TAILLE] = couleur + (255,)

    def lire(x: int, y: int) -> tuple[int, int, int]:
        return px[x % TAILLE, y % TAILLE][:3]

    # Les plaques d'abord : c'est le fond sur lequel tombe le reste.
    for _ in range(rng.randint(5, 6)):
        cx, cy = rng.randrange(TAILLE), rng.randrange(TAILLE)
        rayon = rng.randint(4, 7)
        encre = POUSSIERE if rng.random() < 0.55 else TERRE_HUMIDE
        for dy in range(-rayon, rayon + 1):
            for dx in range(-rayon, rayon + 1):
                carre = dx * dx + dy * dy
                if carre > rayon * rayon:
                    continue
                # Bord rongé : un disque net ferait une pastille, pas une plaque.
                if carre > (rayon - 2) ** 2 and rng.random() < 0.55:
                    continue
                poser(cx + dx, cy + dy,
                      _melange(lire(cx + dx, cy + dy), encre, PART_PLAQUE))

    # La poussière : un grain d'un pixel, assez dense pour tuer l'aplat.
    for _ in range(rng.randint(48, 64)):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        poser(x, y, _ecarte(lire(x, y), rng.choice((-14, -9, 9, 14))))

    # La paille : de courts brins couchés, jamais deux dans le même sens.
    for _ in range(rng.randint(6, 8)):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        dx, dy = rng.choice(((1, 0), (1, 1), (0, 1), (1, -1)))
        ton = _ecarte(paille, rng.randint(-14, 10))
        for i in range(rng.randint(2, 4)):
            poser(x + dx * i, y + dy * i, ton)

    # Une javelle ou deux : quelques brins tombés au même endroit, ce qui les
    # fait lire comme de la paille répandue plutôt que comme des rayures.
    for _ in range(rng.randint(1, 2)):
        cx, cy = rng.randrange(TAILLE), rng.randrange(TAILLE)
        for _brin in range(rng.randint(3, 4)):
            x, y = cx + rng.randint(-2, 2), cy + rng.randint(-2, 2)
            dx, dy = rng.choice(((1, 0), (1, 1), (0, 1), (1, -1)))
            for i in range(2):
                poser(x + dx * i, y + dy * i, _ecarte(paille, rng.randint(-18, 0)))

    # Les pierres enfoncées : deux pixels et leur ombre, pas davantage.
    for _ in range(rng.randint(3, 5)):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        poser(x, y, pierre)
        poser(x + 1, y, _ecarte(pierre, -18))
        if rng.random() < 0.5:
            poser(x, y + 1, _ecarte(pierre, -26))
    return image


RECETTES = {"dalles": _dalles, "battue": _battue}


def sol(nom_recette: str, planche: str, ancre: tuple[int, int]) -> Image.Image:
    """Le sol enrichi d'un terrain bâti, dérivé du remplissage du pack."""
    remplissage = _cellule(planche, ancre[0] + 1, ancre[1] + 1)
    return RECETTES[nom_recette](remplissage, random.Random(nom_recette))
#endregion


#region Les seize bords
def _distance_herbe(cellule: Image.Image) -> list[list[int]]:
    """Pour chaque pixel, sa distance à l'herbe la plus proche (bornée).

    Sert au seul liseré : au-delà de [constant LISERE] la valeur exacte n'a plus
    d'usage, la propagation s'arrête donc là.
    """
    px = cellule.convert("RGBA").load()
    loin = LISERE + 1
    distance = [[0 if _est_herbe(px[x, y]) else loin for x in range(TAILLE)]
                for y in range(TAILLE)]
    for _ in range(LISERE):
        avant = [ligne[:] for ligne in distance]
        for y in range(TAILLE):
            for x in range(TAILLE):
                voisins = [avant[y + dy][x + dx]
                           for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                           if 0 <= x + dx < TAILLE and 0 <= y + dy < TAILLE]
                distance[y][x] = min(distance[y][x], min(voisins) + 1)
    return distance


def bord(cellule: Image.Image, sol_tuile: Image.Image, force: float) -> Image.Image:
    """La cellule du pack, son sol repeint, son herbe intacte.

    [param force] est ce qu'il reste du sol sous le liseré : plus il est bas,
    plus la lisière est franche. La pierre en veut un net (le pack la cerne d'un
    trait noir), la terre un fondu (elle se perd dans l'herbe).
    """
    source = cellule.convert("RGBA").load()
    motif = sol_tuile.convert("RGBA").load()
    distance = _distance_herbe(cellule)

    image = Image.new("RGBA", (TAILLE, TAILLE))
    px = image.load()
    for y in range(TAILLE):
        for x in range(TAILLE):
            if distance[y][x] == 0:
                px[x, y] = source[x, y]
                continue
            r, g, b, _a = motif[x, y]
            if distance[y][x] <= LISERE:
                # Le liseré s'éclaircit en s'éloignant de l'herbe : d'un coup, il
                # redessinerait la marche d'escalier qu'il est censé masquer.
                part = force + (1.0 - force) * (distance[y][x] - 1) / max(LISERE - 1, 1)
                r, g, b = (int(r * part), int(g * part), int(b * part))
            px[x, y] = (r, g, b, 255)
    return image


def bords(cle: str, planche: str, ancre: tuple[int, int], sol_tuile: Image.Image,
          force: float, ecarts: dict) -> dict[str, Image.Image]:
    out: dict[str, Image.Image] = {}
    for masque, place in DISPOSITION.items():
        dc, dr = ecarts.get(masque, place)
        out[masque] = bord(_cellule(planche, ancre[0] + dc, ancre[1] + dr),
                           sol_tuile, force)
    return out
#endregion


def ecrire() -> int:
    SOLS.mkdir(parents=True, exist_ok=True)
    BORDS.mkdir(parents=True, exist_ok=True)
    for cle, nom, planche, ancre, recette, force, ecarts in MANIFESTE:
        tuile = sol(recette, planche, ancre)
        tuile.save(SOLS / f"{nom}.png")
        print(f"{cle} — sol « {recette} » → {(SOLS / f'{nom}.png').relative_to(RACINE)}")
        for masque, image in bords(cle, planche, ancre, tuile, force, ecarts).items():
            image.save(BORDS / f"{cle}_{masque}.png")
        print(f"  16 bords → {BORDS.relative_to(RACINE)}/{cle}_*.png")
    print("\nEnsuite : varier-tuiles.py (variantes) puis coins-transition.py (coins)")
    return 0


def apercu() -> int:
    """Les deux sols répétés 3 × 3, puis leurs seize bords en ligne."""
    lignes: list[Image.Image] = []
    for cle, _nom, planche, ancre, recette, force, ecarts in MANIFESTE:
        tuile = sol(recette, planche, ancre)
        pave = Image.new("RGBA", (TAILLE * 3, TAILLE * 3))
        for j in range(3):
            for i in range(3):
                pave.paste(tuile, (i * TAILLE, j * TAILLE))

        jeu = bords(cle, planche, ancre, tuile, force, ecarts)
        rangee = Image.new("RGBA", (TAILLE * (3 + len(jeu)), TAILLE * 3), (24, 22, 34, 255))
        rangee.paste(pave, (0, 0))
        for index, masque in enumerate(DISPOSITION):
            rangee.paste(jeu[masque], ((3 + index) * TAILLE, TAILLE))
        lignes.append(rangee)
        print(f"{cle} : sol + {len(jeu)} bords")

    planche_finale = Image.new("RGBA", (max(l.width for l in lignes),
                                        sum(l.height + 4 for l in lignes)),
                               (24, 22, 34, 255))
    y = 0
    for ligne in lignes:
        planche_finale.paste(ligne, (0, y))
        y += ligne.height + 4
    cible = "/tmp/sols-batis.png"
    planche_finale.resize((planche_finale.width * 4, planche_finale.height * 4),
                          Image.NEAREST).save(cible)
    print(f"\nAperçu : {cible}  (à gauche le sol répété 3 × 3, "
          f"à droite les seize bords dans l'ordre {', '.join(DISPOSITION)})")
    return 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--apercu", action="store_true",
                         help="dépose une planche de contrôle dans /tmp, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(apercu() if args.apercu else ecrire())
