# LIGO — preparación final de producción

2 de noviembre de 2026. Rama `codex/ligo`, base `b1f793e4`. **Compilado y validado localmente; no publicado.** Sin commits, push, migraciones, asignaciones de roles ni escrituras remotas. Los 88 archivos originales conservan sus hashes y la copia de pruebas original continúa limpia.

## Resultado funcional

Identidad LIGO, navegación responsive, swipe, perfiles/vista previa, fotos privadas, filtros de edad/universidad/carrera, likes/matches, texto/fotos/audio/checks, bloqueos, suspensiones, verificación y paneles por rol implementados. CRUD de universidades reservado a superadmin; carreras/intereses a admin/superadmin; autorización del servidor conservada. Compatibilidad histórica probada sin inferir afiliaciones.

Estos recorridos se comprobaron con pruebas automatizadas y emuladores, no enviando mensajes ni modificando estudiantes reales. La nueva APK de producción no se instaló en un teléfono en esta tarea. Las notificaciones push **no están implementadas**; no se añadieron como funcionalidad nueva.

## Pruebas finales

| Verificación | Resultado |
|---|---|
| Flutter analyze | Sin incidencias |
| Flutter test | 311 aprobadas |
| Reglas/backend, roles, históricos y flujo multimedia | 245 aprobadas en `demo-ligo-validation`, puertos separados |
| Backend alojado y sellado GCS | 9 aprobadas; GCS con mocks, sin escrituras remotas |
| Plan de revocación y activación aditiva | 7 aprobadas con mocks |
| Imagen Linux amd64 / Node 22 | Construcción y smoke test sin red aprobados: PNG/WAV, MIME falso, 401, CORS y configuración |
| Web release y APK production | Compilaciones correctas |
| Escáner de artefactos | 56 archivos Web y 745 entradas APK, sin valores privados conocidos del respaldo ni archivos privados |

Total backend/reglas/operaciones: **261 casos, 0 fallos finales**. La primera ejecución aislada tuvo 48 fallos de configuración de guardas/puertos y un mock remoto dentro del entorno emulado; se corrigieron el aislamiento exacto y la separación de pruebas, sin reducir aserciones ni permisos de producción. Logs en `build/ligo-production-*.log`.

## Datos e infraestructura conservados

Respaldo completo nuevo, cifrado DPAPI y verificado: `C:\Users\HP\.codex\worktrees\ligo\tinder_universitario_pruebas\build\online-backups\2026-11-02T16-36-36-449Z\`. Contiene **14 cuentas, 14 perfiles, 6 matches, 23 mensajes y 27 objetos**, además de configuración Auth, reglas e índices. No sobrescribe respaldos anteriores. Sin referencias rotas a fotos o medios. Ninguno de los 27 objetos permite HEAD GCS anónimo (27 respuestas 403); tampoco se encontraron permisos públicos de bucket ni de proyecto. Esto no elimina el riesgo de los tres enlaces con token. Los 14 perfiles siguen sin universityId; las 28 carreras y los 5 intereses originales no se modificaron. Superadmin y admin reales siguen aprobados y no suspendidos; roles intactos.

Proyecto `tinder-universitario`, bucket `tinder-universitario.firebasestorage.app`, backend `https://tinder-api-rcgmfjcicq-ue.a.run.app/`, región us-east1. Backend activo, máximo 1 instancia, concurrencia 8; acceso anónimo a operaciones privadas devuelve 401. Authentication por contraseña habilitado y dominios Hosting autorizados. Limpieza existente de **carnets únicamente**, cada 15 minutos, habilitada y con última ejecución exitosa; no se alteró.

## Artefactos

- Web release: `build/hosted/production/`.
- APK: `build/ligo-production-delivery/LIGO-1.2.0-3-production-private.apk`.
- applicationId conservado: `com.example.tinder_universitario`; etiqueta LIGO; versión 1.2.0 (3); minSdk 24, targetSdk 36; arm64-v8a/armeabi-v7a/x86_64; HTTP claro deshabilitado.
- APK **debug para App Distribution privado**, con firma coincidente con la APK anterior conservada. No es release para tiendas: falta proporcionar la clave de firma release. SHA-256: `0b438aa4c4aa1e5a3176a5dc2c043b69812e36c4b050bc3efc1821e8c7a99416`.
- Docker local `ligo-backend:local-final`, Linux amd64, digest local `sha256:676da7e415d8657a017c28df1bf4d84c904a7edce802b41241be18ac324e6768`.
- Web/APK apuntan al mismo Firebase real y backend indicado; sin banderas demo/staging ni claves privadas. Las claves públicas del cliente Firebase son necesarias y no conceden privilegios. Configuraciones locales fuera de Git. El logo institucional anterior se conservó como archivo, pero se retiró del paquete.

## Bloqueos y autorizaciones pendientes

1. **Tres tokens actuales permiten HEAD anónimo 200:** dos fotografías y un medio de chat. No se revocaron. Plan cifrado preparado en `build/ligo-cutover-plans/`; la operación verifica generaciones/metageneraciones, bytes y rechazo del enlace anterior, sin borrar archivos. Se reforzó el sellado de futuras subidas para comprobar ausencia real de tokens y detener conflictos ([precondiciones GCS](https://docs.cloud.google.com/storage/docs/request-preconditions)). Este refuerzo todavía no está desplegado. No se ha atribuido el origen de esos tokens sin evidencia.
2. Backend LIGO, reglas Firestore, Hosting y APK requieren **autorización de publicación por operación**. Storage Rules ya coinciden con producción; no necesitan republicarse. No cambiar IAM ni limpieza.
3. No existen universidades ni carreras vinculadas en producción y la política multiuniversidad está ausente. Publicar código compatible primero; el superadmin crea catálogos reales desde el dashboard. Luego autorizar la activación aditiva de política/auditoría con hora del servidor y respaldo fresco; nunca actualizar los perfiles anteriores.
4. Plantillas de correo conservan la identidad anterior: preparar revisión de textos/nombre público LIGO, sin tocar enlaces ni configuración de acceso, antes de autorizar su publicación.
5. NPM de producción informa 6 alertas **moderadas transitivas**, ninguna alta/crítica, relacionadas con glob/minimatch y sus dependientes. No se forzaron actualizaciones mayores incompatibles; detalle en `build/ligo-production-dependency-audit.json`.
6. Pendientes una firma release, notificaciones push y la prueba humana de la nueva versión online entre dos estudiantes legítimamente aprobados, incluida voz física. No se aprobaron usuarios para fabricar estas pruebas.

**Evaluación:** versión online privada preparada para el corte autorizado; no declarar todavía cerrado el lanzamiento público definitivo. Procedimiento: `deploy/CORTE_LIGO.md`. No usar los procedimientos antiguos de migración/bootstrap para este cambio.

Cambios de esta tarea: metadatos Web, retiro del activo institucional del paquete, guardas de pruebas aisladas, sellado GCS con verificación, plan de corte con autorización/precondiciones, escáner portable, pruebas y documentación. Inventario completo separado de los cambios previos: `build/ligo-production-files.json`.
