#!/usr/bin/env python3
"""Régénère le matériel de dessin des figurines depuis les planches en place.

À relancer après avoir ajouté ou retouché une planche. Tout se déduit des
fichiers — taille de case, ligne de pieds, palette : rien n'est écrit en dur, de
sorte qu'un changement d'échelle (32 → 64 → 128) n'oblige pas à toucher ce
script.

    python3 art/atelier.py

Dépend de Pillow uniquement.
"""

from __future__ import annotations

import glob
import os
import sys
from collections import Counter

from PIL import Image

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLANCHES = os.path.join(RACINE, "assets", "textures", "actor")
ATELIER = os.path.join(RACINE, "art")

# Accents repris de data/models/view/theme/palette.gd — la charte « Velmar ».
CHARTE = [
    ("INK", (0x14, 0x10, 0x26)),
    ("GOLD", (0xF5, 0xC8, 0x42)),
    ("GOLD_DIM", (0x8A, 0x70, 0x28)),
    ("CRIMSON", (0xE9, 0x45, 0x60)),
    ("VERDANT", (0x2D, 0x6A, 0x4F)),
    ("TEXT", (0xE8, 0xE6, 0xF0)),
]

# Un pixel est « posé » au-delà de ce seuil d'alpha. En dessous c'est du bord
# adouci, pas de la couleur choisie : le compter fausserait la palette.
SEUIL_ALPHA = 8


def planches() -> list[str]:
    trouvees = sorted(set(glob.glob(os.path.join(PLANCHES, "**", "*.png"), recursive=True)))
    if not trouvees:
        sys.exit(f"Aucune planche sous {PLANCHES}")
    tailles = {Image.open(f).size for f in trouvees}
    if len(tailles) > 1:
        sys.exit(f"Planches de tailles differentes, a uniformiser d'abord : {sorted(tailles)}")
    return trouvees


def couleurs(img: Image.Image) -> set[tuple[int, int, int]]:
    return {p[:3] for p in img.getdata() if p[3] > SEUIL_ALPHA}


def mesurer(fichiers: list[str]) -> dict:
    """Déduit la géométrie commune : case, ligne de pieds, sommet du crâne.

    On prend le sol le plus fréquent plutôt que le plus bas : une planche qui
    déborde de deux pixels est un défaut à corriger, pas la règle à suivre.
    """
    larg, haut = Image.open(fichiers[0]).size
    case = haut // 2
    sols: Counter = Counter()
    cranes: Counter = Counter()
    for f in fichiers:
        im = Image.open(f).convert("RGBA")
        for rangee in (0, case):
            pose = im.crop((0, rangee, larg, rangee + case))
            bb = pose.getbbox()
            if bb:
                cranes[bb[1]] += 1
                sols[bb[3]] += 1
    return {
        "largeur": larg,
        "hauteur": haut,
        "case": case,
        "sol": sols.most_common(1)[0][0],
        "crane": cranes.most_common(1)[0][0],
        "axe": larg // 2,
        "hors_norme": {k: v for k, v in sols.items() if k != sols.most_common(1)[0][0]},
    }


def ecrire_palette(fichiers: list[str]) -> int:
    """Palette GIMP triée par nombre de planches où la couleur apparaît."""
    compte: Counter = Counter()
    for f in fichiers:
        compte.update(couleurs(Image.open(f).convert("RGBA")))

    def luminance(c: tuple[int, int, int]) -> float:
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

    ordre = sorted(compte, key=lambda c: (-compte[c], luminance(c)))
    total = len(fichiers)
    with open(os.path.join(ATELIER, "palette-figurines.gpl"), "w") as fh:
        fh.write("GIMP Palette\nName: Ciel Emblem - figurines\nColumns: 8\n#\n")
        fh.write("# Couleurs du casting, les plus partagees en premier.\n")
        for c in ordre:
            fh.write(f"{c[0]:3d} {c[1]:3d} {c[2]:3d}\tfig {c[0]:02x}{c[1]:02x}{c[2]:02x} ({compte[c]}/{total})\n")
        fh.write('#\n# Accents de la charte « Velmar : nuit et or »\n')
        for nom, c in CHARTE:
            fh.write(f"{c[0]:3d} {c[1]:3d} {c[2]:3d}\tcharte {nom}\n")
    return len(ordre)


def ecrire_gabarit(g: dict) -> None:
    """Calque de repères à superposer dans l'éditeur pixel."""
    img = Image.new("RGBA", (g["largeur"], g["hauteur"]), (0, 0, 0, 0))
    px = img.load()
    sol, crane, axe, coupe = (255, 0, 110, 190), (0, 200, 255, 120), (255, 255, 255, 70), (255, 180, 0, 220)
    for rangee in (0, g["case"]):
        for x in range(g["largeur"]):
            px[x, rangee + g["sol"] - 1] = sol
            px[x, rangee + g["crane"]] = crane
        for y in range(0, g["case"], 2):  # pointillé : l'axe ne doit pas masquer le dessin
            px[g["axe"], rangee + y] = axe
    for x in range(g["largeur"]):
        px[x, g["case"] - 1] = coupe
    img.save(os.path.join(ATELIER, "gabarit-reperes.png"))


def ecrire_contact(fichiers: list[str], g: dict) -> tuple[int, int]:
    """Les planches côte à côte, sur le fond de la charte — la vue du joueur.

    L'agrandissement s'adapte : une planche de 128 n'a pas besoin du ×4 qu'il
    fallait à une de 32 pour être lisible à l'écran.
    """
    echelle = max(1, 512 // g["hauteur"])
    vues = [Image.open(f).convert("RGBA") for f in fichiers]
    contact = Image.new("RGBA", (sum(v.width for v in vues) * echelle,
                                 g["hauteur"] * echelle), CHARTE[0][1] + (255,))
    x = 0
    for v in vues:
        agrandie = v.resize((v.width * echelle, v.height * echelle), Image.NEAREST)
        contact.paste(agrandie, (x, 0), agrandie)
        x += agrandie.width
    contact.save(os.path.join(ATELIER, "planche-contact.png"))
    return contact.size


def main() -> None:
    fichiers = planches()
    g = mesurer(fichiers)
    n = ecrire_palette(fichiers)
    ecrire_gabarit(g)
    taille = ecrire_contact(fichiers, g)
    print(f"{len(fichiers)} planches lues, case de {g['largeur']}x{g['case']}")
    print(f"palette-figurines.gpl : {n} couleurs + {len(CHARTE)} accents de charte")
    print(f"gabarit-reperes.png   : sol y={g['sol']}, crane y={g['crane']}, axe x={g['axe']}")
    print(f"planche-contact.png   : {taille[0]}x{taille[1]}")
    if g["hors_norme"]:
        print(f"\n⚠  Planches hors norme (sol attendu a y={g['sol']}) : {g['hors_norme']}")
        print("   Une unite dont les pieds ne tombent pas sur la ligne flotte ou s'enfonce.")


if __name__ == "__main__":
    main()
