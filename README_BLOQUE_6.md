# Bloque 6 — HU-15: Deshacer match

Proyecto: `C:\Users\HP\Desktop\tinder_universitario`. Firebase: `tinder-universitario`.
Solo HU-15. Sin deploy, seeds, migraciones, cambios remotos, commit ni push.

## Modelo y transición

Activo (compatible con los documentos existentes):

```text
matches/{uidMenor}.{uidMayor}
  users: [uidMenor, uidMayor]
  createdAt: timestamp original
  isActive: true
```

Cerrado:

```text
matches/{uidMenor}.{uidMayor}
  users: [uidMenor, uidMayor]     // sin cambios
  createdAt: timestamp original // sin cambios
  isActive: false
  closedAt: timestamp servidor
  closedBy: uid del participante autenticado
```

`StudentMatch` incorpora `closedAt` y `closedBy` opcionales. `fromMap` valida dos
participantes distintos y ordenados, isActive booleano y coherencia del cierre:
activo sin metadatos de cierre; inactivo con fecha y autor participante.
Los documentos activos anteriores sin closedAt/closedBy siguen siendo válidos.
No se migran automáticamente documentos inválidos o cierres administrativos antiguos sin metadatos.

## Servicio y concurrencia

`UnmatchService.unmatch(matchId)` obtiene la identidad desde FirebaseAuth; no recibe
un UID libre desde el formulario. Auth y Firestore son inyectables para pruebas.
La transacción lee el match, valida existencia, modelo, ID determinista,
participación, sesión y estado activo; actualiza solamente isActive, closedAt y closedBy.
No contiene operaciones de borrado ni escrituras de usuarios, mensajes o swipes.

Ante dos cierres simultáneos, la transacción en conflicto observa el cierre en su
reintento o es rechazada por reglas. Solo gana un commit. Un cierre confirmado nunca
puede cambiar de autor, fecha ni volver a isActive true. El servicio informa si ya está cerrado;
otros errores generan feedback recuperable. No se reintenta una operación de cierre automáticamente fuera del SDK.

## Seguridad Firestore

Se conserva CREATE con LIKE mutuo, READ de participantes y DELETE denegado.
UPDATE permite exclusivamente:

* Usuario autenticado participante del documento original.
* Estado original true, nuevo false.
* Esquema final exacto: users, createdAt, isActive, closedAt y closedBy.
* Diff limitado a isActive, closedAt y closedBy: users y createdAt permanecen intactos.
* Documento original sin campos de cierre; closedBy igual a request.auth.uid y closedAt igual a request.time.

Reactivación, nuevo cierre, cambios posteriores, terceros, anónimos, campos extra y timestamps falsos son rechazados.
No se cambiaron las reglas de usuarios, catálogos, preferencias, descubrimiento, swipes ni Storage.
En mensajes se añadió una comprobación getAfter del estado activo, junto con la comprobación previa:
así no puede enviarse un mensaje en el mismo lote que cierra el match. La lectura de historial no requiere match activo.

## Interfaz y conservación del historial

Menú discreto de opciones del chat → Deshacer match → diálogo:

«¿Deshacer match?»

«Ya no podrán enviarse mensajes nuevos. El historial se conservará.»

Cancelar no escribe nada. Confirmar ejecuta una sola operación; el menú y envío
se deshabilitan durante confirmación/cierre. Al confirmar el servidor se muestra
«Match finalizado. El historial se conserva.» y se vuelve a Matches cuando existe esa ruta.
Si el chat es la ruta raíz, permanece mostrando el historial cerrado.
Un error no cierra la pantalla ni borra el borrador o historial.

El otro participante que ya esté en ChatScreen recibe el estado cerrado por el listener:
«Este match ha finalizado. Ya no puedes enviar mensajes. Puedes consultar el historial.»
El campo y botón de envío quedan deshabilitados. Rules rechaza nuevos mensajes aunque
se intenten desde un cliente antiguo o después de una lectura previa del estado activo.
Un mensaje confirmado antes del cierre pertenece al historial y se conserva.

El listener del match ignora snapshots con escrituras locales pendientes hasta confirmar
los metadatos del servidor, evitando interpretar un closedAt pendiente como modelo inválido.
No se muestran closedBy, UID, email, birthDate ni preferencias. Se conserva la ficha pública actual.

## Mis Matches e índices

`MatchesService.load` consulta `users arrayContains uid` y filtra isActive true
antes de construir la lista y leer fichas. Una escucha de esa misma consulta retira
IDs cerrados en tiempo real, también cuando el cierre lo hace el otro usuario.
Al regresar del chat se recarga la lista. Reintentar reinicia también la escucha.

No hace falta un índice compuesto: se conserva el índice array automático. Esto
evita una nueva configuración para el proyecto pequeño, a cambio de leer también
los documentos de matches cerrados del propio usuario. No se leen mensajes para filtrar.
El orden sigue siendo por createdAt descendente en memoria. Una nueva coincidencia
puede requerir pulsar Actualizar; la retirada de cerrados sí es inmediata al recibir el snapshot.
Si crece el volumen, se podrá paginar y filtrar isActive en servidor con el índice correspondiente.

## Tests

Resultados finales (29/09/2026, hora Bolivia):

