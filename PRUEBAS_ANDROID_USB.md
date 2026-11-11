# Android físico por USB — demo aislado

La aplicación de pruebas se llama **Tinder Demo Local**, paquete `com.example.tinder_universitario.demo`, separado de la variante original. Se utiliza exclusivamente `lib/main_demo_android.dart`, flavor `demo` y `TINDER_DEMO=true`. No iniciar `lib/main.dart` ni el flavor `standard` para estas pruebas.

## Aislamiento comprobado

- Teléfono Android 14/API 34, ARM64. ADB detecta el ID `ID_DEL_DISPOSITIVO` (obtener el valor local con `adb devices`; no versionar el serial físico).
- Modo avión activo, Wi-Fi deshabilitado y `Active default network: none`. El valor guardado `mobile_data=1` no implica una red activa en modo avión; se comprobó el estado efectivo de conectividad.
- Auth `127.0.0.1:9099`, Firestore `127.0.0.1:8088`, Storage `127.0.0.1:9198` y backend privado `127.0.0.1:7360`. El cliente usa el proxy `http://127.0.0.1:7357/__demo/api/`; por eso también necesita 7357. No hace falta exponer el hub o la consola de emuladores al teléfono.
- El proyecto y los recursos nativos empaquetados son ficticios: `demo-tinder-universitario`. El arranque comprueba flavor y proyecto antes de mostrar la aplicación; los servicios se configuran antes de AuthGate. No importa las opciones de Firebase reales.
- Las tres llamadas `useAuthEmulator`, `useFirestoreEmulator` y `useStorageEmulator` utilizan **`automaticHostMapping: false`**. Se corrigió una conversión automática de FlutterFire a `10.0.2.2`, que es incorrecta para teléfono físico y `adb reverse`.
- La configuración de red del flavor demo permite HTTP solamente para `127.0.0.1`. No es un firewall para todo HTTPS: **mantener modo avión y Wi-Fi apagado durante estas pruebas**. Ver [configuración oficial de Android](https://developer.android.com/privacy-and-security/security-config).
- APK con minSdk 24, targetSdk 36 y binarios ARM64: compatible para iniciar en API 34. Declara INTERNET y RECORD_AUDIO. El micrófono solicita permiso al grabar, no se concedió por ADB; la grabación es con la app en primer plano. No se agrega acceso amplio a archivos o fotos del teléfono.

## Repetir la conexión

Desde `C:\Users\HP\Desktop\tinder_universitario_pruebas`, con emuladores/backend/servidor demo en funcionamiento, cable USB conectado y depuración USB autorizada:

```powershell
$adb = 'C:/Users/HP/AppData/Local/Android/Sdk/platform-tools/adb.exe'
$device = 'ID_DEL_DISPOSITIVO'
foreach ($port in 7357,7360,9099,8088,9198) {
    & $adb -s $device reverse "tcp:$port" "tcp:$port"
}
& $adb -s $device reverse --list
node tool/demo/android-usb-check.mjs
flutter run --debug --flavor demo --target lib/main_demo_android.dart --dart-define=TINDER_DEMO=true --no-pub -d $device
```

Los túneles pueden perderse al desconectar/reiniciar el teléfono o ADB. Si falla el acceso, volver a configurarlos; no cambiar los endpoints por direcciones de producción. Mantener la PC y los servicios encendidos. La comprobación de salud es de solo lectura y no restablece estados administrativos de cuentas modificadas en pruebas manuales.

Si Android bloquea la instalación con `INSTALL_FAILED_USER_RESTRICTED`, habilitar **Instalar vía USB** y aceptar la instalación en el teléfono. No desinstalar aplicaciones anteriores ni borrar sus datos para resolverlo. En este caso se autorizó manualmente esa opción y se reintentó.

## Cuentas y prueba manual

Contraseña ficticia común: **DemoTinder2026!**.

| Cuenta | Correo |
| --- | --- |
| Ana, aprobada con perfil y match | ana.manual@demo.test |
| Bob, aprobado con perfil y match | bob.manual@demo.test |
| Administrador | admin@demo.test |
| Superadministrador | superadmin@demo.test |

Entrar como Ana y comprobar perfil, fotografías, Descubrir, match con Bob y chat. Para probar voz, permitir micrófono **al usar la aplicación**, grabar, escuchar la previa y enviar exclusivamente una nota de prueba. La instalación/arranque por sí solos no prueban captura real ni audibilidad. No usar carnets ni archivos personales reales.

## Evidencia de esta ejecución

- Salud de servicios y autorización: `audit-android-usb-health.json`. Auth, Firestore, Storage, backend directo y proxy respondieron; lecturas de fotografías sin sesión denegadas.
- Cambio de código de aplicación limitado a `lib/main_demo_android.dart`: desactivar la conversión automática de localhost. No se cambiaron reglas, credenciales reales ni datos.
- Análisis y regresiones del cambio: `audit-android-usb-analyze-final.log`, `audit-android-usb-flutter-tests.log`.
- Se renombró la copia de comparación antigua `build/phase5-original-profile_screen.dart` a `.dart.txt`: el analizador estaba interpretando ese respaldo como fuente con imports inexistentes. Se conserva su contenido; no se alteró la exclusión del analizador para ocultar errores.
- Comprobación runtime preparada con el inspector oficial de Flutter: `tool/demo/android-vm-check.mjs`; solo inspecciona proyecto, host y tipos de pantalla, sin guardar campos de entrada ni credenciales. La dirección temporal del depurador se guarda en `build/android-usb-vm.txt`, nunca se publica.
- Resultado final: **APK corregido compilado, instalado y ejecutado en el teléfono físico**. El inspector mostró `AuthGate` y `LoginScreen`, proyecto `demo-tinder-universitario` y host efectivo de Firestore `127.0.0.1:8088`; `audit-android-usb-runtime.json`. Android confirmó la actividad demo reanudada, versión 1.0.0 y actualización del paquete.
- Los cinco servicios respondieron desde el propio proceso Android a través de USB: Auth 9099 y Firestore 8088 devolvieron 200 en sus raíces; backend 7360 y proxy 7357 devolvieron 401 sin sesión; Storage 9198 devolvió 403 al intentar consultar una fotografía privada sin sesión. Ese rechazo es el resultado esperado, no se relajaron reglas. Evidencia: `audit-android-usb-installation.json`, con SHA-256 del APK instalado, y el comprobador runtime.
- `flutter analyze` final sin observaciones y **271 pruebas Flutter aprobadas**, cero fallidas. Las compilaciones mostraron la advertencia ya conocida sobre la futura migración de plugins a Built-in Kotlin; no impidió compilar o iniciar esta versión.
- La prueba en teléfono verificó instalación, arranque, configuración runtime y transporte local. **No verificó todavía un inicio de sesión interactivo, captura física de voz, audibilidad ni todos los flujos de chat en Android**. Realizar esos pasos manuales con las cuentas ficticias indicadas.

No se hizo commit, push, merge, reset ni deploy; no se modificó main ni el proyecto original. Las pruebas anteriores del AVD no sustituyen esta comprobación en el dispositivo físico.
