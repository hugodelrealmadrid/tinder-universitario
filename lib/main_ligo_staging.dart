import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/auth_service.dart';
import 'theme/app_theme.dart';
import 'staging_web_auth_stub.dart'
    if (dart.library.js_interop) 'staging_web_auth_web.dart';

/// Mismo código de producto; entrada local aislada, sin configuración real.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (!const bool.fromEnvironment('LIGO_STAGING') ||
        (kIsWeb
            ? Uri.base.host != '127.0.0.1' || Uri.base.port != 7465
            : defaultTargetPlatform != TargetPlatform.android ||
                  appFlavor != 'ligostaging') ||
        Firebase.apps.isNotEmpty) {
      throw StateError('Arranque de staging no autorizado.');
    }
    const options = FirebaseOptions(
      apiKey: 'AIzaSy000000000000000000000000000000000',
      appId: kIsWeb
          ? '1:1234567890:web:ligo-staging'
          : '1:1234567890:android:00000000000000000000000000000000',
      messagingSenderId: '1234567890',
      projectId: 'demo-ligo-staging',
      authDomain: '127.0.0.1',
      storageBucket: 'demo-ligo-staging.appspot.com',
    );
    if (kIsWeb) await initializeStagingWebAuth(options);
    final app = await Firebase.initializeApp(options: options);
    final auth = FirebaseAuth.instanceFor(app: app);
    if (!kIsWeb) {
      await auth.useAuthEmulator(
        '127.0.0.1',
        9399,
        automaticHostMapping: false,
      );
    }
    final db = FirebaseFirestore.instanceFor(app: app);
    db.settings = const Settings(persistenceEnabled: false);
    db.useFirestoreEmulator('127.0.0.1', 8288, automaticHostMapping: false);
    await FirebaseStorage.instanceFor(
      app: app,
    ).useStorageEmulator('127.0.0.1', 9498, automaticHostMapping: false);
    if (Firebase.apps.any((x) => x.options.projectId != 'demo-ligo-staging')) {
      throw StateError('Proyecto incorrecto.');
    }
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LIGO · staging funcional',
        theme: const bool.fromEnvironment('LIGO_20_PREVIEW')
            ? AppTheme.night
            : AppTheme.light,
        builder: (context, child) {
          final shell = Padding(
            padding: EdgeInsets.only(bottom: kIsWeb ? 22 : 0),
            child: Banner(
              message: 'STAGING LOCAL',
              location: BannerLocation.topEnd,
              child: child!,
            ),
          );
          return !kIsWeb && const bool.fromEnvironment('LIGO_20_PREVIEW')
              ? AnnotatedRegion<SystemUiOverlayStyle>(
                  value: AppTheme.nightSystemBars,
                  child: shell,
                )
              : shell;
        },
        home: AuthGate(
          service: AuthService(auth: auth, firestore: db),
        ),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'No se pudo iniciar el staging aislado. No se conectará a producción.',
            ),
          ),
        ),
      ),
    );
  }
}
