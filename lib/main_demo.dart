import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'features/auth/auth_gate.dart';
import 'features/auth/auth_service.dart';
import 'theme/app_theme.dart';

@JS('demoFirebaseReady')
external void _reportReady(JSString project, JSString bucket);

/// Punto de entrada exclusivo Web. No importa firebase_options.dart ni main.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (!kIsWeb ||
        !const bool.fromEnvironment('TINDER_DEMO') ||
        const String.fromEnvironment('CHAT_STORAGE_ORIGIN') !=
            'http://127.0.0.1:9198') {
      throw StateError(
        'Usa el lanzador Web demo con el endpoint local obligatorio.',
      );
    }
    if (Firebase.apps.isNotEmpty) {
      throw StateError(
        'El arranque demo exige una página nueva sin otras apps Firebase.',
      );
    }
    final app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-tinder-universitario-key',
        appId: '1:1234567890:web:demo-local',
        messagingSenderId: '1234567890',
        projectId: 'demo-tinder-universitario',
        authDomain: '127.0.0.1',
        storageBucket: 'demo-tinder-universitario.appspot.com',
      ),
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('127.0.0.1', 9099);
    await auth.setPersistence(Persistence.SESSION);
    final db = FirebaseFirestore.instanceFor(app: app);
    db.settings = const Settings(persistenceEnabled: false);
    db.useFirestoreEmulator('127.0.0.1', 8088);
    await FirebaseStorage.instanceFor(
      app: app,
    ).useStorageEmulator('127.0.0.1', 9198);
    if (Firebase.apps.any(
      (a) => a.options.projectId != 'demo-tinder-universitario',
    )) {
      throw StateError('Se detectó una app ajena al proyecto demo.');
    }
    _reportReady(app.options.projectId.toJS, app.options.storageBucket!.toJS);
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Tinder Universitario — DEMO LOCAL',
        theme: AppTheme.light,
        // Reserva el espacio de los avisos del servidor demo y de Auth Emulator.
        builder: (context, child) => Padding(
          padding: const EdgeInsets.only(top: 26, bottom: 22),
          child: child!,
        ),
        home: AuthGate(
          service: AuthService(auth: auth, firestore: db),
        ),
      ),
    );
  } catch (error) {
    // Nunca volver al arranque o las opciones de producción si el demo falla.
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'El entorno demo no pudo iniciarse. No se usará producción.\n$error',
            ),
          ),
        ),
      ),
    );
  }
}
