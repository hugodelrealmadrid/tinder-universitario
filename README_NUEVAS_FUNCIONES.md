# Vista previa y chat multimedia

- Mi perfil: botón «Vista previa de mi perfil», con nombre, edad, carrera, descripción, intereses y galería. Muestra el formulario actual; guardar sigue siendo necesario para publicar los cambios. Omite email, apellido y fecha de nacimiento en la vista previa pública.
- Chat: doble check blanco para mensajes enviados y azul cuando el destinatario abre el chat y el mensaje se construye en la lista visible. Los mensajes pendientes muestran un reloj. La lectura se almacena en Firestore y se actualiza en tiempo real. Se evita marcar durante pausa o cuando hay otra ruta encima.
- Imágenes: selección de galería, JPG/PNG/WebP hasta 5 MB, miniatura y ampliación con zoom.
- Audio: adjuntar archivos MP3/M4A/WAV/OGG hasta 15 MB y reproducir/pausar en la conversación. Esta versión permite adjuntar audio existente; no incluye grabación con micrófono.
- Las reglas permiten archivos únicamente a participantes y carga únicamente en matches activos sin bloqueos. Solo el destinatario puede agregar `readAt`, sin modificar el mensaje.

## Instalación y comprobación

Se agregaron `file_picker` y `audioplayers`. Ejecutar desde la carpeta del proyecto:

```sh
flutter pub get
dart format lib test/chat_receipts_test.dart
flutter analyze
flutter test
firebase deploy --only firestore:rules,storage
```

El primer comando actualiza `pubspec.lock`. Para las reglas de Storage con consultas a Firestore, Firebase puede solicitar habilitar los permisos de integración entre ambos servicios.

En dos dispositivos/cuentas con match activo: enviar texto, imagen y audio; comprobar checks blancos antes de abrir el chat receptor y azules después; probar pausa/reproducción, ampliación de imagen, cancelar selección y errores de red. Verificar que un tercero no puede leer archivos ni modificar recibos, y que un match cerrado o bloqueado no admite nuevas cargas.

## Validación realizada

Se revisaron los cambios y pasaron las cuatro pruebas Node del CLI de catálogos existente. Se agregaron pruebas Flutter para persistencia del visto, compatibilidad de mensajes antiguos y color del indicador. Actualización: se instaló Flutter 3.47.7 y pasaron las 173 pruebas Flutter del proyecto. El SDK se configuró para VS Code en este equipo. Las reglas Firebase todavía necesitan validación con emuladores y despliegue; no se modificó el proyecto remoto.

