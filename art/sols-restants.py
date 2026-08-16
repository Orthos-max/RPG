#!/usr/bin/env python3
"""Les huit sols que le pack ne donnait pas : neige, marais, fosse, ouvrages.

    python3 art/sols-restants.py [--apercu]

`decouper-tuiles.py` a pris dans SSCAP tout ce qui s'y trouvait, `sols-batis.py`
a dérivé la cour d'un fortin et la terre d'un hameau. Restaient huit terrains
mal servis, et ils se répartissent en deux misères :

- **neige, marais, porte, tour** n'avaient aucune tuile. [TacticsScenery] les
  rendait donc à la teinte plus un bruit procédural : un aplat clair, un aplat
  vert sombre, deux aplats gris. C'est le rendu que le joueur voit et qu'il
  appelle « une case vide » ;
- **sable, fosse, ruines, mur** en portaient une, empruntée à autre chose. La
  fosse montrait l'aplat très sombre de `mountains v2`, le mur la roche foncée
  de la montagne, les ruines un pavé neuf. Aucune ne disait ce qu'elle était.

Le pack ne pouvait pas les tirer d'affaire : ses 350 cellules n'ont ni neige, ni
marais, ni vue de dessus d'un rempart (planches relues cellule par cellule le
2026-08-16). Ces huit sols sont donc **peints ici**, à la même taille et dans la
même gamme que les tuiles découpées — 32 × 32, quatre à six tons par terrain,
aucun dégradé continu.

## Ce qui tient le raccord

Tout est tracé **modulo la tuile** : un caillou qui sort à droite rentre à
gauche, et le bruit de fond est cyclique par construction ([method _bruit]). La
tuile est projetée en coordonnées monde à raison d'une par case ; sans cela, la
couture se verrait à chaque frontière de case, c'est-à-dire partout.

## Ce qui n'est pas dessiné ici, et pourquoi

Les **objets** d'une case sont posés en volume par [TacticsProps] : le créneau
d'un mur, les piles d'une porte, le fût d'une tour, les colonnes brisées d'une
ruine, les roseaux d'un marais. Le sol ne les répète pas — une colonne peinte
*sous* la colonne en volume ferait deux colonnes. Ces tuiles disent donc le
**sol** de l'ouvrage : l'assise circulaire de la tour, le seuil usé de la porte,
le chemin de ronde du mur, le dallage crevé de la ruine.

Les accidents ponctuels — coquillage, éclat, touffe — ne sont pas non plus ici
mais dans les variantes (`varier-tuiles.py`). La raison est mécanique : quand un
terrain a des variantes, [method TacticsScenery.variant_rank] en tire toujours
une, et la tuile de base ne s'affiche plus telle quelle. Un coquillage peint
dans le fond serait un coquillage sur **toutes** les cases de sable ; peint dans
une variante sur trois, il est ce qu'il doit être — une trouvaille.

`--apercu` n'écrit rien dans le jeu : il dépose dans `/tmp` les huit sols
répétés 3 × 3, agrandis, pour juger de la couture à l'œil.
"""

from __future__ import annotations

import argparse
import math
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
TAILLE = 32


#region Outils
def _cellule(planche: str, col: int, rang: int) -> Image.Image:
    """Une cellule 32 × 32 d'une planche du pack."""
    source = PACK / f"{planche}.png"
    if not source.exists():
        sys.exit(f"Planche introuvable : {source}")
    image = Image.open(source).convert("RGBA")
    x, y = col * TAILLE, rang * TAILLE
    if x + TAILLE > image.width or y + TAILLE > image.height:
        sys.exit(f"{planche} ({col},{rang}) déborde de la planche")
    return image.crop((x, y, x + TAILLE, y + TAILLE))


def _melange(a, b, part: float) -> tuple[int, int, int]:
    return tuple(round(a[k] + (b[k] - a[k]) * part) for k in range(3))  # type: ignore[return-value]


def _ecarte(couleur, delta: int) -> tuple[int, int, int]:
    return tuple(min(255, max(0, c + delta)) for c in couleur)  # type: ignore[return-value]


