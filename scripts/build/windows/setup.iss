; Installeur Windows de Ciel Emblem — Inno Setup 6.
;
; Compilation (depuis la racine du dépôt) :
;   ISCC.exe /DMyAppVersion=0.1.0 scripts\build\windows\setup.iss
;   wine ISCC.exe ...              (macOS / Linux)
;
; Normalement appelé par scripts/build/package.sh, qui prépare le dossier source
; (build/windows/staging : exe + pck + ciel_game/ + notice) et passe la version
; lue dans project.godot.

#define MyAppName "Ciel Emblem"
#define MyAppPublisher "CielAI"
#define MyAppExeName "CielEmblem.exe"
#define MyAppURL "https://github.com/Orthos-max/RPG"

; Version injectée par package.sh (/DMyAppVersion=…), repli si compilé à la main.
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

; Dossier à empaqueter : le staging Windows produit par package.sh.
; Surchargeable par /DSourceDir=… (chemin absolu Windows).
#ifndef SourceDir
  #define SourceDir "..\..\..\build\windows\staging"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\..\build\dist"
#endif

; Icône : réutilisée si package.sh a su convertir assets/textures/ui/icons/icon.png
; en .ico. Sinon Inno Setup extrait celle de l'exécutable.
#define IconFile SourceDir + "\ciel-emblem.ico"

[Setup]
; GUID propre à Ciel Emblem — ne jamais le changer, il identifie le produit
; pour les mises à jour et la désinstallation.
AppId={{BADE6901-4FB0-425D-873A-ABAD2C7635AF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
VersionInfoVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayName={#MyAppName} {#MyAppVersion}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir={#OutputDir}
OutputBaseFilename=Ciel-Emblem-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installation par défaut sans droits admin (repli {userpf}) ; l'assistant
; propose « pour tous les utilisateurs » si l'on peut élever les privilèges.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline dialog
#if FileExists(IconFile)
SetupIconFile={#IconFile}
#endif

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Tout le staging : l'exe, le .pck, le pont CielAI (ciel_game/) et la notice.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Notice (LISEZ-MOI)"; Filename: "{app}\LISEZ-MOI.txt"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Le jeu ne laisse rien à côté de l'exécutable, mais on nettoie le dossier s'il
; reste vide. Les sauvegardes de %APPDATA%\Godot\app_userdata\Ciel Emblem\ sont
; volontairement conservées : désinstaller ne doit pas effacer une campagne.
Type: dirifempty; Name: "{app}"
