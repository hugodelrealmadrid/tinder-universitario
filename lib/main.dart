import 'theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TinderUniversitarioApp());
}

class TinderUniversitarioApp extends StatelessWidget {
  const TinderUniversitarioApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Tinder Universitario',
    theme: AppTheme.light,
    home: const FirebaseStartup(),
  );
}

class FirebaseStartup extends StatefulWidget {
  const FirebaseStartup({super.key});
  @override
  State<FirebaseStartup> createState() => _FirebaseStartupState();
}

class _FirebaseStartupState extends State<FirebaseStartup> {
  late Future<AuthService> _startup = _initialize();
  Future<AuthService> _initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    if (kIsWeb) await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    return AuthService();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AuthService>(
    future: _startup,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No se pudo iniciar Firebase.',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Comprueba la conexión y la configuración de Firebase. Si es la primera ejecución, sigue README_BLOQUE_1.md.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() => _startup = _initialize()),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return AuthGate(service: snapshot.data!);
    },
  );
}
