# Bloque 2 — Perfil, carrera, intereses y fotografías

## Alcance y arquitectura

Se trabaja únicamente en `C:\Users\HP\Desktop\tinder_universitario`.
Se conserva Firebase real del Bloque 1, su registro, login, persistencia y logout.
No se implementan descubrimiento, preferencias, likes, matches, chat ni administración.

Después del login, Home muestra Mi perfil. La pantalla permite guardar un borrador, editar los datos, elegir UNA carrera activa, seleccionar/quitar intereses, subir/eliminar fotos, elegir la principal y activar/desactivar al guardar.

- `student_profile.dart`: modelo y criterios mínimos del perfil.
- `profile_service.dart`: lecturas del servidor y transacciones Firestore; preserva fotos recientes al guardar un formulario antiguo.
- `photo_store.dart`: archivos reales en Firebase Storage mediante `putData`, compatible con Web y Android.
- `profile_screen.dart`: formulario responsive, loading, errores, estados y recuperación de selección interrumpida en Android.

Los nuevos usuarios se crean con `isActive=false`. La carga del perfil es de solo lectura: no migra ni desactiva automáticamente cuentas existentes. Los cambios se guardan por acción explícita del usuario.

Guardar parcial requiere seleccionar género; los demás campos mínimos pueden quedar aún vacíos y el perfil se mantiene inactivo. Una fecha informada debe corresponder a una persona de 18 años o más. Activar requiere nombre, apellido, fecha válida, género, una carrera activa, al menos una foto y una principal incluida en las fotos. La activación es voluntaria: completar los datos o subir una foto no activa automáticamente. Desactivar conserva todos los datos. Quitar la última foto desactiva.

Límites: nombres/apellidos 80 caracteres, género seleccionado entre Masculino y Femenino, descripción 500, hasta 5 intereses, hasta 6 fotos de 5 MB en JPG/PNG/WebP. Son límites de validación y seguridad, también aplicados en reglas. La UI muestra solamente opciones activas; si una selección antigua se desactiva en el catálogo, informa que debe sustituirse o quitarse.

## Estructura de datos

```text
Firestore
  users/{uid}
    firstName, lastName, email, birthDate, gender, description
    careerId: String/null
    photoUrls: String[]
    mainPhotoUrl: String/null
    interestIds: String[]
    role, isActive, createdAt, updatedAt
  careers/{careerId}
    name: String
    isActive: Boolean
  interests/{interestId}
    name: String
    isActive: Boolean

Storage (archivos físicos)
  profile_photos/{uid}/{idAleatorio}
```

`birthDate` se guarda como Timestamp UTC de la fecha, sin hora significativa. `updatedAt` usa el timestamp del servidor. El cliente no modifica email, role ni createdAt. No existen semestre, segunda carrera, `user_careers` ni una colección de fotos. Las URLs se guardan en el usuario, nunca bytes/base64.

## Configuración manual antes de probar contra Firebase real

No se han publicado reglas ni cargado catálogos en el proyecto remoto durante esta implementación. Las pruebas de seguridad usan exclusivamente emuladores con un ID demo.

1. En Firebase Console, proyecto `tinder-universitario`, abre Storage y comprueba que existe el bucket `tinder-universitario.firebasestorage.app` ya indicado en `lib/firebase_options.dart`. Si todavía no existe, inicializa Storage. Firebase exige actualmente el plan Blaze para Storage; no se ha cambiado tu facturación. Referencia oficial: https://firebase.google.com/docs/storage/flutter/start
2. Firestore → Rules: reemplaza por el contenido de `firestore.rules` y publica.
3. Storage → Rules: reemplaza por `storage.rules` y publica.
4. Es importante publicar las reglas nuevas antes de probar registros nuevos: las anteriores exigían `isActive=true` y el nuevo registro crea `false`.
5. No es necesario reconfigurar Authentication ni reemplazar `firebase_options.dart`. Si al crear Storage la consola asigna un bucket distinto, actualiza la configuración mediante FlutterFire y el nombre del bucket permitido en `ownPhoto` dentro de `firestore.rules`.

