# Project Spec — Godot Tactical RPG (CielAI)

> **Document de cap.** Décrit ce que le jeu **est** aujourd'hui et ce qu'il doit **devenir**.
> Servira de référence à Claude Code pour implémenter les prochaines features.
> Dernière mise à jour : 2026-08-05 (caméra, décor, retour de jeu, chasse aux bugs)

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
  maps/          → niveaux (map_level et outpost_level engendrés depuis MapData ;
                   test_level, dernière arène sculptée, gardée comme cas d'essai)
  textures/      → actor, mob, ui
docs/            → PROJECT_SPEC, CIEL_PROTOCOL, INSTALL
scripts/
  ciel_game/     → PONT CielAI (_paths, launch, command, state)
  build/         → export.sh, package.sh
  test_net.sh    → test réseau à deux processus
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
- **`tactics_tile.gd`** — tuiles : terrain, surlignage, ce qu'elles affichent.
  Elles ne portent plus d'état de parcours depuis le 2026-08-07.
- **`battle_grid.gd`** + **`path_field.gd`** (`data/models/world/map/`) — la grille
  et le parcours **en données** : adjacence, occupation, distances, chemins,
  tout sans moteur physique ni fenêtre.
- **`tactics_participant.gd`** / **`tactics_player.gd`** / **`tactics_opponent.gd`** — participants.
- **`pawn.gd`** — unité sur la grille.
- **`support_tracker.gd`** — suivi des soutiens en session.
- **`props.gd`** (`data/models/view/scenery/`) — décor posé sur les cases :
  arbres, rochers, créneaux. Procédural, sans collision, déterministe.
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
      → état CielAI `terrain`/`terrain_def`) **et choisi en préparation** : `ChapterMap`
      lit la carte du chapitre sans monter la bataille, l'écran de préparation montre
      la zone de déploiement case par case avec son terrain, et `ChapterRunner` pose
      les pions sur la case retenue — y compris en headless.
- [x] **Inventaire limité** par unité (`ItemDB`, 5 emplacements, consommables + toniques).
- [x] **Armes nommées et menu d'équipement** : `WeaponDB` (14 armes — puissance,
      portée, précision, critique, poids, prix), fourreau de 3 armes par unité,
      arme en main appliquée aux stats (`Stats.equip`), armurerie à l'intendance
      et menu d'équipement à l'écran de préparation. Le poids amorti par la force
      décide du second coup : la plus grosse arme n'est pas toujours la bonne.
- [x] **Riposte** : `FECombatCalculator.calculate_exchange` résout un échange
      complet — assaut, riposte de la cible si elle tient encore debout, son arme
      engage un combat et l'assaillant est à sa portée, puis un second coup pour le
      plus rapide des deux. Un archer pris au contact ne rend rien (portée minimale),
      un bâton non plus. L'assaillant peut mourir de son propre assaut.
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
- [x] ~~**M2 — Hotseat (local, 2 joueurs sur la même machine)**~~ — **retiré le
      2026-08-06** : personne ne s'en servait. Ce qu'il avait apporté reste et
      sert au réseau — les actions humaines remontées dans `TacticsParticipant`,
      la boucle de tour qui prend le camp en paramètre, le bandeau « à qui de
      jouer ». Seuls le mode, son bouton et son entrée de menu ont disparu ; la
      valeur 2 de `GameSession.Mode` reste vacante, elle voyage jusqu'à Ciel.
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
- [x] ~~**Signature & notarisation macOS**~~ — **abandonné le 2026-08-08, décision
      d'Aurèle** : le certificat Développeur Apple coûte 200-600 €/an et il ne le
      prendra pas. Conséquence assumée : sur macOS, le premier lancement impose le
      détour « clic droit → Ouvrir », déjà documenté dans `INSTALL.md`. Ne plus le
      remonter comme une dette — c'en est le prix, pas un oubli. Windows, la
      plateforme sur laquelle Aurèle joue, n'est pas concerné.
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
- [x] **Version `fe_2d/`** : **supprimée le 2026-08-06**. Prototype isolé (grille
      isométrique en `_draw`, unités et stats dupliquées), caduc depuis le choix
      de la 3D, et cassé depuis le refactor de la grille : son `class_name
      BattleGrid` entrait en collision avec la vraie grille de bataille, si bien
      que le bouton « Prototype 2D » de l'écran-titre menait à un écran inerte.
      1 074 lignes qui dupliquaient les règles du jeu, et le piège qui allait
      avec : corriger un bug de combat au mauvais endroit.
- [x] **Aperçu des dégâts avant d'engager** : `BattleForecast` (logique pure) met en
      forme le calculateur — dégâts totaux, nombre de coups, précision, critique, PV
      restants, létalité (sûre ou « seulement si critique »), triangle/terrain/soutien/
      efficacité/procs. Affiché par `BattleForecastPanel` au survol d'une cible à portée.
      Depuis la riposte, **les deux camps sont annoncés** : dégâts rendus, précision,
      PV restants de l'assaillant, létalité — et la raison quand la cible ne peut
      pas riposter.
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
La passe du 2026-08-06 a livré les quatre features de jeu qui restaient
codables : la **riposte**, le **menu d'équipement d'armes**, le **choix du terrain
en préparation** et le **menu d'actions en français**.
La passe du 2026-08-07 a livré les quatre derniers chantiers codables : la
**carte du chapitre 2 rendue présentable**, le **placement et le tour adverse
prouvés à la souris**, la **grille en données achevée**, et le **confort de
l'éditeur de cartes**.
La passe du 2026-08-08 a posé la **charte graphique** (§6bis) : le jeu n'avait
aucun thème et tombait donc sur celui de Godot pour tout ce qui n'était pas un
bouton.

**Backlog : 47 items faits, 1 abandonné, 2 restants.** La signature macOS est
**abandonnée** (décision d'Aurèle du 2026-08-08 : il ne paiera pas le certificat
Apple). Restent la partie en ligne sur deux machines et les fichiers audio +
animations de duel — **bloqués hors du code** : ils demandent du matériel ou des
fichiers son.

**Deux chantiers sont en attente par choix d'Aurèle, pas par blocage :**
- **Les cartes des chapitres 1, 3, 4, 5, 6.** Cinq chapitres sur six pointent
  encore sur `map_level.tscn` (`campaign_db.gd`) ; seul le chapitre 2 a la
  sienne. Codable — la recette est prouvée (`outpost_map.tres` →
  `outpost_arena.tres` → `outpost_level.tscn`) — mais reporté le 2026-08-08.
- **Les noms du lore.** `docs/LORE.md` nomme les protagonistes (Ciel, Luna,
  Patriot, Aldric) mais son §10 laisse le roster jouable « à définir ». Seule la
  machinerie de migration des sauvegardes est préparable d'avance.

Ordre conseillé pour la reprise — classé par ce que ça rapporte au projet, pas
par facilité :

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

**Seconde moitié faite le 2026-08-07.** Il ne reste rien de l'ancien monde :

- `pf_root` / `pf_distance` ont quitté les nœuds `StaticBody3D` pour
  [`path_field.gd`](../data/models/world/map/path_field.gd), indexé par
  coordonnée. `TacticsTile` ne garde que ce qu'elle dessine (`reachable`,
  `attackable`, `hover`). Le parcours s'éprouve sans monter de scène.
- Le repli sur `tile_raycasting.tscn` a disparu, scène et script compris : toute
  tuile passe par `TacticsTileService`, donc par l'index bâti dans la foulée —
  il n'y avait plus aucun cas à rattraper.
- `TacticsPawn.get_tile()` consulte l'index au lieu de lancer un rayon vers le
  bas. Le `RayCast3D` du pion est retiré de `pawn.tscn`, et le rattrapage que
  `ChapterRunner` devait faire après chaque placement (`force_raycast_update`)
  n'a plus lieu d'être.

**Un bug de fond trouvé au passage.** `BattleGrid.coord_at_position` faisait
`floori(x + 0.5)`, ce qui suppose des centres de case sur les entiers. Une carte
de largeur **paire** les met sur les demis : la frontière entre deux cases
tombait alors exactement sur le centre de l'une d'elles. Un pion arrêté à
quelques centièmes en deçà de son centre était attribué à la case précédente, et
`adjust_to_center` l'y recollait — **un déplacement de cinq cases en valait
quatre**. Invisible tant que la case se lisait au rayon. La grille compte
désormais les cases depuis une tuile réelle, ce qui règle les deux parités.

### ✅ 2. Prouver une bataille fenêtre ouverte — **fait le 2026-08-06**

`test_window.gd` joue un tour complet **à la souris** : sélection d'une unité,
ouverture du menu, déplacement sur une case surlignée, attaque d'un ennemi, mort
de la cible, fin de tour. Neuf vérifications, dans une vraie fenêtre.

Le piège du clic simulé, payé une seconde fois : `Input.parse_input_event` ne
suffit pas. Sans `position` renseignée le viewport route le clic en (0,0) ; sans
`Input.warp_mouse` le rayon de sélection part de l'ancien curseur. Il faut les
deux, plus une frame entre les deux — la sélection lit
`Input.is_action_just_pressed`, qui ne vaut qu'une frame.

La suite s'ajoute au lanceur en option (`bash scripts/test_all.sh --window`) :
elle ne peut pas tourner en `--headless`, rien n'y dessine ni ne clique.

> **Ce qu'elle a appris dès son premier passage.** Une assertion « frapper ne
> rend pas de PV à l'assaillant » est tombée : 20 → 21 PV. Ce n'était pas un bug
> du jeu mais une lacune du test — achever une cible donne de l'XP, et une montée
> de niveau augmente les PV maximum. L'invariant ne tient qu'à niveau constant.

