# Preparación de la rama de integración local

Fecha: 19 de octubre de 2026, America/La_Paz. Directorio de trabajo: `C:\Users\HP\Desktop\tinder_universitario_pruebas`.

**Resultado Git:** trabajo de las cinco fases consolidado en `feature/integracion-tinder`, desde `2b448ae41fe4e0fbab38cf632cc4003440252b41`. No se hizo merge, rebase, push ni deploy. No se utilizó Firebase de producción. `main` y el worktree original permanecen en `d18360d26648f1296272cce9887692d5b5dcf383`, sin cambios de archivos ni del índice del original. **El cierre del demo queda pendiente:** después de pasar las pruebas, terminó inesperadamente su proceso Auth/Storage/hub; se preservaron respaldos y se solicitó autorización antes de importar datos (sección 5).

## 1. Estado inicial y respaldo comprobado

Se releyó `INFORME_PREINTEGRACION.md` y se revisaron ambos worktrees. La copia estaba en HEAD separado, con 36 archivos versionados modificados, 130 nuevos no ignorados y ningún cambio preparado/conflicto. El original estaba limpio en main. Los dos worktrees comparten el directorio Git: los commits agregan objetos y una referencia nueva al repositorio común, sin mover main ni escribir en los archivos del original.

Respaldo válido, creado **antes de modificar los archivos preexistentes y antes de crear la rama**:

```text
C:\Users\HP\Desktop\tinder_universitario_pruebas\build\respaldo-integracion-20261019-222416
```

| Contenido | Comprobación realizada |
| --- | --- |
| `historial.bundle` | `git bundle verify`: historia completa y válida; incluye la base y referencias anteriores |
| `tracked.patch` | Diff binario de todos los cambios versionados iniciales respecto de HEAD |
| `fuentes.zip` | 231 archivos: todos los versionados y nuevos no ignorados, incluidos informes, parches y evidencias que después se excluyen del commit |
| `locales-privados.zip` | 1.001 archivos locales/ignorados relevantes: evidencias, exports anteriores, configuración local, vendor, FFmpeg/licencias y caché de emuladores, entre otros |
| `manifiesto-archivos.json` | SHA-256 individual de los 1.232 archivos archivados; se reabrió cada entrada ZIP y se comprobó su hash |
| `SHA256.json` | Hashes de ZIPs, bundle, manifiesto, patch, estado y referencias iniciales |
| `demo-actual/` | Export nuevo del demo vivo, aceptado por Firebase CLI local; Auth, Firestore y Storage; 10 cuentas Auth y 35 archivos de exportación |
| `SHA256-demo.json` | Inventario y hashes de los 35 archivos del export; metadata de las tres clases de servicio comprobada |
| `configuracion-generada/`, `SHA256-configuracion.json` | Copia adicional comprobada de configuración de paquetes/plugins Flutter y versión, recogida sin editarla |
| `estado-inicial.txt`, `referencias.txt` | Estado y referencias anteriores a la consolidación |
| `ignorados-reconstruibles-no-copiados.txt` | Inventario de dependencias/cachés/compilaciones regenerables excluidas de los ZIPs |

Hashes SHA-256 de los tres archivos principales:

```text
fuentes.zip          9C3A79CEC3347ACD4870A3423845CE7FDE6B9CDD74F783F3B6A61AABA14C04E8
locales-privados.zip 249904ACD0AF05DD97668B9E27D1C209A16F0D4272719ACB0DB6E047E116104C
historial.bundle     5E7F63DBF28BD85CAE83DA5F1781A02D13ADED8FB1C51D8B4448F64269BA46CA
```

No se copiaron `tool/node_modules`, la mayoría de `.dart_tool`, cachés Gradle ni salidas Android de compilación regenerables. Se conservan en su ubicación actual y se reconstruyen con los locks/SDK; no contienen código de las fases omitido. La configuración generada relevante se agregó por separado. No se borró ningún artefacto. El primer intento de respaldo, `build/respaldo-integracion-20261019-222356`, quedó incompleto por un log abierto; se conservó y **no debe usarse como respaldo válido**. El segundo leyó archivos con acceso compartido, sin cerrar los servicios.

