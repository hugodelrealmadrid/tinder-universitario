# Fase 2: funcionalidades del docente

Actualización posterior de voz real: el usuario activó la entrada física y confirmó que se escucha. Se verificó en Flutter Web la captura con señal, vista previa, envío al demo y reproducción como Bob con lectura confirmada. El informe `INFORME_CORRECCION_VOZ_WEB.md` registra la nota de 10,752 segundos y la evidencia. Los resultados vigentes tras esa corrección son 246 pruebas Flutter, 148 de reglas y 10 de demo aprobadas; analyze limpio y Web compilado. Android continúa pendiente de ejecución. Las cifras y limitaciones de la entrega inicial que siguen son históricas.

19 de octubre de 2026. Trabajo exclusivo en la copia de pruebas. Se conservaron los cambios anteriores en `audit-teacher-phase2-preexisting.patch`. No hubo commit, push, merge, reset ni deploy; no se modificaron main, el proyecto original ni Firebase producción.

## Implementación

- Notas de voz: botón de micrófono, mantener presionado, desplazar a la izquierda para cancelar, soltar para escuchar antes de enviar, detener, descartar y confirmar envío. También admite pulsar para iniciar/detener por accesibilidad. Conserva adjuntar archivos de audio. Usa `record 7.1.2`, PCM mono 16 kHz empaquetado como WAV, máximo 60 segundos (aproximadamente 1,92 MB), compatible con el reproductor existente. Captura en memoria, sin archivo temporal persistente; cancela al salir o pasar a segundo plano. No sube nada antes de confirmar. Reutiliza el servicio de medios y su registro de subidas pendientes; los fallos de envío ambiguos indican revisar el chat para evitar duplicados.
- Reproductor compartido: duración, progreso, pausa y búsqueda para notas y adjuntos. Errores de captura clasificados sin registrar excepciones, URLs ni datos personales. Permiso Android RECORD_AUDIO declarado.
- Perfil público desde Matches y encabezado del chat: nombre, edad, carrera, descripción, intereses y galería. Proyección independiente `matchProfiles`, sin correo, fecha de nacimiento, documentos o roles. Las reglas exigen propietario o match activo sin bloqueo, y proyección exacta del perfil; no permiten listar galerías. No se abrió lectura de `users` ajenos. Perfiles antiguos sin proyección usan la tarjeta pública autorizada con foto principal hasta republicar; el demo recibió una migración aditiva de sus tres galerías.
- Preferencias: selección de hasta cinco carreras activas del catálogo existente, sin selección equivale a todas. Compatibilidad recíproca en Descubrir y reglas. Preferencias antiguas sin campo siguen funcionando. Se reemplazó el texto de edad por «Selecciona el rango de edad» conservando validaciones 18+.
- Checks: se conservan pendiente, enviado blanco y leído azul; `readAt` solo puede establecerlo el receptor. La duración opcional de nota se valida y queda inmutable al marcar lectura.

## Correcciones encontradas durante la fase

Se corrigió la interferencia del tooltip con el gesto de mantener presionado y la interacción entre el estado de grabación y los controles del chat. Se separaron los botones de perfil y chat en Matches. Se optimizó la evaluación recíproca de carreras para respetar el presupuesto de reglas, incluyendo cinco carreras en ambos usuarios.

La primera compilación Web reutilizaba un registrador de plugins anterior sin `record_web`: se invalidó únicamente `web_entrypoint.stamp` dentro de `.dart_tool/flutter_build` y se recompiló. Se verificó que el registrador final incluye RecordPluginWeb. No se borró build ni las exportaciones de datos. Los intentos anteriores a esta corrección no validan el micrófono físico.

## Pruebas finales

| Comprobación | Resultado | Registro |
| --- | --- | --- |
| flutter analyze --no-pub | Sin incidencias | audit-teacher-analyze-delivery.log |
| flutter test --no-pub | 241 aprobadas, 0 fallidas | audit-teacher-tests-delivery.log |
| Firestore y Storage en emuladores independientes | 148 aprobadas, 0 fallidas | audit-teacher-rules-delivery.log |
| Guardia, configuración y Auth demo; control de micrófono sintético | 10 aprobadas, 0 fallidas | audit-teacher-demo-delivery.log |
| Compilación Web demo final con plugin registrado | Correcta | audit-teacher-web-registered.log |
| Compilación Android debug | Correcta | audit-teacher-android-delivery.log |
| git diff --check | Sin errores de espacios | Comprobación final local |

Las pruebas nuevas cubren permisos y cancelación asíncrona, límite de captura, WAV, confirmación de envío, errores ambiguos, gesto de mantener/deslizar, preferencias antiguas y nuevas, catálogo, privacidad y galería del match, cierre/bloqueo de match y recibos de texto/imagen/audio. Los rechazos PERMISSION_DENIED en la suite son casos negativos esperados. Hubo fallos intermedios corregidos; la tabla corresponde a las ejecuciones finales.

La suite de reglas utiliza `firebase.teacher-rules.json`, proyecto `demo-tinder-phase2-rules`, Firestore 8188 y Storage 9298. No vació los emuladores del demo principal. Sus servicios se detuvieron al terminar; el demo principal sigue activo.

## Pruebas reales Web

