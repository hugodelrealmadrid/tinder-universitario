# Fase 3: base de verificación universitaria y administración

19 de octubre de 2026. Trabajo exclusivo en `C:\Users\HP\Desktop\tinder_universitario_pruebas`. Sin commit, push, merge, reset ni deploy. No se modificaron main, el proyecto original ni Firebase producción. Se conservaron las fases anteriores, el diff en `audit-phase3-preexisting.patch` y respaldos en `build/phase3-before`. Datos anteriores exportados a `build/phase3-fixtures-before`.

## Arquitectura y autoridad

| Recurso | Contenido y autorización |
| --- | --- |
| `accountAccess/{uid}` | Rol `user`, `admin` o `superadmin`; estado `pending`, `approved` o `rejected`; `suspended`; fechas y última solicitud. Escritura solo por backend; cliente solo lee su propio documento. |
| `users/{uid}.datingAllowed` | Proyección booleana exclusiva del servidor. Aprobación y suspensión actualizan autoridad y proyección en la misma transacción. Reutiliza las lecturas de perfiles para respetar el presupuesto de Rules. El cliente no puede crear, añadir, modificar ni eliminar este campo. Ausencia equivale a denegación. |
| `users.isActive` | Sigue representando exclusivamente la visibilidad voluntaria. Suspender no lo modifica. `users.role` se conserva como campo legado inmutable, sin autoridad administrativa. |
| `verificationRequests/{requestId}` | UID, institución fija `univalle_cochabamba`, fechas, estado, etapa de documento, referencia privada y generación del objeto, motivo codificado de resolución. Solo el backend escribe; propietario lee su solicitud o consulta las suyas con límite 20. |
| `university_cards/{uid}/{requestId}/document` | Imagen privada. Todas las operaciones de SDK cliente están denegadas, incluidos propietario, admin y superadmin. Lectura mediante backend con permiso vigente, sin auto-revisión, sin URL ni token de descarga. |
| `administration/roles` | Registro transaccional de superadministradores para serializar altas/bajas y proteger al último. Cliente sin acceso. |
| `administrativeAudit` | Actor, destinatario, acción, motivo codificado, solicitud y fecha. No guarda fotos, correo, número de carnet, texto del reporte, IP ni token. El cliente no puede escribir ni borrar registros. |
| `verificationCleanup` | Cola privada: ruta, generación, intentos, próximo reintento y arrendamiento del trabajo. Cliente sin acceso. |

El rol y la verificación son independientes: convertir a alguien en admin no lo aprueba. Para administrar se exige rol administrativo, aprobación y ausencia de suspensión. Las operaciones leen el estado actual en Firestore, sin confiar en roles del token ni en controles de Flutter.

La proyección `datingAllowed` es parte del contrato de servidor, no un segundo mecanismo de aprobación del cliente. Toda modificación futura del estado deberá utilizar estas operaciones transaccionales. No se deben editar manualmente solo uno de los documentos de autoridad/proyección.

## Backend confiable local

Implementación en `tool/backend`. El adaptador de arranque exige proyecto `demo-*` y comprueba el hub, Auth, Firestore y Storage vinculados a loopback. Configura los tres hosts de emuladores explícitamente; rechaza hosts incompatibles y no tiene fallback ADC/remoto. La prueba confirma que rechaza un proyecto real.

El proceso HTTP escucha únicamente en `127.0.0.1:7360`. Flutter utiliza el proxy del mismo origen `http://127.0.0.1:7357/__demo/api/`; la CSP y guardia del navegador no añadieron destinos externos. Se verifica el ID token mediante Admin SDK con comprobación de revocación; la identidad del actor procede del token, nunca del cuerpo. Se rechazan campos inesperados, orígenes ajenos, cuerpos grandes y exceso de solicitudes. Respuestas privadas con `Cache-Control: no-store`; errores sin excepciones internas o información del carnet.

Operaciones disponibles:

