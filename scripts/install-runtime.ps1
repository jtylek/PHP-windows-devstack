[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('all', 'apache', 'php', 'mariadb')]
    [string]$Component = 'all',

    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime/manifest/components.json'),

    [string]$DestinationRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime'),

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-Sha256Hex([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

& (Join-Path $PSScriptRoot 'verify-runtime-manifest.ps1') -ManifestPath $ManifestPath

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'DevStack runtime installation requires 64-bit Windows.'
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$selected = @($manifest.components | Where-Object {
    $_.enabled -and ($Component -eq 'all' -or $_.name -eq $Component)
})

if ($selected.Count -eq 0) {
    throw "No enabled runtime component matched '$Component'."
}

$destinationFullPath = [System.IO.Path]::GetFullPath($DestinationRoot)
[System.IO.Directory]::CreateDirectory($destinationFullPath) | Out-Null

foreach ($item in $selected) {
    $targetPath = Join-Path $destinationFullPath $item.targetDirectory
    $targetFullPath = [System.IO.Path]::GetFullPath($targetPath)
    if (-not $targetFullPath.StartsWith($destinationFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe target path for '$($item.name)'."
    }

    if ((Test-Path -LiteralPath $targetFullPath) -and -not $Force) {
        throw "Runtime '$($item.name)' already exists at '$targetFullPath'. Use -Force to replace it safely."
    }

    if (-not $PSCmdlet.ShouldProcess("$($item.displayName) $($item.version)", "Download, verify and install")) {
        continue
    }

    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("devstack-" + [Guid]::NewGuid().ToString('N'))
    $archivePath = Join-Path $temporaryRoot "$($item.name).zip"
    $extractPath = Join-Path $temporaryRoot 'extract'
    $stagingPath = $null
    $backupPath = $null
    [System.IO.Directory]::CreateDirectory($extractPath) | Out-Null

    try {
        Write-Host "Downloading $($item.displayName) $($item.version)..."
        $webClient = [Net.WebClient]::new()
        $progressHandler = [System.Net.DownloadProgressChangedEventHandler]{
            param($sender, $event)
            $percent = $event.ProgressPercentage
            $received = [math]::Round($event.BytesReceived / 1MB, 1)
            $total = if ($event.TotalBytesToReceive -gt 0) {
                " / $([math]::Round($event.TotalBytesToReceive / 1MB, 1)) MB"
            }
            else {
                ''
            }
            Write-Progress -Id 1 -Activity "Downloading DevStack components" `
                -Status "$($item.displayName): $percent% ($received MB$total)" `
                -PercentComplete $percent
        }
        $webClient.add_DownloadProgressChanged($progressHandler)
        try {
            $webClient.DownloadFile($item.archiveUrl, $archivePath)
        }
        finally {
            $webClient.remove_DownloadProgressChanged($progressHandler)
            $webClient.Dispose()
            Write-Progress -Id 1 -Activity "Downloading DevStack components" -Completed
        }
        Write-Host "Downloaded $($item.displayName). Verifying SHA-256..."

        $actualHash = Get-Sha256Hex $archivePath
        $expectedHash = $item.sha256.ToLowerInvariant()
        if ($actualHash -cne $expectedHash) {
            throw "SHA-256 verification failed for '$($item.name)'. Expected $expectedHash but received $actualHash."
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $extractPath)

        $payloadRoot = $extractPath
        if ($item.stripTopDirectory) {
            $topDirectories = @(Get-ChildItem -LiteralPath $extractPath -Directory)
            $topFiles = @(Get-ChildItem -LiteralPath $extractPath -File)
            if ($topDirectories.Count -ne 1 -or $topFiles.Count -ne 0) {
                throw "Archive '$($item.name)' does not contain exactly one top-level directory."
            }
            $payloadRoot = $topDirectories[0].FullName
        }

        foreach ($relativePath in $item.requiredFiles) {
            $candidate = Join-Path $payloadRoot $relativePath
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                throw "Archive '$($item.name)' is missing required file '$relativePath'."
            }
        }

        $stagingPath = Join-Path $destinationFullPath (".staging-$($item.name)-" + [Guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::Move($payloadRoot, $stagingPath)

        if (Test-Path -LiteralPath $targetFullPath) {
            $backupRoot = Join-Path $destinationFullPath '.backup'
            [System.IO.Directory]::CreateDirectory($backupRoot) | Out-Null
            $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
            $backupPath = Join-Path $backupRoot ("$($item.name)-$timestamp-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
            [System.IO.Directory]::Move($targetFullPath, $backupPath)
            Write-Host "Previous runtime moved to '$backupPath'."
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
            name = $item.name
            version = $item.version
            archiveUrl = $item.archiveUrl
            sha256 = $expectedHash
            installedAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $targetFullPath '.devstack-receipt.json') -Encoding utf8
        Write-Host "Installed $($item.displayName) $($item.version) to '$targetFullPath'."
    }
    finally {
        if ($null -ne $stagingPath -and (Test-Path -LiteralPath $stagingPath)) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}
