[CmdletBinding()]
param(
    [string]$InstallRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$passwordPath = Join-Path ([System.IO.Path]::GetFullPath($InstallRoot)) 'data/secrets/mariadb-root-password.dpapi'
if (-not (Test-Path -LiteralPath $passwordPath -PathType Leaf)) {
    throw "MariaDB password file was not found: $passwordPath"
}

Add-Type -AssemblyName System.Security
$protected = [System.IO.File]::ReadAllBytes($passwordPath)
$passwordBytes = [Security.Cryptography.ProtectedData]::Unprotect(
    $protected,
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser)
try {
    [Text.Encoding]::UTF8.GetString($passwordBytes)
}
finally {
    [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
}
