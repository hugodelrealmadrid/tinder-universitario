# Rediseño visual de Tinder Universitario

## 1. Objetivo

Modernizar la presentación de la aplicación Flutter existente, con prioridad móvil,
sin cambiar los Sprints 1–3, la arquitectura ni el backend Firebase.
Proyecto: `C:\Users\HP\Desktop\tinder_universitario`.

## 2. Archivos creados

- `lib/theme/app_theme.dart`
- `lib/widgets/app_ui.dart`
- `test/ui_redesign_test.dart`
- `README_REDISENO_UI.md`

## 3. Archivos modificados

- `lib/main.dart`: aplica el tema; inicio Firebase intacto.
- `lib/features/auth/auth_form.dart`: presentación compartida de Login/Registro.
- `lib/features/home/home_screen.dart`: portada e iconos de navegación.
- `lib/features/discovery/discovery_screen.dart`: tarjeta, acciones fijas y estados.
- `lib/features/matches/matches_screen.dart`: tarjetas y estado vacío.
- `lib/features/chat/chat_screen.dart`: avatar, burbujas, composición y diálogo Unmatch.
- `lib/features/profile/profile_screen.dart`: resumen, secciones, fotos y feedback.
- `lib/features/preferences/preferences_screen.dart`: jerarquía, secciones y feedback.
- `lib/features/safety/safety_dialog.dart`: iconos y colores de confirmación.
- `test/discovery_test.dart`: desplazamiento hasta Guardar preferencias antes de pulsar.

## 4. Componentes reutilizables

`AppTheme` / `AppColors`: tipografía, paleta, superficies, controles, chips,
diálogos, AppBars, SnackBars y navegación. Sin nuevas dependencias.

`AppMark`: marca propia con birrete Material dentro de un degradado coral/naranja.
No usa logos, código ni assets propietarios de Tinder.

`AppPhoto`: imagen con BoxFit.cover, carga, imagen ausente, error y semántica.
`SectionHeading`: secciones con icono, título y subtítulo opcional.
`AppNotice`: avisos y errores legibles, con icono y liveRegion.
`AppEmptyState`: estados vacíos con iconografía y explicación.

## 5. Pantallas rediseñadas

- Login y Registro: tarjeta sobre fondo suave, marca, título, inputs con iconos,
  botones y enlaces. Se mantiene mostrar/ocultar contraseña ya existente.
- Inicio: presentación universitaria y acceso a los mismos destinos.
- Discovery: fotografía grande, degradado, nombre/edad/carrera/intereses superpuestos,
  descripción completa debajo y menú de seguridad. LIKE/PASS circulares se mantienen
  visibles en una franja inferior independiente del desplazamiento del contenido.
- Matches: foto, nombre/edad, carrera y acceso visual a chat; estado vacío explicado.
- Chat: avatar, burbujas coral/blancas, esquinas diferenciadas, timestamps discretos,
  campo y botón circular, aviso de match finalizado.
- Perfil: resumen de los datos guardados con foto, nombre/edad, carrera, descripción
  e intereses. Editar perfil desplaza al formulario existente, sin crear otra ruta.
- Edición: secciones Tus datos, Sobre ti, Intereses, Fotografías y Visibilidad.
- Fotos: cuadrícula de dos columnas en móvil y tres desde 540 px de contenido,
  distintivo Principal, placeholders, acciones y progreso junto a las fotografías.
- Preferencias: secciones Género de interés y Rango de edad; mismos selectores 18–100.
- Unmatch/Bloquear/Reportar: iconografía, estilos destructivos y tema compartido.

AuthGate conserva su navegación; sus formularios de recuperación usan AuthCard y el tema.

## 6. Decisiones visuales

Fondos claros, superficies blancas, texto oscuro, coral como acento principal y verde
para LIKE. Rojo identifica acciones destructivas; azul, información. Color acompañado
de texto/iconos. Bordes redondeados, sombras discretas y controles táctiles amplios.

Anchos máximos: Auth 460, Discovery 520, Matches 640, Perfil 680 y Chat 720 px.
Formularios y contenido largo pueden desplazarse; no se limita ni oculta la descripción.
Las imágenes mantienen proporción mediante recorte cover, sin deformación.

Se conservan los cuatro destinos existentes: Inicio, Descubrir, Matches y Perfil.
No se añadió otra navegación. Se resaltan destino seleccionado e icono activo.

## 7. Lógica preservada

Servicios, modelos, consultas, IDs, colecciones, reglas, índices y configuración Firebase
no se modificaron. Tampoco AuthGate, persistencia de sesión ni publicación de fichas.
El cálculo de edad mostrado en el resumen reutiliza `ageOn`; no escribe ningún dato.

Se mantienen todos los callbacks de registro/login/logout, validaciones de edad/género,
una sola carrera, intereses, activación, recuperación Android de fotos, subida/borrado,
preferencias, LIKE/PASS, match recíproco, chat realtime, historial, Unmatch, bloqueo y reporte.
El botón Editar solo desplaza la vista. La franja de acciones solo cambia su posición.

No se implementaron swipe gestual, correo institucional, otro rango de edad, nuevas
historias, notificaciones, panel administrativo, IA, geolocalización ni pagos.

