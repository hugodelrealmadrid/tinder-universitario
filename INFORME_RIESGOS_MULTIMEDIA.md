# Seguimiento de los tres riesgos multimedia

Fecha: 13 de octubre de 2026. Trabajo realizado exclusivamente en el worktree de pruebas.

**Recomendación: todavía necesita trabajo antes de integrar.** Se corrigieron comportamientos del cliente y se ampliaron las pruebas, pero ninguno de los tres riesgos queda eliminado frente a clientes manipulados o pérdida del almacenamiento local. No se modificó Firebase de producción, main ni el proyecto original; no hubo commit, push, merge, reset ni deploy.

## Gravedad real y solución propuesta

| Riesgo | Gravedad y alcance | Estado tras esta fase |
| --- | --- | --- |
| URL permanente con token | Alta para confidencialidad si el enlace se filtra. Es una credencial de acceso compartible: quien posee el token puede descargar sin una sesión Firebase. Conocer solo la ruta no concede acceso. No se encontró acceso anónimo por enumerar rutas. Un participante autorizado también puede copiar y reenviar los bytes; eso no lo impiden las reglas. | El cliente oficial deja de obtener y consumir download URLs. Su nueva descarga requiere un ID token y está verificada con el emulador. Los tokens ya existentes, la extracción deliberada por clientes autorizados y las URLs antiguas siguen pendientes. |
| Contenido distinto del MIME | Media para errores e integridad; potencialmente alta para estabilidad por imágenes enormes o archivos preparados para abusar de los decodificadores. Declarar HTML como imagen no hace que esta UI ejecute HTML: usa Image.memory y un reproductor de audio, no un WebView. | Mitigado al enviar y recibir. Las reglas siguen comprobando tamaño y MIME declarado; no decodifican contenido. Un cliente modificado puede evitarlas y los controles de audio son de estructura, no decodificación completa. |
| Mensaje sin objeto y huérfanos | Media para integridad, duplicados, almacenamiento y costes. La ruta canónica impide usarlo para referenciar arbitrariamente archivos de terceros; puede producir mensajes rotos o archivos nunca publicados. | El cliente normal verifica el objeto antes de publicar y reconcilia fallos con el servidor. Existe registro local para reintentar limpieza. Firestore sigue aceptando una referencia canónica sin objeto; no hay atomicidad entre servicios ni reconciliación de servidor. |

## Correcciones implementadas

**Descarga autorizada compartida por Web y Android.** `ChatAuthenticatedDownload` usa la API REST de Storage con `Authorization: Firebase <ID token>` y `alt=media`. No llama a getDownloadURL ni getData y no añade `token=` a la URL. El endpoint está limitado al host oficial HTTPS o a hosts locales de emulación; se rechazan rutas externas, traversal y redirecciones. Se limita el cuerpo, incluso sin Content-Length, y se establecen tiempos de espera. Falta de sesión, HTTP de error, archivo vacío y exceso de tamaño no entregan bytes al widget. El servicio comprueba tamaño/MIME mediante metadata y rechaza cambios de usuario durante la descarga.

La API y los datos siguen siendo compatibles con Image.memory y BytesSource. No se revocó ningún token ni se cambió ninguna configuración de producción. La prueba existente de download URL continúa reproduciendo HTTP 200 sin sesión; las nuevas pruebas REST sin download token devuelven 200 para participantes y 403 para terceros y anónimos. Son dos mecanismos distintos, y proteger uno no elimina el otro.

**Validación defensiva de contenido.** Antes de subir y antes de entregar bytes recibidos al widget se verifican formato, MIME y límites de 5 MiB/15 MiB. JPEG/PNG/WebP deben tener su firma correcta y decodificar una imagen; se limita a 4096 por dimensión y 16 millones de píxeles antes de obtener un frame. MP3 necesita frames completos; WAV requiere contenedor RIFF/WAVE y chunks de formato/datos; M4A requiere estructura de boxes con pista de audio y datos y rechaza pista de vídeo; OGG exige páginas completas y cabecera Opus/Vorbis. Se rechazan HTML renombrado, firmas incompletas, contenedores truncados y combinaciones de MIME/tipo incorrectas.

Los controles de audio NO verifican todas las muestras, checksums, códecs ni todos los tags posibles. Las fixtures MP3/M4A/OGG de pruebas ejercitan estructura; no prueban que esos archivos sintéticos sean reproducibles. Los formatos legítimos atípicos pueden ser rechazados. La prueba PNG utiliza una imagen real generada por el motor, y la prueba de dimensiones utiliza una imagen válida de 5000×1.

El selector de audio ahora solicita un stream, comprueba el tamaño declarado y corta al alcanzar el máximo real durante la lectura. Se evita cargar un archivo arbitrariamente grande con withData. La imagen seleccionada también se comprueba por tamaño antes de leer sus bytes. El procesado interno de ImagePicker y el consumo total de los decodificadores siguen necesitando pruebas reales.

