import 'package:flutter/material.dart';

import 'backend_client.dart';

class AcademicAdminScreen extends StatefulWidget {
  const AcademicAdminScreen({super.key, required this.client});
  final VerificationClient client;
  @override
  State<AcademicAdminScreen> createState() => _AcademicAdminScreenState();
}

class _AcademicAdminScreenState extends State<AcademicAdminScreen> {
  Map<String, dynamic>? _university, _campus;
  String _search = '';
  final _pages = <String?>[null];
  late var _results = _load();

  Future<Map<String, dynamic>> _load() => widget.client.academicCatalog(
    university: _university?['id'] as String?,
    campus: _campus?['id'] as String?,
    cursor: _pages.last,
  );

  void _navigate(
    Map<String, dynamic>? university,
    Map<String, dynamic>? campus,
  ) {
    setState(() {
      _university = university;
      _campus = campus;
      _search = '';
      _pages
        ..clear()
        ..add(null);
      _results = _load();
    });
  }

  Future<void> _edit(Map<String, dynamic>? row) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AcademicEditor(
        client: widget.client,
        university: _university?['id'] as String?,
        campus: _campus?['id'] as String?,
        row: row,
      ),
    );
    if (mounted && saved == true) {
      setState(() {
        _results = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        _campus?['name'] as String? ??
            _university?['name'] as String? ??
            'Universidades',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Wrap(
        spacing: 8,
        children: [
          if (_university != null)
            TextButton(
              onPressed: () => _navigate(null, null),
              child: const Text('Universidades'),
            ),
          if (_campus != null)
            TextButton(
              onPressed: () => _navigate(_university, null),
              child: const Text('Volver a sedes'),
            ),
          FilledButton.icon(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: Text(
              _campus != null
                  ? 'Asociar carrera'
                  : _university != null
                  ? 'Nueva sede'
                  : 'Nueva universidad',
            ),
          ),
        ],
      ),
      TextField(
        key: ValueKey(_campus?['id'] ?? _university?['id'] ?? 'all'),
        decoration: const InputDecoration(
          labelText: 'Buscar en esta página',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (value) =>
            setState(() => _search = value.trim().toLowerCase()),
      ),
      FutureBuilder<Map<String, dynamic>>(
        future: _results,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return Column(
              children: [
                Text(verificationError(snapshot.error!)),
                TextButton(
                  onPressed: () => setState(() {
                    _results = _load();
                  }),
                  child: const Text('Reintentar'),
                ),
              ],
            );
          }
          final data = snapshot.requireData;
          final rows = (data['items'] as List).cast<Map<String, dynamic>>();
          final visible = rows
              .where(
                (row) =>
                    '${row['name']} ${row['abbreviation'] ?? ''} ${row['city'] ?? ''}'
                        .toLowerCase()
                        .contains(_search),
              )
              .toList();
          final next = data['nextCursor'] as String?;
          return Column(
            children: [
              if (visible.isEmpty)
                const ListTile(title: Text('No hay registros en esta página.')),
              for (final row in visible)
                Card(
                  child: ListTile(
                    title: Text(row['name'] as String),
                    subtitle: Text(
                      '${row['isActive'] == true ? 'Activo' : 'Desactivado'}${row['city'] == null ? '' : ' · ${row['city']}'}',
                    ),
                    onTap: _campus != null
                        ? () => _edit(row)
                        : () => _university == null
                              ? _navigate(row, null)
                              : _navigate(_university, row),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Editar',
                      onPressed: () => _edit(row),
                    ),
                  ),
                ),
              if (_pages.length > 1 || next != null)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _pages.length == 1
                          ? null
                          : () => setState(() {
                              _pages.removeLast();
                              _results = _load();
                            }),
                      child: const Text('Anterior'),
                    ),
                    OutlinedButton(
                      onPressed: next == null
                          ? null
                          : () => setState(() {
                              _pages.add(next);
                              _results = _load();
                            }),
                      child: const Text('Siguiente'),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _AcademicEditor extends StatefulWidget {
  const _AcademicEditor({
    required this.client,
    required this.university,
    required this.campus,
    required this.row,
  });
  final VerificationClient client;
  final String? university, campus;
  final Map<String, dynamic>? row;
  @override
  State<_AcademicEditor> createState() => _AcademicEditorState();
}

class _AcademicEditorState extends State<_AcademicEditor> {
  late final _name = _controller('name'),
      _city = _controller('city'),
      _abbreviation = _controller('abbreviation'),
      _country = _controller('countryCode', 'BO'),
      _source = _controller('source'),
      _date = _controller('verifiedOn');
  late bool _active = widget.row?['isActive'] != false;
  late String? _career = widget.row?['id'] as String?;
  bool _busy = false;
  String? _error;
  late final Future<List<Map<String, dynamic>>> _careers = _loadCareers();
  TextEditingController _controller(String key, [String fallback = '']) =>
      TextEditingController(text: widget.row?[key] as String? ?? fallback);
  Future<List<Map<String, dynamic>>> _loadCareers() async {
    final items = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final page = await widget.client.catalogs('careers', cursor: cursor);
      items.addAll(
        (page['items'] as List).cast<Map<String, dynamic>>().where(
          (row) => row['isActive'] == true,
        ),
      );
      cursor = page['nextCursor'] as String?;
    } while (cursor != null && mounted);
    return items;
  }

  @override
  void dispose() {
    for (final c in [_name, _city, _abbreviation, _country, _source, _date]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.campus != null && _career == null) {
      setState(() => _error = 'Selecciona una carrera.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.saveAcademic({
        'university': widget.university,
        'campus': widget.campus,
        'target': widget.campus != null ? _career : widget.row?['id'],
        'revision': widget.row?['revision'],
        'data': {
          'isActive': _active,
          if (widget.campus == null) ...{
            'name': _name.text,
            'city': _city.text,
          },
          if (widget.university == null) ...{
            'abbreviation': _abbreviation.text,
            'countryCode': _country.text.trim().toUpperCase(),
          },
          if (widget.campus != null) ...{
            'source': _source.text.trim(),
            'verifiedOn': _date.text.trim(),
          },
        },
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = verificationError(error);
        });
      }
    }
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    enabled: !_busy,
    decoration: InputDecoration(labelText: label),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.campus != null
          ? 'Oferta de sede'
          : widget.university != null
          ? 'Sede'
          : 'Universidad',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.campus == null) ...[
              _field(_name, 'Nombre oficial'),
              _field(_city, 'Ciudad'),
              if (widget.university == null) ...[
                _field(_abbreviation, 'Sigla'),
                _field(_country, 'País (código ISO)'),
              ],
            ] else ...[
              if (widget.row == null)
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _careers,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(verificationError(snapshot.error!));
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    return DropdownMenu<String>(
                      expandedInsets: EdgeInsets.zero,
                      enableFilter: true,
                      enabled: !_busy,
                      label: const Text('Carrera'),
                      onSelected: (value) => _career = value,
                      dropdownMenuEntries: snapshot.data!
                          .map(
                            (row) => DropdownMenuEntry(
                              value: row['id'] as String,
                              label: row['name'] as String,
                            ),
                          )
                          .toList(),
                    );
                  },
                )
              else
                Text(widget.row!['name'] as String),
              _field(_source, 'Fuente oficial HTTPS'),
              _field(_date, 'Fecha verificada (AAAA-MM-DD)'),
            ],
            SwitchListTile(
              title: const Text('Activo'),
              value: _active,
              onChanged: _busy ? null : (v) => setState(() => _active = v),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Guardando…' : 'Guardar'),
      ),
    ],
  );
}