**Étendue le 2026-08-07 — seize vérifications.** Elle joue désormais aussi le
**placement d'avant-bataille** (échanger deux unités, en poser une sur une case
ouverte, tout défaire) et le **tour adverse** (rendre la main, voir l'IA locale
déplacer ses pions d'elle-même, et récupérer le tour).

Le placement se défait avant que la bataille commence, et c'est délibéré : les
étapes suivantes jouent la position de départ du chapitre, et la laisser défaite
mettait l'attaque hors de portée — le test se déclarait alors « non testable »
au lieu d'échouer, ce qui est la pire des deux issues.

Reste hors de son champ : la caméra.

### 🗂 2bis. L'argument d'origine, gardé pour mémoire

> Les trois blocages remontés par Aurèle le 2026-08-05 (échange au déploiement,
> changement d'unité, regard libre) sont **tous** passés au travers de la suite
> headless : rien n'y pilote la souris. Deux dataient d'avant. C'est le meilleur
> argument possible pour ce chantier.

`shot.gd` a démontré qu'on peut lancer une vraie fenêtre avec collisions et rendu.
La suite : un `test_window.gd` qui joue **un tour complet** — sélection, déplacement,
attaque, mort. C'est le plus gros trou de preuve du projet, et il n'est ouvrable que
depuis l'arrivée de cet outil. Plus facile après le point 1 ; plus prudent avant.

### 🥉 3. Finir la route artistique

| Étape | Pourquoi |
|---|---|
| ✅ **La caméra du jeu** — orthographique, inclinaison fixe, posée sur le plateau (2026-08-05) | Fait : [`framing.gd`](../data/models/view/camera/tactics/framing.gd). Voir le journal ci-dessous |
| ✅ **Décors posés sur les cases** — arbres, rochers, créneaux (2026-08-05) | Fait : [`props.gd`](../data/models/view/scenery/props.gd), en bataille **et** dans l'éditeur |
| ✅ **Surlignage de portée** — teinté, plus posé d'un bloc (2026-08-06) | Fait : [`tactics_scenery.gd`](../data/models/view/scenery/tactics_scenery.gd) `highlight_material()`. Le grain, la trame des cases et le terrain restent lisibles sous la teinte |
| ✅ **La carte du chapitre 2 rendue présentable** (2026-08-07) | Fait : [`outpost_map.tres`](../data/models/world/map/outpost_map.tres). Elle était plate et entièrement « en herbe » — 200 tuiles posées à la main, sans terrain déclaré, donc sans un seul décor. Devenue un `MapData` de 10 × 20 : ruines du poste avancé, rempart percé d'une brèche, montagne à l'ouest, mare, bois, chemin, et du relief |
| ✅ **Neuf terrains de plus, dont cinq bâtis** (2026-08-08) | Fait : village, fortin, porte, ruines, tour, pont, sable, neige, marais — table unique dans [`map_data.gd`](../data/models/world/map/map_data.gd), volumes dans [`props.gd`](../data/models/view/scenery/props.gd). Voir le journal du 2026-08-08 (2) |
| ⬜ **Les cartes des chapitres 1, 3, 4, 5 et 6** | Elles pointent encore sur `map_level.tscn`. C'est maintenant dessinable par Aurèle lui-même dans l'éditeur — pont court : `MapDocument.to_map_data()` |

### ✅ 4. Supprimer `fe_2d/` — fait le 2026-08-06

1 074 lignes de code mort qui dupliquaient les règles. Dossier, bouton
d'écran-titre, chargeur de scène 2D et exclusion d'export : tout est parti.
`scripts/test_all.sh` n'a plus à excluire ce dossier de sa détection d'erreurs.

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

### ✅ 7. Confort de l'éditeur de cartes — fait le 2026-08-07

- **Le roster se lit sur le disque** au lieu d'être une liste de neuf chemins
  écrite dans l'interface. Ajouter une fiche au jeu suffit désormais à la rendre
  posable — et les **personnages écrits dans l'éditeur de personnages** le sont
  aussi, pour les deux camps (rien ne dit qu'une créature de son cru soit un
  allié). Ils n'ont pas de `.tres` : le pion emprunte une fiche de départ,
  entièrement réécrite par `ChapterRunner.apply_roster_unit` une fois en scène.
- **Niveau des unités posées** (1 à 20), réglé sur le pinceau plutôt que sur la
  case : on pose six squelettes de niveau 8 sans rouvrir le panneau. Une unité
  posée au-dessus de 1 **monte réellement les échelons**, par les croissances de
  sa classe — lui écrire `level = 8` lui donnerait l'étiquette d'une vétérane et
  les statistiques d'une recrue. Le tirage est à graine fixe (nom + niveau visé),
  donc identique d'une ouverture à l'autre et sur les deux machines d'une partie
  en réseau, comme le décor.
- **Partage de cartes** : bouton « 🔗 Partager » — copier la carte dans le
  presse-papiers, la remplacer par celle du presse-papiers, exporter vers un
  fichier ou en importer un (sélecteur natif, tout le disque : une carte reçue
  d'un ami est dans les téléchargements, pas dans `user://maps/`). Le format
  d'échange est celui de l'enregistrement — pas de second format à maintenir.
  Exporter accepte un brouillon injouable, là où enregistrer le refuse : on doit
  pouvoir envoyer une carte inachevée à quelqu'un pour qu'il la finisse. Un
  import s'annule au Ctrl+Z comme n'importe quel autre geste.

### 8. Le reste

🔊 **Fichiers audio** — tout est branché et attend :
[`assets/audio/README.md`](../assets/audio/README.md) donne la liste, le format et
l'intention de chaque son ; `Audio.missing_cues()` dit lesquels manquent. Ensuite
seulement, les **animations de duel**. (La signature macOS, elle, ne viendra
jamais : voir §4, elle est abandonnée.)

> **Si l'on ne devait en faire que trois** : le refactor de la grille (1), le tour
> complet prouvé fenêtre ouverte (2), et la caméra du jeu (3, première ligne). Les
> deux premiers assainissent le cœur ; le troisième est ce qu'on voit dès le
> lancement.

---

## 6bis. La charte graphique — « Velmar : nuit et or »

> Posée le 2026-08-08. Direction choisie par Aurèle sur trois propositions ;
> les deux autres (Célestria marbre et cyan, parchemin et bleu roi) sont
> écartées, pas en attente.

### L'état des lieux, mesuré

Aurèle : « on utilise la charte de Godot ? » — à moitié vrai, et la moitié
fausse valait d'être mesurée avant de repeindre quoi que ce soit :

| | Origine | Constat |
|---|---|---|
| **Interface** | Godot | **Aucun fichier `.theme`**, aucun `gui/theme/custom` dans `project.godot`. Tout `Control` tombait sur le thème d'usine. Par-dessus, **60 couleurs hex en dur dans 12 fichiers** et **17 `StyleBoxFlat` fabriqués à la main** dans 8 écrans |
| **Décor du plateau** | À nous | `tactics_scenery.gd` est déjà une direction assumée : ciel #3a4a72 → #24213a, sept terrains, soleil #fff1d6, brume, grain procédural |
| **Figurines** | Projet amont | 7 planches, dont 4 de héros pour 6 classes (`assets/textures/actor/README.md`) |

Ce n'était donc pas « l'interface de Godot » mais **des boutons repeints écran
par écran posés sur des widgets d'usine**. Les boutons étaient à nous ; les
champs de saisie, listes déroulantes, compteurs, cases à cocher et barres de
défilement étaient gris, et c'est ce mélange qui se voyait — plus encore que les
couleurs, la **police** de Godot signait l'origine sur chaque écran.

### Ce qui la définit

- [`palette.gd`](../data/models/view/theme/palette.gd) — **la source unique**.
  Fonds, reliefs, bordures, accents, texte, cinq tailles de police, géométrie.
  Règle : *l'or est un accent, jamais un fond* ; le pourpre ne sert qu'à ce qui
  blesse ou ne se défait pas.
- [`ciel_theme.gd`](../data/models/view/theme/ciel_theme.gd) — le `Theme`, bâti
  en code comme le décor du plateau : aucune ressource à ouvrir dans l'éditeur,
  un seul fichier à relire. Les icônes qui trahissaient Godot le plus vite
  (flèches d'un compteur, chevron d'une liste, case à cocher) y sont **dessinées
  pixel par pixel** plutôt qu'empruntées.
- **Polices** — Cinzel (titres, capitales gravées) et Alegreya Sans (corps),
  toutes deux sous licence OFL, donc redistribuables avec le jeu
  (`assets/fonts/`, licences incluses).
- **Cinq variations nommées** : `TitreEmbleme`, `TitreSection`, `TexteDiscret`,
  `BoutonPrincipal`, `BoutonDanger`. Un écran demande un rôle au lieu d'empiler
  trois `add_theme_*_override`.

### Deux pièges payés, et verrouillés par un test

1. **Un thème ne traverse pas un `CanvasLayer`.** Posé sur la fenêtre racine, il
   descend à ses `Control` — mais s'arrête net sur un `CanvasLayer`, qui n'est ni
   l'un ni l'autre. Or `Main._mount_ui` pose *chaque* écran dans un `CanvasLayer` :
   la première tentative n'a donc rien changé du tout, capture d'écran à l'appui.
   Le raccord se fait une fois, dans `Main._ready`, sur `SceneTree.node_added`.
2. **`variation_opentype` n'accepte que le tag entier de l'axe.** Avec la clé
   texte `{"wght": 700}` — celle qui marche pour `opentype_features` juste à
   côté — Godot **n'échoue pas, il ignore** : le titre restait en Regular sans
   qu'aucun message ne le dise. Mesuré en comparant des largeurs de chaîne :
   identiques à 400, 700 et 900. D'où `TextServerManager…name_to_tag("weight")`.

Le test 24 de `test_features.gd` mesure les deux, plus la présence de la charte
sur chaque type de widget : ces bugs-là sont muets, seule une mesure les attrape.

### Ce qui reste à faire

- **Le nettoyage** : les 60 couleurs en dur et les 17 `StyleBox` faits main
  vivent toujours dans les écrans, et **gagnent** sur le thème là où ils se
  recouvrent. Les remplacer par les variations de la charte, écran par écran.
- **Les emoji employés comme icônes** (💾 🗺️ 👤 🎯) rendent au style du système
  et jurent avec un médiéval-fantastique. Ils demandent des glyphes dessinés.
- **Le décor du plateau** n'a pas été retouché : Velmar s'accorde déjà à son
  ciel. Une bascule vers une autre direction, elle, l'exigerait.

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

---

### Passe du 2026-08-05 (3) — le décor des cases

Le plateau disait son terrain par la seule teinte de ses cases : un damier vert
clair et vert foncé, où « forêt » était une convention à retenir plutôt qu'une
chose à voir. Le cadrage de la passe précédente ayant remis tout le plateau à
l'écran, sa platitude sautait aux yeux.

| Livré | Où |
|---|---|
| Arbres sur la forêt, rochers sur la montagne, créneaux sur les murs — procéduraux, un `MultiMesh` par type | `data/models/view/scenery/props.gd` |
| Le décor apparaît aussi **dans l'éditeur de cartes**, redessiné à chaque coup de pinceau | `map_editor_level.gd` (`_rebuild_props`) |
| Le calcul du décor se vérifie en headless | `test_map.gd` |

Trois règles tiennent l'ensemble, et chacune est tenue par un test :

* **Rien ne cache une unité.** Tout décor est plafonné à 0,85 unité (un pion en
  fait ~1,2), et sur la forêt — le seul de ces trois terrains où l'on puisse se
  tenir — il est décalé vers un coin, centre dégagé avec 28 % de marge. Montagne
  et mur sont infranchissables : leur décor peut occuper toute la case.
* **Rien n'intercepte la souris.** Aucune collision sur ces volumes : la
  sélection continue de viser la tuile.
* **Rien n'est tiré au hasard.** La variation vient d'un hachage des coordonnées
  de la case — deux machines d'une même partie en réseau dessinent le même bois.

Deux choses apprises en mesurant :

* **`MultiMesh.get_instance_transform()` rend l'identité en headless.** Un test
  qui interroge le décor *posé* ne mesure donc rien. D'où
  `TacticsProps.placements()`, public : tout le calcul, séparé de la pose, et
  c'est lui que le test interroge.
* **`SphereMesh` lisse ses normales quel que soit son nombre de segments.** Les
  rochers en sphère donnaient des œufs ; ce sont les arêtes vives d'un bloc
  incliné qui font la pierre.

**Tests** (tous verts) :

```bash
godot --headless --path . --script test_combat.gd    #  31 OK
godot --headless --path . --script test_map.gd       # ALL TESTS PASSED (+ décor)
godot --headless --path . --script test_features.gd  # 374 OK
godot --headless --path . --script test_battle.gd    #  68 OK
bash scripts/test_net.sh                             # transport + reconnexion
```

Éprouvé capable d'échouer : le décalage vers le coin ramené de 0,30 à 0,10, le
test nomme le feuillage posé sur le centre de la case.

---

### Passe du 2026-08-05 (4) — trois blocages remontés par Aurèle

Premier retour de jeu réel sur la build `b928b85`. Trois reproches, trois causes
distinctes — dont une seule venait de la passe précédente.

| Reproche | Cause réelle | Correctif |
|---|---|---|
| « la caméra est moins libre » | l'inclinaison verrouillée **et** le regard libre mort : `is_rotating` ne redescendait jamais | `service/rotation.gd` |
| « on ne peut pas échanger deux unités au déploiement » | le pion masque toujours sa case au rayon : cliquer la deuxième ne faisait que la reprendre | `deployment_phase.gd` |
| « on ne peut pas sélectionner les différentes unités » | l'étape « montrer les actions » ne rappelait plus la sélection | `service/turn.gd`, `service/selection.gd` |

**La caméra.** Deux fautes, pas une. L'inclinaison fixe (§6.3) rendait bien le
cadrage « Awakening », mais interdisait de regarder derrière un rempart : elle
redevient libre, et ne sert plus que de position de repos. Surtout,
`rotate_camera` comparait `t_pivot.rotation.y`, que `get_euler()` rend dans
(-180°, 180°], à `y_rot`, qui vit dans [0°, 360°) : au-delà d'un demi-tour
l'égalité était impossible, `is_rotating` restait vrai pour toujours, et c'est
lui qui autorise le clic-milieu. **Le regard libre était donc mort tout court.**
Bug latent depuis toujours pour les caps > 180° ; poser `y_rot = 315` au
démarrage l'a rendu permanent. La comparaison se fait maintenant sur des angles.

Le zoom souffrait du même genre d'erreur d'unité : `zoom_speed = 10` fait cinq
crans sur une plage d'ouverture de 55°, mais **deux** sur une plage de hauteur de
19 unités. Un cran de molette envoyait d'une butée à l'autre. Le pas s'exprime
désormais en fraction de la plage, quelle que soit l'unité.

**Les deux clics.** Même forme dans les deux cas : *cliquer une autre unité ne
fait pas la chose évidente*. Au déploiement, l'aide annonçait « Deux unités
échangent leurs places » alors que le rayon touchait toujours le pion avant sa
case — l'échange était injouable. En bataille, choisir une unité vous y
enfermait jusqu'à trouver « Cancel » au bas du menu. Les deux gestes sont
désormais ceux de n'importe quel Fire Emblem.

> **Le trou de couverture.** Aucun de ces trois bugs n'était visible pour la
> suite headless, et deux d'entre eux étaient déjà là avant. `test_battle.gd`
> vérifiait la *règle* d'échange (`plan.place()`) sans jamais emprunter le
> *chemin du clic* ; rien ne pilote la souris. C'est exactement ce que le
> `test_window.gd` du §6.2 doit couvrir, et ce retour le fait passer devant le
> reste : les trois correctifs ci-dessus ont été vérifiés à la main, en fenêtre,
> avec des clics simulés — pas par la suite.

---

### Passe du 2026-08-05 (5) — déplacer une unité à la souris était impossible

En pilotant un tour complet à la souris pour chercher des bugs, le premier
trouvé est le plus gros du projet : **cliquer une case atteignable ne déplaçait
pas l'unité**. Le pion repassait aussitôt au menu d'actions sans avoir bougé.
Reproduit à l'identique sur `29aceb7` — le bug est ancien, pas une régression.

**La cause.** Contrôles et caméra vivent dans `main.tscn` et survivent aux
niveaux ; l'arène arrive avec la carte. `TacticsControls` chargeait donc une
ressource d'arène **par défaut** (`arena.tres`), alors que les cartes de
chapitre passent par `map_arena.tres` — deux instances distinctes de la même
classe. Or les contrôles parlent à l'arène **par signaux** portés par cette
ressource : personne n'était à l'autre bout.

Tout ce que les contrôles demandaient à l'arène se perdait donc en silence :
surlignage du survol, remise à zéro des marqueurs, et surtout
`get_pathfinding_tilestack()`, qui rendait une pile vide. Une pile vide, pour
`move_pawn()`, veut dire « trajet terminé » : retour au menu, pion immobile.

**Le correctif.** Le niveau met les contrôles en relation avec l'arène qu'il a
réellement montée (`TacticsLevel._bind_controls_to_arena()` →
`TacticsControls.use_arena()`). Deviner une ressource ne suffit pas : c'est la
même leçon que le rayon de caméra écrit à la main, corrigé le même jour.

> **Pourquoi la suite ne voyait rien.** Le pont CielAI et l'IA locale appellent
> le **nœud** arène directement, jamais la ressource : les 68 vérifications
> passaient au vert sur un jeu injouable à la main. Le nouveau test compare les
> deux instances et demande un vrai trajet — retirer le correctif le fait tomber
> à 70 OK / 2 ÉCHECS, en nommant la pile vide.

`test_battle.gd` : **72 OK**.

---

### Passe du 2026-08-06 — riposte, armes, terrain choisi, menu en français

Les quatre dernières features de jeu codables, livrées ensemble.

**1. La riposte.** Le moteur résolvait un combat dans un seul sens : attaquer ne
coûtait rien, et l'aperçu d'avant-combat n'avait qu'un camp à montrer.
`FECombatCalculator.calculate_exchange()` produit désormais un **échange** —
assaut, riposte, puis un second coup pour le plus rapide des deux, et pour lui
seul. `roll_exchange()` le déroule coup par coup en suivant les PV : dès que l'un
tombe, l'échange s'arrête, et les dégâts rapportés sont ceux réellement encaissés.

Trois raisons de ne pas riposter, toutes de règle : être déjà à terre, porter une
arme qui n'engage aucun combat (bâton), ou se trouver hors de portée. Cette
dernière a demandé une notion neuve, la **portée minimale**
(`WeaponType.get_min_range`) : un arc vaut 2, donc un archer pris au contact ne
rend rien. `LocalAIBrain` lit la même règle (`can_strike`), sans quoi l'IA aurait
fui les archers au lieu de les charger — exactement le mauvais réflexe.

`TacticsParticipantCombatService.attack_pawn()` a été durci au passage :
l'assaillant peut désormais **mourir de son propre assaut**, cas qui n'existait
pas et qui laissait interroger un pion sur le départ.

**2. Les armes.** `WeaponDB` (14 armes) remplace les deux chiffres nus que
portait chaque fiche. Une arme a une puissance, une portée, un modificateur de
précision et de critique, un poids et un prix. Le fourreau tient 3 armes,
l'arme en main s'applique aux stats (`Stats.equip`), s'achète à l'armurerie et se
choisit au menu **Équipement** de l'écran de préparation. Le poids, amorti par la
force, décide du second coup : la hache d'acier ralentit le mage et laisse le
grand chevalier intact.

Rétrocompatible par construction : une fiche qui ne déclare pas de `weapons`
garde ses `weapon_type` / `weapon_might` bruts, et une sauvegarde d'avant le
catalogue se recharge sans arsenal.

**3. Le terrain choisi en préparation.** Le bonus défensif d'une case était
calculé de bout en bout — jusqu'au pont CielAI — sans que personne puisse le
choisir. `ChapterMap` lit la carte d'un chapitre **sans monter la bataille**,
l'écran de préparation la montre case par case (terrain, bonus, occupant), et
`ChapterRunner._apply_deployment_tiles()` pose les pions sur la case retenue.
Contrairement à `DeploymentPhase`, ceci marche **aussi en headless** : c'est de la
donnée, pas un clic.

> **Piège 1 — hors de l'arbre, `global_position` rend l'identité.** Première
> version : instancier la scène du niveau (sans l'ajouter à l'arbre, donc sans
> `_ready`) et lire les positions des pions. Godot rend `Transform3D()` et le dit
> par une erreur : les quatre unités de départ tombaient toutes sur la même case,
> et la zone de déploiement était fausse. `ChapterMap` interroge maintenant le
> `SceneState` de la scène empaquetée et compose les transformations à la main.
> Rien n'est instancié, rien n'est libéré, et la console reste propre.

> **Piège 2 — un pion se recentre sur la tuile que son rayon croit avoir sous
> lui.** Le pion était bien posé sur sa case… et revenait à sa position d'éditeur
> **une frame plus tard**. Le coupable n'est pas le serveur physique mais le
> `RayCast3D` du pion : son collisionneur date de la frame précédente, et
> `is_pawn_configured()` recentre chaque pion sur *cette* tuile-là à chaque frame.
> D'où `_refresh_tile_sensor()` : `force_update_transform()` puis
> `force_raycast_update()` juste après le déplacement. (`DeploymentPhase` y
> échappait sans le savoir : elle suspend le niveau pendant le placement.)

**4. Le menu d'actions en français.** Le piège annoncé n'existait pas tout à
fait : la clé d'action était déjà le **nom du nœud** bouton, pas son libellé. Le
libellé vit désormais dans une table séparée (`TacticsControlsResource.action_labels`),
posée à l'ouverture par `TacticsControls._ready()`. Déplacer / Attaquer / Annuler
le déplacement / Attendre / Retour, et Soigner pour un porteur de bâton. Un test
vérifie que chaque clé désigne un bouton existant et qu'aucun bouton ne montre
encore sa clé au joueur — c'est ce test qui garde les deux notions séparées.

**Vérification.**

```
godot --headless --path . --script test_combat.gd    #  54 OK (31 avant)
godot --headless --path . --script test_features.gd  # 446 OK (374 avant)
godot --headless --path . --script test_battle.gd    #  76 OK (72 avant)
godot --headless --path . --script test_map.gd       # ALL TESTS PASSED
./scripts/test_net.sh                                # TEST RÉSEAU OK
```

`test_battle.gd` prouve le trajet complet du choix de terrain : une case
défensive est retenue devant la carte, et l'unité s'y tient une fois la bataille
ouverte, avec le bonus annoncé. Les nouveaux écrans ont été **regardés**, pas
supposés : `shot.gd` accepte l'écran `prep` (`equip`, `positions`, `shop`).

**Reste à faire, hérité :** l'équipement ne se change pas *en cours de bataille*
(seulement en préparation), et le moteur ignore toujours l'usure des armes.

---

### Passe du 2026-08-06 (2) — chasse aux bugs

Trois trouvailles, dont deux régressions introduites par la passe précédente.

**1. Un porteur de grimoire ne pouvait plus attaquer.** Cinq endroits testaient
`WeaponType.is_magical()` là où ils voulaient dire « porte un bâton » — l'un
d'eux nommait même sa variable `is_staff_user`. Or `is_magical` répond à une tout
autre question : « cette attaque vise-t-elle la RÉS plutôt que la DÉF ? », et un
grimoire y répond oui.

Le bug dormait depuis toujours, sans conséquence : aucune unité du joueur ne
portait de grimoire, et les mages adverses n'ouvrent pas de menu d'actions.
L'armurerie vend Feu et Foudre — il suffisait désormais d'en acheter un pour que
l'unité devienne un soigneur incapable d'attaquer : bouton « Soigner », ennemis
non ciblables, plus aucune prévision de combat.

Correctif : `WeaponType.is_healing()` (le bâton, et lui seul), et la règle de
ciblage rassemblée en **un seul endroit**, `TacticsPawnCombatService.can_target()`
— la laisser recopiée à trois endroits est ce qui a permis au bug d'y survivre.

**2. Revendre toutes ses armes ne coûtait rien.** Un fourreau vide veut dire deux
choses opposées : « fiche d'avant le catalogue, ses valeurs brutes font foi » ou
« elle a tout revendu ». `ChapterRunner._apply_arsenal()` ne connaissait que la
première, donc une unité dépouillée repartait au combat avec l'arme écrite dans
son `.tres` — l'or était gratuit. Le roster porte maintenant un marqueur
`uses_arsenal` qui tranche, et `Stats.unequip()` ramène l'unité au contact.

**3. Une suite peut être verte pendant qu'un script ne compile plus.** Trouvé en
me trompant : en extrayant `can_target`, j'ai laissé une variable référencée après
sa suppression. `test_combat` a répondu **57 OK / 0 ÉCHECS** et `test_battle`
**76 OK / 0 ÉCHECS**, erreur de parsing imprimée juste au-dessus. Godot signale et
continue ; tant qu'aucun test n'emprunte le fichier cassé, le vert ment.

Deux garde-fous écrits en GDScript ont échoué avant de trouver le bon :
`ResourceLoader.load()` rend un script cassé sans broncher, et `GDScript.reload()`
échoue sur tout fichier portant un `class_name` — 94 faux positifs sur 107. C'est
la **sortie du moteur** qui dit la vérité, pas le moteur interrogé depuis
lui-même. D'où `scripts/test_all.sh` : il lance les quatre suites avec le bon
binaire et échoue si une erreur de script apparaît, quel que soit le compte de
tests. Vérifié en cassant volontairement `unit_sheet.gd` — les suites restent à
« 0 ÉCHECS », le script sort en erreur.

Les deux correctifs sont éprouvés par mutation : remettre le bug fait tomber le
test qui le garde (`57 OK / 1 ÉCHEC`, `449 OK / 1 ÉCHEC`).

```
bash scripts/test_all.sh   # 58 / 450 / 76 OK + test_map — et l'absence d'erreurs de script
```

---

### Passe du 2026-08-06 (3) — deux retours de jeu réel d'Aurèle

**1. Frapper ou soigner clôt le tour de l'unité.** Après une attaque,
`can_attack` tombait bien à faux, mais `can_move` restait vrai : l'unité repartait
se promener après son coup. Une ligne dans `TacticsParticipantCombatService`
(`end_pawn_turn()`), et la règle Fire Emblem est rétablie — on se déplace puis on
agit, jamais l'inverse. Le soin passe par le même entonnoir, donc il est couvert
aussi.

**2. Le chapitre 2 était coupé en deux — et pas pour la raison annoncée.**
Aurèle : « on ne peut pas aller plus loin que la moitié de la map, moi et les
ennemis bloqués chacun de notre côté ; la map a différents niveaux, ce qui n'est
pas pris en compte ».

Le relief était un faux coupable. La vraie cause est arithmétique :
`BattleGrid._infer_tile_size()` déduisait le côté d'une case du **plus petit**
écart entre deux colonnes de tuiles. Cette carte est posée à la main : deux
colonnes s'y trouvent à 0,996 l'une de l'autre au lieu de 1,0 — quatre millièmes
invisibles à l'œil. Retenu comme côté de case, ce 0,996 décalait le calcul des
coordonnées jusqu'à faire **sauter une colonne entière** : deux tuiles tombaient
sur la même case, une case restait vide, et le plateau se retrouvait percé de
part en part. Mesuré : **160 cases indexées pour 200 tuiles posées**.

Le correctif est la **médiane** des écarts au lieu du minimum : il faudrait que la
moitié de la carte soit de travers pour la tromper. Vérifié en scène — 200 tuiles
sur 200, côté de case 1,0.

Deux corrections d'accompagnement, à la demande d'Aurèle : le relief du chapitre 2
est aplati (tuiles à hauteur 0, décor sculpté retiré, pions reposés au sol) et ses
tuiles sont remises sur une trame régulière de 1,0. Le jeu se joue de plain-pied
pour le moment.

> **Deux fausses pistes, gardées ici pour qu'on ne les reprenne pas.** D'abord une
> analyse de connectivité en Python qui concluait à « 16 zones isolées » : elle
> arrondissait les coordonnées avec `round()`, dont l'arrondi bancaire collapsait
> les colonnes. La formule du moteur est `floor(x + 0.5)`. Ensuite une sonde qui
> croyait charger le chapitre 2 mais montrait le chapitre 1 : `Main` retient le
> chapitre au moment où il **ouvre l'écran de préparation**, changer
> `chapter_index` ensuite ne suffit pas. `shot.gd` accepte désormais un numéro de
> chapitre (`battle out.png 2`) et fait la manœuvre correctement.

Trois tests neufs verrouillent tout cela : le côté de case déduit d'une trame de
travers, le chapitre 2 d'un seul tenant et de plain-pied, et le compteur de zones
lui-même. Éprouvés par mutation.

```
bash scripts/test_all.sh   # 58 / 459 / 76 OK + test_map
```

---

### Passe du 2026-08-06 (4) — quatre demandes d'Aurèle

**1. Renouveler le code d'une partie en ligne.** Un bouton « 🔄 Générer un
nouveau code » referme le salon et le rouvre. Le code est l'adresse de la machine
écrite en sept caractères — 5 bits par caractère, soit 35 bits pour 32 bits
d'adresse. Les **trois bits qui restent en tête** distinguent huit écritures du
même chemin : le code change d'allure, sans mentir sur la destination.

> Ce que le bouton ne fait pas, et l'écran le dit : révoquer l'ancien code.
> Il mène toujours à cette machine. Seul un changement de réseau couperait le
> chemin.

**2. CielAI ne semblait « rien faire » pendant son tour.** Il faisait quelque
chose : il attendait. `FALLBACK_AFTER_FRAMES` accordait **600 frames — dix
secondes — par décision** avant que l'IA locale ne prenne la main. Sans client
Ciel branché, chaque tour adverse devenait une suite de gels de dix secondes.

La patience est désormais conditionnelle : pleine tant que Ciel répond, réduite à
une demi-seconde dès qu'il s'est tu une fois, et **rendue entière au premier ordre
reçu** — brancher un client en cours de partie fonctionne sans rien redémarrer.

**3. Sauvegarder et charger.** La campagne écrivait déjà toute seule et
« Continuer » relisait cet unique emplacement ; ce qui manquait était de
**choisir**. Quatre emplacements (`Campaign.SAVE_SLOTS`), décrits sans être
chargés — `slot_info()` relit l'en-tête du JSON, car charger pour décrire
écraserait la partie en cours. « Charger une partie » à l'écran-titre,
« 💾 Sauvegarder » à la préparation. L'emplacement 1 reste celui que le jeu écrit
tout seul : on peut le charger, pas l'écraser à la main.

**4. Un menu principal en deux colonnes, responsive.** Trois grilles (partir au
combat, réglages, extras) qui passent de deux colonnes à une, dans un
`ScrollContainer` — une fenêtre courte fait défiler au lieu de perdre ses
derniers boutons.

> **Le piège du responsive ici.** Le projet est en `stretch/mode="canvas_items"` :
> la largeur **logique** ne bouge pas avec la fenêtre, seule la hauteur s'étire.
> Un seuil sur `size.x` ne se déclenche donc jamais — la première version restait
> obstinément sur deux colonnes en fenêtre étroite. C'est la **forme** de la
> fenêtre qui décide : `TitleScreen.is_wide()` demande à la fois une largeur
> minimale et un format plus large que haut.

```
bash scripts/test_all.sh   # 58 / 478 / 76 OK + test_map
```


---

### Passe du 2026-08-06 (5) — retours de jeu, suite

**Le prototype 2D est supprimé.** Voir §6.4. Il ne compilait plus depuis le
refactor de la grille : son `class_name BattleGrid` entrait en collision avec la
vraie grille de bataille, et le bouton de l'écran-titre menait à un écran inerte.

**Un arc ne tire plus à bout portant.** La portée minimale n'existait que pour la
riposte : `mark_attackable_tiles()` avait un plafond mais pas de plancher, si bien
que Virion pouvait frapper la case d'à côté. Le plancher est maintenant appliqué
partout où une portée d'attaque se calcule — marquage des cases pour les deux
camps, décision de l'IA locale (`can_strike` au lieu d'un simple `dist > range`),
et cases exportées à Ciel.

**La grille d'une carte posée à la main.** `TacticsGrid.grid_size()` retombait sur
un 16×10 de secours dès que l'arène ne déclarait pas de [MapData] — donc sur le
chapitre 2, dont le plateau fait 10×20. Tout ce qui borne un calcul par cette
taille travaillait sur une emprise qui n'existe pas : cases à portée, carte des
terrains exportée à Ciel, zone de déploiement par défaut. `BattleGrid.dimensions()`
rend maintenant l'emprise réellement indexée.

**La barre de l'écran de préparation.** Six boutons à 240 px font 1520 px pour un
écran logique de 1280 : « Lancer la bataille » sortait de l'écran et devenait
inatteignable à la souris. Les boutons se partagent désormais la largeur
disponible.

> **Le crash du chapitre 2 n'est pas reproduit.** Quatre tentatives — headless,
> fenêtré, par progression réelle depuis le chapitre 1, et avec la phase de
> déploiement confirmée puis 900 frames de bataille — aucune n'a fait tomber le
> jeu. Les trois correctifs ci-dessus touchent le chapitre 2 et peuvent l'avoir
> emporté avec eux, mais **rien ne le prouve** : la cause reste à identifier, et
> il faut savoir ce que « crash » veut dire ici (fenêtre qui se ferme ? gel ?
> écran noir ?).

```
bash scripts/test_all.sh   # 58 / 482 / 76 OK + test_map
```


---

### Passe du 2026-08-06 (6) — le crash du chapitre 2, trouvé

Aurèle : « lorsque l'on passe du chapitre 1 au chapitre 2, l'écran se fige et le
jeu se ferme ». C'est la **transition** qui plantait, pas le chapitre 2 — ce que
mes quatre premières tentatives de reproduction avaient manqué, parce qu'elles
appelaient `complete_chapter()` directement et sautaient le chemin de la victoire.

**Deux gestionnaires de victoire couraient en parallèle.** `ChapterRunner` évalue
l'objectif, écrit le résultat dans la campagne et enchaîne sur l'écran suivant.
Mais `TacticsPawnCombatService._check_victory()` — hérité d'avant la campagne —
faisait sa propre annonce puis, **2,8 secondes après le dernier mort**,
déchargeait le niveau et rentrait au menu.

Deux secondes et huit dixièmes, c'est exactement le temps qu'un joueur met à lire
« Victoire » et à cliquer. Le minuteur tombait alors en plein chargement du
chapitre suivant : le niveau tout juste monté était détruit sous les pieds de son
propre `ChapterRunner`, encore en train d'attendre ses frames d'initialisation.
Écran figé, puis fermeture.

Reproduit en faisant cliquer la sonde **vite** (45 frames au lieu de 400) : le
niveau du chapitre 2 passe de « présent » à « PERDU » entre deux relevés. C'est
la lenteur de mes sondes qui avait masqué le bug — elles laissaient le minuteur
passer avant d'enchaîner.

Le chemin hérité garde son annonce (une escarmouche ou un duel local n'a pas de
runner, personne d'autre ne la fait) mais ne touche plus à la scène dès qu'un
arbitre est aux commandes : `chapter_runner()` remonte du pion jusqu'au niveau
pour le savoir.

**Journal sur disque activé** (`file_logging` dans `project.godot`). Sans lui, un
plantage chez un joueur ne laisse aucune trace : la fenêtre se ferme et l'erreur
part avec elle. Les dix derniers journaux sont conservés dans `user://logs/`,
et `docs/INSTALL.md` dit où les trouver.

```
bash scripts/test_all.sh   # 58 / 482 / 77 OK + test_map
```


---

### Passe du 2026-08-06 (7) — le tour à la souris, enfin prouvé

Le §6.2 est fait : `test_window.gd`. Neuf vérifications qui jouent un tour comme
un joueur — cliquer une unité, ouvrir son menu, la déplacer, frapper.

C'était le plus gros trou de preuve du projet, et la journée l'avait démontré
trois fois : un porteur de grimoire incapable d'attaquer, un arc qui tirait au
contact, un bouton poussé hors de l'écran. Trois bugs qu'aucune des 617
vérifications headless ne pouvait voir, parce qu'aucune ne tient une souris.

La suite couvre aussi, au passage, deux correctifs du jour : le menu d'actions en
français (le libellé lu sur le vrai bouton, pas dans la table) et la fin de tour
après une attaque.

```
bash scripts/test_all.sh --window   # 58 / 482 / 77 OK + test_map + 9 OK
```


---

### Passe du 2026-08-06 (8) — le surlignage de portée

Dernière ligne du §6.3. Les matériaux de portée posaient un aplat de couleur unie
par-dessus la case (`material_override`) : à l'affichage d'une portée, tout le
grain de la passe artistique disparaissait d'un coup, la trame des cases avec, et
la zone se lisait comme une seule flaque bleue.

`TacticsScenery.highlight_material(terrain_type, state)` repart du matériau de
terrain de **cette case-là**, mélange la teinte de l'état à sa couleur (68 %) et
ajoute une lueur discrète pour rester lisible dans une ombre portée. Le motif, sa
projection en coordonnées monde et sa réponse à la lumière sont conservés.

Effet de bord voulu : une forêt à portée reste une forêt, plus sombre que la
plaine voisine — l'information de terrain survit au surlignage, alors qu'elle
était effacée par l'aplat.

Les matériaux sont mis en cache par couple (terrain, état) — au pire 49 — et
chaque tuile garde les siens sous la main : `_process` passe par là 200 fois par
image, il n'a pas à reconstruire une clé de cache à chaque fois.

`shot.gd` gagne l'écran `range` (une unité en main, sa portée affichée), qui a
servi à comparer l'avant et l'après. Marquer les tuiles à la main ne tient pas —
la boucle de tour les remet à zéro à chaque frame ; il faut demander l'étape
« choisir la case » et laisser le jeu surligner.

```
bash scripts/test_all.sh --window   # 58 / 489 / 77 OK + test_map + 9 OK
```


---

### Passe du 2026-08-06 (9) — duel local retiré, éditeur de personnages

**Le duel local (M2) est retiré**, à la demande d'Aurèle : personne ne s'en
servait. Ce qu'il avait apporté reste et sert au réseau — actions humaines
remontées dans `TacticsParticipant`, boucle de tour paramétrée par camp, bandeau
« à qui de jouer ». Seuls le mode, son bouton et son entrée de menu disparaissent.

> La valeur `2` de `GameSession.Mode` reste **vacante** plutôt que renumérotée :
> le mode voyage jusqu'à Ciel dans `ai_state.json`, et décaler `NETWORK` de 3 à 2
> aurait changé le protocole pour rien.

**Éditeur de personnages.** Le joueur écrit ses propres recrues et les verse dans
son armée. Trois pièces, dans l'ordre habituel du projet :

* `UnitDocument` — la fiche : nom, classe, niveau, PV, mouvement, sept
  statistiques, armes, objets. Elle se valide (bornes, arme que la classe sait
  manier, nom non vide) et se sérialise. Logique pure, éprouvée en headless.
* `UnitLibrary` — le rangement, dans `user://units/*.json`. Même raison que
  [MapLibrary] : `res://` est en lecture seule une fois le jeu installé, une
  fiche enregistrée là serait perdue. Un personnage est un fichier JSON lisible,
  corrigeable à la main, envoyable à quelqu'un.
* `CharacterEditor` — l'écran, accessible depuis l'écran-titre.

Deux partis pris qui méritent d'être dits :

1. **Une fiche neuve part des bases de sa classe**, pas de zéros. Un personnage
   créé sans rien toucher doit être jouable tout de suite. Changer de classe
   rebat ces bases — c'est ce qu'on attend en la choisissant, et ça évite un
   archer avec les statistiques d'un chevalier.
2. **L'aperçu monte une unité vivante** (`Stats.import_stats`) au lieu de
   recopier les formules de combat. C'est la seule façon d'être sûr que les
   chiffres affichés pendant le réglage — attaque, précision, esquive, vitesse
   d'attaque, poids de l'arme — sont ceux que le combat appliquera.

`Campaign.enlist_custom()` fait entrer la recrue par la même porte que les
autres : une entrée de roster, avec son arsenal, sa portée d'arme et ses objets.
Elle survit à la sauvegarde comme n'importe quelle unité.

```
bash scripts/test_all.sh --window   # 58 / 509 / 77 OK + test_map + 9 OK
```

### Passe du 2026-08-07 — les quatre chantiers restés codables

Les quatre points que le §6 laissait ouverts, dans l'ordre où ils ont été faits.

**1. La carte du chapitre 2, présentable.** Elle était jouable et vide : 200
tuiles posées à la main, plates, sans terrain déclaré — donc affichées en herbe
et sans un seul décor, `TacticsProps` ne posant d'arbres et de rochers que sur
les cases qui annoncent leur terrain. Elle est désormais un `MapData` de 10 × 20
(`outpost_map.tres`, `outpost_arena.tscn`, `outpost_level.tscn`) : ruines du
poste avancé, rempart percé d'une brèche de trois cases, montagne à l'ouest,
mare, bois, chemin, et du relief là où personne ne démarre. Les pions sont
reposés au centre exact de leur case.

`test_level.tscn` reste au dépôt, exprès : c'est la dernière arène sculptée, et
donc le seul cas d'essai honnête pour `ChapterMap.scene_tiles` et pour le refus
d'une carte qui ne déclare pas son terrain. Les tests qui portaient sur le
chapitre 2 pointent sur elle.

Ce que le test vérifie maintenant : une grille de 10 × 20, plusieurs terrains
(dont bois et rempart), **une seule zone franchissable** au saut le plus faible
du jeu, la marche la plus haute bien en deçà de ce saut, chaque départ praticable
et de plain-pied, et assez de cases ouvertes pour les places du chapitre.

**2. `test_window.gd` étendu — 9 vérifications, puis 16.** Le placement
d'avant-bataille à la souris (échanger deux unités, en poser une sur une case
ouverte, tout défaire) et le tour adverse (rendre la main, voir l'IA locale jouer
d'elle-même, récupérer le tour). Deux détails payés :

- Le placement doit se **défaire** avant que la bataille commence. Sans cela,
  l'unité déplacée se retrouvait loin des ennemis et le test d'attaque se
  déclarait « non testable » — il passait au vert en ne vérifiant rien.
- Le bouton de fin de tour vit dans le menu d'actions, qui se referme quand
  l'assaillant a fini son tour. Il faut reprendre une unité disponible d'abord,
  comme le ferait un joueur.

**3. La grille en données, finie.** Voir §6.1 : `PathField` remplace `pf_root` /
`pf_distance` sur les nœuds, `TacticsPawn.get_tile()` consulte l'index,
`tile_raycasting` disparaît, et le `RayCast3D` du pion avec.

> **Le bug que ce refactor a révélé.** En passant `get_tile()` à l'index, un
> déplacement de cinq cases s'est mis à en valoir quatre. Ce n'était pas le
> nouveau code : `BattleGrid.coord_at_position` faisait `floori(x + 0.5)`, ce qui
> suppose des centres de case sur les entiers. Une carte de largeur **paire** les
> met sur les demis, et la frontière entre deux cases tombait alors exactement
> sur le centre de l'une d'elles. Un pion arrêté à 0,14 de son centre — la
> tolérance d'arrivée du déplacement — était attribué à la case d'avant, et
> `adjust_to_center` l'y recollait. Le rayon, lui, ne trouvait rien à cet endroit
> et ne recentrait donc pas : le bug était là depuis le début, masqué par
> l'imprécision qu'il remplaçait. La grille compte désormais les cases depuis une
> tuile réelle.

**4. Confort de l'éditeur de cartes.** Voir §6.7 : roster lu sur le disque et
ouvert aux personnages du joueur, niveau des unités posées (avec montée réelle et
tirage à graine fixe), et partage de cartes par presse-papiers ou par fichier.

`shot.gd` accepte un argument de plus : `editor units` ouvre le sélecteur
d'unité, le seul moyen de juger cette liste autrement qu'en lisant du code.

```
bash scripts/test_all.sh --window   # 58 / 549 / 77 OK + test_map + 16 OK
```

### Passe du 2026-08-07 (2) — deux règles de déplacement qui mentaient

Deux bugs trouvés en refactorant le parcours, laissés de côté ce jour-là parce
qu'ils touchent à l'équilibre, puis corrigés sur décision d'Aurèle.

**On ne pouvait pas traverser ses propres unités.** `process_surrounding_tiles`
annonçait le contraire — il testait « l'occupant est-il un allié ? » — mais ce
test était enfermé dans une branche qui ne s'exécutait que si la liste d'alliés
était **vide**, auquel cas la réponse était forcément non. Résultat : toute case
occupée bloquait, y compris celles de ses propres camarades. Une unité coincée
derrière ses voisins ne pouvait plus sortir de la mêlée.

La règle est désormais celle de Fire Emblem : on **traverse** les siens, jamais
l'adversaire, et on ne s'**arrête** sur personne (`mark_reachable_tiles` refusait
déjà toute case occupée comme destination, il n'a pas bougé). La liste d'alliés
dit maintenant explicitement de quel calcul il s'agit : non vide, c'est un
déplacement ; vide, c'est une portée d'arme, et l'occupation ne compte pas — un
arc tire par-dessus les têtes.

**Le joueur et l'IA ne franchissaient pas les mêmes dénivelés.** Le deuxième
argument de `process_surrounding_tiles` est la hauteur franchissable ; l'IA
(`ai_executor`, `ciel_ai`) y passe le `jump` du pion (2), le joueur y passait son
`movement` (5). Deux camps, deux règles : le joueur escaladait des falaises que
l'adversaire ne pouvait pas suivre. `plyr_serv` passe désormais `jump` lui aussi.

> **Sans effet visible sur les cartes actuelles**, et il faut le dire : aucune
> n'a de marche assez haute pour que 2 et 5 diffèrent (le relief y plafonne à
> 0,75 de dénivelé perçu). Ça se serait vu sur une carte dessinée dans l'éditeur,
> qui autorise des hauteurs de -1 à 3.

Le premier est tenu par un test (`_test_traversal_rules`), éprouvé sur le service
réel et non sur une règle recopiée — **et vérifié en le faisant échouer** sur
l'ancien code avant de le déclarer bon. Il ne demande pas de fenêtre : c'est le
premier bénéfice concret du parcours sorti des nœuds.

```
bash scripts/test_all.sh --window   # 58 / 557 / 77 OK + test_map + 16 OK
```

### Passe du 2026-08-07 (3) — trois retours de jeu réel d'Aurèle

**Le plantage à la mort de Virion.** L'adversaire qui le vise pose la caméra sur
lui ; Virion meurt et quitte la scène une demi-seconde plus tard, pendant que la
caméra le poursuit encore. La garde en place — `if not res.target or res.target
== null` — répond juste **en debug**, où Godot annule les références aux objets
libérés. Dans une build **exportée**, cette protection n'existe pas : la
référence reste pendante, répond « vrai », et lire `global_position` fait tomber
le jeu.

> **À retenir, au-delà de ce bug.** Aucune suite de ce projet ne reproduira
> jamais ce genre de plantage : elles tournent toutes en debug, donc sous la
> protection qui manque au joueur. `is_instance_valid` est la seule garde qui
> vaille dès qu'une référence peut désigner un nœud disparu — un pion meurt, et
> tout ce qui le tenait le tient encore.

Corrigé sur la caméra et sur le tour adverse (une riposte peut tuer l'assaillant
en cours de tour, et le pion actif disparaît sous les pieds de l'étape suivante).

**Une régression de la veille, trouvée au passage.** Un mort reste en scène une
demi-seconde. Tant que l'occupation se lisait par un rayon, il cessait de compter
dès que sa collision était coupée ; `BattleGrid` ne regarde pas les collisions,
donc depuis le passage à l'index un cadavre bloquait sa case. Les morts sont
écartés de l'occupation.

**Le placement des unités, refait.** Deux écrans faisaient le même travail : le
bouton « Positions » de la préparation choisissait les cases, puis la bataille
s'ouvrait et redemandait de placer les unités sur le plateau. Le second écrasait
le premier — d'où « ce bouton ne sert à rien ». L'écran de préparation perd donc
son panneau ; les cases se choisissent sur le plateau, là où l'on voit le
terrain.

Et le vrai bug derrière « on ne peut cliquer que sur une autre unité » : l'unité
**restait en main** après avoir été posée. Le clic suivant sur une autre unité
tombait donc dans le cas « échange » au lieu de la choisir — impossible de passer
à la suivante, on permutait sans fin les deux mêmes. Poser relâche désormais ;
recliquer l'unité qu'on tient la repose ; la case de l'unité en main est
surlignée ; et le bandeau dit à chaque instant ce qu'on attend du joueur.

```
bash scripts/test_all.sh --window   # 58 / 557 / 77 OK + test_map + 18 OK
```

### Passe du 2026-08-07 (4) — une seconde bataille dans la même session

Aurèle : « quand on veut relancer une partie, on peut déployer les personnages,
mais quand on commence la partie on ne peut plus cliquer ni interagir. » Et :
« on ne peut toujours pas lancer la deuxième mission après avoir fini la
première. »

**C'était le même bug.** Le passage d'un chapitre au suivant fonctionne : monté
en sonde, la victoire s'enregistre, la campagne avance, la carte du chapitre 2
se charge. Ce qui ne fonctionnait pas, c'est la bataille **une fois montée**.

Participant, contrôles et caméra vivent dans `main.tscn` et **survivent aux
niveaux**. Ils gardaient de la bataille précédente :

- `TacticsParticipantResource` — `curr_pawn`, `stage`, et surtout `targets` et
  `hostile_camps`, qui désignent des **camps** du niveau d'avant ;
- `TacticsControls.curr_pawn` — l'unité que le joueur tenait à la fin de la
  bataille précédente ;
- `BattleGrid.current`, statique, qui survivait au niveau en désignant des tuiles
  libérées.

`TacticsParticipant.reset_participant()` existait déjà, écrit exactement pour ça
(« Resets the participant's pawn references when unloading a level ») — et
**personne ne l'appelait**. Il est appelé au `_ready` du participant, complété
des camps, doublé d'un `reset_for_level()` sur les contrôles et d'une remise à
zéro de `BattleGrid.current` au déchargement.

> Même leçon que le plantage de Virion, et c'est la deuxième fois de la journée :
> en debug, Godot annule les références aux objets libérés, donc la seconde
> bataille se rattrapait toute seule sur le Mac. Dans une build exportée, les
> services travaillaient sur des références pendantes et plus rien ne répondait
> au clic.

**Nouvelle suite : `test_chapters.gd`** (`--window`, 14 vérifications). Elle
gagne le chapitre 1, passe au 2, et **clique une unité** pour exiger qu'elle soit
prise. C'est le seul test qui monte deux batailles dans une même session, donc le
seul qui puisse voir ce que les ressources partagées gardent de l'une à l'autre —
le chaînage des chapitres a cassé deux fois, il est désormais tenu.

L'assertion a demandé deux essais. « La référence est-elle valide ? » ne prouvait
rien : en debug un nœud libéré se lit comme `null`, donc une ressource périmée
passait pour propre. C'est l'**étape** du participant qui trahit l'état d'avant.
Vérifié en faisant échouer le test sur le code non corrigé.

```
bash scripts/test_all.sh --window   # 58 / 557 / 77 OK + test_map + 18 + 14 OK
```

### Passe du 2026-08-07 (5) — l'armée se repose entre les chapitres

Aurèle : « il n'y a pas de soin entre les chapitres, ajoutes-en un automatique. »

Les blessures traversaient les chapitres et rien ne les effaçait : il fallait
payer l'intendance pour se relever. C'est le mauvais sens de la difficulté — l'or
manque justement quand la campagne va mal, donc une partie mal engagée n'avait
aucun moyen de se redresser. C'est aussi la convention de Fire Emblem : une
bataille finie, l'armée se soigne.

`CampaignState.rest_army()` remet tous les survivants à plein, gratuitement, dans
`complete_chapter` — donc avant la sauvegarde, et seulement sur un chapitre
**bouclé**. La mort permanente n'est pas touchée : personne ne se relève.

**L'intendance garde son utilité**, et c'est pour ça que le soin payant reste :
après une **défaite**, le chapitre n'est pas bouclé, rien n'est effacé, et il
faut décider si l'on paie pour repartir d'aplomb ou si l'on retente avec des
blessés.

```
bash scripts/test_all.sh --window   # 58 / 561 / 77 OK + test_map + 18 + 14 OK
```

### Passe du 2026-08-07 (6) — enrôler ses créations, et le reste du balayage

**Un personnage écrit entre enfin en campagne.** `enlist_custom()` existait sans
appelant : on pouvait créer une recrue, l'enregistrer, la relire — et rien de
plus. L'intendance la propose désormais sur la même ligne que les autres
recrues, avec un bouton « Enrôler ».

**Gratuit pour l'instant**, choix d'Aurèle : on veut d'abord pouvoir jouer ses
créations. Le chemin de paiement est en place — `hire_custom()` vérifie l'or et
le déduit, l'affichage dit « gratuit » ou le prix — donc leur donner un coût un
jour ne demandera que de changer `CUSTOM_RECRUIT_COST`.

**Le reste du balayage des références pendantes.** Deux endroits du tour adverse
restaient exposés à la classe de bug qui a fait tomber le jeu deux fois :

- `attack_pawn` écrivait sur `res.curr_pawn` sans vérifier qu'il existe encore —
  or une riposte peut tuer l'assaillant à la frame précédente ;
- `get_nearest_target_adjacent_tile` et `get_weakest_attackable_pawn`
  appelaient `.get_neighbors()` et `.attackable` sur le retour de `get_tile()`,
  qui vaut `null` pour une unité hors grille.

Aucun n'est prouvé par un test — ils ne tombent que dans une build exportée, et
les suites tournent en debug. C'est le prix de cette classe de bug, et la raison
de la balayer à la main plutôt que d'attendre qu'elle se manifeste.

```
bash scripts/test_all.sh --window   # 58 / 570 / 77 OK + test_map + 18 + 14 OK
```

### Passe du 2026-08-07 (7) — figurines, fiches d'unité, et la liste de courses

**`assets/textures/actor/README.md`** — le pendant du README audio, et pour la
même raison : le code est prêt, l'art manque. Quatre planches de héros pour six
classes, donc Sully porte celle du seigneur et Cordelia celle de la clerc. Le
fichier dit le format (128 × 256, dos en haut, face en bas), ce qui manque, pour
qui, et comment brancher une planche fournie.

**Trois planches dormaient sur le disque** : `chr_pawn_skeleton_cpt.png` et
`chr_pawn_skeleton_mage.png` existaient sans qu'aucune fiche pointe dessus — les
trois morts-vivants portaient la même. Garrick et les mages noirs ont désormais
la leur.

**Sélecteur de figurine dans l'éditeur de personnages.** `UnitDocument` gagne un
champ `sprite`, sérialisé, vide par défaut — auquel cas la figurine de la classe
fait foi (`ClassDataDB.get_sprite`, table honnête sur ce qu'on a plutôt que sur
ce qu'on voudrait). La liste se lit sur le disque, comme le roster de l'éditeur
de cartes : déposer une planche suffit à la rendre choisissable. Un aperçu montre
la moitié basse de la planche — l'unité de face, celle qu'on voit en jeu.

**Fiches d'unité à l'écran de préparation** (bouton « 📋 Fiches »). L'écran ne
montrait qu'une ligne par unité : nom, niveau, PV, arme. Tout ce qui décide
réellement d'une bataille — les sept statistiques, les **croissances** (qui
pèsent plus sur la valeur d'une unité que ses chiffres du jour), les compétences
débloquées, le fourreau avec l'arme en main, l'inventaire — n'était visible nulle
part avant d'engager. Les unités tombées y figurent aussi, marquées.

`shot.gd` accepte `prep … detail`.

```
bash scripts/test_all.sh --window   # 58 / 573 / 77 OK + test_map + 18 + 14 OK
```

### Passe du 2026-08-08 — la charte graphique, et le certificat Apple abandonné

Deux décisions d'Aurèle ouvrent la passe : **le certificat Développeur Apple ne
sera jamais pris** (200-600 €/an, il ne veut pas payer — la signature macOS
quitte donc le backlog, voir §4), et **les cartes des chapitres attendront**.
Ce qu'il voulait à la place : « améliorer les graphiques. Enfin plutôt choisir
une charte graphique, parce qu'actuellement on utilise la charte de Godot ? »

**La question méritait d'être mesurée avant d'être traitée** — elle était à
moitié vraie. L'état des lieux complet est en §6bis ; en une phrase : les
*boutons* étaient à nous, repeints écran par écran (60 couleurs en dur dans 12
fichiers, 17 `StyleBoxFlat` faits main dans 8 écrans), et tout le reste — champs,
listes déroulantes, compteurs, cases à cocher, barres de défilement, **et la
police** — était d'usine. Le décor 3D, lui, n'a jamais rien eu de Godot.

**Direction retenue : « Velmar — nuit et or »**, choisie sur trois propositions.
Elle formalise ce que les écrans faisaient déjà à tâtons et s'accorde au ciel du
plateau sans y toucher.

Livré : `palette.gd` (source unique), `ciel_theme.gd` (le thème, bâti en code,
icônes dessinées comprises), Cinzel + Alegreya Sans sous licence OFL dans
`assets/fonts/`, et cinq variations nommées.

**Les deux pièges de la passe**, tous deux muets — aucun message d'erreur, aucun
plantage, juste un écran inchangé :

- **un thème ne traverse pas un `CanvasLayer`**, et `Main._mount_ui` en pose un
  autour de chaque écran ; la première application n'a donc strictement rien
  changé, ce que seule la capture d'écran a montré ;
- **`variation_opentype` ignore les clés texte** — `{"wght": 700}` laissait
  Cinzel en Regular, alors que la clé texte marche pour `opentype_features`
  juste à côté. Mesuré en comparant des largeurs : identiques à 400, 700 et 900.

Corrigé au passage, trouvé à l'œil sur les captures : Alegreya Sans compose par
défaut des **chiffres elzéviriens** — hauteurs inégales, certains sous la ligne.
Acceptable en roman, mauvais dans un jeu où l'on compare des PV et des taux de
critique en colonne. `lnum` + `tnum` les redressent et les alignent.

Test 24 (`test_features.gd`) verrouille les deux pièges et la couverture des
widgets. Reste à faire, listé en §6bis : le nettoyage des couleurs en dur, qui
gagnent encore sur le thème là où elles se recouvrent, et les emoji-icônes.

```
bash scripts/test_all.sh --window   # 58 / 588 / 77 OK + test_map + 18 + 14 OK
```

---

### Passe du 2026-08-08 (2) — neuf terrains, dont cinq se bâtissent

Demande d'Aurèle, dans la foulée de la charte : « améliorer les graphiques des
cartes et les possibilités de création dans l'éditeur de map. C'est un univers
d'héroïc fantasy donc tu peux rajouter des options pour des bâtiments ? »

**Neuf terrains ajoutés**, portant la palette de 7 à 16 :

| Bâti | Franchissable | DÉF | Ce qu'on y voit |
|---|---|---|---|
| Village | oui | +1 | Une chaumière : corps de torchis, toit à deux pans |
| Fortin | oui | +2 | Une tourelle de pierre, bannière d'or deux cases sur cinq |
| Porte | oui | +1 | Deux piliers **alignés sur le rempart**, passage libre au milieu |
| Ruines | oui | +1 | Deux colonnes brisées et un bloc effondré |
| Tour | **non** | — | Fût de pierre et toit conique d'ardoise, pleine case |
| Pont | oui | 0 | Platelage de bois, garde-corps **le long de la travée** |
| Sable, Neige, Marais | oui | 0 | Roseaux dans la vase ; cailloux épars sur le sable |

Et la plaine reçoit une touffe d'herbe une case sur trois : une carte de 300
cases n'est plus un tapis uni.

**Une table, plus cinq.** Un terrain était décrit à cinq endroits —
franchissabilité dans `MapData`, teinte dans `TacticsScenery`, nom technique
dans `TacticsGrid`, nom français dans `UnitSheet`, légende dans `CielAI`. En
ajouter un demandait de visiter les cinq. Tout vit maintenant dans
`MapData.TERRAINS` ; les quatre autres endroits y renvoient.

**Deux bugs trouvés en chemin**, aucun des deux visible sans y aller voir :

- **La carte ASCII envoyée à Ciel mentait.** Elle tirait la première lettre du
  nom du terrain : `water` et `wall` étaient tous deux `w`, `path` et `pit` tous
  deux `p` — pendant que la légende, écrite à la main, annonçait des lettres
  distinctes (`a` pour wall, `i` pour pit) que le code n'employait pas. Ciel
  lisait des murs comme des lacs. Les codes sont désormais dans la table, uniques
  et vérifiés par un test ; la légende est engendrée depuis eux.
- **Un arbre sur quatre dépassait le plafond du décor.** `MAX_HEIGHT` est censé
  garantir qu'aucun décor ne cache un pion ; le facteur d'échelle des arbres
  montait à 1,2 et multipliait *aussi* la hauteur. Le test ne l'avait jamais vu
  parce qu'il ne dessinait qu'une seule case de forêt, dont le hachage tombait
  juste. Il en dessine seize maintenant, une par terrain.

**Éditeur — trois gestes qui manquaient** (`map_editor_level.gd`) :

- **le pinceau suit la souris** bouton enfoncé. Un trait ne compte que pour *un*
  coup d'annulation, et ne redessine le décor qu'au relâchement — sinon une carte
  de 32 × 24 recalculerait ses 768 cases à chaque pixel parcouru ;
- **pinceau 1×1, 3×3 ou 5×5**, borné à la grille ;
- **remplissage** d'une zone d'un seul tenant (voisinage à quatre, comme le
  déplacement).

La palette passe à trois rangées — nature, constructions, outils — les seize
boutons ne tenaient plus sur une ligne. Chaque bouton porte la teinte réelle de
son terrain et dit en infobulle ce qu'il coûte et ce qu'il donne.

**Ce que le test tient maintenant** : le centre d'une case praticable reste
libre pour tout décor plus haut que `FLAT_HEIGHT` — la mesure d'avant ne savait
juger que des disques (troncs, frondaisons) ; maisons, piliers et garde-corps
sont des boîtes, dont un garde-corps qui longe presque tout un bord de case et
qu'un cercle circonscrit aurait condamné à tort. On ramène le centre de la case
dans le repère du décor.

Regarder le résultat : `godot --path . --resolution 1600x900 --script shot.gd --
editor sortie.png terrains` charge une carte de démonstration qui montre les
seize terrains à la fois.

```
bash scripts/test_all.sh   # 58 / 600 / 81 OK + test_map
```

---

### Passe du 2026-08-08 (3) — la carte du chapitre 2, et trois défauts

**La carte du chapitre 2 emploie les nouveaux terrains.** 22 cases changées dans
[`outpost_map.tres`](../data/models/world/map/outpost_map.tres), sous une règle
stricte : **aucune franchissabilité modifiée**. Un mur devient une tour (les deux
bloquent), une herbe devient un marais, une forêt devient un village (+1 DÉF dans
les deux cas). Le chapitre se joue donc exactement comme avant en matière de
déplacement et de portée, et aucun pion n'a bougé.

- Le rempart a maintenant **deux tours** encadrant la trouée, une **porte** là où
  le chemin le traverse, et sa **brèche est jonchée de pierres** (ruines).
- Un **hameau au nord**, au bord de la route — ce que le poste protégeait — et le
  **hameau pillé à l'ouest**, derrière le rempart.
- Un **corps de logis effondré** au milieu de la cour, une **redoute** à l'écart
  du chemin, une **roselière** au bord de la mare.

**Deux cases changent d'intérêt tactique, délibérément** : la brèche et la porte
donnent +1 DÉF, la redoute +2. Se battre dans une brèche doit valoir mieux que
se battre en plaine. L'IA locale suit sans rien apprendre — elle raisonne sur le
`def_bonus` d'une case, jamais sur son type. À surveiller à l'essai : le chapitre
est un cran plus dur pour qui attaque un défenseur bien posté.

Un pont manque à l'appel : la mare du chapitre n'offre aucune traversée qui mène
quelque part. En forcer une aurait fait une case praticable isolée.

#### Chasse aux bugs

**1. L'éditeur tombait à l'ouverture si le roster était vide.**
`map_editor_level.gd` prenait `roster_of("player")[0]` sans regarder. Un dossier
de fiches introuvable dans une build installée suffisait — jamais en
développement, où les fiches sont là. Le reste du code savait déjà quoi faire
d'un chemin vide : `place_unit` refuse poliment, le sélecteur annonce un camp
sans unité. C'est le seul endroit qui ne le savait pas.

**2. Une arène engendrée par-dessus des tuiles existantes se montait vide.**
`TacticsArena._generate_from_map_data()` cédait la main une frame après avoir
libéré l'ancien nœud `Tiles`, alors que `_ready` l'appelle **sans l'attendre** :
`serv.setup()` passait sur une arène sans tuiles. Et le nœud seulement
`queue_free` gardait son nom jusqu'à la fin de la frame, donc le nouveau naissait
« @Tiles@2 », introuvable pour qui le cherche par son nom. Aucune arène livrée
n'a à la fois des tuiles à la main et un `MapData` — mais **c'est exactement ce
qu'on obtient en convertissant `map_level.tscn`**, ce qui reste à faire pour cinq
chapitres. La fonction est devenue synchrone (`remove_child` puis `queue_free`,
comme l'éditeur de cartes le fait déjà pour la même raison), et un test monte le
cas de figure.

**3. L'export vers Ciel lisait un terrain sans garde.** Corrigé en passant par
`TacticsGrid.terrain_code()`, qui applique les mêmes vérifications que
`terrain_name()` — une tuile libérée rend « ? » au lieu de faire tomber l'export.
Même famille que le piège de 2026-08-06 : les références aux nœuds libérés ne se
manifestent que dans la build exportée.

Corrigé au passage : activer le remplissage désactivait aussi le glisser de
l'outil d'élévation, qui n'a rien à voir avec lui.

#### Ce qui a été cherché sans rien trouver

Une sonde jetable a passé 300 documents de carte tirés au hasard (tailles
extrêmes, terrains inconnus, unités hors grille, niveaux hors bornes), 120
partitions de zones de remplissage, 400 échanges de combat et les six cartes de
chapitre au crible d'une vingtaine d'invariants : grille toujours accordée à sa
taille, aller-retour JSON fidèle, redimensionnement ne laissant jamais rien
dehors, zones partitionnant exactement la grille, dégâts jamais négatifs,
précision dans [0, 100], nul ne perdant plus de PV qu'il n'en a. **Rien n'a
cédé.** La sonde n'est pas conservée : ces invariants sont déjà tenus par des
tests nommés.

Également passé en revue sans trouver de défaut : aucune mutation d'un matériau
partagé (`TacticsConfig.terrain_material` et le cache de surlignage sont lus,
jamais écrits), prévision de combat et combat réel bâtis sur les mêmes options,
aucune erreur du moteur dans les journaux des six suites.

**Relevé, non corrigé** : `map_generator.gd` (245 lignes) n'est référencé nulle
part et porte sa **propre table de terrains**, figée à sept. Du code mort qui
duplique une source de vérité — même motif que `fe_2d/`, supprimé le 2026-08-06.
À supprimer ou à brancher sur `MapData.TERRAINS`, au choix d'Aurèle.

```
bash scripts/test_all.sh --window   # 58 / 601 / 81 OK + test_map + 18 + 14 OK
```

---

### Passe du 2026-08-08 (4) — le code mort

Balayage complet du dépôt : pour chaque script, scène, ressource, fonction,
constante et signal, comptage des références réelles dans **tous** les fichiers
suivis — code, scènes, ressources, configuration d'export, documentation. Ce qui
n'était nommé nulle part est parti. **1 052 lignes**, et la suite reste au vert.

**Neuf fichiers entiers**, dont deux cascades — un script que seule sa propre
scène référençait, et cette scène que rien ne référençait :

| Fichier | Lignes | Pourquoi il ne servait plus |
|---|---|---|
| `data/modules/menu/main_menu.gd` + `assets/scene/main_menu.tscn` | 391 | Menu d'avant, remplacé par `title_screen.gd`. Il portait encore l'ancienne palette (`#1a1a2e`), donc d'avant la charte |
| `data/models/world/map/map_generator.gd` | 245 | Générateur procédural jamais appelé, avec **sa propre table de terrains** figée à sept. Le relevé de la passe précédente |
| `data/modules/map_editor/map_editor.gd` + `.tscn` | 249 | Peintre de terrain `@tool` de l'éditeur Godot, remplacé par l'éditeur en jeu (`MapEditorLevel`), qui fait tout ce qu'il faisait et le reste |
| `probe_suite.gd` | 146 | Sonde jetable d'une session de débogage passée |
| `test_map.tscn` | 6 | Nœud enveloppant `test_map.gd` — **cassé de toute façon** : ce script étend `SceneTree`, il ne peut pas être attaché à un nœud |
| `tile_converter.tscn` | 6 | Scène enveloppant `TacticsTileService`, dont tout le monde se sert par ses fonctions statiques |
| `pawn.tres` | 6 | Ressource vide ; `pawn.gd` construit la sienne en code |

**Vingt-sept fonctions** que personne n'appelait — ni le code, ni les scènes, ni
les tests, ni la documentation. Vérifiées une par une, et contrôle fait sur les
appels dynamiques (`callv`, `has_method`) : aucune n'y figurait. Réparties sur
20 fichiers, des accesseurs oubliés pour l'essentiel (`has_next`,
`get_chapter_by_id`, `promotion_options`, `can_pawn_move`, `attackable_tiles`,
`preview_combat`…).

**Aucune constante ni aucun signal mort** : les seuls qui l'étaient — les deux
tables de glyphes de terrain de `prep_screen.gd` — avaient déjà été retirés
pendant la passe des terrains, plutôt que d'être étendus à seize entrées.

```
bash scripts/test_all.sh --window   # 58 / 601 / 81 OK + test_map + 18 + 14 OK
```

---

### Passe du 2026-08-08 (5) — les morts qui ressuscitaient, et le terrain au survol

**Le bug, remonté par Aurèle** : « J'ai échoué à la première mission, Lissa,
Virion et Chrom sont morts, sauf que lorsque je veux recommencer il y a
seulement Lissa de mort. »

Deux causes, la même famille — **`queue_free` laisse le nœud enfant jusqu'à la
fin de la frame, mais pas au-delà** :

1. Un pion tombé est rendu invisible, privé de ses collisions, puis **libéré une
   demi-seconde plus tard**. Le report au roster
   (`ChapterRunner.player_unit_snapshots()`) ne lisait que les pions **encore en
   scène**, et il n'a lieu qu'à la **fin du chapitre**. Tout ce qui était mort
   depuis plus d'une demi-seconde n'était donc jamais reporté : seule la
   dernière chute de la bataille comptait. Chrom et Virion se relevaient
   intacts, Lissa restait morte parce qu'elle était tombée en dernier.
2. `_apply_roster()` écartait les unités non déployées par un simple
   `queue_free()` : pendant une frame, elles étaient encore enfants de
   `level.player`. Tout ce qui parcourt ce nœud les comptait — l'objectif,
   l'export vers Ciel, et la mémoire des morts, qui inscrivait au roster des
   unités jamais entrées en lice.

**Correction** : le runner retient l'état de chaque unité du joueur **à chaque
frame** (`_last_seen`), et le report rend l'union des unités en scène et des
disparues. À chaque frame et non toutes les demi-secondes : l'objectif s'évalue
à cette période-là, exactement le délai de libération d'un mort — retenir au
même rythme, c'est jouer à pile ou face sur chaque mort. Et les non-déployés
quittent l'arbre (`remove_child`) avant d'être libérés.

Un test monte le cas exact : un pion tombe, quitte la scène, quarante frames
passent, et il doit toujours être reporté au roster avec zéro PV.

**Demandé aussi** : voir le terrain d'une case au survol, et ce qu'il donne. Un
encart s'allume au-dessus de la fiche d'unité — « Forêt · 🛡 +1 DÉF », « Montagne
· infranchissable · 🛡 +3 DÉF ». Avec seize terrains dont quatre défensifs,
reconnaître un fortin d'une ruine à la couleur du sol était devenu un pari.

La phrase est écrite par `MapData.type_summary()` et **sert aussi d'infobulle
dans l'éditeur** : celui qui dessine une carte et celui qui la joue lisent la
même chose de la même case. Un test le tient.

```
bash scripts/test_all.sh --window   # 58 / 601 / 84 OK + test_map + 18 + 14 OK
```
