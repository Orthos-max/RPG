# Ciel Emblem

[![Licence: MIT](https://img.shields.io/badge/Licence-MIT-green.svg)](./LICENSE)
[![Godot 4.3](https://img.shields.io/badge/Godot-4.3-blue.svg)](https://godotengine.org/)
[![Version 0.1.0](https://img.shields.io/badge/version-0.1.0-c9a227.svg)](./project.godot)

**Un tactical RPG au tour par tour façon _Fire Emblem_, écrit sur Godot 4.3.**

---

## Fonctionnalités

### Campagne solo — 6 chapitres
Écran-titre (nouvelle partie, reprise, difficulté, mort permanente), sélection
d'unités avant mission, **phase de placement** case par case, intros et outros de
chapitre, sauvegarde JSON lisible dans `user://saves/`.
Cinq familles d'objectifs : rout, boss, survie, protection d'une unité, prise de
point — plus des objectifs secondaires récompensés en or. Entre deux chapitres,
l'**intendance** : boutique, armurerie, objets à gain permanent, soins payants,
recrutement. Les blessures persistent d'un chapitre à l'autre. Des **coffres**
sont disséminés sur les maps : or ou objets à ramasser pendant la mission.

### Combat Fire Emblem complet
- Formule FE intégrale : précision, esquive, critique, dégâts, **double attaque**,
  et la **riposte** résolue en échange complet.
- **Triangle des armes** (épée > hache > lance), 9 types d'armes, 14 armes nommées
  avec poids, portée, critique et prix ; fourreau de 3 armes par unité.
- **Classes et promotions embranchées** (Lord → Great Lord / Master Lord, Archer →
  Sniper / Bow Knight…), croissances de stats par classe, expérience et niveaux.
- **11 compétences** passives et à déclenchement, **soutiens** entre paires,
  **bonus de terrain**, **arme efficace** contre les volants.
- **Prévision de combat** au survol d'une cible : dégâts, coups, précision,
  critique, PV restants et létalité — **des deux côtés**, riposte comprise.
- Inventaire limité (5 emplacements), consommables et toniques.
- **Montée de niveau animée** : les gains de stats s'inscrivent une par une,
  avec fanfare et braises — et les **promotions** ont leur propre cérémonie.
- **Quick save / quick load** en plein combat (F5 / F9) et bilan de bataille
  **détaillé unité par unité** après la mission.

### Son & ambiance
20 sons procéduraux (coups, critiques, soins, niveaux, interface) et trois
boucles musicales (titre, bataille, préparation) — générés localement, sans
aucun droit d'auteur. Particules d'ambiance par terrain : feuilles en forêt,
flocons en neige, reflets sur l'eau, braises dans les ruines.

### Multijoueur par code d'accès
Créer une partie, transmettre un **code de 7 caractères**, jouer. Pas de
matchmaking : du peer-to-peer entre amis (ENet, port 24710). L'hôte fait autorité
et valide chaque ordre reçu. Un invité qui saute
voit son siège gardé 90 s pendant que l'IA locale le tient, et se reconnecte tout
seul.

### Éditeurs intégrés
- **Éditeur de cartes** — pinceaux de terrain, élévation, unités des deux camps,
  cases de départ, point de commandement, réglages d'objectif, annulation/rétablissement
  (Ctrl+Z), redimensionnement, bibliothèque dans `user://maps/`, partage par
  presse-papiers ou fichier, et essai immédiat contre l'IA locale.
  Une carte d'essai ne touche jamais à la campagne.
- **Éditeur de personnages** — les créatures écrites y sont posables dans
  l'éditeur de cartes, pour les deux camps.

### Ce qui tient le tout
Suites de tests headless (combat, cartes, features, intégration), suites en vraie
fenêtre qui jouent un tour **à la souris**, test réseau à deux processus, et
`shot.gd` pour capturer un écran réel. Export macOS / Windows / Linux, installeur
Windows construit en CI.

---

## Lancer le jeu

**Le plus court chemin — double-cliquer sur `Jouer.command`** (macOS). Le projet
démarre dans le moteur, sans passer par l'éditeur Godot.

```bash
bash scripts/ciel_game/launch.sh   # équivalent, en ligne de commande
godot --path .                     # ou directement
```

Il faut **Godot 4.3** — le projet y est verrouillé.

Pour jouer sans installer Godot du tout (build autonome, installeur Windows,
`.dmg` macOS), tout est dans [`docs/INSTALL.md`](docs/INSTALL.md).

### Les tests

```bash
bash scripts/test_all.sh            # les quatre suites headless
bash scripts/test_all.sh --window   # + les suites en vraie fenêtre
bash scripts/test_net.sh            # transport réseau, deux processus
```

Une suite seule :

```bash
godot --headless --path . --script res://tests/test_combat.gd
```

Et pour *voir* plutôt que mesurer :

```bash
godot --path . --resolution 1600x900 --script shot.gd -- battle sortie.png free
```

---

## Structure du projet

```
data/
  models/        données & logique pure — aucun nœud, donc testable en headless
    config/        configuration, journal de débogage
    view/          caméra, contrôles, décor du plateau, charte graphique
    world/
      ai/            validation des ordres, IA locale, difficulté
      combat/        arène, participants, pions, camps
      map/           MapData, grille de bataille, champ de parcours
      stats/         stats, classes, armes, compétences, objets, exp, soutiens
      utilities/     conversions monde ↔ grille
    campaign/      chapitres, objectifs, plan de déploiement
    net/           sièges gardés, plan de reconnexion
  modules/       nœuds Godot — gameplay et écrans
    tactics/       niveau, arène, participants, pion, caméra, contrôles
    ai/            IA adverse locale et difficulté
    campaign/      déroulé de chapitre, phase de placement
    menu/          titre, préparation, salon réseau
    net/           miroir côté invité
    ui/            bandeaux, prévision de combat, fiche d'unité
  services/      autoloads transverses — campagne, combat, réseau, session, audio
assets/
  maps/          niveaux
  textures/      figurines, terrains, interface
  packs/         packs d'art tiers (voir Crédits)
  fonts/         Cinzel, Alegreya Sans (OFL)
  audio/         branché, en attente de fichiers
art/             atelier des figurines — gabarits, palette, outils de découpe
docs/            PROJECT_SPEC, INSTALL
scripts/
  build/         export, packaging, installeur Windows
  test_all.sh    toutes les suites, d'un coup
tests/           les suites headless et fenêtrées
```

Trois règles gouvernent cette arborescence : `models` porte les données et la
logique, `modules` les nœuds Godot, `services` ce qui traverse tout.

---

## Documentation

| Document | Ce qu'on y trouve |
|---|---|
| [`docs/PROJECT_SPEC.md`](docs/PROJECT_SPEC.md) | Le document de cap : architecture, backlog, journal d'implémentation |
| [`docs/INSTALL.md`](docs/INSTALL.md) | Jouer, construire, empaqueter, dépanner |
| [`assets/textures/actor/README.md`](assets/textures/actor/README.md) | Le format des figurines et ce qui manque |
| [`art/METHODES.md`](art/METHODES.md) | Les routes possibles pour produire les planches |

---

## Crédits

### Packs d'art

| Pack | Auteur·rices | Usage | Licence |
|---|---|---|---|
| [Tiny Swords](https://pixelfrog-assets.itch.io/tiny-swords) (Free Pack) | Pixel Frog | Figurines des pions sur le plateau (`data/models/view/pawn/pawn_look.gd`) | Pack gratuit |
| SSCAP SRPG Tileset v1.3 | SRPG Studio Community Asset Project — Briver, Soviet, General Ciraxis, Kennedy, Yeedley/CardCafe, Deluka | Textures de terrain, découpées case par case par `art/decouper-tuiles.py` | [CC BY 3.0](http://creativecommons.org/licenses/by/3.0/) |
| Shikashi's Fantasy Icons Pack (v1 & v2) | Shikashi | Icônes d'objets et d'interface | Pack commercial, usage libre en jeu ; nombre d'icônes dérivées de [game-icons.net](https://game-icons.net) (CC BY 3.0) |

### Polices

**Cinzel** (titres) et **Alegreya Sans** (corps), toutes deux sous
[SIL Open Font License](assets/fonts/), donc redistribuables avec le jeu.

### Le reste

Le décor du plateau — ciel, brume, lumière rasante, grain du terrain, arbres,
rochers, créneaux — est **entièrement procédural** : aucun asset, tout en code
dans [`data/models/view/scenery/`](data/models/view/scenery/).

---

## Licence & base d'origine

Ce projet est sous [licence MIT](./LICENSE).

Ciel Emblem est bâti sur le template **[godot-tactical-rpg](https://github.com/ramaureirac/godot-tactical-rpg)**
de Rodrigo Maureira et de ses contributeur·rices — dont viennent la grille, la
caméra tactique et l'ossature du projet, avant tout ce qui s'est ajouté depuis.
Merci à eux.

📖 **[Wiki du template d'origine](https://github.com/ramaureirac/godot-tactical-rpg/wiki)** — pour comprendre les fondations, ou en repartir pour son propre jeu.
