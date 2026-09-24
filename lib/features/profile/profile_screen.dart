import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/auth_service.dart';
import 'profile_service.dart';
import 'student_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.uid,
    required this.logout,
    this.service,
  });
  final String uid;
  final Widget logout;
  final ProfileService? service;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileService _service = widget.service ?? ProfileService();
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  String? _gender;
  final _description = TextEditingController();
  final _picker = ImagePicker();
  StudentProfile? _profile;
  List<CatalogItem> _careers = [], _interests = [];
  Set<String> _selectedInterests = {};
  DateTime? _birthDate;
  String? _careerId;
  bool _activate = false, _loading = true, _busy = false;
  String? _error, _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _description.dispose();
    super.dispose();
  }

  String _message(Object error) {
    if (error is ProfileException) return error.message;
    return firebaseError(error);
  }

  void _fill(StudentProfile profile) {
    _profile = profile;
    _first.text = profile.firstName;
    _last.text = profile.lastName;
    _gender = ProfileGender.isValid(profile.gender) ? profile.gender : null;
    _description.text = profile.description;
    _birthDate = profile.birthDate;
    _careerId = profile.careerId;
    _selectedInterests = profile.interestIds.toSet();
    _activate = profile.isActive && profile.isComplete;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _service.load(widget.uid);
      final careers = await _service.catalog('careers');
      final interests = await _service.catalog('interests');
      if (!mounted) return;
      setState(() {
        _careers = careers;
        _interests = interests;
        _fill(profile);
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted &&
        _profile != null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        final lost = await _picker.retrieveLostData();
        if (!mounted) return;
        if (lost.exception != null) throw lost.exception!;
        if (lost.files?.isNotEmpty == true) await _upload(lost.files!.first);
      } catch (error) {
        if (mounted) setState(() => _error = _message(error));
      }
    }
  }

  String? get _activeCareerId =>
      _careers.any((item) => item.id == _careerId) ? _careerId : null;
  StudentProfile get _draft => StudentProfile(
    firstName: _first.text,
    lastName: _last.text,
    gender: _gender ?? '',
    description: _description.text,
    birthDate: _birthDate,
    careerId: _activeCareerId,
    interestIds: _selectedInterests.toList(),
    photoUrls: _profile!.photoUrls,
    mainPhotoUrl: _profile!.mainPhotoUrl,
  );
  void _changed() => setState(() {
    if (!_draft.isComplete) _activate = false;
  });

  Future<void> _run(
    Future<void> Function() action, {
    bool resetDraft = false,
    String? success,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      final profile = await _service.load(widget.uid);
      if (!mounted) return;
      setState(() {
        if (resetDraft) {
          _fill(profile);
        } else {
          _profile = profile;
        }
        if (!_draft.isComplete) _activate = false;
        _notice = success;
      });
    } catch (error) {
      // Si falló el borrado físico, Firestore ya puede haber quitado la URL.
      try {
        final current = await _service.load(widget.uid);
        if (mounted) {
          setState(() {
            _profile = current;
            if (!_draft.isComplete) _activate = false;
          });
        }
      } catch (_) {
        /* Conserva el formulario y el mensaje original. */
      }
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(XFile file) => _run(() async {
    if (await file.length() > maxPhotoBytes) {
      throw const ProfileException('Cada imagen debe pesar como máximo 5 MB.');
    }
    await _service.upload(widget.uid, await file.readAsBytes());
  }, success: 'Fotografía guardada.');

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && file != null) await _upload(file);
  }

  Future<void> _delete(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar fotografía'),
        content: const Text(
          'Se eliminará del perfil y de Storage. Si es la última, el perfil quedará inactivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(
        () => _service.remove(widget.uid, url),
        success: 'Fotografía eliminada.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mi perfil')),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error ?? 'No se pudo cargar tu perfil.'),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                    widget.logout,
                  ],
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _profile!.email,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(
                              label: Text(
                                _draft.isComplete
                                    ? 'Perfil completo'
                                    : 'Perfil incompleto',
                              ),
                            ),
                            Chip(
                              label: Text(
                                _profile!.isActive &&
                                        !ProfileGender.isValid(_profile!.gender)
                                    ? 'Requiere corregir género'
                                    : _profile!.isActive
                                    ? 'Activo (guardado)'
                                    : 'Inactivo (guardado)',
                              ),
                            ),
                          ],
                        ),
                        if (!_draft.isComplete)
                          Text(
                            'Para activar falta: ${_draft.missingFields().join(', ')}.',
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Selecciona un género para guardar. Puedes completar los demás datos después; los campos con * son necesarios para activar el perfil.',
                        ),
                        const SizedBox(height: 16),
                        if (_busy) const LinearProgressIndicator(),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_notice!, semanticsLabel: _notice),
                          ),
                        _text(_first, 'Nombre *', 80),
                        _text(_last, 'Apellido *', 80),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final now = DateTime.now();
                                  final date = await showDatePicker(
                                    context: context,
                                    firstDate: DateTime(1900),
                                    lastDate: now,
                                    initialDate:
                                        _birthDate ??
                                        DateTime(
                                          now.year - 18,
                                          now.month,
                                          now.day,
                                        ),
                                    helpText: 'Fecha de nacimiento',
                                    cancelText: 'Cancelar',
                                    confirmText: 'Aceptar',
                                  );
                                  if (date != null && mounted) {
                                    _birthDate = date;
                                    _changed();
                                  }
                                },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            _birthDate == null
                                ? 'Fecha de nacimiento *'
                                : 'Nacimiento: ${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
                          ),
                        ),
                        if (_birthDate != null && !isAdult(_birthDate!))
                          Text(
                            'Debes tener al menos 18 años.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey('gender-${_gender ?? 'none'}'),
                          initialValue: _gender,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Género *',
                          ),
                          hint: const Text('Selecciona una opción'),
                          items: ProfileGender.labels.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  _gender = value;
                                  _changed();
                                },
                          validator: (value) => ProfileGender.isValid(value)
                              ? null
                              : 'Selecciona Masculino o Femenino.',
                        ),
                        if (_profile!.gender.isNotEmpty &&
                            !ProfileGender.isValid(_profile!.gender))
                          const Text(
                            'El género anterior no es válido. Elige una opción y guarda el perfil; no se cambiará automáticamente.',
                          ),
                        const SizedBox(height: 16),
                        _text(
                          _description,
                          'Descripción',
                          maxDescriptionLength,
                          lines: 4,
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey('career-${_activeCareerId ?? 'none'}'),
                          initialValue: _activeCareerId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Carrera * (una sola)',
                          ),
                          items: _careers
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(
                                    item.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  _careerId = value;
                                  _changed();
                                },
                        ),
                        if (_careerId != null && _activeCareerId == null)
                          const Text(
                            'Tu carrera anterior ya no está activa. Selecciona otra para activar tu perfil.',
                          ),
                        if (_careers.isEmpty)
                          const Text(
                            'No hay carreras activas disponibles. Debe cargarse el catálogo en Firestore. Puedes guardar el resto del perfil.',
                          ),
                        const SizedBox(height: 24),
                        Text(
                          'Intereses (${_selectedInterests.length}/$maxInterests)',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text('Opcionales. Selecciona o quita hasta 5.'),
                        if (_interests.isEmpty)
                          const Text('No hay intereses activos disponibles.'),
                        Wrap(
                          spacing: 8,
                          children: _interests
                              .map(
                                (item) => FilterChip(
                                  label: Text(item.name),
                                  selected: _selectedInterests.contains(
                                    item.id,
                                  ),
                                  onSelected: _busy
                                      ? null
                                      : (selected) {
                                          if (selected &&
                                              _selectedInterests.length >=
                                                  maxInterests) {
                                            setState(
                                              () => _error =
                                                  'Puedes seleccionar hasta 5 intereses.',
                                            );
                                            return;
                                          }
                                          setState(() {
                                            if (selected) {
                                              _selectedInterests.add(item.id);
                                            } else {
                                              _selectedInterests.remove(
                                                item.id,
                                              );
                                            }
                                          });
                                        },
                                ),
                              )
                              .toList(),
                        ),
                        ..._selectedInterests
                            .where(
                              (id) => !_interests.any((item) => item.id == id),
                            )
                            .map(
                              (id) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Interés anterior no disponible',
                                ),
                                trailing: TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                          () => _selectedInterests.remove(id),
                                        ),
                                  child: const Text('Quitar'),
                                ),
                              ),
                            ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                    final careers = await _service.catalog(
                                      'careers',
                                    );
                                    final interests = await _service.catalog(
                                      'interests',
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _careers = careers;
                                        _interests = interests;
                                      });
                                    }
                                  }),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Recargar catálogos'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Fotografías *',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text(
                          'Hasta 6 imágenes JPG, PNG o WebP de 5 MB. Las fotos se guardan al realizar cada acción.',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _profile!.photoUrls.map(_photo).toList(),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed:
                              _busy || _profile!.photoUrls.length >= maxPhotos
                              ? null
                              : _pick,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Seleccionar y subir imagen'),
                        ),
                        if (_service.pendingDeletes.isNotEmpty) ...[
                          const Text(
                            'Hay archivos pendientes de eliminar de Storage. Reintenta antes de salir.',
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () async {
                                      for (final url
                                          in _service.pendingDeletes.toList()) {
                                        await _service.retryDelete(
                                          widget.uid,
                                          url,
                                        );
                                      }
                                    },
                                    success: 'Archivos pendientes eliminados.',
                                  ),
                            child: const Text(
                              'Reintentar eliminación en Storage',
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Activar perfil al guardar'),
                          subtitle: Text(
                            _draft.isComplete
                                ? 'Puedes desactivarlo sin borrar tus datos.'
                                : 'Disponible cuando completes los datos mínimos.',
                          ),
                          value: _activate && _draft.isComplete,
                          onChanged: _busy || !_draft.isComplete
                              ? null
                              : (value) => setState(() => _activate = value),
                        ),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  if (!_form.currentState!.validate()) return;
                                  _run(
                                    () async {
                                      await _service.save(
                                        widget.uid,
                                        _draft,
                                        activate: _activate,
                                      );
                                    },
                                    resetDraft: true,
                                    success: 'Perfil guardado.',
                                  );
                                },
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Guardar perfil'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        AbsorbPointer(absorbing: _busy, child: widget.logout),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    ),
  );

  Widget _text(
    TextEditingController controller,
    String label,
    int max, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      maxLines: lines,
      maxLength: max,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => _changed(),
      validator: (value) =>
          (value?.trim().length ?? 0) > max ? 'Máximo $max caracteres.' : null,
    ),
  );

  Widget _photo(String url) {
    final main = url == _profile!.mainPhotoUrl;
    return SizedBox(
      width: 190,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Image.network(
              url,
              height: 170,
              width: 190,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 170,
                      child: Center(child: CircularProgressIndicator()),
                    ),
              errorBuilder: (context, error, stack) => const SizedBox(
                height: 170,
                child: Center(
                  child: Text(
                    'No se pudo cargar la foto',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _busy || main
                  ? null
                  : () => _run(
                      () => _service.chooseMain(widget.uid, url),
                      success: 'Foto principal actualizada.',
                    ),
              icon: Icon(main ? Icons.star : Icons.star_border),
              label: Text(main ? 'Principal' : 'Hacer principal'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => _delete(url),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );
  }
}
