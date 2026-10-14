[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime/manifest/components.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Runtime manifest does not exist: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 2) {
    throw "Unsupported runtime manifest schema: $($manifest.schemaVersion)"
}

$names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($component in $manifest.components) {
    if ([string]::IsNullOrWhiteSpace($component.name) -or -not $names.Add($component.name)) {
        throw "Component names must be nonempty and unique."
    }

    if ([string]::IsNullOrWhiteSpace($component.version)) {
        throw "Component '$($component.name)' has no pinned version."
    }

    if ($component.archiveUrl -notmatch '^https://') {
        throw "Component '$($component.name)' must use an HTTPS archive URL."
    }

    if ($component.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw "Component '$($component.name)' does not have a valid SHA-256 value."
    }

    if ($component.targetDirectory -notmatch '^[a-zA-Z0-9._-]+$') {
        throw "Component '$($component.name)' has an unsafe target directory."
    }

    if ($component.enabled -and $component.archiveType -ne 'zip') {
        throw "Enabled component '$($component.name)' must currently use a ZIP archive."
    }

    if ($component.enabled -and $component.requiredFiles.Count -eq 0) {
        throw "Enabled component '$($component.name)' must declare required files."
    }

    foreach ($requiredFile in $component.requiredFiles) {
        if ([System.IO.Path]::IsPathRooted($requiredFile) -or $requiredFile.Contains('..')) {
            throw "Component '$($component.name)' contains an unsafe required-file path."
        }
    }
}

Write-Host "Runtime manifest is valid ($($manifest.components.Count) components)."
