import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'auth_form.dart';
import 'auth_gate.dart';

/// Herramienta local de alta personal, sin provisión, roles ni navegación de citas.
class RegistrationOnlyService extends AuthService {
  RegistrationOnlyService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required this.allowedEmail,
  }) : super(auth: auth, firestore: firestore) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(allowedEmail)) {
      throw ArgumentError('Se requiere el correo autorizado.');
    }
  }
  final String allowedEmail;
  bool allows(String? email) =>
      email?.trim().toLowerCase() == allowedEmail.toLowerCase();
  void _check(String? email) {
    if (!allows(email)) {
      throw StateError('Esta ejecución solo admite la cuenta autorizada.');
    }
  }

  @override
  Future<void> register(String email, String password, DateTime birthDate) {
    _check(email);
    return super.register(allowedEmail, password, birthDate);
  }

  @override
  Future<void> login(String email, String password) {
    _check(email);
    return super.login(allowedEmail, password);
  }

  @override
  Future<bool> ensureProfile(User user, {DateTime? birthDate}) {
    _check(user.email);
    return super.ensureProfile(user, birthDate: birthDate);
  }
}

class RegistrationOnlyGate extends StatefulWidget {
  const RegistrationOnlyGate({super.key, required this.service});
  final RegistrationOnlyService service;
  @override
  State<RegistrationOnlyGate> createState() => _RegistrationOnlyGateState();
}

class _RegistrationOnlyGateState extends State<RegistrationOnlyGate> {
  bool _register = true;
  late final _changes = widget.service.authChanges;
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _changes,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(child: Text('No se pudo iniciar la sesión.'));
      }
      final user = snapshot.data;
      if (user == null) {
        return AuthForm(
          service: widget.service,
          register: _register,
          fixedEmail: widget.service.allowedEmail,
          onSwitch: () => setState(() => _register = !_register),
        );
      }
      if (!widget.service.allows(user.email)) {
        return const Center(
          child: Text(
            'Sesión distinta de la cuenta autorizada. Cierra esta pestaña.',
          ),
        );
      }
      return ProfileGate(
        key: ValueKey(user.uid),
        service: widget.service,
        user: user,
        verifiedBuilder: (_) => const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Cuenta registrada y correo verificado.\n'
                'Ya puedes cerrar esta pestaña y avisar para revisar tu UID.\n'
                'No se asignaron roles ni se habilitaron funciones de citas.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    },
  );
}
