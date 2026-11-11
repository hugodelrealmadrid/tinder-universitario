# LIGO: compatibilidad multiuniversidad implementada en staging

La ampliación aditiva está autorizada e implementada exclusivamente en `codex/ligo`. No se ha conectado con producción, publicado reglas, modificado cuentas históricas ni creado un proyecto remoto. Los cambios visuales LIGO y el nuevo dashboard quedan para la siguiente etapa.

## Contrato de compatibilidad

- `universities/{id}` incorpora nombre, país, ciudad, actividad y revisión. Solo superadmin puede escribir mediante el backend.
- Las carreras nuevas llevan `universityId`. Las carreras históricas conservan su ámbito y no pueden reasignarse durante una edición. Admin y superadmin gestionan carreras e intereses.
- `users.universityId` es opcional para históricos e inmutable una vez creado el perfil. Ninguna tarea infiere o rellena universidades. Las proyecciones y preferencias sin universidad mantienen su formato anterior.
- La política `platformSettings/academic` activa la selección obligatoria para nuevos registros. `legacyBefore` es el instante de activación: el backend usa la fecha de creación confiable del documento para reconocer perfiles anteriores, nunca una fecha enviada por el cliente. En producción no se ha creado esta política.
- El registro autenticado selecciona universidad activa y luego carrera activa vinculada. Las reglas verifican esa relación y rechazan formatos antiguos para perfiles nuevos cuando está activada la política.
- Desactivar universidad/carrera no suspende estudiantes ni revoca verificaciones. Se conservan selecciones guardadas; nuevas selecciones requieren actividad. Un interés inactivo puede conservarse o retirarse, pero no volver a agregarse.
- El filtro de universidad es opcional. Un perfil sin afiliación explícita no coincide con una universidad concreta; sin filtro continúa siendo elegible según las validaciones anteriores.
- Las solicitudes nuevas muestran su institución explícita. Las solicitudes y motivos históricos mantienen su formato; ninguna aprobación automática.

## Autorización

Catálogos se modifican exclusivamente mediante operaciones autenticadas del backend: validación de campos y duplicados normalizados, transacciones, revisión esperada, recibos idempotentes y auditoría. No hay eliminación física en el CRUD. Las reglas deniegan escrituras directas incluso a administradores. Pendientes y suspendidos no pueden administrar. Gestión de roles y universidades queda reservada a superadmin; se mantienen controles de autoaprobación y último superadmin.

## Validación y ejecución

Ver `staging/README.md` e `INFORME_LIGO_MULTIUNIVERSIDAD.md`. Los emuladores usan `demo-ligo-staging` únicamente como identificador local. No es un proyecto remoto ni reemplaza los demos existentes. La ejecución tiene puertos y TEMP/TMP propios y Web con conexiones externas bloqueadas por CSP.

Una activación futura en producción requiere autorización específica y una coordinación de backend, reglas y frontend. No ejecutar migraciones ni modificar perfiles anteriores para activar esta ampliación.
