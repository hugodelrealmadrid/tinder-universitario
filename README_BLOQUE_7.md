# Bloque 7 — HU-16 Bloquear / HU-17 Reportar

Proyecto: `C:\Users\HP\Desktop\tinder_universitario`. Firebase: `tinder-universitario`.
Último bloque funcional del Sprint 3. Implementación y validación locales; no deploy,
seeds remotos, cambios a datos remotos, commit ni push.

## Modelos exactos

```text
blocks/{blockerUid}.{blockedUid}
  blockerId: string
  blockedId: string
  createdAt: timestamp servidor

reports/{reporterUid}.{reportedUid}
  reporterId: string
  reportedId: string
  reason: fake_profile | inappropriate_content | harassment | spam | other
  details: string (vacío si se omite, máximo 500)
  createdAt: timestamp servidor
  status: "pending"
```

No contienen emails, nombres, fotografías, fechas de nacimiento ni perfiles.
`SafetyIds.idFor` reutiliza la validación de `SwipeDecision.idFor`: UID distintos,
1..128 caracteres alfanuméricos, guion o guion bajo, separados por punto. IDs direccionales:
A.B no es B.A. El punto está excluido de los UID para evitar ambigüedades.

`ReportReasons` centraliza códigos estables, etiquetas españolas y límite de detalles.
La UI usa dropdown para el motivo, nunca texto libre. Detalles es el único campo
libre y es opcional; se recortan espacios exteriores. La validación Dart es conservadora
en UTF-16 (como el chat existente), por lo que emojis pueden consumir dos unidades.

## Política MVP de duplicados

Se eligió la alternativa A solicitada: **un reporte por pareja direccional**.
El ID fijo y UPDATE denegado impiden sobrescribirlo o añadir otro con un ID aleatorio.
No hay renovación por tiempo, administración ni resolución de reportes desde clientes.
Mientras exista ese documento no puede enviarse otro de A sobre B, aunque cambie el motivo.
Esto evita duplicados por doble clic, reintentos y múltiples dispositivos, sin backend adicional.

El cliente no lee reports, ni siquiera para averiguar si ya existe uno. Un permission-denied
se informa como posible duplicado o acción no autorizada, sin afirmar que necesariamente sea duplicado.
Un fallo de red permite reintentar con el mismo ID: si la primera escritura llegó al servidor,
el segundo intento no puede sobrescribirla. No se simula éxito ante un rechazo.

El bloqueo propio duplicado sí puede reconocerse mediante GET del ID propio:
`block` devuelve false si ya existía, sin reescribir ni cambiar su timestamp.
La UI confirma el estado bloqueado. UPDATE/DELETE de blocks permanecen denegados.

## Bloqueo atómico y cierre

`SafetyService.block(target)` obtiene el UID de FirebaseAuth, valida identidad y destino
y ejecuta una transacción. Lee exclusivamente su bloqueo y el match canónico de esa pareja.
Las reglas comprueban existencia del usuario destino sin abrir su documento privado al cliente.

Si el match está activo, lo cierra con `StudentMatch.closeFields`, compartido con HU-15:

```text
isActive: false
closedAt: timestamp servidor
closedBy: UID del usuario que bloquea
```

El block y el cierre se confirman juntos. Users y createdAt del match permanecen iguales.
Sin match solo se crea blocks; con match cerrado se conserva exactamente su cierre original.
Nunca se borran mensajes, swipes, usuarios ni matches. Un bloqueo propio previo con match
activo inconsistente puede cerrar ese match sin reescribir el block.

Rules exige que el match canónico esté ausente o inactivo al finalizar el commit del bloqueo.
Por ello un cliente no puede crear un block dejando un match activo. La actualización del match
debe cumplir todas las reglas HU-15. Un reintento adicional limitado de la transacción permite
resolver cambios concurrentes que Rules detecte antes del reintento automático del SDK.
Una denegación persistente se muestra como error. Dos bloqueos simultáneos pueden producir
los dos documentos direccionales, pero conservan un único cierre del match.

## Efecto mutuo y privacidad

Aunque el block sea direccional, `noBlocks(a,b)` y `noBlocksAfter(a,b)` comprueban
A.B y B.A. La ausencia de bloqueo se exige en ambos sentidos.

* **Discovery:** lectura de discoveryCards denegada en cualquier dirección, incluso si había match.
  El cliente omite fichas con permiso denegado y revisa adicionalmente su propio bloqueo puntual.
  Mantiene todas las exclusiones anteriores. Después de bloquear desde Discovery se retira
  inmediatamente la tarjeta local y se busca el siguiente candidato.
* **Swipes:** CREATE denegado con bloqueo en cualquier dirección. Los antiguos quedan intactos.
  El servicio también rechaza el bloqueo propio y lee la ficha protegida antes de decidir.
* **Matches:** CREATE denegado aunque ya existan dos LIKE antiguos. Un match activo se cierra
  al bloquear y desaparece por la escucha de la lista activa implementada en HU-15.
