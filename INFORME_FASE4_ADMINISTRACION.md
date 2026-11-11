# Informe Fase 4 — Verificación universitaria y administración

Fecha: 19 de octubre de 2026. Copia exclusiva: `C:\Users\HP\Desktop\tinder_universitario_pruebas`.

## Resultado y límites

Implementadas las interfaces de estudiante, administrador y superadministrador, conectadas a operaciones reales del backend privado de la Fase 3. El demo conserva las fases anteriores y usa únicamente el proyecto ficticio `demo-tinder-universitario`. No se hizo commit, push, merge, reset ni deploy; no se modificaron main, el proyecto original ni Firebase de producción.

La implementación queda preparada para pruebas de aceptación en demo. **No recomiendo integrarla para producción todavía:** permanecen las brechas heredadas de fotografías de perfil y medios de chat, además de tareas operativas indicadas más adelante.

Se revisó Git antes de editar y se conservó el diff anterior en `audit-phase4-preexisting.patch`. Los modelos, cliente y barrera de verificación anteriores están respaldados como archivos `.bak` en `build/phase4-before`. Los emuladores estaban detenidos; se restauró `build/phase3-fixtures-secure-final`, sin volver a sembrar ni reemplazar los datos de Ana, Bob o Carla. Las pruebas destructivas corrieron en emuladores separados.

## Interfaces y arquitectura

### Estudiante

`UniversityGate` observa el documento de autorización propio confirmado por el servidor. Las cuentas sin aprobación explícita reciben la pantalla de verificación; una suspensión o pérdida del rol administrativo cierra también las rutas y diálogos previamente abiertos. Las reglas y el backend siguen siendo la autoridad definitiva.

La pantalla explica que solo se admite Univalle sede Cochabamba y permite seleccionar un carnet físico o virtual en JPG, PNG o WebP. El selector lee un stream acotado; se comprueban extensión, tamaño de hasta 5 MB, firma, dimensiones y decodificación real antes de subir. El backend vuelve a decodificar con sharp, limita píxeles, rechaza contenido inválido y recodifica a PNG sin EXIF. Esta validación no acredita por sí sola la autenticidad ni la pertenencia institucional: esa decisión sigue siendo humana.

Hay estados pendiente/rechazado, fecha, motivo comprensible, selección/descartar/enviar, actualización y retiro con confirmación. El rechazo permite una nueva solicitud y conserva el historial anterior. Al aprobar, la barrera abre la aplicación; una suspensión impide cargar carnets y usar citas. Las fotografías de carnets no se incorporan al perfil ni a sus galerías.

### Administración

Las cuentas admin aprobadas y no suspendidas entran al dashboard. Incluye bandeja de pendientes y consultas de aprobadas/rechazadas, fechas, revisor, motivo e historial por solicitud. Las solicitudes y la auditoría se paginan de 20 en 20 por identificador; no se presentan como un orden cronológico. Las propias solicitudes no ofrecen revisión.

El visor obtiene bytes autenticados mediante el backend y utiliza `RawImage` con imagen decodificada de propiedad del widget, sin `ImageCache`. Cierra su contenido al perder foco o tras 60 segundos, libera la imagen al desmontarse y recibe `Cache-Control: no-store`. No genera URLs permanentes ni agrega cachés persistentes de carnets. Un administrador autorizado aún puede hacer capturas o copiar bytes desde sus herramientas: la interfaz no sustituye la política de confidencialidad ni la seguridad del dispositivo.

Aprobar exige confirmación. Rechazar exige elegir un motivo del catálogo del servidor; no se admite motivo vacío. Los botones se desactivan durante la operación. Una decisión concurrente devuelve HTTP 409 y la pantalla actualiza la lista. No se permite aprobar una solicitud vencida aunque todavía no haya pasado el worker.