**Publicación y limpieza más seguras.** Antes de subir se comprueba el match y el bloqueo propio y se guarda un registro local sin bytes ni credenciales. Si falla ese registro, no comienza la subida. Después de subir se consulta metadata y se exige que tamaño y MIME coincidan antes de crear el mensaje. Storage permite al propietario verificar su objeto aún no publicado; el destinatario y terceros no pueden leerlo. Se conservan las restricciones sobre sobrescritura y borrado de archivos publicados.

Ante un error se consulta el mensaje mediante Source.server. No se acepta una respuesta de caché o con escrituras pendientes. Si se confirma la publicación, se conserva el archivo y se reconoce el éxito, evitando el reintento innecesario. Si se confirma que no hay mensaje, se intenta borrar el objeto. Si no se puede leer el servidor o limpiar, se conserva el registro y no se borra a ciegas. La UI distingue el envío no confirmado y explica que reenviarlo puede duplicarlo. Un fallo al borrar el registro de un mensaje ya confirmado no convierte el envío en un falso error; el registro se podrá reconciliar más tarde. La idempotencia completa entre reenvíos tras un estado ambiguo sigue necesitando servidor.

El registro usa SharedPreferencesAsync, separado por proyecto, bucket y usuario, con una clave por operación para evitar perder entradas por un índice compartido. Al abrir un chat se reconcilian entradas de más de 30 minutos. Se ignoran registros corruptos, de otro usuario o con rutas inválidas. No se tocan subidas activas del mismo proceso. El margen de 30 minutos reduce carreras entre pestañas, pero no es un lease distribuido. Esta recuperación es best effort: no garantiza persistencia ante cierre abrupto, limpieza de datos, pérdida del dispositivo o borrado administrativo del match.

## Protecciones de servidor necesarias

1. **Privacidad estricta:** servir archivos mediante un endpoint que verifique Firebase Authentication, pertenencia al chat y política de acceso en cada solicitud. Evitar URLs permanentes compartibles. Quitar/revocar tokens antiguos y evitar que nuevos objetos finalizados vuelvan a tenerlos; restringir el acceso directo a metadata/descarga del bucket final. Una descarga autenticada no puede impedir que un destinatario copie el contenido. App Check y límites de uso ayudan contra abuso, pero no sustituyen autorización.
2. **Validación confiable:** subir a un área privada de cuarentena y validar en un proceso de servidor con decodificadores limitados en tiempo/memoria. Verificar contenido real, dimensiones, duración, pistas y códecs; considerar recodificación a formatos conocidos para Web/Android. Publicar únicamente archivos aprobados. Los clientes no deben poder escribir por sí mismos un estado «verificado».
3. **Integridad y limpieza:** usar un ID de operación estable, estados y leases de servidor. El servidor verifica el objeto/generación y crea o finaliza el mensaje de forma idempotente, comprobando match/bloqueos en una transacción Firestore. Denegar creación directa de mensajes multimedia por clientes cuando esa ruta exista; mantener el envío de texto. Añadir reconciliación periódica, reintentos y limpieza de objetos abandonados, evitando borrar operaciones en curso. Aunque centralizarlo reduce mucho las carreras, no convierte Firestore y Storage en una única transacción: sigue haciendo falta reconciliación.

Estas protecciones son compatibles con ambos clientes: UI y reproductor reciben bytes y el mensaje mantiene su identidad. Al integrar un backend, se debe adaptar la implementación de ChatMediaStore a ese endpoint de confianza; el descargador actual restringe deliberadamente sus hosts a Storage y emuladores. No se implementó un backend ficticio ni se endurecieron reglas de una forma que rompiese el flujo actual sin ese backend. Ninguna de estas acciones se desplegó.

## Verificaciones

| Comprobación | Resultado final | Evidencia |
| --- | --- | --- |
| flutter analyze | Sin incidencias | audit-phase2-result-analyze.log |
| flutter test | 217 aprobadas, 0 fallidas | audit-phase2-result-tests.log |
| Reglas + REST Firebase demo | 142 aprobadas, 0 fallidas, 0 omitidas | audit-phase2-rules.log |
| Compilación Web | Compilación correcta | audit-phase2-result-web.log |
| Compilación Android | Compilación correcta: APK debug generado, BUILD SUCCESSFUL (3m43s) | audit-phase2-result-android.log |

Se agregaron 33 pruebas Flutter y dos pruebas Firebase respecto al final de la auditoría anterior. Cubren transporte autorizado, límites por stream, contenido falso/truncado, imágenes sobredimensionadas, lectura del receptor, objeto no confirmado, fallo del registro, publicación ambigua, conservación ante fallo de lectura, limpieza/reintento tras reiniciar, separación de usuarios/proyectos y corrupción/concurrencia del registro. El resto de la suite sigue cubriendo las funciones existentes.

