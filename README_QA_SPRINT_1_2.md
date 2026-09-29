# QA final — Sprint 1 y Sprint 2

Fecha: 28 de septiembre de 2026, America/La_Paz (logs UTC del 29/09).
Proyecto: `C:\Users\HP\Desktop\tinder_universitario`.
Base Git revisada: `64d8bce` — Sprint 2 - Auth, perfiles, discovery, swipes y matches.
El repositorio estaba limpio al comenzar. No se hizo commit ni push.

## 1. Objetivo del QA

Comprobar HU-01 a HU-12 con evidencia ejecutable y revisión del código; corregir
la exposición de fecha de nacimiento en Discovery y Mis Matches sin ampliar Sprint 3.

## 2. Alcance

Se revisaron los servicios, modelos, formularios, navegación y tests de `lib/` y
`test/`; reglas completas de Firestore/Storage; configuración Firebase local;
herramientas de pruebas y configuración de compilación Web/Android.

Se mantiene una carrera, sin semestre; género masculino/femenino; preferencias
masculino/femenino/ambos; fotografías en Storage y referencias dentro del perfil.
No existe colección Firestore `profile_photos`: ese nombre identifica una carpeta de Storage.

No se implementaron HU-13 a HU-17, Cloud Functions ni cambios de catálogos.
No se accedió ni modificó Firebase remoto, Authentication remoto o Supabase.
No se ejecutaron seeds remotos, borrados de datos reales, resets ni despliegues.

## 3. Entorno probado

- Windows, PowerShell, Flutter 3.44.4 stable y Dart 3.12.2.
- Java 21.0.9 de Android Studio; Node 24.15.0; Firebase CLI local 15.31.0.
- Flutter: Firestore falso y dobles de Auth/Storage en memoria.
- Reglas: proyecto **demo-tinder-universitario**, Firestore 127.0.0.1:8088,
  Storage 127.0.0.1:9198. Firebase CLI confirmó configuración demo.
- Las limpiezas y fixtures de tests se limitan al emulador.
- La suite de catálogos utiliza un `fetch` simulado: sus cuatro tests no ejecutan POST reales.
- No se ejecutó la aplicación compilada contra producción ni se probó un teléfono físico.

## 4. Historias y matriz HU-01 a HU-12

“PASS local” requiere un test o una revisión concreta; no equivale a aceptación en producción.

| Historia | Funcionalidad | Implementada | Pruebas existentes/ampliadas | Resultado | Observaciones |
|---|---|---|---|---|---|
| HU-01 | Registro | Sí | `auth_test.dart`, `auth_service_test.dart`; reglas «Registro crea solo user e inactivo» | PASS local | Auth delegado; menor rechazado antes de registrar; perfil privado, role=user, inactivo. No verifica pertenencia institucional. |
| HU-02 | Login/logout y sesión | Sí | AuthService: login válido/inválido, logout; widget AuthGate restaura stream y vuelve al login | PASS local | Revisión de `main.dart`: Persistence.LOCAL en Web; AuthGate usa authStateChanges. Persistencia real entre reinicios no probada con SDK remoto. |
| HU-03 | Completar perfil | Sí | `profile_test.dart`: guardado parcial, campos protegidos, menor y género inválido; reglas equivalentes | PASS local | Perfil incompleto permanece inactivo. Fecha exacta solo en users privado. |
| HU-04 | Carrera única | Sí | Servicio rechaza carrera inactiva; reglas rechazan carrera inventada, lista careerIds y semester | PASS local | Selector de una carrera activa. Catálogo real no modificado. |
| HU-05 | Fotos y principal | Sí | Subir, límite/tipo, cambiar principal, retirar última, recuperación de fallo; reglas Storage de dueño/tamaño/MIME | PASS local | Storage no comparte transacción con Firestore. Ver riesgos de URLs y huérfanos. |
| HU-06 | Activar/desactivar | Sí | «Activar requiere foto…», última foto desactiva; reglas «Perfil completo activa…» | PASS local | Desactivar conserva datos; no activa perfil incompleto. |
| HU-07 | Intereses | Sí | Guardar/quitar, máximo 5, duplicados e inexistentes; reglas catálogo | PASS local | Solo IDs activos al cambiarlos. Sin escrituras remotas al catálogo. |
| HU-08 | Preferencias | Sí | Mínimo 18, orden min/max, máximo 100, géneros exactos y selectores; privacidad en reglas | PASS local | Preferencias ajenas nunca se entregan al cliente. |
| HU-09 | Descubrimiento | Sí, privacidad corregida | Exclusión propia/inactivos/evaluados, paginación, género/edad; reciprocidad real en reglas; `discovery_privacy_test.dart` | PASS local | Edad entera; reglas bloquean fichas legadas o vencidas. Renovación manual documentada. |
| HU-10 | LIKE/PASS | Sí | Tipo, self-swipe, segunda decisión, ID; reglas owner y rechazo update/delete | PASS local | Decisiones persistentes; candidato evaluado excluido. |
| HU-11 | Match recíproco | Sí | Unilateral, LIKE+PASS, reciprocidad, ID canónico y concurrencia forzada en emulador | PASS local | Dos LIKE simultáneos → dos swipes y exactamente un match. |
| HU-12 | Mis Matches | Sí | Consulta por participante, orden, estado vacío, perfil no disponible y widget 360px; reglas terceros | PASS local | Solo matches propios. No update/delete, chat ni unmatch. |

