[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$requiredPaths = @(
    'DevStack.sln',
    'runtime/manifest/components.json',
    'runtime/templates/httpd.conf.template',
    'runtime/templates/php.ini.template',
    'runtime/templates/mariadb.ini.template',
    'src/DevStack.Core/DevStack.Core.csproj',
    'src/DevStack.ControlPanel/DevStack.ControlPanel.csproj',
    'www/index.php'
)

foreach ($relativePath in $requiredPaths) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Required path is missing: $relativePath"
    }
}

$manifestPath = Join-Path $repositoryRoot 'runtime/manifest/components.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.components.Count -lt 3) {
    throw 'Runtime manifest is invalid.'
}

Write-Host 'DevStack repository layout is valid.'
