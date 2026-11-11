# LIGO — entrega visual de staging

Rama `codex/ligo`. Sin commits, push, despliegues ni consultas a producción. Mantener la revisión de Hugo antes de publicar.

## Abrir y probar

- Web: http://127.0.0.1:7465/
- APK local: [ligo-staging-debug.apk](build/ligo-delivery/ligo-staging-debug.apk).
- Compilación Web: `build/ligo-staging/web`.
- Logo vectorial: [horizontal claro](assets/branding/ligo/logo-horizontal-light.svg), [oscuro](assets/branding/ligo/logo-horizontal-dark.svg), [símbolo](assets/branding/ligo/symbol-light.svg). El mismo dibujo vectorial se pinta en Flutter sin depender de una fuente ni de un bitmap del logo.
- Instrucciones de arranque, aislamiento e instalación Android: [staging/README.md](staging/README.md).

Contraseña ficticia común: `Ligo-staging-2026!`. Superadmin `ligo_root@ligo.test`; admin `ligo_admin@ligo.test`; estudiantes completos `ligo_visual_ana@ligo.test` y `ligo_visual_bob@ligo.test`. Exclusivos de emuladores. Ana y Bob ya tienen un match y tres mensajes de prueba; no borrar datos para repetir capturas.

## Implementación

Identidad vectorial llama moderna, variantes claras/oscuras/monocromáticas, favicon, iconos adaptativos y splash. Tema centralizado, landing responsive, tarjetas de Descubrir con swipe configurable y retorno, navegación, perfil/galería/vista previa, preferencias, matches, chat y verificación. Dashboard responsive con permisos existentes, métricas reales, distribución por estado y tabla paginada de usuarios. Catálogos existentes con búsqueda y filtros visuales.

La búsqueda de usuarios se limita explícitamente a las páginas cargadas; «Cargar más» amplía ese conjunto. No hay cifras de crecimiento inventadas. Fotografías conservan sus permisos originales; no se concede acceso especial a fotos por aparecer en una tabla administrativa. Datos históricos sin universidad siguen sin asignación inferida.

Única ampliación funcional autorizada expresamente: endpoints GET `/administration/summary` y `/administration/users` de lectura protegida; reutilizan la autorización del backend, revalidan tras consultar, limitan páginas y campos, y no devuelven carnets ni URLs permanentes. No cambian roles ni reglas.

Archivos principales: `lib/theme/app_theme.dart`, `lib/widgets/{app_ui,brand_header,swipe_card}.dart`, pantallas de auth/home/discovery/matches/chat/profile/preferences/verification, `lib/features/verification/admin_visual.dart`, `backend_client.dart`, `lib/features/academics/catalog_admin_screen.dart`, `tool/backend/{administration-read,http-handler}.mjs`, `assets/branding/ligo/`, recursos Android y Web, `lib/main_ligo_staging.dart`, scripts `tool/ligo/`, pruebas visuales, integración Android y fixtures ficticios de `staging/fixtures/`.

## Comprobaciones

- Flutter: ejecución final completa 311/311 aprobadas después de los últimos ajustes de encuadre y contraste. `flutter analyze`: sin incidencias. Logs `build/ligo-tests-delivered-final.log` y `build/ligo-analyze-delivered.log`. También pasaron 67 pruebas específicas de chat, medios, voz y swipe durante la revisión.
- Backend: 4 pruebas nuevas aprobadas para permisos, métricas reales, paginación/lista blanca y revocación. Incluyen anónimo, user, pendiente y suspendido con claims falsificados. `build/ligo-visual-backend-final.log`.
- Android real de plataforma: integración ejecutada sobre AVD aislado API 36.1 (no teléfono físico), con inicio de sesión, roles root/admin, fotografía privada descargada y decodificada, gesto LIKE cancelado, likes mutuos, match, envío de texto/imagen/audio y recepción/carga del audio. `build/ligo-android-complete-run.log`: All tests passed.
- Web real: portada, sesiones root/admin/user, métricas del backend, lista de usuarios, carreras, Descubrir con fotografía privada, preferencias, perfil, matches y chat con imagen y audio cargado.
- Web release y Android debug staging compilados. Logs finales `build/ligo-web-delivered.log`, `build/ligo-android-delivered.log`. APK de entrega sin instrumentación.
- Reglas y lógica crítica comparadas con la base previa al rediseño; sin cambios. Los 88 archivos respaldados del proyecto original conservan sus hashes; la copia de pruebas original permanece limpia. `build/ligo-preservation-final.json`.

