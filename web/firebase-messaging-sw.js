/* Configuración pública del proyecto inyectada solo en un entorno FCM autorizado. */
importScripts('/firebase-messaging-config.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
if (!self.LIGO_FIREBASE_WEB_CONFIG?.projectId ||
    self.LIGO_FIREBASE_WEB_CONFIG.projectId.startsWith('demo-')) {
  throw new Error('FCM requiere un proyecto configurado explícitamente.');
}
firebase.initializeApp(self.LIGO_FIREBASE_WEB_CONFIG);
// FCM presenta la notificación genérica y aplica fcmOptions.link al pulsarla.
// Evitar showNotification aquí para no duplicar el aviso.
firebase.messaging();