* **Chat:** nuevos mensajes denegados por bloqueo en cualquiera de las direcciones, incluso si
  por una escritura administrativa inconsistente el match siguiera activo. El cliente comprueba
  adicionalmente su propio bloqueo; el inverso lo valida el servidor. El cierre normal deshabilita
  el envío en ambos chats por el listener del match.
* **Historial:** continúa legible por los participantes según la política de HU-15; no se borra.

BLOCKS permite solo GET de un ID cuyo blockerId está representado por el UID autenticado
en su prefijo determinista. No permite LIST, ni GET al destinatario o terceros.
El cliente nunca consulta el bloqueo inverso ni recibe listas de quién lo bloqueó.
Las reglas inspeccionan esos documentos internamente al autorizar la ficha/interacción.
Una denegación no revela si se debe a bloqueo, preferencias o estado del perfil.

El índice discoveryIndex mantiene su contrato anterior de metadatos activos sin ficha personal;
no hace joins ni expone documentos blocks. No se muestran IDs ni datos internos en la interfaz.
Las fichas públicas actuales siguen usando edad, sin reintroducir birthDate.

REPORTS permite CREATE autenticado del remitente, pero **READ, UPDATE y DELETE son false
para todos los clientes**, incluido el autor y el reportado. No hay panel administrativo;
la revisión manual solo puede hacerse con acceso administrativo autorizado fuera de la app.

## Reportar es independiente

`SafetyService.report` valida sesión, no auto-reporte, motivo del catálogo y longitud,
y escribe únicamente reports con status pending y timestamp del servidor.
No ejecuta block, cierre, desactivación de cuenta ni borrados. Bloquear tampoco crea reportes.
Las reglas admiten un reporte independientemente de si existe bloqueo. No hay ban automático.

## UI

Los menús de Chat activo y de la tarjeta de Discovery ofrecen Bloquear usuario y Reportar usuario.
Se conserva Deshacer match en Chat.

Bloquear abre «¿Bloquear usuario?» con el texto:
«Ya no podrán encontrarse en Descubrir ni enviarse mensajes. Esta acción no se puede deshacer actualmente.»
Cancelar no escribe. Confirmar deshabilita botones y navegación del diálogo durante la operación,
muestra loading y evita doble ejecución. Al éxito se informa Usuario bloqueado; desde chat vuelve
a Matches cuando hay una ruta anterior, y desde Discovery retira la tarjeta.

Reportar abre selector de motivo y detalles opcionales, con Cancelar/Enviar reporte.
Al confirmar correctamente muestra «Reporte enviado.». No ofrece bloqueo automático.
En error el diálogo permanece abierto, conserva los datos y permite reintentar.
Los motivos visibles son Perfil falso, Contenido inapropiado, Acoso, Spam y Otro.

## Cambios de Rules

* blocks: esquema exacto, remitente autenticado, destino existente, no self, ID correcto,
  timestamp servidor y match cerrado después de la operación. Lecturas puntuales propias, sin listas ni mutaciones.
* reports: esquema exacto, ID direccional, autor autenticado, destino existente, no self,
  motivo permitido, details string hasta 500, pending y timestamp servidor. Sin lecturas ni mutaciones.
* discoveryCards: noBlocks protege tanto la rama de compatibilidad como la de match previo.
* swipes, matches CREATE y messages CREATE: noBlocksAfter, para impedir también eludir el bloqueo
  creando interacciones en el mismo lote. Se mantienen las validaciones anteriores.

