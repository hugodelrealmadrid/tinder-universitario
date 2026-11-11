param(
    [Parameter(Mandatory)]
    [string]$CopiaDescargada,
    [string]$ProyectoAislado,
    [switch]$Aab
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repo
if ((git branch --show-current) -ne 'codex/ligo') { throw 'Se requiere codex/ligo.' }
$CopiaDescargada = (Resolve-Path -LiteralPath $CopiaDescargada).Path
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
if ($ProyectoAislado -eq 'auto') {
    $ProyectoAislado = & (Join-Path $PSScriptRoot 'ligo-prepare-android.ps1') -Repo $repo
}
if ($ProyectoAislado) {
    if (!(Test-Path -LiteralPath $ProyectoAislado -PathType Container)) {
        throw 'La copia aislada no existe. Ejecutá nuevamente con -ProyectoAislado auto.'
    }
    $ProyectoAislado = (Resolve-Path -LiteralPath $ProyectoAislado).Path
    $isolatedParent = Join-Path $env:LOCALAPPDATA 'LIGO-Android'
    if ((Split-Path -Parent $ProyectoAislado) -ne $isolatedParent -or
        (Get-Item -LiteralPath $ProyectoAislado).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Seleccioná una compilación aislada preparada para LIGO.'
    }
    $manifest = Get-Content -LiteralPath (Join-Path $ProyectoAislado 'ligo-release-source.json') -Raw | ConvertFrom-Json
    if ($manifest.repo -ne $repo -or $manifest.branch -ne 'codex/ligo' -or $manifest.head -ne (git rev-parse HEAD)) {
        throw 'La revisión de la copia no coincide con el worktree.'
    }
    foreach ($entry in $manifest.checks.PSObject.Properties) {
        foreach ($root in @($repo, $ProyectoAislado)) {
            if ((Get-FileHash -LiteralPath (Join-Path $root $entry.Name)).Hash -ne $entry.Value) {
                throw "La fuente cambió desde que se preparó la copia: $($entry.Name)"
            }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $ProyectoAislado 'build/app/outputs')) {
        throw 'La copia ya tiene salidas Android. Conservá esos archivos y prepará otra copia limpia.'
    }
}
& (Join-Path $PSScriptRoot 'ligo-release-key.ps1') -Accion Recuperar -Archivo $CopiaDescargada
if ($ProyectoAislado) { Set-Location -LiteralPath $ProyectoAislado }
$key = Join-Path $env:LOCALAPPDATA 'LIGO-Release-Privado/ligo-release.p12'
$secure = Read-Host 'Contraseña del keystore para Gradle' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$previousGradleOpts = $env:GRADLE_OPTS
try {
    if ($ProyectoAislado) { $env:GRADLE_OPTS = "$previousGradleOpts -Dorg.gradle.caching=false" }
    $env:TINDER_KEYSTORE_FILE = $key
    $env:TINDER_KEY_ALIAS = 'ligo-release'
    $env:TINDER_KEYSTORE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    $env:TINDER_KEY_PASSWORD = $env:TINDER_KEYSTORE_PASSWORD
    $java = 'C:\Program Files\Android\Android Studio\jbr\bin'
    $cert = & (Join-Path $java 'keytool.exe') '-J-Duser.language=en' -list -v -keystore $key -storetype PKCS12 -alias ligo-release '-storepass:env' TINDER_KEYSTORE_PASSWORD
    if ($LASTEXITCODE -ne 0 -or ($cert -join ' ') -notmatch 'SHA256:\s*([0-9A-F:]{95})') {
        throw 'No se pudo verificar la huella pública del almacén.'
    }
    $expectedCert = $Matches[1].Replace(':','').ToLowerInvariant()
    if ($expectedCert -ne '1403d48c85ceeed8fcbfb509e02cc37ff84a04a8c121d97d3ae5e1ff2e8a47a3') {
        throw 'El almacén no corresponde al certificado Release aprobado de LIGO.'
    }
    $flags = @('--release','--flavor','production','--target=lib/main.dart','--no-pub',
        '--dart-define-from-file=deploy/existing-project.android.local.json',
        '--dart-define=LIGO_MULTIUNIVERSITY=true','--dart-define=LIGO_STORIES=true',
        '--dart-define=LIGO_NOTIFICATIONS=true','--dart-define=LIGO_BACKEND_WRITES=true','--dart-define=LIGO_FCM=false')
    flutter build apk @flags
    if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación APK.' }
    if ($Aab) {
        flutter build appbundle @flags
        if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación AAB.' }
    }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    $secure.Dispose()
    [Environment]::SetEnvironmentVariable('GRADLE_OPTS',$previousGradleOpts,'Process')
    foreach ($name in @('TINDER_KEYSTORE_FILE','TINDER_KEY_ALIAS','TINDER_KEYSTORE_PASSWORD','TINDER_KEY_PASSWORD')) {
        [Environment]::SetEnvironmentVariable($name,$null,'Process')
    }
}
$tools = Join-Path $env:LOCALAPPDATA 'Android/Sdk/build-tools/36.1.0'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$apk = 'build/app/outputs/flutter-apk/app-production-release.apk'
$badging = & (Join-Path $tools 'aapt.exe') dump badging $apk
if ($LASTEXITCODE -ne 0 -or ($badging -join ' ') -notmatch "package: name='com.example.tinder_universitario' versionCode='9' versionName='2.0.0'") {
    throw 'La APK no coincide con paquete y versión esperados.'
}
$signature = & (Join-Path $tools 'apksigner.bat') verify --print-certs $apk
if ($LASTEXITCODE -ne 0 -or ($signature -join ' ') -notmatch "certificate SHA-256 digest: $expectedCert") {
    throw 'La firma de la APK no coincide con el almacén recuperado.'
}
Write-Host "Certificado Release SHA-256: $expectedCert"
Get-FileHash -LiteralPath $apk -Algorithm SHA256
if ($Aab) {
    $bundle = 'build/app/outputs/bundle/productionRelease/app-production-release.aab'
    & (Join-Path $java 'jarsigner.exe') -verify $bundle
    if ($LASTEXITCODE -ne 0) { throw 'Falló la verificación de la firma AAB.' }
    $bundleCert = & (Join-Path $java 'keytool.exe') '-J-Duser.language=en' -printcert -jarfile $bundle
    if ($LASTEXITCODE -ne 0 -or ($bundleCert -join ' ') -notmatch 'SHA256:\s*([0-9A-F:]{95})' -or
        $Matches[1].Replace(':','').ToLowerInvariant() -ne $expectedCert) {
        throw 'La firma del AAB no coincide con el almacén recuperado.'
    }
    Get-FileHash -LiteralPath $bundle -Algorithm SHA256
}

if ($ProyectoAislado) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $artifacts = @($apk)
    if ($Aab) { $artifacts += $bundle }
    foreach ($artifact in $artifacts) {
        $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $artifact).Path)
        try {
            $libs = @($zip.Entries | Where-Object FullName -Match '^(base/)?lib/[^/]+/libapp\.so$')
            if ($libs.Count -eq 0) { throw "No se halló código Flutter en $artifact" }
            foreach ($entry in $libs) {
                $abi = $entry.FullName.Split('/')[-2]
                $file = "build/app/intermediates/stripped_native_libs/productionRelease/stripProductionReleaseDebugSymbols/out/lib/$abi/libapp.so"
                $stream = $entry.Open()
                try { $packaged = (Get-FileHash -InputStream $stream).Hash } finally { $stream.Dispose() }
                if ($packaged -ne (Get-FileHash -LiteralPath $file).Hash) {
                    throw "La biblioteca empaquetada de $abi difiere de la generada por Gradle."
                }
                $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $file).Path)
                $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
                foreach ($marker in @('Guardar sede','registration/options','tinder-universitario','https://tinder-api-rcgmfjcicq-ue.a.run.app/')) {
                    if (!$text.Contains($marker)) { throw "Falta el marcador esperado en $abi" }
                }
                if ($text -match 'demo-ligo-staging|(?:localhost|127\.0\.0\.1|10\.0\.2\.2):(?:7465|7466|9399|8288|9498)') {
                    throw "Referencia de staging en $abi"
                }
            }
        } finally { $zip.Dispose() }
        Write-Host "Artefacto aislado: $((Resolve-Path -LiteralPath $artifact).Path)"
    }
}
