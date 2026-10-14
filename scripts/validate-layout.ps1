[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$requiredPaths = @(
    'DevStack.sln',
    '.github/workflows/build-apache.yml',
    'build/apache/build-config.json',
    'runtime/manifest/components.json',
    'runtime/templates/httpd.conf.template',
    'runtime/templates/php.ini.template',
    'runtime/templates/mariadb.ini.template',
    'scripts/install-runtime.ps1',
    'scripts/build-apache.ps1',
    'scripts/install-apache-artifact.ps1',
    'scripts/verify-runtime-manifest.ps1',
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
if ($manifest.schemaVersion -ne 2 -or $manifest.components.Count -lt 3) {
    throw 'Runtime manifest is invalid.'
}

Write-Host 'DevStack repository layout is valid.'
