param([Parameter(Mandatory)][string]$Repo)
$ErrorActionPreference = 'Stop'
$base = Join-Path $env:LOCALAPPDATA 'LIGO-Android'
if (!(Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base | Out-Null }
if ((Get-Item -LiteralPath $base).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'La carpeta de compilación no puede ser un enlace.'
}
$root = Join-Path $base ('release-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
foreach ($folder in @($root, "$root/android/app/src", "$root/deploy")) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}
$entries = @('lib','assets','pubspec.yaml','pubspec.lock','.metadata',
    'android/build.gradle.kts','android/settings.gradle.kts','android/gradle.properties',
    'android/gradle','android/gradlew','android/gradlew.bat','android/local.properties',
    'android/app/build.gradle.kts','android/app/src/main','android/app/src/production',
    'deploy/existing-project.android.local.json')
$checks = @{}
foreach ($entry in $entries) {
    $source = Join-Path $Repo $entry
    $target = Join-Path $root $entry
    Copy-Item -LiteralPath $source -Destination $target -Recurse
    if ((Get-Item -LiteralPath $target).PSIsContainer) {
        foreach ($file in Get-ChildItem -LiteralPath $target -Recurse -File) {
            $relative = $file.FullName.Substring($root.Length + 1)
            $checks[$relative] = (Get-FileHash -LiteralPath $file.FullName).Hash
        }
    } else {
        $checks[$entry] = (Get-FileHash -LiteralPath $target).Hash
    }
}
if (!(Select-String -LiteralPath "$root/lib/features/profile/profile_screen.dart" -SimpleMatch 'Guardar sede' -Quiet) -or
    !(Select-String -LiteralPath "$root/lib/features/profile/profile_service.dart" -SimpleMatch 'completeAffiliation' -Quiet)) {
    throw 'La copia no contiene el flujo actualizado de sede.'
}
Push-Location -LiteralPath $root
try {
    flutter clean | Out-Host
    if ($LASTEXITCODE) { throw 'flutter clean falló.' }
    flutter pub get --offline --enforce-lockfile | Out-Host
    if ($LASTEXITCODE) { throw 'No se pudo restaurar el lockfile.' }
    Push-Location -LiteralPath "$root/android"
    try {
        & .\gradlew.bat :app:clean --offline --no-build-cache | Out-Host
        if ($LASTEXITCODE) { throw 'Gradle clean falló.' }
    } finally { Pop-Location }
} finally { Pop-Location }
# Flutter regenera local.properties y el registro de plugins desde el lockfile.
$checks.Remove('android/local.properties')
$checks.Remove('android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java')
@{repo=$Repo;branch='codex/ligo';head=(git -C $Repo rev-parse HEAD);checks=$checks} |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$root/ligo-release-source.json" -Encoding utf8
$root
