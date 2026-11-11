# Diagnóstico y corrección de notas silenciosas Web

19 de octubre de 2026. Solo `C:\Users\HP\Desktop\tinder_universitario_pruebas`. Se preservó el estado Git y se guardaron los archivos de audio previos en `build/voice-fix-before`, además de `audit-voice-preexisting.patch`. Sin commit, push, merge, reset ni deploy. Main, el proyecto original y Firebase producción no se modificaron.

## Actualización: entrada física activa y recorrido Web comprobado

Después del diagnóstico inicial, el usuario confirmó que Windows detecta su voz, que el micrófono quedó activado y que la prueba ya funciona correctamente. La página de diagnóstico muestra ahora `muted=false`, `enabled=true`, `AudioContext=running`, pico 0,8337 y RMS 0,03422. El usuario confirmó la escucha; el agente verificó los indicadores, sin sustituirlos por audio sintético. Evidencia `build/voice-physical-working.png`.

Se continuó con la entrada AMD explícita en Flutter Web, sin `syntheticMic`: medidor activo, captura de 10,752 segundos, escucha previa con avance hasta 0:08/0:10 y envío confirmado al chat local. La nota `PeTBscW1qlNh57mB3pYe`, enviada a las 14:17 hora Bolivia, tiene 344108 bytes, PCM16 mono 16000 Hz y MIME audio/wav; duración declarada y calculada coinciden, 170098 muestras son no nulas, pico 0,72586 y RMS 0,04472. Se descargó como Bob y se observó reproducción receptora hasta 0:10/0:10; Ana mostró Visto y Firestore contiene readAt. Evidencias: `audit-voice-physical-confirmed.log` y `build/voice-physical-bob.png`. La escucha humana confirmada corresponde a la prueba realizada por el usuario; el agente comprobó señal, formato, transporte, estados y avance del reproductor.

Esto cierra el diagnóstico inicial de silencio en este entorno Web. Continúan pendientes la matriz de Chrome/Edge, dispositivos alternativos y ejecución Android. El relato de fallo que sigue se conserva como evidencia anterior. Este cierre no cambió código Flutter ni reglas; se actualizaron informes y la herramienta de inspección para incluir el recibo de lectura.

Se exportó el estado actual de los emuladores a `build/voice-physical-fixtures`, exclusivamente local, para conservar la nota de prueba y los demás datos ante un reinicio. Registro `audit-voice-physical-export.log`. Los servicios principales se dejaron funcionando.

## Causa comprobada y alcance

La nota de la prueba manual guardada a las 13:23 (hora Bolivia), identificador `9bDYu9JHUudJeJzzhnnf`, contiene **exclusivamente ceros**: 456064 bytes, 14,251 segundos, PCM mono de 16 bits a 16000 Hz, MIME `audio/wav`, pico y RMS 0. La duración registrada coincide con los bytes PCM. Su contenedor es válido, pero no contiene voz recuperable. Aumentar volumen o cambiar reproductor no restaura audio que no se capturó.

La nota sintética anterior tiene muestras no nulas. Sirve como control técnico del formato y transporte, no como validación de micrófono físico. No se sustituyó la prueba física por ese control.

Se realizó una prueba independiente con `navigator.mediaDevices.getUserMedia({audio:true})`, Web Audio para medir entrada y MediaRecorder WebM/Opus para escucha local. No usa Flutter, record, Firebase, audio sintético ni persistencia. En esta computadora mostró la entrada física AMD, `live`, `enabled=true`, **`muted=true` de forma persistente**, `AudioContext=running`, pico aproximado 7,174e-10 y RMS 1,383e-10. Estos valores se cuantizan a ceros en PCM16. El usuario también confirmó el estado muted=true. Evidencia: `build/voice-physical-diagnostic.png`.

Según la [definición de MediaStreamTrack.muted](https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/muted), ese estado indica que la pista no está pudiendo entregar contenido multimedia. Es diferente de enabled=false. Se localizó el fallo observado en la entrada del navegador/sistema, antes del contenedor WAV y del almacenamiento. **No se ha determinado todavía si lo causa un control físico de silencio, la configuración de Windows, el controlador o el navegador integrado.** No se modificaron permisos globales ni controladores para intentar adivinarlo.

