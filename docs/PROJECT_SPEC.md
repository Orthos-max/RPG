# Project Spec — Godot Tactical RPG (CielAI)

> **Document de cap.** Décrit ce que le jeu **est** aujourd'hui et ce qu'il doit **devenir**.
> Servira de référence à Claude Code pour implémenter les prochaines features.
> Dernière mise à jour : 2026-08-05 (caméra du jeu : cadrage « Awakening » en bataille)

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
    campaign/    → chapitres, objectifs, contenu de campagne, plan de déploiement
    net/         → seat_registry (places gardées), reconnect_plan (retour de l'invité)
  modules/     → nœuds Godot (gameplay et écrans)
    tactics/     → level, arena, participants, pawn, camera, controls
    ai/          → ciel_ai.gd (pont, autoload)
    campaign/    → chapter_runner (roster + objectif), deployment_phase (placement)
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
fe_2d/           → prototype 2D abandonné (voir backlog)
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
- **`camera.gd`** — caméra tactics (pan/zoom/rotation, focus sur pions), cadrée
  sur le plateau à l'ouverture d'une bataille par **`framing.gd`**
  (`data/models/view/camera/tactics/`) : orthographique, inclinaison fixe.
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
  soutien, triangle. *(31 assertions)*
- **`test_map.gd`** — MapData (grille 16×10), terrains, hauteurs, chargement.
- **`test_features.gd`** — validation des ordres, IA locale, croissances,
  promotions, efficacité, objets, compétences, objectifs (dont la prise de point),
  sauvegarde, économie, difficulté, session, codes réseau, reconnexion,
  déploiement, annulation de déplacement, fiche d'unité, cartes du joueur,
  annulation dans l'éditeur. *(361 assertions)*
- **`test_battle.gd`** — intégration : titre → campagne → chapitre chargé →
  placement des unités → état exporté → ordre rejeté → sauvegarde → chapitre à
  prise de point, carte du joueur dessinée puis jouée. *(54 assertions en
  headless, davantage fenêtre ouverte — le placement demande des collisions de
  tuiles)*
- **`test_net.gd`** + `scripts/test_net.sh` — transport réseau à deux processus,
  coupure réelle et reconnexion comprises.
- **`shot.gd`** — *pas un test : des yeux.* Ouvre une vraie fenêtre, va jusqu'à
  l'écran demandé (`title`, `battle`, `editor`), pose une caméra d'observation
  orthographique et enregistre une image. C'est le seul moyen de juger le rendu,
  que `--headless` ne dessine pas. `godot --path . --resolution 1600x900
  --script shot.gd -- battle sortie.png free`

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
- [x] **Étoffer le contenu** : 6 chapitres, et les deux objectifs restés sans carte
      sont joués. « Prise de point » : `ObjectiveDB.is_seized` (règle pure, preneur
      nommable), `ChapterRunner` reporte la case de chaque unité et colore le point,
      `ai_state.json` gagne `objective_point` pour que Ciel sache quoi défendre
      (chapitres 4 et 5). « Protéger » : voir ci-dessous (chapitre 6).
- [x] **Objectif « protéger » et unités imposées** : un chapitre déclare ses
      `required_units` — déployées quoi qu'il arrive, verrouillées à l'écran de
      préparation, remises en place si la sélection les oublie, et cessant d'être
      exigées si l'unité tombe en mort permanente. Deux corrections de sémantique :
      un camp vide ne vaut pas une protégée perdue (au premier frame, personne n'est
      encore en scène), et disparaître vaut tomber (le pion mort quitte la scène).
- [x] **Choix des cases de déploiement** : `DeploymentPlan` (règle pure — cases
      ouvertes, occupation, échange de deux unités) + `DeploymentPhase` (tuiles
      surlignées, clic unité puis case, bataille suspendue jusqu'à confirmation).
      Un chapitre peut déclarer sa zone (`deploy_tiles`) ; sinon c'est le voisinage
      de la ligne de départ. *L'étape ne s'ouvre pas en `--headless` : sans rendu,
      les tuiles n'ont pas de collision et un pion ignore où il se tient.*

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
- [x] **M5 — CielIA vs un ami en réseau** : trois camps dans une même bataille
      (joueur local, invité distant, Ciel). `TeamData.Side.GUEST`, ordre de jeu et
      camps hostiles fournis par `GameSession` ; la boucle de tour itère sur les camps
      au lieu de tester « joueur ou adversaire ». Aucune carte n'ayant de troisième
      armée, `ArmySplit` cède la moitié des pions adverses à l'invité — un pion sur
      deux, de façon déterministe, donc identique sur les deux machines sans échange.
      Chacun pour soi. Case à cocher dans « Créer une partie ».
      *Reste à faire : le vérifier sur deux vraies machines (même limite que ci-dessous).*
- [x] **Règles réseau** : autorité de l'hôte (il seul simule), validation de chaque
      ordre reçu, reprise par l'IA locale si l'invité part.
- [ ] **Vérifier une partie en ligne sur deux vraies machines** ⚠️ *(la seule brique
      livrée sans preuve de bout en bout)* : `scripts/test_net.sh` couvre le
      transport (code, connexion, diffusion d'état, relais d'ordre, acquittement),
      mais le déroulé d'une bataille à deux n'a jamais tourné — le mode headless ne
      crée pas les collisions de tuiles. À faire fenêtre ouverte, deux instances.
      Points à surveiller : fidélité du miroir après un déplacement, ordre des
      ordres pendant une animation, fin de tour vue des deux côtés.
- [x] **Reconnexion en cours de partie** : la place d'un invité coupé lui reste
      gardée 90 s (`SeatRegistry`, côté hôte) pendant que l'IA locale tient le
      siège ; l'invité retente tout seul (`ReconnectPlan` — première tentative
      immédiate, puis toutes les 3 s). Au retour, l'hôte lui rend son contrôleur
      d'origine, la carte et l'état complet (en fiable, une demi-seconde après la
      connexion : envoyé depuis le signal lui-même, le paquet se perdait). Un hôte
      qui quitte volontairement prévient, au lieu de laisser l'invité retenter 90 s.
      `scripts/test_net.sh` coupe réellement la liaison et vérifie tout le chemin.

### 📦 P2 — Installateur & distribution (jouer simplement)
> Objectif : un joueur peut lancer le jeu sans installer/télécharger Godot ni configurer quoi que ce soit.
- [x] **Export Godot** : `export_presets.cfg` versionné (macOS / Windows / Linux) +
      `scripts/build/export.sh`. *Nécessite les modèles d'export Godot 4.3 installés.*
- [x] **Packaging natif** : `scripts/build/package.sh` produit un `.dmg` (create-dmg
      ou hdiutil), un `.zip` Windows et un `.tar.gz` Linux, notice et pont CielAI
      inclus.
- [x] **Installateur Linux** : `install.sh` pose le jeu dans `~/.local` avec une
      entrée de menu.
- [x] **Installeur Windows** (Inno Setup) : `scripts/build/windows/setup.iss` — raccourcis
      menu Démarrer/bureau, entrée de désinstallation, pont `ciel_game/` inclus, version
      lue dans `project.godot`. `package.sh` compile le `.iss` si `ISCC.exe` est
      disponible (natif ou via Wine) et se rabat sur le seul `.zip` sinon.
- [x] **Construction automatisée** : `.github/workflows/windows-installer.yml` bâtit
      le `.exe` sur un runner Windows (Godot 4.3 + modèles en cache + Inno Setup) et
      publie l'artefact `Ciel-Emblem-Windows`. Premier livrable : run `31029824017`.
      *Reste à faire : exécuter l'installeur sur une vraie machine Windows.*
- [ ] **Signature & notarisation macOS** : sans elles, le premier lancement impose
      le détour « clic droit → Ouvrir » (documenté dans `INSTALL.md`). Demande un
      certificat Développeur Apple, puis `codesign/codesign=1` dans `export_presets.cfg`.
- [x] **Portabilité du pont CielAI** : `scripts/ciel_game/_paths.sh` résout le dossier
      `user://` selon l'OS, honore `CIEL_USERDATA`/`GODOT_BIN`, crée le dossier au besoin
      et retombe sur l'ancien nom de projet. Les scripts sont copiés à côté du binaire.
- [x] **Page/instructions de lancement** : `docs/INSTALL.md` (jouer, construire,
      brancher Ciel, dépannage).

### 🏅 P3 — Vision long terme (hors modes de jeu ci-dessus)
- [ ] **Sons & animations de combat** (sprites en croisade, caméra de duel).
      ⚠️ *Le côté logiciel est prêt : `SoundDB` (catalogue + traduction
      « événement de bataille → son ») et l'autoload `Audio` (bus SFX/Music/UI,
      8 voix, musiques bouclées, volumes dans `user://settings.json`) écoutent déjà
      `BattleRecorder`. **Il ne manque que les fichiers** — liste, format et
      intention de chaque son dans [`assets/audio/README.md`](../assets/audio/README.md),
      et `Audio.missing_cues()` dit lesquels manquent. Restent à coder : les
      animations de duel proprement dites.*
