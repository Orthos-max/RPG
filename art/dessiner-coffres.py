#!/usr/bin/env python3
"""Coffres pixel art 32x32, palette Velmar (nuit et or).

Génère chest.png (fermé) et chest_open.png (ouvert) dans
assets/textures/chests/. Style : caisse de bois sombre, ferrures dorées,
couvercle bombé, ombre portée ; ouvert = couvercle relevé + trésor doré.
"""
from PIL import Image, ImageDraw

S = 32  # taille de la texture

# Palette
WOOD_DARK = (58, 36, 20)
WOOD = (78, 49, 26)
WOOD_LIGHT = (104, 66, 34)
GOLD = (212, 175, 55)
GOLD_LIGHT = (245, 230, 163)
GOLD_DARK = (154, 123, 30)
BLACK = (12, 10, 8)
SHADOW = (0, 0, 0, 70)
INNER = (22, 14, 8)
COIN = (240, 200, 90)


def shadow(d: ImageDraw.ImageDraw) -> None:
    """Ombre portée ovale sous le coffre."""
    for dx in range(6, 26):
        h = 3 - abs(dx - 15) // 5
        for dy in range(h):
            d.point((dx, 30 + dy), fill=SHADOW)


def closed() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shadow(d)
    # Corps de la caisse (8..23 x, 17..28 y)
    for x in range(8, 24):
        for y in range(17, 29):
            base = WOOD if (x - y) % 5 != 0 else WOOD_DARK
            d.point((x, y), fill=base)
    # Bords du corps (liseré sombre)
    d.rectangle([8, 17, 23, 17], fill=BLACK)
    d.rectangle([8, 28, 23, 28], fill=BLACK)
    # Couvercle bombé (7..24 x, 9..18 y)
    for x in range(7, 25):
        # hauteur du couvercle : plus haut au centre
        top = 9 + abs(x - 15) // 3
        for y in range(top, 19):
            d.point((x, y), fill=WOOD_LIGHT if (x + y) % 4 != 0 else WOOD)
    d.rectangle([7, 9, 24, 9], fill=WOOD_LIGHT)
    # Arête du couvercle
    d.rectangle([7, 18, 24, 18], fill=BLACK)
    # Ferrures dorées : bande centrale + montants + loquet
    d.rectangle([7, 20, 24, 21], fill=GOLD)
    d.rectangle([8, 20, 9, 28], fill=GOLD)
    d.rectangle([22, 20, 23, 28], fill=GOLD)
    # Loquet / serrure centrale
    d.rectangle([13, 22, 18, 26], fill=GOLD_LIGHT)
    d.rectangle([14, 23, 17, 25], fill=BLACK)
    d.point((15, 24), fill=GOLD_LIGHT)
    # Rivets dorés sur le couvercle
    for rx in (9, 12, 15, 18, 21):
        d.point((rx, 12), fill=GOLD_LIGHT)
        d.point((rx, 15), fill=GOLD_DARK)
    return img


def opened() -> Image.Image:
    """Inutilisé depuis la simplification (le coffre ouvert disparaît),
    conservé pour mémoire : c'était le sprite « ouvert » 32x32."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shadow(d)
    return img


import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures", "chests")
os.makedirs(OUT, exist_ok=True)
closed().save(os.path.join(OUT, "chest.png"))
print("textures 32x32 générées dans", os.path.abspath(OUT))
