# Acheter un pack de figurines — liste de contrôle

Écrit pour Ciel Emblem, avec ses contraintes réelles : case de 128 × 128, deux
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

### 2. Résolution native de 128 × 128 par pose

Pas 32 ou 64 agrandis. C'est exactement le piège dans lequel les planches
actuelles de Ciel Emblem étaient tombées : 128 × 256 sur le disque, 32 × 32 de
contenu réel. Un vendeur sérieux annonce la taille de case ; sinon, demander une
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

Test simple sur l'image d'exemple : compter les couleurs. Du vrai pixel art en
tient quelques dizaines. Le casting actuel de Ciel Emblem en compte **25 pour
huit planches**.

---

## Format technique

- **PNG à alpha réel**, pas un fond magenta ou blanc à détourer.
- **Grille régulière**, cases de taille constante, sans marge variable. Un atlas
  aux espacements irréguliers se redécoupe à la main, planche par planche.
- **Ligne de pieds constante** sur tout le pack. C'est le défaut le plus fréquent
  et le plus coûteux : si chaque personnage pose ses pieds à une hauteur
  différente, les unités flottent ou s'enfoncent les unes par rapport aux autres,
  et il faut recaler chaque planche. Ciel Emblem attend `y = 120`.
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

## Ce qu'on ne prend pas, pour l'instant

Les colonnes d'animation. Décision du 2026-08-10 : une colonne, deux images. D'un
pack animé on n'extrait que les deux poses de repos — mais **on garde les images
de marche de côté**, elles sont déjà payées et serviront le jour où l'animation
viendra.

Ce n'est pas un critère *contre* un pack animé : à prix égal, il laisse la porte
ouverte.
