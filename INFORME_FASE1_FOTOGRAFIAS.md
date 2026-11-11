# Fase 1: fotografías y estabilidad del demo

19 de octubre de 2026. Trabajo exclusivo en `C:\Users\HP\Desktop\tinder_universitario_pruebas`. Se preservaron cambios locales previos; respaldo de su diff en `audit-phase1-preexisting.patch`. No hubo commit, push, merge, reset ni deploy. No se modificó el arranque normal, main, el proyecto original ni Firebase de producción. No se implementaron filtros, roles ni verificación universitaria.

## Correcciones

1. CSP del servidor: `connect-src` permite `blob:` además del servidor y los tres emuladores locales. La guardia JavaScript permite blobs del mismo origen y rechaza los de otros orígenes. No se añadieron destinos externos. Una prueba real confirmó lectura por XHR y otra el bloqueo CSP de un dominio reservado `.invalid`, sin credenciales ni datos.
2. Descubrir: HTTP solo se admite con `TINDER_DEMO=true`, proyecto demo y bucket demo. La URL debe usar exactamente `127.0.0.1:9198`, bucket demo y ruta canónica de fotos. El modo normal sigue exigiendo HTTPS. La validación de rutas locales se comparte con el borrado.
3. AppPhoto: diagnóstico por categorías (`access-denied`, `not-found`, `network`, `load-failed`) sin URL, token ni texto de excepción. El usuario recibe un mensaje genérico accesible y un reintento que invalida la entrada de caché.
4. Borrado: la prueba real encontró que `refFromURL` de FlutterFire no reconoce `127.0.0.1` en la versión instalada. Se utiliza la ruta local validada sobre la misma instancia Storage ya emulada, conservando comprobaciones de bucket y propietario. Producción conserva su flujo. Se comprobó que eliminar la principal borra objeto y referencia y selecciona la foto restante. El huérfano sintético del intento previo se limpió tras comprobar que no tenía referencias.
5. Chat Web: `ImageDescriptor.width/height` no están implementados para imágenes codificadas en el motor Web instalado. Se verifican dimensiones desde cabeceras PNG/JPEG/WebP antes de decodificar y se exige decodificación real; después se vuelven a comprobar dimensiones. Android conserva el flujo original mediante descriptor. Se mantienen límites de tamaño, dimensiones y MIME. La inspección de cabecera no se presenta como validación suficiente del contenido.
6. Recarga: FlutterFire restauraba Auth antes de ejecutar `useAuthEmulator`; la comprobación de SDK cancelaba el arranque de forma segura. El módulo demo configura Auth síncronamente al inicializarlo, antes de restaurar sesión, y utiliza persistencia por pestaña. Se verificó recarga conservando las dos sesiones y endpoints locales. No se relajó la comprobación de aislamiento.

## Pruebas finales

| Comprobación | Resultado | Evidencia |
| --- | --- | --- |
| flutter analyze --no-pub | Sin incidencias | audit-photo-analyze-release.log |
| flutter test --no-pub | 223 aprobadas, 0 fallidas | audit-photo-tests-release.log |
| Reglas Firestore/Storage con emuladores demo | 142 aprobadas, 0 fallidas | audit-photo-rules.log |
| Guardia de red, inicialización Auth y verificación demo | 9 aprobadas, 0 fallidas | audit-photo-demo-all.log |
| Compilación Web final | Correcta | audit-photo-build-release.log |
| Borrado real de la principal | Objeto ausente, referencia ausente, principal restante válida | audit-photo-operation-after-final.log |

Los intentos intermedios detectaron incompatibilidad de una clase interna, una fixture sin Material, arranque prematuro de la suite de reglas y los fallos reales de borrado, validación Web y recarga descritos. Se corrigieron y repitieron las comprobaciones. Los resultados de la tabla son los finales, no los intentos intermedios.

## Pruebas reales de navegador

Con cuentas sintéticas Ana y Bob: acceso, perfil con foto, selección desde selector real, subida, cambio de principal y vista previa con la nueva imagen. Después se eliminó la principal y se verificó su eliminación física mediante SDK contra emuladores. Matches muestra el avatar del match y Descubrir muestra a Carla con su foto HTTP local. Bob envió una PNG por el selector real; tanto Bob como Ana la visualizaron. Ana descargó la imagen y abrió su visor. Ambas sesiones recargaron correctamente con el inicializador final.

Evidencia visual en `build/photo-preview.png`, `build/photo-discovery.png` y `build/photo-chat-final.png`. Las imágenes son siluetas coloreadas sintéticas, no fotografías personales ni placeholders de error.

## Aislamiento y uso

Abrir **http://127.0.0.1:7357/__demo/start.html**. Proyecto único `demo-tinder-universitario`, bucket `demo-tinder-universitario.appspot.com`. Auth 9099, Firestore 8088, Storage 9198 y Web 7357, vinculados a loopback. Configuración real del SDK y eventos guardados en `audit-photo-status-final.json`. Los intentos de fuentes externas durante la pantalla de error intermedia fueron bloqueados; no se habilitaron esos destinos para corregirla. Las pruebas de guardia confirman rechazo de hosts Firebase de producción antes de llegar al transporte.

Ana: `ana.manual@demo.test`; Bob: `bob.manual@demo.test`; contraseña de ambas: `DemoTinder2026!`. Usar ventanas normal/incógnito o navegadores diferentes. Carla es una fixture adicional de Descubrir. Mantener los servicios activos; datos temporales. No usar el arranque normal para estas pruebas. Comando seguro de recompilación en `PRUEBAS_MANUALES_DEMO.md`, ahora con `--dart-define=TINDER_DEMO=true`.

## Pendientes manuales y límites

- Repetir en Chrome/Edge externos y un dispositivo Android. Esta fase verificó el navegador integrado y PNG reales; no ejecutó Android ni certifica todos los navegadores.
- Probar JPEG/WebP reales de teléfonos, orientación EXIF, imágenes grandes y pérdidas de red durante subida/borrado. Las pruebas de cabeceras y límites no sustituyen esa matriz de archivos reales.
- Los riesgos ya documentados de tokens de descarga, clientes manipulados, MIME y reconciliación entre Firestore/Storage requieren las protecciones de servidor del informe multimedia. Esta fase no afirma haberlos eliminado.

## Archivos de esta fase

Aplicación: `lib/widgets/app_ui.dart`, `lib/features/discovery/discovery_models.dart`, `lib/features/discovery/discovery_service.dart`, `lib/features/profile/photo_store.dart`, `lib/features/profile/demo_photo_url.dart` (nuevo), `lib/features/chat/chat_media_validation.dart`, `lib/main_demo.dart`.

Pruebas Flutter: `test/photo_phase1_test.dart` (nuevo), `test/chat_media_validation_test.dart`.

Herramientas demo: `tool/demo/server.mjs`, `browser.js`, `bootstrap.js`, `probe.js`, `seed.mjs`, `verify.test.mjs`; nuevos `auth-demo.js`, `auth-demo.test.mjs`, `browser.test.mjs`, `photo-state.mjs`.

Documentación/evidencia: este informe, `PRUEBAS_MANUALES_DEMO.md`, `audit-phase1-preexisting.patch`, `audit-photo-status-final.json` y la actualización de `audit-demo-seed.json` al sembrar las tres fixtures. Logs y compilaciones permanecen locales e ignorados por Git.
