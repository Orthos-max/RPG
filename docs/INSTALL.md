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
1. Télécharger `CielEmblem.zip` et le décompresser où l'on veut.
2. Double-cliquer sur `CielEmblem.exe`.
3. Si Windows SmartScreen s'interpose : **Informations complémentaires** → **Exécuter quand même**.

### Linux
1. Télécharger `CielEmblem.x86_64`.
2. Le rendre exécutable : `chmod +x CielEmblem.x86_64`.
3. Le lancer : `./CielEmblem.x86_64`.

### Une fois dans le jeu
* **Nouvelle partie** → campagne solo (3 chapitres), difficulté et mort permanente réglables sur l'écran-titre.
* **Continuer** → reprend la dernière sauvegarde.
* **Escarmouche CielAI** → une carte, camp adverse piloté par l'IA externe Ciel (voir §3).
* **Échap** → retour à l'écran-titre.

Commandes de bataille : souris (clic pour sélectionner/déplacer), manette et clavier
supportés (`ZQSD`/`WASD` pour la caméra, `A`/`E` pour pivoter).

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

### Packaging optionnel (macOS `.dmg`)
```bash
brew install create-dmg
bash scripts/build/export.sh macos
unzip -q build/macos/CielEmblem.zip -d build/macos/
create-dmg --volname "Ciel Emblem" build/macos/CielEmblem.dmg "build/macos/Ciel Emblem.app"
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

## 4. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `Godot introuvable` | binaire hors des chemins connus | `export GODOT_BIN=/chemin/vers/Godot` |
| Export en échec immédiat | modèles d'exportation absents | Éditeur → Gérer les modèles d'exportation |
| `Aucun état disponible` | le jeu ne tourne pas, ou autre dossier | `state.sh --path`, puis `CIEL_USERDATA` |
| Ciel ne joue pas son tour | contrôle basculé sur l'IA locale | `command.sh toggle on` |
| Commande sans effet | ordre rejeté | lire `ai_feedback.json` (ou `last_error` dans l'état) |
| L'app macOS ne s'ouvre pas | build non signée | clic droit → Ouvrir → Ouvrir |

Tests de non-régression (développement) :
```bash
godot --headless --path . --script test_combat.gd
godot --headless --path . --script test_map.gd
godot --headless --path . --script test_features.gd
```
