# LIGO — compatibilidad multiuniversidad y CRUD administrativos

Implementado el 1 de noviembre de 2026 exclusivamente en `codex/ligo`, copia administrada `C:\Users\HP\.codex\worktrees\ligo\tinder_universitario_pruebas`. Sin commits, push, despliegue, consultas a producción ni migraciones. El rediseño visual LIGO y el nuevo dashboard no forman parte de esta etapa.

## Resultado

Registro autenticado por pasos con universidad y carreras activas vinculadas; universidad visible únicamente si existe explícitamente; filtro opcional por universidad compatible con carrera/edad; perfiles históricos sin afiliación conservados sin inferencias. Catálogos gestionables desde el menú del panel actual: universidades solo superadmin, carreras/intereses admin y superadmin.

Escrituras mediante backend autenticado con transacciones, idempotencia, revisión optimista, duplicados normalizados y auditoría. No hay borrado físico ni reasignación de carreras históricas. Las reglas rechazan escrituras directas y afiliaciones manipuladas. Desactivaciones conservan estudiantes y referencias guardadas; nuevas selecciones requieren actividad. Una referencia de interés retirada no puede volver a agregarse si está inactiva.

La política de activación es aditiva y solo existe en el staging ficticio. La antigüedad de un perfil se verifica con metadatos de creación de Firestore, no con fechas manipulables del documento. No es necesaria una migración masiva para conservar los formatos históricos.

## Archivos de esta etapa

- Backend: `tool/backend/{academic-policy,access-error,catalogs}.mjs`; ajustes en `verification.mjs`, `http-handler.mjs` y guardas locales exactas en `profile-media.mjs`/`private-object.mjs`.
- Reglas: `firestore.rules`. Sin cambios en `storage.rules`.
- Flutter: nuevo `lib/features/academics/{registration_fields,catalog_admin_screen}.dart`; ajustes de registro en auth, modelos/servicios/pantallas de perfil, preferencias, descubrimiento y matches; cliente/pantallas de verificación y administración. Compatibilidad de la entrada de registro existente.
- Staging: `lib/main_ligo_staging.dart`, `staging/*`, `tool/ligo/{staging,server,seed,prepare-web}.mjs`, `staging-bootstrap.js`.
- Pruebas: `test/ligo_academic_test.dart`, `tool/ligo/academic.test.mjs`; parametrización local de `tool/{rules,phase3,phase5}.test.mjs` conservando sus valores originales por defecto.
- Documentación: este archivo, `LIGO_ARQUITECTURA.md`, `staging/README.md`.

Los otros cambios preexistentes no deben atribuirse a esta etapa. Se preservaron mediante snapshot cifrado local en `build/ligo-baselines/2026-11-01T22-21-31-353Z/source.dpapi`, verificado por hash y protegido con DPAPI. No versionar este respaldo, build, dependencias, FFmpeg ni datos de emuladores.

## Pruebas ejecutadas

- `flutter analyze`: sin incidencias (`build/ligo-analyze-clean.log`).
- `flutter test`: 303 aprobadas, incluidas 13 nuevas (`build/ligo-flutter-final.log`).
- Firebase/backend: 209 pruebas existentes aprobadas en regresión; 16 nuevas aprobadas en su ejecución final (`build/ligo-staging-academic-final.log`). Total de casos distintos aprobados: 225. Una ejecución intermedia completa tuvo tres fallos de fixture por faltar la política de activación; se corrigió la preparación y se reejecutaron los 16 casos afectados, sin reducir aserciones ni permisos.
- Compilación Web release de staging: correcta. SDK Firebase y fuentes servidos localmente, CSP sin conexiones externas.
- Navegador real de staging: acceso superadmin, creación de universidad ficticia y desactivación con confirmación; resultado «Inactivo · referencias conservadas». No se atribuyen pruebas manuales de Android ni de producción a esta etapa.
- Casos de integración nuevos: solicitud/carnet ficticio, aprobación por otro administrador, preferencias recíprocas, like/match, texto/readAt, fotografía/audio, rechazo de terceros y revocación por suspensión. Comparación de contenido y updateTime de fixtures históricos tras CRUD.
- Preservación: hashes de los 88 archivos del proyecto original coinciden con su respaldo; main sigue en `b1f793e`; demo local permanece limpio en `feature/integracion-tinder`, `351a489`. No se accedió al demo online ni a producción.

Los mensajes PERMISSION_DENIED de ataques esperados y una advertencia MaxListeners del driver aparecen en logs; no equivalen a casos aprobados que hayan fallado. No se ha cambiado el límite de listeners para ocultarla.

## Cómo probar

Staging: http://127.0.0.1:7465/. Solo accesible en esta PC. Cuentas ficticias `ligo_root@ligo.test`, `ligo_admin@ligo.test`, `ligo_student@ligo.test`; contraseña común `Ligo-staging-2026!`. Panel actual → «Administrar catálogos». Instrucciones de reproducción, puertos y precauciones en `staging/README.md`.

## Límites y siguiente paso

La funcionalidad está preparada y probada localmente. No está activada en producción ni distribuida en una APK. Antes de una activación futura se necesitará autorizar y coordinar backend/reglas/frontend y registrar el instante de corte de la política, sin reescribir usuarios anteriores. No se han eliminado las referencias históricas a Univalle ni cambiado identidad visual. La revisión humana debe confirmar el flujo de registro y edición en el staging antes de continuar con la identidad LIGO.
