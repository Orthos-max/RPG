# Figurines de Ciel Emblem — liste de courses

> Le système est en place et **attend ses planches**. Rien à recâbler : dépose un
> `.png` au bon endroit, pointe une fiche dessus, et l'unité le porte — en
> bataille comme dans l'éditeur de personnages, qui liste tout seul ce qu'il
> trouve dans ces dossiers.

C'est le pendant de [`assets/audio/README.md`](../../audio/README.md), et pour la
même raison : le code est prêt, l'art manque.

---

## Le problème, en une phrase

**Quatre planches de héros pour six classes.** Deux paires se partagent donc la
même figurine :

| Classe | Planche portée | Ressemble à |
|---|---|---|
| Lord (Chrom) | `chr_pawn_knight.png` | — |
| **Cavalier (Sully)** | `chr_pawn_knight.png` | **au Lord** |
| Cleric (Lissa) | `chr_pawn_mage.png` | — |
| **Pegasus Knight (Cordelia)** | `chr_pawn_mage.png` | **à la Cleric** |
| Archer (Virion) | `chr_pawn_archer.png` | — |
| Great Knight (Frederick) | `chr_pawn_chemist.png` | — |

Recruter Sully donne donc un second Chrom sur le plateau, et Cordelia une
seconde Lissa. Ce n'est pas un bug de code — le `sprite` de chaque fiche voyage
correctement jusqu'au pion depuis le 2026-08-07. Il n'y a simplement pas d'image
à leur donner.

---

## Format attendu

| | |
|---|---|
| Format | **`.png`**, fond transparent |
| Taille | **128 × 256** — une colonne, deux rangées de 128 × 128 |
| Rangée du haut | l'unité **de face** (vue quand elle vient vers la caméra) |
| Rangée du bas | l'unité **de dos** |
| Style | pixel art, palette réduite, pieds posés sur la ligne `y = 120` |

> ⚠️ **La rangée du haut est le visage, pas le dos.** Ce README a documenté
> l'inverse jusqu'au 2026-08-10, alors que les planches livrées, elles, avaient
> le visage en haut — c'est le README qui avait tort, pas l'art. La raison est
> dans `movement.gd` : `look_at_direction()` ajoute un `PI` à l'angle, donc
> `basis.z` suit le sens de la marche au lieu de l'opposer. Un scalaire négatif
> signifie « vient vers nous » et sélectionne la frame 0, celle du haut.
> Vérifié sur les quatre directions de la grille : ±0,435 pour un seuil de 0,306.
> Dessiner en suivant l'ancienne consigne donnait des unités qui montrent leur
> dos en avançant vers toi.

### Le casting actuel ne tient pas ses 128

Les planches font bien 128 × 256, mais leur **contenu** n'est qu'un
agrandissement ×4 au plus proche voisin d'un dessin de 32 × 32 : réduites en
32 × 64 puis ré-agrandies, elles reviennent **à l'octet près**, toutes les huit.
Les trois quarts du fichier ne portent aucune information.

Le format reste donc 128 × 256, mais **128 est la grille à remplir pour de
bon** — une planche neuve dessinée à cette taille porte seize fois plus de
détail que le casting actuel. Les huit planches d'origine sont à retravailler,
pas seulement les quatre manquantes : une figurine réellement dessinée en 128
posée à côté d'un squelette en 32 se verra immédiatement.

Le format a été arrêté le 2026-08-10 sur les chiffres suivants. La figurine
mesure 1,28 unité de monde (`pixel_size` 0.01 × 128 px), la caméra est
orthographique et cadre entre 7 et 26 unités de haut. Rapport entre un pixel
d'art et un pixel d'écran :

| Cadrage | Figurine à l'écran (1080p) | Art 128 |
|---|---|---|
| Zoom max (7) | 197 px | 1,54× |
| Ouverture serrée (9) | 154 px | 1,20× |
| Repos (10) | 138 px | 1,08× |
| Ouverture large (18) | 77 px | 0,60× — réduite |
| Dézoom max (26) | 53 px | 0,42× — réduite |

En 1080p le 128 passe donc sous le 1:1 à cadrage large : le détail peint y est
moyenné par le mipmap. Ce n'est **pas** un défaut de rendu — une planche 128 n'y
est jamais pire qu'une 64, seulement moins exploitée — c'est un coût de
production à assumer sciemment. En 1440p le rapport tient à 0,80×, en 4K à
1,20× : le 128 s'y justifie pleinement.

Côté machine, la question ne se pose pas : 60 planches en 128 × 256 sans perte,
mipmaps comprises, pèsent **10 Mo de VRAM**. La puissance du PC du joueur
n'entre pas dans l'arbitrage.

Le pion est un `Sprite3D` en `billboard`, `vframes = 2` : il choisit dos ou face
selon l'orientation par rapport à la caméra. Une planche mal découpée se voit
tout de suite — l'unité change de moitié en tournant.

### Une seule colonne — décidé le 2026-08-10