La marca «Univalle · Cochabamba» está en la interfaz, pero el registro admite cualquier
correo sintácticamente válido. No existe verificación de matrícula, sede ni dominio.
No se inventó un dominio autorizado para resolver esa decisión de negocio.

## 5. Matriz de pruebas

| Área | Evidencia ejecutada | Resultado |
|---|---|---|
| Auth | 5 tests previos + 6 nuevos de servicio/widget | 11 PASS |
| Perfil/carrera/fotos/intereses/activación | `test/profile_test.dart` | 23 PASS |
| Discovery/preferencias | `test/discovery_test.dart` | 12 PASS |
| Privacidad de Discovery | `test/discovery_privacy_test.dart` | 6 PASS |
| Matches | `test/matches_test.dart` | 10 PASS |
| Firestore y Storage | `tool/rules.test.mjs` | 40 PASS, 0 FAIL, 0 omitidos |
| Herramienta de catálogos, sin red | `tool/seed_catalogs_cli.test.mjs` | 4 PASS, 0 FAIL |

Flutter total: **62 PASS, 0 FAIL**. Se conservaron los 50 tests anteriores y se añadieron 12.
Los fixtures y la expectativa de proyección de tests previos se adaptaron al contrato sin birthDate.
Reglas: 32 tests anteriores + 8 nuevos = **40**. Los cuatro tests de herramientas
se contabilizan por separado.

## 6. Pruebas funcionales y decisión de edad

La ficha contiene exactamente:
`firstName, age, gender, description, careerId, mainPhotoUrl, interestIds, isActive, updatedAt`.
No contiene birthDate, email, apellido, role, preferencias, lista privada de fotos ni createdAt.
El índice conserva únicamente `isActive, updatedAt`.

`DiscoveryPublication.card` deriva la edad en años cumplidos por calendario UTC.
`ProfileService` ya sincronizaba perfil/índice/ficha en una sola transacción:
esa operación ahora reemplaza la ficha completa con el contrato nuevo, sin mezclar campos legados.
El propietario conserva su fecha exacta en `users/{uid}` y puede editarla.

`DiscoveryCandidate` recibe un entero age, sin propiedad birthDate ni conversión desde una fecha ajena.
La compatibilidad cliente usa `acceptsAge`. Las reglas siguen comprobando ambas preferencias
con las fechas **privadas** y la hora del servidor, sin entregar esas fechas al cliente.

