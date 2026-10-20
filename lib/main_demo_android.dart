import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/auth_service.dart';
import 'theme/app_theme.dart';

/// Solo flavor demo + adb reverse de los cuatro puertos. Sin opciones reales.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb ||
      !const bool.fromEnvironment('TINDER_DEMO') ||
      appFlavor != 'demo') {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Se requiere Android flavor demo y TINDER_DEMO=true.'),
          ),
        ),
      ),
    );
    return;
  }
  final app = await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSy000000000000000000000000000000000',
      appId: '1:1234567890:android:00000000000000000000000000000000',
      messagingSenderId: '1234567890',
      projectId: 'demo-tinder-universitario',
      storageBucket: 'demo-tinder-universitario.appspot.com',
    ),
  );
  if (Firebase.apps.any(
    (a) => a.options.projectId != 'demo-tinder-universitario',
  )) {
    throw StateError('Demo: proyecto no permitido.');
  }
  final auth = FirebaseAuth.instanceFor(app: app);
  // En teléfono físico, adb reverse expone los servicios en el propio loopback.
  // FlutterFire mapea localhost a 10.0.2.2 por defecto incluso sin un AVD.
  await auth.useAuthEmulator('127.0.0.1', 9099, automaticHostMapping: false);
  final db = FirebaseFirestore.instanceFor(app: app);
  db.settings = const Settings(persistenceEnabled: false);
  db.useFirestoreEmulator('127.0.0.1', 8088, automaticHostMapping: false);
  await FirebaseStorage.instanceFor(
    app: app,
  ).useStorageEmulator('127.0.0.1', 9198, automaticHostMapping: false);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tinder DEMO LOCAL',
      theme: AppTheme.light,
      builder: (context, child) => Column(
        children: [
          const Material(
            color: Color(0xff16452d),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'DEMO LOCAL · Solo emuladores',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child!),
        ],
      ),
      home: AuthGate(
        service: AuthService(auth: auth, firestore: db),
      ),
    ),
  );
}
