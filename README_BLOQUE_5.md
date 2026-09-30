# Bloque 5 · Sprint 3 · Chat e historial

Fecha de validación: 29 de septiembre de 2026.
Proyecto: Tinder Universitario. Base revisada: commit 57c3263.

HU-13 permite conversar por texto entre los dos participantes de un match activo.
HU-14 recupera el historial persistido y recibe mensajes en tiempo real.
Implementación local pendiente de revisión y despliegue. No se ejecutaron deploy, commit, push, seeds ni operaciones sobre Firebase remoto.

## Archivos

Creado | Responsabilidad
--- | ---
`lib/features/chat/chat_message.dart` | Modelo, normalización, límites y excepción de validación.
`lib/features/chat/chat_service.dart` | Lectura del match, historial por snapshots y envío.
`lib/features/chat/chat_screen.dart` | Cabecera pública, historial, burbujas y formulario.
`test/chat_test.dart` | 23 pruebas nuevas de modelo, servicio y widgets.
`README_BLOQUE_5.md` | Diseño, evidencia y guía de QA.

Modificado | Cambio
--- | ---
`lib/features/matches/matches_screen.dart` | Tap/click abre ChatScreen; permite inyectar ChatService en tests.
`firestore.rules` | Permisos específicos de la subcolección messages; límites y validación.
`tool/rules.test.mjs` | 24 pruebas nuevas de reglas usando los emuladores existentes.

Sin cambios en Auth, perfiles, fotografías, preferencias, Discovery, creación de swipes/matches, Storage Rules, Firebase options, dependencias o configuración de índices.

## Modelo exacto

Ruta: `matches/{matchId}/messages/{messageId}`. ID automático de Firestore.

```text
senderId: string      // UID del remitente autenticado
text: string          // texto normalizado
createdAt: timestamp  // FieldValue.serverTimestamp()
```

Son exactamente tres campos obligatorios. El ID documental y el método isOwn del modelo Dart no se almacenan como campos.
No se duplican email, nombre, foto, receiverId ni perfil. Los participantes provienen del match padre.

## Longitud y normalización

`ChatLimits.maxTextLength = 1000`; `ChatLimits.historyLimit = 50`.
Las reglas mantienen los valores correspondientes en `maxMessageLength()` y `maxChatHistory()`.
Si cambian, deben actualizarse en ambas plataformas.

Se aplica `trim()` antes de comprobar vacío o longitud y antes de escribir. Se conservan espacios y saltos de línea internos.
El límite cuenta unidades UTF-16, igual que `String.length` de Dart y el comportamiento verificado de Rules en el emulador.
Ejemplos: 1000 letras ASCII o acentuadas, o 500 emojis simples fuera del plano básico. Algunos emojis compuestos consumen más unidades.
El contador del formulario usa el mismo cálculo. Si se supera el límite, se muestra el error al enviar y se conserva el borrador.

Las pruebas detectaron que Rules trim() no elimina todos los espacios Unicode que elimina Dart.
`trimmedText()` rechaza esos espacios en los extremos, incluidos NBSP, separadores Unicode y BOM.
Se verificó que mensajes vacíos o formados solamente por esos espacios no se aceptan.

## Envío

1. El formulario activa una guardia síncrona; deshabilita el botón y la edición durante el envío.
2. ChatService normaliza y valida el texto.
3. Lee el match desde el servidor y valida su existencia, dos participantes, ID canónico, pertenencia del usuario y estado activo.
4. Crea un documento en messages con los tres campos y timestamp del servidor.
5. Las reglas vuelven a comprobar los permisos al escribir: si el match cambió entre lectura y escritura, el envío se rechaza.
6. Se limpia el borrador únicamente después de confirmación satisfactoria. Ante error se conserva y se habilita el reintento.

No se actualiza el match, no se guarda lastMessage y no se modifica otra colección durante el envío.
La guardia evita doble clic mientras una operación está en curso; no deduplica mensajes intencionalmente iguales enviados en operaciones separadas.

## Tiempo real, historial y orden

```dart
.collection('matches')
.doc(matchId)
.collection('messages')
.orderBy('createdAt', descending: true)
.limit(ChatLimits.historyLimit)
.snapshots()
```

El servicio invierte localmente el resultado para devolverlo en ASC.
La lista visual usa reverse con acceso inverso a esa lista para anclarse al mensaje más reciente, manteniendo el más antiguo arriba.
Empates de timestamp conservan el orden de la consulta, cuyo desempate predeterminado es el ID documental.
No hay polling ni consultas ilimitadas. Las reglas también rechazan listados sin límite o con límite mayor a 50.
Un segundo snapshot del match actualiza el estado activo del formulario. Los StreamBuilder cancelan sus suscripciones al salir.

