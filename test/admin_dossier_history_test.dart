import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/verification/admin_dossier_history.dart';
import 'package:tinder_universitario/features/verification/backend_client.dart';

import 'verification_fixtures.dart';

class _HistoryClient extends FakeVerificationClient {
  _HistoryClient();
  final historyCalls = <(String, String?)>[];
  bool failed = false;

  @override
  Future<Map<String, dynamic>> dossierHistory(
    String uid,
    String kind, {
    String? cursor,
  }) async {
    historyCalls.add((kind, cursor));
    if (kind == 'conversations' && !failed) {
      failed = true;
      throw const VerificationFailure('permission-denied');
    }
    if (kind == 'reportsReceived') return {'items': <Map<String, dynamic>>[]};
    return {
      'items': <Map<String, dynamic>>[
        {
          'person': {'name': cursor == null ? 'Alma Ríos' : 'Bruno Vega'},
          'active': true,
          'date': '2026-11-07T14:00:00Z',
          'messages': null,
        },
      ],
      if (kind == 'matches' && cursor == null) 'nextCursor': 'next-opaque',
    };
  }
}

void main() {
  testWidgets('Pagina, vuelve, distingue error y dato desconocido en móvil', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _HistoryClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDossierHistory(
            uid: 'fixture',
            client: client,
            canReadAudit: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alma Ríos'), findsOneWidget);
    expect(find.text('Auditoría'), findsNothing);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Bruno Vega'), findsOneWidget);
    expect(client.historyCalls.last, ('matches', 'next-opaque'));
    await tester.tap(find.text('Anterior'));
    await tester.pumpAndSettle();
    expect(client.historyCalls.last, ('matches', null));
    await tester.tap(find.text('Conversaciones'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No tienes autorización'), findsOneWidget);
    await tester.tap(find.text('Reintentar historial'));
    await tester.pumpAndSettle();
    expect(find.text('Cantidad de mensajes no disponible'), findsOneWidget);
    await tester.tap(find.text('Reportes recibidos'));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay registros fechados en reportes recibidos.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
