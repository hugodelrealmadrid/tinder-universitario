import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

typedef AcademicChoice = ({
  String universityId,
  String campusId,
  String careerId,
});
typedef AcademicOption = ({String id, String name});

class AcademicDirectory {
  AcademicDirectory([FirebaseFirestore? db])
    : db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore db;

  Stream<void> get availabilityChanges =>
      db.doc('registrationDirectory/version').snapshots().skip(1).map((_) {});

  Future<List<AcademicOption>> options(String path) async {
    final parts = path.split('/');
    final parameters = switch (parts) {
      ['interests'] || ['universities'] => {'kind': path},
      ['universities', final university, 'campuses'] => {
        'kind': 'campuses',
        'university': university,
      },
      [
        'universities',
        final university,
        'campuses',
        final campus,
        'offerings',
      ] =>
        {'kind': 'careers', 'university': university, 'campus': campus},
      _ => throw ArgumentError.value(path, 'path'),
    };
    const staging = bool.fromEnvironment('LIGO_STAGING');
    final endpoint = staging
        ? 'http://127.0.0.1:7466/'
        : const String.fromEnvironment('VERIFICATION_BACKEND_URL');
    final origin = Uri.tryParse(endpoint);
    if (origin == null ||
        !origin.hasAuthority ||
        !(origin.scheme == 'https' ||
            (staging &&
                db.app.options.projectId == 'demo-ligo-staging' &&
                origin.origin == 'http://127.0.0.1:7466'))) {
      throw StateError('Directorio académico no configurado.');
    }
    final uri = origin
        .resolve('registration/options')
        .replace(queryParameters: parameters);
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Directorio no disponible.');
    }
    final items = (jsonDecode(response.body) as Map)['items'] as List;
    return items
        .map((row) => (id: row['id'] as String, name: row['name'] as String))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}

class AcademicSelector extends StatefulWidget {
  const AcademicSelector({
    super.key,
    required this.directory,
    required this.onChanged,
    this.retainedUniversity,
    this.retainedCareer,
  });
  final AcademicDirectory directory;
  final ValueChanged<AcademicChoice?> onChanged;
  final String? retainedUniversity, retainedCareer;
  @override
  State<AcademicSelector> createState() => _AcademicSelectorState();
}

class _AcademicSelectorState extends State<AcademicSelector> {
  Future<List<AcademicOption>> _options(String path, String? retained) async {
    final options = await widget.directory.options(path);
    return retained == null
        ? options
        : options.where((item) => item.id == retained).toList();
  }

  late Future<List<AcademicOption>> _universities = _options(
    'universities',
    widget.retainedUniversity,
  );
  Future<List<AcademicOption>>? _campuses, _careers;
  AcademicOption? _university, _campus, _career;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _picker(
        'Universidad',
        _university,
        _universities,
        retry: () => setState(() {
          _universities = _options('universities', widget.retainedUniversity);
        }),
        choose: (value) => setState(() {
          _university = value;
          _campus = null;
          _career = null;
          _careers = null;
          _campuses = widget.directory.options(
            'universities/${value.id}/campuses',
          );
          widget.onChanged(null);
        }),
      ),
      _picker(
        'Sede o campus',
        _campus,
        _campuses,
        retry: () => setState(() {
          _campuses = widget.directory.options(
            'universities/${_university!.id}/campuses',
          );
        }),
        choose: (value) => setState(() {
          _campus = value;
          _career = null;
          _careers = _options(
            'universities/${_university!.id}/campuses/${value.id}/offerings',
            widget.retainedCareer,
          );
          widget.onChanged(null);
        }),
      ),
      _picker(
        'Carrera',
        _career,
        _careers,
        retry: () => setState(() {
          _careers = _options(
            'universities/${_university!.id}/campuses/${_campus!.id}/offerings',
            widget.retainedCareer,
          );
        }),
        choose: (value) => setState(() {
          _career = value;
          widget.onChanged((
            universityId: _university!.id,
            campusId: _campus!.id,
            careerId: value.id,
          ));
        }),
      ),
    ],
  );

  Widget _picker(
    String label,
    AcademicOption? selected,
    Future<List<AcademicOption>>? future, {
    required VoidCallback retry,
    required ValueChanged<AcademicOption> choose,
  }) {
    return FutureBuilder<List<AcademicOption>>(
      future: future,
      builder: (context, snapshot) {
        final options = snapshot.data ?? const <AcademicOption>[];
        if (snapshot.hasError) {
          return TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: Text('Reintentar · $label'),
          );
        }
        final loading = snapshot.connectionState == ConnectionState.waiting;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            onPressed: loading || options.isEmpty
                ? null
                : () async {
                    final option = await showDialog<AcademicOption>(
                      context: context,
                      builder: (_) =>
                          _AcademicSearch(label: label, options: options),
                    );
                    if (mounted && option != null) choose(option);
                  },
            child: Text(
              loading
                  ? 'Cargando $label…'
                  : selected?.name ??
                        (future != null && options.isEmpty
                            ? '$label · Sin opciones'
                            : label),
            ),
          ),
        );
      },
    );
  }
}

class _AcademicSearch extends StatefulWidget {
  const _AcademicSearch({required this.label, required this.options});
  final String label;
  final List<AcademicOption> options;
  @override
  State<_AcademicSearch> createState() => _AcademicSearchState();
}

class _AcademicSearchState extends State<_AcademicSearch> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.options
        .where((option) => option.name.toLowerCase().contains(_query))
        .toList();
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 380,
        height: 360,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Sin coincidencias'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(items[index].name),
                        onTap: () => Navigator.pop(context, items[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class AcademicLabel extends StatefulWidget {
  const AcademicLabel({
    super.key,
    required this.university,
    required this.campus,
    this.style,
  });
  final String university;
  final String? campus;
  final TextStyle? style;
  @override
  State<AcademicLabel> createState() => _AcademicLabelState();
}

class _AcademicLabelState extends State<AcademicLabel> {
  late var _label = _load();
  Future<String> _load() async {
    final directory = AcademicDirectory();
    final university = widget.university;
    final campus = widget.campus;
    final options = await Future.wait([
      directory.options('universities'),
      if (campus != null)
        directory.options('universities/$university/campuses'),
    ]);
    return [
      for (final item in options[0])
        if (item.id == university) item.name,
      if (campus != null)
        for (final item in options[1])
          if (item.id == campus) item.name,
    ].join(' · ');
  }

  @override
  void didUpdateWidget(covariant AcademicLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.university != widget.university ||
        oldWidget.campus != widget.campus) {
      _label = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _label,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox.shrink();
      }
      final text = snapshot.data;
      return Text(
        text != null && text.isNotEmpty ? text : 'Afiliación no disponible',
        style: widget.style,
      );
    },
  );
}
