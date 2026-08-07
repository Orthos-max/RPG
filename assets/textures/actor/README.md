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
| Rangée du haut | l'unité **de dos** (vue quand elle s'éloigne de la caméra) |
| Rangée du bas | l'unité **de face** |
| Style | pixel art, la figurine occupe la largeur, pieds en bas de case |

Le pion est un `Sprite3D` en `billboard`, `vframes = 2` : il choisit dos ou face
selon l'orientation par rapport à la caméra. Une planche mal découpée se voit
tout de suite — l'unité change de moitié en tournant.

Pour animer plus tard, il suffira de monter `TacticsPawnResource.ANIMATION_FRAMES`
et d'ajouter des colonnes : la formule de choix de frame les prend déjà en compte.

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
