# Staging local LIGO

## Arranque habitual con datos persistentes

Desde la raíz de la rama `codex/ligo`:

```powershell
node tool/ligo/start-local.mjs
```

También puedes abrir `staging/ABRIR_LIGO.cmd` con doble clic. Mantén esa ventana abierta y la computadora encendida. Este lanzador arranca Auth, Firestore, Storage, backend y Web en los puertos exclusivos de LIGO, importa el último respaldo verificado y exporta los tres servicios cada cinco minutos. Ctrl+C intenta una exportación final antes de detener únicamente sus procesos. Un cierre forzado o apagón puede perder cambios posteriores a la última exportación; no cerrar a la fuerza la ventana.

Respaldos completos inmutables y manifiestos SHA-256: `build/ligo-staging/persistent/exports/`; referencia al último: `build/ligo-staging/persistent/latest.json`. No borrar `build/ligo-staging/persistent`, no ejecutar `flutter clean` sin copiar primero esos respaldos fuera de `build`, y no subirlos a Git. Los temporales se separan por ejecución y por backend. Si los puertos están ocupados, el lanzador se detiene sin matar ni reemplazar servicios existentes.

El 2 de noviembre de 2026 se reconstruyeron con autorización las cinco cuentas ficticias originales: el staging anterior no tenía exportaciones de Auth/Firestore y sus cambios manuales no fueron recuperables. Se conservaron los cuatro blobs encontrados y sus hashes en `build/ligo-staging/recovery-evidence`. La reconstrucción inicial usó `--reconstruct-fixtures`; **no repetir ese argumento para el uso habitual**. El arranque normal se niega a iniciar vacío cuando falta un respaldo válido.

Los siguientes comandos de arranque antiguo y pruebas son para entornos descartables, no para abrir el staging manual persistente.

Solo emuladores, datos ficticios y rama `codex/ligo`. No crea un proyecto Firebase remoto, no importa datos reales y no cambia los demos existentes. El identificador local es `demo-ligo-staging`.

## Servicios separados

Auth 9399; Firestore 8288 y WebSocket 9165; Storage 9498; hub 4420; logging 4520. Web `http://127.0.0.1:7465/`, backend 7466. Todos en loopback. TEMP/TMP exclusivos por ejecución en `build/ligo-staging/runs/<uuid>/temp`; el lanzador rechaza puertos ocupados y credenciales de servicios reales.

## Ejecución (desde la raíz de esta copia)

Requisitos: dependencias Flutter resueltas, Node y dependencias de `tool`, JDK de Android Studio. Las pruebas multimedia de regresión necesitan FFmpeg/FFprobe en la ubicación ignorada existente `tool/ffmpeg/...`; nunca versionar binarios, credenciales o exportaciones.

Terminal 1:

```powershell
node tool/ligo/staging.mjs start
```

Solo en un staging nuevo y vacío, en otra terminal:

```powershell
node tool/ligo/seed.mjs
```

Este comando se niega a sobrescribir un staging ya inicializado. Crea tres cuentas ficticias con correo verificado, datos mínimos y acceso aprobado para probar las interfaces:

- `ligo_root@ligo.test`: superadmin.
- `ligo_admin@ligo.test`: admin.
- `ligo_student@ligo.test`: user.

Contraseña común ficticia: `Ligo-staging-2026!`. No usar estas cuentas o contraseña fuera de emuladores.

Compilar y preparar Web:

```powershell
flutter build web --release --no-pub --target=lib/main_ligo_staging.dart --dart-define=LIGO_STAGING=true --no-web-resources-cdn --no-wasm-dry-run --output=build/ligo-staging/web
node tool/ligo/prepare-web.mjs
node tool/ligo/server.mjs
```

`prepare-web` descarga únicamente módulos públicos del SDK desde gstatic, comprueba importaciones y los sirve localmente junto con fuentes del SDK Flutter. Alternativa sin descarga: `--cache-dir <directorio>` con los cinco módulos y `sdk-version.json` de la misma versión. No lee recursos Firebase reales. La página en ejecución solo permite conexiones a los puertos locales enumerados; no relajar su CSP.

En el panel administrativo actual: menú «Administrar catálogos». Universidades solo superadmin; carreras e intereses admin/superadmin. Probar crear, editar y desactivar; no existe borrado físico. El registro de una cuenta ficticia nueva pide universidad y carrera; correo de prueba puede verificarse exclusivamente mediante Auth Emulator para completar el recorrido.

## Pruebas

Con este staging detenido (sin tocar otros demos):

```powershell
node tool/ligo/staging.mjs test
node tool/ligo/staging.mjs regression
flutter analyze
flutter test
```

Las pruebas crean y limpian sus propios fixtures en estos puertos: no ejecutarlas contra un staging manual que se quiera conservar. El lanzador rechaza cualquier instancia ya activa. No usar comandos genéricos para detener Java/Node ni borrar carpetas temporales compartidas. Este staging es volátil y no importa respaldos automáticamente.


## Rediseño visual LIGO

La portada Web, el dashboard y la aplicación Android comparten los activos de `assets/branding/ligo/` y el tema central. El panel usa `/administration/summary` y `/administration/users`: operaciones de lectura con autorización vigente en el backend, sin documentos de identidad ni URLs con token. La búsqueda y los filtros de la tabla se aplican a las páginas cargadas; «Cargar más» amplía ese conjunto. Las fotografías mantienen sus permisos originales: un administrador no obtiene acceso adicional a ellas por aparecer en la tabla.

Cuentas adicionales ficticias con perfil completo: `ligo_visual_ana@ligo.test` y `ligo_visual_bob@ligo.test`, con la misma contraseña local indicada arriba. Sus imágenes son sintéticas. El recorrido Android creó entre ellas un match y mensajes ficticios; no restablecer los datos del staging para repetir una captura.

Para agregar estos fixtures en un staging que todavía no los contiene:

```powershell
node tool/ligo/seed-visual.mjs --create-fictitious-only
```

El script rechaza sobrescrituras. No debe ejecutarse contra Firebase real.

APK exclusivamente local:

```powershell
flutter build apk --debug --flavor ligostaging --target=lib/main_ligo_staging.dart --dart-define=LIGO_STAGING=true --no-pub
adb -s <dispositivo> reverse tcp:9399 tcp:9399
adb -s <dispositivo> reverse tcp:8288 tcp:8288
adb -s <dispositivo> reverse tcp:9498 tcp:9498
adb -s <dispositivo> reverse tcp:7466 tcp:7466
adb -s <dispositivo> install -r build/ligo-delivery/ligo-staging-debug.apk
```

La variante tiene identificador `.ligostaging`, etiqueta LIGO STAGING y configuración Firebase ficticia. Necesita estos servicios locales; no es una APK online ni de producción. La restricción nativa de red conserva HTTP únicamente para loopback y una raíz HTTPS local sin confianza en servicios externos.

Prueba adicional de endpoints que puede ejecutarse con este staging activo, sin vaciarlo:

```powershell
node --test tool/ligo/administration-read.test.mjs
```

Esta prueba solo crea y elimina sus propios fixtures con prefijo aleatorio; no usar en su lugar los comandos generales de regresión sobre un staging manual activo.
