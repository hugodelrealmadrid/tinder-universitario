# Auditoría de la rama de Tinder Universitario

Fecha: 13 de octubre de 2026 (America/La_Paz).

**Recomendación: necesita más trabajo antes de integrarse en main.** Las correcciones y pruebas de esta copia mejoran la seguridad y estabilidad, pero no resuelven completamente la privacidad de las descargas, la validación del contenido multimedia ni la consistencia entre Firestore y Storage.

## Alcance y protección de cambios

Se comparó el commit HEAD `2b448ae` con `main`, incluyendo las diferencias de reglas, vista previa, servicio/modelo/interfaz de chat, dependencias y documentación de la rama. El worktree estaba en HEAD separado. No se hizo commit, push, merge, reset ni deploy, ni se modificó el proyecto original o main.

Antes de editar existían cambios en `firebase.json`, `pubspec.lock` y `tool/package-lock.json`. Se guardaron en `audit-preexisting.patch`; al finalizar se verificó que el diff de esos tres archivos coincide exactamente con el respaldo inicial. No son correcciones de esta auditoría.

Las pruebas de reglas utilizan exclusivamente `demo-tinder-universitario`, Firestore `127.0.0.1:8088` y Storage `127.0.0.1:9198`. Las pruebas Flutter usan fakes y fixtures locales. Las compilaciones no ejecutan la aplicación ni realizan operaciones de Firebase de producción.

## Funcionalidades revisadas y hallazgos

**Vista previa.** Lee `_draft`, que obtiene los valores actuales del formulario, y abre una pantalla sin servicio de persistencia. La nueva prueba confirma que un nombre editado aparece en la vista previa, Firestore permanece igual y el borrador sigue disponible al regresar. No requiere guardar para previsualizar. Conserva la distinción existente: subir, eliminar y elegir la foto principal ya persisten inmediatamente mediante ProfileService; la vista previa no convierte esas operaciones en cambios pendientes ni permite revertirlas. La vista previa omite apellido, correo y fecha de nacimiento completa. La edad, carrera e intereses proceden del borrador y catálogos cargados.

**Checks y readAt.** Las reglas originales de la rama permitían agregar readAt después de bloqueo/cierre, revelando nuevas lecturas al otro participante. Se corrigió: solo el destinatario puede agregar el timestamp del servidor una vez, con match activo antes y después del commit y sin bloqueos después del commit. El contenido, remitente y ruta permanecen inmutables. La UI deja de generar recibos en chats inactivos. Se mantiene la lectura del historial tras bloqueo/unmatch, conforme al comportamiento existente.

Construir una fila de ListView no garantiza que esté dentro de pantalla: Flutter también construye filas cercanas para la caché de desplazamiento. Se añadió comprobación del rectángulo de la fila frente al viewport después del frame, estado de aplicación y ruta actual. Al terminar el desplazamiento se revisan las filas. Las pruebas confirman lectura de mensajes visibles, ausencia de readAt para mensajes fuera de pantalla, actualización al desplazarse y ausencia de recibos durante pausa o con match cerrado. El indicador expresa confirmación del servidor y lectura declarada por el destinatario; no demuestra que una persona haya leído el contenido.

**Imágenes y audio.** Se agregó validación de correspondencia entre tipo y MIME en ChatService, además de límites de 5 MiB para imágenes y 15 MiB para audio. Storage mantiene límites y lista cerrada de MIME. Se preservan mensajes de texto antiguos y sus límites.

El widget multimedia mantenía su Future inicial al cambiar la ruta. Se corrigió su actualización y se añadió clave por mediaPath. El audio pausado reiniciaba la fuente al pulsar reproducir; ahora usa resume(). Se descargan bytes acotados para Image.memory y BytesSource con MIME, y el audio solo se descarga al pulsar «Cargar audio», evitando descargar todos los audios al abrir el historial. Los fallos de descarga ofrecen reintento, incluidos errores que llegan antes del siguiente frame. La reproducción/pausa/reanudación real por plataforma queda pendiente de prueba en dispositivo y navegador.

