import 'academic_selector.dart';
import '../../widgets/motion_entrance.dart';
import 'package:flutter/foundation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';

class AuthForm extends StatefulWidget {
  const AuthForm({
    super.key,
    required this.service,
    required this.register,
    required this.onSwitch,
    this.fixedEmail,
  });
  final AuthService service;
  final bool register;
  final VoidCallback onSwitch;
  final String? fixedEmail;
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  DateTime? _birthDate;
  static const _academic = bool.fromEnvironment('LIGO_MULTIUNIVERSITY');
  AcademicChoice? _affiliation;
  int _step = 0;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.fixedEmail != null) _email.text = widget.fixedEmail!;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.register && _academic && _step == 0) {
      setState(() => _step = 1);
      return;
    }
    if (widget.register && _academic && _affiliation == null) {
      setState(() => _error = 'Selecciona universidad, sede y carrera.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.register) {
        if (_academic) {
          await widget.service.registerAcademic(
            _email.text,
            _password.text,
            _birthDate!,
            _affiliation!,
          );
        } else {
          await widget.service.register(
            _email.text,
            _password.text,
            _birthDate!,
          );
        }
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
            const MotionEntrance(child: LigoLogo(size: 44)),
            const SizedBox(height: 20),
            const SizedBox(height: 12),
            Text(
              widget.register
                  ? 'Crea tu cuenta · Solo mayores de 18 años'
                  : 'Tu próxima conexión empieza aquí',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Text(
              widget.register
                  ? 'Tu historia empieza aquí'
                  : 'Bienvenido de nuevo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            if (widget.register && _academic) ...[
              LinearProgressIndicator(
                value: (_step + 1) / 2,
                semanticsLabel: 'Progreso del registro',
              ),
              const SizedBox(height: 12),
              Text(
                _step == 0
                    ? '1 de 2 · Datos y acceso'
                    : '2 de 2 · Tu afiliación universitaria',
              ),
            ],
            if (!widget.register || !_academic || _step == 0) ...[
              TextFormField(
                controller: _email,
                readOnly: widget.fixedEmail != null,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
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
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                  initialDate: _birthDate,
                  onChanged: (date) => _birthDate = date,
                ),
              ],
            ],
            if (widget.register && _academic && _step == 1) ...[
              AcademicSelector(
                directory: widget.service.academicDirectory,
                onChanged: (choice) => _affiliation = choice,
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _step = 0;
                        _affiliation = null;
                        _error = null;
                      }),
                child: const Text('Atrás'),
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
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: _busy
                    ? null
                    : const LinearGradient(
                        colors: [
                          Color(0xFFB93628),
                          Color(0xFFBE0F52),
                          Color(0xFF6324C6),
                        ],
                      ),
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.register
                              ? (_academic && _step == 0
                                    ? 'Continuar'
                                    : 'Crear cuenta')
                              : 'Iniciar sesión',
                        ),
                ),
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
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 960;
          final form = Container(
            key: const ValueKey('ligo-auth-card'),
            constraints: const BoxConstraints(maxWidth: 440),
            padding: EdgeInsets.all(wide ? 28 : 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 48,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: child,
          );
          return SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 56 : 24,
                    vertical: 22,
                  ),
                  child: Row(
                    children: [
                      const LigoLogo(size: 36),
                      const Spacer(),
                      if (wide) ...[
                        const Icon(
                          Icons.verified_user_outlined,
                          color: AppColors.coral,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Conexiones auténticas',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: wide ? 32 : 12),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    color: AppColors.darkBackground,
                  ),
                  child: Stack(
                    children: [
                      if (wide)
                        Positioned.fill(
                          child: Image.asset(
                            'assets/branding/ligo/campus-hero.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                          ),
                        ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.darkBackground.withValues(alpha: .9),
                                const Color(
                                  0xFF392057,
                                ).withValues(alpha: wide ? .5 : 1),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(wide ? 52 : 12),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(child: _LandingCopy()),
                                  const SizedBox(width: 64),
                                  Flexible(child: form),
                                ],
                              )
                            : Column(
                                children: [
                                  if (kIsWeb) const _LandingCopy(compact: true),
                                  if (kIsWeb) const SizedBox(height: 20),
                                  form,
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 40,
                  ),
                  child: Wrap(
                    spacing: 40,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: const [
                      _LandingFeature(
                        Icons.school_outlined,
                        'Compartí tu mundo',
                        'Conocé estudiantes de distintas universidades.',
                      ),
                      _LandingFeature(
                        Icons.favorite_border,
                        'Conectá a tu manera',
                        'Encontrá afinidad, empezá una conversación.',
                      ),
                      _LandingFeature(
                        Icons.lock_outline,
                        'Tu privacidad importa',
                        'Verificación y fotografías con acceso protegido.',
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Text(
                    'LIGO · Para estudiantes mayores de 18 años',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _LandingCopy extends StatelessWidget {
  const _LandingCopy({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'TU MUNDO, MÁS CERCA',
        style: TextStyle(
          color: Color(0xFFFFADB9),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(height: 22),
      Text(
        'Conectá con personas que comparten tu mundo.',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 34 : 54,
          height: 1.06,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.7,
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Una carrera, una conversación, una nueva historia. Descubrí conexiones que empiezan con algo en común.',
        style: TextStyle(color: Color(0xFFECECF0), fontSize: 16, height: 1.7),
      ),
      const SizedBox(height: 24),
      const Row(
        children: [
          Icon(Icons.verified_outlined, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Personas reales. Comunidad universitaria.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    ],
  );
}

class _LandingFeature extends StatelessWidget {
  const _LandingFeature(this.icon, this.title, this.text);
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 280,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.coral, size: 28),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}

class BirthDateField extends StatelessWidget {
  const BirthDateField({
    super.key,
    required this.onChanged,
    this.enabled = true,
    this.initialDate,
  });
  final DateTime? initialDate;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => FormField<DateTime>(
    initialValue: initialDate,
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
