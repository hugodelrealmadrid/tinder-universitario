import 'package:flutter/material.dart';
import '../../widgets/app_ui.dart';
import 'admin_theme.dart';
import 'audit_presentation.dart';
import 'backend_client.dart';

class AdminOverview extends StatefulWidget {
  const AdminOverview({
    super.key,
    required this.client,
    required this.onNavigate,
    this.showAudit = false,
  });

  final VerificationClient client;
  final ValueChanged<String> onNavigate;
  final bool showAudit;

  @override
  State<AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<AdminOverview> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _events = [];
  String? _error, _activityError;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showAudit != widget.showAudit ||
        oldWidget.client != widget.client) {
      _summary = null;
      _events = [];
      _load();
    }
  }

  int? _count(String key) {
    final value = _summary?[key];
    return value is int && value >= 0 ? value : null;
  }

  Future<void> _load() async {
    final client = widget.client;
    final audit = widget.showAudit;
    bool current() =>
        mounted && client == widget.client && audit == widget.showAudit;
    setState(() {
      _busy = true;
      _error = null;
      _activityError = null;
    });
    try {
      final summary = await client.administrationSummary();
      if (!current()) return;
      setState(() => _summary = summary);
      if (audit) {
        try {
          final page = await client.eventFeed();
          final rows =
              (page['items'] as List? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList()
                ..sort(
                  (a, b) => (b['at'] as String? ?? '').compareTo(
                    a['at'] as String? ?? '',
                  ),
                );
          if (current()) setState(() => _events = rows.take(4).toList());
        } catch (error) {
          if (current()) {
            setState(() {
              _events = [];
              _activityError = verificationError(error);
            });
          }
        }
      }
    } catch (error) {
      if (current()) {
        setState(() {
          _summary = null;
          _events = [];
          _error = verificationError(error);
        });
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  static const _metrics = [
    ('totalUsers', 'Usuarios registrados', Icons.people_outline, 'users'),
    (
      'verified',
      'Acreditaciones aprobadas',
      Icons.verified_outlined,
      'requests',
    ),
    (
      'pendingRequests',
      'Solicitudes por revisar',
      Icons.assignment_outlined,
      'requests',
    ),
    ('reports', 'Reportes abiertos', Icons.flag_outlined, 'reports'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListView(
      padding: EdgeInsets.all(compact ? 16 : 28),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF241535), Color(0xFF14121D)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AdminTheme.border),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VISTA GENERAL',
                        style: TextStyle(
                          color: Color(0xFFF0BEFF),
                          letterSpacing: 1.5,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'El pulso de tu comunidad',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Gestiona la comunidad, las acreditaciones y los reportes.',
                        style: TextStyle(color: AdminTheme.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar estadísticas',
                  color: const Color(0xFFF0BEFF),
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_busy)
          const LinearProgressIndicator(semanticsLabel: 'Cargando resumen'),
        if (_error != null) AppNotice(_error!, error: true),
        if (_summary != null) ...[
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 1080
                  ? 4
                  : box.maxWidth >= 290
                  ? 2
                  : 1;
              const gap = 12.0;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in _metrics)
                    SizedBox(
                      width: (box.maxWidth - gap * (columns - 1)) / columns,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => widget.onNavigate(metric.$4),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(metric.$3, color: colors.primary),
                                const SizedBox(height: 10),
                                Text(
                                  _count(metric.$1)?.toString() ?? '—',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  metric.$2,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _OverviewPanel(
            title: 'Estado de acreditación',
            child: _accreditation(context),
          ),
          if (widget.showAudit)
            _OverviewPanel(
              title: 'Actividad de auditoría',
              action: TextButton(
                onPressed: () => widget.onNavigate('audit'),
                child: const Text('Ver auditoría'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_activityError != null)
                    AppNotice(_activityError!, error: true),
                  if (_events.isEmpty && !_busy && _activityError == null)
                    const Text('No hay acciones en la página consultada.'),
                  for (final event in _events)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(eventSentence(event)),
                      subtitle: Text(
                        '${adminDate(event['at'])} · ${eventResult(event['result'])}',
                      ),
                    ),
                  if (_events.isNotEmpty)
                    const Text(
                      'Acciones más recientes de la página consultada.',
                      style: TextStyle(color: AdminTheme.muted, fontSize: 12),
                    ),
                ],
              ),
            )
          else
            _OverviewPanel(
              title: 'Cola de revisión',
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => widget.onNavigate('requests'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Revisar solicitudes'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onNavigate('reports'),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Revisar reportes'),
                  ),
                ],
              ),
            ),
          if (_summary!['generatedAt'] != null)
            Text(
              'Consultado · ${adminDate(_summary!['generatedAt'])}',
              style: const TextStyle(color: AdminTheme.muted, fontSize: 12),
            ),
        ],
      ],
    );
  }

  Widget _accreditation(BuildContext context) {
    final values = [_count('verified'), _count('pending'), _count('rejected')];
    if (values.contains(null)) return const Text('Distribución no disponible.');
    final counts = values.cast<int>();
    final total = counts.fold(0, (sum, count) => sum + count);
    if (total == 0) {
      return const Text('Todavía no hay acreditaciones registradas.');
    }
    const labels = ['Aprobadas', 'Pendientes', 'Rechazadas'];
    const colors = [Color(0xFF76DBB2), Color(0xFFD4A2FF), Color(0xFFFFA5B2)];
    return Column(
      children: [
        for (var i = 0; i < counts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(labels[i])),
                    Text('${counts[i]}'),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: counts[i] / total,
                  semanticsLabel: labels[i],
                  color: colors[i],
                  backgroundColor: AdminTheme.border,
                  borderRadius: BorderRadius.circular(8),
                  minHeight: 7,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
