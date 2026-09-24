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
      AuthForm(service: service, register: true, onSwitch: onLogin);
}
