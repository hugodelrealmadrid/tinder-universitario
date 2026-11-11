param(
    [Parameter(Mandatory)]
    [ValidateSet('Crear','Recuperar')]
    [string]$Accion,
    [string]$Archivo
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'LIGO-Release-Privado'
$keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$keyName = 'ligo-release.p12'
$key = Join-Path $root $keyName
$archive = Join-Path $root 'ligo-release-respaldo.7z'

function Invoke-Checked($Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "La operación terminó con código $LASTEXITCODE." }
}

if (!(Test-Path -LiteralPath $keytool) -or !(Test-Path -LiteralPath $sevenZip)) {
    throw 'Se requieren keytool de Android Studio y 7-Zip.'
}

if (!(Test-Path -LiteralPath $root)) {
    if ($Accion -ne 'Crear') { throw 'Primero hay que crear el almacén local.' }
    New-Item -ItemType Directory -Path $root | Out-Null
}
if ((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'La carpeta privada no puede ser un enlace o punto de montaje.'
}
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Invoke-Checked 'icacls.exe' @($root, '/inheritance:r', '/grant:r', ('*'+$sid+':(OI)(CI)F'), '*S-1-5-18:(OI)(CI)F')

if ($Accion -eq 'Crear') {
    if (Test-Path -LiteralPath $archive) { throw 'Ya existe un respaldo local. Conservá ese archivo.' }
    if (!(Test-Path -LiteralPath $key)) {
        Write-Host 'Ingresá y guardá en tu gestor la contraseña del keystore.'
        Invoke-Checked $keytool @('-genkeypair','-storetype','PKCS12','-keystore',$key,'-alias','ligo-release','-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=LIGO')
    }
    Write-Host 'Usá otra contraseña para cifrar el archivo 7z. Guardala en tu gestor.'
    Push-Location -LiteralPath $root
    try { Invoke-Checked $sevenZip @('a','-t7z','-mhe=on','-p',$archive,$keyName) }
    finally { Pop-Location }
    Get-FileHash -LiteralPath $archive -Algorithm SHA256
    Write-Host 'Subí manualmente solo este .7z a Drive privado. Luego descargalo a otra ruta y ejecutá Recuperar.'
    exit
}

if (!$Archivo) { throw 'Indica la ruta de la descarga con -Archivo.' }
$download = (Get-Item -LiteralPath $Archivo).FullName
if ($download -eq $archive) { throw 'Seleccioná la copia descargada, no el archivo local original.' }
if ((Get-FileHash -LiteralPath $download).Hash -ne (Get-FileHash -LiteralPath $archive).Hash) {
    throw 'El SHA-256 del archivo descargado difiere del original.'
}

$restore = Join-Path $root ('verificacion-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $restore | Out-Null
$restoredKey = Join-Path $restore $keyName
try {
    Invoke-Checked $sevenZip @('e',('-o'+$restore),$download,$keyName)
    $hash = (Get-FileHash -LiteralPath $restoredKey -Algorithm SHA256).Hash
    if ($hash -ne (Get-FileHash -LiteralPath $key -Algorithm SHA256).Hash) {
        throw 'El SHA-256 del keystore recuperado difiere del original.'
    }
    Invoke-Checked $keytool @('-list','-v','-storetype','PKCS12','-keystore',$restoredKey,'-alias','ligo-release')
    Write-Host "Copia recuperada y leída por keytool. SHA-256 del keystore: $hash"
} finally {
    if (Test-Path -LiteralPath $restoredKey) { Remove-Item -LiteralPath $restoredKey }
    Remove-Item -LiteralPath $restore
}
