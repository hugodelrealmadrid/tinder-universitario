# Pruebas online: comandos preparados, NO ejecutados

Solo para un proyecto Firebase NUEVO de pruebas. No usar el proyecto heredado `tinder-universitario`, ni importar el demo. Ejecutar bloque por bloque tras autorización; si un comando falla, detenerse. Los comandos crean recursos con posible costo.

## Lo necesario del propietario

1. Crear/elegir un proyecto Firebase exclusivo de pruebas y dar su ID. Activar Blaze personalmente solo cuando se autorice el despliegue; no entregar datos de tarjeta ni contraseñas.
2. En ese proyecto habilitar Auth correo/contraseña, crear Firestore Standard `(default)` y el bucket Firebase en `southamerica-west1` (Santiago). Confirmar ubicación ANTES de crearlos. Registrar app Web y Android development (`com.example.tinder_universitario.development`); entregar configuración pública y nombre EXACTO del bucket. Usar dominio gratuito `ID.web.app` para empezar, sin comprar dominio.
3. Instalar o habilitar Google Cloud CLI (`gcloud` no está disponible en el PATH de esta sesión). Iniciar sesión personalmente con `gcloud auth login` y `firebase login`, autorizando solo operaciones en el proyecto de pruebas. No generar claves JSON. Cloud Build necesitará una identidad constructora con acceso al bucket de staging, registro de logs y escritura en el repositorio Artifact Registry; comprobar permisos de esa identidad al habilitarlo, sin conceder Owner/Editor. No se ha inspeccionado ninguna cuenta cloud.
4. Aprobar presupuesto de prueba (propuesta US$5/mes), región y limpieza cada 15 min. Elegir la cuenta del primer superadmin; su bootstrap seguro y la inicialización del catálogo en el proyecto nuevo siguen pendientes antes de habilitar citas. No reutilizar bootstrap/seed demo ni el CLI histórico de catálogos que fija otro proyecto.

## 1. Variables y creación de recursos

PowerShell, desde la raíz del proyecto integrado. Reemplazar solo ID y bucket; todas las operaciones fijan proyecto explícito. No cambiar el proyecto global de gcloud/Firebase.

```powershell
$testProject = 'REEMPLAZAR_ID_PRUEBAS'
$testBucket = 'REEMPLAZAR_BUCKET_EXACTO'
$testRegion = 'southamerica-west1'
if ($testProject -notmatch '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' -or $testProject -eq 'tinder-universitario' -or $testProject.StartsWith('demo-')) { throw 'Proyecto de pruebas obligatorio' }
$webOrigin = "https://${testProject}.web.app"
$apiIdentity = "tinder-api@${testProject}.iam.gserviceaccount.com"
$cleanupIdentity = "tinder-cleanup@${testProject}.iam.gserviceaccount.com"
$schedulerIdentity = "tinder-scheduler@${testProject}.iam.gserviceaccount.com"
$image = "${testRegion}-docker.pkg.dev/${testProject}/tinder/backend:online-v1"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com cloudscheduler.googleapis.com firestore.googleapis.com identitytoolkit.googleapis.com storage.googleapis.com --project=$testProject
gcloud artifacts repositories create tinder --repository-format=docker --location=$testRegion --project=$testProject
gcloud iam service-accounts create tinder-api --project=$testProject
gcloud iam service-accounts create tinder-cleanup --project=$testProject
gcloud iam service-accounts create tinder-scheduler --project=$testProject
foreach ($identity in @($apiIdentity, $cleanupIdentity)) {
  gcloud projects add-iam-policy-binding $testProject --member="serviceAccount:$identity" --role=roles/datastore.user
  gcloud storage buckets add-iam-policy-binding "gs://$testBucket" --member="serviceAccount:$identity" --role=roles/storage.objectUser --project=$testProject
}
gcloud projects add-iam-policy-binding $testProject --member="serviceAccount:$apiIdentity" --role=roles/firebaseauth.viewer
```

Bucket sin acceso público IAM y con prevención de acceso público, comprobarlo en la consola del proyecto nuevo. Nunca añadir `allUsers` al bucket. Las reglas de Storage deniegan acceso SDK, el backend sirve bytes autenticados.

## 2. Compilar y validar Linux sin Docker local

```powershell
gcloud builds submit . --config=deploy/cloudbuild.json --ignore-file=deploy/cloudbuild.ignore --substitutions="_IMAGE=$image" --region=$testRegion --project=$testProject
```

Cloud Build compila deploy/Dockerfile y ejecuta la imagen SIN red ni credenciales: valida Sharp/PNG y FFmpeg/FFprobe/WAV. Solo publica la imagen si pasa. El contexto enviado excluye demo, exportaciones, configuraciones locales, frontend y secretos. Este paso sube código y genera cargos: requiere autorización, no se ha ejecutado. Si Docker se habilita localmente, primero puede ejecutarse `docker build -f deploy/Dockerfile -t tinder-api .`; tampoco se ha compilado todavía.

## 3. Reglas y API privada autenticada

