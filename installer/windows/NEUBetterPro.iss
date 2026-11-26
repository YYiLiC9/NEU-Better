; NEU Better Windows installer (Inno Setup 6)
; Build with: tools\build_windows_installer.ps1

#ifndef MyAppVersion
  #define MyAppVersion "0.4.1"
#endif

#define MyAppName "NEUBetterPro"
#define MyAppPublisher "YYiLiC9"
#define MyAppURL "https://github.com/YYiLiC9/NEU-Better"
#define MyAppExeName "NEUBetterPro.exe"

[Setup]
AppId={{8C0B5E7A-3D49-4F2D-9C61-7E5B2A1D9F30}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Programs\NEUBetterPro
DefaultGroupName={#MyAppName}
DisableDirPage=no
UsePreviousAppDir=yes
PrivilegesRequired=lowest
AllowNoIcons=yes
OutputDir=..\..\dist
OutputBaseFilename=NEU-Better-{#MyAppVersion}-x64-installer
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\neu_better_pro"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\NEUBetterPro"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