Las pruebas de Firebase solo usan demo-tinder-universitario y hosts locales 8088/9198. Sus ID tokens de REST son fixtures sin firma válidas únicamente para el emulador; no son credenciales reales. La primera prueba REST falló por un bucket incorrecto de la fixture y pasó al usar el bucket del entorno. Los fallos iniciales de análisis correspondían a la interfaz nueva y a avisos de estilo y se corrigieron. Los logs intermedios se conservan; los resultados finales están en la tabla.

## Pruebas manuales antes de integrar

**Preparación obligatoria:** usar una inicialización de Firebase explícitamente demo con Auth, Firestore y Storage emulados y dos cuentas/fixtures de chat. El main actual conserva la configuración real del proyecto: NO ejecutar ese arranque para estas pruebas. El define CHAT_STORAGE_ORIGIN solo selecciona el endpoint de la descarga HTTP; no convierte Firebase Auth/Firestore/Storage en emuladores por sí solo. Configurar todos los servicios del SDK también. La descarga rechaza el endpoint oficial cuando el proyecto del SDK empieza por demo-.

Para Web, el endpoint HTTP es http://127.0.0.1:9198. En el emulador Android habitual es http://10.0.2.2:9198. Se selecciona con `--dart-define=CHAT_STORAGE_ORIGIN=...`, además de la inicialización demo. En un dispositivo físico hace falta un túnel seguro/port forwarding que alcance los emuladores; no ampliar a producción ni quitar la lista de hosts permitidos para salir del paso.

1. Dos cuentas: enviar, recibir y ampliar JPG/PNG/WebP; enviar y reproducir MP3, M4A/AAC, WAV y OGG Opus/Vorbis reales. Probar pausa, reanudación, fin y repetición en Android y navegadores objetivo. Incluir archivos de distintos teléfonos/encoders y tags habituales para detectar falsos rechazos del validador.
2. Inspeccionar red en Web: no debe haber download URLs con token en el chat; sí Authorization en la descarga. Probar sesión ausente/cambiada, tercero, expiración de ID token y errores. Comprobar CORS del endpoint y permisos de red Android. Si se habilita App Check, integrar su token también en la petición REST antes de hacer obligatoria su validación.
3. Cancelar selectores; seleccionar archivos vacíos, MIME/extensión falsos, truncados, sobredimensionados y en el límite. Revisar mensajes de error, memoria, fluidez y que no quede mensaje publicado ni subida iniciada tras rechazo.
4. Desconectar la red y cerrar durante subida, después de subida y durante publicación. Volver con la misma cuenta: los mensajes confirmados no deben duplicarse ni perder el archivo. Tras superar el margen de recuperación, comprobar la limpieza de huérfanos y la conservación del registro cuando sigue sin red.
5. Dos pestañas y cambio de cuenta: no limpiar una subida activa ni archivos del otro usuario. Probar almacenamiento local deshabilitado, cuota agotada y eliminación del registro; esta última debe considerarse un caso que necesita limpieza de servidor.
6. Bloquear y deshacer match durante cada fase. Deben denegarse archivos/mensajes/recibos nuevos y conservarse el historial según la política existente. Comprobar limpieza del propietario tras el cierre.
7. Al preparar la solución de servidor, repetir con llamadas directas que omitan el cliente: falso MIME, mensaje sin objeto y URL antigua filtrada. Hoy las pruebas reproducen que esas tres limitaciones persisten; no se puede aprobar privacidad estricta únicamente por una suite verde.

## Archivos y conservación del trabajo anterior

Nuevos: lib/features/chat/chat_authenticated_download.dart, lib/features/chat/chat_media_validation.dart, lib/features/chat/pending_chat_uploads.dart, test/chat_authenticated_download_test.dart, test/chat_media_validation_test.dart, test/pending_chat_uploads_test.dart y test/chat_media_fixtures.dart.

Modificados en esta fase: lib/features/chat/chat_service.dart, lib/features/chat/chat_media_widget.dart, lib/features/chat/chat_screen.dart, storage.rules, test/chat_media_test.dart, tool/rules.test.mjs, pubspec.yaml y pubspec.lock. Las adiciones de dependencias son http (ya transitiva, ahora directa), shared_preferences y la interfaz de preferencias para sus pruebas.

Documentación/respaldo: INFORME_RIESGOS_MULTIMEDIA.md y audit-phase2-preexisting.patch. Se conserva INFORME_AUDITORIA.md como informe histórico. Se guardó también la versión previa de la prueba multimedia en un log local. Se mantuvieron los cambios anteriores; firebase.json y tool/package-lock.json no se editaron y las versiones previas del lock se conservaron al agregar las nuevas dependencias. Los artefactos/logs de compilación quedan ignorados por Git.

Referencias: [Firebase: autorización de Storage](https://firebase.google.com/docs/storage/security), [reglas y metadata de Storage](https://firebase.google.com/docs/reference/security/storage) y [SharedPreferences: persistencia y límites](https://pub.dev/packages/shared_preferences/versions/2.5.6). Las conclusiones de explotación y transporte se basan en las pruebas locales, no en cambios de producción.