| Comprobación | Resultado |
|---|---|
| flutter pub get | PASS, sin cambios de dependencias |
| flutter analyze | PASS, No issues found |
| flutter test | 100/100 PASS: 85 anteriores + 15 nuevos |
| Firestore/Storage Rules | 82/82 PASS: 64 anteriores + 18 nuevos |
| Herramientas | 4/4 PASS |
| Build Web | PASS, build/web, 68,8 s |
| Build Android debug | PASS, build/app/outputs/flutter-apk/app-debug.apk, 54,8 s de Gradle |
| git diff --check | PASS |

Advertencias: nueve paquetes tienen versiones nuevas incompatibles con las restricciones actuales;
no se actualizaron. Android informa compatibilidad futura de Kotlin Gradle Plugin en los plugins
Firebase, sin impedir el build. Web informa Wasm dry run correcto y reducción de fuentes.
Git informa conversión LF/CRLF según su configuración; no hubo errores de whitespace.
Los PERMISSION_DENIED del emulador corresponden a pruebas negativas esperadas.

Se conservan los 85 tests Flutter anteriores; dos fixtures del test de chat ahora
representan cierres con closedAt/closedBy, sin eliminar sus comprobaciones.
Se añaden 15 tests Flutter: ambos participantes, tercero/anónimo, segundo cierre,
match ausente/ID inválido, modelos coherentes/incoherentes, lista activa, historial,
envío deshabilitado, Cancelar, confirmar una vez, error, 360 px, retorno y retirada en vivo,
y estado coherente ante solicitudes simultáneas.

El fake Flutter no modela conflictos de transacción reales. La suite del emulador
complementa esa prueba: sincroniza las lecturas de A y B antes de ambos commits y
exige exactamente un éxito y un rechazo, conservando autor y fecha del ganador.

Se conservan los 64 tests de reglas anteriores y se añaden 18 tests de HU-15:
participantes, terceros/anónimo, transiciones inválidas, alteración de campos protegidos,
autor/fecha falsos, campos extra, inmutabilidad tras cierre, DELETE denegado,
historial privado, mensajes nuevos rechazados, lote cierre+mensaje y concurrencia.
Los tests de CREATE por LIKE mutuo siguen dentro de la regresión.

Comandos locales (no realizan operaciones remotas):

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
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

## Archivos

Creados: `lib/features/matches/unmatch_service.dart`, `test/unmatch_test.dart`, `README_BLOQUE_6.md`.

Modificados: `lib/features/matches/student_match.dart`, `lib/features/matches/matches_service.dart`,
`lib/features/matches/matches_screen.dart`, `lib/features/chat/chat_screen.dart`,
`lib/features/chat/chat_service.dart`, `firestore.rules`, `test/chat_test.dart`, `tool/rules.test.mjs`.

## Limitaciones

* No rematch: los swipes siguen inmutables y se conserva el match de ID determinista. No reaparece la pareja en Discovery.
* Sin lista de chats archivados en HU-15. El historial conserva sus permisos y permanece visible
  en un chat ya abierto; al volver a la lista activa no hay un acceso nuevo al chat cerrado.
* Se conserva la ventana de los últimos 50 mensajes de Bloque 5; no se borran los anteriores.
* La operación necesita conexión y autorización del servidor; no se promete cierre offline.
* No HU-16/17, borrados, rematch, notificaciones, Cloud Functions, multimedia ni funciones de presencia.
* No se probó contra cuentas reales durante esta ejecución; las pruebas reales siguientes las ejecuta el usuario.

## Deploy manual pendiente — NO ejecutado

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js deploy --project tinder-universitario --only firestore:rules
```

No hay índices nuevos ni comando de deploy de índices. No desplegar Storage para este cambio.
Usar la nueva app y reglas: las reglas anteriores rechazan el cierre desde el cliente.

## Prueba con dos usuarios reales

1. Revisar cambios y ejecutar personalmente el deploy anterior.
2. Arrancar la versión actualizada:
   `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8585`.
3. Abrir `http://127.0.0.1:8585` en dos perfiles separados/normal e incógnito. Iniciar A y B.
4. Usar un match activo existente, abrirlo en ambas sesiones y enviar mensajes en ambos sentidos.
5. En A abrir Opciones → Deshacer match. Pulsar Cancelar: sigue activo y ambos pueden enviar.
6. Reabrir el menú en A y confirmar Deshacer match. Ver feedback y regreso a Matches sin esa entrada.
7. En B, mantener el chat abierto: historial conservado, aviso de finalización y envío deshabilitado.
8. En Console → Firestore → Datos verificar el mismo documento matches: isActive false,
   closedBy UID de A, closedAt timestamp; users y createdAt originales. No editar desde Console.
9. Comprobar subcolección messages y ambos swipes: siguen existiendo. Volver a Matches en B:
   tampoco aparece. Recargar/iniciar sesión de nuevo en ambos: no reaparece ni se reactiva.
10. Para ver retirada en vivo de la lista, repetir con otra pareja activa dejando B en Matches
    mientras A cierra desde el chat. Para probar cierre simultáneo usar otra pareja activa,
    abrir confirmación en ambos y aceptar casi al mismo tiempo; verificar un único cierre válido.
11. No borrar swipes ni reactivar manualmente para repetir. La Console administrativa no
    aplica las reglas cliente: rechazos de terceros y escrituras manipuladas se comprueban con el emulador.