Los mensajes confirmados se guardan en Firestore y se consultan nuevamente al reabrir el chat o volver a iniciar sesión.
Un timestamp local aún pendiente se representa con null y se muestra como «Enviando…» hasta su resolución.
No se inventa una fecha de cliente para almacenarla.

Se usan índices automáticos de colección sobre createdAt. No se añadió un índice compuesto ni una consulta collectionGroup.
Esto presupone que no se haya desactivado manualmente esa indexación en Firebase remoto; no se inspeccionó el proyecto remoto.
Referencia: [índices automáticos de Firestore](https://firebase.google.com/docs/firestore/query-data/index-overview#automatic_indexes).

## Seguridad y match inactivo

- GET: exclusivamente participantes de un match padre existente y válido.
- LIST / listeners de consulta: mismos participantes, con límite máximo de 50.
- CREATE: participante autenticado, match activo, senderId propio, texto válido, timestamp igual a request.time y campos exactos.
- UPDATE y DELETE: siempre denegados, incluso para el autor.
- Terceros y anónimos no pueden leer, listar, escuchar ni escribir.
- Padres inexistentes, inválidos o con más de dos participantes no habilitan el chat.

La política adoptada es conservar el historial privado legible para ambos participantes al desactivar un match.
Un match inactivo bloquea nuevos mensajes en formulario, servicio y reglas.
La simulación de inactividad se realizó exclusivamente con fixtures del emulador. El cliente sigue sin permiso para modificar matches.
No se implementó Unmatch.

Las reglas existentes de matches —create mediante LIKE recíproco y atómico, lectura por participantes, update/delete denegados— permanecen iguales.
También permanecen las restricciones de users, preferences, discoveryCards y Storage.

## Pantalla y navegación

Mis Matches → tap/click → ChatScreen → botón Atrás → Mis Matches.
La navegación Inicio / Descubrir / Matches / Perfil y el acceso a Preferencias no se modificaron.
La cabecera reutiliza solamente la ficha pública obtenida por MatchesService. No consulta el perfil privado ajeno.
Si la ficha o fotografía no está disponible, muestra un reemplazo; la existencia del chat depende del match.

Se muestran nombre, foto disponible, texto y fecha/hora local sencilla. No se exponen email, UID, birthDate ni preferencias privadas.
Burbujas propias a la derecha, recibidas a la izquierda. El estado vacío muestra «Aún no hay mensajes. ¡Saluda!».
Hay loading, error comprensible con Reintentar y estado Enviando.
La prueba de widget a 360 × 800 incluye texto largo y reducción de espacio por teclado, sin overflow.

## Pruebas nuevas

Flutter: 23 casos que cubren mensaje válido y esquema mínimo; vacío; espacios ASCII; espacios Unicode; longitud; trim;
límite Unicode; orden cronológico; ventana de 50 que se actualiza; autoría; timestamp pendiente;
match inactivo; match inexistente/ajeno; recuperación por nueva instancia;
estado vacío y privacidad; error con borrador conservado y reintento; doble envío;
360 px, alineación, orden visual y teclado; desactivación en vivo; recepción en vivo;
navegación ida/vuelta; recuperación de error del listener; loading y acceso no disponible.

Rules: 24 casos nuevos. A y B pueden enviar; terceros no pueden enviar/get/list/listen; anónimos rechazados;
participantes pueden leer; senderId falso; vacío; espacios/trim; exceso de longitud;
límite exacto ASCII/acentos/emojis; campos extra; timestamp inválido; campos faltantes y tipos inválidos;
UPDATE; DELETE; padre ausente; match inactivo; padre inválido; consulta acotada;
recepción en vivo y recuperación con otro contexto autenticado; listener del historial inactivo.

Los tests Flutter usan FakeFirebaseFirestore inyectado, sin inicializar Firebase real.
La suite Rules fija `demo-tinder-universitario`, Firestore 127.0.0.1:8088 y Storage 127.0.0.1:9198.
Los cuatro tests de herramientas inyectan fetch falso; no ejecutan seeds ni hacen POST reales.

## Resultados finales

Verificación | Resultado
--- | ---
`flutter pub get` | PASS; sin cambios de dependencias.
`flutter analyze` | PASS; No issues found.
`flutter test` | PASS; 85/85: 62 anteriores + 23 nuevos.
`Firestore / Storage Rules` | PASS; 64/64: 40 anteriores + 24 nuevos.
`node --test tool/seed_catalogs_cli.test.mjs` | PASS; 4/4, transporte simulado.
`flutter build web` | PASS; build/web, 66,8 s de compilación.
`flutter build apk --debug` | PASS; build/app/outputs/flutter-apk/app-debug.apk, 19,1 s de Gradle.
`git diff --check` | PASS; sin errores de whitespace.

Comandos de regresión (PowerShell desde la raíz del proyecto):

```powershell
flutter pub get
flutter analyze
flutter test
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --config firebase.emulators.json --project demo-tinder-universitario --only firestore,storage "node --test tool/rules.test.mjs"
node --test tool/seed_catalogs_cli.test.mjs
flutter build web
$env:GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dorg.gradle.jvmargs=-Xmx2048m'
flutter build apk --debug
git diff --check
```

## Advertencias y límites

- pub get informa nueve paquetes con versiones más nuevas incompatibles con las restricciones actuales. No se actualizaron.
- Los PERMISSION_DENIED del log del emulador corresponden a casos negativos esperados; el resumen final es 64 PASS / 0 FAIL.
- Git avisa sobre conversión LF/CRLF según su configuración existente.
- Web: Wasm dry run correcto y avisos informativos de reducción de fuentes. Android: firebase_auth, firebase_core y firebase_storage aplican Kotlin Gradle Plugin; Flutter avisa de futura incompatibilidad y recomienda Built-in Kotlin. El build actual pasa. No se modificó Gradle ni se actualizaron plugins fuera del bloque.
- No se implementó cargar mensajes anteriores a los últimos 50. Permanecen almacenados; la vista solo muestra esa ventana.
- El borrador se conserva en memoria ante error; no se persiste al cerrar la pantalla o recargar.
- El envío requiere confirmar el match con el servidor. Si se pierde conexión durante una escritura, puede permanecer pendiente hasta que el SDK resuelva la operación. No se añaden reintentos automáticos ni timeouts que arriesguen duplicarla.
- No hay rate limiting, deduplicación entre dispositivos, moderación ni cifrado de extremo a extremo en este bloque.
- El nombre/foto de cabecera es la ficha pública cargada al abrir desde Matches, sin sincronización adicional del perfil.
- No se hicieron pruebas de chat contra cuentas reales ni QA manual en un teléfono; se verificaron widgets, emuladores y compilaciones.
- No se implementaron HU-15/16/17, notificaciones, FCM, Functions, leído, typing, última conexión, multimedia ni ubicación.

## Despliegue de reglas: comando para revisión, NO ejecutado

Después de aprobar los cambios, desde PowerShell:

```powershell
Set-Location 'C:\Users\HP\Desktop\tinder_universitario'
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js deploy --project tinder-universitario --only firestore:rules
```

Utiliza firebase.json y despliega únicamente Firestore Rules. Requiere una sesión de Firebase CLI autorizada.
No es un despliegue de la app Web ni de Storage. El chat remoto seguirá denegado por las reglas anteriores hasta que se apruebe y ejecute este paso.

## QA manual real con dos usuarios: pasos pendientes para el usuario

Estos pasos sí generan mensajes remotos cuando se ejecuten. No se ejecutaron durante este trabajo.

1. Revisar y aprobar los archivos y desplegar las reglas con el comando anterior.
2. Ejecutar desde la raíz:

   ```powershell
   flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8585
   ```

3. Abrir http://127.0.0.1:8585 en dos perfiles separados de navegador (o ventana normal e incógnito). Iniciar sesión con A y B existentes.
4. Usar un match activo existente entre A y B. Si no existe, establecer compatibilidad recíproca y realizar LIKE en ambas cuentas desde Discovery; no crear el match manualmente en la consola.
5. En ambas sesiones, entrar en Matches y pulsar la coincidencia. Verificar nombre/foto o reemplazo, botón Atrás y estado vacío si corresponde.
6. Desde A escribir «  Hola B  » y pulsar Enviar. Comprobar texto sin espacios en los extremos, burbuja derecha en A e izquierda en B sin recargar.
7. Responder desde B. Comprobar orden, actualización instantánea y fecha/hora.
8. Probar vacío, solo espacios y 1001 letras: deben rechazarse sin crear mensajes. Comprobar que 1000 letras se aceptan.
9. Hacer doble clic rápido en Enviar: debe quedar un único mensaje de esa operación.
10. Cerrar y reabrir el chat, recargar y cerrar/iniciar sesión: los mensajes confirmados deben recuperarse.
11. Desconectar Internet antes de enviar y observar el error o estado pendiente del SDK. El borrador no debe desaparecer sin confirmación. Restablecer la conexión antes de reintentar.
12. Probar ancho 360 px y teclado; volver a Matches con Atrás y recorrer Inicio, Descubrir, Perfil y Preferencias.
13. Opcionalmente abrir el APK debug generado en Android y repetir intercambio entre Web y Android.
14. Para terceros, match inactivo, UPDATE/DELETE y límite de 50, usar las pruebas automatizadas del emulador; no alterar matches reales para simular esos estados.

Firebase remoto, Authentication, careers, interests y Supabase no fueron modificados. Sin commit ni push.
