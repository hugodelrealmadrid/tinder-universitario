import 'guided_registration.dart';
import 'package:flutter/material.dart';
import 'auth_form.dart';
import 'auth_service.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({
    super.key,
    required this.service,
    required this.onLogin,
  });
  final AuthService service;
  final VoidCallback onLogin;
  @override
  Widget build(BuildContext context) =>
      const bool.fromEnvironment('LIGO_MULTIUNIVERSITY')
      ? GuidedRegistration(service: service, onLogin: onLogin)
      : AuthForm(service: service, register: true, onSwitch: onLogin);
}