Las reglas comparan la ficha completa con `cardFields(user)`, tanto al escribir como al leer.
Esto rechaza campos extra, edad manipulada, fichas con birthDate y fichas cuya edad venció.
También se aplica a la lectura autorizada por un match.

Limitación deliberada, sin proceso de servidor:
- La edad se renueva al guardar perfil o realizar una acción explícita sobre sus fotos.
- Tras un cumpleaños, la ficha queda temporalmente inaccesible para terceros hasta republicarse.
  Discovery la omite; Mis Matches conserva el match y muestra «Perfil no disponible».
- Al entrar a Discovery, el dueño recibe una instrucción para guardar si su ficha es legada
  o tiene una edad vencida. No hay migración automática al iniciar sesión ni al leer.
- Edad sin nacimiento en un borrador: null; no permite activar ni descubrir ese perfil.
- Para nacidos el 29 de febrero, el cambio ocurre el 1 de marzo en años no bisiestos.
- Un reloj cliente incorrecto o un guardado que cruce el cumpleaños UTC puede causar rechazo;
  las reglas no aceptan una edad falsa para evitarlo. Corregir reloj/reintentar.
- Una ficha ya cargada en pantalla no se actualiza por sí sola a medianoche; se valida al volver a leer.
- Las reglas nuevas bloquean lecturas futuras; no retiran información que alguien descargó antes.

## 7. Pruebas de seguridad

Se auditaron ambas reglas completas. No se añadieron permisos globales ni se relajaron validaciones.

| Recurso | Política comprobada |
|---|---|
| users | Get del dueño; sin list/delete; campos protegidos; create inactivo/user; mayoría de edad y activación completa |
| preferences | Solo dueño; géneros/rango/tipos/campos exactos; sin list/delete |
| careers/interests | Lectura autenticada; ninguna escritura cliente |
| discoveryIndex | Índice mínimo; páginas activas con límite <=25; solo dueño publica su estado |
| discoveryCards | Get individual por dueño, reciprocidad o match válido; sin list; contenido exacto y edad vigente |
| swipes | Emisor crea decisión propia válida, nunca a sí mismo; ID direccional; inmutables; terceros sin get |
| matches | Dos LIKE comprobados con getAfter; ID y participantes ordenados; lectura/lista solo participantes; sin update/delete |
| Storage | Carpeta propia; 1..5 MB; JPEG/PNG/WebP por contentType; sin reemplazo; terceros/anónimos/subcarpetas rechazados |
| Rutas no definidas | Denegadas, incluida una supuesta colección Firestore profile_photos |

La prueba concurrente sincroniza las lecturas iniciales de los dos LIKE antes de permitir
los commits. Resultado observado: un resultado false, uno true; dos swipes y un match.
Se conservó el reintento único de la transacción para la carrera permission-denied.
No se modificó la lógica de matches para hacer pasar pruebas.

## 8. Resultados Flutter

- `flutter pub get`: código 0; sin cambios en pubspec ni lockfile.
- `flutter analyze`: código 0, **No issues found!**
- `flutter test --reporter expanded`: código 0, **62/62**, All tests passed.
- Los dobles de Auth verifican llamadas y reacción del cliente, no el servicio remoto.
- Widgets de Perfil, Discovery y Matches probados a 360 px; AuthGate login/logout probado.

## 9. Resultados reglas Firebase

Comando ejecutado:

~~~powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --config firebase.emulators.json --project demo-tinder-universitario --only firestore,storage "node --test tool/rules.test.mjs"
~~~

Resultado: **40/40 PASS**, 0 FAIL, 0 cancelados, 0 omitidos; salida 0.
Los emuladores se detuvieron al terminar. Los mensajes PERMISSION_DENIED corresponden
a pruebas negativas esperadas; no son tests fallidos.
Log local fuera de Git:
`C:\Users\HP\.codex\visualizations\2026\09\05\01a073b1-6969-77a3-8edb-4d84a04a5e76\tinder-qa-rules.log`.

Prueba adicional ejecutada: `node --test tool/seed_catalogs_cli.test.mjs`: 4/4 PASS.

