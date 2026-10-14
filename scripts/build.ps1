[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot 'validate-layout.ps1')
& (Join-Path $PSScriptRoot 'verify-runtime-manifest.ps1')
dotnet restore (Join-Path $repositoryRoot 'DevStack.sln')
dotnet build (Join-Path $repositoryRoot 'DevStack.sln') --configuration $Configuration --no-restore
