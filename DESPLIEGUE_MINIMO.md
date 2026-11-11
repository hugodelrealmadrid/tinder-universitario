# Preparación de entorno alojado

Cambios locales sobre main 351a489. No se consultó ni modificó Firebase real; el demo sigue en la copia de pruebas. Preparación consolidada en un commit local; no se han desplegado servicios.

## Infraestructura mínima propuesta

Un proyecto Firebase separado para desarrollo alojado y otro para producción: Authentication (correo/contraseña y verificación de correo), Firestore Standard `(default)`, Storage privado y Hosting para Flutter Web. Un servicio Cloud Run Linux para la API y un Cloud Run Job para limpieza, programado por Cloud Scheduler cada 15 minutos inicialmente (confirmar este objetivo de retención; los reintentos pueden demorarlo). Los Jobs facturan un mínimo de un minuto por ejecución, por lo que no se propone ejecutarlos continuamente. APK Android utiliza la misma API HTTPS; no necesita adb reverse. Firebase Storage requiere Blaze/facturación; no se promete costo cero. Elegir región cercana a Firestore/Storage, min-instances=0, max-instances=1 inicialmente, concurrencia=8, memoria inicial 1 GiB, alertas de presupuesto y seguimiento del consumo. Las alertas no son un límite duro de gasto.

La API puede admitir invocación pública de Cloud Run porque valida ID tokens Firebase revocados en cada solicitud; esto NO significa acceso público a datos. CORS admite solo los orígenes Web configurados; Android no envía Origin. Todas las autorizaciones permanecen en VerificationBackend y reglas. Las fotos ajenas consultan Firestore REST con el token del lector para aplicar las mismas reglas. Storage SDK permanece completamente denegado. No habilitar IAM público en el bucket ni entregar URLs de descarga con token.

Identidad de servicio sin archivos de claves: permisos de datos Firestore (`roles/datastore.user`), lectura de usuarios Auth (`roles/firebaseauth.viewer`) y objetos SOLO del bucket elegido (`roles/storage.objectUser`). Revisar permisos efectivos en desarrollo antes de producción; nunca Owner/Editor. Job con identidad dedicada y permisos de datos/limpieza necesarios. Scheduler usa OAuth para invocar la API de ejecución del Job, con `roles/run.invoker` sobre ese Job. No se añade endpoint HTTP público de limpieza.

## Configuración preparada

- Demo: conservar sus entradas main_demo y main_demo_android, launchers/configs locales existentes; no usar archivos hosted. No se cambió la copia de pruebas.
- Desarrollo alojado: copiar deploy/development.example.json a development.local.json y completar con un proyecto distinto al productivo. APP_ENV=development. API también APP_ENV=development y su propio ID/bucket/dominio.
- Producción: copiar deploy/production.example.json a production.local.json y completar. Backend: deploy/backend.env.example como plantilla. El backend exige proyecto doblemente explícito y arranque Cloud Run; rechaza hosts de emulador y credenciales JSON. Puerto suministrado por Cloud Run.
- La entrada lib/main.dart ahora falla antes de usar Firebase si no existe configuración explícita; ya no utiliza silenciosamente firebase_options.dart. Las entradas demo siguen separadas.
- Android: registrar applicationId antes de distribuir (actual com.example.tinder_universitario); descargar configuración PÚBLICA correcta a android/app/src/production/google-services.json, ignorada en Git. Producción exige flavor production, archivo nativo propio y HTTPS sin cleartext. Desarrollo Android usa flavor development (applicationId con sufijo .development) y android/app/src/development/google-services.json propio, también ignorado en Git. No sustituir el archivo nativo heredado de standard. Verificar coincidencia de appId/proyecto. Definir SHA-1/SHA-256 y dominios autorizados de Auth según proveedor elegido.
- Firma release mediante variables TINDER_KEYSTORE_FILE, TINDER_KEYSTORE_PASSWORD, TINDER_KEY_ALIAS, TINDER_KEY_PASSWORD; no enviarlas por chat ni guardarlas en Git. Sin ellas release falla; demo debug conserva su firma habitual.

Compilaciones locales futuras, con configuraciones completas (no ejecutadas contra proyectos reales):

```powershell
flutter build web --target lib/main.dart --dart-define-from-file=deploy/production.local.json --output=build/hosted/production
flutter build apk --release --flavor production --target lib/main.dart --dart-define-from-file=deploy/production.local.json
docker build -f deploy/Dockerfile -t tinder-api .
```

Contenedor solo incluye dependencias runtime y backend; no incluye Flutter, exportaciones, demo ni credenciales. Comando del Job: node backend/hosted-cleanup.mjs, misma imagen, una tarea y paralelismo=1. Los cursores de reconciliación se conservan en Firestore para progresar entre ejecuciones. Configs Firebase de publicación separadas: firebase.hosted.json y firebase.development.json; siempre indicar explícitamente el proyecto al publicar. Hosting sirve build/hosted/production o development, nunca build/web del demo.

