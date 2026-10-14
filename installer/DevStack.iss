#define MyAppName "DevStack"
#define MyAppVersion "1.0.0-rc.1"
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
VersionInfoVersion=1.0.0.1
VersionInfoDescription=DevStack online installer
VersionInfoProductName=DevStack
VersionInfoProductVersion=1.0.0.1

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
Filename: "{app}\{#MyAppExeName}"; Description: "Launch DevStack"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\runtime\apache"
Type: filesandordirs; Name: "{app}\runtime\php"
Type: filesandordirs; Name: "{app}\runtime\mariadb"
Type: files; Name: "{app}\.devstack-ready"
Type: files; Name: "{app}\setup-progress.txt"

[Code]
const
  WAIT_OBJECT_0 = 0;
  WAIT_TIMEOUT = $102;

function WaitForSingleObject(hHandle: Integer; dwMilliseconds: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';

function GetExitCodeProcess(hProcess: Integer; var lpExitCode: Cardinal): Boolean;
  external 'GetExitCodeProcess@kernel32.dll stdcall';

function CloseHandle(hObject: Integer): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

procedure UpdateRuntimeProgress;
var
  ProgressText: String;
  FirstSeparator: Integer;
  SecondSeparator: Integer;
  Completed: Integer;
  Total: Integer;
  MessageText: String;
begin
  if not LoadStringFromFile(ExpandConstant('{app}\setup-progress.txt'), ProgressText) then
    exit;

  FirstSeparator := Pos('|', ProgressText);
  SecondSeparator := Pos('|', Copy(ProgressText, FirstSeparator + 1, Length(ProgressText)));
  if SecondSeparator > 0 then
    SecondSeparator := SecondSeparator + FirstSeparator;
  if (FirstSeparator = 0) or (SecondSeparator = 0) then
    exit;

  try
    Completed := StrToInt(Copy(ProgressText, 1, FirstSeparator - 1));
    Total := StrToInt(Copy(ProgressText, FirstSeparator + 1, SecondSeparator - FirstSeparator - 1));
    MessageText := Trim(Copy(ProgressText, SecondSeparator + 1, Length(ProgressText)));
    WizardForm.ProgressGauge.Max := Total;
    WizardForm.ProgressGauge.Position := Completed;
    WizardForm.StatusLabel.Caption := MessageText;
  except
    // Ignore a partially written progress update and try again on the next poll.
  end;
end;

procedure RunRuntimeSetup;
var
  SetupHandle: Integer;
  ExitCode: Cardinal;
  Parameters: String;
begin
  Parameters := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\scripts\setup-runtime.ps1') + '" -InstallRoot "' +
    ExpandConstant('{app}') + '" -ProgressPath "' +
    ExpandConstant('{app}\setup-progress.txt') + '"';

  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Parameters, '', SW_HIDE, ewNoWait, SetupHandle) then
    RaiseException('Could not start the DevStack runtime setup process.');

  repeat
    UpdateRuntimeProgress;
    WizardForm.ProcessMessages;
  until WaitForSingleObject(SetupHandle, 250) <> WAIT_TIMEOUT;

  UpdateRuntimeProgress;
  if not GetExitCodeProcess(SetupHandle, ExitCode) then
    RaiseException('Could not determine the runtime setup result.');
  CloseHandle(SetupHandle);

  if ExitCode <> 0 then
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
