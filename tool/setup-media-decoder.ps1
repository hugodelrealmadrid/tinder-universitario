$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$archive = Join-Path $PSScriptRoot 'ffmpeg/verified.zip'
$binary = Join-Path $PSScriptRoot 'ffmpeg/release/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe'
if (Test-Path -LiteralPath $binary) {
    $version = & $binary -version
    if ($LASTEXITCODE -ne 0 -or $version[0] -notmatch 'ffmpeg version 9\.0\.2-') { throw 'Decoder inesperado' }
    Write-Output 'FFmpeg 9.0.2 ya instalado localmente.'
    exit 0
}
if (-not (Test-Path -LiteralPath $archive)) {
    node tool/download-ffmpeg.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Descarga no verificada' }
}
$expected = '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba'
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'SHA-256 incorrecto' }
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $PSScriptRoot 'ffmpeg/release')
if (-not (Test-Path -LiteralPath $binary)) { throw 'Falta binario verificado' }
Write-Output 'Decoder local preparado; conservar LICENSE y README del paquete.'
