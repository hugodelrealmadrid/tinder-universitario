$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$approved = '1403d48c85ceeed8fcbfb509e02cc37ff84a04a8c121d97d3ae5e1ff2e8a47a3'
$key = Join-Path $env:LOCALAPPDATA 'LIGO-Release-Privado/ligo-release.p12'
$java = 'C:\Program Files\Android\Android Studio\jbr'
$tools = Join-Path $env:LOCALAPPDATA 'Android/Sdk/build-tools/36.1.0'
Set-Location -LiteralPath $repo
if ((git branch --show-current) -ne 'codex/ligo') { throw 'Se requiere codex/ligo.' }
git merge-base --is-ancestor bfc89e8 HEAD
if ($LASTEXITCODE) { throw 'Falta la revisión de filtros aprobada.' }
if (git status --porcelain -- lib/features/verification/admin_workspace.dart) {
    throw 'El componente aprobado tiene cambios locales.'
}
$config = Get-Content -LiteralPath 'deploy/existing-project.android.local.json' -Raw | ConvertFrom-Json
if ($config.APP_ENV -ne 'production' -or $config.FIREBASE_PROJECT_ID -ne 'tinder-universitario' -or $config.VERIFICATION_BACKEND_URL.TrimEnd('/') -ne 'https://tinder-api-rcgmfjcicq-ue.a.run.app') {
    throw 'La configuración Android no corresponde a producción.'
}
if (!(Test-Path -LiteralPath $key -PathType Leaf)) { throw 'Falta el keystore Release existente.' }
$env:JAVA_HOME = $java
$root = & (Join-Path $PSScriptRoot 'ligo-prepare-android.ps1') -Repo $repo
Push-Location -LiteralPath $root
try {
    # Regenerar los plugins en la compilación Release, como en el asistente validado de la versión 9.
    flutter clean
    if ($LASTEXITCODE) { throw 'Falló flutter clean.' }
    $lock = (Get-FileHash -LiteralPath 'pubspec.lock').Hash
    $secure = Read-Host 'Contraseña del keystore Release' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $previousGradleOpts = $env:GRADLE_OPTS
    try {
        $env:GRADLE_OPTS = "$previousGradleOpts -Dorg.gradle.caching=false"
        $env:TINDER_KEYSTORE_FILE = $key
        $env:TINDER_KEY_ALIAS = 'ligo-release'
        $env:TINDER_KEYSTORE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        $env:TINDER_KEY_PASSWORD = $env:TINDER_KEYSTORE_PASSWORD
        $cert = & "$java/bin/keytool.exe" '-J-Duser.language=en' -list -v -keystore $key -storetype PKCS12 -alias ligo-release '-storepass:env' TINDER_KEYSTORE_PASSWORD
        if ($LASTEXITCODE -or ($cert -join ' ') -notmatch 'SHA256:\s*([0-9A-F:]{95})' -or $Matches[1].Replace(':','').ToLowerInvariant() -ne $approved) {
            throw 'El certificado no coincide con el Release aprobado.'
        }
        flutter build apk --release --flavor production --target lib/main.dart --build-number 10 --build-name 2.0.0 --pub --dart-define-from-file=deploy/existing-project.android.local.json --dart-define=LIGO_MULTIUNIVERSITY=true --dart-define=LIGO_STORIES=true --dart-define=LIGO_NOTIFICATIONS=true --dart-define=LIGO_BACKEND_WRITES=true --dart-define=LIGO_FCM=false
        if ($LASTEXITCODE -or (Get-FileHash -LiteralPath 'pubspec.lock').Hash -ne $lock) { throw 'Falló la compilación o cambió el lockfile.' }
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        $secure.Dispose()
        $env:GRADLE_OPTS = $previousGradleOpts
        foreach ($name in @('TINDER_KEYSTORE_FILE','TINDER_KEY_ALIAS','TINDER_KEYSTORE_PASSWORD','TINDER_KEY_PASSWORD')) {
            [Environment]::SetEnvironmentVariable($name,$null,'Process')
        }
    }
    $apk = 'build/app/outputs/flutter-apk/app-production-release.apk'
    $badging = & "$tools/aapt.exe" dump badging $apk
    if ($LASTEXITCODE -or ($badging -join ' ') -notmatch "package: name='com.example.tinder_universitario' versionCode='10' versionName='2.0.0'") {
        throw 'El paquete o la versión Android no coinciden.'
    }
    $signature = & "$tools/apksigner.bat" verify --print-certs $apk
    if ($LASTEXITCODE -or ($signature -join ' ') -notmatch "certificate SHA-256 digest: $approved") { throw 'Firma APK inválida.' }
    $out = Join-Path $repo 'build/ligo20-android-entrega/LIGO-2.0.0-10-production.apk'
    if (Test-Path -LiteralPath $out) { throw 'Ya existe una APK de entrega con ese nombre.' }
    Copy-Item -LiteralPath $apk -Destination $out
    Write-Host "Copia aislada: $root"
    Get-FileHash -LiteralPath $out -Algorithm SHA256
} finally {
    Pop-Location
}
