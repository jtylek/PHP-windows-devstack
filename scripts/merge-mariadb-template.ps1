[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallRoot)
$ErrorActionPreference = 'Stop'
$path = Join-Path $InstallRoot 'runtime/templates/mariadb.ini.template'
$defaultsPath = Join-Path $InstallRoot 'runtime/template-defaults/mariadb.ini.template'
$lines = @(Get-Content -LiteralPath $path)
$defaults = @(Get-Content -LiteralPath $defaultsPath)
$additions = @()
$section = ''
$existing = @{}
foreach ($line in $lines) {
    if ($line -match '^\s*\[([^\]]+)\]') { $section = $Matches[1] }
    if ($section -in @('mariadbd','mysqld','server','mariadb') -and $line -match '^\s*([a-zA-Z0-9_-]+)\s*=') {
        $existing[$Matches[1].Replace('-','_').ToLowerInvariant()] = $true
    }
}
$keys = @('innodb_buffer_pool_size','innodb_log_file_size','innodb_flush_log_at_trx_commit',
    'innodb_io_capacity','innodb_io_capacity_max','table_definition_cache','tmp_table_size',
    'max_heap_table_size','key_buffer_size','slow_query_log','slow_query_log_file','long_query_time','log_output')
foreach ($line in $defaults) {
    if ($line -match '^\s*([a-zA-Z0-9_]+)\s*=' -and $Matches[1] -in $keys -and -not $existing.ContainsKey($Matches[1])) { $additions += $line }
}
if ($additions.Count -eq 0) { return }
$output = @()
$inserted = $false
foreach ($line in $lines) {
    $output += $line
    if (-not $inserted -and $line -match '^\s*\[mariadbd\]\s*$') {
        $output += '# Added development defaults; existing explicit settings retained.'
        $output += $additions
        $inserted = $true
    }
}
if (-not $inserted) { throw 'MariaDB template lacks [mariadbd]; restore the template from your backup and review it.' }
[IO.File]::WriteAllLines($path, $output, (New-Object Text.UTF8Encoding($false)))
