# Corte LIGO — preparado, NO ejecutado

Usar exclusivamente `tinder-universitario`, región us-east1, rama `codex/ligo`. Cada publicación o cambio de datos requiere aprobación previa del responsable. No usar showcase, seeds, migraciones antiguas, bootstrap ni scripts de asignación de roles. No cambiar facturación, IAM, el Job de limpieza ni datos históricos.

## Antes del corte

1. Acordar una ventana de prueba sin ediciones concurrentes y actualizar el respaldo, conservando los anteriores:

```powershell
node tool/online/backup.mjs --read-only-backup
node tool/online/ligo-cutover.mjs plan <nuevo-directorio-backup>
```

Verificar el resultado y las cantidades actuales. Los planes anteriores son evidencia, no deben aplicarse a un respaldo distinto. Las operaciones de escritura del nuevo script rechazan respaldos de más de 15 minutos. Si tarda la publicación, volver a respaldar y planificar. No imprimir tokens, hashes de contraseña ni documentos.

## Operaciones independientes por autorizar

2. Publicar la imagen Linux local validada en el repositorio **existente** `us-east1-docker.pkg.dev/tinder-universitario/tinder/backend`, con tag `ligo-1.2.0-3`. Autenticación de operador existente; ninguna clave JSON. No es push a GitHub. Registrar su digest remoto y comprobar que corresponde a la imagen validada. Si se reconstruye una imagen, volver a ejecutar el smoke test Linux antes de promoverla.

3. Desplegar una revisión de `tinder-api`, inicialmente sin tráfico y con tag de preflight. Conservar cuenta de servicio, bucket, proyecto, orígenes, IAM y limpieza. Mínimo 0, máximo 1 tanto en servicio como en revisión, concurrencia 8, CPU 1, memoria 1 GiB, facturación por solicitud. La nueva revisión requiere `TINDER_PRE_CUTOVER=false`. Probar 401 sin token/token inválido y CORS restringido en su URL. No se conceden privilegios por permitir llegada HTTP a Cloud Run.

Comando de referencia para el operador autenticado (no ejecutado; usar la imagen fijada por digest):

```powershell
gcloud run deploy tinder-api --project=tinder-universitario --region=us-east1 --image=<digest-validado> --service-account=tinder-api@tinder-universitario.iam.gserviceaccount.com --cpu=1 --memory=1Gi --port=8080 --concurrency=8 --min=0 --max=1 --max-instances=1 --cpu-throttling --timeout=60s --update-env-vars=TINDER_PRE_CUTOVER=false --no-traffic --tag=ligo-preflight
```

No usar un deploy que vuelva a crear IAM ni habilite APIs. Mantener la revisión anterior registrada para revertir tráfico si falla la validación, sin restaurar datos.

4. Tras validar compatibilidad de la revisión con los formatos históricos y autorizar su promoción, llevar el backend al 100% antes de revocar enlaces: así las subidas nuevas usan el sellado reforzado. Publicar únicamente las reglas Firestore compatibles; Storage Rules no cambiaron:

```powershell
gcloud run services update-traffic tinder-api --project=tinder-universitario --region=us-east1 --to-revisions=<revision-validada>=100
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=tinder-universitario --config=firebase.hosted.json --only=firestore:rules
```

Comparar el ruleset publicado con el archivo validado y comprobar lecturas históricas. Las reglas de catálogos siguen denegando escrituras de clientes. No sustituirlas por reglas abiertas ni por las reglas de mantenimiento del corte inicial.

5. Con revisión/backend compatibles y respaldo/plan fresco, autorizar separadamente la revocación de los tokens identificados:

```powershell
node tool/online/ligo-cutover.mjs revoke <backup-fresco> <plan-cifrado> --authorized-production-write
```

Esta operación solo cambia metadatos de los objetos planificados y guarda un recibo local. No borra objetos ni escribe perfiles, mensajes o matches. Se detiene ante generaciones diferentes, conflicto de metadatos, checksum distinto o token que siga funcionando. No improvisar borrados ni restaurar tokens para resolver un error.

6. Repetir el inventario de tokens y comprobar que no hay nuevos enlaces activos; si aparecen, detener el siguiente paso y revisar un respaldo/plan fresco. Tras las comprobaciones, autorizar la publicación de Hosting:

```powershell
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=tinder-universitario --config=firebase.hosted.json --only=hosting
```

Comprobar https://tinder-universitario.web.app/ con las cuentas reales por sus propietarios. No crear usuarios ficticios ni emitir tokens de suplantación. Cotejar roles, verificación pendiente y suspensión con los controles actuales.

7. Autorizar la distribución privada de `build/ligo-production-delivery/LIGO-1.2.0-3-production-private.apk` en la aplicación Android existente, a los testers reales indicados por el propietario. Reutilizar sus invitaciones; no cambiar roles. Misma firma debug que la APK anterior conservada: sirve para prueba privada, no para tiendas. Notas: `deploy/LIGO_RELEASE_NOTES.txt`.

## Activación multiuniversidad, sin migración

8. El superadmin crea desde la interfaz al menos una universidad real y una carrera nueva vinculada, con país/ciudad correctos. Los registros históricos quedan intactos; no editar las 28 carreras antiguas para adjudicarles universidad ni copiar catálogos ficticios. Los administradores gestionan carreras/intereses, no universidades globales ni roles.

9. Con esos catálogos revisados, generar otro respaldo fresco y solicitar autorización específica para activar la política:

```powershell
node tool/online/ligo-cutover.mjs activate-academics <backup-fresco> <UID-superadmin-aprobado> --authorized-production-write
```

El script exige superadmin aprobado, cuenta verificada/habilitada, catálogo activo compatible y ausencia de política previa. Hace un commit aditivo de política/auditoría con precondición del rol y hora del servidor. No actualiza usuarios ni inferencias de universidad. Si la política ya existe, se detiene y no cambia su fecha de corte. Probar registro nuevo, selección de carrera y edición histórica por los propios participantes.

10. Revisar la marca pública/plantillas de correo en Firebase, conservando dominios, enlaces de acción y proveedor de acceso. Publicar esos textos solo con autorización. Prueba manual final: dos estudiantes legítimamente aprobados, fotos, filtros, likes/match, texto, imagen, voz física y checks; control negativo de pendientes/suspendidos mediante pruebas, sin cambiar estados reales para fingir resultados.

## Detención y recuperación

Ante fallo, detener la siguiente operación y conservar recibos y respaldos. Antes de activar multiuniversidad, se puede volver a tráfico/release anteriores mediante su procedimiento autorizado; nunca ejecutar una restauración masiva ni retirar las reglas aditivas tras crear perfiles nuevos. Después de activar, evaluar compatibilidad antes de cualquier rollback de backend. No borrar catálogos ni quitar universityId de registros para recuperar.

Quedan documentados: notificaciones push ausentes, clave release pendiente y seis alertas NPM moderadas transitivas; no hay alertas altas/críticas en el audit ejecutado. Ver `INFORME_LIGO_PRODUCCION.md`.
