[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installFullPath = [IO.Path]::GetFullPath($InstallRoot)
$certificateDirectory = Join-Path $installFullPath 'runtime/certificates'
$bundlePath = Join-Path $certificateDirectory 'cacert.pem'
$tempDirectory = Join-Path $certificateDirectory ('.refresh-' + [Guid]::NewGuid().ToString('N'))
$bundleUrl = 'https://curl.se/ca/cacert.pem'
$checksumUrl = 'https://curl.se/ca/cacert.pem.sha256'

function Test-ExistingBundle {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $text = [IO.File]::ReadAllText($Path)
        return $text.Length -gt 50000 -and ([regex]::Matches($text, '-----BEGIN CERTIFICATE-----')).Count -gt 50
    }
    catch {
        return $false
    }
}

[IO.Directory]::CreateDirectory($certificateDirectory) | Out-Null
[IO.Directory]::CreateDirectory($tempDirectory) | Out-Null
$downloadedBundle = Join-Path $tempDirectory 'cacert.pem'
$downloadedChecksum = Join-Path $tempDirectory 'cacert.pem.sha256'
$lastError = $null
$verified = $false

try {
    for ($attempt = 1; $attempt -le 3 -and -not $verified; $attempt++) {
        $webClient = [Net.WebClient]::new()
        try {
            Write-Host "Downloading current Mozilla CA bundle (attempt $attempt of 3)..."
            $webClient.DownloadFile($bundleUrl, $downloadedBundle)
            $webClient.DownloadFile($checksumUrl, $downloadedChecksum)

            $checksumText = [IO.File]::ReadAllText($downloadedChecksum)
            $checksumMatch = [regex]::Match($checksumText, '(?i)\b([0-9a-f]{64})\b')
            if (-not $checksumMatch.Success) {
                throw 'The CA bundle checksum response did not contain a SHA-256 value.'
            }
            $expectedHash = $checksumMatch.Groups[1].Value.ToLowerInvariant()
            $stream = [IO.File]::OpenRead($downloadedBundle)
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try {
                $actualHash = ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
            }
            finally {
                $algorithm.Dispose()
                $stream.Dispose()
            }
            if ($actualHash -cne $expectedHash) {
                throw "The downloaded CA bundle failed SHA-256 verification (expected $expectedHash, got $actualHash)."
            }

            $pem = [IO.File]::ReadAllText($downloadedBundle)
            if ($pem.Length -lt 50000 -or ([regex]::Matches($pem, '-----BEGIN CERTIFICATE-----')).Count -lt 50) {
                throw 'The downloaded CA bundle is incomplete or is not a PEM certificate bundle.'
            }
            $verified = $true
        }
        catch {
            $lastError = $_
            if (Test-Path -LiteralPath $downloadedBundle) {
                Remove-Item -LiteralPath $downloadedBundle -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $downloadedChecksum) {
                Remove-Item -LiteralPath $downloadedChecksum -Force -ErrorAction SilentlyContinue
            }
            if ($attempt -lt 3) {
                Write-Warning "CA bundle download or verification failed: $($_.Exception.Message) Retrying."
                Start-Sleep -Seconds ($attempt * 2)
            }
        }
        finally {
            $webClient.Dispose()
        }
    }

    if (-not $verified) {
        if (Test-ExistingBundle -Path $bundlePath) {
            Write-Warning "Could not refresh the CA bundle; retaining the existing verified-format bundle. $($lastError.Exception.Message)"
            return
        }
        throw "Could not install the PHP CA bundle. $($lastError.Exception.Message)"
    }

    if (Test-Path -LiteralPath $bundlePath) {
        $previousPath = Join-Path $tempDirectory 'cacert.previous.pem'
        Move-Item -LiteralPath $bundlePath -Destination $previousPath
        try {
            Move-Item -LiteralPath $downloadedBundle -Destination $bundlePath
            Remove-Item -LiteralPath $previousPath -Force
        }
        catch {
            if (-not (Test-Path -LiteralPath $bundlePath) -and (Test-Path -LiteralPath $previousPath)) {
                Move-Item -LiteralPath $previousPath -Destination $bundlePath
            }
            throw
        }
    }
    else {
        Move-Item -LiteralPath $downloadedBundle -Destination $bundlePath
    }

    Write-Host "Verified Mozilla CA bundle installed at '$bundlePath'."
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