## Datos y migraciones: ejecutar solo tras autorización y respaldo

Si se elige un proyecto NUEVO, no importar Auth, Firestore ni Storage del demo: cargar solo catálogos públicos de carreras/intereses, crear nuevas cuentas y designar explícitamente al primer superadmin mediante un procedimiento de operador revisado. El bootstrap actual es demo-only y NO debe adaptarse quitándole su protección. Falta preparar/aprobar ese bootstrap real con UID verificado, revisión humana y auditoría; no existe aprobación automática de usuarios.

Si ya existen datos reales, primero inventario y simulación, mantenimiento de escrituras y respaldo verificable. Crear accountAccess explícito (user/pending/no suspendido por defecto, sin aprobar cuentas), alinear users.datingAllowed, solicitudes/auditoría y contador de superadmins con la infraestructura actual; recomponer discoveryCards/matchProfiles sin datos privados. Publicar catálogos compatibles. Mensajes anteriores necesitan pruebas chatUploads confiables y rutas validadas. Fotos necesitan profilePhotoAssets y profilePhotoManifests, referencias internas consistentes en users y proyecciones; validar bytes/MIME/tamaño/hash/generación antes de asociar. Objetos/referencias dudosos se ponen en cuarentena, no se aceptan por conveniencia.

Revocar TODOS los tokens heredados de Storage con precondiciones de generación/metageneración y comprobar antiguas URLs sin sesión; borrar la URL en Firestore no revoca el token. No ejecutar tool/demo/migrate-phase5.mjs contra un proyecto real. Falta un migrador real específico para el inventario elegido; no se ha fabricado ni ejecutado una migración genérica riesgosa. Política de borrado de carnets depende de Job y reintentos: comprobar su ejecución y alertar si quedan tareas pendientes. Borrado genérico por antigüedad del bucket podría eliminar medios referenciados y no se configura.

Reglas Firestore/Storage existentes no se relajaron. Las consultas observadas usan índices automáticos; el ejemplo de índices no está enlazado al despliegue para evitar proponer borrados de índices existentes. Los emuladores no prueban requerimientos de índices reales: validar consultas en desarrollo alojado y añadir únicamente índices que efectivamente falten. Revisar índices existentes antes de publicar este manifiesto, sin borrar índices útiles.

## Autorizaciones y comprobaciones que faltan

Elegir proyectos, bucket exacto, región, dominio Web, package Android definitivo, UID del primer superadmin y cuenta de facturación. Proporcionar configuración cliente pública, no claves privadas. Autorizar creación de infraestructura/IAM, activación de facturación, publicación de reglas/backend/Hosting y cualquier migración por separado. No se ejecutó ninguno de esos pasos.

Primero validar en desarrollo alojado con datos ficticios: compilar imagen Linux/Sharp/FFmpeg, permisos ADC/IAM, Auth y correo, CORS, subida/reproducción de notas de voz físicas Android/Web, lectura de fotos según visibilidad, suspensión, autoaprobación/roles/último superadmin, revocación de URLs antiguas y limpieza con reintentos. App Check/limitación distribuida/monitoreo requieren evaluación antes de apertura pública: el límite actual es por proceso y no evita por sí solo abuso de costos. Falta prueba Linux porque el motor Docker local está apagado. No se afirma validación de producción.

Fuentes: [Cloud Run](https://cloud.google.com/run/docs/container-contract), [identidad de servicio](https://cloud.google.com/run/docs/configuring/services/service-identity), [Job programado](https://cloud.google.com/run/docs/execute/jobs-on-schedule), [REST y reglas](https://firebase.google.com/docs/firestore/use-rest-api), [Storage y facturación](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024).

## Validación local realizada

- flutter analyze: sin observaciones (repetido tras los últimos cambios de configuración).
- flutter test: 274 aprobadas; las 3 pruebas de configuración se repitieron tras bloquear combinaciones demo/alojado.
- Firebase/backend: 208 aprobadas en proyecto demo-tinder-phase3-tests, puertos secundarios y TEMP/TMP aislados. No se ejecutaron fixtures contra el demo principal.
- Backend alojable: 4 pruebas aprobadas de configuración, rechazo de credenciales/hosts de emulador, CORS/token revocado, delegación de fotos a reglas y cursor durable. Las llamadas remotas se sustituyeron por mocks.
- Android demo debug arm64: compilación correcta. Advertencia previa de migración futura de plugins Kotlin; no se actualizan dependencias sin necesidad.
- Imagen Linux: NO compilada, motor Docker apagado; no se afirma compatibilidad FFmpeg/Sharp/IAM de producción sin esta comprobación.
- Demo principal: Web HTTP 200, mismos procesos y cinco puertos locales; worktree de pruebas limpio. Validaciones realizadas sobre la preparación derivada de 351a489, posteriormente consolidada en un commit local. No se publicaron servicios ni se contactó Firebase real.

Comandos para pruebas online: [deploy/PRUEBAS_ONLINE.md](deploy/PRUEBAS_ONLINE.md).