**Pas d'animation pour l'instant.** Une planche = une colonne, deux rangées, deux
images en tout. `ANIMATION_FRAMES` reste à 1 et `hframes` à son défaut.

Ça compte surtout au moment de **récupérer un pack acheté**. Les packs tactiques
livrent presque toujours quatre directions × plusieurs images de marche : il ne
faut en extraire que **deux images fixes** — la pose de repos vers le bas (le
visage) au-dessus, la pose de repos vers le haut (le dos) en dessous. Tout le
reste est à laisser de côté tant que l'animation n'est pas décidée.

Une planche qui garderait ses colonnes de marche ne provoquerait aucune erreur :
`hframes` valant 1, Godot prend **toute la largeur** du fichier comme une seule
image et afficherait les quatre poses côte à côte, écrasées sur un pion quatre
fois trop large. C'est spectaculaire, donc au moins ça ne passe pas inaperçu.

Le jour où l'animation viendra, il suffira de monter
`TacticsPawnResource.ANIMATION_FRAMES` et d'ajouter les colonnes à droite : la
formule de choix de frame les prend déjà en compte, et garder les images de
marche du pack quelque part de côté évitera de racheter ou redessiner.

### Repères de dessin

Mesurés sur les huit planches existantes, à respecter pour que le casting reste
d'aplomb :

| Repère | Position dans la case de 128 |
|---|---|
| Ligne de pieds | `y = 120` (dernière rangée opaque : 119) |
| Sommet du crâne | `y = 8` |
| Hauteur de la figurine | 108 à 116 px |
| Axe de symétrie | `x = 64` |
| Proportions | ~2,3 têtes de haut — du chibi franc, à tenir |
| Palette | 25 couleurs pour tout le casting, 9 partagées |

Les proportions comptent autant que la résolution : le casting actuel tient un
canon chibi (crâne du haut du dessin jusqu'à ~`y = 56`, corps et jambes en
dessous). En montant en résolution la tentation est de dériver vers 3 ou 4 têtes
— ce serait changer l'identité de toutes les unités sans l'avoir décidé.

Le dossier [`art/`](../../../art/) à la racine du dépôt contient de quoi
travailler : `gabarit-reperes.png` (calque de repères à superposer),
`palette-figurines.gpl` (lisible par Aseprite et GIMP, couleurs du casting +
accents de la charte « Velmar : nuit et or ») et `planche-contact.png` (les huit
figurines côte à côte en ×4, pour comparer proportions et teintes en dessinant).

Un défaut connu à ne pas reproduire : `chr_pawn_skeleton_mage.png` a ses pieds
de face à `y = 124`, quatre pixels plus bas que tout le monde. Il flotte donc très
légèrement par rapport aux autres.

### Réglages moteur — ne pas les défaire

Les `.import` de ce dossier sont en `compress/mode=0` (sans perte) avec
`mipmaps/generate=true`, et surtout `detect_3d/compress_to=0`. Ce dernier compte :
laissé à `1`, Godot rebascule tout seul la texture en compression VRAM dès qu'il
la voit servir en 3D — c'est ce qui était arrivé, et le block compression bave
sur des aplats de dix couleurs. Le `Sprite3D` est en `texture_filter = 4`
(`NEAREST_WITH_MIPMAPS_ANISOTROPIC`) : net de près, propre au dézoom. Les aperçus
2D des menus (`character_editor.gd`, `prep_screen.gd`) sont en
`TEXTURE_FILTER_NEAREST` pour la même raison.

---

## Ce qui manque

### Héros — `character/`

| Fichier à fournir | Pour qui | Priorité |
|---|---|---|
| `chr_pawn_cavalier.png` | **Sully** — cavalerie, lance, monture | 🔴 elle ressemble au Lord |
| `chr_pawn_pegasus.png` | **Cordelia** — pégase, lance, ailes | 🔴 elle ressemble à la Cleric |
| `chr_pawn_lord.png` | **Chrom** — pour qu'il ait le sien, et libérer `knight` | 🟠 |
| `chr_pawn_cleric.png` | **Lissa** — bâton de soin, pour libérer `mage` | 🟠 |

Les classes promues (Great Lord, Paladin, Sniper, Falcon Knight…) n'ont aucune
planche : une unité promue garde la figurine de sa classe de départ. C'est
acceptable pour l'instant, ça se verra quand la campagne ira plus loin.

### Créatures — `mob/`

Rien ne manque : les trois morts-vivants ont chacun la leur depuis le
2026-08-07 (elles existaient sur le disque sans être branchées).

---

## Comment brancher une planche fournie

1. Déposer le `.png` dans `character/` ou `mob/`.
2. Ouvrir la fiche de l'unité (`data/models/world/stats/hero/*.tres`) et pointer
   son champ `sprite` sur le nouveau chemin.
3. C'est tout — le roster transporte l'apparence, le pion la relit.

Pour un personnage créé dans l'**éditeur de personnages**, rien à éditer : le
sélecteur d'avatar liste ce qu'il trouve dans ces deux dossiers, la nouvelle
planche y apparaît d'elle-même.
