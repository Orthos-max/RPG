# Lexique des figurines

Plusieurs mots désignent la même chose, et un même mot désigne parfois deux
choses. Ce fichier fixe lequel employer. Les termes du **code** sont donnés tels
quels, même quand ils sont malheureux — c'est ce qui est écrit dans les fichiers.

---

## Les trois pièges à connaître

**1. `case` ne parle que du plateau.** Une case, c'est une cellule de la grille de
combat. Le carré de 128 × 128 dans une planche s'appelle une **cellule**. J'ai
moi-même écrit « case de 128 » dans les premières notes du 2026-08-10 — c'est
corrigé, mais le réflexe peut revenir.

**2. `sheet` en anglais, dans ce code, veut dire *fiche*, pas *planche*.**
[UnitSheet] est « ce que le joueur lit en survolant un pion ». La planche de
sprites ne s'appelle jamais « sheet » ici.

**3. Le nœud `Character` n'est pas le personnage.** C'est le `Sprite3D` **à
l'intérieur** du pion — l'image, pas le combattant. Le combattant, c'est le nœud
parent, `Pawn`.

---

## L'image

| À dire | Ce que c'est | Aussi appelé | Remarque |
|---|---|---|---|
| **planche** | le fichier `.png` entier, 128 × 256, deux poses | sprite sheet, feuille | le mot de référence |
| **cellule** | un carré de 128 × 128 dans la planche | frame, case ❌ | ne **pas** dire « case » |
| **pose** | ce que contient une cellule : de face, ou de dos | rangée, vue, image | il y en a exactement deux |
| **frame** | le mot de Godot pour l'indice de la pose | — | `0` = haut = visage, `1` = bas = dos |
| **figurine** | l'apparence d'une unité, donc la planche qu'elle porte | avatar | terme du projet, employé partout |
| **avatar** | strictement synonyme de figurine | figurine | n'apparaît qu'une fois, pour le sélecteur de l'éditeur |

⚠️ **`sprite`** — dans le code, le champ `sprite` d'une fiche contient le chemin
d'une **planche entière**, pas d'une image. `sprite = "res://…/chr_pawn_knight.png"`
désigne les deux poses à la fois.

⚠️ **`portrait`** — **n'existe pas dans le projet.** Ce serait un buste de dialogue
façon Fire Emblem : une illustration large, sans grille, affichée quand un
personnage parle. Rien à voir avec l'avatar, et rien n'est fait pour l'instant.

---

## Le plateau

| À dire | Ce que c'est | Remarque |
|---|---|---|
| **case** | une cellule de la grille de combat | le mot est **réservé** à ça |
| **tuile** | l'objet 3D posé qui matérialise une case | une case est logique, une tuile est physique |
| **pion** | l'unité présente sur le plateau — nœud `Pawn` | `CharacterBody3D` |
| **`Character`** | le `Sprite3D` **dans** le pion : son image | ⚠️ pas le personnage |
| **plateau** | la carte de combat dans son ensemble | arène, niveau |

---

## L'unité

| À dire | Ce que c'est | Nom dans le code |
|---|---|---|
| **unité** | un combattant de la partie | — |
| **fiche** | ce que le joueur lit en survolant un pion | `UnitSheet` |
| **document** | la fiche éditable de l'éditeur de personnages | `UnitDocument` |
| **classe** | Lord, Cavalier, Cleric… | ⚠️ `expertise` |
| **roster** | la liste des unités dont on dispose | — |
| **déploiement** | les unités choisies pour un chapitre | — |

⚠️ **`expertise`** — c'est le mot du code pour **classe**. `setup(stats, expertise)`
attend « Lord », « Archer »… Ne pas y chercher un niveau de maîtrise.

---

## Le rendu

| À dire | Ce que c'est |
|---|---|
| **taille du fichier** | les dimensions annoncées du `.png` — 128 × 256 |
| **résolution réelle** | le détail réellement présent. Peut être bien plus basse |
| **agrandissement** | une image gonflée sans ajout de détail. Le piège du casting actuel : 32 × 32 étalés sur 128 × 128 |
| **plus proche voisin** | filtre qui garde le pixel carré. Pour **agrandir**. Dit *nearest* |
| **linéaire** | filtre qui moyenne. Pour **réduire** — les vignettes de menu |
| **mipmap** | versions réduites pré-calculées, employées quand l'image est loin |
| **crénelage** | l'escalier sur un bord. *Aliasing* |
| **anticrénelage** | bords adoucis. Souhaitable ailleurs, **à fuir** en pixel art. *Anti-aliasing* |
| **billboard** | le pion se tourne toujours vers la caméra |
| **`pixel_size`** | combien d'unité de monde vaut un pixel de planche. `0.01` × 128 = 1,28 |
| **cadrage** | la hauteur de monde visible à l'écran, `size` de la caméra orthographique. De 7 (près) à 26 (loin) |

---

## Ce qui se ressemble mais n'est pas pareil

- **planche** ≠ **figurine** : la planche est le fichier, la figurine est
  l'apparence qu'il donne à une unité. En pratique on dit souvent l'un pour
  l'autre, et ce n'est pas grave.
- **cellule** ≠ **case** : la première est dans l'image, la seconde sur le plateau.
- **fiche** ≠ **planche** : la fiche porte les chiffres, la planche porte l'image.
- **avatar** = **figurine** : là, c'est vraiment la même chose.
- **pion** ≠ **`Character`** : le pion contient le `Character`.
