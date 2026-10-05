# Verificación real del correo con Firebase Authentication

Proyecto: `C:\Users\HP\Desktop\tinder_universitario`.
Firebase: `tinder-universitario`. Trabajo y validación locales, sin deploy.

## 1. Flujo anterior

AuthGate escuchaba `authStateChanges()`. Una sesión autenticada pasaba por ProfileGate,
que inicializaba `users/{uid}` de forma idempotente y abría HomeScreen. No se exigía
que Firebase Auth marcara el correo como verificado.

## 2. Flujo nuevo

```text
Sin sesión → Login / Registro
Con sesión, emailVerified false → Verifica tu correo
Con sesión, emailVerified true → inicialización/recuperación del perfil → Inicio
```

La barrera se implementa dentro del ProfileGate existente bajo AuthGate. Se sigue
intentando crear el documento inicial en segundo plano como antes, pero ningún resultado
de Firestore permite saltarse la verificación. Si falta el documento o falló su creación,
el flujo previo de Completar registro/Reintentar continúa disponible después de verificar.

Registro crea la cuenta con `createUserWithEmailAndPassword` y solicita automáticamente
`sendEmailVerification()`. El envío y la inicialización del perfil son independientes:
un fallo al enviar no elimina la cuenta ni se presenta como contraseña/registro inválido.
La pantalla muestra ese error y permite reenviar sin registrar otra cuenta.

Login correcto de una cuenta no verificada es válido: abre la pantalla de verificación.
Login y reapertura no envían otro correo automáticamente; el usuario puede solicitarlo.
En cada reapertura se evalúa el estado de Firebase, sin guardar un permiso local de acceso.

## 3. Archivos creados

- `lib/features/auth/email_verification_screen.dart`
- `test/email_verification_test.dart`
- `README_VERIFICACION_EMAIL.md`

## 4. Archivos modificados en este bloque

- `lib/features/auth/auth_service.dart`: envío, refresco, estado de entrega/cooldown,
  mensajes de error y stream `userChanges()`.
- `lib/features/auth/auth_gate.dart`: barrera antes de HomeScreen y reevaluación del usuario actual.
- `test/auth_service_test.dart`: mocks con currentUser/userChanges/emailVerified/envío;
  la regresión de entrada normal usa explícitamente una cuenta verificada.

Se preservaron los cambios no confirmados del rediseño anterior. No son cambios nuevos
de este bloque. No se modificaron AuthForm, Login, Registro, Home, tema ni componentes
visuales existentes, servicios de perfil/chat/discovery, reglas, índices o configuración Firebase.

## 5. Fuente de verdad: emailVerified

Solo se consulta `FirebaseAuth.currentUser.emailVerified`. No se agrega `emailVerified`
a Firestore ni se utilizan booleanos de perfil, IDs especiales o almacenamiento local
para autorizar el acceso. Firebase marca el correo tras usar su enlace de verificación.

La pantalla usa AuthCard, AppColors, el tema y AppNotice del rediseño. Incluye email actual,
icono, instrucciones, Ya verifiqué mi correo, Reenviar correo y Cerrar sesión.
Solo muestra «Enviamos un enlace de verificación a:» después de que Firebase acepte el envío
en esta sesión. Para cuentas antiguas o tras reiniciar, explica que se puede reenviar sin
afirmar que acaba de enviarse uno. Aceptar el envío no garantiza su entrega en la bandeja.

## 6. Refresco mediante reload()

Al pulsar Ya verifiqué mi correo:

1. Se obtiene el usuario autenticado.
2. Se espera `user.reload()`.
3. Se vuelve a obtener `FirebaseAuth.currentUser`.
4. Se comprueba que sigue siendo la misma cuenta y se lee el nuevo `emailVerified`.
5. Si es false se muestra «Tu correo todavía no ha sido verificado.».
6. Si es true, ProfileGate vuelve a evaluar el usuario actual y permite el flujo normal.

