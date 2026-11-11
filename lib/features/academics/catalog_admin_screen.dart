import 'dart:math';
import 'package:flutter/material.dart';
import '../verification/backend_client.dart';
import '../verification/account_access.dart';

String catalogOperationId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
const catalogLabels = {'careers': 'Carreras', 'interests': 'Intereses'};

/// Formularios funcionales; el dashboard visual LIGO se desarrolla después.
class CatalogAdminScreen extends StatefulWidget {
  const CatalogAdminScreen({
    super.key,
    required this.client,
    required this.access,
    required this.kind,
    this.embedded = false,
  });
  final VerificationClient client;
  final AccountAccess access;
  final String kind;
  final bool embedded;
  @override
  State<CatalogAdminScreen> createState() => _CatalogAdminScreenState();
}

class _CatalogAdminScreenState extends State<CatalogAdminScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _cursor, _error;
  bool _busy = false, _editing = false;
  String _search = "", _filter = "all";
  bool get _allowed =>
      widget.access.canAdminister &&
      widget.access.canDate &&
      catalogLabels.containsKey(widget.kind);
  @override
  void initState() {
    super.initState();
    if (_allowed) _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.catalogs(
        widget.kind,
        cursor: more ? _cursor : null,
      );
      if (mounted) {
        setState(() {
          _items = [
            if (more) ..._items,
            ...(result['items'] as List).map(
              (x) => Map<String, dynamic>.from(x as Map),
            ),
          ];
          _cursor = result['nextCursor'] as String?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    if (_busy || _editing) return;
    _editing = true;
    try {
      final done = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _CatalogEditor(client: widget.client, kind: widget.kind, row: row),
      );
      if (done == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Catálogo actualizado. La operación quedó auditada.'),
          ),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      _editing = false;
    }
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    if (_busy) return;
    final active = row['isActive'] != true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(active ? 'Activar elemento' : 'Desactivar elemento'),
        content: Text(
          active
              ? 'Permitirá nuevas selecciones.'
              : 'Impedirá nuevas selecciones. No suspenderá cuentas ni eliminará referencias existentes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{'name': row['name'], 'isActive': active};
      await widget.client.saveCatalog(
        widget.kind,
        data,
        id: row['id'] as String,
        expectedRevision: row['revision'] as int,
        requestId: catalogOperationId(),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _stateLabel(Map<String, dynamic> row) =>
      row['isActive'] == true ? 'Activo' : 'Inactivo';

  Widget _actions(Map<String, dynamic> row) => Wrap(
    spacing: 8,
    children: [
      TextButton.icon(
        onPressed: _busy ? null : () => _edit(row),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Editar'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _toggle(row),
        child: Text(row['isActive'] == true ? 'Desactivar' : 'Activar'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Scaffold(
        body: Center(child: Text('Acceso administrativo no autorizado.')),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(catalogLabels[widget.kind]!)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                catalogLabels[widget.kind]!,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Las desactivaciones no eliminan datos ni revocan acreditaciones existentes.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Crear elemento'),
              ),
              const SizedBox(height: 20),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar en elementos cargados',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in {
                    'all': 'Todos',
                    'active': 'Activos',
                    'inactive': 'Inactivos',
                  }.entries)
                    ChoiceChip(
                      label: Text(f.value),
                      selected: _filter == f.key,
                      onSelected: (_) => setState(() => _filter = f.key),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!, semanticsLabel: _error),
              if (!_busy && _items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hay elementos en este catálogo.'),
                ),
              LayoutBuilder(
                builder: (context, box) {
                  final visible = _items
                      .where(
                        (row) =>
                            (row['name'] as String).toLowerCase().contains(
                              _search.toLowerCase(),
                            ) &&
                            (_filter == 'all' ||
                                (row['isActive'] == true) ==
                                    (_filter == 'active')),
                      )
                      .toList();
                  if (visible.isEmpty) {
                    return _items.isEmpty
                        ? const SizedBox.shrink()
                        : const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Ningún elemento coincide con los filtros.',
                            ),
                          );
                  }
                  if (box.maxWidth >= 640) {
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: box.maxWidth),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Nombre')),
                              DataColumn(label: Text('Estado')),
                              DataColumn(label: Text('Acciones')),
                            ],
                            rows: [
                              for (final row in visible)
                                DataRow(
                                  cells: [
                                    DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 310,
                                        ),
                                        child: Text(
                                          row['name'] as String,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(_stateLabel(row))),
                                    DataCell(_actions(row)),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final row in visible)
                        Card(
                          child: ListTile(
                            title: Text(row['name'] as String),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [Text(_stateLabel(row)), _actions(row)],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (_cursor != null)
                TextButton(
                  onPressed: _busy ? null : () => _load(more: true),
                  child: const Text('Cargar más'),
                ),
              TextButton(
                onPressed: _busy ? null : () => _load(),
                child: const Text('Actualizar catálogo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogEditor extends StatefulWidget {
  const _CatalogEditor({required this.client, required this.kind, this.row});
  final VerificationClient client;
  final String kind;
  final Map<String, dynamic>? row;
  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.row?['name'] as String?,
  );
  late bool _active = widget.row?['isActive'] as bool? ?? true;
  bool _busy = false;
  String? _error;
  final _operation = catalogOperationId();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.saveCatalog(
        widget.kind,
        {'name': _name.text.trim(), 'isActive': _active},
        id: widget.row?['id'] as String?,
        expectedRevision: widget.row?['revision'] as int?,
        requestId: _operation,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.row == null ? 'Crear elemento' : 'Editar elemento'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: widget.kind == 'interests' ? 80 : 120,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? 'Escribe un nombre válido.'
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo para nuevas selecciones'),
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) Text(_error!, semanticsLabel: _error),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
