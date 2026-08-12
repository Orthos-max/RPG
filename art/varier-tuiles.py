#!/usr/bin/env python3
"""Dérive des **variantes** des tuiles de terrain, pour casser le damier.

    python3 art/varier-tuiles.py [--planche-contact]

Chaque terrain ne portait qu'une seule tuile 32 × 32, projetée en coordonnées
monde : seize cases d'herbe montraient seize fois le même motif, à la même
phase, et le plateau redevenait le damier que toute la passe artistique
cherchait à faire oublier.

Ce script écrit, à côté de chaque tuile de base, trois ou quatre **variantes** :
la même surface, avec autre chose dessus. Une fleur, un caillou, une plaque
d'herbe rase, un champignon sous les arbres. [TacticsScenery] en choisit une par
case, par hachage de sa coordonnée — la carte est donc stable d'un chargement à
l'autre, et deux machines d'une partie en réseau dessinent la même prairie.

## Dériver plutôt que découper

Le pack SSCAP a bien des cellules voisines, mais ce sont des **bords** et des
morceaux de bâtiment, pas des remplissages interchangeables : `decouper-tuiles.py`
n'en a trouvé qu'un par terrain, et c'est normal — un jeu d'autotuiles n'a besoin
que de celui-là. Les variantes se dérivent donc de la tuile retenue, ce qui règle
d'un coup la contrainte de palette : les détails sont peints avec **les couleurs
de la tuile elle-même**, échantillonnées sur ses propres pixels. Aucune variante
ne peut sortir de la gamme, puisqu'elle n'a pas d'autre encre.

## Deux règles qui tiennent le raccord

1. **Rien ne touche les bords.** Une case d'herbe `v2` en jouxte une `v0` : si la
   variante avait retouché sa bordure, la couture se verrait d'une case à
   l'autre. Les détails sont donc plantés à [constant MARGE] pixels du cadre, et
   la teinte d'ensemble n'est jamais retouchée.
2. **Les détails sont rares.** Trois à six taches par tuile de 32 × 32. Au-delà,
   la variante cesse d'être de l'herbe pour devenir un motif — et quatre motifs
   se repèrent aussi vite qu'un seul.

`--planche-contact` n'écrit aucune variante : il assemble une planche de
vérification (chaque terrain en ligne, ses variantes en colonnes, répétées 2 × 2)
dans `art/planche-variantes.png`, pour juger à l'œil de ce que le hachage va
distribuer.
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
BASES = RACINE / "assets" / "textures" / "terrain"
SORTIE = BASES / "variants"
TAILLE = 32

## Distance minimale au bord de la tuile, en pixels.
##
## Un détail planté plus près déborderait visuellement sur la case voisine, qui
## porte peut-être une autre variante : c'est exactement la couture qu'on évite.
MARGE = 4

# (fichier de base, nombre de variantes, recette)
#
# Le compte suit la visibilité : l'herbe couvre le plus de cases et se lit le
# mieux, elle en reçoit quatre. Les sols bâtis, qu'on voit par plaques de deux ou
# trois cases, se contentent de trois.
MANIFESTE: list[tuple[str, int, str]] = [
    ("terrain_outdoor_grass",  4, "prairie"),
    ("terrain_outdoor_forest", 3, "sous-bois"),
    ("terrain_outdoor_sand",   3, "sable"),
    ("terrain_outdoor_path",   3, "chemin"),
    ("terrain_outdoor_earth",  3, "terre"),
    ("terrain_outdoor_cobble", 3, "pave"),
]


#region Palette
def _palette(tuile: Image.Image) -> list[tuple[int, int, int]]:
    """Les couleurs de la tuile, triées de la plus sombre à la plus claire."""
    couleurs = sorted({px[:3] for px in tuile.convert("RGBA").getdata()},
                      key=lambda c: c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114)
    return couleurs


def _quantile(palette: list[tuple[int, int, int]], part: float) -> tuple[int, int, int]:
    """La couleur au rang demandé (0 = la plus sombre, 1 = la plus claire)."""
    index = min(len(palette) - 1, max(0, round(part * (len(palette) - 1))))
    return palette[index]


def _melange(a: tuple[int, int, int], b: tuple[int, int, int],
             part: float) -> tuple[int, int, int]:
    return tuple(round(a[k] + (b[k] - a[k]) * part) for k in range(3))  # type: ignore[return-value]


def _ecarte(couleur: tuple[int, int, int], delta: int) -> tuple[int, int, int]:
    """Éclaircit ou assombrit sans quitter la gamme (bornes dures à 0 et 255)."""
    return tuple(min(255, max(0, c + delta)) for c in couleur)  # type: ignore[return-value]
#endregion


#region Pinceaux
def _tache(tuile: Image.Image, rng: random.Random, couleur, rayon: int) -> None:
    """Une tache ronde, plantée à distance du bord."""
    cx = rng.randint(MARGE + rayon, TAILLE - 1 - MARGE - rayon)
    cy = rng.randint(MARGE + rayon, TAILLE - 1 - MARGE - rayon)
    px = tuile.load()
    for dy in range(-rayon, rayon + 1):
        for dx in range(-rayon, rayon + 1):
            if dx * dx + dy * dy > rayon * rayon:
                continue
            px[cx + dx, cy + dy] = couleur + (255,)


def _fleur(tuile: Image.Image, rng: random.Random, coeur, petale) -> None:
    """Une fleur : quatre pétales en croix autour d'un cœur d'un pixel."""
    cx = rng.randint(MARGE + 1, TAILLE - 2 - MARGE)
    cy = rng.randint(MARGE + 1, TAILLE - 2 - MARGE)
    px = tuile.load()
    for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
        px[cx + dx, cy + dy] = petale + (255,)
    px[cx, cy] = coeur + (255,)


def _brin(tuile: Image.Image, rng: random.Random, couleur) -> None:
    """Un brin dressé : deux ou trois pixels en colonne, avec une inflexion."""
    hauteur = rng.randint(2, 3)
    cx = rng.randint(MARGE + 1, TAILLE - 2 - MARGE)
    cy = rng.randint(MARGE + hauteur, TAILLE - 1 - MARGE)
    px = tuile.load()
    for i in range(hauteur):
        px[cx + (1 if i == hauteur - 1 and rng.random() < 0.5 else 0), cy - i] = couleur + (255,)


def _fissure(tuile: Image.Image, rng: random.Random, couleur) -> None:
    """Une fissure : une marche d'escalier de quatre à six pixels."""
    x = rng.randint(MARGE, TAILLE - 1 - MARGE - 6)
    y = rng.randint(MARGE + 2, TAILLE - 3 - MARGE)
    px = tuile.load()
    for _ in range(rng.randint(4, 6)):
        px[x, y] = couleur + (255,)
        x += 1
        y += rng.choice((-1, 0, 0, 1))
        y = min(TAILLE - 1 - MARGE, max(MARGE, y))


