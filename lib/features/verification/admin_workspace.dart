import 'package:flutter/material.dart';
import 'admin_theme.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import 'backend_client.dart';
import 'audit_presentation.dart';

class AdminSelect extends StatelessWidget {
  const AdminSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.fieldIcon,
  });
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final IconData? fieldIcon;
  @override
  Widget build(BuildContext context) {
    final icon = fieldIcon;
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12));
    final dropdown = DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${options.keys.join()}'),
      initialValue: value,
      isExpanded: true,
      decoration: icon == null
          ? InputDecoration(labelText: label, isDense: true)
          : InputDecoration(
              filled: true,
              fillColor: AdminTheme.surface,
              constraints: const BoxConstraints(minHeight: 52),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: border.copyWith(
                borderSide: BorderSide(color: colors.outline),
              ),
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
            ),
      items:
          <String, String>{
                ...options,
                if (!options.containsKey(value)) value: 'Selección anterior',
              }.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
    if (icon == null) {
      return SizedBox(
        width: MediaQuery.sizeOf(context).width < 600
            ? (MediaQuery.sizeOf(context).width - 44) / 2
            : 190,
        child: dropdown,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              _FilterIcon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Semantics(label: label, child: dropdown),
      ],
    );
  }
}

class _FilterIcon extends StatelessWidget {
  const _FilterIcon(this.icon, {this.size = 32});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: size * .55, color: colors.onPrimaryContainer),
    );
  }
}

class AdminIdentity extends StatelessWidget {
  const AdminIdentity({super.key, required this.person, this.photo});
  final Map<String, dynamic> person;
  final String? photo;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 38,
        height: 38,
        child: ClipOval(
          child: (photo ?? person['photoPath']) == null
              ? ColoredBox(
                  color: AppColors.rose,
                  child: Center(
                    child: Text(
                      personName(person).characters.first,
                      style: const TextStyle(
                        color: AppColors.wine,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
              : AppPhoto(url: photo ?? person['photoPath'] as String?),
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              personName(person),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (person['email'] != null)
              Text(
                person['email'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AdminTheme.muted),
              ),
          ],
        ),
      ),
    ],
  );
}

