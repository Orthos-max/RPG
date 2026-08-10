# Atelier des figurines

Matériel de dessin, pas des ressources de jeu. Le `.gdignore` à côté empêche
Godot d'importer ce dossier — rien d'ici ne part dans le build.

La consigne complète (format, convention dos/face, repères) est dans
[`assets/textures/actor/README.md`](../assets/textures/actor/README.md). Ce qui
suit ne décrit que les trois fichiers.

Par où produire les planches — 3D, commande, pack, IA, dessin :
[`METHODES.md`](METHODES.md), comparées sur les contraintes du projet.

Pour l'achat d'un pack tout fait : [`ACHAT-PACK.md`](ACHAT-PACK.md) — la liste de
contrôle, éliminatoires en tête.

Si un mot n'est pas clair — planche, cellule, figurine, fiche, pion — c'est dans
[`LEXIQUE.md`](LEXIQUE.md), qui dit aussi lesquels ne veulent pas dire la même
chose dans le code et dans la conversation.

## `gabarit-reperes.png`

128 × 256 transparent, à ouvrir comme **calque du dessus** dans Aseprite par-dessus
la planche en cours. Rien à effacer avant d'exporter : le calque ne fait pas
partie de la planche.

| Trait | Couleur | Ce qu'il marque |
|---|---|---|
| Horizontale | rose | `y = 119`, la dernière rangée où poser les pieds |
| Horizontale | cyan | `y = 8`, le sommet du crâne |
| Verticale pointillée | blanc | `x = 64`, l'axe de symétrie |
| Horizontale | orange | `y = 127`, la coupe entre visage (haut) et dos (bas) |

Le gabarit se déduit des planches : si l'échelle change encore, relancer
`atelier.py` suffit à le refaire au bon format.

## `palette-figurines.gpl`

Palette GIMP, lue telle quelle par Aseprite (`File ▸ Palette ▸ Load`). Deux
blocs :

- **les 25 couleurs du casting actuel**, triées par nombre de planches où elles
  apparaissent — les premières sont le noyau commun, celles qui font qu'un
  archer et un chevalier ont l'air de venir du même monde ;
- **six accents de la charte** « Velmar : nuit et or », repris de
  `data/models/view/theme/palette.gd`. L'or reste un accent : dès qu'il remplit
  une surface, il cesse de désigner ce qui compte.

Rester dans ce jeu de couleurs vaut mieux que de bien dessiner isolément. Une
figurine techniquement supérieure mais hors palette casse le casting.

## `planche-contact.png`

Les huit planches côte à côte, agrandies ×4, sur le fond `INK` de la charte —
c'est-à-dire à peu près ce que voit le joueur. À garder ouvert pendant qu'on
dessine : c'est le seul moyen de voir qu'une nouvelle figurine est trop grande,
trop pâle ou trop détaillée avant de la mettre en jeu.

Elle se régénère avec le script d'atelier :

```
python3 art/atelier.py
```

## Ce qui reste à dessiner

| Fichier | Pour qui | Pourquoi c'est urgent |
|---|---|---|
| `chr_pawn_cavalier.png` | Sully | elle porte la planche du Lord |
| `chr_pawn_pegasus.png` | Cordelia | elle porte la planche de la Cleric |
| `chr_pawn_lord.png` | Chrom | pour libérer `knight` |
| `chr_pawn_cleric.png` | Lissa | pour libérer `mage` |

Déposer le `.png` fini dans `assets/textures/actor/character/`, puis pointer le
champ `sprite` de la fiche (`data/models/world/stats/hero/*.tres`) dessus. Pour
un personnage de l'éditeur, rien à faire : le sélecteur liste le dossier.
