# Corte online de pruebas con administración provisional

Esta secuencia sustituye el bootstrap normal del CORTE_FINAL.md. No marcar reviewConfirmed=true ni simular revisión independiente.

1. Tras autorización: compilar imagen Linux y publicar una nueva revisión con el código provisional, conservando TINDER_PRE_CUTOVER=true, min=0/max=1/concurrencia=8. Recompilar Web y Android con sus configuraciones públicas separadas. Los binarios/imagen anteriores no incluyen esta excepción.
2. Ventana coordinada sin escrituras: nuevo respaldo cifrado verificado, nuevo plan de diez cuentas; publicar mantenimiento, migrar, publicar reglas estrictas y revocar tokens siguiendo CORTE_FINAL.md. Ante cualquier inconsistencia, detenerse conservando originales y respaldos. Ninguna de las diez cuentas se aprueba.
3. Una vez comprobadas reglas/referencias/revocación: activar operaciones del backend, publicar Web para acceso pendiente y preparar limpieza privada. Todos siguen pendientes; no hay citas habilitadas. El propietario inicia sesión y presenta su carnet exclusivamente en la pantalla privada de verificación. No enviarlo por chat/correo ni generar URL con token. La solicitud debe quedar pending/ready y sin reviewedBy.
4. SOLO tras autorización explícita del bootstrap excepcional: cambiar ownerAuthorization del archivo ignorado deploy/provisional-superadmin.local.json a initial_admin_online_test. Ejecutar una sola operación privilegiada de operador (no existe endpoint cliente para este bootstrap):

    node tool/online/run.mjs bootstrap-provisional $backupDir --apply-existing-project --provisional-exception-confirmed --confirmation-file=deploy/provisional-superadmin.local.json

El operador comprueba identidad Auth habilitada y email verificado, reglas estrictas, migración/revocación completas, Storage privado sin token y generación/tipo/tamaño, solicitud vigente del mismo UID y registro inicial vacío. Cinco escrituras en un commit atómico con precondiciones: rol superadmin provisional, estado universitario PENDIENTE, datingAllowed=false, registro administrativo, marcador de consumo y auditoría. La auditoría incluye UID, fecha, motivo owner_authorized_online_test_pending_independent_review y independentReview=false; no contiene carnet/correo. Se refiere a cinco documentos (cuenta, registro, perfil, marcador y auditoría).

5. Verificar administración, autoaprobación rechazada, gestión de roles rechazada y citas/chat/fotos de terceros inaccesibles al propietario pendiente. Solo después distribuir APK de pruebas y activar limpieza periódica privada; no ejecutar limpieza antes de la migración. El resto se verifica mediante el flujo habitual, sin aprobaciones masivas. Mantener acceso limitado a pruebas.

## Caducidad y privacidad

Máximo 72 horas, limitado además por el vencimiento del carnet/solicitud (actualmente 24 horas desde su creación). Caduca también si se suspende/rechaza la cuenta, se retira el carnet o cambia la solicitud. No se renueva por reintentos. La limpieza elimina documentos vencidos/resueltos con reintentos; no extender retención automáticamente. La regularización posterior requiere revisión independiente auténtica y un procedimiento privilegiado autorizado; el candidato nunca decide su propia solicitud. Si vence sin revisión, se conserva el rol histórico/registro para proteger al último superadmin pero las operaciones administrativas quedan denegadas.

## Fallos y autorizaciones

Antes de conceder privilegios, un fallo deja todas las cuentas pendientes. Tras el corte, ante errores activar nuevamente TINDER_PRE_CUTOVER=true y detener publicaciones/operaciones. Mantener reglas estrictas, respaldos, originales y diarios; no recrear tokens ni restaurar reglas débiles automáticamente. La restauración de datos requiere evaluación y autorización independiente.

Hace falta autorizar: nueva revisión backend y binarios, mantenimiento/migración/reglas/revocación, apertura Web para presentar carnet, bootstrap provisional de este UID después de la subida, limpieza programada y distribución del APK. Preparar código no autoriza ejecutar esos pasos.

Validación local completada: analyze limpio; 22 pruebas Flutter; 21 pruebas Node (7 provisionales, 8 migración, 6 backend alojable); 208 regresiones Firebase aprobadas y el nuevo caso provisional aprobado en ejecución dirigida tras corregir su fecha de fixture. Compilaciones Web release y Android productionDebug aprobadas. Artefactos inspeccionados sin datos/tokens del respaldo. No se construyó ni publicó una nueva imagen remota en esta etapa. Ningún bootstrap o corte ejecutado.

## Ejecución verificada de la ETAPA 2 — 25/10/2026

Bootstrap excepcional consumido para el UID autorizado. Acreditación pendiente, independentReview=false y datingAllowed=false. Vence el 25/10/2026 a las 23:47:06 (Bolivia), o antes si se invalida la solicitud. El reintento no renueva el permiso. Auditoría administrativa registrada; autoaprobación y gestión de roles siguen denegadas.

Limpieza: Cloud Run Job privado tinder-cleanup, us-east1, alcance exclusivo university_cards; identidad dedicada sin Auth, sin borrado Firestore y con borrado Storage condicionado al prefijo de carnets. Scheduler tinder-cleanup-quarter-hour cada 15 minutos, OAuth de identidad separada y run.invoker solo en el Job. Se comprobó la eliminación de un objeto ficticio y una ejecución adicional invocada por Scheduler; ambas terminaron correctamente. No se ejecuta reconciliación de fotografías ni chat. La propagación inicial de IAM requirió un reintento, sin cambios de permisos amplios.

Verificaciones: 209 pruebas Firebase/backend y 15 específicas aprobadas; imagen Linux construida y validada. Diez cuentas/perfiles, cuatro matches, doce mensajes, nueve preferencias y diecinueve objetos originales (incluido carnet) preservados. Web pública: inicio de sesión, panel y estado pendiente comprobados. APK online inspeccionada sin valores privados del respaldo y distribuida por App Distribution exclusivamente al destinatario autorizado (release 2kmak4i3f6u80); ejecución en el teléfono pendiente de prueba del propietario. No se publicó en tiendas ni se hizo push. Recibos y baselines cifrados/ignorados en build/cutover-stage2; no versionarlos.

Script reproducible de infraestructura: tool/online/stage2-cleanup.mjs; requiere --authorized-stage2 y una acción setup/run/status/schedule. No repetir bootstrap ni migraciones. Los respaldos previos y el demo permanecen intactos.


## Regularización permanente — 25/10/2026

La concesión provisional del titular fue regularizada mediante tool/online/regularize-provisional.mjs, sin repetir el bootstrap. El titular confirmó una revisión favorable realizada por su profesor de Proyecto de Sistemas con carnet físico y virtual, identidad, vigencia y sede Cochabamba. Se registró la fuente owner_report_of_external_review y la referencia profesional; la fecha histórica se conservó aproximada («la semana pasada»), sin atribuir autenticación Firebase al docente ni inventar una fecha exacta. Auditoría: administrativeAudit/provisional_superadmin_regularized. La cuenta quedó aprobada, sin provisionalAdminUntil, y conserva su rol superadmin. No se alteró la excepción histórica original.

Siete escrituras atómicas con precondiciones, respaldo nuevo cifrado verificado y 14 pruebas dirigidas aprobadas. Retención del carnet mediante la cola privada existente. No se modificaron cliente, backend desplegado ni reglas; no hizo falta publicar nuevos binarios. La candidata a admin sigue como user/pending y sin solicitud; no se concedió ese rol. Recibos privados en build/production-regularization; no versionarlos. El resto de cuentas y los dos demos permanecen intactos.
