#!/usr/bin/env python3
"""Dessine les textures d'effets de combat sous assets/textures/effects/.

    python3 art/effets.py

Quatre imagettes, blanches et transparentes : `impact` (l'éclair posé sur la
cible), `spark` (l'étincelle d'un choc physique), `mote` (le grain de lumière
d'un sort ou d'un soin), `droplet` (la goutte de sang).

**Elles sont volontairement sans couleur.** La teinte vient du moteur, à
l'exécution ([BattleVFX]) : c'est ce qui permet à un seul grain de servir au
violet d'un sort comme à l'or d'un soin, sans multiplier les fichiers. Les
peindre ici obligerait à en dessiner un par situation.

L'alpha est quantifié sur quatre paliers (0, 96, 176, 255) : un dégradé continu
sur 8 pixels ne se lit pas, il salit le contour. Dépend de Pillow uniquement.
"""

from __future__ import annotations

import math
import os

from PIL import Image

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORTIE = os.path.join(RACINE, "assets", "textures", "effects")

# Paliers d'alpha autorisés — voir l'en-tête du module.
PALIERS = (0, 96, 176, 255)
# En dessous, le pixel est du bruit de bord : on le retire plutôt que de le
# monter au premier palier, qui l'épaissirait d'un anneau fantôme.
SEUIL = 0.16


def quantifier(valeur: float) -> int:
    """Ramène une intensité 0→1 sur l'un des paliers."""
    if valeur < SEUIL:
        return 0
    index = min(len(PALIERS) - 1, 1 + int(valeur * (len(PALIERS) - 1)))
    return PALIERS[index]


def dessiner(cote: int, intensite) -> Image.Image:
    """Construit une imagette carrée à partir d'une fonction (dx, dy) → 0→1.

    `dx`/`dy` sont comptés depuis le centre géométrique, en pixels.
    """
    img = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    centre = (cote - 1) / 2.0
    pixels = img.load()
    for y in range(cote):
        for x in range(cote):
            alpha = quantifier(max(0.0, min(1.0, intensite(x - centre, y - centre))))
            if alpha:
                pixels[x, y] = (255, 255, 255, alpha)
    return img


def impact(dx: float, dy: float) -> float:
    """Éclair à quatre branches : un cœur brûlant, des pointes en croix.

    Les branches restent fines (décroissance rapide hors de leur axe) : une
    croix épaisse donne une fleur, pas un choc.
    """
    rayon = math.hypot(dx, dy)
    coeur = math.exp(-rayon * 0.55)
    croix = max(math.exp(-abs(dy) * 1.7), math.exp(-abs(dx) * 1.7))
    portee = max(0.0, 1.0 - rayon / 8.5)
    return coeur + portee * croix * 1.2


def spark(dx: float, dy: float) -> float:
    """Étincelle : la même croix, resserrée sur huit pixels."""
    rayon = math.hypot(dx, dy)
    croix = max(math.exp(-abs(dy) * 1.5), math.exp(-abs(dx) * 1.5))
    return math.exp(-rayon * 0.75) + max(0.0, 1.0 - rayon / 4.0) * croix


def mote(dx: float, dy: float) -> float:
    """Grain de lumière : un disque plein au bord adouci."""
    return 1.25 - math.hypot(dx, dy) / 2.9


def droplet(dx: float, dy: float) -> float:
    """Goutte : ronde en bas, effilée vers le haut."""
    # Le haut est comprimé (la goutte s'y étire), le bas reste circulaire.
    etirement = 1.6 if dy < 0 else 1.0
    return 1.35 - math.hypot(dx * etirement, dy * 0.8) / 2.6


FIGURES = {
    "impact": (16, impact),
    "spark": (8, spark),
    "mote": (8, mote),
    "droplet": (8, droplet),
}


def main() -> None:
    os.makedirs(SORTIE, exist_ok=True)
    for nom, (cote, forme) in FIGURES.items():
        img = dessiner(cote, forme)
        chemin = os.path.join(SORTIE, f"{nom}.png")
        img.save(chemin)
        poses = sum(1 for a in img.split()[3].tobytes() if a > 0)
        print(f"  {nom}.png  {cote}×{cote}  {poses} pixels posés")
    print(f"\nÉcrit dans {SORTIE}")


if __name__ == "__main__":
    main()
