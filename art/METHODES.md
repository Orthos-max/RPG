# Comment obtenir de belles figurines

Cinq routes possibles, comparées sur les contraintes réelles de Ciel Emblem et
non dans l'absolu. Le vocabulaire est dans [`LEXIQUE.md`](LEXIQUE.md), le format
dans [`assets/textures/actor/README.md`](../assets/textures/actor/README.md).

## Ce qui décide

Le besoin n'est pas « une belle image », c'est **huit planches qui ont l'air de
venir du même monde**. Une figurine superbe mais hors casting dégrade l'ensemble.
Les critères, par ordre de poids :

1. **Cohérence** entre les huit — proportions, lumière, palette, niveau de détail
2. **Deux poses exactes** par personnage, visage et dos, alignées au pixel
3. **Les montures** — Sully à cheval, Cordelia sur son pégase. Le besoin le plus
   dur, celui qui élimine la plupart des packs
4. **Le temps que ça te prend**, pas seulement l'argent
5. **L'extensibilité** — les classes promues viendront, l'animation peut-être

---

## 1. Rendu 3D → sprite

Modéliser (ou acheter) un personnage chibi en 3D, le poser, le rendre en
orthographique, réduire à 128 et quantifier sur la palette.

**Ce que ça règle, et que rien d'autre ne règle aussi bien :**

- **La cohérence est structurelle**, pas une discipline à tenir. Même modèle,
  même lumière, même caméra : les huit figurines *ne peuvent pas* diverger.
- **Le dos est gratuit** — c'est la même scène, la caméra tourne de 180°. Plus de
  risque de désalignement entre les deux poses.
- **Les montures deviennent faciles** : un cheval modélisé, le personnage posé
  dessus, et la même chaîne produit la planche. C'est le point qui bloque toutes
  les autres méthodes.
- **Les variantes coûtent presque rien** : un seul gabarit de corps, on change
  l'arme, la cape, la couleur. Six classes depuis une base.
- **L'animation, si elle vient un jour**, ce sont juste des rendus en plus.
- **Tu peux régler l'angle empiriquement.** La caméra du jeu est orthographique
  à −52° ; le pion est en billboard intégral, donc une élévation de face
  fonctionne — c'est ce que fait le casting actuel. Avec un pipeline 3D tu peux
  rendre à 0°, 20°, 52° et comparer en jeu en quelques minutes, au lieu de parier.
  Aucune autre méthode ne permet ce réglage à ce prix.

**Ce que ça coûte :** apprendre Blender (gratuit), ou acheter un modèle chibi de
base. Le premier personnage est long, les sept suivants sont rapides — c'est
l'inverse du dessin à la main.

**Outillage :** Blender seul suffit ; des extensions automatisent le rendu en
planches (*Get Sheet Done*, *Pre Render Creator*, *True Pixel Art Generator*).

**Verdict : la meilleure route si tu acceptes une mise en place.** C'est celle
qui répond aux critères 1, 2, 3 et 5 d'un coup.

---

## 2. Commander à un pixel artist

**Ce que ça donne :** exactement ton casting, aux bonnes proportions, dans ta
palette, cohérent par construction puisque c'est une seule main.

**Le point qu'on sous-estime : ton brief est déjà écrit.** Un artiste demande
normalement des semaines d'allers-retours pour cadrer le style. Toi tu as déjà
`gabarit-reperes.png`, `palette-figurines.gpl`, `planche-contact.png`, le format
documenté et les repères mesurés. C'est ce qui fait chuter le prix et le risque —
la moitié du travail d'une commande, c'est la spécification.

**Ce que ça coûte :** de l'argent, et l'attente. Huit planches de deux poses sans
animation reste une commande modeste.

**Où :** artistes présents sur itch.io, r/PixelArt, ArtStation, serveurs Discord
de pixel art.

**Verdict : le meilleur rapport beauté / ton temps.** À privilégier si le budget
existe.

---

## 3. Acheter un pack et retoucher

Traité en détail dans [`ACHAT-PACK.md`](ACHAT-PACK.md).

**Verdict : le moins cher, mais l'offre en 128 est mince** et les montures sont
rares. Vaut d'être tenté — un pack qui convient réglerait tout d'un coup — mais
ne pas compter dessus.

---

## 4. Génération par IA, puis retouche

Tu as ComfyUI, stable-diffusion-webui et KohyaSS installés. Ce qu'il faut savoir
avant de t'y lancer :

**Ce que l'IA fait mal :** un casting cohérent à partir de rien. Deux
générations successives ne donnent pas deux personnages du même monde, et encore
moins le visage *et* le dos du même personnage. C'est exactement le critère n°1.

**Ce que l'IA fait bien :** des **variations sur une base existante**. Une fois
que tu as un personnage juste — rendu en 3D, commandé, ou dessiné — décliner
l'armure, la cape, la couleur, c'est là qu'elle est utile et rapide.

**La sortie brute n'est jamais du pixel art :** bords adoucis, milliers de
couleurs. Il faut toujours réduire au plus proche voisin sur la grille, quantifier
sur la palette, et repasser à la main. `verifier-echantillon.py` te le dira sans
appel.

**Verdict : pas une méthode à elle seule, une étape dans une autre.** À combiner
avec la 1 ou la 3, jamais en point de départ du casting.

---

## 5. Tout dessiner à la main

**Ce que ça donne :** le meilleur résultat possible dans l'absolu, et un contrôle
total.

**Ce que ça coûte :** seize images de 128 × 128. Pour qui n'est pas déjà pixel
artist, c'est un apprentissage, pas une tâche — et les premières planches seront
à refaire une fois la main faite.

**Verdict : la route de l'artisan.** Excellente si tu *veux* apprendre le pixel
art. Coûteuse si tu veux surtout que le jeu avance.

---

## Ce que je recommande

Elles se combinent, et c'est la vraie réponse :

1. **Obtenir une base juste**, par la 3D ou la commande — un personnage, deux
   poses, aux bonnes proportions et dans la palette.
2. **Décliner le casting** depuis cette base : rendus supplémentaires si 3D,
   retouches manuelles ou assistées par IA sinon.
3. **Passer chaque planche par la même moulinette mécanique** — grille, ligne de
   pieds, quantification, assemblage.

C'est cette troisième étape que je peux écrire quel que soit ton choix : la
source change, le conformateur non. Dépose une image et on branche la chaîne.

## Comment juger sans se mentir

Quelle que soit la méthode, deux vérifications avant d'adopter une planche :

```
python3 art/verifier-echantillon.py ta-planche.png   # résolution, couleurs, aplomb
python3 art/atelier.py                               # planche de contact à jour
```

Puis la regarder **dans la planche de contact, à côté des sept autres**. Une
figurine se juge en groupe, jamais seule.