Reportes muestra la bandeja pendiente, fecha, motivo y detalle, permite marcar revisado/descartar con confirmación y abrir la cuenta reportada para suspender/restablecer. La consulta de cuentas pide UID y devuelve únicamente rol, verificación y suspensión; no expone correo ni documentos privados. La suspensión utiliza motivos codificados y no cambia `isActive`. La bandeja de reportes conserva el límite heredado de 20 registros por consulta; al resolverlos se consultan los siguientes. Su paginación completa y el caso de muchas denuncias sobre el propio revisor requieren mejora antes de uso a escala.

### Superadministración

Incluye lo anterior y gestión de roles user/admin de otras cuentas mediante operaciones privilegiadas, con confirmación y auditoría. No ofrece cambios del propio rol ni promoción a superadmin en el panel. La protección del último superadministrador permanece en las transacciones del servidor. Asignar un rol no aprueba una verificación pendiente.

La auditoría, exclusiva de superadmin, muestra actor, destinatario, acción, motivo codificado, solicitud y fecha. No incluye imágenes, tokens, correo, documentos ni el texto sensible de reportes.

### Backend, reglas y limpieza

Se reutilizan `accountAccess`, el espejo protegido `users.datingAllowed`, las solicitudes, la auditoría, el registro de superadministradores y las tareas de limpieza de Fase 3. No fue necesario ampliar las reglas ni permitir lecturas cliente de colecciones administrativas o carnets.

Se agregaron consultas autorizadas de solicitud propia actual, historial por estado con cursor y auditoría con cursor. Las respuestas de solicitudes usan listas blancas y fechas ISO; nunca devuelven `documentPath` ni generaciones. Reportes también usa una lista blanca. La lectura del carnet revalida permiso y estado después de descargar del almacenamiento, antes de devolver los bytes.

Se corrigieron dos problemas de transporte: el proxy demo descartaba parámetros de consulta, y el servidor convertía una solicitud propia inexistente (`null`) en `{ok:true}`. Ahora ambos contratos tienen pruebas mediante HTTP real.

Las decisiones y resoluciones de reportes detectan duplicados. La eliminación de carnets, el retiro, el vencimiento de 24 horas y los reintentos persistentes de limpieza continúan en el backend; no se delegan al navegador. Resolver una solicitud impide inmediatamente su nueva lectura, incluso si la eliminación física tiene que reintentarse.

## Archivos de esta fase

- `lib/features/verification/university_verification_screen.dart` — nuevo flujo del estudiante y validación de selección.
- `lib/features/verification/administration_screen.dart` — dashboards, visor efímero, reportes, suspensión, roles y auditoría.
- `lib/features/verification/university_gate.dart` — conexión reactiva y cierre de rutas al perder autorización.
- `lib/features/verification/backend_client.dart` — nuevas consultas y errores seguros tipados.
- `lib/features/auth/auth_service.dart` — acceso al Auth inyectado para reutilizar la misma identidad en el cliente backend.
- `lib/main_demo.dart` — reserva espacio para los avisos de aislamiento y Auth Emulator, evitando tapar los encabezados.
- `tool/backend/verification.mjs` — consultas mínimas, cursores, conflictos, vencimiento y revalidación de lectura.
- `tool/backend/server.mjs` — rutas nuevas, HTTP 409 y respuesta null correcta.
- `tool/demo/server.mjs` — preserva parámetros de consulta del proxy fijo local.
- `tool/demo/prepare-phase4.mjs` — preparación explícita e idempotente de identidades y documentos ficticios, usando operaciones reales del backend para aprobar, rechazar y asignar roles.
- `tool/demo/phase4-http-check.mjs` — flujo de extremo a extremo HTTP con tokens reales del emulador Auth.
- `tool/demo/phase4-status.mjs` — comprobación de cuentas, SDKs, red y limpieza sin modificar datos.
- `tool/phase3.test.mjs` — ocho casos adicionales de backend/seguridad.
- `test/verification_phase4_test.dart`, `test/verification_fixtures.dart` — interfaces, validación, privacidad, conflictos, carga y responsividad.
- `test/university_access_test.dart` — cliente inyectable y revocación administrativa con un carnet abierto.
- Este informe, evidencias, respaldos y exportación final del demo.