Primero completar configuración Firebase y habilitar Auth/Firestore/Storage según el punto inicial.

```powershell
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=$testProject --config=firebase.development.json --only=firestore:rules,storage
$runtimeEnv = "APP_ENV=development,GOOGLE_CLOUD_PROJECT=$testProject,TINDER_PROJECT_ID=$testProject,TINDER_STORAGE_BUCKET=$testBucket,TINDER_WEB_ORIGINS=$webOrigin"
gcloud run deploy tinder-api --image=$image --region=$testRegion --project=$testProject --service-account=$apiIdentity --set-env-vars=$runtimeEnv --port=8080 --cpu=1 --memory=1Gi --concurrency=8 --min=0 --max=1 --max-instances=1 --timeout=60s --cpu-throttling --allow-unauthenticated
$apiUrl = gcloud run services describe tinder-api --region=$testRegion --project=$testProject --format='value(status.url)'
```

Cloud Run admite HTTP público porque TODAS las operaciones de datos requieren token Firebase y permisos en el backend. No confundir con bucket público. Sin token debe responder 401. No se suministran archivos de credenciales. Antes de desplegar otra imagen, reemplazar el tag por digest de la imagen validada para fijar exactamente el artefacto probado.

## 4. Limpieza privada programada

```powershell
gcloud run jobs deploy tinder-cleanup --image=$image --region=$testRegion --project=$testProject --service-account=$cleanupIdentity --set-env-vars=$runtimeEnv --command=node --args=backend/hosted-cleanup.mjs --cpu=1 --memory=512Mi --tasks=1 --parallelism=1 --task-timeout=300s --max-retries=1
gcloud run jobs add-iam-policy-binding tinder-cleanup --region=$testRegion --project=$testProject --member="serviceAccount:$schedulerIdentity" --role=roles/run.invoker
gcloud scheduler jobs create http tinder-cleanup-quarter-hour --location=$testRegion --project=$testProject --schedule='*/15 * * * *' --time-zone=America/La_Paz --uri="https://run.googleapis.com/v2/projects/$testProject/locations/$testRegion/jobs/tinder-cleanup:run" --http-method=POST --oauth-service-account-email=$schedulerIdentity --attempt-deadline=30s
gcloud run jobs execute tinder-cleanup --region=$testRegion --project=$testProject --wait
```

Scheduler OAuth invoca la API del Job; no hay endpoint de limpieza público. Validar eliminación/reintentos con documentos ficticios y monitorizar colas pendientes. El objetivo de retención es 15 min más reintentos, no una garantía de borrado exacto. Jobs con mínimo facturable de un minuto por ejecución: no usar frecuencia innecesaria.

## 5. Web y Android

Copiar deploy/development.example.json a deploy/development.local.json (ignorado), completar campos públicos y VERIFICATION_BACKEND_URL con `$apiUrl` terminado en `/`. Autorizar `ID.web.app` en Firebase Auth. Guardar google-services.json development en android/app/src/development, no sustituir archivos del demo.

```powershell
flutter build web --target lib/main.dart --dart-define-from-file=deploy/development.local.json --output=build/hosted/development
node tool/node_modules/firebase-tools/lib/bin/firebase.js deploy --project=$testProject --config=firebase.development.json --only=hosting
flutter build apk --debug --flavor development --target lib/main.dart --dart-define-from-file=deploy/development.local.json
```

URL prevista: https://ID_PRUEBAS.web.app . APK: build/app/outputs/flutter-apk/app-development-debug.apk, instalado como aplicación separada. Necesita Internet normal, no adb reverse. Esto no constituye firma de distribución ni despliegue productivo.

## Límites económicos y bloqueos

Propuesta: Santiago para mantener backend/Firestore/bucket cercanos a Bolivia; no se ha medido latencia. Cloud Run request-based, 0 instancias mínimas, máximo 1 a nivel servicio y revisión, concurrencia 8; Job 1 tarea cada 15 min. Presupuesto US$5 con alertas 50/80/100%, revisión diaria de consumo y acceso limitado a evaluadores. Alertas NO son un techo duro: máximo de instancias tampoco limita Storage/Firestore, red, builds ni picos transitorios. Antes de abrir al público faltan controles de abuso/App Check y validación del límite de gasto disponible. Usar datos/carnets ficticios, sin importar cuentas del demo.

Bloqueos actuales: motor Docker apagado; proyecto/billing/config pública/autorización cloud faltantes; imagen Linux e IAM no probados. Además faltan inicializador seguro de catálogos y bootstrap del primer superadmin para el proyecto nuevo: desplegar las pantallas por sí solo no habilita un flujo de citas usable. Prepararlos y probarlos antes de la primera aprobación, sin editar Firestore manualmente ni simular roles en Flutter.

Referencias: [regiones](https://cloud.google.com/run/docs/locations), [límites de escalado](https://cloud.google.com/run/docs/configuring/max-instances), [Cloud Build](https://cloud.google.com/sdk/gcloud/reference/builds/submit), [precios](https://cloud.google.com/run/pricing).