## Límites de la validación

No se realizó grabación con micrófono físico ni prueba auditiva de sonido en este turno. El archivo Android de integración es una señal sintética de un segundo: comprueba almacenamiento, descarga y preparación del reproductor, no captura humana. La funcionalidad de grabación no se reimplementó.

Las capturas de AVD proceden de la aplicación real; las de `build/ligo-visual-captures` son pruebas de widgets con fixtures. La APK staging depende de los emuladores locales y adb reverse; no es una distribución online. Los avisos de KGP de plugins no impidieron compilar; no se actualizaron dependencias ni versiones de plugins durante el rediseño.

Los datos originales y las reglas no se modificaron. El único match y mensajes nuevos pertenecen a las dos cuentas ficticias nuevas del staging LIGO. El staging manual existente y sus catálogos se conservaron.

## Capturas Web reales


### Portada y logo

![Portada y logo](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-portada.jpg)


### Dashboard superadmin

![Dashboard superadmin](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-superadmin.jpg)


### Dashboard admin

![Dashboard admin](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-admin.jpg)


### Usuarios

![Usuarios](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-usuarios.jpg)


### Carreras

![Carreras](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-carreras.jpg)


### Descubrir

![Descubrir](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-descubrir.jpg)


### Preferencias

![Preferencias](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-preferencias.jpg)


### Perfil

![Perfil](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-perfil.jpg)


### Matches

![Matches](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-matches.jpg)


### Chat

![Chat](C:/Users/HP/.codex/visualizations/2026/10/14/01a1384a-289f-7582-bed6-ccf31b6a1774/ligo-web-chat.jpg)


## Capturas Android de la aplicación ejecutada


### login

![Android login](C:/Users/HP/.codex/worktrees/ligo/tinder_universitario_pruebas/build/ligo-android-captures/android-login.png)


### superadmin

![Android superadmin](C:/Users/HP/.codex/worktrees/ligo/tinder_universitario_pruebas/build/ligo-android-captures/android-superadmin.png)


### admin-menu

![Android admin-menu](C:/Users/HP/.codex/worktrees/ligo/tinder_universitario_pruebas/build/ligo-android-captures/android-admin-menu.png)


### discovery

![Android discovery](C:/Users/HP/.codex/worktrees/ligo/tinder_universitario_pruebas/build/ligo-android-captures/android-discovery.png)


### swipe-like

![Android swipe-like](C:/Users/HP/.codex/worktrees/ligo/tinder_universitario_pruebas/build/ligo-android-captures/android-swipe-like.png)


### matches

![Android matches](C:/Users/HP/.codex/worktrees/ligo/tinder_universitario_pruebas/build/ligo-android-captures/android-matches.png)


### chat-enviado

![Android chat-enviado](C:/Users/HP/.codex/worktrees/ligo/tinder_universitario_pruebas/build/ligo-android-captures/android-chat-enviado.png)


### chat-recibido-audio

![Android chat-recibido-audio](C:/Users/HP/.codex/worktrees/ligo/tinder_universitario_pruebas/build/ligo-android-captures/android-chat-recibido-audio.png)

## Integridad de la APK entregada

SHA-256: `40c3ffb115f1b7179d69092cef9a65926d75b3ef648c9a3c606310a3783dc457`. Tamaño: 189279477 bytes (debug). Sin respaldos DPAPI, almacenes de claves, service accounts ni retratos privados de fixtures empaquetados. Manifiesto: `build/ligo-delivery/artifacts.json`.
