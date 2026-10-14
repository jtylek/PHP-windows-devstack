[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/apache/build-config.json'),

    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'),

    [string]$WorkDirectoryRoot = [System.IO.Path]::GetTempPath(),

    [switch]$KeepWorkDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows) {
    throw 'The Apache runtime must be built on 64-bit Windows.'
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'The Apache runtime build requires 64-bit Windows.'
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Apache build configuration does not exist: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($config.schemaVersion -ne 1) {
    throw "Unsupported Apache build configuration schema: $($config.schemaVersion)"
}

if ($config.apache.archiveUrl -notmatch '^https://') {
    throw 'The Apache source archive must use HTTPS.'
}

if ($config.apache.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw 'The Apache source archive must have a valid SHA-256 value.'
}

if ($config.vcpkg.commit -notmatch '^[a-fA-F0-9]{40}$') {
    throw 'The vcpkg revision must be a full Git commit ID.'
}

$requiredCommands = @('git', 'cmake', 'ninja', 'tar')
foreach ($command in $requiredCommands) {
    if ($null -eq (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required build command is not available: $command"
    }
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw 'Visual Studio Installer discovery tool (vswhere.exe) was not found.'
}

$vsRoot = & $vswhere -property installationPath -latest -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64
if ([string]::IsNullOrWhiteSpace($vsRoot)) {
    throw 'Visual Studio 2022 with the C++ x64 toolchain was not found.'
}

$devShellModule = Join-Path $vsRoot 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll'
Import-Module $devShellModule
Enter-VsDevShell -VsInstallPath $vsRoot -DevCmdArguments '-arch=x64 -host_arch=x64' -SkipAutomaticLocation | Out-Null

$outputFullPath = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($outputFullPath) | Out-Null

$workParent = [System.IO.Path]::GetFullPath($WorkDirectoryRoot)
[System.IO.Directory]::CreateDirectory($workParent) | Out-Null
$workRoot = Join-Path $workParent ('ds-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$sourceParent = Join-Path $workRoot 'source'
$buildRoot = Join-Path $workRoot 'build'
$installRoot = Join-Path $workRoot 'install'
$vcpkgRoot = Join-Path $workRoot 'vcpkg'
$sourceArchive = Join-Path $workRoot "httpd-$($config.apache.version).tar.gz"

[System.IO.Directory]::CreateDirectory($sourceParent) | Out-Null

try {
    Write-Host "Downloading Apache HTTP Server $($config.apache.version) source..."
    Invoke-WebRequest -Uri $config.apache.archiveUrl -OutFile $sourceArchive -UseBasicParsing

    $actualSourceHash = (Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedSourceHash = $config.apache.sha256.ToLowerInvariant()
    if ($actualSourceHash -cne $expectedSourceHash) {
        throw "Apache source SHA-256 verification failed. Expected $expectedSourceHash but received $actualSourceHash."
    }

    & tar -xf $sourceArchive -C $sourceParent
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed with exit code $LASTEXITCODE."
    }

    $sourceRoot = Join-Path $sourceParent "httpd-$($config.apache.version)"
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'CMakeLists.txt') -PathType Leaf)) {
        throw 'The verified Apache archive has an unexpected layout.'
    }

    Write-Host "Cloning vcpkg $($config.vcpkg.tag)..."
    & git clone --quiet --depth 1 --branch $config.vcpkg.tag https://github.com/microsoft/vcpkg.git $vcpkgRoot
    if ($LASTEXITCODE -ne 0) {
        throw "git clone for vcpkg failed with exit code $LASTEXITCODE."
    }

    $actualVcpkgCommit = (& git -C $vcpkgRoot rev-parse HEAD).Trim().ToLowerInvariant()
    $expectedVcpkgCommit = $config.vcpkg.commit.ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $actualVcpkgCommit -cne $expectedVcpkgCommit) {
        throw "vcpkg revision verification failed. Expected $expectedVcpkgCommit but received $actualVcpkgCommit."
    }

    & (Join-Path $vcpkgRoot 'bootstrap-vcpkg.bat') -disableMetrics
    if ($LASTEXITCODE -ne 0) {
        throw "vcpkg bootstrap failed with exit code $LASTEXITCODE."
    }

    $vcpkgArguments = @('install', '--triplet', $config.vcpkg.triplet) + @($config.vcpkg.packages)
    & (Join-Path $vcpkgRoot 'vcpkg.exe') @vcpkgArguments
    if ($LASTEXITCODE -ne 0) {
        throw "vcpkg dependency installation failed with exit code $LASTEXITCODE."
    }

    $installed = Join-Path $vcpkgRoot "installed/$($config.vcpkg.triplet)"
    $cmakeArguments = @(
        '-S', $sourceRoot,
        '-B', $buildRoot,
        '-G', $config.toolchain.generator,
        "-DCMAKE_BUILD_TYPE=$($config.toolchain.configuration)",
        "-DCMAKE_INSTALL_PREFIX=$($installRoot.Replace('\', '/'))",
        "-DCMAKE_TOOLCHAIN_FILE=$($vcpkgRoot.Replace('\', '/'))/scripts/buildsystems/vcpkg.cmake",
        "-DVCPKG_TARGET_TRIPLET=$($config.vcpkg.triplet)",
        "-DAPR_INCLUDE_DIR=$($installed.Replace('\', '/'))/include",
        "-DAPR_LIBRARIES=$($installed.Replace('\', '/'))/lib/libapr-1.lib;$($installed.Replace('\', '/'))/lib/libaprutil-1.lib",
        "-DNGHTTP2_INCLUDE_DIR=$($installed.Replace('\', '/'))/include",
        "-DNGHTTP2_LIBRARIES=$($installed.Replace('\', '/'))/lib/nghttp2.lib",
        "-DJANSSON_INCLUDE_DIR=$($installed.Replace('\', '/'))/include",
        "-DJANSSON_LIBRARIES=$($installed.Replace('\', '/'))/lib/jansson.lib",
        '-DENABLE_MIME_MAGIC=A'
    )

    & cmake @cmakeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Apache CMake configuration failed with exit code $LASTEXITCODE."
    }

    & cmake --build $buildRoot --config $config.toolchain.configuration --parallel 2
    if ($LASTEXITCODE -ne 0) {
        throw "Apache compilation failed with exit code $LASTEXITCODE."
    }

    & cmake --install $buildRoot --config $config.toolchain.configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Apache installation failed with exit code $LASTEXITCODE."
    }

    $apacheBin = Join-Path $installRoot 'bin'
    Get-ChildItem -LiteralPath (Join-Path $installed 'bin') -Filter '*.dll' -File |
        Copy-Item -Destination $apacheBin -Force

    if (-not [string]::IsNullOrWhiteSpace($env:VCToolsRedistDir)) {
        $crtDirectory = Join-Path $env:VCToolsRedistDir 'x64/Microsoft.VC143.CRT'
        if (Test-Path -LiteralPath $crtDirectory -PathType Container) {
            Get-ChildItem -LiteralPath $crtDirectory -Filter '*.dll' -File |
                Copy-Item -Destination $apacheBin -Force
        }
    }

    $requiredRuntimeFiles = @(
        'bin/httpd.exe',
        'bin/libhttpd.dll',
        'modules/mod_rewrite.so',
        'modules/mod_ssl.so'
    )
    foreach ($relativePath in $requiredRuntimeFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot $relativePath) -PathType Leaf)) {
            throw "Built Apache runtime is missing required file '$relativePath'."
        }
    }

    $env:PATH = "$apacheBin;$env:PATH"
    & (Join-Path $apacheBin 'httpd.exe') -V
    if ($LASTEXITCODE -ne 0) {
        throw "Built httpd.exe smoke test failed with exit code $LASTEXITCODE."
    }

    $artifactBaseName = "apache-httpd-$($config.apache.version)-win64-vs17"
    $zipPath = Join-Path $outputFullPath "$artifactBaseName.zip"
    $checksumPath = "$zipPath.sha256"
    $receiptPath = Join-Path $outputFullPath "$artifactBaseName.build.json"

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $installRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $artifactHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$artifactHash  $([System.IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath $checksumPath -Encoding ascii

    $receipt = [ordered]@{
        schemaVersion = 1
        artifact = [System.IO.Path]::GetFileName($zipPath)
        sha256 = $artifactHash
        apacheVersion = $config.apache.version
        apacheSourceUrl = $config.apache.archiveUrl
        apacheSourceSha256 = $expectedSourceHash
        vcpkgTag = $config.vcpkg.tag
        vcpkgCommit = $expectedVcpkgCommit
        vcpkgTriplet = $config.vcpkg.triplet
        vcpkgPackages = @($config.vcpkg.packages)
        visualStudio = $config.toolchain.visualStudio
        architecture = $config.toolchain.architecture
        configuration = $config.toolchain.configuration
        builtAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding utf8

    Write-Host "Created $zipPath"
    Write-Host "SHA-256: $artifactHash"
}
finally {
    if ($KeepWorkDirectory) {
        Write-Host "Build work directory retained at '$workRoot'."
    }
    elseif (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
