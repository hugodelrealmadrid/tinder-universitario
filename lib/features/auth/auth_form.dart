import 'package:flutter/material.dart';
import 'auth_service.dart';

class AuthForm extends StatefulWidget {
  const AuthForm({
    super.key,
    required this.service,
    required this.register,
    required this.onSwitch,
  });
  final AuthService service;
  final bool register;
  final VoidCallback onSwitch;
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  DateTime? _birthDate;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.register) {
        await widget.service.register(_email.text, _password.text, _birthDate!);
      } else {
        await widget.service.login(_email.text, _password.text);
      }
    } catch (error) {
      if (mounted) setState(() => _error = firebaseError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthCard(
    child: Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.favorite, color: Color(0xFFE94057), size: 64),
            const SizedBox(height: 20),
            const Text(
              'Tinder Universitario',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              widget.register
                  ? 'Crea tu cuenta · Solo mayores de 18 años'
                  : 'Conoce estudiantes de tu universidad',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
              ),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Escribe un correo válido.',
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _hidePassword,
              autofillHints: [
                widget.register
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Contraseña',
                suffixIcon: IconButton(
                  tooltip: _hidePassword
                      ? 'Mostrar contraseña'
                      : 'Ocultar contraseña',
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Escribe tu contraseña.';
                }
                if (widget.register && value.length < 6) {
                  return 'Usa al menos 6 caracteres.';
                }
                return null;
              },
              onFieldSubmitted: (_) {
                if (!widget.register) _submit();
              },
            ),
            if (widget.register) ...[
              const SizedBox(height: 18),
              TextFormField(
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar contraseña',
                ),
                validator: (value) => value == _password.text
                    ? null
                    : 'Las contraseñas no coinciden.',
              ),
              const SizedBox(height: 18),
              BirthDateField(
                enabled: !_busy,
                onChanged: (date) => _birthDate = date,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                semanticsLabel: _error,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.register ? 'Crear cuenta' : 'Iniciar sesión'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : widget.onSwitch,
              child: Text(
                widget.register
                    ? 'Ya tengo cuenta · Iniciar sesión'
                    : 'Crear una cuenta',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class BirthDateField extends StatelessWidget {
  const BirthDateField({
    super.key,
    required this.onChanged,
    this.enabled = true,
  });
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => FormField<DateTime>(
    validator: (date) => date == null
        ? 'Selecciona tu fecha de nacimiento.'
        : !isAdult(date)
        ? 'Debes tener al menos 18 años.'
        : null,
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: !enabled
              ? null
              : () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: now,
                    initialDate:
                        field.value ??
                        DateTime(now.year - 18, now.month, now.day),
                    helpText: 'Fecha de nacimiento',
                    cancelText: 'Cancelar',
                    confirmText: 'Aceptar',
                  );
                  if (date != null && field.mounted) {
                    field.didChange(date);
                    onChanged(date);
                  }
                },
          icon: const Icon(Icons.calendar_today),
          label: Text(
            field.value == null
                ? 'Fecha de nacimiento'
                : '${field.value!.day}/${field.value!.month}/${field.value!.year}',
          ),
        ),
        if (field.hasError)
          Text(
            field.errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
