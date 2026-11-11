> **LIGO (2/11/2026):** para la actualización actual usar [CORTE_LIGO.md](CORTE_LIGO.md). No repetir la migración ni el bootstrap del corte inicial descritos abajo; las cuentas y roles actuales deben conservarse.

# Despliegue preparado: tinder-universitario

NO ejecutado. Esperar autorización para APIs, IAM, recursos, mantenimiento, migración, revocación y publicación. No utilizar la guía de proyecto nuevo PRUEBAS_ONLINE.md para este proyecto existente. No activar otra vez facturación: ya está habilitada. Falta gcloud disponible en PATH y validar la imagen Linux (Docker apagado; Cloud Build preparado como alternativa).

## Respaldo y plan locales

Respaldo cifrado con DPAPI CurrentUser, permisos NTFS de usuario/SYSTEM; nunca en Git ni en Cloud Build. El directorio exacto y hashes constan en build/online-backups/*/verified.json. backup.dpapi contiene 9 cuentas con hashes/parámetros Auth, 99 documentos Firestore y 9 objetos completos con tokens/metadatos. storage-security.dpapi conserva IAM/ACL adicionales. Los originales quedan intactos. Para recuperar: verifiedBackup(dir) comprueba hashes y loadEncrypted(file) descifra solo bajo el MISMO perfil Windows; conservar también ese perfil/DPAPI. No se ensayó restauración remota, ni se importaron datos reales en emuladores. La copia no es portable por sí sola a otro Windows. Firestore se capturó a readTime fijo y se contrastaron dos lecturas estables; no se afirma atomicidad entre servicios.

Plan cifrado migration-plan-v1.dpapi: conserva 9 usuarios, 9 perfiles, 4 matches, 12 mensajes y 9 preferencias. Copia las 9 fotografías a rutas deterministas privadas, conserva originales, crea manifiestos/pruebas con SHA-256/generación/tipo/tamaño y actualiza únicamente referencias y estado de acceso. Todos user/pending; isActive voluntario se conserva y datingAllowed=false. Catálogos existentes se conservan. Repetición tras commit no revoca aprobaciones posteriores. Precondiciones de updateTime/exists evitan sobrescrituras concurrentes; si cambió inventario, detener y renovar respaldo. Fase Storage y Firestore no es atómica: copia condicional primero, referencias/pruebas en un commit atómico después, diario de progreso para reanudar. No hay borrados automáticos.

```powershell
$backupDir = 'build/online-backups/2026-10-25T00-00-01-675Z'
node tool/online/run.mjs plan $backupDir
```

## Secuencia futura, solo tras autorización

1. Instalar/habilitar gcloud y autenticar personalmente. Habilitar APIs run/cloudbuild/artifactregistry/cloudscheduler. Crear repositorio Docker us-east1 y las identidades API, cleanup y scheduler como en la guía de comandos, usando SOLO tinder-universitario. API: datastore.user, firebaseauth.viewer y storage.objectUser únicamente en el bucket existente; cleanup sin acceso Auth, scheduler run.invoker únicamente sobre el Job. Ninguna clave JSON ni bucket público. Verificar identidad constructora de Cloud Build.
2. Compilar/validar imagen Linux antes de entrar en mantenimiento; desplegar API y Job (no hacen bootstrap ni migración al arrancar):

```powershell
$project = 'tinder-universitario'
$region = 'us-east1'
$image = 'us-east1-docker.pkg.dev/tinder-universitario/tinder/backend:five-phases-v1'
gcloud builds submit . --config=deploy/cloudbuild.json --ignore-file=deploy/cloudbuild.ignore --substitutions="_IMAGE=$image" --region=$region --project=$project
gcloud run deploy tinder-api --image=$image --region=$region --project=$project --service-account=tinder-api@tinder-universitario.iam.gserviceaccount.com --env-vars-file=deploy/existing.backend.example.yaml --cpu=1 --memory=1Gi --port=8080 --concurrency=8 --min=0 --max=1 --max-instances=1 --cpu-throttling --timeout=60s --allow-unauthenticated
gcloud run jobs deploy tinder-cleanup --image=$image --region=$region --project=$project --service-account=tinder-cleanup@tinder-universitario.iam.gserviceaccount.com --env-vars-file=deploy/existing.backend.example.yaml --command=node --args=backend/hosted-cleanup.mjs --cpu=1 --memory=512Mi --tasks=1 --parallelism=1 --task-timeout=300s --max-retries=1
```

Cloud Run admite llegada HTTP pública para validar ID tokens Firebase; ninguna operación privada admite acceso SIN autenticación. Todas validan token revocado y permisos actuales. Probar 401 sin token. El Job no sirve HTTP y Scheduler usa OAuth/run.invoker. No ejecutar el Job ni activar Scheduler hasta terminar migración/revocación/bootstrap: sus cursores cambiarían el snapshot. Antes del corte solo probar 401 sin token, no sesiones de usuarios. Registrar programación cada 15 min, alertas y presupuesto antes de abrir: min=0/max=1 no es techo de gasto de Storage/Firestore/red/Cloud Build. Fijar digest de imagen validada antes del corte. No mover nam5 ni US-EAST1.

Compilar previamente las aplicaciones con los comandos del punto 5 y la URL HTTPS del backend, antes de comenzar el corte. Si Linux, IAM o alguna compilación falla, no entrar en mantenimiento.

3. Coordinar ventana sin escrituras de clientes ni otros operadores. Actualizar respaldo si cambió cualquier dato. Publicar mantenimiento (bloquea temporalmente clientes), ejecutar migración, publicar reglas estrictas y verificar antes de revocar:

```powershell
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=tinder-universitario --config=firebase.maintenance.json --only=firestore:rules,storage
node tool/online/run.mjs migrate $backupDir --apply-existing-project --maintenance-confirmed
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=tinder-universitario --config=firebase.hosted.json --only=firestore:rules,storage
node tool/online/run.mjs revoke $backupDir --apply-existing-project --maintenance-confirmed
```

El operador verifica las reglas publicadas antes de escribir; migración exige mantenimiento real, revocación exige reglas finales. Comprueba copias privadas y referencias antes de revocar TODOS los tokens anteriores con generación/metageneración; después verifica HEAD anónimo de cada token. Si falla, conservar diario/respaldo y resolver, sin restaurar automáticamente reglas débiles, ni repetir borrados. No ejecutar bootstrap si la migración/revocación no terminó correctamente.

4. El propietario debe confirmar UID/correo exactos de una cuenta Auth EXISTENTE, habilitada, correo verificado y pertenencia universitaria revisada explícitamente. Ninguna cuenta está elegida. Copiar superadmin.example.json a superadmin.local.json (ignorado), completar y marcar reviewConfirmed=true solo tras esa revisión. No admite cuentas demo ni reemplaza un bootstrap consumido:

```powershell
node tool/online/run.mjs bootstrap $backupDir --apply-existing-project --confirmation-file=deploy/superadmin.local.json
```

La concesión explícita al primer superadmin es la ÚNICA excepción aprobada por el propietario al estado pendiente inicial; se registra auditoría. Después las otras cuentas pasan por solicitudes/revisión normal, sin autoaprobación.

5. Completar VERIFICATION_BACKEND_URL en deploy/existing-project.local.json con URL HTTPS real terminada en /. Construir ambas apps ANTES de publicar Hosting; Android puede distribuirse luego del corte:

```powershell
flutter build web --target=lib/main.dart --dart-define-from-file=deploy/existing-project.local.json --output=build/hosted/production
flutter build apk --debug --flavor=production --target=lib/main.dart --dart-define-from-file=deploy/existing-project.android.local.json
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=tinder-universitario --config=firebase.hosted.json --only=hosting
```

Mantener ventana hasta pruebas de login pendiente, carnet privado, decisión admin, acceso aprobado, suspensión, mensajes anteriores, fotos y voz. No importar demo. Si algo falla antes del corte, no avanzar: respaldo intacto, originales no borrados y estado de migración conservado.

Validación local: 11 pruebas nuevas (respaldo, cifrado, conservación, commit simulado, idempotencia, ataques y revocación) y 4 del backend alojable aprobadas. Nueve fotos reales decodificadas localmente sin mostrarlas. No se ejecutó migración remota, bootstrap, revocación, mantenimiento, APIs ni despliegues. Docker Linux/cloud/IAM siguen pendientes de validación autorizada; no se declara éxito online.
