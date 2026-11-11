# Recuperación del demo local — 24 de octubre de 2026

**Resultado:** demo recuperado y funcionando en http://127.0.0.1:7357/.
Entrada con comprobaciones del navegador: http://127.0.0.1:7357/__demo/start.html.
Este informe actualiza el estado de recuperación pendiente del informe de integración del 19 de octubre.

Durante la recuperación se utilizó exclusivamente `C:\Users\HP\Desktop\tinder_universitario_pruebas` y el proyecto `demo-tinder-universitario`. En esa etapa no se hizo commit, amend, merge, rebase, push ni deploy. Los lanzadores, verificadores y este informe se dejaron inicialmente sin commit; su consolidación local posterior fue autorizada expresamente y se documenta al final.

## Respaldo utilizado y conservación

Se conservaron intactos los respaldos de `build/respaldo-integracion-20261019-222416/`.
Antes de importar se verificaron **88 entradas de los manifiestos SHA-256**: archivos principales/ZIPs/bundle, export completo, configuración, recuperación propuesta, Firestore vivo y consolidación. No hubo discrepancias.

La importación autorizada combina:

- Firestore exportado el 19 de octubre a las 22:38, desde `firestore-vivo-223840/`.
- Auth y Storage del export completo `demo-actual/`, escrito aproximadamente a las 22:25 del 19 de octubre dentro del respaldo denominado «22:24».
- Carpeta combinada existente: `build/respaldo-integracion-20261019-222416/recuperacion-propuesta/`.

Antes de iniciar el backend se levantaron solamente los emuladores y se comprobó que no hubiera referencias ausentes, archivos huérfanos o solicitudes pendientes vencidas que pudieran causar borrados adicionales. La comprobación pasó: no hubo riesgos detectados ni tareas de limpieza pendientes.

## Aislamiento corregido

La versión instalada del CLI usa `os.tmpdir()/firebase/storage/blobs` para los bytes de Storage y elimina ese directorio al detener ese emulador. Compartir TEMP era insuficiente aunque los proyectos y puertos fueran distintos.

Ahora cada proceso hijo recibe TEMP, TMP y TMPDIR explícitos:

```text
Demo:    C:\Users\HP\Desktop\tinder_universitario_pruebas\build\emulator-runtime\demo\temp
Pruebas: C:\Users\HP\Desktop\tinder_universitario_pruebas\build\emulator-runtime\tests\temp
```

También se separaron los directorios de ejecución/logs en `demo/run` y `tests/run`. Los lanzadores fijan proyecto/configuración locales, excluyen credenciales/opciones heredadas y rechazan puertos de emuladores ocupados. No cambian las variables globales de Windows. Se utiliza la caché local de JARs y Java con heap acotado; las reglas no se relajaron.

**Verificación real del aislamiento:** se guardaron los hashes de los 14 blobs físicos del demo, se ejecutaron las 208 pruebas destructivas en el proyecto secundario, se cerró ese conjunto completo y se verificaron nuevamente los 14 archivos. Todos conservaron nombre y hash. Los puertos secundarios quedaron libres y el demo continuó sirviendo archivos privados. Después se comparó Firestore en otro arranque secundario de solo Firestore, también cerrado sin afectar al principal.

No utilizar los comandos antiguos de arranque directo del CLI para ejecutar simultáneamente los dos entornos. Usar los nuevos lanzadores.

## Datos recuperados y consistencia