`userChanges()` incluye los eventos de reload, además de login/logout. El callback del
botón también reevalúa currentUser; nunca almacena un booleano alternativo de autorización.
Una sesión nula/sustituida o un error al recargar no se interpreta como verificación válida.
No hay polling, deep links ni temporizador consultando Firebase.

## 7. Reenvío y cooldown

AuthService comparte estado de envío entre registro y pantalla mediante ChangeNotifier.
Así un reenvío no compite con el correo automático. Los botones quedan deshabilitados
mientras se envía/comprueba/cierra sesión y se muestra progreso.

Tras un envío correcto se aplica un cooldown de 30 segundos, visible en pantalla.
También se aplica ante `too-many-requests`; Firebase puede exigir una espera mayor,
por eso el mensaje indica esperar unos minutos. Un fallo de red permite reintentar.

La pantalla usa un único Timer de un segundo solo durante el cooldown, para repintar
el tiempo restante. Se cancela al salir. El plazo se calcula con tiempo absoluto,
sin persistencia ni backend adicional. Logout limpia el estado; respuestas de envío
que llegan tarde no se aplican a otra sesión.

Este cooldown evita doble clic/reintentos inmediatos del cliente, no sustituye los límites
de Firebase ni es un sistema de prevención de abuso entre dispositivos o reinicios.

## 8. Cuentas existentes

Todas las cuentas con `emailVerified == false`, incluidas las de prueba con perfil completo
o activo, verán la nueva pantalla. Deben poder abrir su correo y usar el enlace.
No hay excepciones por UID, migraciones, borrados ni cambios automáticos en perfiles.
Una cuenta ya verificada conserva el flujo anterior.

## 9. Qué demuestra y qué no

**La verificación confirma que el usuario tiene acceso al correo registrado. No confirma
por sí sola que el usuario pertenezca a Universidad del Valle.**

No se limita el dominio ni se añade integración institucional. La UI comunica esta distinción.

La barrera de este bloque está en la aplicación. Se analizaron y conservaron firestore.rules
y storage.rules: no se agregó `request.auth.token.email_verified`. Por tanto un cliente
modificado o una versión anterior no obtiene una nueva restricción de backend por este cambio;
las reglas existentes siguen aplicándose igual. Tampoco se ocultan/desactivan automáticamente
las fichas existentes de cuentas no verificadas, porque eso cambiaría datos/Discovery fuera
del alcance. Una futura exigencia de seguridad en servidor requiere su propio diseño y pruebas.

## 10. Tests agregados y modificados

26 tests nuevos: sesión nula, restaurada/no verificada, verificada, reapertura, registro,
documento único/esquema, login, botón comprobar, estado false, nuevo objeto User tras
reload, eventos userChanges, reenvío/cooldown, doble clic, envío automático concurrente,
errores network-request-failed/too-many-requests/user-disabled/desconocido, recuperación
de envío fallido, error de reload, logout/error, sesión nula/sustituida, respuesta tardía,
sesión invalidada durante el envío, recuperación de perfil y layout a 360×800/1280×900 con email largo.

Se actualizó el fake de Auth de los tests anteriores y el escenario de entrada verificada.
No se eliminaron tests. Las pruebas usan Firebase simulado, Firestore en memoria y
emuladores locales; no envían correos reales ni modifican datos remotos.

## 11–15. Resultados de validación

| Comprobación | Resultado |
| --- | --- |
| flutter pub get | Correcto, sin cambios de dependencias |
| flutter analyze | No issues found |
| flutter test | 170/170: 144 anteriores + 26 nuevos |
| Rules Firestore/Storage en emuladores | 114/114 |
| Herramientas de catálogos, sin seed remoto | 4/4 |
| flutter build web | Correcto: `build/web` (71,0 s) |
| flutter build apk --debug | Correcto: `build/app/outputs/flutter-apk/app-debug.apk` (20,2 s) |
| git diff --check | Correcto |

Comandos de validación ejecutados:

