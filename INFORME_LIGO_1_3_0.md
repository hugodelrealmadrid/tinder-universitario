# LIGO 1.3.0 (4) — implementación y compatibilidad

## Estado
Implementado en `codex/ligo`, sobre `b1f793e4cfeb3c6ce6f92d870eed4de36f7d1b1b`. Sin commits nuevos, push, publicación ni accesos de prueba a producción. Se conservaron las modificaciones locales anteriores mediante respaldo cifrado DPAPI verificado: `build/ligo-1.3-baseline.json` identifica el archivo y sus hashes. No se modificaron los demos local/showcase.

## Cambios por módulo

- **Chat:** encabezado y acceso al perfil, burbujas, horas y checks reales, separadores por fecha, selección de imagen con confirmación previa, compositor adaptable. El scroll sigue mensajes nuevos cuando corresponde y permite conservar la lectura del historial. Las filas tienen identidad estable para evitar reiniciar reproductores al recibir mensajes. La lectura se registra por visibilidad de la burbuja, no del separador de fecha.
- **Voz:** micrófono predeterminado sin selector; mantener, cancelar a la izquierda, bloquear hacia arriba, detener, escuchar, enviar y descartar. Android puede enviar al soltar si hubo captura suficiente y señal; una pulsación demasiado corta, silenciosa o mientras se autoriza no envía automáticamente. Web conserva la revisión previa. Indicador de señal y duración; límite existente de 60 segundos; salida del chat con confirmación y liberación de recursos. Ante resultado de envío incierto se conserva el borrador en memoria y se impide repetir automáticamente el envío. No hay persistencia garantizada del borrador al cerrar la app.
- **Auditoría:** catálogo centralizado de acciones en español, nombres/correos autorizados, entidad, fechas, filtros y detalle técnico desplegable. Datos desconocidos se identifican como no disponibles; nunca se inventa un resultado. Los nombres resueltos son los actuales, no una instantánea histórica; los eventos originales no se reescriben.
- **Roles:** tabla/selector de personas, búsqueda por nombre/correo, filtros, detalle y confirmación; ningún UID es necesario para el operador. Las operaciones privilegiadas existentes siguen ejecutándose en el servidor.
- **Reportes:** datos mínimos autorizados, motivos legibles, filtros, paginación y decisiones existentes con confirmación. Solo estados realmente soportados: pendiente, revisado y descartado. No se inventan prioridades ni evidencia. La auditoría global sigue reservada a superadmin.
- **Personas y navegación:** tabla de escritorio, tarjetas móviles, filtros compactos, ordenación, carga paginada y detalles. Sidebar en escritorio y selector/drawer en móvil, visibles según permisos. Los datos de auditoría se retiran inmediatamente al revocar el rol; las páginas de auditoría y reportes no comparten estado almacenado.
- **Descubrir y perfiles:** fotografía protagonista, galería reutilizable, ficha ampliada y composición de escritorio en dos zonas; indicadores LIKE/PASAR. Matches con presentación de conversaciones. Se reutilizan las decisiones, preferencias y autorizaciones existentes.
- **Diseño:** tema LIGO coherente para tarjetas, botones, formularios, diálogos y transiciones, contraste del color primario y respeto del movimiento reducido.

## Compatibilidad y seguridad
No se modificó el contrato de mensajes, `chat_service.dart`, reglas Firestore/Storage ni esquemas históricos para esta versión. PCM mono de 16 kHz y WAV conservan la ruta privada existente; adjuntar archivos de audio sigue disponible. No se asignan universidades, roles ni acreditaciones. No se agregaron dependencias.

Se añadieron tres GET protegidos: `/administration/identities` (máximo 40 UID), `/administration/event-feed` y `/administration/report-feed`. Revalidan acceso vigente, usan listas blancas de campos y paginación. Las consultas no otorgan permisos y no devuelven carnets ni tokens. La auditoría exige superadmin también al finalizar la resolución de identidades.

**Límite explícito:** búsqueda, filtros y ordenación operan sobre la página o las páginas cargadas indicadas por la interfaz; no constituyen búsqueda global de todo Firestore. Usuarios se obtienen en bloques de 25; auditoría/reportes, 20. No se incorporó un servicio adicional de búsqueda ni consultas masivas sin límite.

## Pruebas ejecutadas

