import '../../widgets/app_ui.dart';
import 'package:flutter/material.dart';
import '../auth/auth_service.dart' show firebaseError;
import 'discovery_preferences.dart';
import 'preferences_service.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.uid,
    required this.onBack,
    this.service,
  });
  final String uid;
  final VoidCallback onBack;
  final PreferencesService? service;
  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late final _service = widget.service ?? PreferencesService();
  final _form = GlobalKey<FormState>();
  int _min = DiscoveryLimits.minAge, _max = DiscoveryLimits.maxAge;
  String? _gender;
  bool _loading = true, _saving = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _service.load(widget.uid);
      if (mounted && value != null) {
        setState(() {
          _min = value.minAge;
          _max = value.maxAge;
          _gender = PreferredGender.isValid(value.preferredGender)
              ? value.preferredGender
              : null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = firebaseError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await _service.save(
        widget.uid,
        DiscoveryPreferences(
          minAge: _min,
          maxAge: _max,
          preferredGender: _gender!,
        ),
      );
      if (mounted) {
        setState(
          () => _notice =
              'Preferencias guardadas. Vuelve a Descubrir para aplicarlas.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is DiscoveryException
              ? error.message
              : firebaseError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Preferencias'),
      leading: IconButton(
        onPressed: _saving ? null : widget.onBack,
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Volver',
      ),
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppMark(size: 56),
                        const SizedBox(height: 24),
                        const Text(
                          '¿A quién te gustaría conocer?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Solo se mostrarán personas cuyas preferencias también te incluyan. Tus preferencias son privadas.',
                        ),
                        const SizedBox(height: 24),
                        const SectionHeading(
                          'Tu conexión ideal',
                          icon: Icons.favorite_border,
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey('preferred-$_gender'),
                          initialValue: _gender,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Género de interés',
                          ),
                          items: PreferredGender.labels.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _gender = value),
                          validator: (value) => PreferredGender.isValid(value)
                              ? null
                              : 'Selecciona una opción.',
                        ),
                        const SizedBox(height: 20),
                        const SectionHeading(
                          'Rango de edad',
                          icon: Icons.tune_rounded,
                          subtitle: 'Entre 18 y 100 años',
                        ),
                        _ageField('Edad mínima', _min, (value) => _min = value),
                        const SizedBox(height: 20),
                        _ageField('Edad máxima', _max, (value) => _max = value),
                        if (_error != null) AppNotice(_error!, error: true),
                        if (_notice != null) AppNotice(_notice!),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Guardar preferencias'),
                        ),
                        if (_error != null)
                          TextButton(
                            onPressed: _saving ? null : _load,
                            child: const Text('Recargar'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
  Widget _ageField(String label, int value, ValueChanged<int> change) =>
      DropdownButtonFormField<int>(
        key: ValueKey('$label-$value'),
        initialValue:
            value >= DiscoveryLimits.minAge && value <= DiscoveryLimits.maxAge
            ? value
            : null,
        decoration: InputDecoration(labelText: label),
        items: List.generate(
          DiscoveryLimits.maxAge - DiscoveryLimits.minAge + 1,
          (index) {
            final age = DiscoveryLimits.minAge + index;
            return DropdownMenuItem(value: age, child: Text('$age años'));
          },
        ),
        onChanged: _saving
            ? null
            : (value) {
                if (value != null) setState(() => change(value));
              },
        validator: (value) => value == null
            ? 'Selecciona una edad válida.'
            : _min > _max
            ? 'La edad mínima no puede superar la máxima.'
            : null,
      );
}