| Elemento | Resultado |
| --- | --- |
| Auth | 10 cuentas `@demo.test`; UID, correo, contraseña/hash, fecha de creación y estados efectivos conservados |
| Inicio de sesión | Las 10 cuentas pudieron iniciar sesión con su contraseña ficticia existente; no se restablecieron contraseñas |
| Perfiles / autorización | 10 perfiles y 10 documentos de acceso; roles, verificación, suspensión y espejo de permiso coherentes |
| Storage | 14 objetos: 3 fotos de perfil, 6 imágenes de chat y 5 audios WAV |
| Integridad | Todos los bytes y generaciones coinciden con el snapshot respaldado; sin tokens permanentes restaurados |
| Referencias | Fotos/principales/galerías, manifiestos, matches, mensajes y pruebas de subida coherentes; sin archivos faltantes ni huérfanos detectados |
| Verificación | 7 solicitudes conservadas; ninguna pendiente vencida ni tarea de borrado pendiente; no hay carnets almacenados en el snapshot recuperado |
| Firestore completo | 148 documentos antes y después; no falta ninguno |

El reconciliador existente completó **tres publicaciones ya referenciadas**: dos registros `chatUploads` y un `profilePhotoAssets` pasaron de `ready` a `published`, eliminando `expiresAt`. Se compararon todos los campos de los 148 documentos contra el snapshot original importado en un emulador secundario: esas son las únicas diferencias lógicas. No cambian bytes, referencias, contenido de mensajes ni privilegios y evitan conservar el vencimiento de staging de publicaciones válidas.

Por ello, el hash binario del reexport de Firestore difiere del original. La comparación inicial estricta señaló esas diferencias (salida 2); la comparación posterior las clasificó de forma acotada y comprobó **cero cambios inesperados**. No se escondieron documentos eliminados ni diferencias de contenido. Evidencias: `comparacion-logica-firestore.json` y `comparacion-logica-firestore-clasificada.json`.

Auth materializó `disabled=false` donde el export anterior omitía el campo; el estado efectivo no cambió. Los inicios de sesión de validación actualizan sus metadatos de acceso. No se modificaron decisiones administrativas ni perfiles para conseguir que las pruebas pasaran.

## Pruebas ejecutadas

| Comprobación | Resultado |
| --- | --- |
| Suites Firebase/backend | **208 aprobadas, 0 fallidas**, proyecto `demo-tinder-phase3-tests`, Auth 9199 / Firestore 8188 / Storage 9298 |
| Suite demo | **10 aprobadas, 0 fallidas** |
| Nuevas pruebas de aislamiento | **5 aprobadas, 0 fallidas**, incluidos os.tmpdir real del hijo y rechazo de puertos ocupados |
| HTTP con credenciales demo reales | **25 descargas autorizadas** de fotos/audios; bytes y MIME/no-store comprobados |
| Rechazos HTTP/Storage | **85 accesos no autorizados rechazados**, incluidos anónimo, suspendido, rechazado, tercero de otro chat y accesos administrativos indebidos |
| Carnets resueltos del demo | Los 7 endpoints siguen denegados; no se resubieron documentos al demo |
| Carnet ficticio pendiente | En pruebas secundarias, subida decodificada y lectura autorizada por backend administrador; usuario normal/propietario y SDK Storage denegados |
| Tokens antiguos | 3 URLs antiguas comprobadas siguen sin devolver archivos |
| Supervivencia de archivos al cierre secundario | 14 antes, 14 después; todos los hashes físicos idénticos |
| Sintaxis JavaScript y comparación de datos | Verificadas para los nuevos scripts; comparación de 148 documentos sin cambios inesperados |

La primera ejecución de la nueva prueba de puertos dentro del sandbox devolvió EACCES por la restricción de red de ese proceso. Se repitió con acceso loopback autorizado y las cinco pruebas pasaron. Se conservó la salida anterior; no se modificó la prueba para aceptar un puerto inseguro.

No se reejecutaron Flutter analyze, las 271 pruebas Flutter ni compilaciones: esta recuperación no modifica código Dart/Android ni sus dependencias. Tampoco se afirma una nueva prueba visual, escucha física o ejecución Android. Se comprobó el transporte HTTP real y la igualdad de bytes de los audios.

