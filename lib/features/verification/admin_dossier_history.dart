import 'package:flutter/material.dart';
import 'admin_dossier_photo.dart';
import 'admin_theme.dart';
import 'audit_presentation.dart';
import 'backend_client.dart';
import 'university_verification_screen.dart' show statusLabel;

enum DossierHistoryKind {
  matches('Relaciones', Icons.people_outline),
  conversations('Conversaciones', Icons.chat_bubble_outline),
  likesSent('Likes enviados', Icons.favorite_outline),
  likesReceived('Likes recibidos', Icons.favorite),
  reportsReceived('Reportes recibidos', Icons.flag_outlined),
  reportsSent('Reportes realizados', Icons.outlined_flag),
  verifications('Verificaciones', Icons.verified_outlined),
  audit('Auditoría', Icons.history);

  const DossierHistoryKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AdminDossierHistory extends StatefulWidget {
  const AdminDossierHistory({
    super.key,
    required this.uid,
    required this.client,
    required this.canReadAudit,
  });

  final String uid;
  final VerificationClient client;
  final bool canReadAudit;

  @override
  State<AdminDossierHistory> createState() => _AdminDossierHistoryState();
}

class _AdminDossierHistoryState extends State<AdminDossierHistory> {
  DossierHistoryKind _kind = DossierHistoryKind.matches;
  final _pages = <String?>[null];
  late var _page = _load();

  Future<({Map<String, dynamic>? data, Object? error})> _load() async {
    try {
      return (
        data: await widget.client.dossierHistory(
          widget.uid,
          _kind.name,
          cursor: _pages.last,
        ),
        error: null,
      );
    } catch (error) {
      return (data: null, error: error);
    }
  }

  void _select(DossierHistoryKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _pages
        ..clear()
        ..add(null);
      _page = _load();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final kind in DossierHistoryKind.values)
            if (kind != DossierHistoryKind.audit || widget.canReadAudit)
              ChoiceChip(
                avatar: Icon(kind.icon, size: 16),
                label: Text(kind.label),
                selected: kind == _kind,
                onSelected: (_) => _select(kind),
              ),
        ],
      ),
      const SizedBox(height: 14),
      FutureBuilder(
        future: _page,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator(
              semanticsLabel: 'Cargando historial',
            );
          }
          final response = snapshot.requireData;
          if (response.error != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(verificationError(response.error!)),
                TextButton(
                  onPressed: () => setState(() {
                    _page = _load();
                  }),
                  child: const Text('Reintentar historial'),
                ),
              ],
            );
          }
          final page = response.data!;
          final rows = (page['items'] as List).cast<Map<String, dynamic>>();
          final next = page['nextCursor'] as String?;
          final maxMessages = rows.fold<int>(0, (max, row) {
            final n = row['messages'];
            return n is int && n > max ? n : max;
          });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty)
                Text(
                  'No hay registros fechados en ${_kind.label.toLowerCase()}.',
                ),
              for (final row in rows) _row(row, maxMessages),
              if (_pages.length > 1 || next != null)
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _pages.length == 1
                          ? null
                          : () => setState(() {
                              _pages.removeLast();
                              _page = _load();
                            }),
                      child: const Text('Anterior'),
                    ),
                    Text('Página ${_pages.length}'),
                    OutlinedButton(
                      onPressed: next == null
                          ? null
                          : () => setState(() {
                              _pages.add(next);
                              _page = _load();
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

  Widget _row(Map<String, dynamic> row, int maxMessages) {
    final person = row['person'] as Map?;
    final photo = person?['photoPath'] as String?;
    final name = personName(person);
    final isMatch =
        _kind == DossierHistoryKind.matches ||
        _kind == DossierHistoryKind.conversations;
    final title = switch (_kind) {
      DossierHistoryKind.audit => eventAction(row['action']),
      DossierHistoryKind.verifications => statusLabel(row['status'] as String?),
      DossierHistoryKind.reportsReceived || DossierHistoryKind.reportsSent =>
        reportReasons[row['reason']] ?? 'Motivo no disponible',
      _ => name,
    };
    final messages = row['messages'] as int?;
    final details = [
      if (isMatch)
        switch (row['active']) {
          true => 'Match activo',
          false => 'Match cerrado',
          _ => 'Estado no disponible',
        },
      if (row['closedAt'] != null) 'Cierre · ${adminDate(row['closedAt'])}',
      if (_kind == DossierHistoryKind.conversations) ...[
        messages == null
            ? 'Cantidad de mensajes no disponible'
            : '$messages mensajes',
        if (messages != 0) ...[
          'Primer mensaje · ${adminDate(row['firstMessageAt'])}',
          'Último mensaje · ${adminDate(row['lastMessageAt'])}',
        ],
      ],
      if (_kind == DossierHistoryKind.reportsReceived ||
          _kind == DossierHistoryKind.reportsSent) ...[
        '${_kind == DossierHistoryKind.reportsReceived ? 'Denunciante' : 'Persona reportada'} · $name',
        reportStatuses[row['status']] ?? 'Estado no disponible',
      ],
      if (row['reviewedAt'] != null)
        'Resuelto · ${adminDate(row['reviewedAt'])} · ${personName(row['reviewer'])}',
      if (_kind == DossierHistoryKind.audit)
        '${personName(row['actor'])} · ${eventResult(row['result'])}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo != null)
            SizedBox.square(
              dimension: 48,
              child: AdminDossierPhoto(
                key: ValueKey(photo),
                path: photo,
                load: widget.client.administrationPhoto,
                label: 'Foto de $name',
              ),
            )
          else
            SizedBox(width: 32, child: Icon(_kind.icon, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  adminDate(row['date']),
                  style: const TextStyle(color: AdminTheme.muted),
                ),
                for (final detail in details) Text(detail),
                if (messages != null && maxMessages > 0) ...[
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: messages / maxMessages,
                    semanticsLabel:
                        'Mensajes respecto al mayor conteo de esta página',
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
