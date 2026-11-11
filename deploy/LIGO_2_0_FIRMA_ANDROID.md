# Firma Release de LIGO en Windows

Hugo García Salazar custodia la clave. Abrí PowerShell de forma local, sin transcripción. Desde el worktree codex/ligo, ejecutá:

~~~powershell
& .\deploy\ligo-release-key.ps1 -Accion Crear
~~~

El asistente crea el PKCS12 fuera del repositorio, en `%LOCALAPPDATA%\LIGO-Release-Privado`, con acceso restringido. keytool pide la contraseña del almacén y 7-Zip pide otra para cifrar la copia con el encabezado protegido. Guardá ambas en tu gestor de contraseñas.

1. Subí manualmente solo `ligo-release-respaldo.7z` a Google Drive privado, con acceso restringido a tu cuenta. Conservá el SHA-256 que muestra el asistente. Mantené el PKCS12 original en la carpeta local.
2. Descargá el 7z desde Drive a otra carpeta. Desde el mismo worktree, ejecutá:

~~~powershell
& .\deploy\ligo-release-key.ps1 -Accion Recuperar -Archivo 'C:\ruta\de\descarga\ligo-release-respaldo.7z'
~~~

3. El asistente compara ambos archivos 7z, descifra en una carpeta privada, compara el SHA-256 del PKCS12 recuperado y abre la copia con keytool. Confirmá que keytool muestra `PrivateKeyEntry` para `ligo-release`. Podés comunicar la huella pública SHA-256 del certificado, sin enviar las contraseñas ni el keystore.

Con la copia independiente comprobada, configurar las variables `TINDER_KEYSTORE_FILE`, `TINDER_KEYSTORE_PASSWORD`, `TINDER_KEY_ALIAS` y `TINDER_KEY_PASSWORD` solo en una sesión local de compilación. Verificar el APK con `apksigner verify --print-certs` y `aapt dump badging`. Conservar `com.example.tinder_universitario` y un versionCode superior a 8. Hacer la prueba sobre un dispositivo sin la instalación productiva. La transición desde la firma Debug de 1.5.1 requiere reinstalar, salvo que se valide una rotación compatible. Los datos sincronizados quedan en Firebase.