- Provisionar la cuenta propia como user pendiente, de forma idempotente; nunca promover o aprobar.
- Iniciar solicitud, subir imagen y retirar solicitud propia pendiente. Rechazados pueden iniciar otra. No se sustituye silenciosamente un carnet ya presentado.
- Revisar solicitudes, descargar un carnet pendiente por ID y aprobar/rechazar con motivos controlados. No hay autoaprobación ni autorrevisión; un documento resuelto deja de poder revisarse aunque su borrado esté reintentándose.
- Suspender/restaurar cuentas. Un admin no puede suspender otro administrador; un superadmin puede gestionar esos casos, conservando la protección del último superadmin y prohibiendo actuar sobre sí mismo.
- Gestionar roles, exclusivamente como superadmin, sin modificar el propio rol. Las transacciones concurrentes no pueden eliminar a todos los superadministradores.
- Consultar estado administrativo limitado por UID, listar reportes pendientes y resolver reportes sin autorrevisión.

Rutas: `POST account/provision`, `verification/begin`, `verification/upload/{id}` (binario), `verification/withdraw`, `verification/decide`, `administration/role`, `administration/suspend`, `administration/report`; `GET verification/requests`, `verification/document/{id}`, `administration/reports`, `administration/account/{uid}`. Todos requieren Bearer ID token. No hay ruta HTTP de bootstrap ni de ejecutar la limpieza arbitrariamente.

El wrapper actual es deliberadamente exclusivo de emuladores. Para producción se necesitará otro despliegue revisado, con validación de tokens firmados, IAM, HTTPS, monitorización y un procedimiento inicial de administración aprobado. Esta fase no lo desplegó.

## Protección de citas y archivos existentes

Las cuentas sin autorización explícita no leen Descubrir, swipes, matches ni mensajes anteriores, ni crean mensajes o recibos. Cambiar rol, aprobación, suspensión o `datingAllowed` directamente desde un cliente queda denegado. No se abrió lectura de documentos privados `users` de otros estudiantes.

Flutter añade una barrera mínima de estado después de verificar correo y preparar el perfil. Una cuenta pendiente puede iniciar sesión y consultar su situación; la gestión de solicitudes queda preparada en modelos, repositorio y cliente backend para las pantallas de Fase 4. La pérdida de autorización retira también una ruta de chat ya abierta. La seguridad se mantiene en servidor y reglas aunque se manipule o salte esa barrera.

Se conserva la política anterior de historial: un participante que sigue autorizado puede consultar su conversación histórica tras un cierre/bloqueo. El participante suspendido o pendiente pierde su propio acceso. La suspensión no borra mensajes ni cambios voluntarios de visibilidad. Las tarjetas y galerías ajenas exigen además elegibilidad del perfil consultado.

Los archivos de chat pasan por backend para subida, metadatos y descarga. Esto permite comprobar cuenta, pareja, bloqueos, mensaje, tipo y tamaño sin exceder las dos consultas cruzadas de Storage. La subida cliente directa y la lectura de metadatos por SDK quedan denegadas; obtener metadatos Firebase podía generar un token de descarga. Se mantiene la limpieza del propietario para subidas no comprometidas, con estado de acceso vigente. El servicio Flutter conserva sus validaciones de contenido y la protección ante cambio de sesión.