## 8. Tests y revisión visual

Se conservan los 128 tests anteriores y se agregan 16 en `ui_redesign_test.dart`:

- Login/Registro a 360 px, validación y teclado.
- Discovery a 360×800, 390×844, 412×915 y 1280×900; LIKE y ancho máximo.
- Ficha con carrera larga, cinco intereses y escala de texto 1.5.
- Inicio y Discovery con navegación inferior y acciones visibles a 360 px.
- Matches abre chat; Chat con historial, teclado y cancelar Unmatch.
- Perfil: resumen, edición, selección de interés y guardado.
- Preferencias: mantiene 18–100 y validación.
- Seis fotos: cuadrícula, cambiar principal y cancelar eliminación.
- Bloquear/Reportar con tema a 360 px y cancelación.
- Imagen ausente/error sin alterar dimensiones.

Solo se ajustó un test anterior: `ensureVisible` antes de pulsar Guardar preferencias,
ahora situado después de las nuevas secciones. Conserva todas sus aserciones funcionales.
No se eliminaron ni deshabilitaron tests.

Se revisaron capturas de Login, Registro, Inicio, Discovery móvil/Web, Matches, Chat,
Perfil, edición, fotos, Preferencias y los tres diálogos. Usan datos ficticios, fuentes
del SDK e imágenes ausentes/fallidas; no hubo sesiones ni datos reales de Firebase.
Las capturas son temporales y no forman parte del código de producción.

Comandos:

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
flutter pub get
flutter analyze
flutter test
flutter build web
$env:GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dorg.gradle.jvmargs=-Xmx2048m'
flutter build apk --debug
git diff --check
```

Capturas opcionales, indicando rutas locales de salida/fuentes:

```powershell
flutter test test/ui_redesign_test.dart --dart-define=UI_CAPTURE_DIR=C:/Users/HP/AppData/Local/Temp/tinder-ui-review --dart-define=UI_FONT_DIR=C:/dev/flutter/bin/cache/artifacts/material_fonts
```

## 9–13. Resultados

| Comprobación | Resultado |
| --- | --- |
| flutter pub get | Correcto; sin cambios de dependencias |
| flutter analyze | No issues found |
| flutter test | 144/144; 128 anteriores + 16 nuevos |
| Build Web | Correcto: `build/web` (70,3 s) |
| Build Android debug | Correcto: `build/app/outputs/flutter-apk/app-debug.apk` (74,1 s) |
| git diff --check | Correcto |

## 14. Limitaciones conocidas

La revisión móvil es mediante widget tests y capturas, no un dispositivo físico.
Queda comprobar teclado/galería Android reales y fotografías de Storage con cuentas de prueba.
No se realizó QA remoto ni un APK release firmado.

El resumen de perfil muestra los últimos datos guardados; el formulario mantiene su borrador
hasta Guardar perfil, igual que antes. Con contenido extenso se desplaza la página.
No se añadió navegación gestual ni carrusel fotográfico.

`pub get` informa 12 versiones más nuevas fuera de las restricciones actuales y el SDK
ofrece actualizar Flutter. No se actualizaron SDK ni dependencias en este bloque.
Android informa que firebase_auth, firebase_core y firebase_storage usan Kotlin Gradle
Plugin y necesitarán actualización para versiones futuras de Flutter. El build actual
terminó correctamente. Web informa dry run Wasm correcto y reducción de fuentes.
Git puede avisar de conversión LF→CRLF sin errores de whitespace.
Las suites de Rules y herramientas no se reejecutaron: no se modificaron sus archivos
ni ninguna capa de backend. Los resultados de bloques anteriores no se presentan como nuevos.

## 15. Comprobación manual recomendada

1. Abrir Web y Android con cuentas de prueba autorizadas; comprobar Login, Registro,
   validaciones, mostrar contraseña, logout y sesión restaurada.
2. Revisar Inicio y los cuatro destinos; abrir Preferencias y volver. Probar Back Android.
3. En Perfil revisar resumen, Editar, campos, fecha, género, única carrera, chips,
   guardar parcial/completo y activar/desactivar con las validaciones habituales.
4. Subir fotos reales, observar progreso, cambiar principal, cancelar/confirmar eliminación;
   comprobar error de red y recuperación de la galería. No borrar datos para reiniciar pruebas.
5. Preferencias: seleccionar género y edades, probar mínimo mayor que máximo y guardar.
6. Discovery: foto vertical/horizontal, carga/error, descripción extensa y cinco intereses;
   acciones visibles, PASS/LIKE una vez, match recíproco, vacío/error y reintento.
7. Matches: abrir chat, volver, conservar solo activos. Chat: mensajes en ambos sentidos,
   teclado, texto multilínea, límite, conexión interrumpida y nuevo mensaje realtime.
8. Probar Cancelar en Unmatch/Bloquear/Reportar. Con parejas destinadas a QA, comprobar
   confirmaciones y consecuencias existentes, sin usar cuentas/datos que deban conservarse intactos.
9. Revisar 360×800, 390×844, 412×915 y escritorio; escalado de texto y navegación por teclado.

**Sin deploy, commit, push, seeds, borrado de datos ni operaciones sobre Firebase real.**
