[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallRoot,
    [string]$ProgressPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'DevStack requires 64-bit Windows.'
}

# Windows PowerShell 5.1 can otherwise negotiate an obsolete TLS version on
# older Windows 10 installations.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installFullPath = [System.IO.Path]::GetFullPath($InstallRoot)
$logsDirectory = Join-Path $installFullPath 'logs'
[System.IO.Directory]::CreateDirectory($logsDirectory) | Out-Null
$transcriptPath = Join-Path $logsDirectory 'setup-runtime.log'
Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null

function Write-ProgressState {
    param(
        [Parameter(Mandatory)][int]$Completed,
        [Parameter(Mandatory)][int]$Total,
        [Parameter(Mandatory)][string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($ProgressPath)) {
        return
    }

    $temporaryPath = "$ProgressPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        "$Completed|$Total|$Message" | Set-Content -LiteralPath $temporaryPath -Encoding ascii
        Move-Item -LiteralPath $temporaryPath -Destination $ProgressPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

try {
$pmaStorageConfig = $null

function Read-ProtectedPassword {
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.Security
    $protectedBytes = [System.IO.File]::ReadAllBytes($Path)
    try {
        $passwordBytes = [Security.Cryptography.ProtectedData]::Unprotect($protectedBytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        try { return [Text.Encoding]::UTF8.GetString($passwordBytes) }
        finally { [Array]::Clear($passwordBytes, 0, $passwordBytes.Length) }
    }
    finally { [Array]::Clear($protectedBytes, 0, $protectedBytes.Length) }
}

function New-RandomHexSecret {
    param([int]$ByteCount = 24)
    $bytes = New-Object byte[] $ByteCount
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
        return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $random.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Escape-SqlLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace('\', '\\').Replace("'", "''")
}

function Enable-PhpMyAdminSignon {
    param([Parameter(Mandatory)][string]$InstallRoot, [Parameter(Mandatory)][string]$PhpMyAdminRoot)
    $config = Join-Path $PhpMyAdminRoot 'config.inc.php'
    if (-not (Test-Path -LiteralPath $config)) { throw 'phpMyAdmin configuration is missing.' }
    $contents = Get-Content -LiteralPath $config -Raw
    if ($contents -notmatch 'PHPDevStack local one-time sign-on') {
        Add-Content -LiteralPath $config -Value (@(
            '', '// PHPDevStack local one-time sign-on. Do not change this block manually.',
            "`$cfg['Servers'][`$i]['auth_type'] = 'signon';",
            "`$cfg['Servers'][`$i]['SignonSession'] = 'DevStackPhpMyAdmin';",
            "`$cfg['Servers'][`$i]['SignonURL'] = '/_devstack/phpmyadmin-signon.php';"
        ) -join [Environment]::NewLine) -Encoding utf8
    }
    $template = Join-Path $InstallRoot 'runtime/templates/httpd.conf.template'
    $httpd = Get-Content -LiteralPath $template -Raw
    if ($httpd -notmatch 'PHPDevStack phpMyAdmin local sign-on') {
        Add-Content -LiteralPath $template -Value (@(
            '', '# PHPDevStack phpMyAdmin local sign-on; this endpoint never accepts LAN clients.',
            'Alias /_devstack "{{INTERNAL_ROOT}}"',
            '<Directory "{{INTERNAL_ROOT}}">', '    Options -Indexes', '    AllowOverride None', '    Require local', '</Directory>'
        ) -join [Environment]::NewLine) -Encoding utf8
    }
}

function Initialize-PhpMyAdminStorage {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$PhpMyAdminRoot,
        [Parameter(Mandatory)][string]$RootPassword
    )

    $mariaRoot = Join-Path $RuntimeRoot 'mariadb'
    $serverPath = Join-Path $mariaRoot 'bin/mariadbd.exe'
    $clientPath = Join-Path $mariaRoot 'bin/mariadb.exe'
    $dataDirectory = Join-Path $InstallRoot 'data/mariadb'
    $logsDirectory = Join-Path $InstallRoot 'logs'
    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("devstack-pma-" + [Guid]::NewGuid().ToString('N'))
    $serverConfig = Join-Path $temporaryRoot 'mariadb.ini'
    $clientConfig = Join-Path $temporaryRoot 'client.cnf'
    $server = $null

    [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    try {
        $configLines = @(
            '[mariadbd]',
            ('basedir="{0}"' -f $mariaRoot.Replace('\', '/')),
            ('datadir="{0}"' -f $dataDirectory.Replace('\', '/')),
            'port=3307',
            'bind-address=127.0.0.1',
            'skip-name-resolve',
            ('log-error="{0}/mariadb-error.log"' -f $logsDirectory.Replace('\', '/'))
        )
        [IO.File]::WriteAllLines($serverConfig, $configLines, [Text.Encoding]::ASCII)
        $clientLines = @(
            '[client]'
            "password=$RootPassword"
        )
        [IO.File]::WriteAllLines($clientConfig, $clientLines, [Text.Encoding]::ASCII)

        Write-Host 'Starting MariaDB temporarily for phpMyAdmin configuration storage...'
        $server = Start-Process -FilePath $serverPath -ArgumentList "--defaults-file=$serverConfig", '--console' -WorkingDirectory $mariaRoot -WindowStyle Hidden -PassThru
        $ready = $false
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            Start-Sleep -Seconds 1
            & $clientPath "--defaults-extra-file=$clientConfig" --protocol=tcp --host=127.0.0.1 --port=3307 --user=root --batch --skip-column-names -e 'SELECT 1' *> $null
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        }
        if (-not $ready) { throw 'MariaDB did not become ready for phpMyAdmin configuration storage.' }

        $pmaPassword = New-RandomHexSecret -ByteCount 24
        $escapedPassword = Escape-SqlLiteral $pmaPassword
        $sql = "CREATE DATABASE IF NOT EXISTS ``phpmyadmin`` DEFAULT CHARACTER SET utf8 COLLATE utf8_bin; CREATE USER IF NOT EXISTS 'pma'@'127.0.0.1' IDENTIFIED BY '$escapedPassword'; ALTER USER 'pma'@'127.0.0.1' IDENTIFIED BY '$escapedPassword'; GRANT SELECT, INSERT, UPDATE, DELETE, ALTER, CREATE, INDEX, DROP ON ``phpmyadmin``.* TO 'pma'@'127.0.0.1'; FLUSH PRIVILEGES;"
        $sql | & $clientPath "--defaults-extra-file=$clientConfig" --protocol=tcp --host=127.0.0.1 --port=3307 --user=root --batch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the phpMyAdmin configuration-storage user.' }

        $schemaPath = Join-Path $PhpMyAdminRoot 'sql/create_tables.sql'
        if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "phpMyAdmin configuration-storage schema is missing: $schemaPath" }
        Get-Content -LiteralPath $schemaPath -Raw | & $clientPath "--defaults-extra-file=$clientConfig" --protocol=tcp --host=127.0.0.1 --port=3307 --user=root --batch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not import the phpMyAdmin configuration-storage schema.' }

        return @{ User = 'pma'; Password = $pmaPassword }
    }
    finally {
        if ($server -and -not $server.HasExited) {
            Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
            $server.WaitForExit(5000) | Out-Null
        }
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$runtimeRoot = Join-Path $installFullPath 'runtime'
$manifestPath = Join-Path $runtimeRoot 'manifest/components.json'
$installer = Join-Path $PSScriptRoot 'install-runtime.ps1'
$existingDatabase = Test-Path -LiteralPath (Join-Path $installFullPath 'data/mariadb/mysql') -PathType Container
Write-ProgressState -Completed 0 -Total 7 -Message 'Preparing runtime downloads...'

function Remove-OptionalRuntimeFiles {
    param([Parameter(Mandatory)][string]$Root)

    # The neutral English resources are in the main application directory.
    # Remove the satellite resource directories shipped by self-contained .NET.
    foreach ($culture in @('cs', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pl', 'pt-BR', 'ru', 'tr', 'zh-Hans', 'zh-Hant')) {
        $culturePath = Join-Path $Root $culture
        if (Test-Path -LiteralPath $culturePath -PathType Container) {
            Remove-Item -LiteralPath $culturePath -Recurse -Force
        }
    }

    # Keep runtime binaries and CLI clients, but omit SDK/debug/documentation
    # payloads that are not needed to run the local stack.
    $optionalPaths = @(
        'runtime/apache/manual',
        'runtime/apache/include',
        'runtime/apache/lib',
        'runtime/php/dev',
        'runtime/php/php8embed.lib',
        'runtime/php/php.ini-development',
        'runtime/php/php-cgi.exe',
        'runtime/php/phpdbg.exe',
        'runtime/php/php8phpdbg.dll',
        'runtime/mariadb/include',
        'runtime/mariadb/bin/server.pdb',
        'runtime/mariadb/bin/server.lib',
        'runtime/mariadb/bin/mariadbd.pdb',
        'runtime/mariadb/lib/mariadbclient.lib',
        'runtime/mariadb/lib/libmariadb.pdb'
    )
    foreach ($relativePath in $optionalPaths) {
        $path = Join-Path $Root $relativePath
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

Write-Host 'Downloading and verifying Apache, PHP and MariaDB...'
$components = @('apache', 'php', 'mariadb')
for ($index = 0; $index -lt $components.Count; $index++) {
    $component = $components[$index]
    Write-Host "[$($index + 1)/4] Preparing $component..."
    Write-ProgressState -Completed $index -Total 7 -Message "Downloading and verifying $component..."
    & $installer -Component $component -ManifestPath $manifestPath -DestinationRoot $runtimeRoot -Force
    Write-ProgressState -Completed ($index + 1) -Total 7 -Message "$component is ready."
}
Write-Host '[4/4] Preparing phpMyAdmin...'
Write-ProgressState -Completed 3 -Total 7 -Message 'Downloading and verifying phpMyAdmin...'
& $installer -Component phpmyadmin -ManifestPath $manifestPath -DestinationRoot $installFullPath -Force
Write-ProgressState -Completed 4 -Total 7 -Message 'phpMyAdmin is ready.'

$phpMyAdminRoot = Join-Path $installFullPath 'phpmyadmin'
if ($existingDatabase) {
    if (-not (Test-Path -LiteralPath (Join-Path $phpMyAdminRoot 'config.inc.php'))) {
        throw 'Existing phpMyAdmin configuration is missing. Restore it from the pre-update backup; setup will not reset passwords or database contents.'
    }
    & (Join-Path $PSScriptRoot 'merge-mariadb-template.ps1') -InstallRoot $installFullPath
    Enable-PhpMyAdminSignon -InstallRoot $installFullPath -PhpMyAdminRoot $phpMyAdminRoot
    Write-Host 'Existing databases, passwords, phpMyAdmin configuration and user settings preserved. Database initialization skipped.'
    Write-ProgressState -Completed 7 -Total 7 -Message 'Update complete; existing data preserved.'
    'ready' | Set-Content -LiteralPath (Join-Path $installFullPath '.devstack-ready') -Encoding ascii
    Write-Host 'DevStack runtime setup completed.'
    return
}
$secretBytes = New-Object byte[] 32
$secretRandom = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $secretRandom.GetBytes($secretBytes)
}
finally {
    $secretRandom.Dispose()
}
$phpMyAdminSecret = ([BitConverter]::ToString($secretBytes)).Replace('-', '').ToLowerInvariant()
$phpMyAdminConfig = @'
<?php
$cfg['blowfish_secret'] = sodium_hex2bin('__BLOWFISH_SECRET__');
$i = 1;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = '127.0.0.1';
$cfg['Servers'][$i]['port'] = 3307;
$cfg['Servers'][$i]['connect_type'] = 'tcp';
$cfg['Servers'][$i]['AllowNoPassword'] = false;
'@.Replace('__BLOWFISH_SECRET__', $phpMyAdminSecret)
Set-Content -LiteralPath (Join-Path $phpMyAdminRoot 'config.inc.php') -Value $phpMyAdminConfig -Encoding utf8
[Array]::Clear($secretBytes, 0, $secretBytes.Length)

$dataDirectory = Join-Path $installFullPath 'data/mariadb'
$systemDatabase = Join-Path $dataDirectory 'mysql'
if (-not (Test-Path -LiteralPath $systemDatabase -PathType Container)) {
    Write-ProgressState -Completed 5 -Total 7 -Message 'Initializing MariaDB...'
    [System.IO.Directory]::CreateDirectory($dataDirectory) | Out-Null

    $randomBytes = New-Object byte[] 24
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($randomBytes)
    }
    finally {
        $random.Dispose()
    }
    $rootPassword = ([BitConverter]::ToString($randomBytes)).Replace('-', '').ToLowerInvariant()

    $initializer = Join-Path $runtimeRoot 'mariadb/bin/mariadb-install-db.exe'
    Write-Host 'Initializing the local MariaDB data directory...'
    & $initializer "--datadir=$dataDirectory" '--port=3307' "--password=$rootPassword" '--silent'
    if ($LASTEXITCODE -ne 0) {
        throw "MariaDB initialization failed with exit code $LASTEXITCODE."
    }

    $secretsDirectory = Join-Path $installFullPath 'data/secrets'
    [System.IO.Directory]::CreateDirectory($secretsDirectory) | Out-Null
    Add-Type -AssemblyName System.Security
    $passwordBytes = [Text.Encoding]::UTF8.GetBytes($rootPassword)
    $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
        $passwordBytes,
        $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [System.IO.File]::WriteAllBytes(
        (Join-Path $secretsDirectory 'mariadb-root-password.dpapi'),
        $protectedBytes)
    [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
    $rootPassword = $null
}

$rootPasswordPath = Join-Path $installFullPath 'data/secrets/mariadb-root-password.dpapi'
$rootPassword = Read-ProtectedPassword -Path $rootPasswordPath
$pmaStorageConfig = Initialize-PhpMyAdminStorage -InstallRoot $installFullPath -RuntimeRoot $runtimeRoot -PhpMyAdminRoot $phpMyAdminRoot -RootPassword $rootPassword
$storageLines = @(
    "`$cfg['Servers'][`$i]['controluser'] = '$($pmaStorageConfig.User)';",
    "`$cfg['Servers'][`$i]['controlpass'] = '$($pmaStorageConfig.Password)';",
    "`$cfg['Servers'][`$i]['pmadb'] = 'phpmyadmin';",
    "`$cfg['Servers'][`$i]['bookmarktable'] = 'pma__bookmark';",
    "`$cfg['Servers'][`$i]['relation'] = 'pma__relation';",
    "`$cfg['Servers'][`$i]['table_info'] = 'pma__table_info';",
    "`$cfg['Servers'][`$i]['table_coords'] = 'pma__table_coords';",
    "`$cfg['Servers'][`$i]['pdf_pages'] = 'pma__pdf_pages';",
    "`$cfg['Servers'][`$i]['column_info'] = 'pma__column_info';",
    "`$cfg['Servers'][`$i]['history'] = 'pma__history';",
    "`$cfg['Servers'][`$i]['table_uiprefs'] = 'pma__table_uiprefs';",
    "`$cfg['Servers'][`$i]['tracking'] = 'pma__tracking';",
    "`$cfg['Servers'][`$i]['userconfig'] = 'pma__userconfig';",
    "`$cfg['Servers'][`$i]['recent'] = 'pma__recent';",
    "`$cfg['Servers'][`$i]['favorite'] = 'pma__favorite';",
    "`$cfg['Servers'][`$i]['users'] = 'pma__users';",
    "`$cfg['Servers'][`$i]['usergroups'] = 'pma__usergroups';",
    "`$cfg['Servers'][`$i]['navigationhiding'] = 'pma__navigationhiding';",
    "`$cfg['Servers'][`$i]['savedsearches'] = 'pma__savedsearches';",
    "`$cfg['Servers'][`$i]['central_columns'] = 'pma__central_columns';",
    "`$cfg['Servers'][`$i]['designer_settings'] = 'pma__designer_settings';",
    "`$cfg['Servers'][`$i]['export_templates'] = 'pma__export_templates';"
)
Add-Content -LiteralPath (Join-Path $phpMyAdminRoot 'config.inc.php') -Value ($storageLines -join [Environment]::NewLine) -Encoding utf8
Enable-PhpMyAdminSignon -InstallRoot $installFullPath -PhpMyAdminRoot $phpMyAdminRoot
[Array]::Clear([Text.Encoding]::UTF8.GetBytes($rootPassword), 0, [Text.Encoding]::UTF8.GetByteCount($rootPassword))
$rootPassword = $null

Remove-OptionalRuntimeFiles -Root $installFullPath
Write-Host 'Finalizing runtime setup...'
Write-ProgressState -Completed 6 -Total 7 -Message 'Finalizing DevStack...'

'ready' | Set-Content -LiteralPath (Join-Path $installFullPath '.devstack-ready') -Encoding ascii
Write-ProgressState -Completed 7 -Total 7 -Message 'DevStack is ready.'
Write-Host 'DevStack runtime setup completed.'
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host 'Runtime setup failed. Review setup-runtime.log for the complete error.'
    Write-ProgressState -Completed 0 -Total 7 -Message "Setup failed: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript | Out-Null
}
