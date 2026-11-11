import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'features/auth/registration_only.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const email = String.fromEnvironment('REGISTRATION_EMAIL');
  var stage = 'configuration';
  try {
    if (!kIsWeb ||
        !const bool.fromEnvironment('REAL_REGISTRATION_ONLY') ||
        const bool.fromEnvironment('TINDER_DEMO') ||
        email.isEmpty ||
        !['localhost', '127.0.0.1'].contains(Uri.base.host) ||
        DefaultFirebaseOptions.web.projectId != 'tinder-universitario') {
      throw StateError('Entrada de registro local no configurada.');
    }
    stage = 'firebase';
    final app = await Firebase.initializeApp(
      name: 'personal-registration-only',
      options: DefaultFirebaseOptions.web,
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    stage = 'auth-persistence';
    await auth.setPersistence(Persistence.NONE);
    stage = 'firestore';
    final db = FirebaseFirestore.instanceFor(app: app);
    db.settings = const Settings(persistenceEnabled: false);
    stage = 'registration-service';
    final service = RegistrationOnlyService(
      auth: auth,
      firestore: db,
      allowedEmail: email,
    );
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Registro Firebase real',
        theme: AppTheme.light,
        builder: (context, child) => Column(
          children: [
            const Material(
              color: Color(0xff734700),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'FIREBASE REAL · Solo registro personal · Sin privilegios',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            Expanded(child: child!),
          ],
        ),
        home: RegistrationOnlyGate(service: service),
      ),
    );
  } catch (error) {
    final code = error is FirebaseException
        ? error.code
        : error.runtimeType.toString();
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'No se pudo iniciar el registro local ($stage / $code).',
            ),
          ),
        ),
      ),
    );
  }
}
