# Auditoría de preintegración — Tinder Universitario

Fecha: 19 de octubre de 2026, zona America/La_Paz. Auditoría sobre `C:\Users\HP\Desktop\tinder_universitario_pruebas`; proyecto original consultado exclusivamente en lectura: `C:\Users\HP\Desktop\tinder_universitario`.

**Recomendación:** podemos preparar una integración local controlada en una rama independiente. **No recomiendo fusionar directamente la rama remota de la compañera como si contuviera las cinco fases, ni publicar el resultado en producción.** Primero hay que consolidar los cambios sin commit, revisar la selección de archivos, actualizar instrucciones obsoletas y validar la copia de integración. El backend y las migraciones de producción siguen pendientes.

En esta auditoría la única escritura es este informe. No se ejecutaron commits, cambios de rama, merge, rebase, fetch, instalaciones, pruebas, migraciones, exportaciones ni deploy. No se consultó Firebase de producción ni se alteraron los emuladores o el teléfono. Se consultaron referencias de GitHub con `git ls-remote`, sin guardar objetos ni actualizar referencias locales, y el aviso público de una dependencia.

## 1. Estado exacto de Git

| Elemento | Estado comprobado |
| --- | --- |
| Copia de pruebas | **HEAD separado**, sin rama local propia |
| HEAD y punto de partida de las fases | `2b448ae41fe4e0fbab38cf632cc4003440252b41` |
| Commit de la compañera | «Añadir vista previa, visto de checks, imágenes y audio», 12/10/2026 |
| Referencia coincidente | `origin/feature/vista-previa-visto-checks-imagenes-audio` |
| `main` local y `origin/main` | `d18360d26648f1296272cce9887692d5b5dcf383` |
| Base común de `main` y HEAD | `d18360d26648f1296272cce9887692d5b5dcf383` |
| Relación de historia | `main` es ancestro directo; 0 commits exclusivos de main y 1 exclusivo de la rama de la compañera |
| Proyecto original | Rama `main`, árbol de trabajo e índice limpios, sin archivos nuevos no ignorados |
| Copia, cambios versionados respecto de HEAD | **36 archivos modificados**, todos sin preparar en el índice |
| Cambios preparados / conflictos existentes | **0 / 0** |
| Archivos nuevos no versionados al comenzar | **129 archivos**; el informe agrega uno más |
| Diferencia de archivos ya versionados frente a main | **38 rutas**, incluidas las incorporaciones del commit de la compañera; no incluye los nuevos sin seguimiento |
| Archivos versionados eliminados frente a main | **Ninguno** |

Las referencias de GitHub se comprobaron directamente y coincidieron con los dos SHA anteriores. No se asume que sigan iguales cuando se autorice integrar: hay que volver a verificarlas entonces. No hay una rama local `feature/...` en esta copia; hay una referencia remota y un checkout separado de su commit.

Los dos directorios son worktrees del mismo repositorio: comparten `C:/Users/HP/Desktop/tinder_universitario/.git`. Crear un commit o una rama en pruebas, en una futura operación autorizada, agregaría objetos/referencias a ese repositorio común; no movería por sí solo `main`. No intentar cambiar esta copia a `main`, ya ocupado por el proyecto original.

### Qué está confirmado y qué no

El único commit posterior a main es el de la compañera. Cambia estas 12 rutas:

```text
README_NUEVAS_FUNCIONES.md
firestore.rules
lib/features/chat/chat_media_widget.dart
lib/features/chat/chat_message.dart
lib/features/chat/chat_screen.dart
lib/features/chat/chat_service.dart
lib/features/profile/profile_preview_screen.dart
lib/features/profile/profile_screen.dart
pubspec.lock
pubspec.yaml
storage.rules
test/chat_receipts_test.dart
```

**Ninguna de las fases 1–5 ni la corrección de localhost para Android físico está en un commit nuevo.** Están en archivos modificados y nuevos del worktree. Un merge o cherry-pick del SHA `2b448ae` traería solamente la implementación inicial de la compañera, sin las correcciones y protecciones posteriores.

Distribución de los 129 archivos nuevos: 82 de código/herramientas/pruebas, 3 configuraciones Firebase demo, 10 informes/guías y 34 archivos `audit-*` de evidencia o parches. Dentro de los 82 hay 19 archivos en `lib`, 12 en `test`, 1 en `integration_test`, 3 del flavor Android demo, 9 del backend, 32 de herramientas demo y 6 herramientas adicionales. `git diff` por sí solo **no contiene esos archivos nuevos**. Un parche de los 36 modificados sería incompleto: faltarían, por ejemplo, `university_gate.dart`, el transporte de fotografías privadas y módulos importados por el backend.

