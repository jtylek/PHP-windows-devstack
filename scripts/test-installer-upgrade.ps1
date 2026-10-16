[CmdletBinding()]
param([Parameter(Mandatory)][string]$SetupPath, [string]$InstallRoot = 'C:\ds-test')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security
$root = [IO.Path]::GetFullPath($InstallRoot)
$scratch = Join-Path $env:TEMP ('devstack-upgrade-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$server = $null
try {
    $passwordBytes = [Security.Cryptography.ProtectedData]::Unprotect(
        [IO.File]::ReadAllBytes("$root\data\secrets\mariadb-root-password.dpapi"), $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $password = [Text.Encoding]::UTF8.GetString($passwordBytes)
    $clientIni = Join-Path $scratch 'client.ini'
    [IO.File]::WriteAllLines($clientIni, @('[client]', "password=$password"))
    [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
    $password = $null
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $serverIni = Join-Path $scratch 'server.ini'
    $normalized = $root.Replace('\','/')
    [IO.File]::WriteAllLines($serverIni, @('[mariadbd]', "basedir=$normalized/runtime/mariadb",
        "datadir=$normalized/data/mariadb", "port=$port", 'bind-address=127.0.0.1', "log-error=$normalized/logs/test-db.log"))
    $client = "$root\runtime\mariadb\bin\mariadb.exe"
    $admin = "$root\runtime\mariadb\bin\mariadb-admin.exe"
    function Start-TestDatabase {
        $script:server = Start-Process "$root\runtime\mariadb\bin\mariadbd.exe" -ArgumentList "--defaults-file=$serverIni", '--console' -PassThru -WindowStyle Hidden
        for ($i = 0; $i -lt 30; $i++) {
            & $client "--defaults-extra-file=$clientIni" --protocol=tcp --host=127.0.0.1 "--port=$port" --user=root --batch -e 'SELECT 1' *> $null
            if ($LASTEXITCODE -eq 0) { return }
            Start-Sleep -Seconds 1
        }
        throw 'Test database did not start.'
    }
    function Stop-TestDatabase {
        & $admin "--defaults-extra-file=$clientIni" --protocol=tcp --host=127.0.0.1 "--port=$port" --user=root shutdown
        if ($LASTEXITCODE -ne 0 -or -not $script:server.WaitForExit(30000)) { throw 'Test database did not stop cleanly.' }
        $script:server = $null
    }
    Start-TestDatabase
    & $client "--defaults-extra-file=$clientIni" --protocol=tcp --host=127.0.0.1 "--port=$port" --user=root -e "CREATE DATABASE upgrade_sentinel; CREATE TABLE upgrade_sentinel.keep_me (value VARCHAR(80)); INSERT INTO upgrade_sentinel.keep_me VALUES ('database survived upgrade');"
    if ($LASTEXITCODE -ne 0) { throw 'Could not create upgrade sentinel.' }
    Stop-TestDatabase

    # Simulate a user's old template and hand-added HTTPS configuration.
    [IO.File]::WriteAllText("$root\runtime\templates\mariadb.ini.template", "[mariadbd]`r`nbasedir=`"{{MARIADB_ROOT}}`"`r`ndatadir=`"{{MARIADB_DATA_ROOT}}`"`r`nport={{MARIADB_PORT}}`r`nbind-address=127.0.0.1`r`n[client]`r`nport={{MARIADB_PORT}}`r`n")
    Add-Content "$root\runtime\templates\httpd.conf.template" '# custom HTTPS include preserved'
    [IO.Directory]::CreateDirectory("$root\data\config") | Out-Null
    [IO.File]::WriteAllText("$root\data\config\ports.json", '{"HttpPort":8088,"MariaDbPort":3311}')
    [IO.File]::WriteAllText("$root\data\config\mariadb-settings.json", '{"BufferPoolSizeMb":512}')
    [IO.File]::WriteAllText("$root\www\index.php", '<?php echo "user project preserved";')
    [IO.File]::WriteAllText("$root\www\upgrade-project.txt", 'project sentinel')
    $junctionTarget = Join-Path $scratch 'linked-project'
    [IO.Directory]::CreateDirectory($junctionTarget) | Out-Null
    [IO.File]::WriteAllText((Join-Path $junctionTarget 'external-project.txt'), 'external project sentinel')
    cmd /c "mklink /J `"$root\www\linked-project`" `"$junctionTarget`"" *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create test project junction.' }
    Add-Content "$root\phpmyadmin\config.inc.php" '// user phpMyAdmin configuration sentinel'
    $protectedPaths = @('www/index.php', 'www/upgrade-project.txt', 'data/config/ports.json',
        'data/config/mariadb-settings.json', 'data/secrets/mariadb-root-password.dpapi',
        'phpmyadmin/config.inc.php', 'runtime/templates/httpd.conf.template', 'runtime/templates/php.ini.template',
        'runtime/apache/.devstack-receipt.json','runtime/php/.devstack-receipt.json',
        'runtime/mariadb/.devstack-receipt.json','phpmyadmin/.devstack-receipt.json')
    $hashes = @{}
    foreach ($path in $protectedPaths) { $hashes[$path] = (Get-FileHash -LiteralPath (Join-Path $root $path)).Hash }
    $setup = Start-Process $SetupPath -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=$root", "/LOG=$scratch\installer.log" -Wait -PassThru
    if ($setup.ExitCode -ne 0) {
        Get-Content "$scratch\installer.log"
        Get-Content "$root\logs\setup-runtime.log" -ErrorAction SilentlyContinue
        throw "In-place installer failed: $($setup.ExitCode)"
    }
    foreach ($path in $protectedPaths) {
        if ($hashes[$path] -ne (Get-FileHash -LiteralPath (Join-Path $root $path)).Hash) { throw "Upgrade modified preserved file: $path" }
    }
    $report = Get-Content "$root\logs\upgrade-report.txt" -Raw
    if ($report -notmatch 'Verified full backup:' -or ([regex]::Matches($report, 'Does not need updating - skipped')).Count -ne 4) { throw 'Missing backup/skip report.' }
    if ($report -notmatch 'Preserved 1 symbolic link/junction as links') { throw 'Project junction was not reported.' }
    $backupPath = ([regex]::Match($report, '(?m)^Verified full backup:\s*(.+)$')).Groups[1].Value.Trim()
    if (-not $backupPath) { throw 'Could not determine the backup path.' }
    $backupJunction = Get-Item -LiteralPath (Join-Path $backupPath 'www\linked-project') -Force
    if (-not ($backupJunction.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Backup dereferenced the project junction instead of preserving it as a link.' }
    if ((Get-Content (Join-Path $junctionTarget 'external-project.txt') -Raw) -ne 'external project sentinel') { throw 'Project junction target was changed.' }
    $template = Get-Content "$root\runtime\templates\mariadb.ini.template" -Raw
    if ($template -notmatch 'innodb_buffer_pool_size=\{\{INNODB_BUFFER_POOL_SIZE\}\}') { throw 'New MariaDB defaults were not merged.' }
    if (-not (Test-Path "$root\runtime\internal\phpmyadmin-signon.php")) { throw 'Local phpMyAdmin sign-on endpoint is missing.' }
    if ((Get-Content "$root\phpmyadmin\config.inc.php" -Raw) -notmatch 'PHPDevStack local one-time sign-on') { throw 'phpMyAdmin sign-on configuration was not installed.' }
    if ((Get-Content "$root\runtime\templates\httpd.conf.template" -Raw) -notmatch 'PHPDevStack phpMyAdmin local sign-on') { throw 'Apache local sign-on rule was not installed.' }
    Start-TestDatabase
    $value = & $client "--defaults-extra-file=$clientIni" --protocol=tcp --host=127.0.0.1 "--port=$port" --user=root --batch --skip-column-names -e 'SELECT value FROM upgrade_sentinel.keep_me'
    if ($LASTEXITCODE -ne 0 -or $value -ne 'database survived upgrade') { throw 'Database contents did not survive upgrade.' }
    Stop-TestDatabase

    # Exercise the actual generated configuration and slow log, not just template text.
    dotnet run --project (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests/DevStack.TerminalChecks/DevStack.TerminalChecks.csproj') -- --render $root
    if ($LASTEXITCODE -ne 0) { throw 'Could not render installed configuration.' }
    $serverIni = "$root\runtime\config\generated\mariadb.ini"
    & "$root\runtime\mariadb\bin\mariadbd.exe" "--defaults-file=$serverIni" --verbose --help *> (Join-Path $scratch 'mariadb-options.txt')
    if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $scratch 'mariadb-options.txt'); throw 'MariaDB rejected generated options.' }
    $port = 3311
    Start-TestDatabase
    $settings = & $client "--defaults-extra-file=$clientIni" --protocol=tcp --host=127.0.0.1 "--port=$port" --user=root --batch --skip-column-names -e 'SELECT @@innodb_buffer_pool_size, @@innodb_log_file_size, @@innodb_flush_log_at_trx_commit, @@innodb_io_capacity, @@innodb_io_capacity_max, @@table_definition_cache, @@tmp_table_size, @@max_heap_table_size, @@key_buffer_size, @@slow_query_log, @@long_query_time; SELECT SLEEP(1.2);'
    if ($LASTEXITCODE -ne 0 -or $settings[0] -notmatch '^536870912\s+268435456\s+2\s+1000\s+4000\s+1000\s+67108864\s+67108864\s+16777216\s+1\s+1') { throw 'Live database tuning values differ from the requested profile/override.' }
    Stop-TestDatabase
    if ((Get-Content "$root\logs\mariadb-slow.log" -Raw) -notmatch 'SLEEP\(1.2\)') { throw 'Slow query log did not record the test query.' }

    # A second update must build a complete snapshot while reusing unchanged
    # files from the first verified snapshot. Changed files are physically copied.
    [IO.File]::WriteAllText("$root\www\upgrade-project.txt", 'changed project sentinel')
    $secondSetup = Start-Process $SetupPath -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=$root", "/LOG=$scratch\installer-second.log" -Wait -PassThru
    if ($secondSetup.ExitCode -ne 0) {
        Get-Content "$scratch\installer-second.log"
        Get-Content "$root\logs\setup-runtime.log" -ErrorAction SilentlyContinue
        throw "Second in-place update failed: $($secondSetup.ExitCode)"
    }
    $secondReport = Get-Content "$root\logs\upgrade-report.txt" -Raw
    if ($secondReport -notmatch 'Incremental backup sync: kept \d+ unchanged files') { throw 'Second update did not report an incremental backup sync.' }
    $secondBackup = ([regex]::Match($secondReport, '(?m)^Verified full backup:\s*(.+)$')).Groups[1].Value.Trim()
    if (-not $secondBackup) { throw 'Could not determine the second backup path.' }
    if ($secondBackup -ne (Join-Path "$root-backups" 'current')) { throw 'Updates must maintain one stable backup folder.' }
    $backupFolders = @(Get-ChildItem "$root-backups" -Directory -Force)
    if ($backupFolders.Count -ne 1 -or $backupFolders[0].Name -ne 'current') { throw 'Older timestamped backup folders were not cleaned up after the current backup was verified.' }
    if ((Get-Content "$secondBackup\www\upgrade-project.txt" -Raw) -ne 'changed project sentinel') { throw 'Second backup does not contain the updated project file.' }
    if ((Get-Content "$secondBackup\www\index.php" -Raw) -ne '<?php echo "user project preserved";') { throw 'Incremental sync did not retain an unchanged project file.' }
    $snapshotIndexHash = (Get-FileHash "$secondBackup\www\index.php").Hash
    [IO.File]::WriteAllText("$root\www\index.php", '<?php echo "live file changed after backup";')
    if ((Get-FileHash "$secondBackup\www\index.php").Hash -ne $snapshotIndexHash) { throw 'Changing a live file modified the completed backup snapshot.' }

    # Skipping backup must bypass the inventory/copy/verification work entirely.
    $backupReportHash = (Get-FileHash "$secondBackup\upgrade-report.txt").Hash
    $skipSetup = Start-Process $SetupPath -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=$root",'/TASKS=!backup',"/LOG=$scratch\installer-skip-backup.log" -Wait -PassThru
    if ($skipSetup.ExitCode -ne 0) { Get-Content "$scratch\installer-skip-backup.log"; throw "Update with backup skipped failed: $($skipSetup.ExitCode)" }
    $skipReport = Get-Content "$root\logs\upgrade-report.txt" -Raw
    if ($skipReport -notmatch 'Backup skipped by user' -or $skipReport -notmatch 'WARNING: The user chose to skip') { throw 'Skipped-backup warning is missing.' }
    if ((Get-FileHash "$secondBackup\upgrade-report.txt").Hash -ne $backupReportHash) { throw 'Skipping backup modified the existing recovery backup.' }
    Write-Host 'In-place updates passed: incremental single-folder backup and backup-skip behavior verified.'
}
finally {
    if ($null -ne $server -and -not $server.HasExited) {
        & $admin "--defaults-extra-file=$clientIni" --protocol=tcp --host=127.0.0.1 "--port=$port" --user=root shutdown *> $null
        $server.WaitForExit(30000) | Out-Null
    }
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