El respaldo está fuera del índice, bajo `build`, y no se incorpora al repositorio. Contiene material local y datos ficticios con identificadores/sesiones de pruebas: no publicarlo. Está en el mismo disco; no constituye una segunda copia física ni está cifrado por este procedimiento.

### Recuperación sin sobrescribir trabajo

No se ejecutó recuperación ni importación sobre los servicios activos. Procedimiento futuro:

1. Comprobar hashes contra los JSON del respaldo y ejecutar `git bundle verify` sobre el bundle. Si no coinciden, detenerse.
2. Para recuperar los archivos previos a los commits, extraer `fuentes.zip` y `locales-privados.zip` en una **carpeta nueva y vacía**. No extraer sobre main ni sobre un worktree con cambios. Las rutas internas se conservaron; el patch es evidencia adicional, no sustituye los archivos nuevos.
3. Para recuperar historia, clonar el bundle en otra carpeta nueva y seleccionar la base `2b448ae`. El ZIP permite recuperar después el contenido de trabajo inicial; comparar antes de aplicar cualquier copia. No usar reset/clean en los proyectos actuales.
4. Para recuperar los datos, iniciar **un conjunto nuevo de emuladores o una ventana de recuperación autorizada**, con `--project demo-tinder-universitario --config firebase.demo.json --import <respaldo>\demo-actual`. No iniciar duplicados en los puertos ocupados. El export entre servicios no es una transacción distribuida; comprobar cuentas, referencias y medios después de importar.
5. Restaurar recursos locales selectivamente y comprobar hashes; reconstruir dependencias con `flutter pub get`, `npm --prefix tool ci --ignore-scripts` y la preparación FFmpeg documentada. No ejecutar seeds sobre datos recuperados.

Los ZIPs se verificaron íntegramente y el CLI completó el export, pero no se probó hoy una importación completa en otro entorno. Git tampoco revierte cambios de datos, borrados o tokens.

## 2. Rama y commits locales

La rama se creó mediante `git switch -c feature/integracion-tinder`, conservando el contenido del worktree y sin checkout de main.

| Commit | Organización |
| --- | --- |
| `8e6045f42d5226bf2177f5e8788a17e70ac5aa3f` | Producto: chat/voz, preferencias, perfiles, fotos privadas, verificación/administración, backend, reglas, dependencias y permiso Android; 50 archivos |
| `88108fa9be4e78ddb15b035c571e3e78f242f1ae` | Demo aislado Web/Android, configuraciones locales, migraciones demo, herramientas y regresiones; 71 archivos |
| `a97242fc63126acd09f1b4d6a928db44b3fec662` | Corrección de la prueba demo para aceptar fotografías cambiadas manualmente y verificar sus bytes/autorización, sin restablecer datos |
| `7a2db0b2f90df3fbb926b4d0b20aa6b238eaa4b1` | `docs: documentar respaldo y validacion de rama de integracion`; informes históricos, guías actualizadas y este informe |
| Commit documental que contiene esta actualización (`HEAD`) | `docs: registrar interrupcion del demo y recuperacion pendiente`; incidente detectado al verificar por última vez |

El identificador del último commit se obtiene con `git log -1 --format="%H %s"`; no se escribe su hash dentro del archivo que determina ese mismo hash. Los commits de producto/demo forman una unidad de revisión: no seleccionar solo el primero para integrar ni reconstruir una falsa historia por fases.

Antes de **cada** commit se enumeraron los archivos preparados, se revisó el diff y se ejecutó una inspección de blobs del índice para claves privadas, cuentas de servicio, JWT/OAuth literales, tokens GitHub/AWS, identificador del teléfono y rutas excluidas. Sin coincidencias prohibidas. Las API keys públicas de configuración Firebase cliente, heredadas de main, no son secretos Admin; no se ejecutaron sus entradas. Las contraseñas que aparecen en herramientas/guías son exclusivamente las ficticias del proyecto demo.

El script de inspección y sus resultados `build/revisar-indice-integracion.mjs`, `build/revision-commit-*.json` quedan como evidencia local. Una búsqueda de patrones no constituye garantía matemática de ausencia de secretos; se complementó con revisión de selección y configuración. No se instalaron hooks ni dependencias nuevas.

### Ajustes de consolidación