Los 36 modificados se agrupan así:

- Configuración: `.gitignore`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/gradle.properties`, `firebase.json`, `firestore.rules`, `storage.rules`, `pubspec.yaml`, `pubspec.lock`, `tool/package.json`, `tool/package-lock.json`.
- Autenticación y UI común: `lib/features/auth/auth_gate.dart`, `auth_service.dart`, `lib/widgets/app_ui.dart`.
- Chat: `chat_media_widget.dart`, `chat_message.dart`, `chat_screen.dart`, `chat_service.dart`, dentro de `lib/features/chat/`.
- Descubrir: `discovery_models.dart`, `discovery_publication.dart`, `discovery_service.dart`.
- Matches/preferencias/perfil: `matches_screen.dart`, `discovery_preferences.dart`, `preferences_screen.dart`, `preferences_service.dart`, `photo_store.dart`, `profile_screen.dart`, en sus directorios respectivos.
- Pruebas: `test/auth_service_test.dart`, `chat_receipts_test.dart`, `chat_test.dart`, `discovery_privacy_test.dart`, `discovery_test.dart`, `email_verification_test.dart`, `profile_test.dart`, `safety_test.dart`, `tool/rules.test.mjs`.

## 2. Comparación funcional y conflictos potenciales

**No hay divergencia textual de ramas en este momento:** main no tiene commits nuevos respecto de la base del trabajo. No se realizó un merge de prueba ni se generaron árboles/objetos Git para simularlo. Por la relación de ancestros, una consolidación completa sobre el HEAD actual puede incorporarse a la base actual sin una edición concurrente de main que resolver. Esto no equivale a certificar un merge futuro ni una compatibilidad de datos/servicios.

El proyecto original está limpio; no se detectaron modificaciones locales suyas que pudieran sobrescribirse. Si cambia después de esta auditoría, detener el procedimiento y recalcular la comparación. Las rutas más delicadas son:

| Área / archivos | Conflicto semántico o de operación que hay que revisar |
| --- | --- |
| `firestore.rules`, `storage.rules` | No combinarlas con autorizaciones antiguas para hacer funcionar clientes viejos. Las actuales exigen estado explícito y pruebas de subida; Storage cliente está cerrado. |
| `auth_gate.dart`, `auth_service.dart`, nuevos modelos/gates | El login y correo verificado se conservan, pero ya no equivalen a autorización para citas. Los usuarios antiguos sin migración quedan bloqueados deliberadamente. |
| `photo_store.dart`, `app_ui.dart`, descubrimiento y galería | Las URLs públicas anteriores dejaron de ser el contrato. Se requieren referencias internas, manifiestos, backend y migración. |
| Chat, `readAt`, `durationMs`, nuevas pruebas | Integrar modelo, publicación, lectura, validación, borrado y UI juntos. El mensaje multimedia necesita una prueba confiable de archivo, no solo una ruta correcta. |
| Preferencias y catálogo | `careerIds` es opcional para datos antiguos; lista vacía conserva «cualquier carrera». Mantener los IDs del catálogo y límite actual de hasta cinco carreras, edades y filtros recíprocos. |
| `firebase.json` | Conserva la configuración Flutter del proyecto real y agrega emuladores. No es el archivo de demo completo: le falta Auth local. Usar explícitamente `firebase.demo.json` para el demo. No ejecutar comandos genéricos de publicación de reglas. |
| Gradle y manifiestos | Ahora existen flavors `standard` y `demo`. Los comandos antiguos sin flavor deben actualizarse. Mantener el paquete `.demo`, HTTP local limitado al flavor y el permiso de micrófono. |
| `lib/main_demo_android.dart` | Conservar `automaticHostMapping: false` en Auth, Firestore y Storage; de lo contrario FlutterFire convierte loopback a `10.0.2.2` y rompe USB en teléfonos físicos. |
| Locks y dependencias | No resolver conflictos copiando solo un lock o ejecutando una actualización general. `record`, `http`, SDK `integration_test`, Firebase Admin, Sharp y overrides tienen que corresponder con sus manifiestos. |
| Documentación | `README_NUEVAS_FUNCIONES.md` aún dice que no hay grabación de voz y propone `firebase deploy` de reglas. Es información histórica, no una instrucción vigente. Actualizar antes del commit de integración. |

Los permisos de lectura más estrictos son cambios de producto que deben aceptarse explícitamente al revisar el diff: un match cerrado/bloqueado pierde sus medios; una suspensión o pérdida de aprobación bloquea accesos de citas, incluidos históricos. `isActive` continúa siendo visibilidad voluntaria, no suspensión administrativa.

### Conservación de funcionalidades originales

No se borró ninguno de los archivos versionados de main ni sus 11 archivos de pruebas. Se conserva el código de login/registro, verificación de correo, modelo/servicio de perfil, bloqueo/reportes y unmatch; varios de esos servicios/pantallas son idénticos a main. Las pruebas originales continúan en la suite ampliada. Esto aporta evidencia de conservación, aunque no reemplaza una aceptación funcional del código consolidado.

| Funcionalidad | Evaluación de integración |
| --- | --- |
| Registro, login y correo verificado | Conservados; nueva barrera universitaria adicional. No saltar ninguna de las dos verificaciones. |
| Edición, visibilidad, principal/eliminación de fotos | Conservadas, con transporte privado obligatorio y referencias nuevas. No compatibles con datos legacy sin migración. |
| Vista previa | Se conserva el archivo incorporado por la compañera; usa el borrador sin guardar y el componente de fotos actualizado. |
| Descubrir, preferencias, swipes, matches | Conservados; se agrega carrera sin eliminar edad/género, reciprocidad o bloqueos. |
| Perfil público del match | Agregado con proyecciones públicas, sin acceso general al documento privado `users` ajeno. |
| Chat de texto y recibos | Conservados; mensajes históricos sin `type` siguen siendo texto. `readAt` solo lo escribe el destinatario según reglas. |
| Adjuntar imágenes y archivos de audio | Conservado; notas de voz son adicionales. El servidor aplica decodificación y límites nuevos. |
| Unmatch, bloqueo y reportes | Código/servicios originales conservados; autorización se vuelve más estricta. |
| Verificación/administración | Nuevas funciones dependientes de backend, reglas y migración; no pueden llevarse únicamente las pantallas. |

Los límites actuales del servidor —imágenes no animadas de hasta 4096 por dimensión y 16 millones de píxeles, 5 MiB; audio hasta 15 MiB y 10 minutos; voz hasta 60 segundos— requieren inventario de medios existentes. No se ha comprobado que todos los archivos reales anteriores cumplan esos límites, ni se accederá a ellos durante esta auditoría.

## 3. Migraciones y backend que condicionan la integración

### Datos y autorización

La unidad de integración incluye cliente + reglas + servicios privilegiados + esquema. Nuevos datos de servidor relevantes:

- `accountAccess/{uid}`: rol `user/admin/superadmin`, verificación `pending/approved/rejected`, suspensión y solicitud actual. No confiar en `users.role` ni permitir que el cliente escriba sus privilegios.
- `users/{uid}.datingAllowed`: espejo protegido, actualizado atómicamente por el servidor; su ausencia deniega citas. Mantener `isActive` separado.
- `verificationRequests`, `verificationCleanup`, `administrativeAudit`, `administration/roles`: solicitudes, eliminación, auditoría y registro de superadministradores.
- `profilePhotoAssets`, `profilePhotoManifests`, `chatUploads`: pertenencia, generación, hash, tipo/tamaño y estado del objeto. El cliente no puede crearlos para simular una subida.

Antes de habilitar un entorno con datos antiguos: inventariar, respaldar, establecer mantenimiento de escrituras, migrar referencias y proyecciones públicas, validar objetos, registrar pruebas/manifiestos y revocar tokens de Storage. Para cuentas reales sin verificación explícita, establecer un estado conservador pendiente mediante procedimiento privilegiado; **no aprobar masivamente ni promover roles tomando campos controlados históricamente por el cliente**. El primer superadmin real requiere otro procedimiento de confianza/IAM y auditoría, no el bootstrap ficticio.

La migración demo Fase 5 ya ejecutada registró tres fotos, nueve medios de chat, tres tokens revocados, cero cuarentenas y cero referencias ausentes. Es evidencia de aquel instante, no un inventario de producción o del estado del demo después de todas las acciones manuales. El script `tool/demo/migrate-phase5.mjs` solo acepta el bucket demo y URLs locales; **no sirve para migrar las URLs reales**. Los migradores Fase 2/3 fueron retirados y abortan: no recuperarlos de otra rama para evitar el cierre de URLs públicas.

La revocación de tokens no se consigue cambiando Firestore o haciendo merge de Git. Debe realizarse sobre Storage mediante API privilegiada y comprobarse sin sesión; no puede revertirse activando de nuevo tokens divulgados. La migración real necesita conocer el bucket real configurado, que no tiene por qué usar el sufijo `.appspot.com` del demo. Ninguna cuenta, bucket ni URL de producción fue consultada aquí.

### Backend y despliegue: bloqueo vigente

`tool/backend/emulator.mjs` rechaza proyectos que no empiezan por `demo-`, exige hub/puertos locales y configura el bucket demo. La autorización de fotos de terceros en `profile-media.mjs` también exige REST del emulador de Firestore. `VerificationClient` usa el proxy local con `TINDER_DEMO=true`; fuera de demo necesita `VERIFICATION_BACKEND_URL` HTTPS. **Configurar solo esa variable no convierte este backend en un servidor de producción.**

Faltan un inicializador de producción revisado, IAM mínimo, HTTPS y validación de tokens reales, equivalente seguro de la consulta de visibilidad con las reglas, aislamiento/recursos del decodificador, límites distribuidos, scheduler/colas supervisados, observabilidad, procedimientos de bootstrap/recuperación y migradores con simulación y rollback. No quitar los guards demo para resolverlo.

No existe `firestore.indexes.json` ni declaración de índices en `firebase.json`, ni configuración de Functions/Hosting para este servidor. Probar y versionar los índices necesarios para las consultas administrativas y de limpieza en un entorno de validación apropiado antes de desplegar. El emulador no acredita todos los requisitos operativos/índices del servicio real.

FFmpeg 9.0.2 se instala localmente fuera de Git y el backend utiliza rutas Windows `.exe`. Un checkout nuevo necesita preparación reproducible; un runtime Linux requiere empaquetado distinto, licencia, sandbox y pruebas. La publicación parcial de reglas actuales, sin estos componentes y migración, rompería fotografías, chat y acceso de usuarios anteriores.

## 4. Separación del demo y de una futura compilación de producción

Versionar una herramienta interna de demo no significa incluirla en un APK o Hosting de producción. Separar **repositorio**, **artefacto de aplicación** y **datos operativos**:

| Archivos/elementos | Tratamiento propuesto |
| --- | --- |
| `lib/main_demo.dart`, `lib/main_demo_android.dart` | Conservar para pruebas; nunca usarlos como target de producción ni activar `TINDER_DEMO` en producción. |
| `android/app/src/demo/**` | Exclusivos del flavor demo: identificador `.demo`, opciones ficticias y excepción HTTP local. Producción debe seleccionar `standard`. |
| `tool/demo/**`, incluidos bootstrap, seeds, mic-check y micrófono sintético | Herramientas internas; no publicarlas como sitio/endpoint de producción ni ejecutarlas sobre cuentas reales. El micrófono sintético solo se activa explícitamente en el demo. |
| `firebase.demo.json`, `firebase.phase3-tests.json`, `firebase.teacher-rules.json`, `tool/load-phase5-demo-rules.mjs` | Configuración/pruebas locales; no son manifiestos de deploy de producción. Usar proyecto/config explícitos. |
| `integration_test/**`, `test/**` | Pruebas; no seleccionar el integration test como entrada de una app distribuida. |
| `lib/features/profile/demo_photo_url.dart` | Helper histórico importado por pruebas, no por el flujo productivo actual; no restaurar un fallback de descargas legacy. |
| `audit-*`, APKs, capturas, voz, exportaciones Auth/Firestore/Storage, parches, archivos VM/debug | Respaldar de forma privada; no incluir automáticamente en commits, releases o Hosting. Algunos contienen identificadores o metadatos de pruebas. |
| `build/**`, `.dart_tool/**`, `.firebase/**`, `tool/node_modules/**`, `tool/ffmpeg/**`, cachés y vendor generado | Artefactos/dependencias locales. Reconstruir o empaquetar selectivamente con licencias/hash; no copiar la carpeta completa a producción. |
| `PRUEBAS_ANDROID_USB.md` y registros del teléfono | Revisar/redactar el identificador físico y detalles locales antes de publicarlos; mantener el original en el respaldo privado. |
| `lib/main.dart`, `lib/firebase_options.dart`, `android/app/google-services.json` | Siguen siendo la entrada y configuración reales heredadas, sin cambios respecto de main. **No ejecutar esa entrada para el demo**. Las API keys de cliente no son credenciales Admin, pero tampoco configuran el backend seguro pendiente. |

Se encontró `IntegrationTestPlugin` en el registrante Android generado para el trabajo actual. No se ha compilado/inspeccionado un release en esta auditoría; no asumir que todos los componentes nativos de prueba desaparecen únicamente por estar en `dev_dependencies`. Auditar el artefacto release y sus registrantes/recursos antes de distribuirlo. El archivo generado no se versiona.

La configuración `release` todavía firma con `debug`: comportamiento heredado, no resuelto por estas fases. Es otro requisito de publicación pendiente. El manifiesto demo restringe HTTP a loopback, pero no es un firewall de HTTPS; conservar aislamiento de red durante pruebas físicas. El endpoint demo depende de USB y de la PC, nunca debe presentarse como versión independiente para usuarios finales.

## 5. Riesgos y validación disponible

| Riesgo / condición | Estado y efecto |
| --- | --- |
| Pérdida de trabajo sin commit | Alto: 36 modificados y 129 nuevos. Un merge de la referencia remota o un parche solo de tracked omite las fases. Respaldar y consolidar antes de integrar. |
| Despliegue parcial | Bloqueante: reglas privadas y cuentas fail-closed necesitan backend y migración coordinados. |
| Alertas npm | Auditoría guardada: 3 paquetes con alerta alta en la cadena de desarrollo `firebase-tools → chokidar → braces`; 0 alertas de ejecución en aquella auditoría. No equivalen a tres vulnerabilidades independientes ni a una garantía actual de seguridad. |
| Corrección de braces | Se volvió a consultar el [aviso GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm): sin versión corregida indicada, afecta hasta 3.0.3. La auditoría local propone una degradación mayor del CLI; no aplicarla automáticamente. |
| Flutter/dependencias | Último `pub outdated` guardado: 47 paquetes, sin avisos en versiones actuales ni retiradas. Repetir auditorías en la copia de integración; hoy no se ejecutó npm/pub porque pueden escribir cachés/logs. Mantener locks y evitar upgrades generales. |
| Transporte del SDK Storage | Sigue el aviso MaxListeners en `teeny-request`/PassThrough; falta prueba de carga/memoria. No se ocultó ni se declara resuelta una fuga. |
| Privacidad y retención | Faltan decisión institucional sobre carnets/metadata/auditoría, apelación/fraude, versiones/backups y conservación de chats cerrados. Decodificar no es antivirus ni validación de pertenencia. Los bytes originales pueden conservar EXIF. |
| Limpieza y escala | Medios tienen staging, reintentos y reconciliación paginada. El worker de carnets/reportes aún requiere revisión de escala, supervisión y alarmas; no prometer borrado físico instantáneo. |
| Rollback de datos | Git no revierte decisiones, eliminaciones ni tokens. Recuperación de datos y de autorización exige otro plan; no reabrir permisos antiguos ni reactivar URLs filtradas. |

Evidencia revisada, **sin repetir pruebas hoy**:

| Comprobación | Evidencia existente |
| --- | --- |
| Análisis del cambio Android físico | `audit-android-usb-analyze-final.log`: sin observaciones |
| Flutter | `audit-android-usb-flutter-tests.log`: 271 aprobadas |
| Firebase/backend | 148 reglas + 36 backend/roles + 24 seguridad = **208 aprobadas**; logs finales Fase 5 |
| Demo | `audit-phase5-demo-acceptance-second.log`: 10 aprobadas |
| Compilaciones | Web Fase 5 y APK debug demo corregido compilados |
| Teléfono físico | `audit-android-usb-runtime.json` e `installation.json`: paquete demo instalado, LoginScreen, proyecto demo, Firestore `127.0.0.1:8088`; los cinco puertos respondieron desde Android por USB, incluidos rechazos 401/403 sin sesión |

El usuario informa haber completado sus pruebas manuales Android. Los registros técnicos disponibles certifican instalación, arranque/configuración/transporte, no por sí solos la audibilidad o todos los flujos manuales. Conservar una lista de aceptación de los casos ejecutados antes de distribución. No se declara certificación nueva de Chrome/Edge, iOS o release de producción.

## 6. Estrategia propuesta y comandos futuros — NO ejecutados

Todos los bloques siguientes son una propuesta para una **autorización posterior**. No ejecutarlos como parte de esta auditoría. Se encadenan en la misma sesión PowerShell y reutilizan sus variables; detenerse en cada revisión indicada. Mantener main y el directorio original intactos; preparar el resultado en una copia Git independiente dentro de `build`, que está ignorado. Un clon independiente evita experimentar con el índice del worktree de producción y no necesita modificar sus archivos.

### A. Revalidar y respaldar antes de crear commits

En PowerShell desde la copia de pruebas. Si los SHA o el estado del original cambiaron, detenerse y actualizar este informe; si alguna orden nativa falla, no continuar con el bloque siguiente.

```powershell
$ErrorActionPreference = 'Stop'
$tests = 'C:\Users\HP\Desktop\tinder_universitario_pruebas'
$original = 'C:\Users\HP\Desktop\tinder_universitario'
$mainBase = 'd18360d26648f1296272cce9887692d5b5dcf383'
$featureBase = '2b448ae41fe4e0fbab38cf632cc4003440252b41'
Set-Location -LiteralPath $tests
if ((git --no-optional-locks rev-parse main) -ne $mainBase) { throw 'main cambió' }
if ((git --no-optional-locks rev-parse HEAD) -ne $featureBase) { throw 'HEAD cambió' }
if (@(git --no-optional-locks -C $original status --porcelain).Count -ne 0) {
    throw 'El original tiene cambios; no continuar'
}
git --no-optional-locks -c credential.helper= ls-remote origin refs/heads/main refs/heads/feature/vista-previa-visto-checks-imagenes-audio
# Comparar los dos resultados con los SHA anteriores. Si difieren, detenerse.

$backup = Join-Path $tests ('build\respaldo-preintegracion-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
git --no-optional-locks bundle create (Join-Path $backup 'historial.bundle') --all
if ($LASTEXITCODE -ne 0) { throw 'Falló el bundle' }
git --no-optional-locks bundle verify (Join-Path $backup 'historial.bundle')
if ($LASTEXITCODE -ne 0) { throw 'Bundle no verificable' }
git --no-optional-locks diff --binary --output="$backup\tracked.patch" HEAD
if ($LASTEXITCODE -ne 0) { throw 'Falló el respaldo del diff' }

# El ZIP preserva rutas, incluidos TODOS los nuevos no ignorados; el bundle no los contiene.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files = @(git --no-optional-locks ls-files --cached --others --exclude-standard)
$archive = [IO.Compression.ZipFile]::Open(
    (Join-Path $backup 'fuentes-sin-commit.zip'), [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relative in $files) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, (Join-Path $tests $relative), $relative.Replace('\','/'),
            [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
Get-FileHash -LiteralPath (Join-Path $backup 'fuentes-sin-commit.zip') -Algorithm SHA256
```

El ZIP y bundle son privados. Verificar el inventario del ZIP y conservar otra copia aprobada del respaldo; no subirlo al repositorio. No borrar/reemplazar los respaldos anteriores. El ZIP no incluye ignorados: preservar por separado los exports, licencias/runtime de FFmpeg y otros recursos locales necesarios. Las dependencias y vendor se pueden reconstruir, pero documentar su versión y hash.

Para una copia **actual** de los datos del demo, en una ventana autorizada sin escrituras de los clientes, este comando adicional exportaría a una ruta nueva (no ejecutado hoy):

```powershell
node tool/node_modules/firebase-tools/lib/bin/firebase.js emulators:export "$backup\demo-actual" --project demo-tinder-universitario --config firebase.demo.json --non-interactive
if ($LASTEXITCODE -ne 0) { throw 'No continuar sin exportación comprobada' }
```

El export anterior `build/phase5-fixtures-final` existe, pero precede a las últimas pruebas manuales; no representa necesariamente el estado actual. Exportar servicios distintos no constituye una transacción distribuida: evitar escrituras durante esa ventana y comprobar el resultado.

### B. Consolidar el trabajo completo, sin mover main

Antes del commit, corregir en esta rama las instrucciones obsoletas y revisar que los archivos seleccionados no contengan secretos, seriales físicos o material personal. Estos cambios editoriales quedan para la operación autorizada; no se hicieron hoy.

```powershell
git switch -c codex/consolidacion-fases-1-5
if ($LASTEXITCODE -ne 0) { throw 'No se creó la rama de consolidación' }

$tracked = @(git --no-optional-locks diff --name-only HEAD)
$newSources = @(git --no-optional-locks ls-files --others --exclude-standard -- lib test integration_test android/app/src/demo tool/backend tool/demo)
$additional = @(
    'firebase.demo.json', 'firebase.phase3-tests.json', 'firebase.teacher-rules.json',
    'tool/download-ffmpeg.mjs', 'tool/load-phase5-demo-rules.mjs',
    'tool/phase3.test.mjs', 'tool/phase5.test.mjs',
    'tool/setup-media-decoder.ps1', 'tool/test-media.mjs',
    'INFORME_FASE1_FOTOGRAFIAS.md', 'INFORME_FASE2_DOCENTE.md',
    'INFORME_FASE3_VERIFICACION.md', 'INFORME_FASE4_ADMINISTRACION.md',
    'INFORME_FASE5_SEGURIDAD.md', 'INFORME_PREINTEGRACION.md'
)
$paths = @($tracked) + @($newSources) + @($additional)
git add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'Revisar selección; no continuar' }
$staged = @(git --no-optional-locks diff --cached --name-only)
if ($staged | Where-Object { $_ -match '^(audit-|build/|\.firebase/|tool/(node_modules|ffmpeg|emulator-cache|demo/vendor)/)' }) {
    throw 'Hay artefactos en staging: revisar antes de continuar'
}
git diff --cached --check
git diff --cached --stat
git diff --cached
# Detenerse aquí para revisar el diff completo. NO usar git add . ni git add -A.
```

Los 34 `audit-*` y guías no seleccionadas permanecen respaldados y fuera del commit; no borrarlos. La guía Android con serial físico se podrá incorporar después de redactar una versión pública, no mediante inclusión masiva. Los fixtures sintéticos y herramientas demo del código pueden versionarse como herramientas internas; nunca incluir datos/exportaciones reales o ficticias completas en el artefacto de producción.

Solo después de la revisión autorizada:

```powershell
git commit -m "Consolidar fases 1 a 5 y demo Android aislado"
if ($LASTEXITCODE -ne 0) { throw 'Falló la consolidación' }
$snapshot = (git rev-parse HEAD).Trim()
# Guardar este SHA junto al respaldo. main sigue en $mainBase.
```

Un único checkpoint completo evita commits intermedios donde las importaciones o reglas requieran archivos todavía ausentes. No se afirma una separación histórica por fases que no existe en Git.

### C. Preparar una integración independiente y revisable

```powershell
$integration = Join-Path $tests 'build\integracion-local-fases-1-5'
if (Test-Path -LiteralPath $integration) { throw 'Destino existente; no sobrescribirlo' }
git clone --no-hardlinks $tests $integration
if ($LASTEXITCODE -ne 0) { throw 'Falló el clon independiente' }
git -C $integration switch -c codex/integracion-local-fases-1-5 $mainBase
if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar la rama independiente' }
git -C $integration merge --no-ff --no-commit $snapshot
if ($LASTEXITCODE -ne 0) { throw 'Hay conflictos o falló merge; revisar sin continuar' }
git -C $integration status --short
git -C $integration diff --cached --check
git -C $integration diff --cached --stat
```

Ese merge futuro se realizaría **solo en el clon**, desde la base comprobada; no en main ni en los dos árboles actuales. `--no-ff --no-commit` deja un resultado revisable aun cuando la historia admita fast-forward. Si main cambió, no continuar con esa base antigua como si fuera actual: volver a auditar y obtener su nuevo estado mediante una operación autorizada.

El destino bajo `build` mantiene toda la operación dentro de la carpeta autorizada, pero crea un proyecto Dart anidado. Validar desde el clon, no desde el directorio padre mientras exista esa copia temporal: el analizador del padre solo excluye explícitamente `tool/node_modules/**` y ya detectó una copia `.dart` de respaldo en build en una comprobación anterior. Antes de volver a analizar el padre, archivar la copia temporal o acordar una exclusión específica en la operación autorizada; no se cambia hoy `analysis_options.yaml`.

### D. Validar el resultado antes de confirmar la integración local

Ejecutar únicamente dentro de `$integration`. No arrancar otro demo completo en los puertos 7357/7360/9099/8088/9198 ni reiniciar el actual. Para Firebase/backend usar el proyecto secundario y puertos distintos; los tests limpian datos de su proyecto y no deben apuntar al demo usado manualmente.

```powershell
Set-Location -LiteralPath $integration
flutter pub get
npm --prefix tool ci --ignore-scripts
powershell -NoProfile -File tool/setup-media-decoder.ps1
flutter analyze
flutter test --concurrency=1

$env:RULES_PROJECT = 'demo-tinder-phase3-tests'
$env:RULES_FIRESTORE_PORT = '8188'
$env:RULES_STORAGE_PORT = '9298'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
$env:FIREBASE_EMULATORS_PATH = Join-Path $integration 'tool\emulator-cache'
# Comprobar antes que 9199/8188/9298/4410/4510/9151 estén libres; no matar procesos ajenos.
node tool/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --only auth,firestore,storage --project demo-tinder-phase3-tests --config firebase.phase3-tests.json "node --test --test-concurrency=1 tool/rules.test.mjs tool/phase3.test.mjs tool/phase5.test.mjs"

# Pruebas estáticas del guard Web; no requieren tocar los datos del demo principal.
node --test tool/demo/auth-demo.test.mjs tool/demo/browser.test.mjs
flutter build web --target lib/main_demo.dart --output build/demo-web --no-web-resources-cdn --dart-define=TINDER_DEMO=true --dart-define=CHAT_STORAGE_ORIGIN=http://127.0.0.1:9198
flutter build apk --debug --flavor demo --target lib/main_demo_android.dart --dart-define=TINDER_DEMO=true
npm --prefix tool audit --omit=dev
npm --prefix tool audit
flutter pub outdated
```

Revisar **cada código de salida** antes del siguiente paso; PowerShell puede continuar tras un fallo de un programa nativo. No aplicar correcciones automáticas de vulnerabilidades ni actualizar versiones para ocultar alertas. Las tres suites Firebase se ejecutan secuencialmente porque comparten proyecto de pruebas y lo limpian. No ejecutar `tool/rules.test.mjs` sin esas variables: su valor predeterminado apunta al demo principal.

La suite completa de 10 pruebas demo incluye conexiones al demo vivo. Su comando es `node --test tool/demo/*.test.mjs`, pero requiere una ventana explícita de aceptación después del respaldo y de comprobar fixtures/servicios; no forma parte de la validación aislada automática anterior. No atribuir al clon los resultados históricos ni dar por aprobados nuevos resultados hasta ejecutarlos. También repetir la aceptación Web/Android del commit consolidado, sin instalar una variante `standard` o un integration test por accidente.

Si todo pasa y se aceptó el diff, confirmar **solo la rama de integración**:

```powershell
git -C $integration diff --exit-code
if ($LASTEXITCODE -ne 0) { throw 'Las validaciones dejaron cambios sin revisar: comparar, preparar explícitamente y repetir pruebas' }
git -C $integration status --short
git -C $integration diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Corregir el diff antes de confirmar' }
git -C $integration commit -m "Integrar localmente las fases 1 a 5 sobre la base auditada"
if ($LASTEXITCODE -ne 0) { throw 'Falló el commit de integración' }
$mergeCommit = (git -C $integration rev-parse HEAD).Trim()
git -C $integration log --graph --oneline -4
git --no-optional-locks -C $original rev-parse main
# Debe seguir siendo d18360d26648f1296272cce9887692d5b5dcf383.
```

El paso de transferir ese resultado a main, publicar un PR, hacer push o desplegar **no está autorizado y no está incluido en estos bloques**. Requiere otra revisión y autorización. El clon tiene un repositorio independiente: su nuevo commit de merge no aparece mágicamente en el repositorio original; esa transferencia debe planificarse cuando corresponda, sin confundir refs/objetos entre los dos.

### E. Reversión sin afectar los proyectos actuales

Si el merge aún no se confirmó y se desea cancelarlo, únicamente en el clon de integración, creado limpio:

```powershell
git -C $integration merge --abort
```

Si ya se confirmó y se autorizó revertir el resultado local, el primer padre del merge es la base main auditada:

```powershell
git -C $integration revert -m 1 $mergeCommit
```

Esto conservaría la historia y crearía una reversión local; no usar reset, clean, borrados recursivos ni force push. Si se añadieron otros cambios en el clon, revisar antes de abortar/revertir. La rama de consolidación, el bundle y el ZIP permiten recuperar el trabajo sin tocar el original. Ninguna de estas operaciones revierte Firebase, tokens o eliminaciones: al no migrar datos reales en esta integración local se evita introducir ese problema. Un rollback futuro de producción debe mantener la denegación segura y usar respaldos y procedimientos separados.

## 7. Decisión final

**Sí a preparar una rama local de integración con respaldo, selección completa y revisión. No a integrar ya directamente en main como una versión lista para usuarios reales.** El estado de Git es favorable —base común, main limpio y sin divergencia— y existe una batería de regresión considerable. Lo pendiente es consolidar de forma reproducible un trabajo que hoy no está en Git y respetar sus dependencias de datos/backend.

Para considerar un despliegue se necesitan, además, migración real revisada, backend de producción, configuración/firma/artefacto release, operación de limpieza, políticas de privacidad/retención y resolución o aceptación documentada de dependencias y pruebas de carga. No se resolverá nada de eso relajando reglas, aprobando cuentas automáticamente o volviendo a URLs públicas.

### Conservación comprobada al finalizar

Se comparó una huella conjunta de los **230 archivos versionados y nuevos no ignorados preexistentes**, excluyendo este informe, antes y después de la auditoría. Coincidió: SHA-256 `3fc0bffcee23defaa7b7eb9b6a0bcbdd8aecddfb751f44a8d5806da84b6ec5cc`. El HEAD de pruebas sigue en `2b448ae`, el índice sigue vacío y el original continúa limpio en `d18360d`. Los cinco listeners del demo conservaron sus direcciones loopback y procesos. La única incorporación realizada es `INFORME_PREINTEGRACION.md`; no se alteraron datos, servicios ni archivos de trabajo anteriores.
