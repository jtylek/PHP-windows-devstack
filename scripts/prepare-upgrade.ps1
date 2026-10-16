[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ResultPath,
    [switch]$SkipBackup,
    [string]$CancelFile,
    [string]$DecisionFile
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FileDigest([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)) }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Copy-BackupLink([System.IO.FileSystemInfo]$Entry, [string]$DestinationPath) {
    # Preserve the link itself. /SJ prevents traversing junction targets.
    $destinationDirectory = Split-Path -Parent $DestinationPath
    [IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
    $sourceDirectory = Split-Path -Parent $Entry.FullName
    & robocopy.exe $sourceDirectory $destinationDirectory $Entry.Name /E /COPY:DAT /R:1 /W:1 /SL /SJ /NFL /NDL /NJH /NJS /NP *> $null
    if ($LASTEXITCODE -ge 8) {
        throw "Could not preserve link $($Entry.FullName) (robocopy exit code $LASTEXITCODE)."
    }
}

function Get-RelativePath([System.IO.FileSystemInfo]$Item, [string]$Prefix) {
    return $Item.FullName.Substring($Prefix.Length)
}

function Assert-NotCancelled {
    if ($CancelFile -and (Test-Path -LiteralPath $CancelFile)) {
        throw 'Backup cancelled by the user. The installation files have not been replaced; the partial backup can be deleted after setup closes.'
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

    if ($SkipBackup) {
        $report += 'WARNING: The user chose to skip the safety backup. If this update fails, the previous installation cannot be restored from a setup-created backup.'
        $report += 'Backup skipped by user.'
        $report | Set-Content -LiteralPath $ResultPath
        exit 0
    }

    # Maintain one backup directory. Like a local Robocopy mirror, unchanged
    # files remain in place, changed files are replaced, and stale entries are
    # removed only after changed files have copied and verified.
    Write-Output 'DEVSTACK-UPGRADE|Scanning the installation and previous backups...'
    $backupParent = $root + '-backups'
    $backup = Join-Path $backupParent 'current'
    $previousBackup = $null
    if (Test-Path -LiteralPath $backupParent) {
        $currentReport = Join-Path $backup 'upgrade-report.txt'
        if ((Test-Path -LiteralPath $currentReport) -and ((Get-Content -LiteralPath $currentReport -Raw -ErrorAction SilentlyContinue) -match 'Verified full backup:')) {
            $previousBackup = Get-Item -LiteralPath $backup
        }
        $candidates = @(Get-ChildItem -LiteralPath $backupParent -Directory -Force | Sort-Object Name -Descending)
        foreach ($candidate in $candidates | Where-Object { $_.FullName -ne $backup }) {
            $candidateReport = Join-Path $candidate.FullName 'upgrade-report.txt'
            if (Test-Path -LiteralPath $candidateReport) {
                $candidateText = Get-Content -LiteralPath $candidateReport -Raw -ErrorAction SilentlyContinue
                if ($null -eq $previousBackup -and $candidateText -match 'Verified full backup:') {
                    $previousBackup = $candidate
                    break
                }
            }
        }
    }
    if ($null -ne $previousBackup) {
        Write-Output "DEVSTACK-UPGRADE|Comparing files with the last completed backup $($previousBackup.Name)..."
    }
    else {
        Write-Output 'DEVSTACK-UPGRADE|No completed backup was found; this update will make a full backup.'
    }

    $items = New-Object 'System.Collections.Generic.List[System.IO.FileSystemInfo]'
    $scanCount = 0
    Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object {
        Assert-NotCancelled
        $items.Add($_)
        $scanCount++
        if ($scanCount -eq 1 -or $scanCount % 2000 -eq 0) {
            Write-Output "DEVSTACK-UPGRADE|Scanning installation items ($scanCount): $($_.FullName)"
        }
    }
    $links = @($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    $files = @($items | Where-Object { -not $_.PSIsContainer -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
    $bytes = [Int64](($files | Measure-Object -Property Length -Sum).Sum)
    $previousMap = @{}
    if ($null -ne $previousBackup) {
        $previousPrefix = $previousBackup.FullName.TrimEnd('\') + '\'
        $previousCount = 0
        Get-ChildItem -LiteralPath $previousBackup.FullName -Recurse -Force | ForEach-Object {
            Assert-NotCancelled
            if ($_.FullName -ne (Join-Path $previousBackup.FullName 'upgrade-report.txt')) {
                $previousMap[(Get-RelativePath $_ $previousPrefix)] = $_
            }
            $previousCount++
            if ($previousCount -eq 1 -or $previousCount % 2000 -eq 0) {
                Write-Output "DEVSTACK-UPGRADE|Scanning previous backup ($previousCount items): $($_.FullName)"
            }
        }
    }

    $rootPrefix = $root + '\'
    $copyPlan = New-Object 'System.Collections.Generic.List[object]'
    $reuseCount = 0
    $planNumber = 0
    foreach ($file in $files) {
        Assert-NotCancelled
        $planNumber++
        $relative = Get-RelativePath $file $rootPrefix
        $oldFile = $null
        $same = $false
        if ($null -ne $previousBackup -and $previousMap.ContainsKey($relative)) {
            $oldFile = $previousMap[$relative]
            $same = (-not $oldFile.PSIsContainer) -and
                (-not ($oldFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) -and
                ($oldFile.Length -eq $file.Length) -and
                ($oldFile.LastWriteTimeUtc.Ticks -eq $file.LastWriteTimeUtc.Ticks)
        }
        if ($same) { $reuseCount++ }
        $copyPlan.Add([pscustomobject]@{ Item = $file; Relative = $relative; Reuse = $same; OldFile = $oldFile })
        if ($planNumber -eq 1 -or $planNumber % 2000 -eq 0 -or $planNumber -eq $files.Count) {
            Write-Output "DEVSTACK-UPGRADE|Preparing backup plan ($planNumber of $($files.Count)): $($file.FullName)"
        }
    }
    foreach ($link in $links) {
        $copyPlan.Add([pscustomobject]@{ Item = $link; Relative = (Get-RelativePath $link $rootPrefix); Reuse = $false; OldFile = $null })
    }
    $copyCount = $copyPlan.Count - $reuseCount
    $sizeMiB = [Math]::Round($bytes / 1MB, 1)
    $copyBytes = [Int64](($copyPlan | Where-Object { -not $_.Reuse -and -not ($_.Item.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object { $_.Item.Length } | Measure-Object -Sum).Sum)
    $estimateMiB = [Math]::Round($copyBytes / 1MB, 1)
    if ($DecisionFile) {
        $estimateMessage = "Backup estimate: data to copy this run $estimateMiB MiB; complete backup size about $sizeMiB MiB; $reuseCount unchanged files will be kept."
        Write-Output "DEVSTACK-UPGRADE|BACKUP_CONFIRM|$estimateMessage"
        while (-not (Test-Path -LiteralPath $DecisionFile)) {
            Assert-NotCancelled
            Start-Sleep -Milliseconds 150
        }
        $decision = (Get-Content -LiteralPath $DecisionFile -Raw).Trim()
        Remove-Item -LiteralPath $DecisionFile -Force -ErrorAction SilentlyContinue
        if ($decision -ne 'continue') {
            throw 'Backup cancelled before copying. No application files have been replaced.'
        }
    }
    else { Write-Output "DEVSTACK-UPGRADE|$($files.Count) files ($sizeMiB MiB total); copying $estimateMiB MiB and keeping $reuseCount unchanged files." }
    Write-Output "DEVSTACK-UPGRADE|Preparing the single backup folder: $backup"
    [IO.Directory]::CreateDirectory($backupParent) | Out-Null
    if ($null -ne $previousBackup -and $previousBackup.FullName -ne $backup) {
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        Move-Item -LiteralPath $previousBackup.FullName -Destination $backup
        $previousBackup = Get-Item -LiteralPath $backup
    }
    elseif ($null -eq $previousBackup -and (Test-Path -LiteralPath $backup)) {
        Write-Output 'DEVSTACK-UPGRADE|Removing an incomplete backup folder before the full copy...'
        Remove-Item -LiteralPath $backup -Recurse -Force
    }
    [IO.Directory]::CreateDirectory($backup) | Out-Null
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach ($sid in @($identity, (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $backup -AclObject $acl
    # A missing completion report means an interrupted prior sync; never use it
    # as a verified recovery point, and write a new marker only at the end.
    Remove-Item -LiteralPath (Join-Path $backup 'upgrade-report.txt') -Force -ErrorAction SilentlyContinue

    Write-Output 'DEVSTACK-UPGRADE|Building the backup folder structure...'
    $directoryNumber = 0
    foreach ($directory in $items) {
        if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $directoryNumber++
        $relative = Get-RelativePath $directory $rootPrefix
        [IO.Directory]::CreateDirectory((Join-Path $backup $relative)) | Out-Null
        if ($directoryNumber -eq 1 -or $directoryNumber % 250 -eq 0) {
            Write-Output "DEVSTACK-UPGRADE|Creating backup directories ($directoryNumber): $($directory.FullName)"
        }
    }
    Write-Output "DEVSTACK-UPGRADE|Backup folder structure ready ($directoryNumber directories)."
    $copyNumber = 0
    $planNumber = 0
    $verifiedCopyPlan = New-Object 'System.Collections.Generic.List[object]'
    foreach ($record in $copyPlan) {
        Assert-NotCancelled
        $planNumber++
        $item = $record.Item
        $destination = Join-Path $backup $record.Relative
        if ($record.Reuse) {
            if ($planNumber -eq 1 -or $planNumber % 500 -eq 0 -or $planNumber -eq $copyPlan.Count) {
                Write-Output "DEVSTACK-UPGRADE|Keeping unchanged backup file ($planNumber of $($copyPlan.Count)): $($item.FullName)"
            }
        }
        elseif ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $copyNumber++
            Write-Output "DEVSTACK-UPGRADE|Preserving link ($copyNumber of $copyCount): $($item.FullName)"
            if (Test-Path -LiteralPath $destination) {
                if ($item.PSIsContainer) { [IO.Directory]::Delete($destination, $false) } else { [IO.File]::Delete($destination) }
            }
            Copy-BackupLink -Entry $item -DestinationPath $destination
        }
        else { $verifiedCopyPlan.Add($record) }
        if (-not $record.Reuse -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            ($planNumber -eq 1 -or $planNumber % 2000 -eq 0 -or $planNumber -eq $copyPlan.Count)) {
            Write-Output "DEVSTACK-UPGRADE|Preparing copy list ($planNumber of $($copyPlan.Count)): $($item.FullName)"
        }
    }
    # Launch Robocopy once per source directory (in batches), instead of once
    # per file. Process startup dominates when an installation has thousands
    # of small files. Explicit file lists keep unchanged files out of the copy.
    Write-Output "DEVSTACK-UPGRADE|Grouping $($verifiedCopyPlan.Count) changed files by folder..."
    $copyGroups = @($verifiedCopyPlan | Group-Object { $_.Item.DirectoryName })
    $groupNumber = 0
    foreach ($group in $copyGroups) {
        Assert-NotCancelled
        $groupNumber++
        $sourceDirectory = $group.Name
        $directoryRelative = if ($sourceDirectory.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
            ''
        } else {
            $sourceDirectory.Substring($rootPrefix.Length)
        }
        $destinationDirectory = if ($directoryRelative) { Join-Path $backup $directoryRelative } else { $backup }
        [IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
        $records = @($group.Group)
        for ($offset = 0; $offset -lt $records.Count; $offset += 50) {
            Assert-NotCancelled
            $end = [Math]::Min($offset + 49, $records.Count - 1)
            $batch = @($records[$offset..$end])
            $names = @($batch | ForEach-Object { $_.Item.Name })
            $copyNumber += $batch.Count
            Write-Output "DEVSTACK-UPGRADE|Copying changed files ($copyNumber of $copyCount) from $sourceDirectory (directory $groupNumber of $($copyGroups.Count))..."
            & robocopy.exe $sourceDirectory $destinationDirectory @names /COPY:DAT /IS /IT /R:1 /W:1 /SL /SJ /NDL /NJH /NJS /BYTES 2>&1 | ForEach-Object {
                $robocopyLine = $_.ToString().Trim()
                if ($robocopyLine -match '^(?:New File|Newer|Older|Changed|Tweaked)\s+' -or $robocopyLine -match '^\d+(?:\.\d+)?%\s+') {
                    Write-Output "DEVSTACK-UPGRADE|Robocopy: $robocopyLine"
                }
            }
            $robocopyExitCode = $LASTEXITCODE
            # Robocopy uses bit flags: 0 through 7 are successful outcomes;
            # 8 and above mean a real error.
            if ($robocopyExitCode -ge 8) {
                throw "Backup copy failed in $sourceDirectory (robocopy exit code $robocopyExitCode)."
            }
            foreach ($record in $batch) { $verifiedCopyPlan.Add($record) }
        }
    }
    # Hash only files that changed. Unchanged files were part of the previously
    # verified single-folder backup and are retained in place.
    $fileNumber = 0
    foreach ($record in $verifiedCopyPlan) {
        Assert-NotCancelled
        $fileNumber++
        $file = $record.Item
        if ($fileNumber -eq 1 -or $fileNumber % 100 -eq 0 -or $fileNumber -eq $verifiedCopyPlan.Count) {
            Write-Output "DEVSTACK-UPGRADE|Verifying copied files ($fileNumber of $($verifiedCopyPlan.Count)): $($file.FullName)"
        }
        $copy = Join-Path $backup $record.Relative
        if ((Get-FileDigest $file.FullName) -ne (Get-FileDigest $copy)) { throw "Backup verification failed: $($record.Relative)" }
    }
    $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $copyPlan) { [void]$expected.Add($record.Relative) }
    foreach ($directory in $items | Where-Object { $_.PSIsContainer -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }) {
        [void]$expected.Add((Get-RelativePath $directory $rootPrefix))
    }
    Write-Output 'DEVSTACK-UPGRADE|Removing files that no longer exist in the installation...'
    $stale = @($previousMap.Keys | Where-Object { -not $expected.Contains($_) } | Sort-Object { $_.Length } -Descending)
    foreach ($relative in $stale) {
        Assert-NotCancelled
        $entry = $previousMap[$relative]
        $obsoletePath = Join-Path $backup $relative
        Write-Output "DEVSTACK-UPGRADE|Removing obsolete backup item: $obsoletePath"
        if ($entry.PSIsContainer) { [IO.Directory]::Delete($obsoletePath, $false) } else { [IO.File]::Delete($obsoletePath) }
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
    if ($null -ne $previousBackup) {
        $report += "Incremental backup sync: kept $reuseCount unchanged files; copied $($verifiedCopyPlan.Count) changed files and updated $($links.Count) links."
    }
    else {
        $report += "Full initial snapshot: copied $copyNumber files/links."
    }
    $report += 'Projects, databases, passwords, ports and custom settings will be preserved.'
    $report | Set-Content -LiteralPath $ResultPath
    $report | Set-Content -LiteralPath (Join-Path $backup 'upgrade-report.txt')
    # Keep exactly one generated backup. Delete older completed snapshots only
    # after the new current backup has been copied and verified successfully.
    foreach ($oldBackup in @(Get-ChildItem -LiteralPath $backupParent -Directory -Force | Where-Object { $_.FullName -ne $backup })) {
        $oldReport = Join-Path $oldBackup.FullName 'upgrade-report.txt'
        $generatedName = $oldBackup.Name -match '^\d{8}-\d{6}-[0-9a-fA-F]{8}$'
        $completedGenerated = (Test-Path -LiteralPath $oldReport) -and ((Get-Content -LiteralPath $oldReport -Raw -ErrorAction SilentlyContinue) -match 'Verified full backup:')
        if ($generatedName -or $completedGenerated) {
            Write-Output "DEVSTACK-UPGRADE|Removing older completed backup $($oldBackup.Name)..."
            Remove-Item -LiteralPath $oldBackup.FullName -Recurse -Force
        }
    }
}
catch {
    "Update cannot continue: $($_.Exception.Message)" | Set-Content -LiteralPath $ResultPath
    exit 1
}
