[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [System.IO.Path]::GetFullPath($InstallRoot)

foreach ($culture in @('cs', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pl', 'pt-BR', 'ru', 'tr', 'zh-Hans', 'zh-Hant')) {
    $path = Join-Path $root $culture
    if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove satellite resources')) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

$optionalPaths = @(
    'runtime/apache/manual',
    'runtime/apache/include',
    'runtime/apache/lib',
    'runtime/php/dev',
    'runtime/php/php8embed.lib',
    'runtime/php/php.ini-development',
    'runtime/php/php-cgi.exe',
    'runtime/php/phpdbg.exe',
    'runtime/php/php8phpdbg.dll',
    'runtime/mariadb/include',
    'runtime/mariadb/bin/server.pdb',
    'runtime/mariadb/bin/server.lib',
    'runtime/mariadb/bin/mariadbd.pdb',
    'runtime/mariadb/lib/mariadbclient.lib',
    'runtime/mariadb/lib/libmariadb.pdb'
)
foreach ($relativePath in $optionalPaths) {
    $path = Join-Path $root $relativePath
    if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove development/runtime documentation payload')) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}