def _bruit(graine: str, maille: int, octaves: int = 2) -> list[list[float]]:
    """Bruit de valeur **cyclique**, dans [0, 1], à la taille de la tuile.

    Le treillis se referme sur lui-même (`% n`) et le pas divise toujours 32 :
    le bruit se répète donc exactement d'une tuile à l'autre, ce qui est la
    condition pour qu'une plaque de neige traverse une frontière de case sans
    qu'on la voie.

    [param maille] est la taille des taches du premier octave, en pixels ; les
    octaves suivants la divisent par deux et pèsent moitié moins.
    """
    rng = random.Random(graine)
    cumul = [[0.0] * TAILLE for _ in range(TAILLE)]
    amplitude, poids = 1.0, 0.0
    for octave in range(octaves):
        pas = max(2, maille >> octave)
        n = max(1, TAILLE // pas)
        treillis = [[rng.random() for _ in range(n)] for _ in range(n)]
        for y in range(TAILLE):
            fy = y / pas
            y0 = int(fy) % n
            y1 = (y0 + 1) % n
            ty = fy - int(fy)
            sy = ty * ty * (3.0 - 2.0 * ty)
            for x in range(TAILLE):
                fx = x / pas
                x0 = int(fx) % n
                x1 = (x0 + 1) % n
                tx = fx - int(fx)
                sx = tx * tx * (3.0 - 2.0 * tx)
                haut = treillis[y0][x0] * (1 - sx) + treillis[y0][x1] * sx
                bas = treillis[y1][x0] * (1 - sx) + treillis[y1][x1] * sx
                cumul[y][x] += (haut * (1 - sy) + bas * sy) * amplitude
        poids += amplitude
        amplitude *= 0.5
    return [[v / poids for v in ligne] for ligne in cumul]


def _ton(tons: list[tuple[int, int, int]], valeur: float) -> tuple[int, int, int]:
    """La couleur d'un niveau de bruit, par paliers francs.

    Des paliers, pas un dégradé : c'est ce qui sépare une tuile de pixel art
    d'un rendu de bruit, et ce que font toutes les tuiles du pack.
    """
    index = int(max(0.0, min(0.9999, valeur)) * len(tons))
    return tons[index]


class Toile:
    """Une tuile en cours de peinture, où tout se pose **modulo la case**."""

    def __init__(self, fond: tuple[int, int, int] = (0, 0, 0)) -> None:
        self.image = Image.new("RGBA", (TAILLE, TAILLE), fond + (255,))
        self.px = self.image.load()

    def poser(self, x: int, y: int, couleur) -> None:
        self.px[int(x) % TAILLE, int(y) % TAILLE] = tuple(couleur[:3]) + (255,)

    def lire(self, x: int, y: int) -> tuple[int, int, int]:
        return self.px[int(x) % TAILLE, int(y) % TAILLE][:3]

    def teinter(self, x: int, y: int, couleur, part: float) -> None:
        self.poser(x, y, _melange(self.lire(x, y), couleur, part))

    def disque(self, cx: float, cy: float, rayon: float, couleur,
               rugosite: float = 0.0, rng: random.Random | None = None) -> None:
        """Une tache ronde au bord rongé — un disque net fait une pastille."""
        entier = int(math.ceil(rayon)) + 1
        for dy in range(-entier, entier + 1):
            for dx in range(-entier, entier + 1):
                distance = math.hypot(dx, dy)
                if distance > rayon:
                    continue
                if rugosite and rng and distance > rayon - 1.5 and rng.random() < rugosite:
                    continue
                self.poser(cx + dx, cy + dy, couleur)

    def trait(self, x: float, y: float, dx: float, dy: float, longueur: int,
              couleur, serpent: random.Random | None = None) -> None:
        """Un trait, éventuellement serpenté d'un pixel — jamais une droite nette."""
        for i in range(longueur):
            self.poser(x + dx * i, y + dy * i, couleur)
            if serpent and serpent.random() < 0.35:
                y += serpent.choice((-1, 1)) * abs(dy - 1) * 0.0 + (
                    serpent.choice((-1, 1)) if abs(dx) >= abs(dy) else 0)
                x += serpent.choice((-1, 1)) if abs(dy) > abs(dx) else 0

    def resultat(self) -> Image.Image:
        return self.image
#endregion


#region Les surfaces naturelles
## La neige : cinq tons, du creux bleuté à la crête éclairée.
##
## L'écart entre le plus sombre et le plus clair est volontairement petit. Une
## neige contrastée devient un marbre ; c'est le *nombre* de paliers, pas leur
## écart, qui empêche l'aplat.
TONS_NEIGE = [
    (188, 202, 222),
    (208, 220, 236),
    (224, 233, 245),
    (238, 244, 250),
    (250, 252, 255),
]
## Le caillou qui perce la congère : gris chaud, jamais noir.
PIERRE_NEIGE = (128, 126, 124)


def neige() -> Image.Image:
    """Congère : de larges plaques, des cristaux, deux cailloux qui percent."""
    rng = random.Random("neige")
    plaques = _bruit("neige-plaques", 16, 2)
    grain = _bruit("neige-grain", 4, 1)

    toile = Toile()
    for y in range(TAILLE):
        for x in range(TAILLE):
            # Le grain fin ne change pas de palier, il déplace la frontière : la
            # limite entre deux plaques devient dentelée au lieu d'être lisse.
            toile.poser(x, y, _ton(TONS_NEIGE, plaques[y][x] * 0.86 + grain[y][x] * 0.14))

    # Les congères : des crêtes que le vent a poussées, couchées dans le même
    # sens. La crête prend le jour, le versant sous le vent reste bleu — c'est
    # ce relief-là qui empêche une plaine enneigée d'être une feuille blanche.
    for _ in range(4):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        for i in range(rng.randint(12, 20)):
            toile.poser(x + i, y, TONS_NEIGE[4])
            toile.teinter(x + i, y - 1, TONS_NEIGE[3], 0.6)
            toile.teinter(x + i, y + 1, TONS_NEIGE[0], 0.7)
            toile.teinter(x + i, y + 2, TONS_NEIGE[0], 0.35)
            if rng.random() < 0.3:
                y += rng.choice((-1, 1))

    # Les cristaux : des pixels isolés qui accrochent la lumière. Le rendu leur
    # ajoute un reflet (metallic 0,06) — ils suffisent donc en petit nombre.
    for _ in range(rng.randint(6, 9)):
        toile.poser(rng.randrange(TAILLE), rng.randrange(TAILLE), (255, 255, 255))

    # Deux cailloux affleurants, et l'ombre bleue qu'ils creusent dans la neige.
    for _ in range(2):
        cx, cy = rng.randrange(TAILLE), rng.randrange(TAILLE)
        toile.disque(cx, cy, 1.6, PIERRE_NEIGE)
        toile.poser(cx - 1, cy - 1, _ecarte(PIERRE_NEIGE, 26))
        for dx, dy in ((1, 1), (2, 1), (1, 2)):
            toile.teinter(cx + dx, cy + dy, TONS_NEIGE[0], 0.75)
    return toile.resultat()


## Le marais : la vase, puis l'eau croupie, puis ce qui pousse dedans.
TONS_VASE = [
    (40, 38, 28),
    (50, 50, 35),
    (60, 62, 42),
    (70, 73, 50),
    (82, 85, 58),
]
## L'eau croupie est plus **sombre** que la vase qui l'entoure, jamais plus
## claire : c'est ce qui fait lire un trou d'eau plutôt qu'une flaque de peinture.
EAU_CROUPIE = (34, 50, 44)
EAU_FOND = (24, 38, 34)
EAU_CLAIRE = (86, 116, 96)
ALGUE = (104, 132, 58)
RACINE_BOIS = (66, 50, 32)
ROSEAU = (112, 136, 64)


def marais() -> Image.Image:
    """Vase sombre, flaques vertes, racines affleurantes, touffes de roseaux."""
    rng = random.Random("marais")
    fond = _bruit("marais-fond", 8, 2)
    mousse = _bruit("marais-mousse", 4, 1)

    toile = Toile()
    for y in range(TAILLE):
        for x in range(TAILLE):
            toile.poser(x, y, _ton(TONS_VASE, fond[y][x] * 0.75 + mousse[y][x] * 0.25))

    # Les flaques : deux trous d'eau larges, bord rongé, cerclés d'un liseré de
    # vase détrempée. Un seul reflet, au nord-ouest — d'où vient le soleil du
    # plateau — sinon l'eau devient une pastille brillante.
    for centre in ((9, 11), (23, 22)):
        cx = centre[0] + rng.randint(-2, 2)
        cy = centre[1] + rng.randint(-2, 2)
        rayon = rng.randint(6, 7)
        toile.disque(cx, cy, rayon + 1.2, _melange(TONS_VASE[0], (0, 0, 0), 0.35),
                     0.6, rng)
        toile.disque(cx, cy, rayon, EAU_CROUPIE, 0.55, rng)
        toile.disque(cx, cy, rayon - 2.5, EAU_FOND)
        # Le film d'algue flotte au bord de la flaque, pas en son milieu.
        for _ in range(rng.randint(5, 8)):
            angle = rng.random() * math.tau
            distance = rayon - rng.uniform(0.5, 2.0)
            toile.poser(cx + math.cos(angle) * distance,
                        cy + math.sin(angle) * distance, ALGUE)
        for i in range(3):
            toile.poser(cx - 3 + i, cy - rayon + 2 + i // 2, EAU_CLAIRE)

    # Les racines : elles courent, elles ne traversent pas. Le trait porte son
    # ombre d'un pixel, sans quoi il passe pour une fissure dans la vase.
    for _ in range(2):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        pas_x, pas_y = rng.choice(((1, 0), (1, 1), (1, -1)))
        for _i in range(rng.randint(7, 11)):
            toile.poser(x, y, RACINE_BOIS)
            toile.teinter(x, y + 1, (0, 0, 0), 0.35)
            x += pas_x
            y += pas_y
            if rng.random() < 0.3:
                y += rng.choice((-1, 1))

    # Les touffes : trois brins d'un même pied, comme les roseaux en volume que
    # [TacticsProps] plante sur la case — le sol doit leur donner leur base.
    for _ in range(3):
        cx, cy = rng.randrange(TAILLE), rng.randrange(TAILLE)
        for brin in range(3):
            hauteur = rng.randint(2, 4)
            for i in range(hauteur):
                toile.poser(cx + brin - 1, cy - i,
                            ROSEAU if i < hauteur - 1 else _ecarte(ROSEAU, 22))

    # Les bulles de méthane : trois pixels clairs, jamais deux au même endroit.
    for _ in range(3):
        toile.poser(rng.randrange(TAILLE), rng.randrange(TAILLE), EAU_CLAIRE)
    return toile.resultat()


## Le sable enrichi : rides, souffle du vent, grain. Le pack fournit la gamme.
SABLE_SOURCE = ("Outdoor", 6, 23)


def sable() -> Image.Image:
    """La tuile de sable du pack, ridée par le vent et regrainée.

    Elle n'est pas repeinte mais **retravaillée** : le remplissage de désert de
    SSCAP a la bonne gamme et le bon grain fin, il lui manquait le relief. On
    lui ajoute donc ce qu'un vent laisse — de longues rides, de larges plaques
    plus ou moins tassées — sans jamais introduire d'encre étrangère.
    """
    rng = random.Random("sable")
    source = _cellule(*SABLE_SOURCE)
    toile = Toile()
    toile.image.paste(source, (0, 0))
    toile.px = toile.image.load()

    # Le souffle : de larges plaques à peine plus claires ou plus sombres. C'est
    # ce qui casse l'aplat de loin, là où les rides ne se lisent plus.
    souffle = _bruit("sable-souffle", 16, 2)
    for y in range(TAILLE):
        for x in range(TAILLE):
            toile.poser(x, y, _ecarte(toile.lire(x, y), int((souffle[y][x] - 0.5) * 14)))

    # Les rides : de longs traits presque horizontaux, sombres dessous, clairs
    # dessus — une ride de sable est une petite dune, elle a deux faces.
    for _ in range(5):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        for i in range(rng.randint(12, 20)):
            toile.poser(x + i, y, _ecarte(toile.lire(x + i, y), 10))
            toile.poser(x + i, y + 1, _ecarte(toile.lire(x + i, y + 1), -12))
            if rng.random() < 0.25:
                y += rng.choice((-1, 1))

    # Le grain : un pixel sur dix poussé d'un cran. Sans lui, les rides flottent
    # sur une surface trop lisse pour elles.
    for _ in range(90):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        toile.poser(x, y, _ecarte(toile.lire(x, y), rng.choice((-9, -5, 5, 9))))
    return toile.resultat()
#endregion


#region La fosse
## La roche d'une fosse : quatre tons, du bord éclairé au fond noir.
TONS_FOSSE = [
    (62, 57, 52),
    (80, 74, 67),
    (98, 91, 83),
    (116, 108, 99),
]
## Le fond du trou — presque noir, mais pas noir : un noir pur fait un trou dans
## l'image, pas un trou dans le sol.
FOND_FOSSE = (12, 12, 14)

## Rayon du bord de roche, en pixels, avant que la paroi ne plonge.
RAYON_FOSSE = 13.0
## Profondeur du fondu vers le noir, en pixels.
PAROI_FOSSE = 5.0


def fosse() -> Image.Image:
    """Un gouffre : une margelle de roche, une paroi qui plonge, un fond noir.

    Le trou est **par case**, et c'est voulu : une fosse est infranchissable, le
    joueur doit la reconnaître à une case près. Un fond uniforme — ce que la
    tuile empruntée à `mountains v2` donnait — se confondait avec n'importe quel
    sol sombre.

    La margelle est irrégulière (le rayon est modulé par un bruit angulaire) et
    la roche du bord est cyclique : deux fosses voisines se raccordent par leur
    pierre, et l'œil lit un gouffre crevassé plutôt qu'une grille de trous.
    """
    rng = random.Random("fosse")
    pierre = _bruit("fosse-pierre", 8, 2)
    bosse = _bruit("fosse-bosse", 8, 1)

    toile = Toile()
    centre = (TAILLE - 1) / 2.0
    for y in range(TAILLE):
        for x in range(TAILLE):
            roche = _ton(TONS_FOSSE, pierre[y][x])
            dx, dy = x - centre, y - centre
            distance = math.hypot(dx, dy)
            # Le bord du trou ondule : un cercle parfait se lit comme un puits
            # maçonné, or personne n'a maçonné celui-ci.
            seuil = RAYON_FOSSE - 2.5 + (bosse[y][x] - 0.5) * 6.0
            if distance >= seuil:
                # La lèvre du trou est éclairée au nord-ouest : c'est ce liseré
                # clair qui donne son épaisseur à la margelle.
                if distance < seuil + 1.6 and dx + dy < 0:
                    roche = _melange(roche, (168, 158, 146), 0.45)
                toile.poser(x, y, roche)
                continue
            part = min(1.0, (seuil - distance) / PAROI_FOSSE)
            # Paliers francs : la paroi descend en gradins, comme une roche
            # cassée, plutôt qu'en dégradé continu.
            part = round(part * 3.0) / 3.0
            # Le sud du trou reste éclairé plus bas que le nord : c'est le seul
            # indice qui dit « ça descend » sur une image vue de dessus.
            if dx + dy > 0:
                part = max(0.0, part - 0.2)
            toile.poser(x, y, _melange(roche, FOND_FOSSE, min(1.0, part * 1.15)))

    # Les crevasses : elles partent du bord et mordent la margelle.
    for _ in range(5):
        angle = rng.random() * math.tau
        x = centre + math.cos(angle) * (RAYON_FOSSE + 2)
        y = centre + math.sin(angle) * (RAYON_FOSSE + 2)
        for _pas in range(rng.randint(4, 7)):
            toile.teinter(x, y, (0, 0, 0), 0.45)
            x += math.cos(angle) * -1.0 + rng.uniform(-0.6, 0.6)
            y += math.sin(angle) * -1.0 + rng.uniform(-0.6, 0.6)

    # Quelques pierres restées en équilibre sur la margelle : elles donnent
    # l'épaisseur du bord, donc la profondeur du trou.
    for _ in range(6):
        angle = rng.random() * math.tau
        rayon = RAYON_FOSSE + rng.uniform(0.5, 4.0)
        cx = centre + math.cos(angle) * rayon
        cy = centre + math.sin(angle) * rayon
        toile.disque(cx, cy, rng.choice((1.0, 1.5)), TONS_FOSSE[3])
        toile.poser(cx + 1, cy + 1, TONS_FOSSE[0])
    return toile.resultat()
#endregion


#region Les ouvrages
## La pierre taillée des ouvrages : joint, corps, chanfrein éclairé, ombre.
##
## Une seule gamme pour le mur, la porte, la tour et la ruine : ce sont les
## mêmes pierres, posées par les mêmes gens. Ce qui les distingue est leur
## appareillage, pas leur couleur — c'est ce qui fait tenir un rempart et sa
## porte sur la même image.
JOINT = (58, 56, 53)
PIERRE = [
    (98, 95, 90),
    (112, 109, 103),
    (126, 122, 116),
    (140, 136, 129),
]
CHANFREIN = (162, 158, 150)
OMBRE_PIERRE = (74, 71, 67)
MOUSSE = (86, 108, 58)
TERRE_RUINE = (72, 64, 50)
FER = (66, 62, 58)


def _moellon(toile: Toile, grain: list[list[float]], x0: int, y0: int,
             largeur: int, hauteur: int, decalage: int = 0) -> None:
    """Un bloc taillé : corps grainé, chanfrein au nord-ouest, ombre au sud-est.

    Le grain vient d'un bruit cyclique lu **aux coordonnées de la tuile**, pas
    du bloc : deux blocs voisins n'ont donc pas la même moucheture, et personne
    n'a eu à tirer un aléa par bloc pour ça.
    """
    ton = decalage
    for dy in range(hauteur):
        for dx in range(largeur):
            x, y = x0 + dx, y0 + dy
            index = min(len(PIERRE) - 1,
                        max(0, int(grain[y % TAILLE][x % TAILLE] * len(PIERRE)) + ton))
            couleur = PIERRE[index]
            if dx == 0 or dy == 0:
                couleur = JOINT
            elif dx == 1 or dy == 1:
                couleur = _melange(couleur, CHANFREIN, 0.40)
            elif dx == largeur - 1 or dy == hauteur - 1:
                couleur = _melange(couleur, OMBRE_PIERRE, 0.45)
            toile.poser(x, y, couleur)


def mur() -> Image.Image:
    """Le dessus d'un rempart : trois assises de blocs, joints décalés.

    Vu de la caméra tactique, un mur est d'abord un **chemin de ronde** : de
    longs blocs posés dans le sens de l'ouvrage, larges d'une assise, que le
    créneau de [TacticsProps] vient border. D'où les trois bandes horizontales
    et les joints croisés — un appareillage régulier, sans un caillou qui traîne :
    c'est ce qui le sépare du blocage de la ruine.
    """
    rng = random.Random("mur")
    grain = _bruit("mur-grain", 4, 2)
    toile = Toile(JOINT)

    assises = [(0, 11), (11, 10), (21, 11)]
    for index, (y0, hauteur) in enumerate(assises):
        x = -6 * index  # les joints ne s'alignent jamais d'une assise à l'autre
        while x < TAILLE:
            largeur = rng.choice((10, 12, 14))
            _moellon(toile, grain, x, y0, largeur, hauteur, rng.choice((-1, 0, 0, 1)))
            x += largeur

    # Les éclats : un rempart prend des coups, et un bloc ébréché dit son âge.
    for _ in range(5):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        toile.teinter(x, y, OMBRE_PIERRE, 0.7)
        toile.teinter(x + 1, y, OMBRE_PIERRE, 0.4)
    return toile.resultat()


def porte() -> Image.Image:
    """Le seuil d'une porte : un dallage, sa rainure de herse, ses ornières.

    Le seuil se lit dans un seul sens — nord-sud, celui du passage — parce que
    c'est ce qu'une porte impose : on la franchit, on ne s'y promène pas. Les
    piles de [TacticsProps] s'orientent, elles, sur le rempart qui la porte ;
    les deux ne se contredisent pas, l'une est le sol, l'autre l'ouvrage.
    """
    rng = random.Random("porte")
    grain = _bruit("porte-grain", 4, 2)
    toile = Toile(JOINT)

    # Le dallage : quatre grandes dalles de seuil, et rien d'autre. Un seuil se
    # taille dans les plus grosses pierres qu'on ait — c'est ce qui le sépare du
    # petit appareil d'un chemin de ronde.
    for y0 in (0, 16):
        for x0 in (0, 16):
            _moellon(toile, grain, x0 + (8 if y0 else 0), y0, 16, 16,
                     rng.choice((-1, 0, 0)))

    # Les ornières : deux bandes usées jusqu'au clair, dans le sens du passage.
    for cx in (9, 20):
        for y in range(TAILLE):
            for dx in range(4):
                toile.teinter(cx + dx, y, CHANFREIN,
                              0.42 if 0 < dx < 3 else 0.20)

    # La rainure de herse : la fente où la grille descend, en travers du seuil.
    for x in range(TAILLE):
        toile.teinter(x, 13, (0, 0, 0), 0.25)
        toile.poser(x, 14, _melange(JOINT, (0, 0, 0), 0.55))
        toile.poser(x, 15, _melange(JOINT, (0, 0, 0), 0.70))
        toile.poser(x, 16, _melange(JOINT, (0, 0, 0), 0.35))
        toile.teinter(x, 17, CHANFREIN, 0.20)
    # Les barreaux, vus de dessus : la herse est relevée, il n'en reste que la
    # section des fers dans leur rainure — deux pixels de fer, pas une grille.
    for x in range(2, TAILLE, 5):
        toile.poser(x, 14, _ecarte(FER, 24))
        toile.poser(x, 15, FER)
        toile.poser(x + 1, 15, _ecarte(FER, -10))
        toile.poser(x, 16, _ecarte(FER, -14))

    # Les pas : ce qu'un siècle de passage laisse sur une pierre de seuil. Ils
    # se concentrent dans les ornières, là où l'on marche vraiment.
    for _ in range(20):
        x = rng.choice((9, 20)) + rng.randint(0, 3)
        toile.teinter(x, rng.randrange(TAILLE), OMBRE_PIERRE, 0.25)
    return toile.resultat()


## Rayon de l'assise circulaire d'une tour, en pixels.
RAYON_TOUR = 13.0
## Épaisseur de son mur, en pixels.
MUR_TOUR = 4.0
## Nombre de claveaux du parement — assez pour lire un cercle appareillé.
CLAVEAUX = 16


def tour() -> Image.Image:
    """L'assise d'une tour, vue de dessus : un anneau de claveaux sur un dallage.

    Le fût et le toit sont posés en volume par [TacticsProps] et masquent le
    centre de la case ; ce qui se voit du sol, c'est **l'empreinte** — la
    couronne de pierres qui porte le fût, et le dallage de son pied. Le dedans
    de l'anneau reste sombre : c'est l'intérieur de la tour, pas une cour.
    """
    rng = random.Random("tour")
    grain = _bruit("tour-grain", 4, 2)
    toile = Toile(JOINT)

    # Le dallage du pied : de petites dalles, hors de la couronne.
    for y0 in range(0, TAILLE, 8):
        for x0 in range(0, TAILLE, 8):
            _moellon(toile, grain, x0 + (4 if (y0 // 8) % 2 else 0), y0, 8, 8, -1)

    centre = (TAILLE - 1) / 2.0
    for y in range(TAILLE):
        for x in range(TAILLE):
            dx, dy = x - centre, y - centre
            distance = math.hypot(dx, dy)
            if distance > RAYON_TOUR:
                continue
            if distance > RAYON_TOUR - MUR_TOUR:
                # Le parement : un claveau tous les 2π/16, séparé d'un joint.
                angle = math.atan2(dy, dx)
                secteur = (angle + math.pi) / math.tau * CLAVEAUX
                bord_joint = abs(secteur - round(secteur)) < 0.10
                index = 2 + int(grain[y][x] * 2)
                couleur = JOINT if bord_joint else PIERRE[min(index, len(PIERRE) - 1)]
                # La couronne prend le jour au nord-ouest et l'ombre au sud-est,
                # comme tout le reste du plateau.
                if not bord_joint:
                    part = (-dx - dy) / (2 * RAYON_TOUR)
                    couleur = _melange(couleur, CHANFREIN if part > 0 else OMBRE_PIERRE,
                                       min(0.5, abs(part) * 1.6))
                toile.poser(x, y, couleur)
            elif distance > RAYON_TOUR - MUR_TOUR - 1.0:
                toile.poser(x, y, _melange(JOINT, (0, 0, 0), 0.35))
            else:
                # Le dedans : un sol de pierre sombre, plus clair au centre où le
                # jour tombe par la trappe.
                creux = 1.0 - distance / (RAYON_TOUR - MUR_TOUR)
                toile.poser(x, y, _melange(_melange(PIERRE[0], (0, 0, 0), 0.28),
                                           PIERRE[2], creux * 0.55))

    # Un peu de mousse au pied du parement, côté ombre : une tour est humide.
    for _ in range(10):
        angle = rng.uniform(0.2, 2.4)
        rayon = RAYON_TOUR + rng.uniform(0.0, 2.5)
        toile.teinter(centre + math.cos(angle) * rayon,
                      centre + math.sin(angle) * rayon, MOUSSE, 0.55)
    return toile.resultat()


def ruines() -> Image.Image:
    """Un dallage crevé : des dalles cassées, de la terre et de l'herbe dessous.

    C'est le même appareillage que le fortin — c'était le même bâtiment — mais
    une dalle sur trois manque, et ce qui pousse dessous a repris sa place. Les
    colonnes brisées sont posées en volume par [TacticsProps] : le sol ne dessine
    que ce qui reste sous les pieds.
    """
    rng = random.Random("ruines")
    grain = _bruit("ruines-grain", 4, 2)
    herbe = _bruit("ruines-herbe", 8, 2)

    # Le dessous : de la terre sèche, reprise par l'herbe là où elle a pu.
    toile = Toile()
    for y in range(TAILLE):
        for x in range(TAILLE):
            couleur = _melange(TERRE_RUINE, MOUSSE, 0.65 if herbe[y][x] > 0.62 else 0.0)
            toile.poser(x, y, _ecarte(couleur, int((grain[y][x] - 0.5) * 20)))

    # Les dalles restantes : trois assises à joints croisés, dont un tiers a
    # disparu. Elles sont posées en dernier sur la terre, comme elles l'ont été
    # sur le chantier.
    dalles: list[tuple[int, int, int, int]] = []
    for index, (y0, hauteur) in enumerate(((0, 11), (11, 10), (21, 11))):
        x = -5 * index
        while x < TAILLE:
            largeur = rng.choice((12, 16))
            dalles.append((x, y0, largeur, hauteur))
            x += largeur
    for x0, y0, largeur, hauteur in dalles:
        if rng.random() < 0.34:
            continue
        _moellon(toile, grain, x0, y0, largeur, hauteur, rng.choice((-1, 0, 1)))

    # Les cassures : une dalle de ruine n'a pas de bord droit. Le trait mord la
    # pierre et s'arrête sur la terre — une fêlure ne traverse pas un trou.
    for _ in range(5):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        pas = rng.choice(((1, 0), (0, 1)))
        for _i in range(rng.randint(4, 8)):
            if toile.lire(x, y) not in PIERRE:
                break
            toile.poser(x, y, _melange(JOINT, (0, 0, 0), 0.35))
            x += pas[0]
            y += pas[1]
            if rng.random() < 0.35:
                x += rng.choice((-1, 1))

    # Les gravats : ce qui est tombé des dalles manquantes. Deux pixels et leur
    # ombre — au-delà, ce n'est plus un débris, c'est un caillou.
    for _ in range(rng.randint(12, 16)):
        x, y = rng.randrange(TAILLE), rng.randrange(TAILLE)
        if toile.lire(x, y) in PIERRE:
            continue
        toile.poser(x, y, PIERRE[3])
        toile.poser(x + 1, y, PIERRE[1])
        toile.poser(x, y + 1, _melange(PIERRE[0], (0, 0, 0), 0.45))

    # L'herbe des joints : trois brins, jamais au milieu d'une dalle intacte.
    for _ in range(rng.randint(6, 9)):
        cx, cy = rng.randrange(TAILLE), rng.randrange(TAILLE)
        if toile.lire(cx, cy) in PIERRE:
            continue
        for i in range(rng.randint(2, 4)):
            toile.poser(cx + i // 2, cy - i, _ecarte(MOUSSE, 12 * i))
    return toile.resultat()
#endregion


# (nom de fichier, fabrique, ce que la tuile montre)
MANIFESTE: list[tuple[str, object, str]] = [
    ("terrain_outdoor_sand",  sable,  "sable ridé par le vent (SSCAP retravaillé)"),
    ("terrain_outdoor_snow",  neige,  "congère, cristaux, cailloux affleurants"),
    ("terrain_outdoor_swamp", marais, "vase, flaques d'eau croupie, racines"),
    ("terrain_mountain_pit",  fosse,  "gouffre : margelle de roche, fond noir"),
    ("terrain_outdoor_ruins", ruines, "dallage crevé, gravats, herbe des joints"),
    ("terrain_outdoor_tower", tour,   "assise circulaire d'une tour, vue de dessus"),
    ("terrain_outdoor_gate",  porte,  "seuil de porte : rainure de herse, ornières"),
    ("terrain_outdoor_wall",  mur,    "chemin de ronde : trois assises appareillées"),
]


def ecrire() -> int:
    SOLS.mkdir(parents=True, exist_ok=True)
    for nom, fabrique, quoi in MANIFESTE:
        fabrique().save(SOLS / f"{nom}.png")
        print(f"  {nom:<24} — {quoi}")
    print(f"\n{len(MANIFESTE)} sols écrits dans {SOLS.relative_to(RACINE)}")
    print("Ensuite : varier-tuiles.py (variantes) puis bords-synthese.py (bords)")
    return 0


def apercu() -> int:
    """Les huit sols répétés 3 × 3 : la couture se voit ou ne se voit pas."""
    bloc = TAILLE * 3
    colonnes = 4
    lignes = (len(MANIFESTE) + colonnes - 1) // colonnes
    planche = Image.new("RGBA", (colonnes * (bloc + 4), lignes * (bloc + 4)),
                        (24, 22, 34, 255))
    for index, (nom, fabrique, _quoi) in enumerate(MANIFESTE):
        tuile = fabrique()
        x0 = (index % colonnes) * (bloc + 4)
        y0 = (index // colonnes) * (bloc + 4)
        for j in range(3):
            for i in range(3):
                planche.paste(tuile, (x0 + i * TAILLE, y0 + j * TAILLE))
        print(f"  {nom}")
    cible = "/tmp/sols-restants.png"
    planche.resize((planche.width * 4, planche.height * 4), Image.NEAREST).save(cible)
    print(f"\nAperçu : {cible}")
    return 0


if __name__ == "__main__":
    parseur = argparse.ArgumentParser(description=__doc__)
    parseur.add_argument("--apercu", action="store_true",
                         help="dépose une planche de contrôle dans /tmp, sans rien écrire")
    args = parseur.parse_args()
    raise SystemExit(apercu() if args.apercu else ecrire())
