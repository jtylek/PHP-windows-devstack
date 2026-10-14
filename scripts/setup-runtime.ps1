[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallRoot
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

try {
$runtimeRoot = Join-Path $installFullPath 'runtime'
$manifestPath = Join-Path $runtimeRoot 'manifest/components.json'
$installer = Join-Path $PSScriptRoot 'install-runtime.ps1'

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
foreach ($component in @('apache', 'php', 'mariadb')) {
    & $installer -Component $component -ManifestPath $manifestPath -DestinationRoot $runtimeRoot -Force
}
& $installer -Component phpmyadmin -ManifestPath $manifestPath -DestinationRoot $installFullPath -Force

$phpMyAdminRoot = Join-Path $installFullPath 'phpmyadmin'
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

Remove-OptionalRuntimeFiles -Root $installFullPath

'ready' | Set-Content -LiteralPath (Join-Path $installFullPath '.devstack-ready') -Encoding ascii
Write-Host 'DevStack runtime setup completed.'
}
finally {
    Stop-Transcript | Out-Null
}