**Storage.** Se reforzó la validación del match para comprobar dos UID ordenados, ID canónico y campos básicos. Solo participantes pueden leer archivos vinculados a un mensaje mediante su ruta exacta. Un archivo huérfano no queda disponible al destinatario. Se prohíbe subir sobre un ID de mensaje ya publicado, además de la prohibición existente de reemplazar archivos. Solo el propietario puede limpiar un huérfano, incluso tras cierre. Los archivos publicados no se eliminan por clientes, lo que evita romper el historial. Se probaron terceros, anónimos, ambos sentidos de bloqueo, matches malformados y bloqueos presentes aunque el match siga activo por una inconsistencia administrativa.

**Compatibilidad.** La suite completa vuelve a cubrir autenticación, perfiles, preferencias, descubrimiento, matches, unmatch, bloqueo, reportes y UI existente. No se ampliaron permisos de lectura de perfiles privados ni se alteró la persistencia del chat de texto. La vista previa y reproducción incluyen estados vacíos/errores, pero la experiencia completa con selectores y códecs reales no se ha comprobado.

## Riesgos pendientes reproducidos

1. **Privacidad de URLs con token (prioridad alta).** Se obtuvo una URL con getDownloadURL como participante y se descargó con fetch sin Authorization: HTTP 200. Cambiar la presentación a bytes no basta para eliminar este riesgo: en `firebase_storage_web 3.11.13`, getData usa internamente getDownloadURL y una petición HTTP. Un participante autorizado puede extraer y compartir el token. No se revocaron tokens ni se cambió infraestructura de producción. Para privacidad estricta hace falta un mecanismo de descarga autenticada sin URLs permanentes compartibles y una política de revocación para tokens anteriores. Una persona autorizada también puede copiar el contenido ya descargado; ninguna regla impide eso.
2. **Contenido real y MIME (prioridad alta para endurecimiento).** Una prueba sube texto HTML declarando image/jpeg y Storage lo acepta. Las reglas verifican MIME declarado y tamaño, no decodifican el archivo. El selector de audio obtiene MIME de la extensión; la detección de imágenes del cliente es parcial. La lista de formatos no garantiza archivos válidos, dimensiones seguras ni códecs reproducibles. Requiere validación confiable del contenido antes de publicar/servir archivos. No se afirma que HTML se ejecute en Image.memory.
3. **Consistencia entre servicios y huérfanos.** Firestore acepta un mensaje con ruta canónica aunque el objeto no exista; una prueba lo reproduce. No puede verificar directamente Storage en sus reglas. El envío normal sube primero, publica después y trata de borrar al fallar la escritura. Las pruebas confirman limpieza y preservación del error original cuando la limpieza también falla. Si se cierra la app, se pierde la red o ambas operaciones fallan, pueden quedar huérfanos. La limpieza no tiene cola persistente ni reconciliación de servidor. Una escritura confirmada cuya respuesta se pierde también puede generar un error aparente y duplicarse al reintentar; las reglas impiden borrar su archivo publicado. Hace falta una estrategia idempotente de publicación y reconciliación.
4. **Consumo de recursos.** La lectura del chat se limita a 50 mensajes, pero FilePicker con withData carga el archivo completo antes de comprobar el límite; archivos muy grandes pueden consumir memoria. Imágenes válidas con dimensiones enormes y cargas repetidas requieren controles adicionales. La descarga manual de audio reduce consumo inicial, pero no sustituye validación ni cuotas.
5. **Validación real Android/Web.** Compilar no demuestra selección de archivos, reproducción, permisos, códecs, CORS, ampliación de imagen ni comportamiento entre dos sesiones. La app conserva configuración Firebase real por defecto: no se abrió conectada a ese proyecto. Hace falta un arranque explícito demo y pruebas de integración en navegador/dispositivo antes de integrar.

