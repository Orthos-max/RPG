# Acheter un pack de figurines — liste de contrôle

Écrit pour Ciel Emblem, avec ses contraintes réelles : cellule de 48 × 48 pour les pions (128 × 128 pour les portraits), deux
poses, caméra orthographique inclinée à −52°, figurine entre 53 et 197 px à
l'écran. Le format complet est dans
[`assets/textures/actor/README.md`](../assets/textures/actor/README.md).

L'ordre compte : les quatre premiers points sont **éliminatoires**. Un pack qui
les rate ne se rattrape pas à la retouche, quelle que soit sa beauté.

---

## Les quatre éliminatoires

### 1. Licence : modification + usage commercial + redistribution

Trois autorisations distinctes, à vérifier séparément — un pack peut permettre la
modification et interdire la revente dans un produit fini.

- **Modification / œuvres dérivées.** Sans elle, tout le plan (retoucher à la
  main) tombe.
- **Usage commercial.** À prendre même si le jeu est gratuit aujourd'hui : une
  page itch avec un bouton « soutenir », c'est déjà commercial chez certains
  vendeurs. Rétro-acheter une licence plus tard coûte plus cher, quand c'est
  encore possible.
- **Redistribution dans un exécutable.** Un build embarque les `.png`. La plupart
  des licences de jeu l'autorisent explicitement, mais certaines licences
  « usage personnel » ne couvrent que l'affichage.

À fuir : **CC-BY-SA** et les licences virales, qui contamineraient les planches
dérivées. **CC0** est le plus confortable, **CC-BY** très bien si l'attribution
est acceptable.

Garder la facture **et le texte de la licence** archivés avec le projet. Dans
trois ans, « je crois que c'était libre » ne vaudra rien.

### 2. Résolution native — 48 par pose, 128 pour un portrait

Pas 32 agrandi en 48, ni 64 réduit. C'est exactement le piège dans lequel les planches
actuelles de Ciel Emblem étaient tombées : 128 × 256 sur le disque, 32 × 32 de
contenu réel. Un vendeur sérieux annonce la taille de cellule ; sinon, demander une
image d'exemple et vérifier qu'une réduction ×4 puis un agrandissement ×4 ne
redonnent **pas** l'original à l'identique.

### 3. Vraies unités montées

C'est le besoin le plus urgent du projet — Sully (cavalerie) et Cordelia (pégase)
portent aujourd'hui la figurine d'un autre. Or **la plupart des packs n'ont pas
de montures**, ou seulement des chevaux vus de profil, inutilisables pour des
poses de face et de dos.

Vérifier avant tout le reste : cheval **de face et de dos**, et une créature
ailée si le pégase compte. Un pack sans montures ne résout pas le problème pour
lequel on achète.

### 4. Pixel art véritable, sans anticrénelage

Beaucoup de packs vendus comme « pixel art » sont des illustrations réduites,
avec des bords adoucis et des centaines de couleurs. Ils résistent à la
quantification sur palette, bavent au filtre au plus proche voisin, et ne se
retouchent pas au pixel.

Ça ne se juge pas à l'œil sur une page de vente, ça se mesure :

```
python3 art/verifier-echantillon.py echantillon.png
```

Du vrai pixel art tient en quelques dizaines de couleurs et n'a quasiment pas de
pixels à alpha partiel. Le casting actuel de Ciel Emblem en compte **25 pour
huit planches**, et 0 % d'alpha partiel.

---

## Format technique

- **PNG à alpha réel**, pas un fond magenta ou blanc à détourer.
- **Grille régulière**, cellules de taille constante, sans marge variable. Un atlas
  aux espacements irréguliers se redécoupe à la main, planche par planche.
- **Ligne de pieds constante** sur tout le pack. C'est le défaut le plus fréquent
  et le plus coûteux : si chaque personnage pose ses pieds à une hauteur
  différente, les unités flottent ou s'enfoncent les unes par rapport aux autres,
  et il faut recaler chaque planche. Ciel Emblem attend le sol à 94 % de la hauteur de cellule.
- **Poses de face et de dos** au minimum. Quatre directions, c'est mieux : le
  code retourne déjà l'image horizontalement (`flip_h`), donc gauche/droite
  servira si le besoin vient.
- **Vue de face, pas isométrique.** Le pion est en billboard intégral : il se
  tourne toujours vers la caméra. Une élévation de face classique — le format le
  plus courant — est donc exactement ce qu'il faut. Pas besoin de chercher de
  l'art dessiné en isométrique, et c'est tant mieux, ça élargit le choix.
- **Fichiers sources fournis** (`.aseprite`, `.ase`, `.pyxel`). Décisif pour un
  travail de retouche : on récupère les calques, la palette, les séparations
  corps/vêtement/arme. Sans eux, on repeint par-dessus un aplat. Ça vaut
  largement un supplément de prix.

