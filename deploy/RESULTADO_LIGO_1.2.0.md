# LIGO 1.2.0 (3) — publicación del 2 de noviembre de 2026

- Proyecto existente: tinder-universitario. Sin proyectos, servicios, IAM ni cambios de facturación nuevos.
- Web: https://tinder-universitario.web.app/
- Android privado: https://appdistribution.firebase.google.com/testerapps/1:208598232745:android:91f9c08096304b1aff43b8/releases/4lh7ajf4i0b0g
- Distribución confirmada para los dos correos autorizados. Misma firma debug anterior; no apta para Google Play.
- Backend: tinder-api-00004-f6t, 100% de tráfico, imagen Linux validada fijada por digest 676da7e415d8657a017c28df1bf4d84c904a7edce802b41241be18ac324e6768. Límites conservados: mínimo 0, máximo 1 y concurrencia 8.
- Firestore Rules publicadas y cotejadas; Storage Rules conservadas y cotejadas con el archivo validado.
- Tres tokens revocados mediante precondiciones; enlaces antiguos rechazados y cero tokens activos en el inventario. Archivos originales conservados.
- Respaldo nuevo cifrado y verificado: build/online-backups/2026-11-02T18-04-02-927Z/. Respaldo anterior intacto. Recuperación por tráfico/release registrada en control-before.dpapi; no hubo necesidad de ejecutarla.

## Comprobaciones efectivamente realizadas

- Instantánea posterior: 14 cuentas con campos de seguridad intactos; 219 documentos sin diferencias de contenido; 27 objetos con generaciones y checksums conservados. Roles, acreditaciones, preferencias, matches y mensajes intactos.
- HTTP real: 401 sin autenticación/token inválido; CORS ajeno 403. Preflight del origen autorizado 204 antes de promover.
- Reglas remotas coinciden con las validadas. Hashes públicos de index.html, main.dart.js, bootstrap y manifest coinciden con los artefactos preparados.
- Funciones reales del backend con adaptador REST exclusivamente de lectura sobre producción: seis fotos principales de cuentas aprobadas y cinco medios de chat (dos imágenes y tres WAV), autorización y SHA correctos. Esta prueba no crea sesiones de los propietarios ni equivale a una reproducción física en Android.
- Dos fotos de cuentas pendientes conservan la denegación previa; una de ellas no tiene referencia publicada. No se cambió su estado ni se borraron archivos.
- Navegador, sesión existente: dashboard, catálogo universitario, formulario abierto y cancelado, perfil/foto privada, filtros y matches cargados. Descubrir devuelve correctamente un conjunto compatible vacío con las preferencias/decisiones actuales.
- Validación previa de los artefactos: analyze limpio; 311 pruebas Flutter y 261 backend/reglas; smoke Linux correcto. En esta publicación se añadieron y pasaron dos pruebas del publicador.
- Original: los 88 archivos comparados siguen idénticos; main no cambió; copia original de pruebas limpia. Sin push ni cambios en demos/showcase.

## Límites y acciones manuales pendientes

No se crearon likes, matches, mensajes ni catálogos para probar producción; tampoco se abrieron chats que pudieran escribir readAt. Las escrituras y los ataques de roles fueron probados en emuladores antes de publicar. Falta validar desde los teléfonos la instalación, reproducción/grabación y envío real entre participantes autorizados.

CRUD multiuniversidad publicado, pero no se activó la política de registro multiuniversidad: todavía no existen universidades ni carreras vinculadas en producción. El superadmin debe crear catálogos reales y autorizar separadamente su activación aditiva. No hubo asignaciones históricas ni migraciones.

Permanecen seis alertas NPM moderadas transitivas documentadas, ninguna alta/crítica en la auditoría ejecutada; firma release para tiendas pendiente. No se activaron notificaciones push ni se modificaron plantillas de correo.

Evidencia privada cifrada y recibos: build/ligo-deployments/2026-11-02T18-06-36-906Z/. No versionar build/, respaldos ni configuraciones locales.