Permanece el aviso ya conocido `MaxListenersExceededWarning` del SDK Storage. No impidió las verificaciones, pero sigue pendiente el diagnóstico de carga/memoria; no se ocultó. El runtime de reglas también muestra la línea de Java `Picked up JAVA_TOOL_OPTIONS` como aviso de protocolo al iniciar; las suites de reglas finalizaron aprobadas.

## Exportación nueva y evidencias

Directorio de trabajo y evidencias de esta recuperación:

```text
C:\Users\HP\Desktop\tinder_universitario_pruebas\build\recuperacion-demo-20261024-114640
```

Nueva exportación completa, distinta de todos los respaldos anteriores:

```text
C:\Users\HP\Desktop\tinder_universitario_pruebas\build\recuperacion-demo-20261024-114640\export-completo-final
```

Contiene los 35 archivos esperados de Auth/Firestore/Storage y su metadata. Se generó `SHA256-export-final.json` en el directorio de evidencias y se releyeron los archivos para verificar cada hash. `verificacion-export-final.json` registra las 10 cuentas, 14 objetos, igualdad de bytes/generaciones y conservación de identidad/contraseñas. El export incluye los tres estados de publicación normalizados y los accesos Auth de validación.

Otras evidencias: `consistencia-inicial.log`, `consistencia-final.log`, `acceso-medios.log`, `demo-tests.log`, `aislamiento-unitario-con-puertos.log`, `pruebas-secundarias.log`, `aislamiento-comprobado.json`, `integridad-tokens.log`, `salud-final.log` y logs separados de cada servicio. Los datos y logs permanecen fuera de Git, bajo build.

## Arranque y comprobaciones reproducibles

El demo se deja encendido; **no ejecutar otro arranque mientras sus puertos estén ocupados**. Estos comandos son para futuros reinicios autorizados, en terminales separadas y desde la copia de pruebas:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
node tool/run-isolated-emulators.mjs demo --import 'C:\Users\HP\Desktop\tinder_universitario_pruebas\build\recuperacion-demo-20261024-114640\export-completo-final'

# Otras dos terminales:
node tool/demo/run-isolated-service.mjs backend
node tool/demo/run-isolated-service.mjs web
```

Pruebas destructivas, únicamente mediante su lanzador independiente:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
node tool/run-isolated-emulators.mjs tests
```