def _ride(tuile: Image.Image, rng: random.Random, couleur) -> None:
    """Une ride de sable : un trait horizontal légèrement ondulé."""
    x = rng.randint(MARGE, TAILLE - 1 - MARGE - 8)
    y = rng.randint(MARGE, TAILLE - 1 - MARGE)
    px = tuile.load()
    for i in range(rng.randint(6, 9)):
        px[x + i, y] = couleur + (255,)
        if rng.random() < 0.3:
            y = min(TAILLE - 1 - MARGE, max(MARGE, y + rng.choice((-1, 1))))
#endregion


#region Recettes
## Ce qui pousse, traîne ou se fend sur chaque terrain.
##
## Chaque recette reçoit la tuile, un tirage déterministe et la palette de la
## tuile elle-même. Elle n'a le droit d'écrire qu'avec cette palette, éventuellement
## poussée de quelques niveaux ([method _ecarte]) — c'est ce qui garde toutes les
## variantes d'un terrain dans la même gamme que sa tuile de base.
def _prairie(tuile, rng, palette) -> None:
    clair = _quantile(palette, 0.85)
    sombre = _quantile(palette, 0.15)
    # Une plaque d'herbe rase ou deux : c'est ce qui se lit de plus loin.
    for _ in range(rng.randint(1, 2)):
        _tache(tuile, rng, _ecarte(clair, 8), rng.randint(2, 3))
    # Des fleurs, blanches ou dorées — les seules encres ajoutées, et à moitié
    # noyées dans la teinte de l'herbe pour ne pas trouer la tuile.
    coeur, petale = rng.choice((
        (_melange(clair, (255, 236, 150), 0.75), _melange(clair, (250, 250, 235), 0.70)),
        (_melange(clair, (255, 215, 120), 0.65), _melange(clair, (245, 225, 150), 0.60)),
        (_melange(clair, (235, 225, 250), 0.70), _melange(clair, (230, 220, 245), 0.65)),
    ))
    for _ in range(rng.randint(1, 3)):
        _fleur(tuile, rng, coeur, petale)
    # Un caillou perdu dans l'herbe, ou une touffe plus haute.
    if rng.random() < 0.6:
        _tache(tuile, rng, _melange(sombre, (150, 145, 130), 0.55), 1)
    for _ in range(rng.randint(1, 2)):
        _brin(tuile, rng, _ecarte(clair, 14))


