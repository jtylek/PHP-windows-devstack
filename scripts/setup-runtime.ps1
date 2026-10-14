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
$runtimeRoot = Join-Path $installFullPath 'runtime'
$manifestPath = Join-Path $runtimeRoot 'manifest/components.json'
$installer = Join-Path $PSScriptRoot 'install-runtime.ps1'

Write-Host 'Downloading and verifying Apache, PHP and MariaDB...'
& $installer -Component all -ManifestPath $manifestPath -DestinationRoot $runtimeRoot -Force

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
    $securePassword = ConvertTo-SecureString $rootPassword -AsPlainText -Force
    $securePassword | ConvertFrom-SecureString |
        Set-Content -LiteralPath (Join-Path $secretsDirectory 'mariadb-root-password.dpapi') -Encoding ascii
    $rootPassword = $null
}

'ready' | Set-Content -LiteralPath (Join-Path $installFullPath '.devstack-ready') -Encoding ascii
Write-Host 'DevStack runtime setup completed.'