Además había un defecto de aplicación: se consideraba grabación correcta cualquier cantidad suficiente de PCM, aunque todas las muestras fueran cero, y no se mostraba señal ni se permitía escoger una entrada.

## Cambios

- Medición incremental de muestras PCM16, RMS, pico y nivel visual, sin retener una segunda copia del audio ni registrar muestras o identificadores de dispositivos. Maneja límites de chunks impares.
- Rechazo de grabaciones completamente silenciosas antes de crear borrador o habilitar envío. Mensaje para revisar entrada, volumen y silencio del micrófono. Las grabaciones muy bajas reciben advertencia y pueden escucharse; no se bloquea voz tenue por un umbral arbitrario.
- Si no llega ninguna muestra durante tres segundos, se detiene y explica el fallo en vez de mantener una falsa grabación.
- Selector de micrófono para distinguir predeterminado, comunicaciones y dispositivo físico explícito. La elección solo vive en esa pantalla; no se publica ni persiste.
- Inicialización Web: si el AudioContext de record_web aparece suspendido al iniciar, se solicita resume. El código de la dependencia instalada no lo hace automáticamente en startStream. Es una protección adicional; en el diagnóstico independiente el contexto ya estaba running, por lo que no se atribuye a esa suspensión el silencio comprobado.
- Se solicita procesamiento de voz disponible del navegador (ganancia automática, cancelación de eco y reducción de ruido). No se amplifica ni normaliza silencio para fingir señal.
- Se conserva WAV PCM16 mono 16 kHz y el MIME audio/wav, la escucha previa desde los mismos bytes, la confirmación explícita, el límite de 60 segundos, limpieza, servicio de subida y descarga autenticada y reglas existentes.
- No se cambió el reproductor compartido ni el envío de archivos de audio adjuntos. Revisión del reproductor instalado: volumen inicial 1, resume del contexto de salida al reproducir, carga por gesto del usuario y MIME explícito. No se encontró una causa de volumen/autoplay/blob que explique este archivo de ceros.
- Diagnóstico local opcional: `http://127.0.0.1:7357/_demo/mic-check.html`. Obtiene señal real, muestra estado y permite escuchar WebM/Opus en memoria. Se cierra el micrófono al detener, al salir o al llegar a 15 segundos. No envía el audio a ningún servicio.

## Pruebas finales

| Verificación | Resultado | Evidencia |
| --- | --- | --- |
| flutter analyze --no-pub | Sin incidencias | audit-voice-analyze-final.log |
| flutter test --no-pub | 246 aprobadas, 0 fallidas | audit-voice-tests-final.log |
| Firestore y Storage, emuladores independientes demo | 148 aprobadas, 0 fallidas | audit-voice-rules.log |
| Guardia, Auth y SDK del demo | 10 aprobadas, 0 fallidas | audit-voice-demo.log |
| Compilación Web demo final | Correcta | audit-voice-web-final.log |
| Sintaxis de herramientas y git diff --check | Correctas | Comprobación local |

Se añadieron pruebas de ceros PCM durante 14 segundos, volumen bajo, señal y chunks impares, configuración del capturador con entrada elegida y ausencia completa de muestras. Los fixtures de éxito anteriores ahora contienen señal, para que no vuelvan a aprobar una grabación muda. Los fallos intermedios fueron de infraestructura del test (creación del plugin sin mock y reloj monotónico frente a tiempo simulado); se corrigieron y repitió toda la suite.

La suite de reglas utilizó proyecto `demo-tinder-phase2-rules`, Firestore 8188 y Storage 9298, sin vaciar el demo principal. Esos emuladores de pruebas se detuvieron. Las reglas no cambiaron en esta corrección.

