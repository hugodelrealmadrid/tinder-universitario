import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'auth_form.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import '../home/home_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.service});
  final AuthService service;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _changes = widget.service.authChanges;
  bool _register = false;
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _changes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return AuthCard(child: Text(firebaseError(snapshot.error!)));
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.data != null) {
        _register = false;
        return ProfileGate(
          key: ValueKey(snapshot.data!.uid),
          service: widget.service,
          user: snapshot.data!,
        );
      }
      return _register
          ? RegisterScreen(
              service: widget.service,
              onLogin: () => setState(() => _register = false),
            )
          : LoginScreen(
              service: widget.service,
              onRegister: () => setState(() => _register = true),
            );
    },
  );
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.service, required this.user});
  final AuthService service;
  final User user;
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Future<bool> _profile = widget.service.ensureProfile(widget.user);
  final _form = GlobalKey<FormState>();
  DateTime? _date;
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _profile,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.data == true) {
        return HomeScreen(service: widget.service, uid: widget.user.uid);
      }
      return AuthCard(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Completar registro', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 16),
              Text(
                snapshot.hasError
                    ? firebaseError(snapshot.error!)
                    : 'Tu cuenta está creada. Confirma tu fecha de nacimiento para crear el documento inicial.',
              ),
              const SizedBox(height: 16),
              if (!snapshot.hasError)
                BirthDateField(onChanged: (date) => _date = date),
              FilledButton(
                onPressed: () {
                  if (snapshot.hasError || _form.currentState!.validate()) {
                    setState(
                      () => _profile = widget.service.ensureProfile(
                        widget.user,
                        birthDate: _date,
                      ),
                    );
                  }
                },
                child: Text(
                  snapshot.hasError ? 'Reintentar' : 'Completar registro',
                ),
              ),
              LogoutButton(service: widget.service),
            ],
          ),
        ),
      );
    },
  );
}
