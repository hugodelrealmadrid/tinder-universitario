import 'package:flutter/material.dart';
import 'auth_form.dart';
import 'auth_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    required this.service,
    required this.onRegister,
  });
  final AuthService service;
  final VoidCallback onRegister;
  @override
  Widget build(BuildContext context) =>
      AuthForm(service: service, register: false, onSwitch: onRegister);
}