def _sous_bois(tuile, rng, palette) -> None:
    clair = _quantile(palette, 0.90)
    sombre = _quantile(palette, 0.10)
    # Des trouées de lumière dans la canopée, et l'ombre qui va avec.
    for _ in range(rng.randint(1, 2)):
        _tache(tuile, rng, _ecarte(clair, 6), rng.randint(1, 2))
    for _ in range(rng.randint(1, 2)):
        _tache(tuile, rng, _ecarte(sombre, -6), rng.randint(1, 2))
    # Un champignon : un chapeau de deux pixels sur un pied clair.
    if rng.random() < 0.7:
        chapeau = _melange(clair, (196, 96, 72), 0.60)
        pied = _melange(clair, (232, 222, 200), 0.55)
        cx = rng.randint(MARGE + 1, TAILLE - 2 - MARGE)
        cy = rng.randint(MARGE + 1, TAILLE - 2 - MARGE)
        px = tuile.load()
        px[cx, cy] = chapeau + (255,)
        px[cx + 1, cy] = chapeau + (255,)
        px[cx, cy + 1] = pied + (255,)


def _sable(tuile, rng, palette) -> None:
    clair = _quantile(palette, 0.92)
    sombre = _quantile(palette, 0.20)
    for _ in range(rng.randint(1, 2)):
        _ride(tuile, rng, _ecarte(sombre, -6))
    for _ in range(rng.randint(1, 2)):
        _tache(tuile, rng, _ecarte(clair, 6), rng.randint(1, 2))
    # Deux ou trois graviers, plus sombres que le sable qui les porte.
    for _ in range(rng.randint(2, 3)):
        _tache(tuile, rng, _melange(sombre, (140, 120, 92), 0.45), 1)


def _chemin(tuile, rng, palette) -> None:
    clair = _quantile(palette, 0.90)
    sombre = _quantile(palette, 0.15)
    # L'ornière : deux traits parallèles usés par le passage.
    for _ in range(rng.randint(1, 2)):
        _ride(tuile, rng, _ecarte(sombre, -10))
    for _ in range(rng.randint(2, 4)):
        _tache(tuile, rng, _melange(sombre, (120, 104, 80), 0.50), 1)
    if rng.random() < 0.6:
        _tache(tuile, rng, _ecarte(clair, 8), 2)


