#define MyAppName "PHP Windows DevStack"
#define MyAppVersion "1.0.0-rc.2"
#define MyAppPublisher "PHP Windows DevStack"
#define MyAppExeName "DevStack.ControlPanel.exe"

[Setup]
AppId={{7E112D15-A843-4D65-AC75-6E3A57AD0C71}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName=C:\PHPDevStack
DefaultGroupName=PHP Windows DevStack
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\artifacts
OutputBaseFilename=PHP-Windows-DevStack-Setup-{#MyAppVersion}-win-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
SetupLogging=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion=1.0.0.2
VersionInfoDescription=PHP Windows DevStack online installer
VersionInfoProductName=PHP Windows DevStack
VersionInfoProductVersion=1.0.0.2

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
Name: "{group}\PHP Windows DevStack"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\PHP Windows DevStack"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch PHP Windows DevStack"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\runtime\apache"
Type: filesandordirs; Name: "{app}\runtime\php"
Type: filesandordirs; Name: "{app}\runtime\mariadb"
Type: files; Name: "{app}\.devstack-ready"
Type: files; Name: "{app}\setup-progress.txt"

[Code]
procedure InitializeWizard;
begin
  WizardForm.WelcomeLabel2.Caption :=
    'PHP Windows DevStack is a native, portable Windows development environment for PHP applications.' + #13#10#13#10 +
    'Apache HTTP Server, PHP 8.5 and MariaDB with a desktop control panel will be installed.';
  WizardForm.WelcomeLabel2.AutoSize := False;
  WizardForm.WelcomeLabel2.Width := WizardForm.WelcomeLabel2.Parent.ClientWidth - WizardForm.WelcomeLabel2.Left - 24;
end;

const
  RUNTIME_PROGRESS_TOTAL = 7;

procedure RuntimeSetupLog(const S: String; const Error, FirstLine: Boolean);
var
  MessageText: String;
begin
  MessageText := Trim(S);
  if MessageText = '' then
    exit;

  WizardForm.StatusLabel.Caption := MessageText;
  if Pos('[1/4]', MessageText) > 0 then
    WizardForm.ProgressGauge.Position := 0
  else if Pos('[2/4]', MessageText) > 0 then
    WizardForm.ProgressGauge.Position := 1
  else if Pos('[3/4]', MessageText) > 0 then
    WizardForm.ProgressGauge.Position := 2
  else if Pos('[4/4]', MessageText) > 0 then
    WizardForm.ProgressGauge.Position := 3
  else if Pos('Initializing the local MariaDB', MessageText) > 0 then
    WizardForm.ProgressGauge.Position := 5
  else if Pos('Finalizing runtime setup', MessageText) > 0 then
    WizardForm.ProgressGauge.Position := 6
  else if Pos('DevStack runtime setup completed', MessageText) > 0 then
    WizardForm.ProgressGauge.Position := RUNTIME_PROGRESS_TOTAL;
  WizardForm.Refresh;
end;

procedure RunRuntimeSetup;
var
  ResultCode: Integer;
  Parameters: String;
begin
  Parameters := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\scripts\setup-runtime.ps1') + '" -InstallRoot "' +
    ExpandConstant('{app}') + '" -ProgressPath "' +
    ExpandConstant('{app}\setup-progress.txt') + '"';

  WizardForm.ProgressGauge.Max := RUNTIME_PROGRESS_TOTAL;
  WizardForm.ProgressGauge.Position := 0;
  if not ExecAndLogOutput(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode, @RuntimeSetupLog) then
    RaiseException('Could not start the DevStack runtime setup process.');
  if ResultCode <> 0 then
    RaiseException('Runtime download or MariaDB initialization failed. Review the setup log and try again.');
end;

procedure VerifyRuntimeSetup;
begin
  if not FileExists(ExpandConstant('{app}\.devstack-ready')) then
    RaiseException('Runtime download or MariaDB initialization failed. Review the setup log and try again.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RunRuntimeSetup;
    VerifyRuntimeSetup;
  end;
end;