El resto de modificaciones que muestra Git proviene de fases anteriores y se conservó.

## Pruebas y resultados

| Comprobación final | Resultado | Evidencia |
| --- | --- | --- |
| flutter analyze --no-pub | Sin incidencias | audit-phase4-analyze-final.log |
| flutter test --no-pub | 266 aprobadas, 0 fallidas | audit-phase4-flutter-final.log |
| Backend y ataques de Fases 3–4 | 36 aprobadas, 0 fallidas | audit-phase4-backend-final-tests.log |
| Regresión Firebase/reglas/backend anteriores | 148 aprobadas, 0 fallidas | audit-phase4-regression-local.log |
| Aislamiento y regresión demo | 10 aprobadas, 0 fallidas | audit-phase4-demo-final.log |
| HTTP real autenticado | 7 grupos aprobados | audit-phase4-http.log |
| Compilación Web demo | Correcta | audit-phase4-web-final.log |
| Compilación Android debug | Correcta | audit-phase4-android-final.log |
| git diff --check | Sin errores de whitespace | Comprobación terminal |

Los 36 casos de seguridad incluyen autoaprobación, escalada, roles falsos, último superadmin y concurrencia, carnets ajenos, suspensión, acceso a chats anteriores, privacidad sin tokens, imágenes inválidas, limpieza y reintentos. Los ocho casos añadidos cubren DTO/paginación, solicitud propia, auditoría restringida, rechazo/reenvío/aprobación, decisión simultánea, vencimiento previo al worker y resolución duplicada de reportes. Las reglas también conservan los checks y medios de chat de las fases anteriores.

Las pruebas Flutter nuevas cubren selección, descarte, envío y retiro; motivo y reenvío; usuarios suspendidos y acceso directo al panel; confirmaciones; conflictos; administración de roles ajenos; autorrol prohibido; reportes; botones durante carga; vista privada sin ImageCache, vencimiento y pérdida de foco; diseño a 360 píxeles; y cierre del carnet abierto al revocar el rol.

Las ejecuciones finales no tienen fallos. Hubo intentos iniciales fallidos por restricciones de acceso local del sandbox, variables de puerto incorrectas (el guard de aislamiento abortó antes de ejecutar las pruebas) y sincronización/desplazamiento del arnés de widgets; se corrigieron y se ejecutaron de nuevo las suites. No se debilitaron reglas para obtener los resultados.

Android emitió un aviso de compatibilidad futura de Kotlin Gradle Plugin en plugins existentes; la compilación actual finalizó. **No se ejecutó Android. El APK usa el arranque normal del proyecto: no instalarlo para pruebas aisladas.** Hace falta preparar primero una entrada Android demo que configure todos los emuladores antes de inicializar los SDK, y probar en dispositivo/emulador. La entrada aislada actual es Web.

## Prueba real de navegador

En el navegador integrado basado en Chromium, con sesiones separadas:

1. Admin inició sesión y obtuvo pendientes reales; abrió el carnet ficticio mediante backend privado.
2. Rechazó al estudiante con «Fotografía ilegible». La sesión del estudiante mostró el estado y el motivo en vivo.
3. El estudiante seleccionó el PNG ficticio, superó validación, lo reenvió y quedó pendiente.
4. Admin aprobó tras confirmar. La sesión del estudiante pasó a Inicio con Descubrir, Matches y Perfil habilitados.
5. Admin suspendió esa misma cuenta ficticia. La sesión abierta perdió las funciones de citas y mostró suspensión. Se restableció mediante backend y recuperó Inicio.
6. Superadmin abrió auditoría y consulta de cuentas, con la gestión de administradores disponible. El admin ordinario no recibió esa gestión ni auditoría.

Las acciones de asignar/revocar roles se comprobaron en widgets, transacciones de emulador y HTTP real. Las pruebas de autenticidad documental usan exclusivamente un PNG que dice «DOCUMENTO FICTICIO — SOLO DEMO / NO VALIDO COMO CARNET REAL». No se verificó la pertenencia real de ningún estudiante. Chrome y Edge externos, Android real, cámara nativa y accesibilidad con lector de pantalla requieren aceptación manual adicional.

