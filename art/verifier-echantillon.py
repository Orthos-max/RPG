#!/usr/bin/env python3
"""Passe un échantillon de pack au crible, avant de l'acheter.

Répond mécaniquement aux questions qui décident d'un achat, et que l'œil juge
mal sur une page de vente :

  - la résolution annoncée est-elle réelle, ou un agrandissement ?
  - est-ce du vrai pixel art, ou une illustration réduite (anticrénelage) ?
  - la palette est-elle serrée, comme celle du casting ?
  - les pieds tombent-ils au même endroit d'une planche à l'autre ?

L'origine de l'image — main, IA, mixte — n'entre pas en compte : seules ces
propriétés-là se voient en jeu.

    python3 art/verifier-echantillon.py une-image.png [autre.png ...]

Dépend de Pillow uniquement.
"""

from __future__ import annotations

import os
import sys

from PIL import Image

# Au-delà, on n'est plus sur une palette de pixel art mais sur un dégradé.
# Le casting de Ciel Emblem tient en 25 couleurs pour huit planches.
COULEURS_MAX = 64

# Proportion de pixels à alpha partiel au-delà de laquelle le bord est adouci.
# Du pixel art franc n'en a quasiment pas ; `fix_alpha_border` en tolère un peu.
ANTICRENELAGE_MAX = 0.02

SEUIL_ALPHA = 8


def facteur_agrandissement(im: Image.Image) -> int:
    """Le plus grand N tel que l'image soit un agrandissement ×N au plus proche
    voisin. 1 = l'image porte vraiment sa résolution."""
    for n in (8, 4, 3, 2):
        if im.width % n or im.height % n:
            continue
        reduite = im.resize((im.width // n, im.height // n), Image.NEAREST)
        if reduite.resize(im.size, Image.NEAREST).tobytes() == im.tobytes():
            return n
    return 1


def analyser(chemin: str) -> None:
    im = Image.open(chemin).convert("RGBA")
    pixels = list(im.getdata())
    opaques = [p for p in pixels if p[3] > SEUIL_ALPHA]
    if not opaques:
        print(f"{os.path.basename(chemin)} : image vide")
        return

    couleurs = {p[:3] for p in opaques}
    partiels = sum(1 for p in pixels if SEUIL_ALPHA < p[3] < 248)
    part_aa = partiels / max(1, len(opaques))
    facteur = facteur_agrandissement(im)

    print(f"\n=== {os.path.basename(chemin)} — {im.width}×{im.height} ===")

    verdicts: list[tuple[bool, str]] = []

    if facteur > 1:
        verdicts.append((False, f"agrandissement ×{facteur} : la résolution reelle "
                                f"est {im.width // facteur}×{im.height // facteur}"))
    else:
        verdicts.append((True, "resolution reelle, pas un agrandissement"))

    verdicts.append((len(couleurs) <= COULEURS_MAX,
                     f"{len(couleurs)} couleurs (limite indicative : {COULEURS_MAX})"))

    verdicts.append((part_aa <= ANTICRENELAGE_MAX,
                     f"{part_aa:.1%} de pixels a alpha partiel "
                     f"(limite : {ANTICRENELAGE_MAX:.0%}) — au-dela, bords adoucis"))

    # Si l'image a le rapport d'une planche a deux rangees, verifier l'aplomb.
    if im.height == im.width * 2:
        case = im.height // 2
        sols = []
        for rangee in (0, case):
            bb = im.crop((0, rangee, im.width, rangee + case)).getbbox()
            sols.append(bb[3] if bb else 0)
        verdicts.append((sols[0] == sols[1],
                         f"pieds a y={sols[0]} et y={sols[1]} dans leur case "
                         f"{'(alignes)' if sols[0] == sols[1] else '(DECALES)'}"))

    for ok, texte in verdicts:
        print(f"  {'OK  ' if ok else 'NON '} {texte}")

    if all(ok for ok, _ in verdicts):
        print("  → passe les tests mecaniques. Reste a juger le style, les "
              "proportions (~2,3 tetes) et la presence de montures.")
    else:
        print("  → echoue au moins un test. Voir art/ACHAT-PACK.md.")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for chemin in sys.argv[1:]:
        if not os.path.exists(chemin):
            print(f"{chemin} : introuvable")
            continue
        analyser(chemin)


if __name__ == "__main__":
    main()
