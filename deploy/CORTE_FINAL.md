# Corte final: comandos preparados, NO ejecutados

Web release: build/hosted/production. Android online de pruebas: build/app/outputs/flutter-apk/app-production-debug.apk, firmado con clave debug; no es una versión para Play Store. Las dos usan tinder-universitario y https://tinder-api-rcgmfjcicq-ue.a.run.app/.

## Revisión humana mínima del primer superadministrador

Un docente o responsable autorizado distinto del candidato debe comprobar en persona o videollamada su identidad y un carnet/constancia oficial vigente que acredite pertenencia a Univalle sede Cochabamba. Si el carnet no indica sede o vigencia, contrastar una constancia institucional adicional. Gmail verificado por sí solo no acredita pertenencia. No enviar documentos por este chat ni publicarlos. Registrar únicamente fecha, rol/referencia del revisor y resultado; no conservar copias innecesarias. Tras confirmar esa revisión y la autorización explícita del propietario, habilitar reviewConfirmed en deploy/superadmin.local.json para el UID confirmado del candidato. Para las comprobaciones de reglas del corte, definí el mismo valor localmente en la variable LIGO_STAGE1_CANDIDATE_UID. Ese archivo está ignorado. No se ha habilitado.

## Secuencia tras autorización independiente del corte

1. Acordar ventana sin escrituras/registro. Crear un respaldo NUEVO: `node tool/online/backup.mjs --read-only-backup`. Verificar resultado y usar su directorio, conservando los anteriores. Preparar el plan cifrado con `node tool/online/run.mjs plan $backupDir`. Si aparece cualquier cambio concurrente o error, detenerse. Nunca usar el respaldo histórico de nueve cuentas.
2. Revisar hashes de artefactos (build/online-readiness/artifact-verification.json) y confirmar que código/configuración no cambiaron desde las compilaciones. Mantener TINDER_PRE_CUTOVER=true.
3. Ejecutar, en orden y deteniéndose en el primer fallo:

```powershell
# Desde la raíz del proyecto integrado; completar con el respaldo NUEVO verificado.
$backupDir = 'build/online-backups/REEMPLAZAR_RESPALDO_NUEVO'
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=tinder-universitario --config=firebase.maintenance.json --only=firestore:rules,storage
node tool/online/run.mjs migrate $backupDir --apply-existing-project --maintenance-confirmed
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=tinder-universitario --config=firebase.hosted.json --only=firestore:rules,storage
node tool/online/run.mjs revoke $backupDir --apply-existing-project --maintenance-confirmed
# SOLO después de revisión universitaria, confirmación de UID y autorización del bootstrap.
node tool/online/run.mjs bootstrap $backupDir --apply-existing-project --confirmation-file=deploy/superadmin.local.json
```

4. Con la migración/revocación/bootstrap comprobados, autorizar y activar operaciones del backend:

```powershell
# Requiere sesión gcloud personal; no claves JSON. No ejecutado.
gcloud run services update tinder-api --project=tinder-universitario --region=us-east1 --update-env-vars=TINDER_PRE_CUTOVER=false
```

Conservar límites 0/1 y concurrencia 8. Crear/activar limpieza privada con identidad propia y Scheduler cada 15 minutos según deploy/EXISTENTE.md; no ejecutar limpieza antes de terminar la migración. Probar rechazo sin token y flujos autorizados de pendiente/aprobado/admin/suspensión, carnets y medios con datos ficticios. No aprobar automáticamente otras cuentas.

5. Publicar Web exclusivamente tras las comprobaciones:

```powershell
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=tinder-universitario --config=firebase.hosted.json --only=hosting
```

Hosting previsto: https://tinder-universitario.web.app . Distribuir el APK debug únicamente para pruebas privadas tras el corte. Para Android release hace falta confirmar identificador definitivo y proporcionar configuración de firma fuera del repositorio; no incluir contraseñas ni keystore en Git/APK. Verificar dispositivos sin adb reverse ni dependencia de la PC.

Si falla un paso: mantener mantenimiento/bloqueo, conservar respaldos, originales y diario; no restaurar automáticamente reglas débiles ni borrar datos. El máximo de una instancia no limita todos los cargos de Firebase/Storage/red.

Recompilación local: Web usa deploy/existing-project.local.json; Android usa deploy/existing-project.android.local.json con SU clave pública Firebase nativa. No intercambiar estos archivos. Comandos:

```powershell
flutter build web --target=lib/main.dart --dart-define-from-file=deploy/existing-project.local.json --output=build/hosted/production --no-web-resources-cdn --no-wasm-dry-run --no-pub
flutter build apk --debug --flavor=production --target=lib/main.dart --dart-define-from-file=deploy/existing-project.android.local.json --no-pub
```
