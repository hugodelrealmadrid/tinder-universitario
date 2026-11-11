import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';
import '../preferences/discovery_preferences.dart';
import 'academic_selector.dart';
import 'auth_form.dart';
import 'auth_service.dart';

class GuidedRegistration extends StatefulWidget {
  const GuidedRegistration({
    super.key,
    required this.service,
    required this.onLogin,
    this.recoveryUser,
    this.onRecovered,
  });

  final AuthService service;
  final VoidCallback onLogin;
  final User? recoveryUser;
  final VoidCallback? onRecovered;

  @override
  State<GuidedRegistration> createState() => _GuidedRegistrationState();
}

class _GuidedRegistrationState extends State<GuidedRegistration> {
  static const _titles = [
    'Tu cuenta',
    'Fecha de nacimiento',
    'Universidad',
    'Sede o campus',
    'Carrera',
    'Intereses y preferencias',
    'Revisa tu registro',
  ];
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final _directory = widget.service.academicDirectory;
  late final _draft = widget.recoveryUser == null
      ? null
      : widget.service.pendingAcademicRegistration;
  late final _first = TextEditingController(text: _draft?.firstName);
  late final _last = TextEditingController(text: _draft?.lastName);
  late final _email = TextEditingController(text: widget.recoveryUser?.email);
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  late DateTime? _birth = widget.recoveryUser == null
      ? null
      : widget.service.pendingRegistrationBirthDate;
  late String? _university = _draft?.choice.universityId;
  late String? _campus = _draft?.choice.campusId;
  late String? _career = _draft?.choice.careerId;
  late final _interests = _draft?.interests.toSet() ?? <String>{};
  late final _filterInterests =
      _draft?.preferences.interestIds.toSet() ?? <String>{};
  late final _filterCareers =
      _draft?.preferences.careerIds.toSet() ?? <String>{};
  late final _filterUniversities =
      _draft?.preferences.universityIds.toSet() ?? <String>{};
  late String _mode = _draft?.preferences.universityMode ?? 'all';
  late String _gender =
      _draft?.preferences.preferredGender ?? PreferredGender.both;
  late RangeValues _age = RangeValues(
    (_draft?.preferences.minAge ?? DiscoveryLimits.minAge).toDouble(),
    (_draft?.preferences.maxAge ?? DiscoveryLimits.maxAge).toDouble(),
  );
  List<AcademicOption> _universities = [],
      _campuses = [],
      _careers = [],
      _availableInterests = [];
  int _step = 0;
  int _generation = 0;
  int? _fetchingGeneration;
  bool _loading = false, _busy = false, _hidden = true;
  String? _error, _catalogError;
  Timer? _refresh;
  StreamSubscription<void>? _availability;
  bool _refreshPending = false;

  @override
  void initState() {
    super.initState();
    _availability = _directory.availabilityChanges.listen(
      (_) {
        if (_step >= 2 && _step <= 5 && !_busy) {
          unawaited(_load(background: true));
        }
      },
      onError: (Object _) {
        // The server check before creating Auth still protects a stale draft.
      },
    );
  }

  String get _campusPath => 'universities/$_university/campuses';
  String get _offeringPath => '$_campusPath/$_campus/offerings';