## Demo, cuentas y pasos manuales

Abrir **http://127.0.0.1:7357/__demo/start.html**. Esperar el aviso verde «DEMO LOCAL VERIFICADO». Utilizar pestañas independientes o cerrar sesión para cambiar de cuenta. Todas las contraseñas ficticias son **DemoTinder2026!**.

| Uso | Correo | UID | Estado esperado |
| --- | --- | --- | --- |
| Usuario pendiente | pendiente@demo.test | demo_pending | Pendiente; sin citas |
| Usuario aprobado con perfil completo y match | ana.manual@demo.test | manual_ana | Aprobada; match con Bob |
| Segundo usuario aprobado | bob.manual@demo.test | manual_bob | Aprobado; match con Ana |
| Usuario del flujo probado | estudiante@demo.test | demo_student | Aprobado y restablecido al finalizar |
| Administrador | admin@demo.test | demo_admin | Admin aprobado |
| Superadministrador | superadmin@demo.test | demo_superadmin | Superadmin aprobado |
| Reenvío tras rechazo | rechazado@demo.test | demo_rejected | Rechazado por imagen ilegible |
| Cuenta suspendida | suspendido@demo.test | demo_suspended | Suspendida; sin citas |

Documento de prueba: `build/phase4-fixtures/carnet-ficticio.png`. **No utilizar carnets reales en este demo.** El script de preparación no vuelve a aprobar ni modifica decisiones existentes al repetirse.

Para los tres roles:

1. **Estudiante:** entrar como pendiente o rechazado, seleccionar el PNG ficticio, enviar, comprobar estado sin Descubrir/Matches/chat. Puede retirar o reenviar tras rechazo. Una aprobación recibida habilita Inicio automáticamente. Para probar citas con datos completos usar Ana/Bob.
2. **Admin:** revisar la bandeja, abrir el carnet, cerrarlo y comprobar ocultación tras 60 segundos/cambio de ventana. Rechazar con motivo, ver actualización del estudiante, aceptar reenvío y aprobar. Consultar Aprobadas/Rechazadas para el historial. En Reportes, abrir la cuenta reportada; en Cuentas, usar un UID ficticio para suspender/restablecer. No suspender las cuentas administrativas durante una demostración compartida.
3. **Superadmin:** en Cuentas consultar `demo_student`, asignar admin, comprobar el nuevo panel en esa sesión, revocar a user y comprobar que pierde administración. No usar el propio UID para modificar roles. Ver Auditoría y cargar más registros. Los intentos prohibidos siguen siendo denegados por servidor aunque se construya una petición manual.
4. **Concurrencia:** dos administradores abren la misma solicitud; uno resuelve y el otro debe recibir conflicto/actualización, sin segunda decisión ni auditoría duplicada. El caso fue automatizado; repetir manualmente para aceptación de UX.
5. **Pendiente/suspendido:** intentar volver con Atrás a una conversación anterior o navegar directamente: la barrera debe cerrarla y las lecturas/escrituras protegidas deben seguir denegadas. La seguridad de esos accesos se probó en emuladores y la revocación de ruta abierta en widgets.

Servicios demo principales: Web 7357, backend 7360, Auth 9099, Firestore 8088, Storage 9198, hub 4400 y UI 4000, todos vinculados a 127.0.0.1. Se conserva la CSP que permite solo el propio origen, blobs locales y endpoints de emuladores autorizados. El backend vuelve a comprobar el hub y rechaza proyectos que no comiencen por `demo-`; no usa credenciales de producción ni fallback remoto. Las pruebas destructivas usan otro proyecto y puertos 9199/8188/9298/hub 4410.

## Riesgos y decisiones pendientes