| Verificación | Resultado |
|---|---|
| `flutter analyze --no-pub` | Sin problemas |
| Suite Flutter final | 335 aprobadas, 0 fallidas |
| Firebase/backend, entorno secundario aislado | 248 aprobadas, 0 fallidas |
| Backend/presentación y compatibilidad adicionales | 20 aprobadas, 0 fallidas |
| Lecturas administrativas sobre emuladores staging | 7 aprobadas; subconjunto de la suite anterior |
| Web staging y Web online preparada | Compilaciones release correctas |
| Android staging y online preparada | Compilaciones debug correctas, versión 1.3.0 (4) |
| Integración nativa Android | Interrumpida: el AVD desapareció y el driver recibió `Service has disappeared`; NO aprobada |

Evidencia: `build/ligo-1.3-analyze-final.log`, `build/ligo-1.3-tests-final.log`, `build/ligo-1.3-backend-regression.log`, `build/ligo-1.3-backend-presentation.log` y logs de compilación `build/ligo-1.3-*-final.log`. No se suman subconjuntos duplicados.

Casos nuevos incluyen gestos, envío incierto sin duplicación, salida durante permisos, renderizado responsive, selección de personas, nombres tras cambios de rol, navegación auditoría/reportes, revocación inmediata de privilegios, acceso provisional limitado y ataques contra las consultas administrativas. Las pruebas usan exclusivamente fixtures ficticios.

## Revisión visual y staging
Se revisó el navegador local con login ficticio, dashboard, auditoría y creación/desactivación de una universidad ficticia por el flujo oficial. No se alteraron las universidades previas. La comprobación posterior de Chrome mediante el control de aplicaciones no pudo continuar por expiración de la aprobación del acceso a la ventana; no se presenta como nueva prueba aprobada.

Las capturas comparativas están en `build/ligo-1.3/COMPARATIVA.html`. `captures/after/web` contiene renderizados Flutter de fixtures a anchos móviles y escritorio; no se presentan como capturas del navegador real. La captura Android nativa `captures/after/android/roles-native.png` muestra el selector real de personas. Los archivos `avd-current*.png` conservan evidencias de diagnóstico, incluido el aviso de System UI; no son pruebas del recorrido completo.

Staging: **http://127.0.0.1:7465/**. Servicios 9399 Auth, 8288 Firestore, 9498 Storage, 7466 backend, solo loopback. CSP bloquea destinos de producción. Proyecto `demo-ligo-staging`. Inicio persistente: `node tool/ligo/start-local.mjs` desde este worktree, únicamente cuando sus puertos estén libres. No usar reconstrucción de fixtures ni `flutter clean`, pues los artefactos y exportaciones están bajo build.

Cuentas ficticias: `ligo_root@ligo.test`, `ligo_admin@ligo.test`, `ligo_visual_ana@ligo.test`, `ligo_visual_bob@ligo.test`; clave de staging `Ligo-staging-2026!`. Son exclusivamente locales. Exportación de los tres servicios cada cinco minutos. La recarga verificada conservó 5 cuentas, 35 documentos y 2 archivos con digest idéntico antes/después; las pruebas nativas añadieron datos ficticios mediante las operaciones oficiales. La exportación final verificada contiene 5 cuentas, 39 documentos y los mismos 2 objetos; se conserva además el respaldo anterior al recorrido. `build/ligo-1.3/staging-final-state.json` registra el digest final.

## Artefactos preparados; NO publicados

- APK de producto staging: `build/ligo-1.3/delivery/LIGO-1.3.0-4-STAGING-debug.apk`. Requiere estos servicios locales y adb reverse; no funciona offline ni se conecta al proyecto real.
- APK online de prueba: `build/ligo-1.3/delivery/LIGO-1.3.0-4-ONLINE-PREPARADA-NO-PUBLICADA.apk`. Apunta al proyecto existente y backend real; no instalar para probar contra datos reales sin autorización y coordinación del backend.
- `LIGO-1.3.0-4-INTEGRATION-NO-DISTRIBUIR.apk`: SOLO ejecutor de pruebas ficticias; nunca distribuir como producto.
- Web online preparada: `build/ligo-1.3/web-online`; Web staging: `build/ligo-staging/web`.
- Manifiesto de integridad y metadatos: `build/ligo-1.3/delivery/manifest.json`.

Son APK debug de evaluación, no una entrega release firmada para tienda. No contienen claves de cuenta de servicio, exportaciones ni datos de usuarios. La configuración pública Firebase y URL del backend son identificadores públicos esperados.

## Pendientes manuales y límites
No hay teléfono físico conectado. El intento nativo instaló y abrió la app, inició sesión con root/admin/Ana/Bob ficticios y navegó por los módulos administrativos; luego el AVD dejó de existir en adb. Antes había mostrado “System UI isn’t responding”, con menos de 1 GB de RAM libre en el host. El driver terminó por pérdida del servicio, sin un resultado completo del test. No se declara aprobada ninguna comprobación nativa de audio. Los logs y la captura del aviso se conservan.