---

## Cohérence artistique

- **Proportions ~2,3 têtes.** Le canon chibi du casting actuel. Un pack aux
  proportions héroïques (4 têtes et plus) ne se fondra pas, même recoloré — et
  passer tout le casting à ces proportions est une décision d'identité, pas une
  retouche.
- **Source de lumière unique et constante** dans tout le pack. Deux personnages
  éclairés de côtés opposés ne se corrigent qu'en repeignant les ombres.
- **Palette quantifiable** vers `palette-figurines.gpl` sans s'effondrer. Un pack
  très désaturé ou très pastel s'accordera mal à « Velmar : nuit et or ».
- **Silhouette lisible à 53 px.** C'est la taille de la figurine au dézoom
  maximum. Réduire une image d'exemple à cette taille et vérifier qu'on distingue
  encore la classe : si tout devient une tache, le détail du pack est décoratif.
- **Contour ou pas** — les deux marchent, mais il faut choisir une fois. Un
  casting mi-cerné mi-non-cerné se voit immédiatement.

---

## Couverture du casting

Les besoins de Ciel Emblem, à confronter au contenu du pack :

| Besoin | Classes |
|---|---|
| De base | Lord, Cavalier, Cleric, Pegasus Knight, Archer, Great Knight |
| Promues | Great Lord, Paladin, Sniper, Falcon Knight… (aucune planche à ce jour) |
| Adversaires | morts-vivants — trois squelettes existent |

- **Compter les personnages réellement distincts**, pas les fichiers. Beaucoup de
  packs gonflent leur décompte avec des variantes de palette. Une recoloration ne
  fait pas une classe.
- **Extensions dans le même style.** Un pack unique laisse coincé dès qu'une
  classe s'ajoute. Un vendeur qui publie des extensions régulières vaut mieux
  qu'un pack isolé plus fourni.
- **Adversaires compris ?** Un pack de héros seul laisse la moitié du plateau à
  faire.

---

## Avant de payer

**Le seul vrai test : faire passer un sprite dans la chaîne.** Presque tous les
vendeurs offrent un échantillon gratuit ou une image d'exemple en pleine
résolution. Prendre **une** figurine, la conformer au format, la mettre en jeu, la
regarder aux zooms réels. Une heure qui évite d'acheter un pack qui ne tient pas.

C'est aussi à ce moment qu'on découvre les défauts qui ne se voient pas sur la
page de vente : anticrénelage, ligne de pieds bancale, palette impossible.

Reste à peser le prix **rapporté aux planches réellement utilisables** — pas au
nombre de fichiers. Un pack à 30 € couvrant six classes sur six vaut mieux qu'un
pack à 12 € qui en couvre deux.

---

## Où chercher — et l'état du marché

**Passer le pion en 48 a débloqué l'offre.** L'écrasante majorité du pixel art
tactique se vend en 16, 32 ou 48 px : le 48 est la taille conventionnelle du
sprite de combat, donc la mieux fournie. Le 128, lui, n'existe presque qu'en
personnage de plateforme, en *battler* de profil façon RPG Maker, ou justement
en **portrait** — ce qui tombe bien, puisque c'est désormais le seul usage qu'on
lui réserve.

Chercher donc séparément : **48** pour les pions, **128** pour les portraits,
**32** pour les icônes. Rien pour le terrain, il est procédural.

| Site | Pour quoi | Licence |
|---|---|---|
| **itch.io** | le plus gros catalogue, gros rayon gratuit et prix libre | variable **par créateur** — à lire à chaque fois |
| **CraftPix** | licence commerciale incluse d'office, rangé par genre, section gratuite | homogène, plus simple juridiquement |
| **OpenGameArt** | gratuit, champ de licence explicite | CC0 / CC-BY / GPL, qualité inégale |
| **Kenney** | tout en CC0, imbattable juridiquement | CC0 |
| **Humble Bundle** | lots d'assets périodiques, très bon rapport quantité/prix | à vérifier au cas par cas |
| **GameDev Market** | catalogue modéré et curé | à vérifier |
| **Unity Asset Store / Fab** | fourni, mais ⚠️ certaines licences ne couvrent que des projets Unity — vérifier avant d'acheter pour un projet Godot | à vérifier de près |

Sur itch.io, chercher par **tag** (`128x128`, `sprites`, `tactical-rpg`,
`pixel-art`) et filtrer par prix. Les termes « tactical RPG » seuls donnent
surtout du 32 px : élargir à *top-down*, *battler*, *HD pixel art*.

### L'origine ne juge rien, les mesures oui