class AdminPageHeading extends StatelessWidget {
  const AdminPageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.rose,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(icon, color: AppColors.wine),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: AdminTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AdminPeopleView extends StatefulWidget {
  const AdminPeopleView({
    super.key,
    required this.client,
    required this.onInspect,
    this.selecting = false,
  });
  final VerificationClient client;
  final ValueChanged<String> onInspect;
  final bool selecting;
  @override
  State<AdminPeopleView> createState() => _AdminPeopleViewState();
}

class _AdminPeopleViewState extends State<AdminPeopleView> {
  List<Map<String, dynamic>> _rows = [];
  String? _cursor, _error;
  bool _busy = false, _ascending = true;
  String _query = '',
      _role = 'all',
      _state = 'all',
      _career = 'all',
      _sort = 'name';
  int _page = 0;
  static const _size = 10;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.client.administrationUsers(
        cursor: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        _rows = [
          if (more) ..._rows,
          ...(response['items'] as List).map(
            (r) => Map<String, dynamic>.from(r as Map),
          ),
        ];
        _cursor = response['nextCursor'] as String?;
        _page = 0;
      });
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _filter(VoidCallback f) => setState(() {
    f();
    _page = 0;
  });
  @override
  Widget build(BuildContext context) {
    final filtered =
        _rows
            .where(
              (r) =>
                  [
                    r['name'],
                    r['email'],
                  ].join(' ').toLowerCase().contains(_query.toLowerCase()) &&
                  (_role == 'all' || r['role'] == _role) &&
                  (_state == 'all' ||
                      (_state == 'suspended'
                          ? r['suspended'] == true
                          : r['verificationStatus'] == _state)) &&
                  (_career == 'all' || r['career'] == _career),
            )
            .toList()
          ..sort(
            (a, b) =>
                (_ascending ? 1 : -1) *
                (a[_sort]?.toString() ?? '').toLowerCase().compareTo(
                  (b[_sort]?.toString() ?? '').toLowerCase(),
                ),
          );
    final page = _page.clamp(
          0,
          filtered.isEmpty ? 0 : (filtered.length - 1) ~/ _size,
        ),
        visible = filtered.skip(page * _size).take(_size).toList();
    Map<String, String> values(String field) => {
      'all': 'Todas',
      for (final r in _rows)
        if (r[field] is String && (r[field] as String).isNotEmpty)
          r[field] as String: r[field] as String,
    };
    return LayoutBuilder(
      builder: (context, box) => ListView(
        padding: EdgeInsets.all(box.maxWidth < 600 ? 16 : 28),
        children: [
          AdminPageHeading(
            title: widget.selecting ? 'Seleccionar persona' : 'Tu comunidad',
            subtitle: widget.selecting
                ? 'Busca una cuenta existente. El identificador se utiliza internamente.'
                : 'Personas, acreditaciones y acceso en un solo lugar.',
            icon: widget.selecting
                ? Icons.manage_accounts_outlined
                : Icons.people_outline_rounded,
          ),
          if (!widget.selecting) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar por nombre o correo',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => _filter(() => _query = v),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (widget.selecting && box.maxWidth < 600)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar por nombre o correo',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (v) => _filter(() => _query = v),
              ),
            ),
          Builder(
            builder: (context) {
              final fields = <Widget>[
                AdminSelect(
                  label: 'Rol',
                  fieldIcon: widget.selecting
                      ? null
                      : Icons.person_outline_rounded,
                  value: _role,
                  options: {'all': 'Todos', ...adminRoles},
                  onChanged: (v) => _filter(() => _role = v),
                ),
                AdminSelect(
                  label: 'Acreditación / cuenta',
                  fieldIcon: widget.selecting ? null : Icons.shield_outlined,
                  value: _state,
                  options: const {
                    'all': 'Todos',
                    'approved': 'Aprobados',
                    'pending': 'Pendientes',
                    'rejected': 'Rechazados',
                    'suspended': 'Suspendidos',
                  },
                  onChanged: (v) => _filter(() => _state = v),
                ),
                AdminSelect(
                  label: 'Carrera',
                  fieldIcon: widget.selecting ? null : Icons.school_outlined,
                  value: _career,
                  options: values('career'),
                  onChanged: (v) => _filter(() => _career = v),
                ),
              ];
              if (!widget.selecting) {
                return _PeopleFiltersCard(
                  fields: fields,
                  onRefresh: _busy ? null : () => _load(),
                  onClear: _role == 'all' && _state == 'all' && _career == 'all'
                      ? null
                      : () => _filter(() => _role = _state = _career = 'all'),
                );
              }
              final filters = Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (box.maxWidth >= 600)
                    SizedBox(
                      width: box.maxWidth < 600 ? box.maxWidth - 32 : 320,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Buscar por nombre o correo',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (v) => _filter(() => _query = v),
                      ),
                    ),
                  ...fields,
                  IconButton(
                    tooltip: 'Actualizar usuarios',
                    onPressed: _busy ? null : () => _load(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              );
              return box.maxWidth < 600
                  ? ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Filtros y orden',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      leading: const Icon(Icons.tune_rounded),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: filters,
                        ),
                      ],
                    )
                  : filters;
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '${_rows.length} cuentas cargadas · búsqueda y filtros sobre páginas cargadas. Carga la siguiente página para ampliar.',
              style: const TextStyle(fontSize: 11, color: AdminTheme.muted),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) AppNotice(_error!, error: true),
          if (visible.isEmpty && !_busy)
            const AppEmptyState(
              title: 'No hay coincidencias',
              message: 'Prueba otro nombre o carga más cuentas.',
              icon: Icons.person_search_outlined,
            ),
          if (box.maxWidth >= 900)
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: _sort == 'name' ? 0 : null,
                  sortAscending: _ascending,
                  showCheckboxColumn: false,
                  dataRowMinHeight: 76,
                  dataRowMaxHeight: 88,
                  columns: [
                    DataColumn(
                      label: const Text('Persona'),
                      onSort: (_, up) => setState(() {
                        _sort = 'name';
                        _ascending = up;
                      }),
                    ),
                    for (final title in [
                      'Carrera',
                      'Acceso',
                      'Visibilidad',
                      'Acciones',
                    ])
                      DataColumn(label: Text(title)),
                  ],
                  rows: visible
                      .map(
                        (r) => DataRow(
                          onSelectChanged: (_) =>
                              widget.onInspect(r['uid'] as String),
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 240,
                                child: AdminIdentity(
                                  person: r,
                                  photo: r['photoPath'] as String?,
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(
                                  _academicSummary(r),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                            DataCell(_access(r)),
                            DataCell(
                              Text(
                                r['isActive'] == true
                                    ? 'Visible'
                                    : r['isActive'] == false
                                    ? 'No visible'
                                    : 'No disponible',
                              ),
                            ),
                            DataCell(
                              TextButton.icon(
                                onPressed: () =>
                                    widget.onInspect(r['uid'] as String),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  widget.selecting
                                      ? 'Seleccionar'
                                      : 'Ver detalle',
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          if (box.maxWidth < 900)
            for (final r in visible)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AdminIdentity(
                        person: r,
                        photo: r['photoPath'] as String?,
                      ),
                      const SizedBox(height: 12),
                      _access(r),
                      const Divider(height: 24),
                      Text(
                        _academicSummary(r),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => widget.onInspect(r['uid'] as String),
                          label: Text(
                            widget.selecting ? 'Seleccionar' : 'Ver detalle',
                          ),
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Página anterior',
                onPressed: page > 0
                    ? () => setState(() => _page = page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  'Página ${page + 1} · ${filtered.length} coincidencias',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Página siguiente',
                onPressed: (page + 1) * _size < filtered.length
                    ? () => setState(() => _page = page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (_cursor != null)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _load(more: true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Cargar siguiente página de cuentas'),
            ),
        ],
      ),
    );
  }

  Widget _access(Map<String, dynamic> r) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        adminRoles[r['role']] ?? 'Rol no disponible',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
      Text(
        r['suspended'] == true
            ? 'Cuenta suspendida'
            : {
                    'approved': 'Acreditación aprobada',
                    'pending': 'Acreditación pendiente',
                    'rejected': 'Acreditación rechazada',
                  }[r['verificationStatus']] ??
                  'Sin acreditación explícita',
        style: TextStyle(
          fontSize: 11,
          color: r['suspended'] == true ? AdminTheme.alert : AdminTheme.muted,
        ),
      ),
    ],
  );
}

class AdminHistoryView extends StatefulWidget {
  const AdminHistoryView({
    super.key,
    required this.client,
    this.reports = false,
    this.onInspect,
    this.onReview,
  });
  final VerificationClient client;
  final bool reports;
  final ValueChanged<String>? onInspect;
  final Future<void> Function(String, String)? onReview;
  @override
  State<AdminHistoryView> createState() => _AdminHistoryViewState();
}

class _AdminHistoryViewState extends State<AdminHistoryView> {
  List<Map<String, dynamic>> _rows = [];
  final List<String?> _history = [null];
  String? _next, _error;
  bool _busy = false;
  String _search = '',
      _action = 'all',
      _actor = 'all',
      _result = 'all',
      _status = 'pending';
  DateTimeRange? _range;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = widget.reports
          ? await widget.client.reportFeed(
              status: _status,
              cursor: _history[_page],
            )
          : await widget.client.eventFeed(cursor: _history[_page]);
      if (mounted) {
        setState(() {
          _rows = (r['items'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          _next = r['nextCursor'] as String?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
      helpText: 'Filtrar fechas de esta página',
    );
    if (mounted && range != null) setState(() => _range = range);
  }

  Future<void> _detail(Map<String, dynamic> r) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.reports ? 'Detalle del reporte' : 'Detalle de auditoría',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.reports) ...[
                  const Text(
                    'Persona que reporta',
                    style: TextStyle(color: AdminTheme.muted, fontSize: 11),
                  ),
                  AdminIdentity(
                    person: Map<String, dynamic>.from(
                      r['reporter'] as Map? ?? {},
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Persona reportada',
                    style: TextStyle(color: AdminTheme.muted, fontSize: 11),
                  ),
                  AdminIdentity(
                    person: Map<String, dynamic>.from(
                      r['reported'] as Map? ?? {},
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(reportReasons[r['reason']] ?? 'Motivo no catalogado'),
                  if (r['details'] != null) Text(r['details'] as String),
                  Text(
                    'Estado: ${reportStatuses[r['status']] ?? 'No disponible'}',
                  ),
                  if (r['reviewedAt'] != null)
                    Text('Decisión registrada: ${adminDate(r['reviewedAt'])}'),
                ] else ...[
                  Text(
                    eventSentence(r),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text('Resultado: ${eventResult(r['result'])}'),
                  if (r['actor'] is Map)
                    Text(
                      (r['actor']['email'] as String?) ??
                          'Correo no disponible',
                    ),
                  if (r['target'] is Map)
                    Text(
                      (r['target']['email'] as String?) ??
                          'Correo de la entidad no disponible',
                    ),
                  const Text(
                    'Los nombres se resuelven al consultar; no son una instantánea de la identidad histórica.',
                    style: TextStyle(fontSize: 11, color: AdminTheme.muted),
                  ),
                ],
                const SizedBox(height: 12),
                Text(adminDate(r[widget.reports ? 'createdAt' : 'at'])),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _review(Map<String, dynamic> r, String resolution) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          resolution == 'reviewed'
              ? 'Marcar reporte revisado'
              : 'Descartar reporte',
        ),
        content: const Text(
          'La decisión quedará auditada. No se suspenderá automáticamente ninguna cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onReview?.call(r['id'] as String, resolution);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows.where((r) {
      final day = DateTime.tryParse(
        r[widget.reports ? 'createdAt' : 'at'] as String? ?? '',
      )?.toLocal();
      return (widget.reports
                  ? '${personName(r['reporter'])} ${personName(r['reported'])} ${r['reason'] ?? ''}'
                  : '${eventSentence(r)} ${r['actor'] is Map ? r['actor']['email'] ?? '' : ''}')
              .toLowerCase()
              .contains(_search.toLowerCase()) &&
          (_action == 'all' || r['action'] == _action) &&
          (_actor == 'all' || r['actorId'] == _actor) &&
          (_result == 'all' || eventResult(r['result']) == _result) &&
          (_range == null ||
              day != null &&
                  !day.isBefore(_range!.start) &&
                  day.isBefore(_range!.end.add(const Duration(days: 1))));
    }).toList();
    return LayoutBuilder(
      builder: (context, box) => ListView(
        padding: EdgeInsets.all(box.maxWidth < 600 ? 16 : 28),
        children: [
          AdminPageHeading(
            title: widget.reports
                ? 'Reportes y moderación'
                : 'Una historia transparente',
            subtitle: widget.reports
                ? 'Revisa con contexto. Decide con cuidado.'
                : 'Acciones reales, identidades autorizadas y trazabilidad.',
            icon: widget.reports ? Icons.flag_outlined : Icons.history_rounded,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: box.maxWidth < 600 ? box.maxWidth - 32 : 300,
                child: TextField(
                  decoration: InputDecoration(
                    labelText: widget.reports
                        ? 'Buscar por persona'
                        : 'Buscar en esta página',
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              if (widget.reports)
                AdminSelect(
                  label: 'Estado del reporte',
                  value: _status,
                  options: reportStatuses,
                  onChanged: (v) {
                    setState(() {
                      _status = v;
                      _page = 0;
                      _history
                        ..clear()
                        ..add(null);
                    });
                    _load();
                  },
                ),
              if (!widget.reports) ...[
                AdminSelect(
                  label: 'Acción',
                  value: _action,
                  options: {
                    'all': 'Todas',
                    for (final r in _rows)
                      if (r['action'] is String)
                        r['action'] as String: eventAction(r['action']),
                  },
                  onChanged: (v) => setState(() => _action = v),
                ),
                AdminSelect(
                  label: 'Actor',
                  value: _actor,
                  options: {
                    'all': 'Todos',
                    for (final r in _rows)
                      if (r['actorId'] is String)
                        r['actorId'] as String: personName(r['actor']),
                  },
                  onChanged: (v) => setState(() => _actor = v),
                ),
                AdminSelect(
                  label: 'Resultado',
                  value: _result,
                  options: const {
                    'all': 'Todos',
                    'Exitosa': 'Exitosa',
                    'Fallida': 'Fallida',
                    'Con advertencia': 'Con advertencia',
                    'No consignado': 'No consignado',
                  },
                  onChanged: (v) => setState(() => _result = v),
                ),
              ],
              OutlinedButton.icon(
                onPressed: _dates,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_range == null ? 'Fechas' : 'Rango seleccionado'),
              ),
              if (_range != null)
                IconButton(
                  tooltip: 'Quitar fechas',
                  onPressed: () => setState(() => _range = null),
                  icon: const Icon(Icons.close),
                ),
              IconButton(
                tooltip: 'Actualizar registros',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '20 registros por página · filtros y búsqueda aplicados a esta página. No se modifican registros históricos.',
              style: TextStyle(fontSize: 11, color: AdminTheme.muted),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) AppNotice(_error!, error: true),
          if (!_busy && rows.isEmpty)
            AppEmptyState(
              title: widget.reports
                  ? 'Nada que revisar aquí'
                  : 'Sin eventos coincidentes',
              message: 'Cambia los filtros o consulta otra página.',
              icon: widget.reports
                  ? Icons.task_alt_rounded
                  : Icons.manage_search_rounded,
            ),
          if (!widget.reports && box.maxWidth >= 900)
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  dataRowMinHeight: 72,
                  dataRowMaxHeight: 88,
                  columns: [
                    for (final c in [
                      'Quién',
                      'Acción / entidad',
                      'Fecha',
                      'Resultado',
                      '',
                    ])
                      DataColumn(label: Text(c)),
                  ],
                  rows: rows
                      .map(
                        (r) => DataRow(
                          onSelectChanged: (_) => _detail(r),
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 190,
                                child: AdminIdentity(
                                  person: Map<String, dynamic>.from(
                                    r['actor'] as Map? ?? {},
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 270,
                                child: Text(
                                  '${eventDescription(r)}\n${r['entity'] is Map ? r['entity']['name'] ?? 'Elemento no disponible' : personName(r['target'])}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                adminDate(r['at']),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            DataCell(
                              Text(
                                eventResult(r['result']),
                                style: TextStyle(
                                  color: r['result'] == 'success'
                                      ? AppColors.green
                                      : r['result'] == 'error'
                                      ? AdminTheme.alert
                                      : AdminTheme.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'Ver evento',
                                onPressed: () => _detail(r),
                                icon: const Icon(Icons.open_in_new, size: 18),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          if (widget.reports || box.maxWidth < 900)
            for (final r in rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.rose,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.reports
                                  ? Icons.flag_outlined
                                  : Icons.history,
                              color: AppColors.wine,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.reports
                                  ? reportReasons[r['reason']] ??
                                        'Motivo no catalogado'
                                  : eventDescription(r),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.reports
                                ? reportStatuses[r['status']] ?? 'No disponible'
                                : eventResult(r['result']),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AdminTheme.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (widget.reports) ...[
                        Text(
                          'Reporta: ${personName(r['reporter'])}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Persona reportada: ${personName(r['reported'])}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (r['details'] != null)
                          Text(
                            r['details'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ] else
                        Text(eventSentence(r)),
                      const SizedBox(height: 10),
                      Text(
                        adminDate(r[widget.reports ? 'createdAt' : 'at']),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AdminTheme.muted,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => _detail(r),
                            child: const Text('Ver detalle'),
                          ),
                          if (widget.reports) ...[
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => widget.onInspect?.call(
                                      r['reportedId'] as String,
                                    ),
                              child: const Text('Consultar / suspender cuenta'),
                            ),
                            if (r['status'] == 'pending') ...[
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _review(r, 'reviewed'),
                                child: const Text('Marcar revisado'),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _review(r, 'dismissed'),
                                child: const Text('Descartar reporte'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Página anterior',
                onPressed: !_busy && _page > 0
                    ? () {
                        setState(() => _page--);
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Página ${_page + 1}', style: const TextStyle(fontSize: 12)),
              IconButton(
                tooltip: 'Página siguiente',
                onPressed: !_busy && _next != null
                    ? () {
                        setState(() {
                          _page++;
                          if (_history.length <= _page) {
                            _history.add(_next);
                          } else {
                            _history[_page] = _next;
                          }
                        });
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _academicSummary(Map<String, dynamic> user) => [
  user['career'] as String? ?? 'Carrera no disponible',
  user['university'],
  user['campus'],
].whereType<String>().join(' · ');

class _PeopleFiltersCard extends StatelessWidget {
  const _PeopleFiltersCard({
    required this.fields,
    required this.onRefresh,
    required this.onClear,
  });

  final List<Widget> fields;
  final VoidCallback? onRefresh, onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              colors.primary.withValues(alpha: .10),
              AdminTheme.surface,
            ),
            AdminTheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: const _FilterIcon(Icons.tune_rounded, size: 42),
        title: Text(
          'Filtros y orden',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text(
          'Refina la lista y define el orden de los resultados',
          style: TextStyle(color: AdminTheme.muted),
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 16.0;
              final twoColumns =
                  constraints.maxWidth >=
                  440 * MediaQuery.textScalerOf(context).scale(1);
              final width = twoColumns
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final field in fields)
                    SizedBox(width: width, child: field),
                ],
              );
            },
          ),
          const Divider(height: 28),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpiar filtros'),
                ),
                FilledButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
