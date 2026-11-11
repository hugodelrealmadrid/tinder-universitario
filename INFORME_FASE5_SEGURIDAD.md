# Fase 5 — Seguridad y validación final

Trabajo realizado exclusivamente en `C:\Users\HP\Desktop\tinder_universitario_pruebas`. No se hizo commit, push, merge, reset ni deploy, ni se utilizó Firebase de producción. Los cambios de fases anteriores se conservaron; antes de editar se guardaron `audit-phase5-preexisting.patch` y `build/phase5-before.zip`. El respaldo de datos de Fase 4 permanece en `build/phase4-fixtures-final`.

## Diagnóstico y correcciones

### Fotografías de perfil: riesgo alto de divulgación por token

Una URL con token conocido permitía leer sin sesión y sobrevivía a una suspensión. Además, permitir obtener metadatos de Storage permitía recuperar URLs con token. Ocultar la URL en Flutter no solucionaba ese acceso.

Ahora Firestore contiene referencias internas `profile_photos/{uid}/{id}`, nunca URLs de descarga. Storage deniega todas las operaciones del SDK cliente, también metadatos y borrado. El backend entrega bytes autenticados con `Cache-Control: no-store` y comprueba aprobación y suspensión de lector y propietario. Para otras personas aplica las mismas reglas de Firestore: consulta `discoveryCards` o `matchProfiles` con el ID token del solicitante y verifica que la referencia esté en la proyección autorizada. Descubrir solo permite la foto principal; la galería requiere el acceso al perfil del match. Se conservan filtros, visibilidad, reciprocidad y bloqueos existentes.

Cada subida validada genera un registro privado en `profilePhotoAssets` con propietario, ruta, tamaño, MIME, SHA-256, generación de Storage y estado. `profilePhotoManifests` limita las referencias que un cliente puede guardar en su perfil. Ningún cliente, incluido un administrador, puede falsificar esos registros. No se puede eliminar una foto todavía referenciada. El cliente actualiza primero el perfil y solicita después el borrado privilegiado.

La interfaz carga bytes autenticados en una imagen nativa de propiedad del widget, sin `NetworkImage`, URL alternativa ni `ImageCache` global. Libera esa imagen al salir y revalida al volver del segundo plano. Una URL antigua falla de forma cerrada hasta ser migrada; no se intenta descargarla anónimamente.

### Medios del chat: riesgo alto de referencias sin objeto y contenido falsificado

La validación anterior de cabeceras/MIME y la validación del cliente no eran una garantía de integridad para clientes modificados. Ahora el servidor decodifica realmente el contenido antes de aceptar la subida:

- JPG, PNG y WebP: decodificación completa con Sharp, MIME exacto, una sola página, máximo 4096 por dimensión y 16 millones de píxeles; máximo 5 MiB.
- MP3, WAV, M4A/MP4 y OGG: FFprobe y FFmpeg decodifican el audio completo; se rechazan formatos incoherentes, truncamientos, playlists, vídeo, errores de decodificación, más de una pista de audio y excesos. Máximo 15 MiB y 10 minutos de audio decodificado. Las notas de voz mantienen el límite cliente de 60 segundos.
- Decodificador sin shell, protocolos limitados a archivos y pipes, referencias externas de MOV desactivadas, dos validaciones simultáneas, tiempo y salida acotados. Los temporales están en `build` de esta copia y se eliminan al finalizar.

El backend reserva `chatUploads/{matchId}.{messageId}`, escribe un objeto inmutable, revoca tokens y registra generación/hash/tamaño/tipo/duración. El cliente sigue publicando el mensaje en Firestore; **las reglas solo lo permiten si existe una prueba de subida confiable, lista y vigente**, con ruta, remitente y tipo exactos. No es una transacción distribuida entre Storage y Firestore: se utiliza staging, prueba privilegiada inmutable y reconciliación. No se declara atomicidad inexistente.