## 10. Resultado Build Web

`flutter build web`: **correcto, código 0**. Compilación: 145,6 s.
Salida: `build/web`. Wasm dry run correcto; el artefacto entregado es el build Web normal.
No se publicó ni se ejecutó contra Firebase remoto.

## 11. Resultado Build Android

`flutter build apk --debug`: **correcto, código 0**. assembleDebug: 116,6 s.
Salida: `build/app/outputs/flutter-apk/app-debug.apk`.
Se usaron los límites Gradle de memoria/trabajadores indicados al reproducir.
Advertencia no bloqueante: firebase_auth, firebase_core y firebase_storage todavía aplican
Kotlin Gradle Plugin; Flutter avisa de incompatibilidad en versiones futuras.
No se instaló el APK ni se probó un dispositivo físico.

## 12. Defectos encontrados

1. Discovery y Matches recibían birthDate exacta en su ficha, pese a ocultarla visualmente.
2. Las reglas autorizaban ese contrato y faltaban pruebas de privacidad del payload.
3. Auth no permitía inyectar dependencias para probar su servicio sin inicializar Firebase real.
4. Documentación anterior seguía describiendo la exposición y un ejemplo de registro
   en README_BLOQUE_1 indicaba isActive=true, distinto del comportamiento actual.
5. El alcance institucional exclusivo no tiene control técnico de pertenencia.
6. Los tests previos no demostraban por sí solos renovación de edad, rechazo de fichas
   legadas ni el ciclo del servicio Auth. Estos huecos están cubiertos ahora.

No hubo FAIL en las ejecuciones Flutter ni Rules realizadas en este cierre.
La renovación de edad es una limitación explícita de la solución elegida, no una tarea de servidor implementada.

## 13. Defectos corregidos y archivos para el próximo commit

Creados:
- `README_QA_SPRINT_1_2.md`: matriz, evidencia, resultados y límites.
- `test/auth_service_test.dart`: seis tests sin servicios remotos.
- `test/discovery_privacy_test.dart`: seis tests de contrato/edad/republicación.

Modificados:
- `firestore.rules`: contrato age y validación en lectura/escritura; users sigue privado.
- `lib/features/discovery/discovery_publication.dart`: publicación de edad derivada.
- `lib/features/discovery/discovery_models.dart`: candidato sin fecha exacta.
- `lib/features/discovery/discovery_service.dart`: aviso al dueño si ficha legada/vencida.
- `lib/features/preferences/discovery_preferences.dart`: comparación por edad entera.
- `lib/features/auth/auth_service.dart`: constructor con dependencias opcionales;
  producción conserva FirebaseAuth.instance/FirebaseFirestore.instance.
- `test/discovery_test.dart`, `test/matches_test.dart`: contrato nuevo en fixtures y expectativas.
- `tool/rules.test.mjs`: ocho pruebas adicionales y proyección de fixtures sin birthDate.
- `README_BLOQUE_1.md`, `README_BLOQUE_3.md`, `README_BLOQUE_4.md`: documentación coherente.

Solo estos 15 archivos corresponden al cierre. No incluir build/, .dart_tool/,
tool/node_modules/, logs, credenciales ni configuraciones personales.
No se cambió storage.rules, catálogos, Firebase options ni dependencias.

## 14. Riesgos conocidos y advertencias

- Exclusividad institucional no verificada: cualquier correo válido puede registrarse.
- Edad y pertenencia universitaria son datos declarados, sin verificación documental.
- Las URLs con token de descarga de Storage son enlaces portadores: quien las tenga
  puede conservar acceso aunque una lectura SDK de terceros esté denegada.
  Desactivar el perfil no revoca automáticamente enlaces ya compartidos.
- Storage valida MIME/tamaño; no inspecciona que el contenido binario sea una imagen auténtica.
  La aplicación sí comprueba firmas básicas antes de subir.
