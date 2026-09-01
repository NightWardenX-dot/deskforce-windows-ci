; DeskForce Windows installer (Inno Setup 6)
; CI passes /DMyAppVersion=x.y.z /DSourceDir=path /DOutputDir=path

#ifndef MyAppVersion
  #define MyAppVersion "1.2.8"
#endif
#ifndef SourceDir
  #define SourceDir "..\deskforce-pack"
#endif
#ifndef OutputDir
  #define OutputDir "..\out"
#endif

#define MyAppName "DeskForce"
#define MyAppPublisher "DeskForce"
#define MyAppURL "https://deskforce.dr6ter.ru"
#define MyAppExeName "DeskForce.exe"

[Setup]
AppId={{B8E4F2A1-3C5D-4E7F-9A1B-2D3C4E5F6071}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/downloads/update.json
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputDir={#OutputDir}
OutputBaseFilename=DeskForce-Setup
SetupIconFile=..\branding\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "autostart"; Description: "Запускать DeskForce при входе в Windows"; GroupDescription: "Автозапуск:"; Flags: checkedonce

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\DeskForce Tray.lnk"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--tray"; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-service"; StatusMsg: "Установка службы DeskForce..."; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Parameters: "--tray"; Description: "Запустить DeskForce в системном трее"; Flags: postinstall nowait skipifsilent runhidden

[UninstallRun]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--before-uninstall"; RunOnceId: "DeskForceBeforeUninstall"; Flags: runhidden waituntilterminated

[UninstallDelete]
Type: filesandordirs; Name: "{userstartup}\DeskForce.lnk"
Type: filesandordirs; Name: "{userstartup}\DeskForce Tray.lnk"
