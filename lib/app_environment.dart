import 'package:firebase_core/firebase_core.dart';

/// Configuración pública de compilación. Ningún valor autoriza operaciones.
class AppEnvironment {
  const AppEnvironment({
    this.demoFlag = false,
    required this.name,
    required this.projectId,
    required this.bucket,
    required this.apiKey,
    required this.appId,
    required this.senderId,
    required this.authDomain,
    required this.backend,
  });
  final bool demoFlag;
  final String name,
      projectId,
      bucket,
      apiKey,
      appId,
      senderId,
      authDomain,
      backend;

  factory AppEnvironment.configured({required bool web}) => AppEnvironment(
    demoFlag: const bool.fromEnvironment('TINDER_DEMO'),
    name: const String.fromEnvironment('APP_ENV'),
    projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    bucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
    appId: web
        ? const String.fromEnvironment('FIREBASE_WEB_APP_ID')
        : const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
    senderId: const String.fromEnvironment('FIREBASE_SENDER_ID'),
    authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    backend: const String.fromEnvironment('VERIFICATION_BACKEND_URL'),
  );

  void validate() {
    final uri = Uri.tryParse(backend);
    if (demoFlag ||
        !['development', 'production'].contains(name) ||
        !RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(projectId) ||
        projectId.startsWith('demo-') ||
        bucket.isEmpty ||
        !RegExp(r'^AIza[0-9A-Za-z_-]{35}$').hasMatch(apiKey) ||
        !appId.startsWith('1:$senderId:') ||
        senderId.isEmpty ||
        !RegExp(r'^[a-z0-9.-]+$').hasMatch(authDomain) ||
        uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host.endsWith('.example') ||
        uri.path != '/') {
      throw StateError('Completa la configuración del entorno alojado.');
    }
  }

  FirebaseOptions get options {
    validate();
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      storageBucket: bucket,
      authDomain: authDomain,
    );
  }
}