Referencia técnica: la [documentación oficial de descarga Web](https://firebase.google.com/docs/storage/web/download-files) distingue URLs y descarga directa. La limitación específica de Flutter Web se comprobó leyendo el código del SDK instalado y mediante la prueba local de token; no se infiere que cambiar a getData elimine los tokens.

## Resultados de comprobaciones

| Comprobación final | Resultado | Evidencia local |
| --- | --- | --- |
| flutter analyze | Sin incidencias | audit-final-analyze.log |
| flutter test | 184 aprobadas, 0 fallidas | audit-final-tests.log |
| Reglas Firestore y Storage | 140 aprobadas, 0 fallidas; 0 omitidas | audit-final-rules.log |
| flutter build web --no-pub --no-wasm-dry-run | Compilación correcta | audit-final-web.log |
| Android: Gradle assembleDebug | Compilación correcta: BUILD SUCCESSFUL, APK debug generado; 358 tareas, 6m22s | audit-android-result.log |
| git diff --check | Sin errores de espacios | Verificación final de Git |

No se ejecutó la aplicación con cuentas reales ni se probaron códecs o selectores en dispositivos. El primer intento Android con Flutter se interrumpió por ausencia de progreso visible; la comprobación offline posterior falló por falta de tika-core 3.2.3 en caché. El intento con repositorios públicos terminó correctamente y generó build/app/outputs/flutter-apk/app-debug.apk. Gradle emitió avisos de deprecación y Kotlin; no bloquearon la compilación y no se modificó la configuración existente.

Para repetir las pruebas, con los emuladores demo activos:

```powershell
node --test tool/rules.test.mjs
flutter analyze
flutter test
```

El archivo Node fija el proyecto demo y ambos hosts locales y carga las reglas desde esta copia; no usa el proyecto de producción. Para arrancar los emuladores se utilizó:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
$env:FIREBASE_EMULATORS_PATH=Join-Path (Get-Location) 'tool/emulator-cache'
& tool/node_modules/.bin/firebase.cmd emulators:start --only firestore,storage --project demo-tinder-universitario --config firebase.json
```

Se añadieron 11 pruebas Flutter frente a las 173 iniciales y 26 pruebas Node frente a las 114 iniciales. Las pruebas que documentan límites se consideran aprobadas cuando reproducen la limitación esperada; por eso una suite verde no implica ausencia de vulnerabilidades.

Durante la construcción de la suite hubo fallos que se corrigieron: importación ausente de ChatException, fixture de match cerrado sin closedBy/closedAt, expectativa permission-denied en lugar de object-not-found, error rápido de descarga antes de la suscripción del FutureBuilder y un aviso de estilo por llaves. Los logs intermedios se conservan; los resultados finales deben leerse en los archivos indicados arriba.

El primer arranque de emuladores falló por el puerto del hub dentro del sandbox; otro intento encontró un JAR antiguo ocupado en la caché global. Se utilizaron una caché aislada en `tool/emulator-cache` (ignorada localmente) y JDK 21 de Android Studio. No se tocaron procesos ajenos ni se modificaron reglas remotas. Los emuladores iniciados para esta auditoría se cerraron al finalizar las pruebas.

## Archivos de esta auditoría

Correcciones: `firestore.rules`, `storage.rules`, `lib/features/chat/chat_service.dart`, `lib/features/chat/chat_screen.dart`, `lib/features/chat/chat_media_widget.dart`.

Pruebas: `tool/rules.test.mjs`, `test/chat_media_test.dart` (nuevo), `test/chat_test.dart`, `test/profile_test.dart`.

Documentación y respaldo: `INFORME_AUDITORIA.md`, `audit-preexisting.patch`. Logs de verificación y artefactos de compilación quedan en rutas ignoradas por Git. Los tres cambios locales preexistentes permanecen sin alteración.

## Recomendación de integración

No integrar todavía. Las correcciones verificadas deben revisarse junto con la rama, pero los riesgos de descarga con token, contenido declarado y publicación entre servicios siguen abiertos. Antes de integrar se necesita resolver la política de archivos privados y reconciliación, validar contenido en un entorno confiable y comprobar flujos reales Android/Web exclusivamente con configuración demo. Ninguno de esos pendientes se presenta como solucionado por las pruebas unitarias o emuladas.