def _terre(tuile, rng, palette) -> None:
    clair = _quantile(palette, 0.90)
    sombre = _quantile(palette, 0.10)
    # Des mottes : c'est de la terre battue, elle se craquelle et se retourne.
    for _ in range(rng.randint(2, 3)):
        _tache(tuile, rng, _ecarte(sombre, -8), rng.randint(1, 2))
    for _ in range(rng.randint(1, 2)):
        _tache(tuile, rng, _ecarte(clair, 10), rng.randint(1, 2))
    if rng.random() < 0.5:
        _fissure(tuile, rng, _ecarte(sombre, -12))


def _pave(tuile, rng, palette) -> None:
    clair = _quantile(palette, 0.85)
    sombre = _quantile(palette, 0.10)
    # Une dalle plus claire, une fissure, un peu de mousse dans les joints.
    for _ in range(rng.randint(1, 2)):
        _tache(tuile, rng, _ecarte(clair, 10), rng.randint(1, 2))
    if rng.random() < 0.7:
        _fissure(tuile, rng, _ecarte(sombre, -6))
    for _ in range(rng.randint(1, 2)):
        _tache(tuile, rng, _melange(sombre, (96, 124, 62), 0.45), 1)


RECETTES = {
    "prairie": _prairie,
    "sous-bois": _sous_bois,
    "sable": _sable,
    "chemin": _chemin,
    "terre": _terre,
    "pave": _pave,
}
#endregion


def _base(nom: str) -> Image.Image:
    source = BASES / f"{nom}.png"
    if not source.exists():
        sys.exit(f"Tuile de base introuvable : {source} (lancer decouper-tuiles.py ?)")
    return Image.open(source).convert("RGBA")


def _variante(nom: str, recette: str, index: int) -> Image.Image:
    """La variante `index` d'une tuile, toujours la même pour un même index.

    La graine est tirée du nom et de l'index : réécrire la bibliothèque ne
    redistribue pas les fleurs, et une carte déjà jouée reste la carte qu'on
    connaît.
    """
    tuile = _base(nom)
    palette = _palette(tuile)
    rng = random.Random(f"{nom}#{index}")
    RECETTES[recette](tuile, rng, palette)
    return tuile


def ecrire() -> int:
    SORTIE.mkdir(parents=True, exist_ok=True)
    ecrites = 0
    for nom, compte, recette in MANIFESTE:
        for index in range(1, compte + 1):
            cible = SORTIE / f"{nom}_v{index}.png"
            _variante(nom, recette, index).save(cible)
            ecrites += 1
        print(f"  {nom} — {compte} variantes ({recette})")
    print(f"\n{ecrites} variantes écrites dans {SORTIE.relative_to(RACINE)}")
    return 0


def planche_contact() -> int:
    """Chaque terrain en ligne, ses variantes en colonnes, répétées 2 × 2."""
    bloc = TAILLE * 2
    largeur = bloc * (1 + max(c for _n, c, _r in MANIFESTE))
    planche = Image.new("RGBA", (largeur, bloc * len(MANIFESTE)), (24, 22, 34, 255))

    for ligne, (nom, compte, recette) in enumerate(MANIFESTE):
        tuiles = [_base(nom)] + [_variante(nom, recette, i) for i in range(1, compte + 1)]
        for colonne, tuile in enumerate(tuiles):
            for dy in range(2):
                for dx in range(2):
                    planche.paste(tuile, (colonne * bloc + dx * TAILLE,
                                          ligne * bloc + dy * TAILLE))

    cible = RACINE / "art" / "planche-variantes.png"
    planche.resize((largeur * 3, planche.height * 3), Image.NEAREST).save(cible)
    print(f"Planche de contact → {cible.relative_to(RACINE)}")
    print("Colonne 0 : la tuile de base. Les suivantes : ses variantes.")
    return 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--planche-contact", action="store_true",
                         help="assemble une planche de vérification, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(planche_contact() if args.planche_contact else ecrire())
