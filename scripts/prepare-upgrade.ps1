[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ResultPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FileDigest([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)) }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Copy-BackupEntry([System.IO.FileSystemInfo]$Entry, [string]$DestinationRoot) {
    # Copy reparse points as links, never by walking into their targets.  This
    # matters for Composer links and project junctions outside the stack.
    if ($Entry.PSIsContainer) {
        & robocopy.exe $Entry.FullName (Join-Path $DestinationRoot $Entry.Name) /E /COPY:DAT /DCOPY:DAT /SL /SJ /R:1 /W:1 /NDL /NJH /NJS /NP |
            ForEach-Object {
                if ($_ -match '^\s*(?:\d+%)?\s*(?:New File|Newer|Older|Changed)\s+.*?\s{2,}(.+?)\s*$') {
                    Write-Output "DEVSTACK-UPGRADE|Copying: $($matches[1])"
                }
            }
    }
    else {
        & robocopy.exe $Entry.DirectoryName $DestinationRoot $Entry.Name /COPY:DAT /R:1 /W:1 /SL /SJ /NDL /NJH /NJS /NP |
            ForEach-Object {
                if ($_ -match '^\s*(?:\d+%)?\s*(?:New File|Newer|Older|Changed)\s+.*?\s{2,}(.+?)\s*$') {
                    Write-Output "DEVSTACK-UPGRADE|Copying: $($matches[1])"
                }
            }
    }
    # Robocopy uses bit flags: 0 through 7 are successful copy outcomes;
    # 8 and above mean a real error.
    if ($LASTEXITCODE -ge 8) {
        throw "Backup copy failed for $($Entry.Name) (robocopy exit code $LASTEXITCODE)."
    }
}

try {
    $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root)) {
        'Fresh installation.' | Set-Content -LiteralPath $ResultPath
        exit 0
    }
    if (-not (Test-Path -LiteralPath "$root\DevStack.ControlPanel.exe") -or
        -not (Test-Path -LiteralPath "$root\data\mariadb\mysql") -or
        -not (Test-Path -LiteralPath "$root\runtime\manifest\components.json")) {
        throw 'The selected folder exists but is not a complete PHPDevStack installation. Choose another folder; existing files will not be overwritten.'
    }

    # Never terminate a user's processes or copy a live database.
    $prefix = $root + '\'
    $running = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($running.Count -gt 0) {
        throw ('Stop all PHPDevStack services, close its control panel and PHP terminals, then retry. Still running: ' + (($running | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '))
    }
    # Fail before copying/overwriting if credentials belong to another Windows account.
    Add-Type -AssemblyName System.Security
    $secret = [IO.File]::ReadAllBytes("$root\data\secrets\mariadb-root-password.dpapi")
    $plain = [Security.Cryptography.ProtectedData]::Unprotect($secret, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [Array]::Clear($plain, 0, $plain.Length)

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $report = @('Update existing installation.', 'Runtime comparison against this installer''s supported versions:')
    foreach ($item in $manifest.components | Where-Object { $_.enabled }) {
        $componentRoot = if ($item.name -eq 'phpmyadmin') { Join-Path $root $item.targetDirectory } else { Join-Path "$root\runtime" $item.targetDirectory }
        $receiptPath = Join-Path $componentRoot '.devstack-receipt.json'
        if (-not (Test-Path -LiteralPath $receiptPath)) { throw "Missing $($item.name) installation receipt. Update stopped; repair/identify this runtime before replacing it." }
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        foreach ($file in $item.requiredFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $componentRoot $file))) { throw "Incomplete $($item.name) runtime: $file is missing. Update stopped." }
        }
        $installed = [version]$receipt.version
        $supported = [version]$item.version
        if ($item.name -eq 'mariadb' -and $installed -lt $supported -and
            ($installed.Major -ne $supported.Major -or $installed.Minor -ne $supported.Minor)) {
            throw "MariaDB $installed to $supported needs a separate database migration. Automatic cross-series updates are blocked."
        }
        if ($installed -ge $supported) {
            $report += "$($item.displayName): installed $installed; supported $supported. Does not need updating - skipped."
        } else {
            $report += "$($item.displayName): update $installed -> $supported (backup first)."
        }
    }

    # A stopped-installation snapshot permits restoration of matching binaries,
    # templates, DPAPI secrets and database files together. Project trees often
    # contain Composer links or junctions. Keep links as links: their targets are
    # not overwritten by setup and should not be followed into unrelated folders.
    Write-Output 'DEVSTACK-UPGRADE|Preparing a safety backup of your current installation...'
    $all = @(Get-Item -LiteralPath $root) + @(Get-ChildItem -LiteralPath $root -Recurse -Force)
    $links = @($all | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    $files = @($all | Where-Object { -not $_.PSIsContainer -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
    $bytes = [Int64](($files | Measure-Object -Property Length -Sum).Sum)
    $sizeMiB = [Math]::Round($bytes / 1MB, 1)
    Write-Output "DEVSTACK-UPGRADE|Backup plan: $($files.Count) files ($sizeMiB MiB). Starting now..."
    $backup = $root + '-backups\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
    Write-Output 'DEVSTACK-UPGRADE|Creating the backup folder...'
    [IO.Directory]::CreateDirectory($backup) | Out-Null
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach ($sid in @($identity, (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $backup -AclObject $acl
    $entries = @(Get-ChildItem -LiteralPath $root -Force)
    $entryNumber = 0
    foreach ($entry in $entries) {
        $entryNumber++
        Write-Output "DEVSTACK-UPGRADE|Creating backup: $($entry.Name) ($entryNumber of $($entries.Count))"
        Copy-BackupEntry -Entry $entry -DestinationRoot $backup
    }
    # Verify every copied file, including databases, before allowing setup to overwrite.
    $fileNumber = 0
    foreach ($file in $files) {
        $fileNumber++
        if ($fileNumber -eq 1 -or $fileNumber % 100 -eq 0 -or $fileNumber -eq $files.Count) {
            Write-Output "DEVSTACK-UPGRADE|Verifying backup files ($fileNumber of $($files.Count))"
        }
        $relative = $file.FullName.Substring($prefix.Length)
        $copy = Join-Path $backup $relative
        if ((Get-FileDigest $file.FullName) -ne (Get-FileDigest $copy)) { throw "Backup verification failed: $relative" }
    }
    $running = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($running.Count -gt 0) { throw 'A PHPDevStack process started during the backup. Stop it and retry; this backup is not approved for use.' }
    if ($links.Count -gt 0) {
        $linkNames = @($links | ForEach-Object { $_.FullName.Substring($prefix.Length) }) -join ', '
        $report += "Preserved $($links.Count) symbolic link/junction as links: $linkNames"
        $report += 'Their targets were not followed into the backup and are not changed by this installer.'
    }
    $report += "Verified full backup: $backup"
    $report += 'Projects, databases, passwords, ports and custom settings will be preserved.'
    $report | Set-Content -LiteralPath $ResultPath
    $report | Set-Content -LiteralPath (Join-Path $backup 'upgrade-report.txt')
}
catch {
    "Update cannot continue: $($_.Exception.Message)" | Set-Content -LiteralPath $ResultPath
    exit 1
}