Fait main ou assisté par IA : **ce n'est pas un critère**. Un pack dessiné à la
main peut être mou et anticrénelé ; un pack assisté par IA peut être net,
cohérent et parfaitement utilisable. Ce qui se voit en jeu, ce sont des
propriétés mesurables — et elles se mesurent, sur n'importe quelle image
d'exemple :

```
python3 art/verifier-echantillon.py echantillon.png
```

Le script dit si la résolution annoncée est réelle ou agrandie, compte les
couleurs, mesure la part de pixels à alpha partiel (le signe de bords adoucis),
et vérifie l'aplomb des pieds entre les deux rangées. C'est ce qui remplace
l'impression laissée par une page de vente.

Une réserve à connaître, sans qu'elle interdise quoi que ce soit : **le statut
juridique des sorties d'IA n'est pas tranché partout**. C'est un risque à
accepter en connaissance de cause, pas un défaut de l'image.

### Deux pistes examinées le 2026-08-10

**[DaddyDarko — 500+ RPG Themed Sprites](https://dadddydarko.itch.io/500-rpg-themed-asset-pack-2d-sprites)**
(~3 $). 200+ personnages en 128, licence commerciale avec retouche autorisée.
**Écarté sur les montures** — il n'y en a aucune, et c'est le besoin numéro un.
Le vendeur déclare des assets « partiellement générés par IA puis corrigés à la
main » : ça n'entre pas dans le verdict, mais ça vaut de passer un échantillon au
vérificateur avant d'acheter, l'anticrénelage étant fréquent sur ce profil.

**[traegis — 2D Character Sprite Pack 128x128](https://traegis.itch.io/pixel-art-2d-character-animations)**
(~5 $ CAD). Structurellement le meilleur candidat vu : **quatre directions**
(bas = visage, haut = dos), **un cheval avec animations montées**, **fichiers PSD
fournis**, et un système d'équipement en calques qui permet de tirer plusieurs
classes d'une base. **Mais** : un seul personnage de base, et un thème western /
ferme (chapeau de cow-boy, revolver, faux) au lieu de la fantasy.

Aucun des deux ne se prend tel quel — tous deux visaient le 128 pour le pion,
qui n'est plus la cible. Ils restent utiles comme calibrage de prix.

### Candidats en 48, examinés le 2026-08-10

**[Franuka — Tactical RPG Overworld Pack](https://franuka.itch.io/tactical-rpg-overworld-pack)**
(~15 $). Le meilleur candidat vu à ce jour :

- **48 × 48 disponible** (et aussi 16 et 32) — la cible exacte
- **quatre directions**, haut et bas donnant dos et face
- **64 types d'unités** sur 4 factions, plus deux variantes de couleur
- licence commerciale, retouche autorisée, revente interdite

Réserves : **Beast Riders mais ni cavalerie classique ni monture volante** —
c'est l'éliminatoire n°3 qui reste ouvert pour Sully et Cordelia. Pas de fichiers
sources, pas de portraits (objectif de financement non atteint). Style « mignon
et coloré », à confronter à « Velmar : nuit et or ».

### Candidats portraits en 128

- **[Magory — Fantasy Character Portraits](https://magory.itch.io/fantasy-portraits)**
  (~8 $) : plus de 2 000 portraits, plusieurs tailles dont 128, usage libre en
  projet gratuit ou commercial.
- **[FinchL — Fantasy RPG Portraits 128×128](https://finchl.itch.io/fantasy-rpg-portraits-pack-128x128)** :
  169 portraits, éventail d'espèces large (humains, elfes, nains, morts-vivants,
  nécromanciens…).
- **[PIXEL_1992 — RPG Mega Pixel Art Bundle](https://itch.io/s/167002/-rpg-mega-pixel-art-bundle-95k-fantasy-assets)** :
  lot très fourni, dont 2 500+ visages en 128.

Rappel : rien n'affiche encore un portrait dans le jeu. Acheter d'avance est
possible, s'en servir demandera d'écrire l'écran de dialogue.

### Si rien ne convient

- **Commander à un pixel artist.** À huit planches de deux poses, sans animation,
  une commande devient compétitive face au temps passé — et donne exactement le
  casting voulu, aux bonnes proportions, dans la bonne palette.
- **Rendre depuis la 3D** — voir [`METHODES.md`](METHODES.md). C'est la seule
  route qui règle les montures sans dépendre du catalogue.

---

## Ce qu'on ne prend pas, pour l'instant

Les colonnes d'animation. Décision du 2026-08-10 : une colonne, deux images. D'un
pack animé on n'extrait que les deux poses de repos — mais **on garde les images
de marche de côté**, elles sont déjà payées et serviront le jour où l'animation
viendra.

Ce n'est pas un critère *contre* un pack animé : à prix égal, il laisse la porte
ouverte.