- Se añadieron exclusiones para evidencias `audit-*.json/patch`, `.env`, keystores y archivos de cuenta de servicio. No se borraron esos archivos.
- Se actualizaron README y guía manual: ya no indican desplegar reglas, ausencia de micrófono, migradores retirados ni reinicios con exports antiguos. Se conserva el detalle histórico en los informes y el respaldo.
- La guía Android usa `ID_DEL_DISPOSITIVO`, obtenido localmente con `adb devices`, en lugar del serial físico. El documento original está en el ZIP privado.
- Se quitaron líneas vacías finales marcadas por `git diff --check` en siete archivos de código/configuración/pruebas. No cambia comportamiento.
- La primera ejecución demo falló por una expectativa rígida del seed: Ana había cambiado su foto principal. La prueba ahora valida rutas privadas propias, galería válida, principal incluida, rechazo SDK y bytes autenticados de todas las fotos actuales. No se cambió su perfil ni se relajaron reglas.

## 3. Archivos incluidos y excluidos

**Producto:** `lib/features/**`, `lib/widgets/app_ui.dart`, `firestore.rules`, `storage.rules`, manifiesto Android con micrófono, ajustes Gradle y manifiestos/locks Flutter y Node. El backend completo está en `tool/backend/`: inicialización demo cerrada, autorización, verificación, roles/auditoría, fotos, subida/lectura de chat, validación/decodificación, sellado privado y limpieza.

**Demo/pruebas, versionados para reproducibilidad:** `lib/main_demo.dart`, `lib/main_demo_android.dart`, flavor `android/app/src/demo/**`, configuración de flavors, `firebase.demo.json`, `firebase.phase3-tests.json`, `firebase.teacher-rules.json`, `tool/demo/**` sin vendor generado, herramientas FFmpeg con checksum, carga de reglas local, fixtures sintéticos de código, pruebas Flutter/integration/Node y catálogos existentes. No empaquetar estos servicios/configuraciones como Hosting ni como entrada de producción.

**Documentación:** README actualizado; guías manual y USB sin serial; informes de auditoría, voz, multimedia, fases 1–5, preintegración y este informe. Los informes anteriores preservan sus resultados históricos y no reemplazan el resultado actual.

**Excluidos y conservados localmente:** 34 archivos raíz `audit-*` JSON/patch, logs, datos de emuladores, carnets/archivos de ensayo, exportaciones, VM/debug URIs, capturas, APKs, bases locales, `.firebase`, `.dart_tool`, `build`, `tool/node_modules`, FFmpeg binario, vendor y caché de emuladores. No se agregaron cuentas de servicio, claves privadas, `.env`, keystores, credenciales de producción ni el serial del teléfono a los commits nuevos. Los fixtures de medios embebidos en pruebas son datos sintéticos deliberados, no una exportación de usuarios.

No se eliminaron archivos versionados frente a main. El código de las funcionalidades originales, sus pruebas y el commit de la compañera siguen en la historia. Se conserva el arranque original sin ejecutarlo. Revisar el conjunto exacto con:

```powershell
git log --oneline 2b448ae..feature/integracion-tinder
git diff --name-status 2b448ae feature/integracion-tinder
git show --stat 8e6045f
git show --stat 88108fa
git show --stat a97242f
```

## 4. Validación ejecutada después de consolidar código y entorno

| Comprobación | Resultado de esta sesión | Evidencia local |
| --- | --- | --- |
| `flutter analyze --no-pub` | Sin observaciones | `build/integracion-analyze.log` |
| `flutter test --no-pub --concurrency=1` | **271 aprobadas, 0 fallidas** | `build/integracion-flutter-test.log` |
| Firebase/backend, tres suites secuenciales | **208 aprobadas, 0 fallidas**, salida 0 | `build/integracion-firebase-test.log` |
| Demo, primera ejecución | 9 aprobadas, 1 fallida por foto del seed; corregido en `a97242f` | `build/integracion-demo-test.log` |
| Demo, repetición completa | **10 aprobadas, 0 fallidas** | `build/integracion-demo-test-final.log` |
| CLI catálogos existente | **4 aprobadas, 0 fallidas** | `build/integracion-catalogos-test.log` |
| Salud demo actual | Auth/Firestore/Storage/backend/proxy correctos; Ana/Bob aprobados y no suspendidos; descarga privada funciona y anónimo denegado | `build/integracion-demo-salud.log` |
| Salud, última repetición | **Falló**: fotografía devolvió 403; luego se comprobó proceso Auth/Storage/hub terminado y puerto 4400 rechazando conexiones | `build/integracion-demo-salud-final.log`, `build/integracion-diagnostico-demo.log` |
| `npm audit --omit=dev` | **0 vulnerabilidades notificadas**, salida 0 | `build/integracion-npm-runtime.json` |
| `npm audit` completo | **3 paquetes con alerta alta**, salida 1; misma cadena de desarrollo conocida | `build/integracion-npm-audit.json` |
| `git diff --cached --check`, revisión de índice | Pasaron antes de cada commit tras limpieza de EOF | `build/revision-commit-*.json` |

