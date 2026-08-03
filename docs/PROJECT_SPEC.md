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
| Test headless | `godot --headless --path . --script X.gd --quit` |

> ✅ Corrigé (2026-08-03) : `config/features` = `4.3`, projet renommé **Ciel Emblem**
> (`config/name`), version `0.1.0`. Le dossier `user://` devient donc
> `…/app_userdata/Ciel Emblem/` — les scripts du pont le résolvent automatiquement
> (et retombent sur l'ancien dossier s'il existe encore).

---

## 3. Architecture existante (ce qui est en place)

### 3.1 Organisation des dossiers
```
data/
  models/      → données & logique (resources, services métier)
    config/      → TacticsConfig, DebugLog
    view/        → camera, contrôles d'input
    world/       → combat, map, stats, utilities
    modules/     → blocs réutilisables (nodes Godot)
  modules/     → tactical gameplay (camera, controls, arena, participants, pawn)
  services/    → logique transverse (combat)
assets/
  maps/          → niveaux (arena)
  textures/      → actor, mob, ui
scripts/
  ciel_game/     → PONT CielAI (bash : launch.sh, command.sh, state.sh)
fe_2d/           → variante 2D (work in progress)
test_combat.gd   → tests headless du système de combat
test_map.gd      → tests headless du système de map
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

### 3.5 IA ennemie (`data/modules/ai/`)
- **`ciel_ai.gd`** — module d'IA. Actuellement basique ; la cible est de le faire
  piloter par Ciel via le pont (mais garder un fallback IA locale fonctionnel).

### 3.6 Le pont CielAI (`scripts/ciel_game/`) — **PIÈCE MAÎTRESSE**
Échange de fichiers JSON dans :
`~/Library/Application Support/Godot/app_userdata/Godot Tactical RPG/`

| Fichier | Sens | Description |
|---|---|---|
| `ai_state.json` | Godot → Ciel | État du champ de bataille (turn, stage, pions, positions, stats, tuiles) |
| `ai_command.json` | Ciel → Godot | Ordre d'action (le fichier est supprimé après lecture par Godot) |

**Commandes supportées** (`bash scripts/ciel_game/command.sh <action> [args]`) :
- `select_pawn <nom>` — sélectionner un pion adverse
- `move <col> <row>` — déplacer le pion sélectionné
- `attack <nom>` — attaquer une cible alliée
- `end_pawn` — terminer le tour du pion actif
- `end_turn` — terminer le tour adverse complet
- `toggle on|off` — activer/désactiver le contrôle Ciel

**Lecture d'état** (`bash scripts/ciel_game/state.sh [--watch|--raw]`) :
- `--watch` : affichage temps réel (0.5s), `--raw` : JSON brut, sinon résumé formaté.

**Lancement** : `bash scripts/ciel_game/launch.sh`

### 3.7 Tests automatisés (racine)
- **`test_combat.gd`** — `SceneTree`, tests : load stats, calculateur, soin, mort,
  victoire, soutien, triangle. Sortie `X OK / Y ÉCHECS`, exit code 0/1.
- **`test_map.gd`** — `SceneTree`, tests : MapData (grille 16×10 = 160 cellules),
  terrain (GRASS→WALL/PIT), hauteurs, chargement de scènes.

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
- [ ] **Arbre de compétences passives/actives** par classe (contre-attaque, affinité terrain…).
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
- [ ] **Économie entre chapitres** : boutique, recrutement, soins. *(l'or est déjà
      gagné et persisté ; il ne se dépense pas encore)*
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
- [ ] **M2 — Hotseat (local, 2 joueurs sur la même machine)** : mode "écran partagé" où
      deux humains s'affrontent en alternant les tours avec le même contrôleur input.
- [ ] **M3 — Réseau peer-to-peer (invitation par code)** : Godot `ENetMultiplayerPeer`,
      l'hôte crée une partie et obtient un **code court** (ex. 4-6 caractères) ; les amis
      la rejoignent en saisissant le code. Sync de l'état du niveau, tournant côté hôte.
- [ ] **M4 — Gestion de partie simple** : écran "Créer une partie" (génère le code + choisir
      la carte) et "Rejoindre" (saisir le code). Écran d'attente joueurs, choix des équipes.
- [ ] **M5 — CielIA vs un ami en réseau** : l'hôte peut laisser le camp adverse à Ciel
      (pont JSON rapatrié côté hôte) pendant qu'un humain distant rejoint.
- [ ] **Règles réseau** : autorité de l'hôte pour la résolution de combat, validation des
      actions coté hôte, gestion de reconnexion/desync.

### 📦 P2 — Installateur & distribution (jouer simplement)
> Objectif : un joueur peut lancer le jeu sans installer/télécharger Godot ni configurer quoi que ce soit.
- [x] **Export Godot** : `export_presets.cfg` versionné (macOS / Windows / Linux) +
      `scripts/build/export.sh`. *Nécessite les modèles d'export Godot 4.3 installés.*
- [ ] **Packaging natif** : build signée + `.dmg`/installeur Windows automatisés.
      *(procédure `create-dmg` documentée dans `docs/INSTALL.md`, pas encore scriptée)*
- [ ] **Installateur** : raccourci posé automatiquement (Inno Setup / AppImage).
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

Les 8 étapes de la première passe sont livrées (2026-08-03) — voir §7. La suite :

1. **M2 — Hotseat** : partager les contrôles entre deux humains locaux (le contrôleur
   `LOCAL_PLAYER` côté adverse est déjà reconnu, il retombe sur l'IA locale).
2. **M3/M4 — Réseau par code** : `ENetMultiplayerPeer`, écrans Créer/Rejoindre
   (`GameSession.generate_join_code()` est déjà là), autorité de l'hôte.
3. **Économie entre chapitres** : dépenser l'or (boutique, recrutement, soins).
4. **Arbre de compétences** par classe (P1, seul point de gameplay FE non entamé).
5. **Packaging** : automatiser `.dmg` / installeur Windows par-dessus l'export.
6. **Choix du terrain en préparation** (le bonus DÉF/RÉS est déjà actif en combat).

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

**Tests** (tous verts) :

```bash
godot --headless --path . --script test_combat.gd    # 23 OK — combat FE
godot --headless --path . --script test_map.gd       # ALL TESTS PASSED
godot --headless --path . --script test_features.gd  # 95 OK — logique des nouvelles features
godot --headless --path . --script test_battle.gd    # 21 OK — intégration campagne + pont
```

> ⚠️ Limite connue : en `--headless`, le rendu factice empêche la création des
> collisions de tuiles → un tour de combat complet ne peut pas être simulé sans
> fenêtre. `test_battle.gd` vérifie donc tout ce qui précède le premier tour
> (chargement, déploiement, export d'état, rejet des ordres) ; le combat lui-même
> se teste manuellement ou via `test_combat.gd` (logique pure).