Se verificó de nuevo el SDK real del demo: proyecto `demo-tinder-universitario`, Auth 127.0.0.1:9099, Firestore 127.0.0.1:8088 y Storage 127.0.0.1:9198. Los listeners principales están en loopback y sigue la CSP/guardia que bloquea producción. Evidencia `audit-voice-status-final.json`. Datos y mensajes anteriores se conservaron, incluida la nota silenciosa de evidencia.

En el navegador con la compilación corregida se abrió el selector, se eligió «Microphone Array (AMD Audio Device)» explícitamente y se inició captura real. El silencio recibido fue rechazado con «No se detectó sonido», sin borrador ni nuevo envío. Evidencia `build/voice-silence-rejected.png`. La pestaña anterior con un borrador del usuario no se recargó ni se descartó.

## Prueba manual necesaria para cerrar el problema

1. En Windows abrir **Configuración → Sistema → Sonido → Entrada → Microphone Array (AMD Audio Device) → Probar micrófono**. Hablar y reproducir el resultado. Comprobar volumen de entrada y que el botón/tecla de silencio físico no esté activado. Si Windows tampoco recibe voz, resolver esa entrada o elegir un micrófono funcional antes de probar Flutter. [Instrucciones oficiales de Microsoft](https://support.microsoft.com/en-us/windows/hardware/drivers/how-to-set-up-and-test-microphones-in-windows).
2. Revisar acceso a micrófono para aplicaciones de escritorio en Configuración → Privacidad y seguridad → Micrófono. En Chrome/Edge permitir micrófono para el origen exacto `http://127.0.0.1:7357` y seleccionar el dispositivo que pasó la prueba de Windows. No habilitar acceso para sitios externos. [Ayuda Microsoft](https://support.microsoft.com/en-us/windows/hardware/drivers/fix-microphone-problems), [ayuda Chrome](https://support.google.com/chrome/answer/2693767?hl=es).
3. Abrir la página local de diagnóstico en Chrome/Edge externos; pulsar «Probar micrófono real», hablar y detener. La pista debe poder entregar audio y el medidor/pico/RMS deben subir con la voz. Pulsar reproducir y escuchar las palabras. Si Windows funciona y esta prueba no, el problema está en el navegador/permisos/entrada seleccionada. El diagnóstico no usa el plugin de Flutter.
4. Volver a `http://127.0.0.1:7357/__demo/start.html` (descartar antes cualquier borrador antiguo que se quiera perder). Ana `ana.manual@demo.test`, Bob `bob.manual@demo.test`, contraseña sintética `DemoTinder2026!`; usar navegadores separados. En el chat seleccionar el micrófono comprobado. Mantener presionado, hablar 5–10 segundos y soltar. El medidor debe reaccionar. Escuchar la vista previa, confirmar envío y escuchar desde Bob. No usar `?syntheticMic=1` para esta validación.
5. Repetir en Chrome y Edge: cancelar deslizando, descartar, denegar permiso, silencio y adjuntar un archivo de audio conocido. Una nota totalmente muda ya no debe poder enviarse. Si hay señal y avanza el reproductor pero no se oye, comprobar salida/altavoces, volumen de Windows y pestaña silenciada.

**Estado actual:** el usuario confirmó voz audible tras activar el micrófono; la captura física en Flutter, vista previa, envío, descarga y reproducción receptora se comprobaron técnicamente como se detalla al inicio. Se conserva la protección contra silencio. Android sigue sin ejecución y queda pendiente la matriz de navegadores/dispositivos.

## Archivos modificados en esta corrección

- `lib/features/chat/voice_note_controller.dart`
- `lib/features/chat/voice_note_recorder.dart`
- `lib/features/chat/voice_signal.dart` (nuevo)
- `test/voice_note_test.dart`
- `tool/demo/inspect-voice.mjs` (nuevo, solo lectura de metadatos/señal de notas canónicas en emuladores)
- `tool/demo/mic-check.html`, `tool/demo/mic-check.js` (nuevos)
- Este informe, actualización de guía manual, respaldo y evidencias locales. Los demás cambios Git preexistentes se conservaron.
