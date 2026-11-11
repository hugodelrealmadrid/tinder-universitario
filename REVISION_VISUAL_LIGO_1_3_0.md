# LIGO 1.3.0 — segunda revisión visual

Implementada en `codex/ligo`, sin commits, push, publicación ni cambios remotos.

## Resultado visual
- Descubrir aprovecha la altura útil real: foto protagonista, nombre/edad/carrera/universidad superpuestos y botones circulares LIKE/PASAR próximos a la tarjeta. Escritorio usa hasta 1280 px con información lateral; móvil conserva la información sobre la foto. Se reutiliza el swipe existente y se añade entrada suave de cada tarjeta, respetando movimiento reducido.
- En ventanas bajas se puede desplazar la composición para acceder a todos los controles. Estados vacío, carga y perfil incompleto tienen presentación y acciones claras; el mensaje real del servicio no se oculta.
- Sidebar oscuro: 220 px abierto, 76 px contraído, grupos Comunidad/Moderación/Catálogos, estado activo, logo fijo, scroll propio y pie fijo con Configuración/Abrir aplicación. Drawer móvil compacto, selector de sección en la cabecera y transiciones sin desbordes al expandir. Se conserva exactamente la lista de secciones autorizadas.
- Navegación inferior de 68 px, coherencia de márgenes y botones, tooltips y nombres accesibles.

## Cuenta que mostraba perfil incompleto
Solo se consultó `demo-ligo-staging`. `ligo_root`, `ligo_admin` y `ligo_student` carecen de fotografías y foto principal y tienen `isActive=false`. Para usar Descubrir deben añadir una foto desde Perfil, elegirla como principal, guardar y activar visibilidad. Los intereses vacíos NO son un requisito pendiente obligatorio. El rol administrativo no impide citas; la integridad/visibilidad del perfil sí.

`ligo_visual_ana` y `ligo_visual_bob` están completos, aprobados y activos. Ya tienen likes mutuos y un match; el servicio los excluye de nuevas decisiones. No se borraron likes ni se reinició el descubrimiento para forzar una tarjeta. Se comprobó con login ficticio de Ana que la ficha de Bob y su fotografía privada responden 200; la fotografía sin sesión responde 401. Evidencia sin tokens: `live-profile-proof.json`.

Para revisar el caso completo sin alterar esos datos se usó el servicio real de Descubrir sobre Firestore ficticio **en memoria**, con perfil completo, catálogo, preferencias y fotografía ficticia. Las fotos del arnés se suministran al renderizador; en la app se conserva por defecto AppPhoto y su acceso privado existente. Las capturas NO prueban una nueva autorización de acceso.

## Validación
- `flutter analyze --no-pub`: sin problemas.
- `flutter test --no-pub --concurrency=2`: **351 aprobadas, 0 fallidas**; 16 casos nuevos de revisión.
- Perfiles completos/incompletos, navegación por todas las secciones, sidebar contraído/expandido, pie fijo al desplazar, drawer, roles restringidos, bloqueo y reintentos sin duplicar decisiones.
- Tamaños: 360×740, 390×844, 1280×600, 1440×900 y 1920×1080; adicionalmente 320×480, 1280×440, 700×390 con texto al 140 % y navegación inferior móvil.
- Web staging release recompilada con recursos Firebase locales. Ver resultado de build y comprobación HTTP final en `build/ligo-1.3-review2`.
- Backend y reglas NO se modificaron, por lo que no se repitieron sus baterías. No se compiló una nueva APK ni se probó Android físico en esta revisión.

Los fallos iniciales del arnés y las expectativas antiguas (ListTile, ancho máximo y textos) se corrigieron; las comprobaciones de privacidad, roles, bloqueos y decisiones siguen activas.

## Preservación y acceso
Se conserva el respaldo cifrado DPAPI previo en `build/ligo-1.3-review2/baseline/source.dpapi`, con hashes y verificación de recuperación en `verified.json`. Las 5 cuentas, 39 documentos y 2 archivos de staging conservaron el mismo digest de datos que antes: `8e120c1bbc2d83ed244ac320a83eb6e4c8cd1d81302cc27915955feaa539808e`. Solo se inició sesión de prueba; no se editaron perfiles, likes, matches ni objetos. Backend, reglas, roles y permisos coinciden byte a byte con el respaldo previo a esta revisión.

Staging: http://127.0.0.1:7465/ . Recargar con Ctrl+F5 tras el build. Cuenta administrativa ficticia: `ligo_root@ligo.test`; clave exclusivamente local `Ligo-staging-2026!`. Ana: `ligo_visual_ana@ligo.test`, misma clave. Producción, showcase y demo anterior intactos; ningún despliegue remoto.

## Capturas y archivos
Galería: `build/ligo-1.3-review2/COMPARATIVA.html`. Directorios `before` y `after`, con comparaciones del mismo viewport y fixture. Las capturas se revisaron visualmente además de comprobar ausencia de errores de layout.

Archivos modificados respecto del respaldo de esta revisión:

- `lib/features/discovery/discovery_screen.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/verification/admin_visual.dart`
- `lib/widgets/photo_story.dart`
- `test/final_redesign_test.dart`
- `test/ligo13_navigation_security_test.dart`
- `test/ligo13_visual_revision_test.dart`
- `test/matches_test.dart`
- `test/safety_test.dart`
- `test/ui_redesign_test.dart`
- Este informe.
