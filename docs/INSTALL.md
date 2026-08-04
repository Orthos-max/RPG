# Installer & jouer à Ciel Emblem

Deux publics, deux chemins : **jouer** (aucune connaissance technique requise) et
**construire** le jeu depuis les sources.

---

## 1. Jouer (sans installer Godot)

### macOS
1. Télécharger `CielEmblem.zip`.
2. Double-cliquer dessus : `Ciel Emblem.app` apparaît.
3. Glisser l'app dans le dossier **Applications**.
4. **Premier lancement** : clic droit sur l'app → **Ouvrir** → **Ouvrir**.
   (macOS bloque les apps non signées au double-clic ; ce détour n'est nécessaire qu'une fois.)

### Windows
**Avec l'installeur (recommandé)**
1. Télécharger `Ciel-Emblem-Setup-<version>.exe`.
2. Double-cliquer dessus et suivre l'assistant.
   Si Windows SmartScreen s'interpose : **Informations complémentaires** → **Exécuter quand même**
   (la build n'est pas signée).
3. Le jeu s'installe dans `Program Files\Ciel Emblem` (ou dans le dossier de
   l'utilisateur si l'on n'a pas les droits administrateur) avec un raccourci
   **menu Démarrer** et, au choix, un raccourci **bureau**.
4. Désinstallation : *Paramètres → Applications → Ciel Emblem → Désinstaller*.
   Les sauvegardes de campagne, elles, restent dans `%APPDATA%\Godot\app_userdata\Ciel Emblem\`.

**Sans installeur (version portable)**
1. Télécharger `CielEmblem-<version>-windows.zip` et le décompresser où l'on veut.
2. Double-cliquer sur `CielEmblem.exe`.

### Linux
1. Télécharger `CielEmblem.x86_64`.
2. Le rendre exécutable : `chmod +x CielEmblem.x86_64`.
3. Le lancer : `./CielEmblem.x86_64`.

### Une fois dans le jeu
* **Nouvelle partie** → campagne solo (3 chapitres), difficulté et mort permanente réglables sur l'écran-titre.
* **Continuer** → reprend la dernière sauvegarde.
* **Escarmouche CielAI** → une carte, camp adverse piloté par l'IA externe Ciel (voir §3).
* **Duel local (2 joueurs)** → deux humains sur la même machine, chacun son tour (voir §4).
* **Créer une partie en ligne / Rejoindre avec un code** → duel privé entre amis (voir §4).
* **Échap** → retour à l'écran-titre.

Entre deux chapitres, le bouton **Intendance** de l'écran de préparation permet de
dépenser l'or : potions, objets à gain permanent, soins des blessés et recrutement.

Commandes de bataille : souris (clic pour sélectionner/déplacer), manette et clavier
supportés (`ZQSD`/`WASD` pour la caméra, `A`/`E` pour pivoter).

Après avoir choisi **Attack** (ou **Heal**), survoler une cible à portée affiche la
**prévision de combat** en haut à droite : dégâts totaux, nombre de coups, précision,
critique et PV restants — en rouge si le coup tue, en ambre s'il ne tue qu'en cas de
critique. Les bonus en jeu (triangle des armes, terrain, soutien, arme efficace,
compétences à déclenchement) sont rappelés en dessous.

---

## 2. Construire depuis les sources

### Prérequis
* **Godot 4.3** (le projet est verrouillé sur cette version).
* Les **modèles d'exportation 4.3** : dans l'éditeur, `Éditeur → Gérer les modèles d'exportation → Télécharger`.

### Lancer depuis les sources
```bash
bash scripts/ciel_game/launch.sh
# ou : godot --path .
```

### Exporter
```bash
bash scripts/build/export.sh                     # plateforme courante
bash scripts/build/export.sh macos windows linux # tout d'un coup
GODOT_BIN=/chemin/vers/Godot bash scripts/build/export.sh
```

Résultats dans `build/<plateforme>/`. La recette est versionnée dans `export_presets.cfg`.

### Packaging (livrables prêts à distribuer)
```bash
bash scripts/build/package.sh                      # plateforme courante
bash scripts/build/package.sh macos windows linux  # tout d'un coup
bash scripts/build/package.sh --no-export macos    # empaqueter sans réexporter
```

Résultats dans `build/dist/` :

| Plateforme | Livrable | Contenu |
|---|---|---|
| macOS | `CielEmblem-<version>-macos.dmg` | `Ciel Emblem.app`, notice, pont `ciel_game/` |
| Windows | `CielEmblem-<version>-windows.zip` | `CielEmblem.exe`, notice, pont `ciel_game/` |
| Windows | `Ciel-Emblem-Setup-<version>.exe` | installeur graphique (voir ci-dessous) |
| Linux | `CielEmblem-<version>-linux.tar.gz` | binaire, `install.sh`, raccourci `.desktop`, pont |

Le `.dmg` utilise `create-dmg` s'il est installé (`brew install create-dmg`), sinon
`hdiutil`, fourni avec macOS — aucune dépendance obligatoire.

#### Installeur Windows (Inno Setup)

La recette est dans `scripts/build/windows/setup.iss` ; `package.sh` la compile
automatiquement après avoir produit le `.zip`, **si** le compilateur Inno Setup 6
est disponible. Sinon il le signale et se contente du `.zip` — le packaging
n'échoue pas pour autant.

| Plateforme de build | Installer le compilateur |
|---|---|
| Windows | `winget install JRSoftware.InnoSetup` (fournit `ISCC.exe`) |
| macOS / Linux | Inno Setup 6 dans un préfixe Wine ([jrsoftware.org](https://jrsoftware.org/isinfo.php)), puis `brew install wine-stable` / paquet `wine` |

Si `ISCC.exe` n'est pas à l'emplacement habituel du préfixe Wine, l'indiquer :

```bash
ISCC_PATH="$HOME/.wine/drive_c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
  bash scripts/build/package.sh --no-export windows
```

Compilation à la main, sans passer par `package.sh` (le dossier source est le
staging produit par le packaging) :

```bash
ISCC.exe /DMyAppVersion=0.1.0 /DSourceDir=..\..\..\build\windows\staging \
         scripts\build\windows\setup.iss
```

L'installeur pose l'exécutable, le `.pck`, la notice **et le pont `ciel_game/`**
dans le dossier d'installation ; il crée les raccourcis menu Démarrer/bureau et
une entrée de désinstallation. Il s'installe sans droits administrateur par
défaut (`{userpf}`) et propose l'installation pour tous les utilisateurs
(`Program Files`) si les privilèges peuvent être élevés. L'icône est reprise de
`assets/textures/ui/icons/icon.png` quand ImageMagick (`magick`) ou `icotool` est
installé pour la convertir en `.ico` ; sinon Inno Setup extrait celle de l'exe.

Sur Linux, `install.sh` copie le jeu dans `~/.local/share/ciel-emblem` et pose une
entrée dans le menu des applications :

```bash
tar -xzf CielEmblem-0.1.0-linux.tar.gz -C ciel-emblem && cd ciel-emblem && bash install.sh
```

### Signature (facultatif, macOS)
Sans signature, l'app fonctionne mais exige le clic droit → Ouvrir au premier lancement.
Avec un certificat Développeur Apple : renseigner `codesign/identity` dans
`export_presets.cfg` et passer `codesign/codesign=1`.

---

## 3. Brancher l'IA externe (CielAI)

Le pont est un simple échange de fichiers JSON — aucune dépendance réseau.
Le protocole complet est décrit dans [`CIEL_PROTOCOL.md`](CIEL_PROTOCOL.md).

```bash
# Où le jeu écrit son état (résout automatiquement le dossier de l'OS)
bash scripts/ciel_game/state.sh --path

# Lire l'état de la partie en cours
bash scripts/ciel_game/state.sh
bash scripts/ciel_game/state.sh --watch

# Jouer un tour adverse
bash scripts/ciel_game/command.sh select_pawn Skeleton
bash scripts/ciel_game/command.sh move 5 3
bash scripts/ciel_game/command.sh attack Lord
bash scripts/ciel_game/command.sh end_turn

# Rendre le camp adverse à l'IA locale (et inversement)
bash scripts/ciel_game/command.sh toggle off
```

Sur une build packagée, les scripts sont copiés à côté du binaire (`ciel_game/`).
Pour pointer un dossier d'échange particulier :

```bash
export CIEL_USERDATA="$HOME/mon/dossier/ciel"
```

| OS | Dossier d'échange par défaut |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/Ciel Emblem/` |
| Linux | `~/.local/share/godot/app_userdata/Ciel Emblem/` |
| Windows | `%APPDATA%\Godot\app_userdata\Ciel Emblem\` |

Sauvegardes de campagne : sous-dossier `saves/`. Replays de bataille : `replays/`.

---

## 4. Jouer à deux

### Duel local (même machine)
Écran-titre → **Duel local (2 joueurs)**. Les deux camps se jouent à la souris,
chacun son tour ; le bandeau en haut de l'écran rappelle à qui de jouer.

### Partie en ligne (réseau local ou VPN entre amis)
1. L'hôte : **Créer une partie en ligne** → un **code de 7 caractères** s'affiche
   (par ex. `KJH4FGA`), il choisit la carte et attend.
2. L'invité : **Rejoindre avec un code** → il saisit le code.
3. L'hôte lance la bataille ; les deux machines chargent la même carte.

**Ciel comme troisième camp** — sur l'écran « Créer une partie », l'hôte peut
cocher *Inviter Ciel comme troisième camp*. La bataille compte alors trois
armées : l'hôte (bleu), l'invité (vert) et Ciel (rouge), **chacun pour soi**.
Comme les cartes n'ont que deux armées, l'armée adverse est partagée en deux au
chargement : un pion sur deux pour l'invité, le reste pour Ciel. Le partage est
déterministe, les deux machines obtiennent donc la même répartition.

L'hôte joue le camp bleu, l'invité le camp rouge. **L'hôte fait autorité** : il
simule la bataille et valide chaque ordre reçu (mêmes règles que pour Ciel). Si
l'invité se déconnecte, l'IA locale reprend son camp — la partie ne se fige pas.

Côté invité, les commandes sont : clic sur un de ses pions pour le sélectionner,
clic sur une case pour se déplacer, clic sur un ennemi pour l'attaquer,
`E` pour finir le pion, `T` pour finir le tour, `G` pour se mettre en garde.

**Réseau** : port **24710** en UDP (ENet). Le code encode l'adresse IPv4 de l'hôte,
il fonctionne donc sur un même réseau local ou via un VPN (Tailscale, Hamachi…).
Pour jouer à travers Internet sans VPN, il faut rediriger ce port sur la box de
l'hôte. Si la machine a plusieurs interfaces et que le code annonce la mauvaise
adresse, forcer celle qui convient :

```bash
CIEL_HOST_IP=192.168.1.42 bash scripts/ciel_game/launch.sh
```

Test de bon fonctionnement du transport (deux processus locaux) :

```bash
bash scripts/test_net.sh
```

---

## 5. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `Godot introuvable` | binaire hors des chemins connus | `export GODOT_BIN=/chemin/vers/Godot` |
| Export en échec immédiat | modèles d'exportation absents | Éditeur → Gérer les modèles d'exportation |
| Pas de `Ciel-Emblem-Setup-*.exe` | compilateur Inno Setup introuvable | l'installer, ou `ISCC_PATH=/chemin/ISCC.exe` |
| `Aucun état disponible` | le jeu ne tourne pas, ou autre dossier | `state.sh --path`, puis `CIEL_USERDATA` |
| Ciel ne joue pas son tour | contrôle basculé sur l'IA locale | `command.sh toggle on` |
| Commande sans effet | ordre rejeté | lire `ai_feedback.json` (ou `last_error` dans l'état) |
| L'app macOS ne s'ouvre pas | build non signée | clic droit → Ouvrir → Ouvrir |
| « Code invalide » | code mal recopié | 7 caractères, ni I ni O ni 0 ni 1 |
| L'invité ne se connecte pas | pare-feu ou mauvaise interface | ouvrir le port 24710/UDP, ou `CIEL_HOST_IP=…` |
| Partie en ligne figée | invité déconnecté | l'IA locale reprend le camp automatiquement |

Tests de non-régression (développement) :
```bash
godot --headless --path . --script test_combat.gd    # combat FE
godot --headless --path . --script test_map.gd       # cartes & terrains
godot --headless --path . --script test_features.gd  # logique des features
godot --headless --path . --script test_battle.gd    # intégration campagne + pont
bash scripts/test_net.sh                             # transport réseau (2 processus)
```