Alternativa CLI para publicar reglas desde esta carpeta (Node instalado):

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
npm ci --prefix tool
node tool/node_modules/firebase-tools/lib/bin/firebase.js login
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --only firestore:rules,storage --project tinder-universitario
```

No se abren permisos globales: solo el propietario lee/escribe su perfil y sus fotos. Los catálogos son de lectura para usuarios autenticados; su carga se realiza desde Console o mediante credenciales de administrador. Firestore protege los campos inmutables, edad, activación, tamaños, tipos, URLs propias y referencias activas del catálogo. Storage limita dueño, tamaño y MIME, y no permite sobrescribir un archivo existente.

## Catálogos de desarrollo

La UI siempre consulta Firestore con `isActive == true`. No escribe ni inventa catálogos.

Opción simple: en Firestore Console crea los documentos definidos en `tool/catalogs.seed.json`. Por ejemplo:

- `careers/sistemas`: `name = Ingeniería de Sistemas`, `isActive = true`.
- `careers/medicina`: `name = Medicina`, `isActive = true`.
- `interests/musica`: `name = Música`, `isActive = true`.
- `interests/deportes`: `name = Deportes`, `isActive = true`.

Los nombres son ejemplos de desarrollo; adapta el JSON a las carreras reales de la universidad antes de cargarlo.

Opción script: `tool/seed_catalogs.mjs` crea solo documentos faltantes, sin sobrescribir los existentes. Usa Firebase Admin con Application Default Credentials. Las credenciales deben mantenerse fuera del proyecto y nunca incluirse en Flutter.

```powershell
# Usa credenciales administrativas autorizadas, guardadas fuera del repositorio.
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta-segura\credenciales-admin.json'
node tool/seed_catalogs.mjs tinder-universitario
Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS
```

Tras cargar datos, pulsa Recargar catálogos en la app. Un catálogo vacío muestra un mensaje y permite guardar el resto del borrador.

## Prueba manual exacta del Bloque 2

1. Ejecuta `flutter run -d chrome --web-port=7357` o `flutter run -d ID_ANDROID` (consulta `flutter devices`).
2. Registra un correo nuevo con 18 años o más. Comprueba en Firestore `users/{uid}.isActive == false`. Verifica que logout/login y recarga conservan el comportamiento del Bloque 1.
3. En Mi perfil escribe el nombre, selecciona Masculino o Femenino y pulsa Guardar perfil. Recarga: el nombre persiste y el perfil sigue incompleto/inactivo.
4. Completa apellido, fecha de nacimiento adulta, género y descripción; selecciona UNA carrera. Verifica que no existe selector de semestre ni segunda carrera.
5. Selecciona dos intereses, guarda, recarga, quita uno y guarda otra vez. Comprueba `careerId` escalar e `interestIds` en Firestore. Sin intereses también se puede guardar/activar.
6. Pulsa Seleccionar y subir imagen y elige un JPG/PNG/WebP. Espera el mensaje de guardado. Comprueba el archivo físico en Storage `profile_photos/{uid}/...` y su URL en `users/{uid}.photoUrls`. La primera foto debe ser la principal.
7. Sube otra imagen. Pulsa Hacer principal sobre ella. Comprueba `mainPhotoUrl` y el indicador Principal.
8. Con todos los campos mínimos, activa el interruptor Activar perfil al guardar y pulsa Guardar perfil. Comprueba `isActive=true`. Recarga: debe mantenerse.
9. Desactiva el interruptor y guarda. Debe quedar `isActive=false` sin perder datos ni fotos. Vuelve a activarlo si quieres continuar la prueba de borrado.
10. Elimina la foto principal y confirma: otra foto debe quedar como principal. Elimina la última: `photoUrls=[]`, `mainPhotoUrl=null`, `isActive=false`; los archivos deben desaparecer de Storage.
11. Prueba fecha menor de 18, imagen mayor de 5 MB, séptima foto y sexto interés. La app debe impedirlos con mensajes. Si el selector comprime una imagen grande por debajo de 5 MB, esa imagen sí se acepta.
12. Desde Console marca una carrera/interés de prueba con `isActive=false`, recarga catálogos y comprueba que ya no se ofrecen como opciones activas. Sustituye o quita la selección antigua si corresponde.
13. Prueba un ancho Web de 360 px y un dispositivo/emulador Android. Comprueba selección de fotos y logout en ambos.

## Pruebas automatizadas reproducibles

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Pruebas de reglas (requieren Node y Java; el ejemplo usa el Java instalado con Android Studio):

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
node tool/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --config firebase.emulators.json --project demo-tinder-universitario --only firestore,storage "node --test tool/rules.test.mjs"
```

`firebase.emulators.json` es independiente de la configuración real. Los mensajes PERMISSION_DENIED en las pruebas negativas son esperados. Los tests no leen ni modifican el proyecto real.

## Consistencia y límites prácticos

Firestore y Storage no comparten transacciones. Para borrar, primero se actualizan las URLs y la principal en Firestore; después se borra el archivo. Si Storage falla, aparece un botón de reintento y la referencia ya no queda rota en el perfil. El reintento pendiente se conserva mientras esté abierta esa pantalla. Si se cierra antes, un archivo huérfano puede requerir limpieza en Storage Console. También puede quedar un archivo sin referencia si se pierde toda conexión entre subida y escritura del documento. No se hacen borrados automáticos de archivos de otras sesiones.