```powershell
flutter pub get
flutter analyze
flutter test
node --test tool/seed_catalogs_cli.test.mjs
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --config firebase.emulators.json --project demo-tinder-universitario --only firestore,storage "node --test tool/rules.test.mjs"
flutter build web
$env:GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dorg.gradle.jvmargs=-Xmx2048m'
flutter build apk --debug
git diff --check
```

## 16. Limitaciones y referencias

Advertencias no bloqueantes: pub informa 12 versiones nuevas fuera de las restricciones
actuales; Android informa del uso de Kotlin Gradle Plugin por firebase_auth, firebase_core
y firebase_storage ante versiones futuras de Flutter. No se actualizaron dependencias.
Web informa del dry run Wasm y reducción de fuentes; Git avisa de LF→CRLF.

No se realizó envío/recepción real de correo porque se pidió no operar sobre Firebase real.
La entrega depende de Firebase, sus cuotas, la plantilla y el proveedor de correo/spam.
No hay regreso automático a la app desde el enlace: volver y pulsar Ya verifiqué mi correo.
El estado cacheado puede seguir siendo false hasta reload; eso mantiene la barrera.
No se agregó refresco forzado de token, pues las reglas no consumen una nueva claim.

Se usa el enlace manejado por Firebase por defecto, sin ActionCodeSettings, dominios
personalizados ni cambios de Hosting. No hace falta desplegar reglas para este bloque.
No se modificó la persistencia Web LOCAL ni la persistencia nativa existente.

Referencias oficiales consultadas:

- [Administrar usuarios y enviar verificación](https://firebase.google.com/docs/auth/flutter/manage-users)
- [Streams userChanges, reload y persistencia](https://firebase.google.com/docs/auth/flutter/start)

## 17. Checklist manual con Firebase real — lo ejecuta el usuario

1. En Firebase Console seleccionar **tinder-universitario**. Email/Password ya debe estar
   habilitado. Opcionalmente revisar Authentication → Templates → Email address verification
   (remitente, idioma y texto). No crear claves de servicio ni cambiar reglas.
2. Desde PowerShell:

   ```powershell
   Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
   flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8585
   ```

   Abrir `http://127.0.0.1:8585` en el navegador. Para Android, conectar el dispositivo,
   consultar `flutter devices` y ejecutar `flutter run -d ID_DEL_DISPOSITIVO`.
3. Registrar una cuenta de prueba nueva con un correo real al que tengas acceso y fecha
   de nacimiento de adulto. Debe aparecer Verifica tu correo, nunca Inicio.
4. En Console confirmar una sola cuenta en Authentication y un solo `users/{uid}` con
   el esquema anterior. No debe existir un campo Firestore emailVerified.
5. Antes de abrir el email, pulsar Ya verifiqué mi correo: permanece y muestra el aviso.
   Recargar/cerrar/reabrir la app: continúa bloqueada para uso normal.
6. Esperar el cooldown, pulsar Reenviar correo y comprobar feedback. Durante envío y
   cooldown no se admiten pulsaciones adicionales. Revisar también spam/promociones.
7. Abrir el enlace de verificación recibido y completar la página manejada por Firebase.
   Volver a la app y pulsar Ya verifiqué mi correo. Debe entrar al flujo normal; si hubo
   un fallo previo de perfil, usar el formulario/reintento existente para completarlo.
8. Cerrar sesión e iniciar nuevamente con esa cuenta: entra normalmente, sin otra cuenta
   ni otro documento. El email y el UID originales se conservan.
9. Con una cuenta antigua no verificada, iniciar sesión: debe quedar en verificación.
   Enviar enlace desde Reenviar correo, verificar y comprobar que su perfil se conserva.
10. Probar Cerrar sesión desde verificación: regresa a Login. Comprobar mensaje recuperable
    sin conexión, restaurar la red y reintentar. No provocar spam intencional para probar cuotas;
    too-many-requests ya está cubierto con mocks.

No se ejecutaron deploy, commit, push, seeds, migraciones ni modificaciones de Firebase real.
