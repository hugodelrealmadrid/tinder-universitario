# Tinder Universitario: fases 1 a 5

Esta rama conserva vista previa, preferencias por edad y carrera, perfil público del
match, fotografías privadas, chat con fotografías y archivos de audio, notas de voz
con previa y checks de envío/lectura. Incluye verificación universitaria, roles
separados de la aprobación, suspensión, administración y auditoría.

La autorización depende del backend y de las reglas, no solo de las pantallas.
Las cuentas sin aprobación explícita quedan bloqueadas para citas. Los medios usan
referencias privadas; no restaurar URLs permanentes con token ni permisos anteriores.

## Preparación del demo local

Requiere Flutter/Dart compatibles con pubspec.yaml (validado con Flutter 3.44.4,
Dart 3.12.2), Node.js compatible con Firebase CLI, Java 21 y Android SDK para Android.
Desde la raíz, en Windows:

```powershell
flutter pub get
npm --prefix tool ci --ignore-scripts
powershell -NoProfile -File tool/setup-media-decoder.ps1
node tool/demo/prepare.mjs
flutter build web --target lib/main_demo.dart --output build/demo-web --no-web-resources-cdn --dart-define=TINDER_DEMO=true --dart-define=CHAT_STORAGE_ORIGIN=http://127.0.0.1:9198
```

prepare.mjs descarga SDK públicos estáticos y fuentes, sin consultar datos Firebase.
FFmpeg se descarga con checksum y conserva su licencia fuera de Git. No repetir la
preparación ni regenerar datos sobre el demo que ya está funcionando.

En terminales independientes, desde la raíz, con JAVA_HOME configurado y Java en PATH:

```powershell
node tool/node_modules/firebase-tools/lib/bin/firebase.js emulators:start --project demo-tinder-universitario --config firebase.demo.json --only auth,firestore,storage
node tool/backend/server.mjs
node tool/demo/server.mjs
```

Web: http://127.0.0.1:7357/; backend 7360, Auth 9099, Firestore 8088 y Storage 9198.
Todos escuchan exclusivamente en loopback. Para una instalación nueva y vacía,
consultar PRUEBAS_MANUALES_DEMO.md y los guards de tool/demo/seed.mjs. No ejecutar
seeds ni bootstrap sobre datos existentes. Para recuperar un demo, importar su
export privado al arrancar emuladores; no versionar bases de datos ni exportaciones.

## Validación sin alterar los datos del demo

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
$env:RULES_PROJECT='demo-tinder-phase3-tests'
$env:RULES_FIRESTORE_PORT='8188'
$env:RULES_STORAGE_PORT='9298'
$env:FIREBASE_EMULATORS_PATH=Join-Path $PWD 'tool/emulator-cache'
node tool/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --only auth,firestore,storage --project demo-tinder-phase3-tests --config firebase.phase3-tests.json "node --test --test-concurrency=1 tool/rules.test.mjs tool/phase3.test.mjs tool/phase5.test.mjs"
node --test tool/demo/*.test.mjs
```

Las suites Firebase limpian su proyecto: no ejecutarlas sin las tres variables de
pruebas. La suite demo comprueba fixtures del demo vivo: respaldar antes de usarla.
Para Android físico, seguir PRUEBAS_ANDROID_USB.md con flavor demo, target
lib/main_demo_android.dart y TINDER_DEMO=true; mantener aislamiento de red y USB.

## Límites de integración

Esta rama prepara integración local, no despliegue. El backend está limitado a
emuladores. Faltan backend/IAM/HTTPS de producción, migraciones reales revisadas,
revocación de tokens legacy, índices, firma release y políticas operativas/retención.
No publicar solo las reglas: bloquearía clientes y datos anteriores sin migración.
Consultar INFORME_PREINTEGRACION.md e INFORME_RAMA_INTEGRACION.md para el estado,
las pruebas recientes y los riesgos. Los informes anteriores son evidencia histórica.