Se usó el ejecutable Dart del SDK local para invocar `flutter_tools.snapshot`, equivalente a los subcomandos Flutter indicados, sin resolver nuevamente dependencias. Las pruebas Flutter y el análisis no consultaron Firebase remoto.

Firebase/backend se ejecutó **solo** en `demo-tinder-phase3-tests`, con Auth 9199, Firestore 8188 y Storage 9298, hub 4410 y configuración `firebase.phase3-tests.json`. Se verificaron puertos libres y se establecieron `RULES_PROJECT`, `RULES_FIRESTORE_PORT`, `RULES_STORAGE_PORT` y caché local antes del CLI. Los tests destructivos no apuntaron al demo manual. Java tuvo heap acotado a 512 MiB en esos procesos secundarios. El CLI los cerró al terminar. Los rechazos PERMISSION_DENIED en el log son parte de los ataques que se comprueban, no pruebas fallidas.

No se recompiló ni reinstaló Web/Android en esta sesión: se preservaron el artefacto servido y la instalación previa. No se repitió hoy una prueba manual visual o de micrófono físico. Las pruebas de instalación/arranque y compilaciones anteriores siguen siendo evidencia histórica; los cambios de consolidación al runtime son de whitespace, documentación y pruebas. La aceptación manual del commit final y un checkout nuevo siguen siendo recomendables antes de autorizar la fusión.

## 5. Estado final y demo

En pruebas: rama `feature/integracion-tinder`, código y documentación versionados, sin cambios pendientes de producto ni archivos nuevos no ignorados después del commit documental. Respaldos, evidencias y recursos locales permanecen ignorados. El índice queda vacío.

En el original: `main`, HEAD y referencia main exactamente en `d18360d26648f1296272cce9887692d5b5dcf383`; árbol e índice limpios. `origin/main` tampoco se movió. No se hizo checkout ni edición en el proyecto original.

Al terminar las suites, los listeners eran Web 7357/PID 1380, backend 7360/PID 22160, Auth/Storage 9099/9198/PID 26384 y Firestore 8088/PID 21484, todos `127.0.0.1`. Sin embargo, **la última comprobación detectó una interrupción posterior**: el proceso 26384 terminó y dejaron de escuchar 4400, 9099 y 9198. Web/backend/Firestore siguen activos. No se reinició, reseedó ni migró el demo. Las comprobaciones de login pueden actualizar metadata de última sesión Auth; los intentos de escritura denegados no cambian perfiles.

**URL Web:** http://127.0.0.1:7357/ (entrada: http://127.0.0.1:7357/__demo/start.html). La página sigue servida, pero **no se considera demo funcional hasta recuperar Auth y Storage**.

Ana: `ana.manual@demo.test`; Bob: `bob.manual@demo.test`; contraseña ficticia `DemoTinder2026!`. Guías del repositorio documentan los demás roles. Mantener la PC encendida y los túneles USB si se utiliza el teléfono.

### Incidente final y recuperación preparada, NO ejecutada

`audit-phase4-emulators-local.log` termina con «Error: An unexpected error has occurred». Se comprobó que el proceso que alojaba Auth/Storage/hub ya no existe. El log disponible no establece la causa raíz; no se atribuye a reglas ni se afirma que la prueba secundaria lo haya causado. No se relajó seguridad para corregir el 403.

