# LIGO 2.0 · Notificaciones

## Staging

La Web y Android debug de esta fase usan `LIGO_NOTIFICATIONS=true`, los emuladores de LIGO y el servidor local `node tool/ligo/server.mjs --notifications`. El listener local observa mensajes, recibos, matches y solicitudes recientes en Firestore. En un reinicio recupera diez minutos de eventos. Firebase Emulator Suite no emula FCM, por eso las alertas del sistema permanecen deshabilitadas en las compilaciones locales y el transporte se prueba con un doble. La bandeja y su contador sí usan Firebase local.

## Configuración necesaria para FCM real

1. Elegir un entorno Firebase y un origen HTTPS autorizados. Activar FCM HTTP v1 y registrar la app Android y Web de ese mismo proyecto. Compilar los clientes con `LIGO_NOTIFICATIONS=true` y `LIGO_FCM=true`.
2. En Web, configurar la clave VAPID **pública** como `LIGO_WEB_VAPID`. Servir `/firebase-messaging-config.js` con `self.LIGO_FIREBASE_WEB_CONFIG = {apiKey, appId, projectId, messagingSenderId, authDomain, storageBucket}` y el worker `/firebase-messaging-sw.js` desde ese origen. La configuración debe coincidir con FlutterFire. Permitir el worker local y los orígenes específicos de Firebase Messaging e Installations en la CSP del entorno. El worker deja que FCM presente el aviso para que no haya un segundo aviso manual. [FCM para Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) · [Recepción Web](https://firebase.google.com/docs/cloud-messaging/web/receive-messages)
3. Mantener el API público autenticado de siempre y habilitar `LIGO_NOTIFICATIONS_ENABLED=true` en su configuración. Ejecutar `backend/hosted-notifications.mjs` como un **servicio privado de Cloud Run** con los parámetros Firebase del backend y `LIGO_NOTIFICATION_WEB_ORIGIN`. No conceder invocación a `allUsers` ni a `allAuthenticatedUsers`. Solo la cuenta de Eventarc debe poder invocar ese worker. La identidad del worker necesita Firestore y envío de FCM mediante ADC, sin claves descargadas.
4. Configurar Eventarc en la ubicación compatible con la base, con destino al worker privado `/events` y tipo de datos `application/protobuf`. Usar `written` para `matches/{match}/messages/{message}`, `created` para `matches/{match}` y `written` para `verificationRequests/{request}`. El worker reconsulta el documento y comprueba participantes, bloqueo, suspensión, verificación y solicitud vigente. [Eventarc para Firestore](https://docs.cloud.google.com/eventarc/standard/docs/run/route-trigger-cloud-firestore)
5. Configurar TTL en `notificationDevices.expiresAt` y `notificationPushClaims.expiresAt`. Los tokens se guardan solo en el backend, se eliminan al recibir respuestas de FCM que confirman invalidez y el cierre de sesión intenta retirar el dispositivo. La preferencia de la cuenta es opt-in y se puede registrar más de un dispositivo.
6. Validar en un navegador con permisos concedidos y denegados, y en Android físico. Probar primer plano, segundo plano y apertura desde app terminada. El cierre forzado de Android y las políticas del navegador pueden impedir la entrega. [Recepción Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)

## Entrega y privacidad

Firestore es la fuente de verdad. La inserción del aviso y el contador son atómicos. Cada aviso usa una clave estable. La lectura desde el buzón y los recibos de chat decrementan el contador una sola vez. Push envía un aviso genérico y un identificador opaco. La aplicación consulta el buzón autenticado al pulsarlo, sin confiar en la carga del push para decidir a qué conversación se puede entrar.

Para evitar duplicados, el servidor reclama un intento de push por destinatario y evento antes de enviar. Si FCM o el worker fallan después de reclamarlo, el aviso puede quedar solamente en la bandeja. La bandeja conserva su propia recuperación mediante reintentos del evento. No se registra el texto del chat, el contenido del carnet ni el token del dispositivo en los logs.

## Validación física Android preparada · 8 de noviembre de 2026

La APK RC inspeccionada declara `POST_NOTIFICATIONS` y usa `com.example.tinder_universitario.ligostaging` con target SDK 36. El teléfono conectado tiene Google Play Services. La APK inicia Firebase con opciones ficticias de `demo-ligo-staging` y usa Auth, Firestore y Storage en loopback. Además, `canPush` deshabilita FCM en proyectos cuyo ID comienza por `demo-`. Cambiar únicamente `LIGO_FCM` deja el bloqueo vigente. Se conservan la bandeja y los contadores locales.

### Qué implementa hoy el código

| Caso | Implementación revisada | Evidencia disponible |
| --- | --- | --- |
| Primer plano | `onMessage` consulta el aviso autenticado y el listener de Firestore comparte la deduplicación por ID. Presentación en la app. | Prueba Flutter de la bandeja y contador. FCM físico pendiente. |
| Segundo plano y pulsación | FCM presenta el payload `notification` en Android. `onMessageOpenedApp` recibe el ID opaco. | Carga genérica verificada con transporte doble. Entrega física pendiente. |
| Proceso terminado y pulsación | `getInitialMessage()` se consulta al montar la sesión. La app vuelve a verificar el destinatario, el match y el acceso antes de navegar. | Revisión de código. Arranque frío por push pendiente. |
| Permiso | Solicitud explícita al activar el dispositivo y registro solo si se concede. | Permiso incluido en la APK. Diálogo real pendiente. |
| Renovación | `onTokenRefresh` revisa sesión y preferencia, registra el token nuevo y solicita retirar el anterior conocido en memoria. | El backend retira tokens inválidos o vencidos. Rotación real y cierre simultáneo pendientes. |
| Cierre de sesión | El cierre explícito llama al backend para retirar el token conocido e intenta `deleteToken()` antes de salir. | El backend protege la eliminación por propietario. Revocación efectiva en el teléfono pendiente. |
| Varios dispositivos | Registros separados por hash del token y preferencia de push compartida por cuenta. | Dos registros destinatarios, rechazo de baja ajena y descarte de tokens inválidos y vencidos comprobados con doble. |

### Activación futura, solo con autorización

1. Seleccionar un **proyecto Firebase online dedicado a esta prueba**, distinto de producción, del showcase y de los demos locales. Confirmar el ID y los permisos antes de crear recursos. Registrar Android con el paquete **`com.example.tinder_universitario.development`** y colocar el `google-services.json` de ese proyecto en `android/app/src/development/google-services.json`. Comprobar que el cliente de ese paquete, el ID del proyecto, el número de remitente y el App ID coincidan. Habilitar FCM HTTP v1. [Configuración FCM para Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
2. Preparar Auth, Firestore y Storage de ese mismo proyecto, con las reglas actuales y únicamente cuentas ficticias nuevas, verificadas, aprobadas y con un match activo. Habilitar el API HTTPS autenticado con `LIGO_NOTIFICATIONS_ENABLED=true`. Usar un origen HTTPS del entorno de prueba en `TINDER_WEB_ORIGINS` y `LIGO_NOTIFICATION_WEB_ORIGIN`. Para Android no se requiere configurar VAPID ni publicar la Web.
3. Configurar el worker `node backend/hosted-notifications.mjs` en Cloud Run con IAM privado. El worker y el API usan `APP_ENV=development`, `TINDER_PROJECT_ID`, `GOOGLE_CLOUD_PROJECT` y `TINDER_STORAGE_BUCKET` del proyecto aislado. Dar al worker lectura/escritura Firestore para bandeja, dispositivos y reclamos, y permiso `cloudmessaging.messages.create` vía identidad de servicio ADC. Dar a la identidad del trigger `roles/eventarc.eventReceiver` y `roles/run.invoker` sobre ese worker. Crear primero el trigger de mensajes `google.cloud.firestore.document.v1.written`, filtro `database=(default)`, patrón `matches/{match}/messages/{message}`, destino `/events` y formato `application/protobuf`, en la ubicación compatible con Firestore. Para ampliar el ensayo a matches y acreditaciones, añadir los triggers del apartado anterior. [Triggers de Firestore](https://docs.cloud.google.com/run/docs/triggering/firestore-triggers) · [Permisos Eventarc](https://docs.cloud.google.com/eventarc/docs/roles-permissions) · [Permisos FCM](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasecloudmessaging)
4. Crear un archivo local de configuración pública, fuera de Git, con `APP_ENV=development`, `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET`, `FIREBASE_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_AUTH_DOMAIN` y `VERIFICATION_BACKEND_URL` HTTPS con barra final. Compilar y verificar antes de instalar por USB.

   ```powershell
   flutter build apk --debug --flavor development --target lib/main.dart --dart-define-from-file=deploy/fcm-qa.local.json --dart-define=LIGO_NOTIFICATIONS=true --dart-define=LIGO_FCM=true --dart-define=LIGO_20_PREVIEW=true
   adb -s SERIAL install -r build/app/outputs/flutter-apk/app-development-debug.apk
   ```

   Comprobar que el paquete sea `.development`, que el proyecto nativo y los defines apunten al mismo entorno aislado y que el backend HTTPS esté autorizado. Mantener Internet activo en Android. Esta variante usa servicios online y no necesita `adb reverse`. Si se ensayan respuestas a historias, añadir `LIGO_STORIES=true` y habilitar `LIGO_STORIES_ENABLED=true` solo en ese API de prueba.
5. Entrar con la cuenta receptora ficticia. En la bandeja, activar alertas y conceder el permiso. Enviar desde la otra cuenta ficticia un mensaje nuevo por cada caso. Comprobar primero un solo aviso dentro de la app en primer plano. Después, enviar con la app en segundo plano y con el proceso terminado normalmente, pulsar cada aviso y comprobar el chat correcto. Hacer una prueba separada tras forzar la detención desde Ajustes. Android puede bloquear la entrega hasta volver a abrir la app. Verificar el texto genérico en pantalla bloqueada, sin nombres, texto del chat ni imágenes. [Estados y pulsaciones FCM](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
6. Repetir con el permiso denegado y comprobar que la bandeja funciona. Registrar la misma cuenta en dos teléfonos o en un teléfono y un AVD con Google APIs. Verificar ambos envíos, salir de uno y comprobar que el otro conserva la entrega. Probar cambio de cuenta y renovación en una instalación desechable, verificando el reemplazo desde el backend sin mostrar tokens. Comprobar bloqueo, suspensión y un reintento del mismo evento. Una respuesta a historia debe dejar un solo aviso específico en la bandeja. Al finalizar, desactivar el push de las cuentas de prueba, cerrar sesión y retirar los recursos temporales según la autorización.

### Riesgos que requieren la prueba física

- La baja del token tiene plazos cortos y es de mejor esfuerzo. Si falla la red o se cierra la app antes de cargar el token en memoria, el registro antiguo puede seguir disponible hasta que FCM lo invalide o caduque. Una renovación o un envío en curso durante el logout también merece prueba explícita.
- La preferencia es global por cuenta. Desactivar el switch corta el envío a todos los dispositivos, mientras que el logout intenta retirar solo la instalación actual.
- El reclamo de envío se guarda antes de llamar a FCM. Una falla transitoria posterior puede dejar el aviso únicamente en la bandeja. FCM, la conectividad y las restricciones de batería pueden afectar tiempos y entrega.
- La implementación actual usa avisos del sistema en segundo plano y un aviso interno en primer plano. No se requiere un handler de datos en segundo plano para este payload, ya que la bandeja se escribe en el servidor. Un payload exclusivamente de datos sería un alcance distinto.

### Pruebas ejecutadas

- `flutter test --no-pub test/notifications_screen_test.dart` · 2 aprobadas.
- `LIGO_TEST_PORT_OFFSET=200` y `node tool/ligo/staging.mjs notifications` · 3 aprobadas en `demo-ligo-validation`, con transporte FCM doble.
- ADB confirmó el teléfono físico, Play Services y el permiso presente en el manifiesto del RC. La entrega FCM real, el permiso en tiempo de ejecución y el arranque desde un push no fueron ejecutados. No se enviaron notificaciones ni se crearon servicios remotos.

## Cierre de LIGO 2.0 sin push externo

La bandeja interna es el alcance de esta entrega. Conserva mensajes, matches, acreditaciones y respuestas a historias, sus contadores de no leídos y la navegación autenticada. Al volver a abrir LIGO, Firestore vuelve a cargar los avisos pendientes y sus contadores. La primera carga evita repetir como avisos emergentes las notificaciones que ya estaban en la bandeja.

Staging se compila con `LIGO_NOTIFICATIONS=true` y `LIGO_FCM=false`. La comprobación del ID `demo-*` también bloquea el uso del SDK de Messaging aunque se active por error el flag, y Android conserva desactivada la inicialización automática de FCM. El código y el procedimiento de FCM se preservan para más adelante. Las notificaciones del sistema con la aplicación cerrada quedan pendientes.

Para probar el regreso, salir de la pestaña o cerrar la app de staging, enviar un mensaje entre Alma y Bruno y volver. Abrir la campana, comprobar que el aviso esté sin leer y pulsarlo para verificar la conversación. En Android físico conservar el USB y los túneles de 9399, 8288, 9498 y 7466.

Verificación local de cierre: 3 pruebas Flutter de bandeja y 3 pruebas de backend en emuladores secundarios. Chrome recuperó un mensaje enviado mientras la página estaba cerrada y abrió el chat correcto. Las capturas y los resultados de Android se guardan en `build/ligo-notificaciones-cierre/`.

**Cierre en Android físico.** El contador aparecía pero la bandeja podía quedarse cargando al compartir la suscripción del listener global. La pantalla ahora abre su propia suscripción y obtiene el estado inicial. Las 3 pruebas Flutter volvieron a pasar. Con la APK corregida instalada en Android 14, Alma recuperó el aviso pendiente de Bruno, abrió el chat desde el aviso y se confirmó el cambio a leído en Firestore. Capturas en `build/ligo-notificaciones-cierre/`.