Nueva exportación futura sin detener el demo: elegir una ruta absoluta nueva dentro del workspace:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
node tool/run-isolated-emulators.mjs export --output 'C:\Users\HP\Desktop\tinder_universitario_pruebas\build\NUEVA_EXPORTACION_NO_EXISTENTE'
```

El lanzador rechaza sobrescribir un destino existente. No usar seeds, migradores antiguos, main.dart, flavor standard ni configuraciones reales para este demo.

## Acceso y límites de recuperación

Ana: `ana.manual@demo.test`; Bob: `bob.manual@demo.test`; administrador: `admin@demo.test`; superadministrador: `superadmin@demo.test`. Contraseña ficticia común: `DemoTinder2026!`. Se conservaron los estados de las cuentas tal como estaban respaldados, sin volverlas pendientes ni aprobarlas de nuevo.

**No se detectó pérdida adicional respecto del snapshot autorizado.** Se recuperaron todas sus cuentas, objetos y documentos, con las únicas normalizaciones descritas. No es posible reconstruir cambios de Auth/Storage posteriores al export del 19 de octubre que no se hubieran guardado; este límite anterior a la recuperación permanece. No se afirma que existieran otras subidas o cuentas perdidas.

La recuperación no afecta a Firebase de producción. Todo pertenece al proyecto/bucket demo; las voces o fotos cargadas manualmente pueden contener contenido real aunque se hayan usado en pruebas. Los requisitos pendientes de producción de la fase 5 siguen vigentes y esta recuperación no autoriza integrar ni desplegar.

## Archivos incorporados en esta recuperación

- `tool/emulator-isolation.mjs`
- `tool/emulator-isolation.test.mjs`
- `tool/run-isolated-emulators.mjs`
- `tool/demo/run-isolated-service.mjs`
- `tool/demo/check-recovered-data.mjs`
- `tool/demo/check-media-access.mjs`
- `tool/demo/compare-recovered-firestore.mjs`
- `INFORME_RECUPERACION_DEMO.md`

Base de integración anterior a la consolidación: `d1ea895e2387d5c1a1432865456c97eaa1f22e5b`. Main/original conservados en `d18360d26648f1296272cce9887692d5b5dcf383`.

## Consolidación local autorizada — 24 de octubre de 2026

Se revisaron los ocho archivos completos. Se versionan seis herramientas de código (aislamiento, lanzadores y verificadores), una suite de pruebas de aislamiento y este informe. No se incluye ningún archivo de `build`, respaldo, exportación Firebase, blob temporal, credencial, dato de usuario, binario o artefacto generado. Las cuentas/contraseñas escritas en los scripts son las fixtures ficticias del demo; no hay claves de servicio ni tokens de sesión literales. La revisión del índice complementa la lectura del código con detección de patrones de secretos y rutas prohibidas.

Los ocho archivos previos se copiaron con manifiesto SHA-256 a `build/consolidacion-recuperacion-20261024-121656/archivos-previos/`. En ese directorio se conservan también las nuevas evidencias, fuera de Git.

**Incidente de metadatos de Auth:** la primera selección de pruebas por expresión negativa no excluyó las dos pruebas de login. Pasaron los diez casos demo y los cinco de aislamiento, pero las sesiones actualizaron `lastLoginAt` y `lastRefreshAt` de `manual_ana` y `manual_bob`. La comparación contra el snapshot, cuya huella coincidía con la de antes de las pruebas, confirmó que no cambió ningún otro campo Auth. No se intentó deshacer esos accesos mediante importaciones o modificaciones de Auth. Por tanto, no se declara cumplimiento absoluto de la condición de mantener todos los metadatos de sesión intactos.

Se corrigió la selección con exclusión explícita: `node --test --test-skip-pattern='Cuenta, perfil, match y foto' tool/emulator-isolation.test.mjs tool/demo/*.test.mjs`. La repetición ejecutó **13 pruebas aprobadas**: cinco de aislamiento y ocho del demo sin login. Las dos pruebas de login quedan fuera de esa repetición, no se contabilizan como aprobadas nuevamente. No se cambió código de las pruebas para fabricar resultados.

Firestore y Storage conservaron sus huellas respecto de antes de la ejecución inicial: 148 documentos y 14 archivos. Se estableció además una huella posterior a las dos sesiones para detectar cualquier cambio adicional de las pruebas secundarias. Los scripts de captura y los hashes, sin cuerpos de cuentas ni contraseñas, permanecen bajo build. Los avisos y límites de recuperación documentados anteriormente siguen vigentes.

La nueva ejecución de las suites Firebase/backend finalizó con **208 aprobadas y 0 fallidas**, únicamente en el entorno secundario aislado. Después de su cierre se repitieron las huellas: Firestore y Storage permanecen idénticos a antes de todas las pruebas, y Auth permanece idéntico al estado posterior a los dos logins accidentales, sin cambios adicionales. La revisión de consistencia confirmó nuevamente 10 cuentas/perfiles/registros de acceso, 14 objetos, 7 solicitudes, cero tareas de limpieza pendientes y cero riesgos detectados. No se detuvieron ni reiniciaron los servicios del demo.

Se prepara exclusivamente este conjunto de ocho archivos para un commit local nuevo sobre `feature/integracion-tinder`, sin reescribir commits anteriores. La documentación identifica el commit por su mensaje y por `git log -1` una vez confirmado; su propio hash no puede incluirse dentro del archivo que determina ese hash. El estado final y el resultado de revisión del índice se conservan en las evidencias locales de consolidación.