Referencia del límite: [documentación oficial de Firebase Rules](https://firebase.google.com/docs/rules/rules-behavior#security_rule_limits).

La migración añade miembros validados a los medios existentes y revoca sus tokens. Se encontró una particularidad real del emulador: borrar `firebaseStorageDownloadTokens` como metadata no elimina su lista interna; eliminar el último token por su API lo regenera. El adaptador demo reescribe condicionalmente los mismos bytes mediante GCS, conservando contenido y tipo y creando un objeto sin tokens. No utiliza la API Firebase de metadatos para volver a generarlos. Las siete URLs anteriores de chat comprobadas respondieron **403 sin sesión**. Hay una regresión específica que comprueba token real, revocación y conservación exacta de bytes.

## Carnets y retención

Entrada limitada a 5 MiB. Solo PNG/JPEG/WebP: se comprueba firma, se decodifica realmente con sharp, se limitan píxeles (16 millones), se rechaza contenido animado/multipágina y se recodifica como PNG para eliminar metadatos/EXIF. La extensión y el MIME enviados por el cliente no constituyen autorización ni prueba de formato. HTML, SVG, vacío y exceso se rechazaron en pruebas.

El servidor crea la solicitud antes del objeto. Si la subida/finalización falla, se rechaza y se programa limpieza; una subida interrumpida queda identificada por su solicitud y se recupera al expirar. No se crean rutas arbitrarias ni se sobrescribe el carnet de otro intento.

Política implementada para imágenes:

1. Aprobación, rechazo o retiro encolan borrado inmediato; desde la resolución ya se deniega revisión del carnet.
2. El worker corre cada cinco segundos en el backend local. Usa arrendamiento y generación del objeto; un 404 se considera eliminación completada.
3. Los fallos incrementan contador y reintentan con demora exponencial, con tope de un día. No se registran excepciones con datos sensibles. Si el backend se detiene, la cola permanece para el siguiente arranque.
4. Solicitudes pendientes abandonadas expiran a las 24 horas y también se limpian. Tras el borrado se retiran ruta y generación de la solicitud y se conserva únicamente su estado/fecha/motivo y auditoría mínima.

Las 24 horas son una política inicial del demo, a confirmar con el docente/institución. La retención de metadatos de decisiones y auditoría todavía necesita una política institucional explícita; no se activaron TTL ni purgas de esos registros. Para producción deben añadirse paginación/índices del worker, alertas de reintentos persistentes, supervisión y reconciliación periódica de objetos escritos fuera del protocolo. El borrado del carnet no depende de que el usuario abra la app.

## Migración y primer superadministrador demo

`node tool/demo/migrate-phase3.mjs --approve-synthetic-fixtures` verifica UID y correo exactos de Ana, Bob y Carla demo. Solo esas tres fixtures se aprueban explícitamente si no tenían estado; una ejecución posterior conserva suspensiones y decisiones existentes. No recorre ni aprueba cuentas reales. Conserva perfiles, preferencias, swipes, matches y contenido multimedia. No ejecutar seed sobre el estado manual que se quiera conservar.

Bootstrap consumido una vez en este demo:

```powershell
node tool/demo/bootstrap-superadmin.mjs --create-demo-superadmin
```

UID reservado `demo_superadmin`, correo `superadmin@demo.test`, contraseña sintética `DemoTinder2026!`. Se comprueba la identidad, se crean autoridad y registro en una transacción y se registra `synthetic_demo_only`. La aprobación inicial pertenece exclusivamente a esa identidad sintética de demostración. Una segunda ejecución no reinicializa ni recupera privilegios: falla si ya existen autoridad o registro.

`node tool/demo/prepare-phase3-pending.mjs` prepara `pendiente@demo.test`, misma contraseña demo, sin aprobarla. Su sesión real Web mostró únicamente el estado pendiente y cerrar sesión, sin funciones de citas. Todavía no existen dashboards ni formulario definitivo de carnet.

## Pruebas finales

| Comprobación | Resultado | Evidencia |
| --- | --- | --- |
| Flutter analyze | Sin incidencias | audit-phase3-analyze-final.log |
| Flutter test | 249 aprobadas, 0 fallidas | audit-phase3-flutter-final.log |
| Regresiones Firebase previas, adaptadas al transporte backend | 148 aprobadas, 0 fallidas | audit-phase3-regression-final.log |
| Nuevas pruebas adversariales de backend y reglas | 28 aprobadas, 0 fallidas | audit-phase3-backend-final.log |
| Guardia, Auth, SDK y fixtures demo | 10 aprobadas, 0 fallidas | audit-phase3-demo-final.log |
| Web demo | Compilación correcta | audit-phase3-web-final.log |
| Android debug | Compilación correcta; sin ejecución | audit-phase3-android-final.log |
| HTTP con cuatro sesiones Auth locales | Correcto | audit-phase3-http.log |
| URLs antiguas de chat sin sesión | 7 rechazadas, 0 descargables | audit-phase3-revoked-tokens.log |
| Nota de voz física anterior | Bytes, duración y señal conservados | audit-phase3-voice-preserved.log |

Nuevos casos: ausencia de estado, pendiente/rechazado/suspendido/malformado, autoaprobación, autorrevisión, escalada mediante claims o escrituras, roles independientes de verificación, carnets ajenos incluso por SDK administrativo cliente, último superadmin, demociones concurrentes, administrador suspendido, chats anteriores, denegación de subidas directas, token real revocado, decodificación de documentos, retiro, expiración, recuperación tras interrupción y reintentos de limpieza. Las reglas también protegen el espejo de acceso del perfil.

Las suites destructivas usaron `demo-tinder-phase3-tests`, Auth 9199, Firestore 8188 y Storage 9298. El demo principal no se vació. Hubo fallos intermedios corregidos: presupuesto de reglas, bucket distinto entre SDK y backend en tests, respaldos Dart analizados como código, comparación UTC/local en un test, cierre abrupto de Node y revocación real de tokens del emulador. Los resultados de la tabla corresponden a ejecuciones finales.

Prueba real de navegador: acceso pendiente bloqueado y sesión de Bob aprobada; foto histórica del chat visible y reproducción de la nota física anterior a 0:07/0:10 a través del backend privado. La prueba HTTP comprobó rechazo sin sesión, rechazo de escalada, creación de solicitud pendiente, archivo no publicado privado, suspensión temporal de Ana, denegación del chat y restauración en finally, sin cambiar isActive. Bob recibió bytes idénticos a los subidos.

No se afirma ejecución Android, validación del carnet real de un estudiante, certificación de todos los navegadores ni despliegue de producción. El APK normal conserva su arranque normal: no instalarlo para pruebas aisladas; primero preparar un arranque Android demo.

## Dependencias y riesgos pendientes

- sharp se fijó en 0.35.5 y gRPC en 1.14.6, versiones corregidas según las alertas consultadas. Se aplicaron correcciones npm compatibles sin --force. La auditoría final aún informa 7 alertas (3 altas y 4 moderadas), entre firebase-tools/chokidar/braces y dependencias transitivas. No se forzó una migración incompatible del CLI. Registro `audit-phase3-npm-final.json`. Revisarlas antes de preparar un backend de producción; la auditoría del demo no equivale a certificación de dependencias.
- **Fotografías de perfil:** conservan las URLs con token de fases anteriores. La suspensión deniega su SDK, pero una URL ya entregada puede descargarse sin sesión. Esta fase protege sin tokens carnets y chat, no resuelve ese riesgo heredado de las fotos de perfil. Antes de integrar para producción, migrar lecturas/subidas de perfil a acceso autenticado, sustituir punteros URL cuando corresponda y revocar tokens. No se debe presentar todo Storage como libre de URLs bearer.
- **Medios de chat:** el backend comprueba MIME declarado, límites y autorización; la validación fuerte de bytes sigue en el cliente. La prueba documenta que un cliente manipulado puede declarar MIME permitido con contenido inválido. También se conserva la limitación Firestore/Storage: mediaPath puede existir sin objeto. Hace falta validación de contenido en servidor, finalización privilegiada del mensaje y reconciliación antes de prometer integridad completa. Los carnets sí se decodifican y recodifican en servidor.
- La proyección de acceso debe mantenerse exclusivamente mediante transacciones del backend. La edición manual de documentos con Admin SDK puede romper el contrato; limitar IAM y definir controles operativos antes de producción.
- El índice de Descubrir conserva IDs de perfiles voluntariamente visibles; las tarjetas no autorizadas se deniegan al consultar. Conviene proyectar elegibilidad en el índice para evitar lecturas rechazadas cuando crezca la cantidad de solicitudes pendientes.
- Los emuladores aceptan tokens sin firma por diseño y su API administrativa es para desarrollo local. Loopback y claves demo no constituyen un sistema administrativo desplegable a Internet. El wrapper de este repositorio se niega a arrancar contra producción.
- El registro del backend mostró `MaxListenersExceededWarning` en un `PassThrough` del transporte SDK durante las comprobaciones de descarga. Las comprobaciones de contenido y autorización pasaron; falta prueba de carga y seguimiento del consumo de recursos antes de producción. No se ha confirmado una fuga de memoria con esa advertencia aislada.

## Archivos de esta fase

- `firestore.rules`, `storage.rules`, `firebase.phase3-tests.json`.
- `lib/features/verification/account_access.dart`, `verification_repository.dart`, `backend_client.dart`, `university_gate.dart`.
- `lib/features/auth/auth_gate.dart`, `auth_service.dart`; `lib/features/chat/chat_service.dart`.
- `tool/backend/emulator.mjs`, `verification.mjs`, `server.mjs`, `chat-upload.mjs`, `chat-read.mjs`, `private-object.mjs`.
- `tool/demo/migrate-phase3.mjs`, `bootstrap-superadmin.mjs`, `prepare-phase3-pending.mjs`, `phase3-http-check.mjs`, `check-revoked-tokens.mjs`, `chat-api.mjs`.
- `tool/demo/server.mjs`, `seed.mjs`, `firestore.demo.rules`, `inspect-voice.mjs`, `phase2-evidence.mjs`.
- `tool/package.json`, `tool/package-lock.json`, `tool/rules.test.mjs`, `tool/phase3.test.mjs`.
- `test/university_access_test.dart`, `test/auth_service_test.dart`, `test/email_verification_test.dart`.
- Este informe, guía manual, respaldos y evidencias. Los otros archivos que muestra Git incluyen modificaciones preservadas de fases anteriores.

## Inicio de Fase 4 y recomendación

1. Resolver las brechas heredadas de URLs de perfil y medios de chat antes de considerar integración de producción. Completar la revisión de dependencias y el diseño del despliegue seguro; no reutilizar el bootstrap demo.
2. Confirmar criterios de aprobación Univalle Cochabamba, motivos de rechazo, plazo de revisión, apelaciones y retención de metadatos/auditoría. El límite de 24 horas puede necesitar ajuste institucional.
3. Construir carga/estado/reenvío/retiro sobre VerificationClient y VerificationRepository. El formulario sube bytes al backend, nunca obtiene downloadURL de un carnet. Mostrar consentimiento e instrucciones sin pedir información innecesaria.
4. Construir dashboards con sus propias barreras reactivas de rol y permisos de servidor ya implementados: bandeja de solicitudes, visor privado en memoria, decisión, reportes, suspensión y gestión de roles. Revocar y limpiar vistas al perder rol o sesión.
5. Añadir paginación, monitorización, despliegue/planificador confiable y pruebas de volumen; probar en Chrome/Edge externos y en un Android conectado exclusivamente al entorno demo.

La base está preparada y comprobada para continuar Fase 4 en demo. **No recomiendo integrarla ni desplegarla todavía en producción**, por las brechas y preparación operativa descritas.

Demo activo: http://127.0.0.1:7357/__demo/start.html . Auth 9099, Firestore 8088, Storage 9198, backend 7360 y Web 7357, todos en 127.0.0.1. Estado real de SDK registrado en `audit-phase3-status-final.json`. Ana/Bob/Carla conservan sus datos; la cuenta pendiente y el superadministrador son sintéticos. El backend debe permanecer activo para cargar medios de chat.

Exportación final conservada en `build/phase3-fixtures-secure-final` (registro `audit-phase3-export-secure-final.log`). Para restaurarla, iniciar los emuladores principales con ese import y ejecutar la migración idempotente de Fase 3; no volver a sembrar ni ejecutar el bootstrap ya consumido. Registros de procesos activos: `audit-phase3-web-server.log`, `audit-phase3-backend-server-final.log`.
