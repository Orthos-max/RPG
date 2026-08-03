# Project Spec — Godot Tactical RPG (CielAI)

> **Document de cap.** Décrit ce que le jeu **est** aujourd'hui et ce qu'il doit **devenir**.
> Servira de référence à Claude Code pour implémenter les prochaines features.
> Dernière mise à jour : 2026-08-03

---

## 1. Vision produit

Un **tactical RPG au tour par tour façon Fire Emblem**, développé sur **Godot 4.3**,
dont la signature est le **pont CielAI** : une IA externe (Ciel) qui contrôle le camp
adverse via un échange de fichiers JSON avec le moteur.

Le jeu n'est **pas** qu'un prototype technique : c'est un terrain de jeu vivant où le
joueur humain affronte une IA dirigée par un agent externe, avec un vrai système de
combat (stats, classes, armes, triangle d'armes, expérience, soutiens).

**Axes de développement prioritaires :**
1. **CielAI** — l'IA externe (Ciel) qui pilote le camp adverse. La signature du projet.
2. **Mode Solo / Campagne** — une vraie campagne jouable en solo (chapitres, progression,
   sauvegarde), + le mode CielAI, + un mode multijoueur.
3. **Multijoueur** — créer une partie et inviter des amis via un **code d'accès**
   (pas de matchmaking) ; un ami peut rejeter/prendre le camp de Ciel.
4. **Accessibilité / distribution** — un installateur simple pour jouer sans setup Godot.

---

## 2. Stack & environnement

| Élément | Valeur |
|---|---|
| Moteur | Godot **4.3** (chemin `~/Applications/Godot-4.3.app`) |
| Langage | GDScript (conforme style guide officiel) |
| Branch git | `development` |
| Main scene | `res://assets/scene/main.tscn` |
| Mode | Combat 2D sur grille (engine 3D réutilisé en vue tactics) |
| Test headless | `godot --headless --path . --script X.gd` (sans `--quit` : les suites s'arrêtent seules) |

> ✅ Corrigé (2026-08-03) : `config/features` = `4.3`, projet renommé **Ciel Emblem**
> (`config/name`), version `0.1.0`. Le dossier `user://` devient donc
> `…/app_userdata/Ciel Emblem/` — les scripts du pont le résolvent automatiquement
> (et retombent sur l'ancien dossier s'il existe encore).

---

## 3. Architecture existante (ce qui est en place)

### 3.1 Organisation des dossiers
```
data/
  models/      → données & logique pure (aucun nœud, donc testable en headless)
    config/      → TacticsConfig, DebugLog
    view/        → camera, contrôles d'input
    world/
      ai/          → ciel_command (validation), local_ai (heuristique),
                     ai_executor (scène ↔ IA), difficulty
      combat/      → arena, participant, pawn, team (TeamData)
      map/         → MapData, générateur
      stats/       → stats, classes, armes, compétences, objets, exp, soutiens
      utilities/   → vector, grid (conversions monde ↔ grille)
    campaign/    → chapitres, objectifs, contenu de campagne
  modules/     → nœuds Godot (gameplay et écrans)
    tactics/     → level, arena, participants, pawn, camera, controls
    ai/          → ciel_ai.gd (pont, autoload)
    campaign/    → chapter_runner (roster + objectif en cours de bataille)
    menu/        → title_screen, prep_screen, lobby_screen
    net/         → net_mirror (côté invité)
    ui/          → turn_banner, hints, input capture
  services/    → autoloads transverses
    campaign/    → campaign_state (roster persistant, sauvegarde)
    combat/      → fe_combat (calculateur), battle_log (journal + replay)
    network/     → net_service (parties par code d'accès)
    session/     → game_session (mode, camps, difficulté)
assets/
  maps/          → niveaux (map_level procédural, test_level sculpté)
  textures/      → actor, mob, ui
docs/            → PROJECT_SPEC, CIEL_PROTOCOL, INSTALL
scripts/
  ciel_game/     → PONT CielAI (_paths, launch, command, state)
  build/         → export.sh, package.sh
  test_net.sh    → test réseau à deux processus
fe_2d/           → variante 2D (work in progress)
test_combat.gd / test_map.gd / test_features.gd / test_battle.gd / test_net.gd
```

### 3.2 Système de combat (`data/services/combat/fe_combat.gd`)
- **`FECombatCalculator`** — formule FE complète : hit rate, critique, dégâts, double attaque.
- Signature : `compute_hit_rate`, `compute_crit`, `compute_damage`, `resolve_combat`.
- Degrés de RNG : miss / normal / crit / double / double+crit.
- Bonus de terrain (DEF/RES) et bonus de soutien (hit/crit/avoid/crit_avoid) pris en compte.

### 3.3 Stats & classes (`data/models/world/stats/`)
- **`stats_res.gd`** (`StatsResource`) — modèle de stats.
- **`class_data.gd`** — définition des classes.
- **`weapon_type.gd`** (`WeaponType`) — les 9 types d'armes + triangle d'armes :
  - `Sword > Axe > Lance > Sword` (+1 dmg, +15 hit d'avantage, −15 désavantage).
  - Bows : neutres en mêlée, efficaces vs volants.
  - Tomes : magie (MAG vs RES), Staves : support seul, Dracostone/Beststone/Breath.
- **`exp.gd`** — système d'expérience.
- **`support.gd`** / **`support_pair.gd`** — système de soutien entre paires.
- **Héros** (`.tres`) : `lord`, `cleric`, `archer`, `great_knight`.
- **Mobs** (`.tres`) : `skeleton`, `skeleton_cpn`, `skeleton_mage`.

### 3.4 Gameplay tactics (`data/modules/tactics/`)
- **`tactics_level.gd`** — orquestre le niveau.
- **`tactics_arena.gd`** — arène / grille de combat.
- **`tactics_tile.gd`** + **`tile_raycasting.gd`** — tuiles + raycast souris.
- **`tactics_participant.gd`** / **`tactics_player.gd`** / **`tactics_opponent.gd`** — participants.
- **`pawn.gd`** — unité sur la grille.
- **`support_tracker.gd`** — suivi des soutiens en session.
- **`camera.gd`** — caméra tactics (pan/zoom/rotation, focus sur pions).
- **`controls.gd`** — contrôles (souris/gamepad/clavier).

### 3.5 IA ennemie
- **`ciel_ai.gd`** (autoload) — le pont : export d'état, lecture et **validation**
  des ordres, exécution (déplacement, attaque, soin, objet, promotion, fuite,
  garde), acquittement dans `ai_feedback.json`.
- **`local_ai.gd`** (`LocalAIBrain`) — IA heuristique pure : score de cible
  (achèvement, cible blessée, menace, riposte), terrain défensif, risque
  d'encerclement, modulé par la difficulté.
- **`ai_executor.gd`** — traduit la scène en dictionnaires pour le cerveau, puis
  rend la tuile et la cible retenues au moteur.
- **Verrou anti-blocage** : sans ordre valide pendant ~10 s, l'IA locale joue le
  tour à la place de Ciel (ou du joueur distant).

### 3.6 Le pont CielAI (`scripts/ciel_game/`) — **PIÈCE MAÎTRESSE**
Protocole **v1**, spécifié dans [`CIEL_PROTOCOL.md`](CIEL_PROTOCOL.md).
Échange de fichiers JSON dans le dossier `user://` de **Ciel Emblem** (résolu
automatiquement par OS, surchargeable via `CIEL_USERDATA`).

| Fichier | Sens | Description |
|---|---|---|
| `ai_state.json` | Godot → Ciel | État complet : tour, étape, actions légales, terrains, portées, unités, événements |
| `ai_command.json` | Ciel → Godot | Un ordre, supprimé dès lecture — valide ou non |
| `ai_feedback.json` | Godot → Ciel | Acquittement ou motif de rejet du dernier ordre |
| `replays/*.json` | Godot | Journal complet d'une bataille |

**Commandes** (`bash scripts/ciel_game/command.sh <action> [args]`) : `select_pawn`,
`move`, `attack`, `heal`, `use_item`, `promote`, `flee`, `guard`, `wait`,
`end_pawn`, `end_turn`, `toggle`.

**Lecture d'état** (`bash scripts/ciel_game/state.sh [--watch|--raw|--events|--tiles <nom>|--path]`).

**Lancement** : `bash scripts/ciel_game/launch.sh`

> Le joueur distant (mode réseau) emprunte **le même vocabulaire et la même
> validation** : une seule surface d'ordres à maintenir.

### 3.7 Tests automatisés (racine)
- **`test_combat.gd`** — combat FE : stats, calculateur, soin, mort, victoire,
  soutien, triangle. *(23 assertions)*
- **`test_map.gd`** — MapData (grille 16×10), terrains, hauteurs, chargement.
- **`test_features.gd`** — validation des ordres, IA locale, croissances,
  promotions, efficacité, objets, compétences, objectifs, sauvegarde, économie,
  difficulté, session, codes réseau. *(151 assertions)*
- **`test_battle.gd`** — intégration : titre → campagne → chapitre chargé → état
  exporté → ordre rejeté → sauvegarde. *(21 assertions)*
- **`test_net.gd`** + `scripts/test_net.sh` — transport réseau à deux processus.

Tous en `SceneTree`, sortie `X OK / Y ÉCHECS`, code de sortie 0/1.

---

## 4. Backlog — Améliorations & nouvelles features (par priorité)

### 🥇 P0 — Fondations (indispensable avant tout le reste)
- [x] **Corriger `project.godot`** : `config/features` = `4.3`, projet renommé **Ciel Emblem**.
- [x] **Documenter le protocole CielAI** → `docs/CIEL_PROTOCOL.md` (schémas JSON,
      contrat de commandes, codes d'erreur, garanties).
- [x] **Verrouillage de la boucle IA** : `CielCommand` valide chaque ordre (schéma,
      types, étape, tour, bornes de grille) ; rejet propre + log + `ai_feedback.json`.
      L'ordre est consommé même invalide → pas de boucle de rejet.
- [x] **Fallback IA locale** : `LocalAIBrain` (heuristique pure testable) branché sur
      `TacticsOpponentService` **et** sur un verrou anti-blocage — sans ordre valide
      pendant ~10 s, l'IA locale joue le tour à la place de Ciel.

### 🥈 P1 — Gameplay & fidélité Fire Emblem
- [x] **HP/Stat growths par classe** : `class_data.gd` fait autorité à l'import
      (`use_class_growths`), montée de niveau injectable pour les tests.
- [x] **Pyramide de promotion embranchée** (Lord → Great Lord / Master Lord, Cavalier →
      Paladin / Great Knight, Archer → Sniper / Bow Knight, …) + bonus de promotion réels.
- [x] **Arbre de compétences passives/actives** par classe : 11 compétences
      conditionnelles (attaque/défense, PV bas, PV pleins, terrain, cible volante)
      et deux à déclenchement (Lune perce la défense, Astre ajoute une frappe),
      débloquées par classe et par niveau.
- [x] **Bonus de terrain** exposé de bout en bout (calculateur → `CombatResult.terrain_defense`
      → état CielAI `terrain`/`terrain_def`). *Reste à faire : choix du terrain en préparation.*
- [x] **Inventaire limité** par unité (`ItemDB`, 5 emplacements, consommables + toniques).
      *Reste à faire : menu d'équipement d'armes.*
- [x] **Archerie effective vs volants** : x3 de might, classes volantes déclarées
      (Pegasus/Falcon Knight, Wyvern Rider/Lord).

### 🥉 P2 — Le pont CielAI enrichi (différenciateur du projet)
- [x] **États plus riches pour Ciel** : portées de mouvement/attaque du pion actif, carte
      des terrains, PV/niveau/classe/objets/buffs par unité, actions légales de l'étape.
- [x] **Commandes avancées** : `wait`, `guard`, `use_item`, `heal`, `promote`, `flee`.
- [x] **Détection de changement** : `seq` + `timestamp` + `event_cursor` — Ciel compare
      un compteur au lieu de diffuser tout l'état.
- [x] **Log de parties** persisté : `BattleRecorder` → `user://replays/*.json`.
- [x] **Handicap / équilibrage adversaire** : `DifficultyDB`, bonus progressif par
      chapitre, appliqué au camp adverse à l'entrée en scène.

### 🏆 P3 — Mode Solo / Campagne (expérience solo à part entière)
> Le jeu doit être jouable complet sans adversaire humain : une vraie campagne solo,
> en complément du mode CielAI et du multijoueur.
- [x] **Écran de titre & menu principal** : Nouvelle partie / Continuer / Escarmouche
      CielAI / Difficulté / Mort permanente / Extras / Quitter.
- [x] **Chapitres & progression** : `CampaignDB` (3 chapitres) + `ObjectiveDB`
      (rout, boss, survie, protection, prise de point) et objectifs secondaires.
- [x] **Sélection d'unités avant mission** : écran de préparation, places limitées par
      chapitre, roster persistant appliqué aux pions du niveau.
- [x] **Sauvegarde de campagne** : JSON lisible dans `user://saves/` (stats, XP, niveau,
      or, morts permanentes, progression).
- [x] **Scénario/écriture** : intros/outros de chapitre (boîtes de texte simples).
- [x] **Économie entre chapitres** : boutique (objets tarifés, revente à moitié
      prix, objets à gain permanent), soins payants — les blessures persistent
      désormais d'un chapitre à l'autre — et recrutement (Sully, Cordelia).
- [x] **Objectifs secondaires / récompenses** : aucune perte, run rapide, éradication
      complète — +100 or chacun.
- [x] **Difficulty** : facile/normal/brutal, module l'IA locale (agressivité, prise de
      risque, focus sur les blessés) et le handicap adverse.

### 🤝 P2 — Multijoueur (chantier structuré en phases)
> Concret et minimal : créer une partie + inviter des amis avec un **code d'accès**.
> Pas de matchmaking, pas de salons publics — juste du peer-to-peer familial/privé.
- [x] **M1 — Généralisation des participants** : `TeamData` (Side + Controller :
      LocalPlayer / LocalAI / CielAI / RemotePlayer) et autoload `GameSession`
      (mode, difficulté, chapitre, code d'invitation). La boucle de tour interroge
      `GameSession.controller_for(side)` au lieu d'un test en dur.
- [x] **M2 — Hotseat (local, 2 joueurs sur la même machine)** : les actions
      humaines sont remontées dans `TacticsParticipant`, la boucle de tour prend
      le camp en paramètre et un bandeau rappelle à qui de jouer.
- [x] **M3 — Réseau peer-to-peer (invitation par code)** : `ENetMultiplayerPeer`
      sur le port 24710, code de 7 caractères encodant l'adresse de l'hôte, état
      diffusé par l'hôte et reflété par l'invité (`NetMirror`).
- [x] **M4 — Gestion de partie simple** : écrans Créer/Rejoindre avec choix de
      carte, salon d'attente et répartition automatique des camps.
- [ ] **M5 — CielIA vs un ami en réseau** : le pont et le réseau partagent déjà le
      même chemin d'ordres validés côté hôte ; reste à permettre trois camps
      (joueur local, invité distant, Ciel) dans une même partie.
- [x] **Règles réseau** : autorité de l'hôte (il seul simule), validation de chaque
      ordre reçu, reprise par l'IA locale si l'invité part.
      *Reste à faire : reconnexion en cours de partie.*

### 📦 P2 — Installateur & distribution (jouer simplement)
> Objectif : un joueur peut lancer le jeu sans installer/télécharger Godot ni configurer quoi que ce soit.
- [x] **Export Godot** : `export_presets.cfg` versionné (macOS / Windows / Linux) +
      `scripts/build/export.sh`. *Nécessite les modèles d'export Godot 4.3 installés.*
- [x] **Packaging natif** : `scripts/build/package.sh` produit un `.dmg` (create-dmg
      ou hdiutil), un `.zip` Windows et un `.tar.gz` Linux, notice et pont CielAI
      inclus. *Reste à faire : signature/notarisation macOS.*
- [x] **Installateur Linux** : `install.sh` pose le jeu dans `~/.local` avec une
      entrée de menu. *Reste à faire : installeur Windows (Inno Setup).*
- [x] **Portabilité du pont CielAI** : `scripts/ciel_game/_paths.sh` résout le dossier
      `user://` selon l'OS, honore `CIEL_USERDATA`/`GODOT_BIN`, crée le dossier au besoin
      et retombe sur l'ancien nom de projet. Les scripts sont copiés à côté du binaire.
- [x] **Page/instructions de lancement** : `docs/INSTALL.md` (jouer, construire,
      brancher Ciel, dépannage).

### 🏅 P3 — Vision long terme (hors modes de jeu ci-dessus)
- [ ] **Sons & animations de combat** (sprites en croisade, caméra de duel).
- [ ] **Version `fe_2d/`** : poursuivre le port 2D si la direction artistique évolue.
- [ ] **Polissage UX** : tooltips stats, aperçu des dégâts avant engagement, undo de déplacement.
- [ ] **Mods / éditeur de niveau intégré** (map_editor déjà présent) pour créer ses cartes.

---

## 5. Règles d'implémentation (à transmettre à Claude Code)

1. **Respecter l'architecture existante** : `models` (données/logique) vs `modules`
   (nodes) vs `services` (transverse). Ne pas créer de fichiers fourre-tout.
2. **Tout système de combat modifié doit passer les tests headless**
   (`test_combat.gd`, `test_map.gd`) — ne jamais régresser la suite existante.
3. **Le pont CielAI est sacré** : toute refactor de `data/modules/tactics` ou des stats
   doit préserver le contrat `ai_state.json` / `ai_command.json`.
4. **Code commenté en français** dans les parties custom (cohérent avec le reste du projet).
5. **Une feature = un commit propre** sur `development`, message descriptif.
6. **Ne jamais toucher aux `.godot/`, `.git/`, fichiers `.tmp`** (et les nettoyer si créés).
7. **Ajouter des tests** pour chaque nouvelle feature de logique pure (calculateur,
   croissance de stats, règles).
8. **Vérifier après implémentation** : lancer le jeu + les tests headless avant de
   déclarer une feature terminée.
9. **Garder le multijoueur à l'esprit dès le départ** : ne pas coder d'hypothèse qui
   suppose qu'il n'existe qu'un seul "contrôleur humain local". Introduire la notion
   de `Controller`/`Team` tôt (M1) pour ne pas avoir à tout défaire ensuite.

---

## 6. Prochaines étapes immédiates

Les deux passes du 2026-08-03 ont livré le §6 initial puis le multijoueur,
les compétences, l'économie et le packaging — voir §7. La suite :

1. **Partie en ligne à l'épreuve du terrain** : la vérifier fenêtre ouverte sur deux
   machines, puis traiter la reconnexion en cours de partie (l'IA locale prend le
   relais aujourd'hui, mais l'invité ne peut pas revenir).
2. **M5 — Ciel contre un ami en réseau** : autoriser trois camps dans une même
   partie (joueur local, invité distant, Ciel) — le chemin d'ordres est déjà commun.
3. **Contenu de campagne** : plus de chapitres, objectif « prise de point » (déjà
   supporté par `ObjectiveDB`, aucune carte ne l'utilise), dialogues plus riches.
4. **Choix du terrain / placement en préparation** (le bonus DÉF/RÉS est déjà actif
   en combat, mais le joueur ne choisit pas encore ses cases de déploiement).
5. **Installeur Windows** (Inno Setup) et **signature/notarisation macOS**.
6. **Animations et sons de combat** (P3), le dernier gros morceau de finition.

---

## 7. Journal d'implémentation

### Passe du 2026-08-03 — les 8 étapes du §6

| Livré | Où |
|---|---|
| `project.godot` 4.3 + rebranding **Ciel Emblem** | `project.godot` |
| Spec du protocole CielAI (v1) | `docs/CIEL_PROTOCOL.md` |
| Validation stricte des ordres + feedback | `data/models/world/ai/ciel_command.gd`, `ai_feedback.json` |
| IA locale heuristique + verrou anti-blocage | `data/models/world/ai/local_ai.gd`, `ai_executor.gd` |
| Growths par classe, promotions embranchées, arcs vs volants, inventaire | `class_data.gd`, `stats.gd`, `weapon_type.gd`, `item_db.gd` |
| État enrichi, commandes avancées, replays, difficulté | `ciel_ai.gd`, `battle_log.gd`, `difficulty.gd` |
| Abstraction Team/Controller (M1) | `team_data.gd`, `game_session.gd` |
| Campagne solo : titre, préparation, objectifs, sauvegarde | `title_screen.gd`, `prep_screen.gd`, `campaign_*`, `chapter_runner.gd` |
| Export multi-plateforme + doc d'installation | `export_presets.cfg`, `scripts/build/export.sh`, `docs/INSTALL.md` |

### Passe 2 du 2026-08-03 — multijoueur, compétences, économie, packaging

| Livré | Où |
|---|---|
| Arbre de compétences (11 compétences, passives + procs) | `skill_db.gd`, `class_data.gd`, `fe_combat.gd` |
| Intendance : boutique, objets permanents, soins payants, recrutement | `item_db.gd`, `campaign_state.gd`, `prep_screen.gd` |
| M2 — Hotseat (deux humains locaux) | `tactics_participant.gd`, `turn.gd`, `turn_banner.gd` |
| M3/M4 — Parties privées par code d'accès | `net_service.gd`, `lobby_screen.gd`, `net_mirror.gd` |
| Packaging `.dmg` / `.zip` / `.tar.gz` + installeur Linux | `scripts/build/package.sh` |

Deux choix structurants de cette passe :

* **Les ordres du joueur distant empruntent le chemin de Ciel.** Le protocole
  `CielCommand` sert aussi au réseau : l'hôte valide un ordre venu du réseau
  exactement comme un ordre de Ciel, avec le même acquittement. Une seule
  surface de validation à maintenir, et le verrou anti-blocage protège les deux.
* **Les blessures persistent entre chapitres.** Sans cela, les soins de
  l'intendance n'auraient servi à rien et l'or n'aurait eu qu'un seul débouché.

**Tests** (tous verts) :

```bash
godot --headless --path . --script test_combat.gd    # 23 OK — combat FE
godot --headless --path . --script test_map.gd       # ALL TESTS PASSED
godot --headless --path . --script test_features.gd  # 151 OK — logique des features
godot --headless --path . --script test_battle.gd    # 21 OK — intégration campagne + pont
bash scripts/test_net.sh                             # transport réseau, 2 processus
```

> ⚠️ Limite connue : en `--headless`, le rendu factice empêche la création des
> collisions de tuiles → un tour de combat complet ne peut pas être simulé sans
> fenêtre. `test_battle.gd` vérifie donc tout ce qui précède le premier tour
> (chargement, déploiement, export d'état, rejet des ordres) ; le combat lui-même
> se teste fenêtre ouverte ou via `test_combat.gd` (logique pure). Même limite
> côté réseau : `scripts/test_net.sh` couvre le transport (code, connexion,
> diffusion d'état, relais d'ordre), pas le déroulé d'une bataille à deux.