- **Fotos de perfil con tokens permanentes:** sigue el riesgo de descarga anónima de una URL conocida. La protección de carnets y chat no corrige las fotografías heredadas de perfil. Migrar transporte y revocar tokens antes de producción.
- **Integridad de medios de chat:** el backend conserva validación declarativa de MIME/tamaño/autorización y la validación fuerte del cliente; falta validación fuerte del contenido y finalización privilegiada que vincule archivo y mensaje, además de reconciliación de huérfanos. Fase 4 no los resuelve.
- **Operación y volumen:** worker demo sin escaneo paginado de vencimientos ni cola indexada por vencimiento; faltan monitorización, alertas y pruebas de carga. La paginación nueva de solicitudes/auditoría no corrige esos escaneos ni completa la bandeja de reportes a escala.
- **Retención institucional:** 24 horas para pendientes y eliminación programada al resolver son valores heredados del demo. Confirmar vigencia aceptada, criterios de rechazo, apelaciones, soporte y retención de metadatos/auditoría. El proceso de eliminación puede reintentar; no se promete borrado físico instantáneo.
- **Validación de identidad:** revisión humana de fotografía, sin consulta oficial a Univalle, OCR fiable ni validación antifraude institucional. Definir cómo vincular identidad y pertenencia antes de usar carnets reales. El panel consulta cuentas por UID y minimiza datos; no agrega acceso general a documentos privados de estudiantes.
- **Dependencias:** permanecen las alertas npm documentadas en Fase 3 (7 en su última auditoría). No se cambió el árbol de dependencias ni se hizo otra auditoría de versiones en esta fase. También sigue pendiente investigar el aviso MaxListeners del SDK observado en Fase 3 mediante una prueba de carga; no se declaró una fuga resuelta.
- **Producción:** el servidor de esta copia está deliberadamente restringido a emuladores. Preparar despliegue confiable, IAM, HTTPS, gestión de secretos, rate limiting distribuido, scheduler y procedimientos administrativos consistentes con `datingAllowed`. Nunca reutilizar el bootstrap ni estas contraseñas en producción.
- **Plataformas:** compilación Android comprobada, ejecución pendiente; Chrome/Edge externos y lectores de pantalla pendientes. No interpretar la prueba del navegador integrado como certificación de todas las plataformas.

Recomendación: realizar ahora la aceptación manual de Fase 4 en el demo aislado. Resolver las brechas heredadas y la preparación operativa antes de considerar integración o publicación para usuarios reales.


## Evidencia final y conservación

La verificación `audit-phase4-status-check.log` confirmó las ocho cuentas documentadas, 336 recursos/solicitudes observados exclusivamente en los orígenes locales permitidos, cinco configuraciones de SDK exclusivamente demo, cero recursos externos, un carnet privado pendiente sin tokens y seis solicitudes resueltas sin rutas privadas ni generaciones. No quedaron tareas pendientes de limpieza en esa comprobación. Los contadores reflejan ese instante, no una garantía de ausencia de incidentes futuros.

Se dejó `pendiente@demo.test` con un carnet ficticio ya enviado y listo para revisar. Para volver a probar selección puede retirar la solicitud y enviar otra. La cuenta `estudiante@demo.test` quedó aprobada y sin suspensión después del flujo completo.

Exportación conservada: `build/phase4-fixtures-final`, con Auth, Firestore y Storage; registro `audit-phase4-export.log`. Para una restauración futura usar ese import con `firebase.demo.json` y el proyecto explícito `demo-tinder-universitario`; no ejecutar el seed ni repetir el bootstrap. Después iniciar `node tool/backend/server.mjs` y `node tool/demo/server.mjs` desde esta copia. No iniciar duplicados mientras estén ocupados los puertos. El SDK Java local requerido por los emuladores está en `C:\Program Files\Android\Android Studio\jbr`; la caché de emuladores de esta copia está en `tool/emulator-cache`.

Los emuladores auxiliares de pruebas se cerraron al terminar; se mantienen los servicios del demo principal. Captura exclusivamente ficticia del visor final: `build/phase4-carnet-privado.png`. El documento se cerró en la interfaz al terminar la comprobación; no se deja una vista sensible abierta.
