import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import 'auth_form.dart';
import 'auth_service.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.service,
    required this.onVerified,
  });
  final AuthService service;
  final VoidCallback onVerified;
  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _cooldown;
  bool _checking = false, _loggingOut = false;
  String? _message, _error;
  bool get _busy =>
      _checking || _loggingOut || widget.service.sendingVerification;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_deliveryChanged);
    _watchCooldown();
  }

  void _watchCooldown() {
    _cooldown?.cancel();
    if (widget.service.resendSeconds == 0) return;
    // Solo repinta la cuenta atrás; no consulta Firebase ni reenvía correos.
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || widget.service.resendSeconds == 0) timer.cancel();
      if (mounted) setState(() {});
    });
  }

  void _deliveryChanged() {
    if (!mounted) return;
    _watchCooldown();
    setState(() {});
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    widget.service.removeListener(_deliveryChanged);
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _checking = true;
      _error = null;
      _message = null;
    });
    try {
      final verified = await widget.service.reloadEmailVerification();
      if (!mounted) return;
      if (verified) {
        widget.onVerified();
      } else {
        setState(() => _message = 'Tu correo todavía no ha sido verificado.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = emailVerificationError(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || widget.service.resendSeconds > 0) return;
    setState(() {
      _error = null;
      _message = null;
    });
    try {
      final sent = await widget.service.sendVerificationEmail();
      if (mounted && sent) {
        setState(
          () => _message =
              'Correo de verificación enviado. Revisa también la carpeta de spam.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = emailVerificationError(error));
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() {
      _loggingOut = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.service.logout();
    } catch (error) {
      if (mounted) setState(() => _error = emailVerificationError(error));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final error = _error ?? service.verificationSendError;
    return AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.rose,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_unread_outlined,
                size: 42,
                color: AppColors.coral,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Verifica tu correo',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            service.verificationSent
                ? 'Enviamos un enlace de verificación a:'
                : 'Verifica el acceso al correo de tu cuenta:',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            service.currentUser?.email ?? 'Sesión no disponible',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const Text(
            'Abre el enlace enviado por Firebase, vuelve aquí y pulsa «Ya verifiqué mi correo». Si no tienes el enlace, puedes reenviarlo.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Esto confirma tu acceso al correo; no acredita pertenencia a Univalle.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (error != null) AppNotice(error, error: true),
          if (_message != null) AppNotice(_message!),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _check,
            child: const Text(
              'Ya verifiqué mi correo',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy || service.resendSeconds > 0 ? null : _resend,
            icon: const Icon(Icons.forward_to_inbox_outlined),
            label: const Text('Reenviar correo'),
          ),
          if (service.resendSeconds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Podrás reenviar el correo en ${service.resendSeconds} s',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          TextButton(
            onPressed: _busy ? null : _logout,
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