- [x] **Direction artistique — passe « Awakening »** : `TacticsScenery` rassemble le
      décor en un seul endroit (ciel procédural, brume, lumière rasante et
      **ombres portées** — les pions sont en `ALPHA_CUT_OPAQUE_PREPASS`, leur
      silhouette s'imprime au sol) et le grain du terrain, en bruit teinté
      projeté en coordonnées *monde* : deux cases voisines ne montrent jamais le
      même motif tout en partageant un seul matériau. Aucun asset à produire.
      L'éditeur de cartes emprunte le même décor et les mêmes matériaux.
      *Restent à faire : modèles ou sprites d'unités plus fins, et les décors
      posés sur la carte (arbres, murs, bâtiments).*
- [ ] **Version `fe_2d/`** : prototype isolé (grille isométrique dessinée en
      `_draw`, unités et stats dupliquées) — **caduc** depuis le choix de garder
      la 3D et d'en soigner le rendu. À supprimer ou à reprendre de zéro.
- [x] **Aperçu des dégâts avant d'engager** : `BattleForecast` (logique pure) met en
      forme le calculateur — dégâts totaux, nombre de coups, précision, critique, PV
      restants, létalité (sûre ou « seulement si critique »), triangle/terrain/soutien/
      efficacité/procs. Affiché par `BattleForecastPanel` au survol d'une cible à portée.
      *Le moteur ne gérant pas la riposte, la prévision n'affiche qu'un camp.*
- [x] **Polissage UX** (suite) : `PawnMoveMemory` (annulation d'un déplacement tant
      que l'unité n'a rien fait d'autre, bouton « Undo move » grisé sinon) et
      `UnitSheet` + `UnitSheetPanel` (fiche au survol : esquive, critique, vitesse
      d'attaque, arme, portée, et le bonus du terrain occupé — jusque-là calculé en
      combat sans jamais s'afficher avant d'engager).
- [x] **Mods / éditeur de niveau intégré** : `MapDocument` (terrain, hauteurs, armées,
      zone de déploiement, objectif + validation « pourquoi cette carte n'est pas
      jouable »), `MapLibrary` (`user://maps/*.json`, lisible et échangeable),
      `CustomBattle` (la carte devient un chapitre et emprunte toute la machinerie
      existante), et l'éditeur réécrit autour du document : pinceaux, élévation,
      unités des deux camps, cases de départ, point de commandement, réglages
      d'objectif, bibliothèque, essai immédiat contre l'IA locale ou contre Ciel.
      Une carte d'essai ne touche jamais à la campagne.
- [x] **Annulation et redimensionnement dans l'éditeur** : `MapHistory` (pile
      d'instantanés du document — annuler défait *un geste*, y compris ceux qui
      en entraînent d'autres, comme noyer une case de départ occupée), boutons
      ↶/↷ et raccourcis Ctrl+Z / Ctrl+Maj+Z, et la grille se redimensionne depuis
      les réglages — `MapDocument.resize()` dit ce qu'il a fallu jeter (unités,
      cases de départ, point de commandement hors grille) au lieu de le laisser
      disparaître en silence.
      *Restent ouverts sur l'éditeur : un roster figé de 9 unités sans réglage de
      niveau, aucun import/export dans l'interface (le JSON se copie à la main),
      et rien n'est encore prouvé fenêtre ouverte — toute la preuve est headless.*


---

## 4bis. Brief — Installeur Windows (Inno Setup)

> **Ajouté le 2026-08-04.** À transmettre à Claude Code tel quel.
> Objectif : produire un `.exe` d'installation Windows avec Inno Setup 6.

### ✅ État réel au 2026-08-05 (mesuré, pas supposé)

**La chaîne produit un installeur.** Le blocage de la veille — ni modèles
d'exportation, ni compilateur Inno Setup sur la machine de développement — est levé
en déplaçant la construction sur un runner Windows, qui apporte les deux :
[`.github/workflows/windows-installer.yml`](../.github/workflows/windows-installer.yml).

| Maillon | État |
|---|---|
| `scripts/build/windows/setup.iss` | ✅ Complet — GUID stable, FR/EN, raccourcis, désinstallation qui **préserve les sauvegardes** de `%APPDATA%` |
| `scripts/build/package.sh` | ✅ Prépare le staging, convertit l'icône, appelle ISCC |
| `export_presets.cfg` → `Windows Desktop` | ✅ Présent |
| Modèles d'exportation Godot 4.3 | ✅ Installés par la CI (mis en cache entre les runs) |
| Compilateur Inno Setup (`ISCC`) | ✅ Fourni par l'image `windows-latest` |
| Livrables | ✅ Run `31029824017` — `Ciel-Emblem-Setup-0.1.0.exe` (22 Mo) et `CielEmblem-0.1.0-windows.zip` (29 Mo), contenu vérifié : exe, `.pck`, pont `ciel_game/`, notice |

Trois incompatibilités que seule une vraie machine Windows pouvait révéler, toutes
corrigées : Git Bash ne fournit pas `zip` (repli sur `Compress-Archive`) ; ISCC et
Godot refusent les chemins POSIX `/d/a/…` (traduits par `cygpath`) ; `ISCC_PATH`
n'était honoré que dans la branche Wine.

**Reste la seule dette : lancer l'installeur sur une machine Windows** —
installation, raccourcis, lancement, et surtout une désinstallation qui laisse
`%APPDATA%\Godot\app_userdata\Ciel Emblem\` intact.

### Contexte

Le projet a déjà :
- `export_presets.cfg` avec une cible `Windows Desktop` (`windows_desktop`)
- `scripts/build/export.sh` qui lance l'export Godot pour Windows
- `scripts/build/package.sh` qui produit un `ciel-emblem-windows.zip` contenant le `.exe` + `.pck` + le dossier `ciel_game/` (pont CielAI)

Ce qu'il manque : transformer ce `.zip` en installeur `.exe` qui pose tout proprement avec un assistant graphique, un raccourci dans le menu Démarrer, et une entrée de désinstallation.

### À faire

Créer un script Inno Setup (`setup.iss`) dans `scripts/build/windows/` qui :

1. **Prend en entrée** le contenu du `.zip` Windows (le dossier décompressé produit par `package.sh`).
2. **Installe dans** `{autopf}\Ciel Emblem` (Program Files), avec fallback `{userpf}` si pas admin.
3. **Crée** :
   - Un raccourci dans le menu Démarrer (`Ciel Emblem` → `Ciel Emblem.lnk`)
   - Un raccourci sur le bureau (case à cocher, cochée par défaut)
   - Une entrée de désinstallation dans « Ajout/Suppression de programmes »
4. **Inclut** tout le dossier `ciel_game/` à côté de l'exécutable (même structure que le `.zip`).
5. **Nom du livrable** : `Ciel-Emblem-Setup-<version>.exe`

### Fichiers à créer / modifier

| Fichier | Action |
|---|---|
| `scripts/build/windows/setup.iss` | **Créer** — le script Inno Setup complet |
| `scripts/build/package.sh` | **Modifier** — ajouter une étape qui, si Inno Setup est disponible (via Wine sur macOS, ou natif Windows), compile le `.iss` et produit le `.exe` final |
| `docs/INSTALL.md` | **Modifier** — remplacer le TODO « Installeur Windows » par les instructions d'installation réelles |

### Notes techniques

- L'exécutable Godot exporté s'appellera `Ciel Emblem.exe` (tel que défini dans `export_presets.cfg` → `windows_desktop`).
- **Icône :** vérifier dans `export_presets.cfg` si `application/icon` pointe vers un `.ico`. Si oui, le réutiliser pour l'installeur. Sinon, utiliser l'icône par défaut de l'exe (Inno Setup peut l'extraire).
- **Inno Setup 6** est gratuit : `winget install JRSoftware.InnoSetup` ou téléchargement sur [jrsoftware.org](https://jrsoftware.org/isinfo.php).
- **Version :** lire le numéro de version depuis `project.godot` (`config/version`, actuellement `0.1.0`) pour le passer au `.exe` de sortie.
- **Sur macOS :** Wine peut exécuter le compilateur Inno (`ISCC.exe`). `package.sh` doit détecter la plateforme et utiliser Wine si besoin.
- **Désinstallation propre :** tout ce qui est installé (dossier `Ciel Emblem`, raccourcis) doit être supprimé. Les saves (`user://`) restent dans `%APPDATA%\Ciel Emblem` et ne sont pas touchées.

### Template de base pour `setup.iss`

```iss
#define MyAppName "Ciel Emblem"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "CielAI"
#define MyAppExeName "Ciel Emblem.exe"

[Setup]
AppId={{...GUID...}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=..\..\..\build
OutputBaseFilename=Ciel-Emblem-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\..\build\windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
```

> ⚠️ **À faire par Claude :** générer un GUID unique pour `AppId` (commande PowerShell : `[guid]::NewGuid()`).

### Vérification

Après implémentation, lancer `scripts/build/package.sh` et vérifier que :
- Un `Ciel-Emblem-Setup-0.1.0.exe` est produit dans `build/`.
- L'installeur s'exécute (tester dans une VM Windows ou via Wine).
- Le jeu se lance depuis le menu Démarrer.
- La désinstallation nettoie tout.

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

Les passes du 2026-08-04 ont livré la reconnexion réseau, les deux objectifs de
chapitre restés sans carte, le choix des cases de déploiement, le polissage UX,
la préparation du système sonore, et l'éditeur de cartes — complété depuis par
l'annulation et le redimensionnement.
**Backlog : 44 items faits, 4 restants.** Ordre conseillé pour la reprise —
classé par ce que ça rapporte au projet, pas par facilité :

### ✅ 1. La grille en données — première moitié faite (2026-08-05)

`BattleGrid` ([`data/models/world/map/battle_grid.gd`](../data/models/world/map/battle_grid.gd))
répond désormais aux deux questions qui gouvernent la tactique — **qui est à côté
de qui**, **cette case est-elle occupée** — par de l'arithmétique sur des
coordonnées, sans moteur physique. Il se bâtit depuis les tuiles réellement en
scène, ce qui couvre aussi les chapitres écrits à la main, sans `MapData`.

Vérifié en headless (`test_battle.gd`) : l'index couvre les 160 cases, s'accorde
avec l'ancienne conversion **sur les 160 tuiles**, retrouve chaque pion sur sa
case, et **calcule une portée de déplacement sans fenêtre** (40 cases pour 5 points
de mouvement, aucune au-delà). `TacticsGrid` — la conversion que parle le pont
CielAI — passe par l'index quand il existe : une seule formule, et une
consultation directe au lieu d'un balayage de toutes les tuiles.

Ce qui reste de l'ancien monde :
- `pf_root` / `pf_distance` vivent toujours sur les nœuds `StaticBody3D` ; le
  parcours est juste, mais son état s'accroche encore à la scène.
- Le repli sur `tile_raycasting.tscn` subsiste dans `TacticsTile`, pour les tuiles
  hors index. À supprimer une fois la parité prouvée fenêtre ouverte (§6.2).
- `TacticsPawn.get_tile()` reste un rayon vers le bas.

### 🥇 1bis. La grille en données (le refactor qui débloque le reste)

Aujourd'hui, « qui est à côté de qui » et « cette case est-elle occupée » se
répondent par des **rayons 3D** (`tile_raycasting.tscn`, `TacticsTile.get_neighbors()`,
`get_tile_occupier()`), et le pathfinding accroche son état (`pf_root`, `pf_distance`)
sur des nœuds `StaticBody3D`. Trois conséquences déjà payées :

- **Aucun tour de combat complet n'est testable en headless** — la limite connue
  documentée plus bas vient précisément de là.
- Des règles pures irréprochables (`MapDocument`, `ObjectiveDB`, `DeploymentPlan`)
  posées sur un cœur de déplacement qui, lui, exige une scène 3D montée.
- Tout changement de rendu bute dessus.

`MapData` contient déjà le nécessaire. Ce n'est pas une réécriture : déplacer
l'adjacence et l'occupation dans la donnée, et laisser les tuiles ne faire que de
l'affichage.

### 🥈 2. Prouver une bataille fenêtre ouverte

`shot.gd` a démontré qu'on peut lancer une vraie fenêtre avec collisions et rendu.
La suite : un `test_window.gd` qui joue **un tour complet** — sélection, déplacement,
attaque, mort. C'est le plus gros trou de preuve du projet, et il n'est ouvrable que
depuis l'arrivée de cet outil. Plus facile après le point 1 ; plus prudent avant.

### 🥉 3. Finir la route artistique

| Étape | Pourquoi |
|---|---|
| ✅ **La caméra du jeu** — orthographique, inclinaison fixe, posée sur le plateau (2026-08-05) | Fait : [`framing.gd`](../data/models/view/camera/tactics/framing.gd). Voir le journal ci-dessous |
| **Décors posés sur les cases** — arbres sur la forêt, rochers sur la montagne, créneaux sur les murs | Ce qui sépare « un damier teinté » d'« un champ de bataille ». Formes simples, sans artiste |
| **Retravailler le surlignage de portée** | Les matériaux de portée remplacent le terrain d'un bloc : ils sont restés plats alors que tout le reste a gagné du grain |

### 4. Supprimer `fe_2d/`

1 074 lignes de code mort qui **dupliquent les règles** (ses propres unités, ses
propres stats) et contredisent la direction prise. Le garder, c'est entretenir un
piège pour la prochaine personne qui ouvre le dépôt.

### 5. Aligner les noms sur le lore

*À ne pas entamer avant que le lore soit posé (document écrit par Aurèle et sa
compagne).* Les héros s'appellent encore Chrom, Lissa, Frederick. Ce ne sera pas
qu'un renommage : les identifiants de sauvegarde, la cible du chapitre 2 et les
`required_units` du chapitre 6 en dépendent — et chaque jour d'attente ajoute des
sauvegardes à migrer. La table de correspondance et le chemin de migration peuvent
être préparés d'avance.

### 6. Les deux dettes de vérification (matériel requis)

- ⚠️ **Partie en ligne sur deux vraies machines.** Toujours la seule brique livrée
  sans preuve de bout en bout, et la reconnexion y a ajouté du chemin.
- 🔨 **Installeur Windows exécuté.** La chaîne produit désormais un `.exe` (§4bis) ;
  il reste à l'installer, le lancer et le désinstaller sur une machine Windows.

### 7. Confort de l'éditeur de cartes

Roster figé à 9 unités sans réglage de niveau, aucun import/export dans l'interface
(le JSON se copie à la main). Utile, nettement moins urgent que ce qui précède.

### 8. Le reste

🔊 **Fichiers audio** — tout est branché et attend :
[`assets/audio/README.md`](../assets/audio/README.md) donne la liste, le format et
l'intention de chaque son ; `Audio.missing_cues()` dit lesquels manquent. Ensuite
seulement, les **animations de duel**. Puis la **signature macOS** (certificat Apple).

> **Si l'on ne devait en faire que trois** : le refactor de la grille (1), le tour
> complet prouvé fenêtre ouverte (2), et la caméra du jeu (3, première ligne). Les
> deux premiers assainissent le cœur ; le troisième est ce qu'on voit dès le
> lancement.

---

## 7. Journal d'implémentation

> **État de vérification au 2026-08-04.** Sont prouvés par des tests automatiques :
> le combat et ses règles, la validation des ordres, l'IA locale, la campagne et sa
> sauvegarde, l'économie, les compétences, le transport réseau **et la reconnexion
> après coupure réelle**. Sont prouvés fenêtre ouverte, par `test_battle.gd` : le
> chargement d'un chapitre, le placement des unités, la case à prendre. Sont
> prouvés à la main : un tour d'IA locale complet, un aller-retour d'ordres avec
> Ciel (sélection → déplacement réel → rejet d'un ordre illégal → fin de tour), le
> hotseat et le salon en ligne. **N'est pas encore prouvé : une bataille complète
> en réseau entre deux machines, ni une prise de point jouée jusqu'à la victoire.**

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
godot --headless --path . --script test_combat.gd    # 31 OK — combat FE
godot --headless --path . --script test_map.gd       # ALL TESTS PASSED
godot --headless --path . --script test_features.gd  # 361 OK — logique des features
godot --headless --path . --script test_battle.gd    # 54 OK — intégration campagne + pont
bash scripts/test_net.sh                             # transport réseau, 2 processus
```

> ⚠️ Limite connue : en `--headless`, le rendu factice empêche la création des
> collisions de tuiles → un tour de combat complet ne peut pas être simulé sans
> fenêtre. `test_battle.gd` vérifie donc tout ce qui précède le premier tour
> (chargement, déploiement, export d'état, rejet des ordres) ; le combat lui-même
> se teste fenêtre ouverte ou via `test_combat.gd` (logique pure). Même limite
> côté réseau : `scripts/test_net.sh` couvre le transport (code, connexion,
> diffusion d'état, relais d'ordre), pas le déroulé d'une bataille à deux.

### Passe du 2026-08-04 — reconnexion, prise de point, déploiement

| Livré | Où |
|---|---|
| Reconnexion en cours de partie (place gardée, retour automatique, resynchro) | `seat_registry.gd`, `reconnect_plan.gd`, `net_service.gd`, `net_mirror.gd` |
| Objectif « prise de point » joué de bout en bout + `objective_point` pour Ciel | `objective.gd`, `chapter_runner.gd`, `ciel_ai.gd`, `tactics_tile.gd` |
| Chapitres 4 et 5, écrits dans l'univers de `LORE.md` | `campaign_db.gd` |
| Choix des cases de déploiement avant la bataille | `deployment_plan.gd`, `deployment_phase.gd` |
| Annulation d'un déplacement + fiche d'unité au survol | `move_memory.gd`, `unit_sheet.gd`, `unit_sheet_panel.gd`, `selection.gd` |
| Objectif « protéger » + unités imposées au déploiement | `objective.gd`, `campaign_state.gd`, `prep_screen.gd`, `campaign_db.gd` |
| Système sonore prêt à recevoir ses fichiers | `sound_db.gd`, `audio_service.gd`, `assets/audio/README.md` |
| Éditeur de cartes : dessiner, poser, enregistrer, jouer | `map_document.gd`, `map_library.gd`, `custom_battle.gd`, `map_editor_*.gd` |
| Annuler / rétablir et redimensionner dans l'éditeur | `map_history.gd`, `map_document.gd`, `map_editor_level.gd`, `map_editor_ui.gd` |
| Ciel, ombres portées et grain du terrain (bataille + éditeur) | `tactics_scenery.gd`, `tactics_config.gd`, `tactics_level.gd` |
| Capture d'écran automatisée — juger le rendu sans jouer | `shot.gd` |

Trois choix structurants de cette passe :

* **L'IA locale ne prend plus le camp d'un absent, elle le garde.** Le contrôleur
  d'origine est mémorisé avec la place et rendu tel quel au retour — sans ça, un
  invité revenu aurait récupéré un camp devenu « IA locale » dans la session.
* **L'état de reprise ne voyage pas comme la diffusion courante.** Celle-ci est un
  flux qu'un paquet perdu n'abîme pas ; l'instantané de reprise est l'unique
  paquet qui remet le revenant dans la bataille, il part donc en fiable — et une
  demi-seconde après la connexion, faute de quoi il se perd (constaté à deux
  processus : émis depuis le signal `peer_connected`, il n'arrivait jamais).
* **Poser une unité sur une case occupée échange les deux.** C'est le geste
  attendu quand on réarrange une ligne de départ ; refuser obligerait à vider une
  case avant d'en remplir une autre.

**Tests** (tous verts) :

```bash
godot --headless --path . --script test_combat.gd    #  31 OK — combat FE
godot --headless --path . --script test_map.gd       # ALL TESTS PASSED
godot --headless --path . --script test_features.gd  # 258 OK — logique des features
godot --headless --path . --script test_battle.gd    #  30 OK — intégration (36 fenêtre ouverte)
bash scripts/test_net.sh                             # transport + reconnexion, 2 processus
```

---

### Passe du 2026-08-05 (2) — la caméra du jeu

Le cadrage « Awakening » n'existait que dans `shot.gd`, l'outil de capture. En
jeu, une bataille s'ouvrait sur ceci : du ciel, et un coin de plateau en bas à
droite. Mesuré avant de corriger — trois causes distinctes, pas une.

| Livré | Où |
|---|---|
| Le cadrage devient un module : centre et étendue du plateau **mesurés sur les tuiles**, projection, inclinaison, bornes de zoom | `data/models/view/camera/tactics/framing.gd` |
| Une bataille pose la caméra sur son plateau à l'ouverture, par signal | `tactics_level.gd`, `t_cam_res.gd`, `camera.gd` |
| Le zoom agit sur `size` en orthographique, sur `fov` en perspective | `service/zoom.gd`, `service/t_cam_serv.gd` |
| Le panoramique de bord n'obéit plus à un curseur qui ne commande rien | `service/panning.gd` |
| L'inclinaison ne bouge plus au regard libre | `service/rotation.gd` |
| Le cadrage se vérifie en headless — calcul pur et fuite de la vue | `test_map.gd`, `test_battle.gd` |

**Les trois causes, mesurées :**

1. **Aucun cadrage.** La caméra vit dans `main.tscn` et survit aux niveaux : elle
   entrait en bataille là où l'écran précédent l'avait laissée, avec un rayon de
   déplacement centré sur l'origine du monde plutôt que sur la carte.
2. **Le panoramique de bord obéissait à un curseur hors fenêtre.** Le seuil
   testait `mouse_pos.x <= 1`, vrai aussi pour des coordonnées négatives : souris
   sortie du jeu, la caméra partait toute seule jusqu'à sa limite. Sans écran,
   le serveur d'affichage rend (0,0) — un ordre permanent, et la raison pour
   laquelle aucun test headless n'avait jamais pu regarder où pointait la vue.
3. **Projection perspective.** Le zoom écrivait dans `fov` ; en orthographique
   cette propriété ne fait rien, il fallait donc que le zoom sache sur laquelle
   des deux travailler.

Deux choix structurants :

* **Le plateau se mesure, il ne se déclare pas.** Le centre et l'étendue viennent
  des tuiles réellement en scène, pas de `MapData` — les chapitres écrits à la
  main n'en ont pas, et ce sont justement ceux dont le centre n'est pas
  l'origine. `camera_boundary_radius`, écrit à la main dans deux scènes, était
  juste pour la carte qui l'avait reçu et faux pour les cartes du joueur : il
  passe à 0 (mesure) et reste disponible comme choix explicite de chapitre.
* **L'inclinaison est fixe, y compris au regard libre.** La relever aplatit le
  damier jusqu'à un plan de dessus où toutes les cases se ressemblent — c'est ce
  que le cadrage cherche à éviter. Le regard libre fait tourner, il ne relève
  plus.

`shot.gd` remettait une cible à la caméra avant chaque capture, faute de quoi il
photographiait le vide. Le contournement est retiré : l'outil montre de nouveau
ce que voit un joueur.

**Tests** (tous verts) :

```bash
godot --headless --path . --script test_combat.gd    #  31 OK
godot --headless --path . --script test_map.gd       # ALL TESTS PASSED (+ cadrage, calcul pur)
godot --headless --path . --script test_features.gd  # 374 OK
godot --headless --path . --script test_battle.gd    #  68 OK (+ 7 sur le cadrage)
bash scripts/test_net.sh                             # transport + reconnexion, 2 processus
```

Le test du cadrage a été vérifié capable d'échouer : correctif du panoramique
retiré, `test_battle.gd` tombe à 66 OK / 2 ÉCHECS et nomme la fuite.