Las URLs de descarga de Firebase incluyen tokens: quien reciba una URL puede ver esa foto. La app guarda las URLs solo en el perfil privado del dueño. Las reglas validan bucket y ruta propios, pero Firestore no puede probar por sí solo la existencia física de un archivo en Storage; el flujo normal obtiene las URLs del SDK después de subir. Tampoco las reglas verifican el contenido real más allá del MIME; el cliente comprueba la firma JPG/PNG/WebP.

La edad declarada se valida contra la fecha local en la app y UTC en las reglas. No constituye verificación documental. La app requiere conexión para confirmar guardados; no anuncia éxito basándose únicamente en caché.

## Archivos creados

- lib/features/profile/student_profile.dart
- lib/features/profile/profile_service.dart
- lib/features/profile/photo_store.dart
- lib/features/profile/profile_screen.dart
- test/profile_test.dart
- storage.rules
- firebase.emulators.json
- tool/catalogs.seed.json
- tool/seed_catalogs.mjs
- tool/rules.test.mjs
- tool/package.json y tool/package-lock.json
- README_BLOQUE_2.md

## Archivos modificados

- lib/features/auth/auth_service.dart: nuevos usuarios inactivos y errores de Storage.
- lib/features/auth/auth_gate.dart: pasa UID al inicio.
- lib/features/home/home_screen.dart: acceso al perfil, conserva LogoutButton.
- test/auth_test.dart: prueba de arranque determinista ahora que Firebase está configurado.
- pubspec.yaml y pubspec.lock: Storage, selector y doble de Firestore para tests.
- firestore.rules, firebase.json: reglas del perfil, catálogos y referencia a Storage Rules; se conserva la sección FlutterFire.
- analysis_options.yaml: excluye dependencias Node de las herramientas del análisis Dart.
- .gitignore: herramientas generadas y credenciales administrativas.
- Flutter actualiza sus registradores/metadatos de plugins generados durante la instalación/compilación.

No se modificaron lib/firebase_options.dart ni los identificadores Firebase, ni se reconstruyó el proyecto.

## Resultados de validación

- `flutter pub get`: correcto.
- `flutter analyze`: **No issues found**.
- `flutter test`: **28 pruebas aprobadas** (incluye las 5 del Bloque 1 y 23 de perfil/género).
- Reglas en emuladores oficiales Firestore/Storage: **14 pruebas aprobadas**.
- `flutter build web`: correcto; salida en `build/web`.
- La prueba manual contra Storage/Firestore reales queda pendiente de publicar reglas, habilitar Storage y cargar catálogos.
- `flutter build apk --debug`: correcto; APK en `build/app/outputs/flutter-apk/app-debug.apk`. El primer intento agotó recursos de Windows; el reintento terminó bien limitando Gradle solo para ese proceso, sin cambiar la configuración permanente del proyecto:

```powershell
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dorg.gradle.jvmargs=-Xmx2048m'
flutter build apk --debug
Remove-Item Env:GRADLE_OPTS
```

Gradle emitió el aviso de compatibilidad futura Kotlin de los plugins Firebase; no impidió la compilación actual.


## Corrección de género (antes del Bloque 3)

El campo libre fue sustituido por DropdownButtonFormField. Solo ofrece Masculino y Femenino y la selección es obligatoria para guardar el formulario. ProfileGender, en lib/features/profile/student_profile.dart, centraliza los valores persistidos y sus etiquetas. Firestore recibe exactamente `masculino` o `femenino`, sin normalizar automáticamente valores antiguos. El servicio también valida para impedir valores inválidos fuera del formulario.

Los valores antiguos distintos (incluidos mayúsculas, errores y espacios) se cargan sin selección válida. El perfil se considera incompleto y el interruptor de activación queda deshabilitado hasta elegir una opción y completar los demás requisitos. La lectura no modifica gender, isActive ni updatedAt; se eliminó normalizeLegacyProfile, que antes escribía automáticamente al cargar.

Las reglas tienen validGender() con los mismos dos valores. El alta de Authentication conserva su documento inicial con gender vacío e inactivo. En actualizaciones, un género nuevo solo puede ser uno de los dos válidos. Para mantener la compatibilidad de las fotos y borradores, un género vacío o legado puede conservarse sin cambios solo si el perfil queda inactivo. Nunca permite activación con un género inválido. No hay migración ni deploy automático.

Comando para publicar exclusivamente las reglas Firestore cuando corresponda:

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:rules --project tinder-universitario
```

Ese comando no publica Storage Rules ni modifica catálogos o perfiles. Cambia las reglas aplicables a futuras solicitudes; no reescribe documentos existentes.

