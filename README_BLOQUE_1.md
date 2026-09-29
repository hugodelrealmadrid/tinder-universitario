# Bloque 1 — Firebase Authentication y documento inicial

Se trabajó exclusivamente en C:\Users\HP\Desktop\tinder_universitario.

## Estado

Código implementado para Web y Android. No se ha vinculado un proyecto Firebase real: lib/firebase_options.dart es un marcador explícito que FlutterFire debe reemplazar. Hasta entonces la app muestra un error de configuración con opción de reintento; NO simula un login exitoso.

## Configuración pendiente

1. En Firebase Console, crea o selecciona TU proyecto.
2. Authentication → Sign-in method → Email/Password: habilita correo y contraseña.
3. Crea Cloud Firestore, base de datos `(default)`, seleccionando su región. En Rules, copia el contenido de `firestore.rules` y pulsa Publicar. Las reglas permiten solo creación y lectura del documento propio. La edición de perfiles queda para otro bloque.
4. Instala Node.js y Firebase CLI si no están instalados. En PowerShell:

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
# Reemplaza TU_PROJECT_ID por el ID real de Firebase.
flutterfire configure --project=TU_PROJECT_ID --platforms=android,web --out=lib/firebase_options.dart
```

Si `flutterfire` no está en PATH, usa:

```powershell
& "$env:LOCALAPPDATA\Pub\Cache\bin\flutterfire.bat" configure --project=TU_PROJECT_ID --platforms=android,web --out=lib/firebase_options.dart
```

Acepta reemplazar `lib/firebase_options.dart`. Android usa actualmente `com.example.tinder_universitario`; registra/selecciona la app con ese identificador. FlutterFire genera las opciones y los archivos nativos necesarios. No copies configuración de otro proyecto.

5. Authentication → Settings → Authorized domains: comprueba el dominio Web que usarás y agrega `localhost` para desarrollo si falta.
6. Las reglas también se pueden publicar mediante `firebase deploy --only firestore:rules --project=TU_PROJECT_ID` desde esta carpeta.
7. Ejecuta:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --web-port=7357
```

Para Android: `flutter devices` y luego `flutter run -d ID_DEL_DISPOSITIVO`. El manifest principal ya incluye permiso INTERNET. La compilación Android requiere Android SDK/JDK instalados.

Firebase Storage se utilizará en un bloque posterior; este bloque no sube imágenes, no necesita instalar su SDK ni activar Storage. No existe `profile_photos`.

Guía oficial: https://firebase.google.com/docs/flutter/setup

## Prueba exacta: REGISTRO → FIRESTORE → LOGOUT → LOGIN

1. Abre la app y pulsa Crear una cuenta. Usa un correo nuevo, contraseña de al menos 6 caracteres (o la política superior configurada en Firebase), confirmación y fecha de nacimiento con 18 años cumplidos.
2. Pulsa Crear cuenta. Debe aparecer loading y luego Sesión iniciada. El inicio solo se muestra después de confirmar el documento en Firestore.
3. En Firebase Console → Authentication → Users, copia el UID del correo registrado.
4. En Firestore → Data, comprueba `users/{ese UID}`: firstName='', lastName='', email, birthDate (Timestamp UTC de la fecha), gender='', description='', careerId=null, photoUrls=[], mainPhotoUrl=null, interestIds=[], role='user', isActive=false, createdAt y updatedAt (timestamps del servidor). No debe existir semestre ni una segunda carrera.
5. Recarga el navegador en la misma dirección y puerto o reinicia la app Android. Debe mantenerse la sesión. Se necesita conexión para confirmar el documento en Firestore; la persistencia de Auth no convierte el perfil en un flujo sin conexión.
6. Pulsa Cerrar sesión. Debe volver al login. Recarga: debe seguir en login.
7. Inicia sesión con el mismo correo y contraseña. Debe aparecer Sesión iniciada sin crear otro documento ni cambiar createdAt.
8. Comprueba una contraseña incorrecta, correo duplicado, campos vacíos, confirmación diferente y una fecha menor de 18 años: deben mostrar errores comprensibles.

## Recuperación y límites

Firebase Auth y Firestore son servicios separados, sin transacción conjunta. Si la cuenta se crea pero falla Firestore, la app mantiene al usuario en Completar registro, ofrece Reintentar y Cerrar sesión, y no permite entrar al inicio. La escritura usa una transacción para no sobrescribir un perfil existente. Si se cierra la app antes de crear el documento, el siguiente login pide otra vez la fecha de nacimiento; no es necesario volver a registrar el correo.

La edad se valida en formulario, servicio y reglas. Las reglas usan la fecha UTC del servidor; cerca de medianoche puede diferir del día local. La fecha es declarada por el usuario, no una verificación de identidad.

La persistencia Web usa LOCAL; Android conserva la sesión con Firebase Auth. No se guardan contraseñas en Firestore. Los roles previstos son user/admin/superadmin, pero el cliente solo puede crear user; no hay panel ni asignación de privilegios.

Pruebas locales: límites de edad (incluido 29 de febrero), traducción de errores, fecha obligatoria y pantalla de configuración ausente. No sustituyen una prueba de integración con tu proyecto ni una prueba de reglas con Emulator Suite. No se han desplegado reglas a una cuenta remota.

## Archivos

Creados: lib/firebase_options.dart; lib/features/auth/auth_service.dart; lib/features/auth/auth_gate.dart; lib/features/auth/auth_form.dart; lib/features/auth/login_screen.dart; lib/features/auth/register_screen.dart; lib/features/home/home_screen.dart; firestore.rules; firebase.json; test/auth_test.dart; README_BLOQUE_1.md.

Modificados directamente: lib/main.dart, pubspec.yaml, pubspec.lock, android/app/src/main/AndroidManifest.xml. Flutter puede actualizar registradores de plugins y metadatos generados al resolver dependencias.

No se implementaron funciones del Bloque 2 ni Sprint 2.

## Validación ejecutada

- `flutter pub get`: correcto.
- `flutter analyze`: No issues found.
- `flutter test`: 5 pruebas aprobadas.
- `flutter build web`: correcto, salida en build/web.
- El flujo real Auth/Firestore y las reglas publicadas quedan pendientes de configurar Firebase y ejecutar los pasos anteriores.
- `flutter build apk --debug`: correcto; APK en build/app/outputs/flutter-apk/app-debug.apk. Gradle instaló NDK 28.2.13676358 y CMake 3.22.1 requeridos por el entorno. Emitió avisos de compatibilidad futura Kotlin en plugins Firebase y tipos Java en Firestore; no impidieron compilar.