En personas/roles, una fotografía solo se muestra si las reglas actuales permiten al operador acceder a su ficha: un administrador sin perfil de citas elegible puede ver un avatar no disponible. No se abrió un permiso administrativo general de lectura de fotografías para ocultar esa denegación.

No hay teléfono físico conectado. El emulador no permite verificar que una persona sea audible: la entrada PCM de la prueba nativa es sintética y el AVD se ejecuta sin sonido. Falta en Android físico y Chrome/Edge: autorizar micrófono predeterminado, hablar una frase, revisar señal/duración, escucharla, cancelar deslizando, bloquear/revisar/enviar, recibirla en el otro usuario y verificar los checks. Comprobar también retorno desde segundo plano y salida del chat durante grabación. No se declara probado el micrófono físico.

Los plugins existentes producen advertencias de migración Kotlin Gradle; las compilaciones terminaron correctamente. Se utilizó Gradle/TEMP aislado bajo build para evitar el fallo del caché global, sin borrar ni cambiar la configuración global. Se conservan los logs fallidos previos y se distinguen de los resultados finales.

## Publicación posterior (requiere autorización nueva)
1. Revisar este diff contra el respaldo de inicio y ejecutar la prueba física pendiente.
2. Preparar una imagen del backend que incluya las tres consultas nuevas; conservar rutas y operaciones actuales. Publicar primero el backend compatible y verificar permisos sin modificar datos reales.
3. Publicar Web y una APK release firmada con la clave de distribución existente. Mantener plan de vuelta de binarios sin sobrescribir datos.
4. No son necesarias migraciones de datos ni cambios de reglas por el rediseño 1.3. No activar funciones nuevas ni modificar los roles reales.

## Archivos de esta versión respecto del respaldo inicial

- `.gitignore`
- `analysis_options.yaml`
- `integration_test/ligo13_android_staging_test.dart`
- `lib/features/chat/audio_playback.dart`
- `lib/features/chat/chat_screen.dart`
- `lib/features/chat/voice_note_controller.dart`
- `lib/features/chat/voice_note_recorder.dart`
- `lib/features/discovery/discovery_screen.dart`
- `lib/features/matches/match_profile_screen.dart`
- `lib/features/matches/matches_screen.dart`
- `lib/features/profile/profile_preview_screen.dart`
- `lib/features/verification/admin_visual.dart`
- `lib/features/verification/admin_workspace.dart`
- `lib/features/verification/administration_screen.dart`
- `lib/features/verification/audit_presentation.dart`
- `lib/features/verification/backend_client.dart`
- `lib/theme/app_theme.dart`
- `lib/widgets/photo_story.dart`
- `lib/widgets/swipe_card.dart`
- `pubspec.yaml`
- `test/chat_test.dart`
- `test/discovery_test.dart`
- `test/ligo13_navigation_security_test.dart`
- `test/ligo13_ux_test.dart`
- `test/ligo13_visual_proof_test.dart`
- `test/ligo_visual_test.dart`
- `test/ui_redesign_test.dart`
- `test/verification_fixtures.dart`
- `test/verification_phase4_test.dart`
- `test/voice_note_test.dart`
- `test_driver/ligo13_driver.dart`
- `tool/backend/admin-presentation.test.mjs`
- `tool/backend/administration-read.mjs`
- `tool/backend/http-handler.mjs`
- `tool/ligo/administration-read.test.mjs`

## Preservación final
Se compararon nuevamente los 88 archivos del proyecto original: los 88 coinciden byte a byte con el respaldo. Main conserva el commit indicado y la copia `Desktop/tinder_universitario_pruebas` sigue limpia. Comprobante: `build/ligo-1.3/preservation-final.json`. Esta ejecución no publicó servicios, reglas, Hosting ni APK.

## Repetir Android sin compilar
Con un dispositivo de pruebas autorizado conectado, configurar `adb -s ID reverse tcp:9399 tcp:9399` y los puertos 8288, 9498 y 7466 del mismo modo. Mantener staging iniciado. Para el recorrido automatizado usar `flutter drive --use-application-binary=build/ligo-1.3/delivery/LIGO-1.3.0-4-INTEGRATION-NO-DISTRIBUIR.apk -d ID --flavor ligostaging --target=integration_test/ligo13_android_staging_test.dart --driver=test_driver/ligo13_driver.dart --dart-define=LIGO_STAGING=true --no-pub`. Este recorrido añade likes/texto/audio únicamente entre las cuentas ficticias Ana/Bob; la captura es sintética. Para la prueba manual de micrófono instalar la APK **STAGING-debug**, no la APK de integración.