  @override
  void dispose() {
    _refresh?.cancel();
    unawaited(_availability?.cancel());
    _scroll.dispose();
    for (final controller in [_first, _last, _email, _password, _repeat]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _go(int step) {
    _refresh?.cancel();
    _generation++;
    setState(() {
      _step = step;
      _error = null;
      _catalogError = null;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (step >= 2 && step <= 5) {
      unawaited(_load());
      if (step <= 4) {
        _refresh = Timer.periodic(const Duration(seconds: 5), (_) {
          if (!_loading && !_busy) unawaited(_load(background: true));
        });
      }
    }
  }

  bool _has(List<AcademicOption> options, String? value) =>
      options.any((option) => option.id == value);

  Future<void> _load({bool background = false}) async {
    final generation = _generation;
    if (_fetchingGeneration == generation) {
      _refreshPending = true;
      return;
    }
    _fetchingGeneration = generation;
    if (!background) {
      setState(() {
        _loading = true;
        _catalogError = null;
      });
    }
    try {
      final options = switch (_step) {
        2 => await Future.wait([_directory.options('universities')]),
        3 => await Future.wait([_directory.options(_campusPath)]),
        4 => await Future.wait([_directory.options(_offeringPath)]),
        _ => await Future.wait([
          _directory.options('interests'),
          _directory.options('universities'),
          _directory.options(_offeringPath),
        ]),
      };
      if (!mounted || generation != _generation) return;
      setState(() {
        _catalogError = null;
        switch (_step) {
          case 2:
            _universities = options.first;
            if (!_has(_universities, _university)) {
              _university = _campus = _career = null;
            }
          case 3:
            _campuses = options.first;
            if (!_has(_campuses, _campus)) _campus = _career = null;
          case 4:
            _careers = options.first;
            if (!_has(_careers, _career)) _career = null;
          case 5:
            _availableInterests = options[0];
            _universities = options[1];
            _careers = options[2];
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _catalogError = 'No pudimos actualizar el catálogo. Reintenta.',
        );
      }
    } finally {
      if (_fetchingGeneration == generation) _fetchingGeneration = null;
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(_load(background: true));
        }
      }
    }
  }

  DiscoveryPreferences get _preferences => DiscoveryPreferences(
    minAge: _age.start.round(),
    maxAge: _age.end.round(),
    preferredGender: _gender,
    universityMode: _mode,
    universityIds: _mode == 'selected'
        ? _filterUniversities.toList()
        : const [],
    careerIds: _filterCareers.toList(),
    interestIds: _filterInterests.toList(),
  );

  bool _allPresent(Set<String> ids, List<AcademicOption> options) =>
      ids.every((id) => _has(options, id));

  Future<void> _next() async {
    if (_busy || _loading || _catalogError != null) return;
    if (!(_form.currentState?.validate() ?? true)) return;
    final error = switch (_step) {
      2 when !_has(_universities, _university) =>
        'Selecciona una universidad activa.',
      3 when !_has(_campuses, _campus) => 'Selecciona una sede activa.',
      4 when !_has(_careers, _career) => 'Selecciona una carrera disponible.',
      5 when !_preferences.isValid =>
        'Elige las universidades requeridas y hasta nueve filtros combinados.',
      5
          when !_allPresent(_interests, _availableInterests) ||
              !_allPresent(_filterInterests, _availableInterests) ||
              !_allPresent(_filterCareers, _careers) ||
              (_mode == 'selected' &&
                  !_allPresent(_filterUniversities, _universities)) =>
        'Hay selecciones que ya no están disponibles. Quítalas para continuar.',
      _ => null,
    };
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_step < 6) {
      _go(_step + 1);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final universities = await _directory.options('universities');
      if (!mounted) return;
      if (!_has(universities, _university)) {
        _go(2);
        setState(() => _error = 'La universidad cambió. Selecciona otra.');
        return;
      }
      final campuses = await _directory.options(_campusPath);
      if (!mounted) return;
      if (!_has(campuses, _campus)) {
        _go(3);
        setState(() => _error = 'La sede cambió. Selecciona otra.');
        return;
      }
      final options = await Future.wait([
        _directory.options(_offeringPath),
        _directory.options('interests'),
      ]);
      if (!mounted) return;
      if (!_has(options[0], _career)) {
        _go(4);
        setState(() => _error = 'La carrera ya no está disponible.');
        return;
      }
      if (!_allPresent(_interests, options[1]) ||
          !_allPresent(_filterInterests, options[1]) ||
          !_allPresent(_filterCareers, options[0]) ||
          (_mode == 'selected' &&
              !_allPresent(_filterUniversities, universities))) {
        _go(5);
        setState(
          () => _error =
              'Actualiza los intereses o filtros que dejaron de estar disponibles.',
        );
        return;
      }
      final choice = (
        universityId: _university!,
        campusId: _campus!,
        careerId: _career!,
      );
      final registration = (
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        choice: choice,
        interests: _interests.toList(),
        preferences: _preferences,
      );
      final user = widget.recoveryUser;
      if (user == null) {
        await widget.service.registerAcademic(
          _email.text,
          _password.text,
          _birth!,
          choice,
          registration: registration,
        );
      } else {
        final done = await widget.service.resumeAcademicRegistration(
          user,
          _birth!,
          registration,
        );
        if (mounted && done) widget.onRecovered?.call();
      }
    } catch (error) {
      if (mounted) setState(() => _error = firebaseError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(List<AcademicOption> options, String? id) =>
      options.where((option) => option.id == id).firstOrNull?.name ??
      'No disponible';

  Widget _nameField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        enabled: !_busy,
        maxLength: 80,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(labelText: label, counterText: ''),
        validator: (value) =>
            (value?.trim().isEmpty ?? true) ? 'Completa este campo.' : null,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(24),
            children: [
              const LigoLogo(size: 42),
              const SizedBox(height: 18),
              Text('Paso ${_step + 1} de 7', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (_step + 1) / 7,
                semanticsLabel: 'Progreso del registro',
              ),
              const SizedBox(height: 24),
              Text(
                _titles[_step],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Form(
                key: _form,
                child: KeyedSubtree(key: ValueKey(_step), child: _content()),
              ),
              if (_error != null) AppNotice(_error!, error: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _go(_step - 1),
                      child: const Text('Atrás'),
                    ),
                  if (_step > 0) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || _loading || _catalogError != null
                          ? null
                          : _next,
                      child: _busy
                          ? const Text('Comprobando datos…')
                          : Text(
                              _step < 6
                                  ? 'Siguiente'
                                  : widget.recoveryUser == null
                                  ? 'Crear cuenta'
                                  : 'Completar registro',
                            ),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _busy ? null : widget.onLogin,
                child: Text(
                  widget.recoveryUser == null
                      ? 'Ya tengo cuenta · Iniciar sesión'
                      : 'Cerrar sesión',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _content() {
    if (_step >= 2 && _step <= 5 && _catalogError != null) {
      return Column(
        children: [
          Text(_catalogError!),
          TextButton(
            onPressed: _load,
            child: const Text('Reintentar catálogo'),
          ),
        ],
      );
    }
    if (_loading) {
      return const LinearProgressIndicator(semanticsLabel: 'Cargando catálogo');
    }
    return switch (_step) {
      0 => Column(
        children: [
          _nameField(_first, 'Nombre'),
          const SizedBox(height: 12),
          _nameField(_last, 'Apellido'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            readOnly: widget.recoveryUser != null,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo electrónico'),
            validator: (value) =>
                RegExp(
                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                ).hasMatch(value?.trim() ?? '')
                ? null
                : 'Escribe un correo válido.',
          ),
          if (widget.recoveryUser == null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _hidden,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                suffixIcon: IconButton(
                  tooltip: _hidden
                      ? 'Mostrar contraseña'
                      : 'Ocultar contraseña',
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: const Icon(Icons.visibility_outlined),
                ),
              ),
              validator: (value) => (value?.length ?? 0) >= 6
                  ? null
                  : 'Usa al menos seis caracteres.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _repeat,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar contraseña',
              ),
              validator: (value) => value == _password.text
                  ? null
                  : 'Las contraseñas no coinciden.',
            ),
          ],
        ],
      ),
      1 => BirthDateField(
        initialDate: _birth,
        onChanged: (date) => _birth = date,
      ),
      2 => _OptionList(
        options: _universities,
        selection: _university,
        select: (id) => setState(() {
          if (id != _university) {
            _university = id;
            _campus = _career = null;
            _filterCareers.clear();
          }
        }),
      ),
      3 => _OptionList(
        options: _campuses,
        selection: _campus,
        select: (id) => setState(() {
          if (id != _campus) {
            _campus = id;
            _career = null;
            _filterCareers.clear();
          }
        }),
      ),
      4 => _OptionList(
        options: _careers,
        selection: _career,
        select: (id) => setState(() => _career = id),
      ),
      5 => _preferencesStep(),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: const Text('Cuenta'),
            subtitle: Text(
              '${_first.text.trim()} ${_last.text.trim()}\n${_email.text.trim()}',
            ),
          ),
          ListTile(
            title: const Text('Fecha de nacimiento'),
            subtitle: Text(
              MaterialLocalizations.of(context).formatMediumDate(_birth!),
            ),
          ),
          ListTile(
            title: const Text('Afiliación declarada'),
            subtitle: Text(
              '${_name(_universities, _university)} · ${_name(_campuses, _campus)}\n${_name(_careers, _career)}',
            ),
          ),
          ListTile(
            title: const Text('Intereses y preferencias'),
            subtitle: Text(
              '${_interests.length} intereses de perfil · ${_modeLabels[_mode]} · ${_age.start.round()}–${_age.end.round()} años',
            ),
          ),
          const Text(
            'Después de crear la cuenta, verifica tu correo y presenta tu carnet universitario.',
          ),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Privacidad y eliminación de cuenta'),
            children: [
              Text(
                'Responsable de LIGO: Hugo García Salazar. '
                'Usamos tu correo para la cuenta, tu fecha de nacimiento para '
                'comprobar la edad y tu información académica e intereses '
                'para el perfil y Descubrir. Tus fotos se usan en el perfil '
                'y donde decidas compartirlas. Los mensajes y sus archivos '
                'se muestran a los participantes autorizados del chat. '
                'El carnet se usa para verificar tu acreditación universitaria.',
              ),
              SizedBox(height: 8),
              Text(
                'Para consultar sobre tus datos o pedir la eliminación de tu '
                'cuenta, escribí a hugodelrealmadrid@gmail.com desde el correo '
                'asociado a tu cuenta. Evitá adjuntar contraseñas, códigos o carnets.',
              ),
            ],
          ),
        ],
      ),
    };
  }

  static const _modeLabels = {
    'all': 'Todas las universidades',
    'mine': 'Mi universidad',
    'selected': 'Elegir universidades',
  };

  Widget _preferencesStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _chips('Tus intereses', _availableInterests, _interests),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: _mode,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Filtro universitario'),
        items: [
          for (final entry in _modeLabels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) => setState(() => _mode = value!),
      ),
      if (_mode == 'selected')
        _chips('Universidades elegidas', _universities, _filterUniversities),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _gender,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Género de interés'),
        items: [
          for (final entry in PreferredGender.labels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) => setState(() => _gender = value!),
      ),
      Text('Edad · ${_age.start.round()}–${_age.end.round()} años'),
      RangeSlider(
        values: _age,
        min: 18,
        max: 100,
        divisions: 82,
        labels: RangeLabels('${_age.start.round()}', '${_age.end.round()}'),
        onChanged: (value) => setState(() => _age = value),
      ),
      _chips('Carreras de interés de tu sede', _careers, _filterCareers),
      _chips('Intereses para Descubrir', _availableInterests, _filterInterests),
    ],
  );

  Widget _chips(
    String label,
    List<AcademicOption> options,
    Set<String> chosen,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      if (options.isEmpty) const Text('Sin opciones disponibles.'),
      Wrap(
        spacing: 8,
        children: [
          for (final option in options)
            FilterChip(
              label: Text(option.name),
              selected: chosen.contains(option.id),
              onSelected: (value) => setState(() {
                if (!value) {
                  chosen.remove(option.id);
                } else if (chosen.length < 5) {
                  chosen.add(option.id);
                } else {
                  _error =
                      'Selecciona como máximo cinco opciones en cada grupo.';
                }
              }),
            ),
          for (final id in chosen.where((id) => !_has(options, id)))
            InputChip(
              label: const Text('Opción no disponible'),
              onDeleted: () => setState(() => chosen.remove(id)),
            ),
        ],
      ),
    ],
  );
}

class _OptionList extends StatefulWidget {
  const _OptionList({
    required this.options,
    required this.selection,
    required this.select,
  });
  final List<AcademicOption> options;
  final String? selection;
  final ValueChanged<String> select;
  @override
  State<_OptionList> createState() => _OptionListState();
}

class _OptionListState extends State<_OptionList> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.options
        .where((row) => row.name.toLowerCase().contains(_search))
        .toList();
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              setState(() => _search = value.trim().toLowerCase()),
        ),
        SizedBox(
          height: 240,
          child: rows.isEmpty
              ? const Center(child: Text('Sin opciones disponibles.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final selected = row.id == widget.selection;
                    return ListTile(
                      title: Text(row.name),
                      selected: selected,
                      trailing: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                      ),
                      onTap: () => widget.select(row.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