`existsAfter/getAfter` validan el estado final antes de confirmar las escrituras:
[referencia oficial de Firebase](https://firebase.google.com/docs/reference/rules/rules.firestore).
La suite prueba también LIKE recíproco con carreras distintas para cubrir el presupuesto de lecturas de Rules.

## Archivos

Creados:

* `lib/features/safety/safety_models.dart`
* `lib/features/safety/safety_service.dart`
* `lib/features/safety/safety_dialog.dart`
* `test/safety_test.dart`
* `README_BLOQUE_7.md`

Modificados:

* `lib/features/chat/chat_screen.dart`
* `lib/features/chat/chat_service.dart`
* `lib/features/discovery/discovery_screen.dart`
* `lib/features/discovery/discovery_service.dart`
* `lib/features/matches/student_match.dart`
* `lib/features/matches/unmatch_service.dart`
* `firestore.rules`
* `tool/rules.test.mjs`

## Validación

Resultados locales finales:

| Comprobación | Resultado |
| --- | --- |
| flutter pub get | Correcto, sin cambios de dependencias |
| flutter analyze | No issues found |
| flutter test | 128/128 correctos (28 nuevos) |
| Rules Firestore/Storage, emuladores | 114/114 correctos (32 nuevos) |
| Herramientas | 4/4 correctos |
| flutter build web | Correcto: build/web |
| flutter build apk --debug | Correcto: build/app/outputs/flutter-apk/app-debug.apk |
| git diff --check | Correcto |

Advertencias no bloqueantes: pub informa nueve versiones más nuevas incompatibles con
las restricciones actuales; Web informa del dry run Wasm correcto y reducción de fuentes;
Android advierte que firebase_auth, firebase_core y firebase_storage usan Kotlin Gradle
Plugin y requerirán actualización para versiones futuras de Flutter. Git avisa de conversión
LF a CRLF según la configuración local. No se actualizaron dependencias fuera del alcance.
Android se verificó en debug, no como paquete release firmado ni en dispositivo físico.

Se mantienen los 100 tests Flutter y los 82 tests de reglas anteriores.
Se agregan 28 tests Flutter y 32 tests Rules. Cubren modelos, bloqueos en ambos sentidos,
cierre, historial, independencia de acciones, duplicados, permisos, confirmación, errores,
selección controlada y diálogos a 360 px. El fake Dart simula respuestas de permiso;
los permisos reales, commits atómicos y concurrencia se verifican en el emulador.

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

## Límites del MVP

* No desbloqueo, rematch, borrado, moderación automática, administración ni notificaciones.
* Un reporte por pareja direccional mientras exista el documento; no hay renovación ni edición.
* La privacidad no permite distinguir con certeza duplicado de otros rechazos de permiso.
* Un cliente malicioso aún puede reportar diferentes cuentas conocidas: no hay rate limiting global sin backend.
* Discovery no tiene una suscripción nueva a bloqueos entrantes: una tarjeta ya descargada por el otro
  usuario puede permanecer en pantalla hasta Actualizar o volver a entrar. Las nuevas lecturas y todas
  las nuevas interacciones quedan denegadas desde que se confirma el block. La tarjeta del que bloquea
  se retira inmediatamente. No se puede revocar información ya descargada.
* La cabecera de un chat abierto puede conservar nombre/foto ya cargados; el historial sigue privado
  entre participantes y el envío se deshabilita con el cierre. Sin lista de chats archivados.
* No se cambia la ventana de 50 mensajes ni las limitaciones de publicación de edad del bloque anterior.
* Los enlaces de fotos ya conocidos conservan la política de Storage anterior; no se modifican tokens ni Storage.
* Operaciones sujetas a conexión y confirmación de Firebase. No se probó contra cuentas reales en esta ejecución.

## Deploy manual — NO ejecutado

No se requieren índices nuevos. Solo hay lecturas por ID para blocks/reports; no se listan.

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js deploy --project tinder-universitario --only firestore:rules
```

No hay comando de índices ni despliegue de Storage. Usar reglas y app actualizadas.

## QA real HU-16 (lo ejecuta el usuario)

1. Revisar y ejecutar personalmente el deploy anterior.
2. Iniciar `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8585`.
3. Abrir `http://127.0.0.1:8585` en dos sesiones separadas e iniciar A y B.
4. Para bloqueo sin match usar dos cuentas compatibles, activas y sin swipes/bloqueos entre ellas.
   En Discovery de A abrir Opciones → Bloquear usuario → Cancelar: la tarjeta sigue disponible.
5. Repetir y confirmar. A retira a B. Actualizar Discovery de B: A no aparece. Reiniciar sesión confirma persistencia.
6. En Console verificar `blocks/{uidA}.{uidB}` con solo los tres campos del modelo. No hay documento inverso
   salvo que B bloquee por su propia acción. No modificar datos desde Console.
7. Para chat usar OTRA pareja con match activo y sin bloqueos previos. Enviar mensajes en ambos sentidos.
   Mantener chat de B abierto; A elige Bloquear usuario y confirma.
8. A vuelve a Matches sin la entrada. B conserva mensajes pero el envío queda deshabilitado.
   Verificar match isActive false, closedBy A, closedAt servidor, users/createdAt originales.
9. Verificar que messages y swipes siguen existiendo. Recargar: no vuelve a Discovery ni a Matches activos.
10. No eliminar blocks ni reactivar matches para repetir. Usar otra pareja para cada prueba irreversible.
    Los intentos manipulados y la defensa con match activo inconsistente se prueban en emulador, no alterando datos reales.

## QA real HU-17 (lo ejecuta el usuario)

1. Con otra pareja accesible, abrir Reportar usuario desde Discovery o Chat.
2. Cancelar: no debe crearse reporte. Reabrir; sin motivo, Enviar exige seleccionar uno.
3. Elegir Spam y detalles opcionales, enviar: aparece «Reporte enviado.».
4. En Console verificar `reports/{uidA}.{uidB}`: reporterId A, reportedId B, reason spam,
   details string, createdAt servidor, status pending, sin campos de perfil.
5. Verificar que no se creó blocks ni se cerró/desactivó el match o usuario. El chat continúa funcionando.
6. Intentar reportar nuevamente desde A: no se sobrescribe ni duplica; se muestra un error de posible reporte previo.
7. Si A decide bloquear después, requiere otra acción y confirmación explícita. El reporte original se conserva.
8. No existe UI para consultar reportes. GET/LIST para autor, reportado y terceros están cubiertos por tests de Rules;
   la Console administrativa no aplica las restricciones del cliente y no sirve para probar esos rechazos.

Sin deploy, commit ni push durante la implementación. Sin operaciones remotas sobre Auth, catálogos,
Storage, usuarios, mensajes o Supabase.
