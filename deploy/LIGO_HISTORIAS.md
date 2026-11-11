# Historias de LIGO 2.0

La fase se activa en el cliente con `LIGO_STORIES=true` y en el backend de staging con `node tool/ligo/server.mjs --stories`. La Web escucha en 7465 y la API en 7466. Ambos usan exclusivamente `demo-ligo-staging`. Si el staging está detenido, ejecutar `node tool/ligo/start-local.mjs --stories`. El lanzador comprueba el respaldo antes de restaurar, rechaza puertos ocupados y guarda exportaciones verificadas. El modo de historias conserva el proceso de notificaciones internas.

## Alcance y controles

- Publican estudiantes aprobados y habilitados. Cada historia ajena exige un match activo entre estudiantes aprobados y habilitados. Un bloqueo en cualquier dirección impide acceso, visualizaciones, respuestas y reportes.
- El servidor fija la publicación y la expiración, separadas exactamente por 24 horas. Los archivos quedan en `story_media/{uid}/{id}` con acceso exclusivo mediante la API autenticada. Firestore y Storage deniegan los accesos directos con las reglas existentes.
- Fotos JPG, PNG o WebP hasta 5 MiB. Se decodifican y normalizan a JPEG. Videos MP4 H.264 con audio AAC opcional hasta 15 MiB, 30 segundos y 1920 px por dimensión. El backend valida el contenido, elimina los metadatos del contenedor de video y valida generación, tipo, hash y ausencia de tokens antes de entregar los bytes.
- El propietario tiene hasta 12 historias activas. La bandeja consulta hasta 25 matches por página y el listado de visualizaciones hasta 25 registros. Solo el propietario ve la lista. Se registra una vista por historia y usuario.
- Las respuestas ingresan en el chat existente y generan el aviso interno de mensaje recibido. No se agrega ningún envío FCM específico de historias. Los reportes se revisan desde la cola de moderación existente y sus resoluciones mantienen la auditoría de ese flujo.
- El borrado invalida el acceso antes de retirar el objeto y las vistas. Un barrido periódico elimina objetos vencidos y reservas de subida abandonadas. Los fallos se reintentan en la siguiente ejecución. El cliente Web revoca sus URL de objeto y Android elimina su copia temporal al cerrar el visor o cambiar de historia.

## Comprobaciones reproducibles

Ejecutar desde el worktree de `codex/ligo` en PowerShell.

```powershell
$env:LIGO_TEST_PORT_OFFSET = '200'
node tool/ligo/staging.mjs stories
flutter analyze --no-pub
flutter test --no-pub
```

La suite de historias levanta sus propios emuladores con el proyecto `demo-ligo-validation`, independiente del staging activo. Requiere el FFmpeg que usa el backend de medios.

```powershell
flutter build web --no-pub --no-wasm-dry-run --no-web-resources-cdn --target=lib/main_ligo_staging.dart --dart-define=LIGO_STAGING=true --dart-define=LIGO_20_PREVIEW=true --dart-define=LIGO_MULTIUNIVERSITY=true --dart-define=LIGO_NOTIFICATIONS=true --dart-define=LIGO_STORIES=true --output=build/ligo-stories/web
flutter build apk --debug --no-pub --flavor ligostaging --target=lib/main_ligo_staging.dart --dart-define=LIGO_STAGING=true --dart-define=LIGO_20_PREVIEW=true --dart-define=LIGO_MULTIUNIVERSITY=true --dart-define=LIGO_NOTIFICATIONS=true --dart-define=LIGO_STORIES=true
```

Para Android por USB, el APK de staging usa loopback. Aplicar `adb reverse` a 7466, 9399, 8288 y 9498 antes de probar. Usar únicamente perfiles ficticios y verificar el formato del video con clips de la cámara del dispositivo.

## Configuración externa pendiente

En un eventual entorno alojado, se necesita el índice de `storyAssets` por propietario y expiración, habilitar `LIGO_STORIES_ENABLED` y programar una tarea de limpieza autenticada con `TINDER_CLEANUP_SCOPE=stories`. Esa tarea es independiente de la limpieza de chat y fotografías de perfil. Ninguna de esas operaciones se ejecuta al compilar staging.

## Recuperación local del staging

La Web y la API conservaron sus procesos en 7465 y 7466. Firestore siguió activo en 8288 con el mismo proceso. Auth y Storage se iniciaron por separado en 9399 y 9498, con un directorio temporal propio y reglas sin cambios. El Hub de recuperación en 4420 enumera solo los dos emuladores que arrancó. Por eso las herramientas de arranque que exigen los tres servicios en el mismo Hub deben reservarse para un futuro inicio completo, después de conservar los datos activos.

Se preservaron 9 cuentas ficticias y 16 objetos. La exportación interrumpida conservaba las cuentas, parte del inventario de Storage y una copia de Firestore. Los blobs locales se cotejaron con SHA-256 y las generaciones de Firestore. Para los cuatro carnets ficticios, los bytes recuperados se cotejaron con los fixtures reproducibles originales. Los seis objetos del respaldo completo conservaron sus metadatos. Para los demás se reconstruyó el metadato técnico mínimo, manteniendo la generación y los bytes, con caché privada y sin tokens. Se descargaron y verificaron los 16 objetos después de iniciar el servicio.

Se generó un respaldo nuevo con los tres servicios en `build/ligo-staging/recovery-evidence/historias-staging-verificado-20261108-112334-e2b521a5`. Incluye manifiesto SHA-256. El respaldo anterior, la exportación parcial, el Firestore activo y el puntero original se conservaron.

### Regresión

La corrida anterior falló por un `ECONNRESET` de Storage en la prueba de carnet vencido de Fase 4. El runner también marcó fallida `phase5.test.mjs` a nivel de archivo, sin traza que permita atribuirle la misma causa con certeza. En un entorno secundario limpio se repitieron ambas suites con `node tool/ligo/staging.mjs affected` y pasaron 62 de 62. La regresión completa pasó 252 de 252. No se cambiaron aserciones ni reglas para obtener esos resultados.

La prueba de historias incorpora ahora revisión administrativa auditada, denegación a un estudiante y rechazo de una segunda resolución. Se probó en los emuladores secundarios.

### Validación del cierre

- Flutter Analyze sin hallazgos y 365 pruebas Flutter aprobadas.
- En emuladores, 252 pruebas de regresión, 3 de historias y 3 de notificaciones aprobadas.
- Chrome publicó JPG y MP4 mediante el selector y la API autenticada. En tamaño móvil se comprobó la publicación de JPG, la navegación entre historias, la pausa táctil y la reproducción de MP4. La primera prueba de una foto PNG grande agotó la espera de Chrome DevTools y la repetición con JPEG completó el flujo.
- Los emuladores verificaron caducidad exacta, limpieza de Storage, bloqueos, suspensiones, respuesta en chat, aviso interno y revisión auditada de reportes.
- La compilación Android no sustituye una prueba con dispositivo físico.
