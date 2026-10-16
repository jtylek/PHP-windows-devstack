#define MyAppName "PHP Windows DevStack"
#define MyAppVersion "1.0.0-rc.9"
#define MyAppPublisher "PHP Windows DevStack"
#define MyAppExeName "DevStack.ControlPanel.exe"

[Setup]
AppId={{7E112D15-A843-4D65-AC75-6E3A57AD0C71}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName=C:\PHPDevStack
DisableDirPage=no
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
CloseApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion=1.0.0.9
VersionInfoDescription=PHP Windows DevStack online installer
VersionInfoProductName=PHP Windows DevStack
VersionInfoProductVersion=1.0.0.9

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"
Name: "backup"; Description: "Create a safety backup when updating an existing installation (recommended; may take a long time)"; Flags: checkablealone

[Files]
Source: "..\artifacts\publish\*"; DestDir: "{app}"; Excludes: "www\*,runtime\templates\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\artifacts\publish\www\*"; DestDir: "{app}\www"; Flags: onlyifdoesntexist uninsneveruninstall recursesubdirs createallsubdirs
Source: "..\artifacts\publish\runtime\templates\*"; DestDir: "{app}\runtime\templates"; Flags: onlyifdoesntexist uninsneveruninstall recursesubdirs createallsubdirs
Source: "..\runtime\templates\mariadb.ini.template"; DestDir: "{app}\runtime\template-defaults"; Flags: ignoreversion
Source: "..\scripts\prepare-upgrade.ps1"; Flags: dontcopy
Source: "..\runtime\manifest\components.json"; DestName: "upgrade-components.json"; Flags: dontcopy
Source: "..\scripts\merge-mariadb-template.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
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
var
  UpgradeReport: String;
  UpgradeProgressPage: TOutputProgressWizardPage;
  UpgradeCancelButton: TNewButton;
  UpgradeMinimizeButton: TNewButton;

function ShowWindow(hWnd: THandle; nCmdShow: Integer): Boolean;
  external 'ShowWindow@user32.dll stdcall';

procedure SetUpgradeProgress(const MessageText: String);
begin
  if Assigned(UpgradeProgressPage) then
    UpgradeProgressPage.SetText(MessageText, 'Your existing projects and databases are being protected.');
end;

procedure CancelUpgradeProgress(Sender: TObject);
begin
  SaveStringToFile(ExpandConstant('{tmp}\upgrade-cancel.txt'), 'cancel', False);
  UpgradeCancelButton.Enabled := False;
  SetUpgradeProgress('Cancellation requested. Setup will stop after the current file and will not replace installation files.');
end;

procedure MinimizeUpgradeProgress(Sender: TObject);
begin
  ShowWindow(WizardForm.Handle, 6);
end;

procedure UpgradePreflightLog(const S: String; const Error, FirstLine: Boolean);
var
  MessageText: String;
begin
  MessageText := Trim(S);
  if Pos('DEVSTACK-UPGRADE|BACKUP_CONFIRM|', MessageText) = 1 then
  begin
    MessageText := Copy(MessageText, Length('DEVSTACK-UPGRADE|BACKUP_CONFIRM|') + 1, MaxInt);
    SetUpgradeProgress('Backup estimate is ready. Review the estimate and choose whether to continue.');
    if MsgBox(MessageText + #13#10#13#10 +
      'Creating and verifying the backup can take a long time. Please be patient. Continue with the backup?',
      mbConfirmation, MB_OKCANCEL) = IDOK then
      SaveStringToFile(ExpandConstant('{tmp}\upgrade-decision.txt'), 'continue', False)
    else
      SaveStringToFile(ExpandConstant('{tmp}\upgrade-decision.txt'), 'cancel', False);
  end
  else if Pos('DEVSTACK-UPGRADE|', MessageText) = 1 then
  begin
    SetUpgradeProgress(Copy(MessageText, Length('DEVSTACK-UPGRADE|') + 1, MaxInt));
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpReady then
  begin
    if FileExists(ExpandConstant('{app}\DevStack.ControlPanel.exe')) then
      if WizardIsTaskSelected('backup') then
        WizardForm.ReadyMemo.Lines.Insert(0, 'UPDATE EXISTING INSTALLATION - a safety backup is selected. Setup will estimate its size and warn before creating it; the copy and verification can take a long time.')
      else
        WizardForm.ReadyMemo.Lines.Insert(0, 'UPDATE EXISTING INSTALLATION - backup skipped by user. If setup fails, there will be no setup-created rollback copy.')
    else if DirExists(ExpandConstant('{app}')) then
      WizardForm.ReadyMemo.Lines.Insert(0, 'EXISTING FOLDER - setup will verify it before making changes.')
    else
      WizardForm.ReadyMemo.Lines.Insert(0, 'FRESH INSTALLATION');
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
  Parameters: String;
  CancelParameter: String;
  DecisionParameter: String;
  ReportText: AnsiString;
  Started: Boolean;
  IsUpgrade: Boolean;
begin
  Result := '';
  IsUpgrade := FileExists(ExpandConstant('{app}\DevStack.ControlPanel.exe'));
  ExtractTemporaryFile('prepare-upgrade.ps1');
  ExtractTemporaryFile('upgrade-components.json');
  Parameters := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\prepare-upgrade.ps1') +
    '" -InstallRoot "' + ExpandConstant('{app}') + '" -ManifestPath "' + ExpandConstant('{tmp}\upgrade-components.json') +
    '" -ResultPath "' + ExpandConstant('{tmp}\upgrade-report.txt') + '"';
  CancelParameter := ' -CancelFile "' + ExpandConstant('{tmp}\upgrade-cancel.txt') + '"';
  DecisionParameter := '';
  if IsUpgrade and WizardIsTaskSelected('backup') and not WizardSilent then
    DecisionParameter := ' -DecisionFile "' + ExpandConstant('{tmp}\upgrade-decision.txt') + '"';
  Started := False;
  try
    if not WizardSilent then
    begin
      SetUpgradeProgress('Checking the existing installation...');
      UpgradeProgressPage.Show;
      Started := True;
    end;
    DeleteFile(ExpandConstant('{tmp}\upgrade-cancel.txt'));
    DeleteFile(ExpandConstant('{tmp}\upgrade-decision.txt'));
    if IsUpgrade and not WizardIsTaskSelected('backup') then
      Parameters := Parameters + ' -SkipBackup';
    if not ExecAndLogOutput(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Parameters + CancelParameter + DecisionParameter, '', SW_HIDE, ewWaitUntilTerminated, ExitCode, @UpgradePreflightLog) then
    begin
      Result := 'Could not run update preflight. No application files have been replaced.';
      exit;
    end;
    if LoadStringFromFile(ExpandConstant('{tmp}\upgrade-report.txt'), ReportText) then
      UpgradeReport := String(ReportText)
    else
      UpgradeReport := 'Update preflight did not produce a report.';
    if ExitCode <> 0 then
      Result := UpgradeReport
    else if not WizardSilent then
      MsgBox(UpgradeReport, mbInformation, MB_OK);
  finally
    if Started then
      UpgradeProgressPage.Hide;
  end;
end;

procedure InitializeWizard;
begin
  UpgradeProgressPage := CreateOutputProgressPage(
    'Preparing to Install', 'Setup is preparing to update PHP Windows DevStack.');
  UpgradeCancelButton := TNewButton.Create(WizardForm);
  UpgradeCancelButton.Parent := UpgradeProgressPage.Surface;
  UpgradeCancelButton.Caption := 'Cancel';
  UpgradeCancelButton.Width := 90;
  UpgradeCancelButton.Height := 25;
  UpgradeCancelButton.Left := UpgradeProgressPage.SurfaceWidth - UpgradeCancelButton.Width - 12;
  UpgradeCancelButton.Top := UpgradeProgressPage.SurfaceHeight - UpgradeCancelButton.Height - 12;
  UpgradeCancelButton.OnClick := @CancelUpgradeProgress;
  UpgradeMinimizeButton := TNewButton.Create(WizardForm);
  UpgradeMinimizeButton.Parent := UpgradeProgressPage.Surface;
  UpgradeMinimizeButton.Caption := 'Minimize';
  UpgradeMinimizeButton.Width := 90;
  UpgradeMinimizeButton.Height := 25;
  UpgradeMinimizeButton.Left := UpgradeProgressPage.SurfaceWidth - UpgradeCancelButton.Width - UpgradeMinimizeButton.Width - 24;
  UpgradeMinimizeButton.Top := UpgradeProgressPage.SurfaceHeight - UpgradeMinimizeButton.Height - 12;
  UpgradeMinimizeButton.OnClick := @MinimizeUpgradeProgress;
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
    ForceDirectories(ExpandConstant('{app}\logs'));
    SaveStringToFile(ExpandConstant('{app}\logs\upgrade-report.txt'), UpgradeReport, False);
    RunRuntimeSetup;
    VerifyRuntimeSetup;
  end;
end;