La lectura valida participantes canónicos, aprobación y ausencia de suspensión de ambos, match activo y bloqueos en ambas direcciones; además comprueba asociación al mensaje, generación, MIME, tamaño y SHA-256. Revalida autorización después de descargar. Un archivo sin mensaje solo está disponible temporalmente a quien lo subió. Nadie puede borrar por SDK y el backend no borra medios publicados.

**Cambio deliberado de política:** deshacer/bloquear un match revoca sus medios; el historial de texto permanece conforme a las reglas anteriores. La suspensión o pérdida de aprobación de cualquiera de los participantes también bloquea lectura/publicación de mensajes anteriores. Flutter retira reproductores y fotografías al quedar inactivo el match y cierra el visor asociado cuando se retira su mensaje.

### Archivos huérfanos y fallos parciales

Las reservas listas sin publicación vencen en una hora. Una tarea persistida permite reintentar eliminaciones; un lease evita duplicar trabajo simultáneo. El worker consulta vencimientos por páginas de 50, conserva archivos efectivamente publicados y retira el manifiesto antes de borrar. También recorre publicaciones por páginas para detectar fotos cuya referencia se quitó después del staging, incluso si el cliente se cerró antes de pedir borrado. El borrado es condicional por generación. Los fallos se reprograman, sin volver a habilitar la publicación del archivo.

El worker local se ejecuta cada cinco segundos. Esa frecuencia no garantiza borrado físico instantáneo y no sustituye un scheduler supervisado en producción. La limpieza heredada de carnets y su retención institucional no se declaran resueltas por este cambio de medios.

## Migración ejecutada y necesaria

Se ejecutó únicamente `node tool/demo/migrate-phase5.mjs --revoke-demo-tokens`, con backend detenido durante la migración y comprobaciones obligatorias de proyecto `demo-` y puertos locales. Resultado (`audit-phase5-migration.json`): **3 fotografías y 9 archivos de chat**, **3 tokens revocados y sus URLs denegadas**, cero cuarentenas y cero referencias ausentes. Se preservaron bytes y roles; no se aprobaron cuentas. Se transformaron simultáneamente referencias de `users`, `discoveryCards` y `matchProfiles`, creando pruebas y manifiestos privados. Después se cargaron las reglas estrictas en el emulador y se reinició el backend.

La verificación independiente `tool/demo/phase5-status.mjs` compara las generaciones y SHA-256 actuales, revisa manifiestos y prueba todos los tokens conservados en el respaldo Fase 4, sin imprimirlos. Confirmó tres referencias de perfil, nueve archivos de chat íntegros y tres tokens antiguos denegados.

Los migradores antiguos de Fases 2 y 3 abortan con instrucciones de actualización: ya no pueden restaurar URLs públicas o excepciones demo. El seed ahora exige explícitamente un demo nuevo y vacío; registra referencias privadas sin tokens. No se ejecutó sobre estos datos ni se validó un seed completo nuevo en esta fase.

**Procedimiento futuro para datos reales — solo diseñado, NO ejecutado:**

1. Exportar y verificar respaldo, inventariar objetos/referencias/tokens sin incluir secretos en logs. Preparar backend e IAM, índices, decodificador aislado y cliente compatible.
2. Establecer mantenimiento de escrituras/subidas. El script local no es una migración concurrente de producción y rechaza proyectos reales. Preparar otro migrador privilegiado, con simulación y revisión previa.
3. Validar todos los objetos existentes. Resolver ausencias/cuarentenas antes de habilitar perfiles; no presentar objetos inválidos como válidos. Crear pruebas con generación/hash y manifiestos; actualizar las tres proyecciones de perfil.
4. Revocar **todos** los valores de `firebaseStorageDownloadTokens` mediante API privilegiada y condiciones de generación/metageneración; verificar individualmente las antiguas URLs sin sesión. En el emulador fue necesaria la reescritura condicional de los mismos bytes porque su manejo de tokens difiere del servicio real. No asumir que borrar un campo en Firestore revoca Storage.
5. Aplicar reglas privadas, exigir actualización del cliente, comprobar matriz de autorización, limpiar huérfanos y levantar mantenimiento. No conservar una ruta de compatibilidad con URLs públicas. Vigilar reintentos y mantener un rollback que no vuelva a publicar documentos.

