import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../auth/auth_form.dart';
import '../home/home_screen.dart' show LogoutButton;
import 'account_access.dart';
import 'backend_client.dart';
import 'university_verification_screen.dart';
import 'administration_screen.dart';

/// Barrera reactiva de navegación; la autorización definitiva permanece en servidor.
class UniversityGate extends StatefulWidget {
  const UniversityGate({
    super.key,
    required this.service,
    required this.uid,
    required this.child,
    this.client,
  });
  final AuthService service;
  final String uid;
  final Widget child;
  final VerificationClient? client;
  @override
  State<UniversityGate> createState() => _UniversityGateState();
}

class _UniversityGateState extends State<UniversityGate> {
  late final _access = widget.service.watchAccountAccess(widget.uid);
  bool _wasAllowed = false;
  AccountRole? _lastRole;
  bool _dating = false;
  VerificationClient? _ownedClient;
  VerificationClient get _client =>
      widget.client ??
      (_ownedClient ??= VerificationClient(auth: widget.service.auth));
  @override
  void dispose() {
    _ownedClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AccountAccess>(
    stream: _access,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final a = snapshot.data;
      final allowed = !snapshot.hasError && a?.canDate == true;
      if (_wasAllowed && (!allowed || _lastRole != a?.role)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });
      }
      _wasAllowed = allowed;
      _lastRole = a?.role;
      if (allowed) {
        if (a!.canAdminister) {
          if (!_dating) {
            return AdministrationScreen(
              client: _client,
              access: a,
              uid: widget.uid,
              logout: LogoutButton(service: widget.service),
              onDating: () => setState(() => _dating = true),
            );
          }
          return Column(
            children: [
              Material(
                child: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _dating = false),
                      child: const Text('Administración'),
                    ),
                  ),
                ),
              ),
              Expanded(child: widget.child),
            ],
          );
        }
        return widget.child;
      }
      _dating = false;
      if (!snapshot.hasError) {
        return UniversityVerificationScreen(
          key: ValueKey(widget.uid),
          client: _client,
          access: a ?? const AccountAccess(suspended: true),
          logout: LogoutButton(service: widget.service),
        );
      }
      final message = snapshot.hasError
          ? 'No se pudo comprobar tu autorización. Reintenta cuando haya conexión.'
          : a?.suspended == true && a?.role != null
          ? 'Tu cuenta está suspendida administrativamente.'
          : a?.status == UniversityStatus.rejected
          ? 'Tu verificación universitaria fue rechazada.'
          : 'Tu verificación universitaria está pendiente. Las funciones de citas requieren aprobación.';
      return AuthCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Verificación universitaria'),
            const SizedBox(height: 16),
            Text(message),
            LogoutButton(service: widget.service),
          ],
        ),
      );
    },
  );
}