- Storage/Firestore no son atómicos; pueden quedar archivos huérfanos tras una pérdida de conexión.
  El reintento de borrado solo se conserva mientras permanece abierta la pantalla.
- El índice revela IDs activos a usuarios autenticados. El get puntual de swipes admite al destinatario
  para comprobar reciprocidad; no permite listar decisiones ajenas.
- Discovery puede consumir muchas lecturas; Mis Matches carga la lista sin paginación.
- No se consolidan automáticamente dos LIKE antiguos que ya existieran antes del Bloque 4.
- Pub get avisa de 9 paquetes con versiones nuevas incompatibles con las restricciones actuales.
  No se actualizaron dependencias. El aviso de nueva versión Flutter es informativo.
- Web informa de Wasm dry run correcto y reducción de fuentes; no se ejecutó una app Wasm.
- Android: aviso futuro de KGP en firebase_auth, firebase_core y firebase_storage.
  No bloqueó el build actual; revisar soporte Built-in Kotlin antes de actualizar Flutter.
- Git puede avisar LF → CRLF por la configuración existente; no se cambió esa configuración.

## 15. Pendientes reales y comandos de despliegue

1. Decidir cómo garantizar —o aceptar explícitamente que no se garantiza— pertenencia
   a Univalle sede Cochabamba. No basta la etiqueta visual.
2. Aceptar la renovación manual de edad como límite del alcance sin backend de ejecución.
3. Desplegar reglas nuevas y distribuir el cliente actualizado de forma coordinada.
   Clientes anteriores intentan escribir birthDate en la ficha y serán rechazados.
4. Cada propietario debe guardar su perfil para reemplazar su ficha antigua.
   No se ejecutó actualización masiva ni se tocaron usuarios remotos.
5. Validar login/persistencia real tras reinicio, selector de fotos y flujo con dos usuarios
   en navegador y dispositivo Android, en un entorno de aceptación autorizado.
6. Configurar Hosting o el destino de publicación Web si se desea desplegar la app.
   firebase.json no define hosting; el build no constituye un deploy.
7. Para distribución Android de producción, definir ID definitivo y firma release.
   Este cierre produjo un APK debug, no una versión de tienda.

**Comando exacto necesario para publicar la única regla modificada — NO ejecutado:**

~~~powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:rules --project tinder-universitario
~~~

No hace falta desplegar reglas Storage ni índices para estos cambios.
No se proporciona un `deploy hosting` funcional porque no existe configuración de Hosting;
requiere elegir/configurar ese destino antes. No ejecutar seeds como parte del despliegue.

Comandos locales de reproducción:

~~~powershell
flutter pub get
flutter analyze
flutter test
flutter build web
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dorg.gradle.jvmargs=-Xmx2048m'
flutter build apk --debug
git diff --check
git status --short
~~~

## 16. Conclusión del QA

Las doce historias están implementadas y cuentan con evidencia local satisfactoria.
La corrección de birthDate pasa las pruebas de servicio, contrato público y reglas reales del emulador.
Análisis limpio, 62/62 tests Flutter, 40/40 de reglas, 4/4 de herramientas y ambos builds correctos.
`git diff --check`: sin errores de whitespace.

- **Sprint 1:** HU-01 a HU-06 pueden cerrarse técnicamente para el alcance funcional local
  implementado. No corresponde declarar cumplida la exclusividad institucional: su control
  o aceptación explícita sigue pendiente, al igual que la validación real de sesión/fotos.
- **Sprint 2:** HU-07 a HU-12 pueden cerrarse técnicamente en local con la limitación de
  renovación manual de edad documentada. La corrección de privacidad todavía debe desplegarse
  junto con el cliente; los propietarios deben republicar fichas y completar QA de aceptación.

Por tanto, **cierre técnico local satisfactorio; cierre de aceptación/producción condicionado**
a los pendientes enumerados. No se inició Sprint 3.

Sin deploy, commit ni push. Los resultados describen el código local probado;
no certifican el estado de reglas o clientes desplegados en Firebase real.