Los archivos ya descargados o capturados por una persona autorizada no pueden revocarse retroactivamente. La protección impide nuevas lecturas; no promete borrar copias, memoria o capturas ajenas. Tampoco borra archivos/versiones/backups de producción que aquí no se han inventariado.

## Dependencias

Se conservaron las versiones funcionales de Flutter/Firebase. La auditoría npm inicial tenía 7 alertas (3 altas y 4 moderadas). Se actualizaron dependencias transitivas compatibles mediante overrides de `@opentelemetry/core` 2.8.0 y `gaxios → uuid` 11.1.1, conservando el override gRPC existente. Firebase Admin y Sharp están declarados como dependencias de ejecución.

Resultado npm: **cero alertas conocidas de ejecución** (`npm audit --omit=dev`); **3 altas en herramientas de desarrollo** (`firebase-tools → chokidar → braces`). No se aplicó `audit fix --force` ni una degradación mayor del CLI. El aviso [GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm) afecta `braces <= 3.0.3` y no publicaba versión corregida al revisar. No aceptar patrones/árboles de terceros no confiables para esas herramientas; volver a auditar y actualizar cuando exista una corrección compatible. Cero alertas conocidas no demuestra ausencia de vulnerabilidades.

El decoder Windows es FFmpeg **9.0.2**, de Gyan, proveedor enlazado por [FFmpeg](https://ffmpeg.org/download.html). Archivo verificado con SHA-256 `60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba`. Binarios/temporales excluidos de Git; LICENSE/README conservados. Preparación reproducible desde esta carpeta: `powershell -File tool/setup-media-decoder.ps1`. Si faltan binarios, la aceptación de audio falla de forma cerrada. Para Linux/producción hace falta un empaquetado separado, revisión de licencia y aislamiento nativo de mínimo privilegio; las restricciones de FFmpeg no equivalen a un sandbox del sistema operativo.

Permanece el aviso `MaxListenersExceededWarning` del transporte `teeny-request` del SDK Storage, localizado con `--trace-warnings` en sus streams `PassThrough`. No se ocultó aumentando límites ni se declaró resuelta una fuga. Falta una prueba de carga y seguimiento de memoria a largo plazo.

## Pruebas y evidencia

`flutter pub outdated --json` final revisó 47 paquetes sin versiones actuales retiradas ni marcadas con avisos de seguridad (`audit-phase5-pub-outdated-final.json`). Las compilaciones advierten que varios plugins deberán migrar a Built-in Kotlin para versiones futuras de Flutter; la compilación debug actual terminó correctamente.

Las suites Firebase usan exclusivamente `demo-tinder-phase3-tests` (Auth 9199, Firestore 8188, Storage 9298). Las comprobaciones del demo usan `demo-tinder-universitario` y conservan datos/estados.

| Comprobación | Resultado / evidencia |
| --- | --- |
| `flutter analyze --no-pub` | Sin observaciones en repetición final; `audit-phase5-analyze-acceptance.log` |
| Flutter completo | 271 aprobadas, 0 fallidas; `audit-phase5-flutter-acceptance.log` |
| Reglas existentes | 148 aprobadas, 0 fallidas; `audit-phase5-rules-final.log` |
| Backend/roles/administración | 36 aprobadas, 0 fallidas; `audit-phase5-backend-recheck.log` |
| Nuevas pruebas de seguridad y decodificación | 24 aprobadas, 0 fallidas; `audit-phase5-security-final.log` |
| Demo completo | 10 aprobadas, 0 fallidas en repetición final; `audit-phase5-demo-acceptance-second.log` |
| Integridad y tokens antiguos en demo | Aprobado tras prueba Web; `audit-phase5-status-acceptance.json` |
| Cuentas, roles, carnets, configuración y aislamiento observado | Aprobado; `audit-phase5-isolation-acceptance.json` |
| Compilación Web final | Aprobada, salida `build/demo-web`; `audit-phase5-web-verbose.log` |
| Android debug | Aprobada la entrada final demo, `build/app/outputs/flutter-apk/app-demo-debug.apk`; `audit-phase5-android-demo-final.log`. También compiló la entrada de integración, sin ejecución. |
| Ejecución Android | No aprobada: dos intentos del AVD API 36.1 agotaron recursos o no completaron el arranque. No se ejecutó el flujo ni se comprobó micrófono/audibilidad Android. |

La matriz nueva cubre ausencia de sesión, usuarios pendientes/suspendidos, propietario suspendido, tercero, filtros y visibilidad, bloqueos, galería ajena, token heredado realmente válido antes de revocar, metadatos/tipo falsificados, rutas manipuladas, pruebas/manifiestos falsificados, mensajes sin archivo validado, asociación remitente/ruta/tipo, checks de lectura, objetos sustituidos, formatos reales, tamaños y limpieza con fallo/reintento. Las 36 regresiones incluyen autoaprobación, autoasignación, roles, último superadmin y concurrencia administrativa.

Las 148 pruebas históricas adaptadas ejercitan reglas Firestore y transporte privado de Storage/backend: no se presentan como 148 autorizaciones directas del SDK Storage, ahora completamente denegado. Hay casos nuevos específicos que prueban la denegación SDK incluso para propietario y superadmin. Las fixtures de fotos antiguas se cambiaron por referencias privadas y el caso de historial aprobado ahora declara aprobados explícitamente a ambos participantes; no se relajaron reglas para hacer pasar pruebas.

Hubo ejecuciones intermedias fallidas por fixtures antiguas, sincronización/tamaño del widget de prueba y agotamiento de recursos de Windows (`errno 1450`). Se corrigieron y repitieron; se conservan sus logs. Una consulta de diagnóstico tuvo timeout de revisión automática y pasó al reintentar; no fue un rechazo por inseguridad. La validación final debe leerse de las filas anteriores, sin contar intentos interrumpidos como aprobados.

## Archivos de esta fase

- Reglas/configuración: `firestore.rules`, `storage.rules`, `tool/demo/firestore.demo.rules`, `.gitignore`, `pubspec.yaml`, `pubspec.lock`, `tool/package.json`, `tool/package-lock.json`.
- Backend: nuevos `media-validation.mjs`, `profile-media.mjs`, `media-cleanup.mjs`; actualizados `chat-upload.mjs`, `chat-read.mjs`, `private-object.mjs`, `server.mjs`, todos en `tool/backend/`.
- Flutter: nuevos `lib/features/profile/private_photo_path.dart`, `private_profile_photo.dart`, `lib/main_demo_android.dart`; actualizados `photo_store.dart`, `lib/widgets/app_ui.dart`, `lib/features/discovery/discovery_models.dart`, `lib/features/verification/backend_client.dart`, `lib/features/chat/chat_service.dart`, `chat_screen.dart`, `chat_media_widget.dart`. `lib/features/profile/profile_screen.dart` solo cambió de formato en una asignación, sin cambio de lógica.
- Android demo: `android/app/build.gradle.kts`, `android/gradle.properties`, nuevos `android/app/src/demo/google-services.json`, `AndroidManifest.xml`, `res/xml/demo_network_security.xml`. El flavor `standard` conserva la identidad previa; el demo usa sufijo `.demo`, opciones ficticias y entrypoint con guard obligatorio. Se redujo el heap Gradle anterior de 8 GiB a 2 GiB y los workers a dos para esta computadora.
- Herramientas: `tool/download-ffmpeg.mjs`, `tool/setup-media-decoder.ps1`, `tool/test-media.mjs`, `tool/load-phase5-demo-rules.mjs`; `tool/demo/migrate-phase5.mjs`, `phase5-status.mjs`, `prepare.mjs`, `seed.mjs`, migradores retirados Fases 2/3 y `verify.test.mjs`.
- Pruebas: `tool/phase5.test.mjs`, `tool/phase3.test.mjs`, `tool/rules.test.mjs`; `test/security_phase5_test.dart`, `chat_media_test.dart`, `photo_phase1_test.dart`, `discovery_test.dart`, `discovery_privacy_test.dart`, `safety_test.dart`; `integration_test/demo_android_test.dart`.
- Evidencia y entrega: este informe, `audit-phase5-*` y artefactos ignorados dentro de `build/`. Los demás archivos sucios de Git pertenecían a fases anteriores; no son todos cambios nuevos de Fase 5.

## Riesgos restantes y criterio de integración

**Integración local:** candidata después de revisar el diff y aceptar las nuevas reglas de medios, migración y dependencias nativas, con pruebas finales registradas. Requiere ejecutar el backend junto al cliente: el cliente por sí solo ya no puede descargar/subir fotos. No se ha integrado ninguna rama. Sigue pendiente aceptación en Chrome/Edge externos y un Android real o emulador capaz de arrancar.

**Producción: NO lista.** Este backend rechaza proyectos reales; la delegación de visibilidad de fotos está restringida a REST del emulador. Antes de desplegar hacen falta servicio HTTPS/IAM real, equivalente seguro de esa delegación, migrador revisado, inventario y revocación real de tokens, cola/scheduler supervisados, cuotas/rate limiting distribuidos, índices probados, aislamiento del decodificador, monitorización y pruebas de carga. No abrir Storage como atajo.

Permanecen las decisiones de Fases 3/4: retención/expiración de carnets y auditoría, criterio humano y apelaciones, fraude y vinculación con pertenencia institucional, eliminación en backups/versiones y operación de la cola de carnets. No se usaron carnets reales ni se comprobó ninguna conexión oficial con Univalle. La bandeja de reportes y el worker heredado de carnets todavía requieren evaluación de escala.

La decodificación no es antivirus ni prueba de identidad. Se conservan los bytes originales, que pueden incluir metadatos EXIF u otros metadatos aportados por el usuario; antes de aceptar contenido personal real debe decidirse su eliminación mediante recodificación segura y validarse esa transformación. No se declara cerrada esa cuestión de privacidad.

Debe definirse también la retención de medios de matches cerrados: se revoca su lectura, pero siguen asociados a mensajes y no se consideran huérfanos. Esta fase no elimina automáticamente historiales legítimos ni decide su plazo de conservación.

## Demo y aceptación manual

**Prueba real realizada en el navegador integrado:** arranque de la Web final por `/__demo/start.html`, sesión de Ana conservada; fotografía de Carla en Descubrir; perfil y vista previa de Ana; selección/subida de PNG ficticio, cambio a principal y eliminación mediante confirmación; restauración de `profile_photos/manual_ana/main` y comprobación independiente de que solo quedan las tres fotos originales. Se abrió Matches, el perfil/galería de Bob y el chat, donde se visualizaron imágenes históricas y checks azules. Una nota de 8 segundos se descargó, mostró controles/duración, pasó a «Pausar audio» y finalizó sin error visible. Esto verifica descarga/inicialización/estado de reproducción, **no una nueva captura de micrófono físico ni audibilidad comprobada por una persona**. Chrome/Edge externos y Android siguen pendientes. Evidencia: `build/phase5-perfil-privado.png`, `build/phase5-galeria-match.png`.

Se creó un respaldo nuevo completo `build/phase5-fixtures-final` (Auth, Firestore y Storage), sin sobrescribir Fase 4; `audit-phase5-export-final.log` confirma la exportación. La revisión final preservó las ocho cuentas, un carnet ficticio privado pendiente, seis solicitudes resueltas sin rutas privadas y ninguna tarea pendiente de eliminación de carnets en ese instante. Los puertos 4400, 7357, 7360, 8088, 9099 y 9198 escuchaban solo en 127.0.0.1. Los procesos auxiliares de emuladores de pruebas y el AVD se cerraron para liberar memoria; los servicios principales del demo quedaron activos.

Abrir **http://127.0.0.1:7357/__demo/start.html** y comprobar el aviso verde. El frontend usa SDK locales y CSP limitada a localhost; el backend escucha en 127.0.0.1:7360. Auth 9099, Firestore 8088 y Storage 9198 permanecen locales. Las comprobaciones de recursos observados no equivalen a una certificación de todo tráfico futuro del sistema operativo.

Contraseña ficticia común: **DemoTinder2026!**. Ana `ana.manual@demo.test`, Bob `bob.manual@demo.test`; pendiente `pendiente@demo.test`; admin `admin@demo.test`; superadmin `superadmin@demo.test`; suspendido `suspendido@demo.test`.

1. Ana: perfil, vista previa, Descubrir (Carla), Matches (Bob), perfil público y galería; comprobar fotografías. Subir una imagen ficticia nueva, elegirla principal y eliminarla; confirmar que vuelve la original y que persiste tras recargar.
2. Ana/Bob: enviar texto, foto, archivo de audio y voz física; escuchar previa y receptor, observar checks. Repetir tras cambiar de pestaña. No inferir audibilidad de audio sintético ni de la compilación Android.
3. Admin: suspender únicamente una cuenta ficticia participante y comprobar denegación de nuevas descargas y acceso al chat desde la otra. Restablecer por backend; no editar `datingAllowed` manualmente. Deshacer/bloquear otro match ficticio para comprobar revocación de medios.
4. Pendiente/suspendido: comprobar que no se accede a citas ni a fotos mediante rutas directas. Admin sin auditoría de superadmin; superadmin sin cambio de rol propio ni eliminación del último.
5. Android: utilizar exclusivamente flavor demo y `lib/main_demo_android.dart` con `TINDER_DEMO=true`, puertos 7357/9099/8088/9198 mediante `adb reverse`, Wi-Fi/datos desactivados y comprobar opciones demo. **No instalar el APK standard** para estas pruebas. `integration_test/demo_android_test.dart` prepara comprobaciones de login, bytes/decodificación, subida/principal/eliminación, chat y denegaciones; todavía debe ejecutarse. No se acredita grabación física ni audibilidad Android con ese test.

Para reproducir compilaciones, ejecutar desde esta copia: Web `flutter build web --target lib/main_demo.dart --output build/demo-web --no-web-resources-cdn --dart-define=TINDER_DEMO=true --dart-define=CHAT_STORAGE_ORIGIN=http://127.0.0.1:9198`; Android demo `flutter build apk --debug --flavor demo --target lib/main_demo_android.dart --dart-define=TINDER_DEMO=true`. Para conservar la variante original en una compilación sin ejecución: `flutter build apk --debug --flavor standard`. No ejecutar ninguna entrada con configuración real para probar este demo.

En una máquina con recursos suficientes, arrancar el AVD, desactivar Wi-Fi/datos y comprobar que `adb shell settings get global wifi_on` y `adb shell settings get global mobile_data` devuelvan `0` antes de iniciar la app. Establecer cada puerto con `adb reverse tcp:7357 tcp:7357` y lo mismo para 9099, 8088 y 9198. Después ejecutar `flutter test integration_test/demo_android_test.dart --flavor demo --dart-define=TINDER_DEMO=true -d emulator-5554`. Cambiar el ID solo por el dispositivo demo comprobado; no utilizar dispositivos personales sin acordar el aislamiento de red. La prueba añade mensajes sintéticos y, en su ejecución correcta, restaura la galería inicial. Si se interrumpe después de publicar una foto, revisar el perfil y eliminar exclusivamente esa foto nueva desde la app; el respaldo final conserva la referencia original. La prueba física de voz sigue siendo una aceptación manual separada.
