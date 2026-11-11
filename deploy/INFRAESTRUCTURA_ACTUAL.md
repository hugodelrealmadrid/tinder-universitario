# Infraestructura online preparada

Proyecto tinder-universitario; región us-east1.

- Backend: https://tinder-api-rcgmfjcicq-ue.a.run.app
- Cloud Build validado: 520d5752-c4f9-4322-a3dd-3b6046883662.
- Imagen fijada: us-east1-docker.pkg.dev/tinder-universitario/tinder/backend@sha256:3c12581a13a4549e90f018452461c74e3bf97ed678e39d16fd5efb6058f93bcf
- Cloud Run: mínimo 0, máximo 1 en servicio y revisión, concurrencia 8, CPU 1 con facturación por solicitud, memoria 1 GiB.
- Dos identidades sin claves JSON: tinder-api (datos de aplicación) y tinder-builder (fuentes temporales, repositorio y logs). Los permisos Storage/Artifact Registry se limitan al bucket/repositorio correspondiente.
- Bucket de fuentes exclusivo, privado, con eliminación a siete días. Nunca contiene respaldos, credenciales ni fuentes del cliente.
- TINDER_PRE_CUTOVER=true: después de validar Firebase ID token, devuelve 503 sin operaciones de datos. Sin token o con token inválido devuelve 401. La llegada HTTP pública solo permite que el backend valide los tokens Firebase; no concede permisos administrativos.
- No ejecutar login/provisión, migración, revocación, reglas, bootstrap ni publicaciones hasta autorización del corte. No se creó ni ejecutó limpieza programada.

Validaciones: seis pruebas locales de backend; doce de respaldo/migración; nueve comprobaciones HTTPS; PNG y WAV decodificados en Linux sin red. El arranque real de Cloud Run terminó correctamente. No se probaron flujos con usuarios reales contra datos migrados.

Recibos, inventario de fuentes, hashes, digest, límites y comprobaciones HTTPS: build/cloud-preparation/ (ignorado). Respaldos anteriores intactos. Demo local respondió HTTP 200 sin reinicios.

La configuración local ignorada deploy/existing-project.local.json ya contiene la URL HTTPS del backend. No se compiló ni publicó la aplicación en esta etapa. Google Cloud CLI portable quedó preparado en build/cloud-preparation/sdk; la sesión Firebase existente permitió operar por REST sin otra autenticación.

Antes del corte: revisión humana de pertenencia universitaria del candidato, compilaciones Web/Android, ventana de mantenimiento y respaldo actualizado si cambian datos. Requiere autorización independiente para migración, reglas, revocación, bootstrap, activación de operaciones (TINDER_PRE_CUTOVER=false), publicación y limpieza programada. Seguir deploy/EXISTENTE.md con el respaldo de diez cuentas, no el histórico de nueve. No ejecutar las instrucciones de proyecto nuevo de PRUEBAS_ONLINE.md.