Antes de cualquier reinicio se exportó directamente el Firestore que sigue vivo a una ruta nueva, mediante la misma API local de exportación que utiliza el CLI:

```text
build/respaldo-integracion-20261019-222416/firestore-vivo-223840/
```

Respuesta 200; metadata e inventario SHA-256 conservados. El archivo de datos `output-0` coincide exactamente con el export completo de las 22:24: SHA-256 `4AC18BEAA74FA5C6F418E511E75AB60885205942B22946BC8D9F7297A2C6F7FD`. No se detectaron cambios en ese contenido Firestore entre ambos exports. Esto no permite recuperar cambios Auth/Storage no exportados.

Se preparó **sin importar ni sobrescribir** la carpeta `build/respaldo-integracion-20261019-222416/recuperacion-propuesta/`: Firestore de las 22:38 y Auth/Storage del respaldo completo de las 22:24. Se verificaron por hash los 34 archivos copiados; inventario en `SHA256-recuperacion-propuesta.json`. El snapshot completo inicial sigue intacto. También existe `rama-consolidada.bundle`, verificado, con los cuatro commits anteriores a este incidente, y `estado-consolidado.json`/`SHA256-consolidado.json` con sus identificadores.

Se solicitó autorización expresa para recuperar con esa combinación, porque no puede garantizarse preservar modificaciones de Auth/Storage posteriores a las 22:24. La instrucción del usuario exige detenerse ante una operación con posible pérdida de datos. **No se detuvo el Firestore vivo ni se importó el snapshot pendiente de esa respuesta.** Una recuperación autorizada deberá conservar nuevamente el Firestore vivo si cambió, liberar solo sus procesos identificados, arrancar los emuladores con proyecto/config/import explícitos y repetir salud/privacidad/demo. No usar seeds ni los exports de fases anteriores.

## 6. Riesgos y condiciones para integrar con main

**Consolidación Git completada; recuperación del demo pendiente de autorización.** La rama está disponible para revisión. Antes de recomendar una futura fusión local, recuperar el demo y repetir su validación. No se fusionó ni está lista para desplegar a producción.

1. Antes de una fusión, revisar el diff completo y revalidar main: esta sesión no actualizó referencias remotas. Si main gana cambios, recalcular conflictos; no usar una resolución que relaje reglas o restaure URLs tokenizadas. Integrar conjuntamente cliente/backend/reglas/pruebas, no cherry-picks parciales.
2. El backend continúa limitado a emuladores. Faltan implementación y revisión de producción, IAM mínimo, HTTPS, validación real, consulta equivalente de visibilidad, índices, límites distribuidos, sandbox del decodificador y tareas de limpieza supervisadas. No quitar los guards demo para desplegarlo.
3. Usuarios y medios legacy requieren una migración real distinta del script demo: inventario, backup, simulación, referencias/manifiestos, cuentas pendientes por defecto, bootstrap confiable y revocación de tokens comprobada. No aprobar cuentas reales automáticamente. Un rollback Git no revierte datos ni restituye archivos eliminados.
4. npm sigue informando `braces → chokidar → firebase-tools`: tres paquetes, una cadena de desarrollo. El audit propone bajar el CLI a 6.8.0 como cambio mayor; no se aplicó por incompatibilidad. Ejecución tiene cero avisos notificados hoy. Reevaluar versiones/aviso antes de una publicación; no equivale a ausencia de vulnerabilidades desconocidas.
5. Quedan pruebas de carga/memoria por el aviso previo de listeners de Storage, empaquetado multiplataforma/licencias de FFmpeg, revisión de EXIF, políticas institucionales de retención/carnets/auditoría, copias/versiones y recuperación. No se declaran resueltas al crear commits.
6. La firma release sigue usando configuración debug heredada. Auditar registrantes/plugins y el artefacto release; excluir targets/servicios demo y datos locales. Nunca publicar `build` o el worktree entero.
7. Validar desde un checkout nuevo y repetir aceptación Web/Android del commit final. Los resultados actuales usan dependencias y runtimes ya instalados, respaldados; no prueban una instalación completamente limpia ni una recuperación del export.

Una autorización posterior debe concretar la rama/worktree de destino y el método de revisión/reversión. No ejecutar merge, rebase, push, despliegues o migraciones reales basándose únicamente en este informe.