Se verificó selección múltiple persistente, catálogo de 28 carreras y exclusión real de Carla al elegir solo Medicina. Al restaurar todas las carreras reapareció Carla con fotografía; se conservaron edad 18–40 y género Ambos. Se abrió el perfil público desde Matches y desde el encabezado del chat; evidencia de este último en `build/phase2-header-profile.png`.

En un modo explícito de pruebas, un tono sintético alimentó la API de captura: se grabó, escuchó la vista previa con progreso, confirmó el envío y reprodujo desde la cuenta receptora. La descarga autenticada confirmó WAV no vacío, mono 16 bits a 16 kHz, duración 8320 ms y 266284 bytes. Este ensayo valida el recorrido Web, no el dispositivo de micrófono. El modo solo se activa con `?syntheticMic=1` en el origen local exacto, muestra una advertencia visible y nunca solicita micrófono físico.

Ana envió una nota, texto «Fase 2: comprobación de lectura» y una PNG mediante selector real. Antes de abrir Bob, los tres carecían de readAt; después de abrir el chat receptor los tres tenían lectura y Ana mostró Visto. Se observó reproducción receptora con progreso 0:04/0:08. Evidencia: `audit-teacher-all-unread.log`, `audit-teacher-all-read.log`, `build/phase2-voice-received.png`. El estado pendiente se cubrió automáticamente; no se simuló desconexión real en navegador.

## Límites y pruebas manuales obligatorias

1. Micrófono físico Web: tras corregir el plugin, el navegador integrado quedó esperando permiso; el usuario confirmó que no apareció solicitud. Se canceló el intento; no se envió grabación física. Abrir Chrome/Edge externos, comprobar permiso de micrófono del sitio y privacidad de Windows, grabar voz, escuchar y descartar. Probar denegación, ausencia de dispositivo y dispositivo ocupado.
2. Android: compiló, pero no se ejecutó en dispositivo ni emulador Android. No se afirma captura o reproducción nativa comprobada. El APK normal usa el arranque normal del proyecto: no instalarlo ni ejecutarlo para estas pruebas aisladas. Primero debe prepararse y verificarse un arranque Android demo con endpoints adecuados; 127.0.0.1 del teléfono no es el equipo servidor.
3. Repetir mantener/soltar y deslizar con ratón y pantalla táctil, interrupción por otra app, 60 segundos, pérdida de red, reproducción repetida y búsqueda, tanto voz real como adjuntos. Probar galerías de varias fotografías y cambios de perfil con dos sesiones abiertas.
4. Los riesgos anteriores de URLs con token, contenido real frente a MIME y atomicidad/huérfanos entre Firestore y Storage siguen requiriendo protecciones de servidor descritas en `INFORME_RIESGOS_MULTIMEDIA.md`. La captura controlada y la limpieza del cliente reducen riesgo, pero no autentican a clientes manipulados ni garantizan transacciones entre servicios.
5. Antes de una futura integración, revisar conjuntamente reglas y proyecciones para usuarios existentes. No se desplegó ninguna regla ni migración a producción. No se implementaron carnet ni administración.

## Archivos de esta fase

- Audio: `lib/features/chat/voice_note_controller.dart`, `voice_note_recorder.dart`, `audio_playback.dart`, `chat_media_widget.dart`, `chat_message.dart`, `chat_service.dart`, `chat_screen.dart`; `android/app/src/main/AndroidManifest.xml`, `pubspec.yaml`, `pubspec.lock`.
- Perfil público: `lib/features/matches/match_profile_screen.dart`, `matches_screen.dart`, `lib/features/discovery/discovery_publication.dart`.
- Preferencias: `lib/features/preferences/discovery_preferences.dart`, `preferences_service.dart`, `preferences_screen.dart`, `lib/features/discovery/discovery_models.dart`.
- Reglas y tests: `firestore.rules`, `firebase.teacher-rules.json`, `tool/rules.test.mjs`, `test/voice_note_test.dart`, `teacher_phase2_test.dart`, `chat_receipts_test.dart`, `chat_media_test.dart`. Storage conserva las reglas existentes de la fase anterior.
- Demo: `tool/demo/migrate-phase2.mjs`, `phase2-evidence.mjs`, `synthetic-mic.js`, `bootstrap.js`, `browser.js`, `browser.test.mjs`, `seed.mjs`, `firestore.demo.rules`; este informe, guía manual, respaldo y evidencias locales. Los demás cambios que muestra Git pertenecen también a fases anteriores y se conservaron.

## Uso y recomendación

Demo: http://127.0.0.1:7357/__demo/start.html . Ana `ana.manual@demo.test`, Bob `bob.manual@demo.test`; contraseña sintética `DemoTinder2026!`. Usar navegadores separados o ventana normal/incógnito. Abrir Matches y chat. No añadir el parámetro syntheticMic para validar voz real.

Se verificaron de nuevo proyecto demo, CSP y listeners Auth 9099, Firestore 8088, Storage 9198 y Web 7357 ligados a 127.0.0.1. Estado SDK y bloqueos registrados en `audit-teacher-status-final.json`; los intentos de fuentes externas permanecieron bloqueados. El aislamiento corresponde al servidor y artefacto demo, no a toda la computadora. Datos previos exportados a `build/teacher-phase2-fixtures-before`; exportación posterior en `build/teacher-phase2-fixtures-after`.

Las funcionalidades están implementadas y las suites finales pasan. Recomiendo completar las pruebas físicas Web y Android antes de dar la fase por validada para integración.
