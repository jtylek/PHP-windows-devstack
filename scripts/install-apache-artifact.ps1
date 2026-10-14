[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ArchivePath,

    [Parameter(Mandatory)]
    [string]$ChecksumPath,

    [string]$DestinationRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime'),

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$archiveFullPath = [System.IO.Path]::GetFullPath($ArchivePath)
$checksumFullPath = [System.IO.Path]::GetFullPath($ChecksumPath)
if (-not (Test-Path -LiteralPath $archiveFullPath -PathType Leaf)) {
    throw "Apache artifact does not exist: $archiveFullPath"
}
if (-not (Test-Path -LiteralPath $checksumFullPath -PathType Leaf)) {
    throw "Apache checksum file does not exist: $checksumFullPath"
}

$checksumLine = (Get-Content -LiteralPath $checksumFullPath -Raw).Trim()
if ($checksumLine -notmatch '^(?<hash>[a-fA-F0-9]{64})\s+\*?(?<file>[^\r\n]+)$') {
    throw 'The Apache checksum file has an invalid format.'
}

$expectedHash = $Matches.hash.ToLowerInvariant()
$expectedName = $Matches.file.Trim()
if ($expectedName -cne [System.IO.Path]::GetFileName($archiveFullPath)) {
    throw "The checksum is for '$expectedName', not '$([System.IO.Path]::GetFileName($archiveFullPath))'."
}

$actualHash = (Get-FileHash -LiteralPath $archiveFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -cne $expectedHash) {
    throw "Apache artifact SHA-256 verification failed. Expected $expectedHash but received $actualHash."
}

$destinationFullPath = [System.IO.Path]::GetFullPath($DestinationRoot)
$targetFullPath = Join-Path $destinationFullPath 'apache'
if ((Test-Path -LiteralPath $targetFullPath) -and -not $Force) {
    throw "Apache already exists at '$targetFullPath'. Use -Force to replace it safely."
}

if (-not $PSCmdlet.ShouldProcess($targetFullPath, 'Install verified Apache build artifact')) {
    return
}

[System.IO.Directory]::CreateDirectory($destinationFullPath) | Out-Null
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('devstack-apache-install-' + [Guid]::NewGuid().ToString('N'))
$extractPath = Join-Path $temporaryRoot 'extract'
$stagingPath = Join-Path $destinationFullPath ('.staging-apache-' + [Guid]::NewGuid().ToString('N'))
$backupPath = $null
[System.IO.Directory]::CreateDirectory($extractPath) | Out-Null

try {
    Expand-Archive -LiteralPath $archiveFullPath -DestinationPath $extractPath
    foreach ($relativePath in @('bin/httpd.exe', 'bin/libhttpd.dll', 'modules/mod_rewrite.so', 'modules/mod_ssl.so')) {
        if (-not (Test-Path -LiteralPath (Join-Path $extractPath $relativePath) -PathType Leaf)) {
            throw "Apache artifact is missing required file '$relativePath'."
        }
    }

    [System.IO.Directory]::Move($extractPath, $stagingPath)
    if (Test-Path -LiteralPath $targetFullPath) {
        $backupRoot = Join-Path $destinationFullPath '.backup'
        [System.IO.Directory]::CreateDirectory($backupRoot) | Out-Null
        $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
        $backupPath = Join-Path $backupRoot ("apache-$timestamp-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        [System.IO.Directory]::Move($targetFullPath, $backupPath)
    }

    try {
        [System.IO.Directory]::Move($stagingPath, $targetFullPath)
        $stagingPath = $null
    }
    catch {
        if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath) -and -not (Test-Path -LiteralPath $targetFullPath)) {
            [System.IO.Directory]::Move($backupPath, $targetFullPath)
            $backupPath = $null
        }
        throw
    }

    $receipt = [ordered]@{
        schemaVersion = 1
        name = 'apache'
        archive = [System.IO.Path]::GetFileName($archiveFullPath)
        sha256 = $expectedHash
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $targetFullPath '.devstack-receipt.json') -Encoding utf8
    Write-Host "Installed verified Apache runtime to '$targetFullPath'."
}
finally {
    if ($null -ne $stagingPath -and (Test-Path -LiteralPath $stagingPath)) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
