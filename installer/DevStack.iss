#define MyAppName "DevStack"
#define MyAppVersion "0.1.0-alpha.1"
#define MyAppPublisher "DevStack"
#define MyAppExeName "DevStack.ControlPanel.exe"

[Setup]
AppId={{7E112D15-A843-4D65-AC75-6E3A57AD0C71}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\DevStack
DefaultGroupName=DevStack
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\artifacts
OutputBaseFilename=DevStack-Setup-{#MyAppVersion}-win-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion=0.1.0.1
VersionInfoDescription=DevStack online installer
VersionInfoProductName=DevStack
VersionInfoProductVersion=0.1.0.1

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\artifacts\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\scripts\install-runtime.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\verify-runtime-manifest.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\setup-runtime.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\trim-runtime.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\show-database-password.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\DevStack"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\DevStack"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\setup-runtime.ps1"" -InstallRoot ""{app}"""; StatusMsg: "Downloading and configuring Apache, PHP, MariaDB and phpMyAdmin..."; Flags: waituntilterminated; AfterInstall: VerifyRuntimeSetup
Filename: "{app}\{#MyAppExeName}"; Description: "Launch DevStack"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\runtime\apache"
Type: filesandordirs; Name: "{app}\runtime\php"
Type: filesandordirs; Name: "{app}\runtime\mariadb"
Type: files; Name: "{app}\.devstack-ready"

[Code]
procedure VerifyRuntimeSetup;
begin
  if not FileExists(ExpandConstant('{app}\.devstack-ready')) then
    RaiseException('Runtime download or MariaDB initialization failed. Review the setup log and try again.');
end;
