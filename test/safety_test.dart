import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/safety/safety_models.dart';
import 'package:tinder_universitario/features/safety/safety_service.dart';
import 'package:tinder_universitario/features/safety/safety_dialog.dart';
import 'package:tinder_universitario/features/discovery/discovery_service.dart';
import 'package:tinder_universitario/features/discovery/discovery_screen.dart';
import 'package:tinder_universitario/features/discovery/discovery_publication.dart';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';
import 'package:tinder_universitario/features/matches/matches_service.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';
import 'package:tinder_universitario/features/chat/chat_message.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';

void main() {
  late _PermissionFirestore db;
  SafetyService service([String? uid = 'ana']) =>
      SafetyService(firestore: db, currentUid: () => uid);
  Future<void> pair() => db.doc('matches/ana.bob').set({
    'users': ['ana', 'bob'],
    'createdAt': Timestamp.fromMillisecondsSinceEpoch(1),
    'isActive': true,
  });
  setUp(() async {
    db = _PermissionFirestore();
    final now = DateTime.now().toUtc();
    await db.doc('careers/sistemas').set({
      'name': 'Sistemas',
      'isActive': true,
    });
    for (final uid in ['ana', 'bob']) {
      final user = <String, dynamic>{
        'firstName': uid == 'ana' ? 'Ana' : 'Roberto',
        'lastName': 'Prueba',
        'email': '$uid@example.com',
        'birthDate': Timestamp.fromDate(
          DateTime.utc(now.year - 22, now.month, now.day),
        ),
        'gender': 'femenino',
        'description': '',
        'careerId': 'sistemas',
        'photoUrls': ['https://example.test/photo.jpg'],
        'mainPhotoUrl': 'https://example.test/photo.jpg',
        'interestIds': <String>[],
        'isActive': true,
        'role': 'user',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      };
      await db.doc('users/$uid').set(user);
      await db.doc('discoveryCards/$uid').set(DiscoveryPublication.card(user));
      await db.doc('discoveryIndex/$uid').set({
        'isActive': true,
        'updatedAt': user['updatedAt'],
      });
      await db
          .doc('preferences/$uid')
          .set(
            const DiscoveryPreferences(
              minAge: 18,
              maxAge: 100,
              preferredGender: PreferredGender.both,
            ).toFirestore(),
          );
    }
  });
  test('HU16 ID direccional estable y distinto del inverso', () {
    expect(SafetyIds.idFor('ana', 'bob'), 'ana.bob');
    expect(SafetyIds.idFor('bob', 'ana'), 'bob.ana');
  });
  test(
    'HU16 bloqueo sin match exacto, sin reporte ni cambios a users',
    () async {
      final before = (await db.doc('users/bob').get()).data();
      expect(await service().block('bob'), true);
      final block = (await db.doc('blocks/ana.bob').get()).data()!;
      expect(
        block.keys,
        unorderedEquals(['blockerId', 'blockedId', 'createdAt']),
      );
      expect(block['blockerId'], 'ana');
      expect(block['blockedId'], 'bob');
      expect(block['createdAt'], isA<Timestamp>());
      expect((await db.collection('matches').get()).docs, isEmpty);
      expect((await db.collection('reports').get()).docs, isEmpty);
      expect((await db.doc('users/bob').get()).data(), before);
    },
  );
  test('HU16 duplicado idempotente conserva timestamp', () async {
    await service().block('bob');
    final before = (await db.doc('blocks/ana.bob').get()).data();
    expect(await service().block('bob'), false);
    expect((await db.doc('blocks/ana.bob').get()).data(), before);
  });
  for (final uid in ['ana', null]) {
    test('HU16 self/identidad $uid rechazada', () async {
      await expectLater(
        service(uid).block('ana'),
        throwsA(isA<SafetyException>()),
      );
      expect((await db.collection('blocks').get()).docs, isEmpty);
    });
  }
  test(
    'HU16 bloquea y cierra match con semántica HU15 sin borrar historial/swipes',
    () async {
      await pair();
      await ChatService(firestore: db).send('ana.bob', 'ana', 'Historial');
      await db.doc('swipes/ana.bob').set({'type': 'like'});
      await service().block('bob');
      final data = (await db.doc('matches/ana.bob').get()).data()!;
      expect(data['isActive'], false);
      expect(data['closedBy'], 'ana');
      expect(data['closedAt'], isA<Timestamp>());
      expect(data['createdAt'], Timestamp.fromMillisecondsSinceEpoch(1));
      expect(data['users'], ['ana', 'bob']);
      expect(
        (await ChatService(
          firestore: db,
        ).watchMessages('ana.bob').first).single.text,
        'Historial',
      );
      expect((await db.doc('swipes/ana.bob').get()).exists, true);
      expect(await MatchesService(firestore: db).load('ana'), isEmpty);
      expect(await MatchesService(firestore: db).load('bob'), isEmpty);
      await expectLater(
        ChatService(firestore: db).send('ana.bob', 'bob', 'No'),
        throwsA(isA<ChatException>()),
      );
    },
  );
  test('HU16 bloqueo de match cerrado no sobrescribe cierre', () async {
    await pair();
    await db.doc('matches/ana.bob').update({
      'isActive': false,
      'closedBy': 'bob',
      'closedAt': Timestamp.now(),
    });
    final before = (await db.doc('matches/ana.bob').get()).data();
    await service().block('bob');
    expect((await db.doc('matches/ana.bob').get()).data(), before);
  });
  test(
    'HU16 envío cliente rechaza bloqueo propio aunque match esté activo',
    () async {
      await service().block('bob');
      await pair();
      await expectLater(
        ChatService(firestore: db).send('ana.bob', 'ana', 'No'),
        throwsA(isA<ChatException>()),
      );
    },
  );
  test('HU16 Discovery excluye bloqueo propio y nuevos LIKE/PASS', () async {
    await service().block('bob');
    final discovery = DiscoveryService(firestore: db);
    await discovery.start('ana');
    expect(await discovery.next(), isNull);
    for (final type in ['like', 'pass']) {
      await expectLater(
        discovery.decide('ana', 'bob', type),
        throwsA(isA<DiscoveryException>()),
      );
    }
  });
  test(
    'HU16 Discovery omite ficha denegada por bloqueo inverso sin leer ese bloqueo',
    () async {
      await service().block('bob');
      // Simula la respuesta de Rules; el emulador verifica la regla bidireccional real.
      db.deniedReads.addAll(['discoveryCards/ana', 'blocks/ana.bob']);
      final discovery = DiscoveryService(firestore: db);
      await discovery.start('bob');
      expect(await discovery.next(), isNull);
    },
  );
  for (final reason in ReportReasons.labels.keys) {
    test('HU17 serializa motivo controlado $reason y campos exactos', () async {
      await service().report('bob', reason, '  Detalle  ');
      final data = (await db.doc('reports/ana.bob').get()).data()!;
      expect(
        data.keys,
        unorderedEquals([
          'reporterId',
          'reportedId',
          'reason',
          'details',
          'createdAt',
          'status',
        ]),
      );
      expect(data['reason'], reason);
      expect(data['details'], 'Detalle');
      expect(data['status'], 'pending');
      expect(data['createdAt'], isA<Timestamp>());
    });
  }
  test('HU17 self-report y anónimo rechazados', () async {
    await expectLater(
      service().report('ana', 'spam', ''),
      throwsA(isA<SafetyException>()),
    );
    await expectLater(
      service(null).report('bob', 'spam', ''),
      throwsA(isA<SafetyException>()),
    );
  });
  test(
    'HU17 motivo inválido y detalles largos rechazados sin escribir',
    () async {
      await expectLater(
        service().report('bob', 'libre', ''),
        throwsA(isA<SafetyException>()),
      );
      await expectLater(
        service().report('bob', 'spam', 'x' * 501),
        throwsA(isA<SafetyException>()),
      );
      expect((await db.collection('reports').get()).docs, isEmpty);
    },
  );
  test('HU17 detalles opcionales y reporte no bloquea ni cierra', () async {
    await pair();
    await service().report('bob', 'spam', '');
    expect((await db.doc('reports/ana.bob').get()).data()!['details'], '');
    expect((await db.collection('blocks').get()).docs, isEmpty);
    expect((await db.doc('matches/ana.bob').get()).data()!['isActive'], true);
  });
  test(
    'HU17 duplicado denegado se informa sin leer reportes ni sobrescribir',
    () async {
      await service().report('bob', 'spam', 'Original');
      // El fake no distingue CREATE/UPDATE en set; simulamos el rechazo.
      // La prohibición real del duplicado y GET se prueba contra el emulador.
      db.deniedWrites.add('reports/ana.bob');
      db.deniedReads.add('reports/ana.bob');
      await expectLater(
        service().report('bob', 'other', 'Cambio'),
        throwsA(isA<SafetyException>()),
      );
      expect(db.dump(), contains('Original'));
      expect(db.dump(), isNot(contains('Cambio')));
    },
  );

  Future<void> openDialog(
    WidgetTester tester,
    SafetyAction action,
    SafetyService closing,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final done = await showSafetyDialog(
                  context,
                  target: 'bob',
                  action: action,
                  service: closing,
                );
                if (done && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        action == SafetyAction.report
                            ? 'Reporte enviado.'
                            : 'Usuario bloqueado.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('report-reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam').last);
    await tester.pumpAndSettle();
  }

  for (final action in SafetyAction.values) {
    testWidgets('Cancelar $action no escribe', (tester) async {
      final controlled = _ControlledSafety(db);
      await openDialog(tester, action, controlled);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(controlled.blocks, 0);
      expect(controlled.reports, 0);
    });
    testWidgets('Confirmar $action una vez, loading y 360px sin overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controlled = _ControlledSafety(db)..pending = Completer<void>();
      await openDialog(tester, action, controlled);
      if (action == SafetyAction.report) await choose(tester);
      final callback = tester
          .widget<FilledButton>(find.byKey(const ValueKey('safety-submit')))
          .onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(controlled.blocks + controlled.reports, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('safety-submit')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      controlled.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(
          action == SafetyAction.block
              ? 'Usuario bloqueado.'
              : 'Reporte enviado.',
        ),
        findsOneWidget,
      );
      expect(
        (await db
                .collection(action == SafetyAction.block ? 'reports' : 'blocks')
                .get())
            .docs,
        isEmpty,
      );
    });
    testWidgets('Error $action conserva diálogo y permite reintentar', (
      tester,
    ) async {
      final controlled = _ControlledSafety(db)..fail = true;
      await openDialog(tester, action, controlled);
      if (action == SafetyAction.report) await choose(tester);
      await tester.tap(find.byKey(const ValueKey('safety-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Revisa tu conexión'), findsOneWidget);
      expect(find.byType(SafetyDialog), findsOneWidget);
      controlled.fail = false;
      await tester.tap(find.byKey(const ValueKey('safety-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(SafetyDialog), findsNothing);
    });
  }
  testWidgets('HU17 selector obligatorio, no motivo de texto libre', (
    tester,
  ) async {
    await openDialog(tester, SafetyAction.report, service());
    await tester.tap(find.byKey(const ValueKey('safety-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona un motivo.'), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget); // Solo detalles.
    expect((await db.collection('reports').get()).docs, isEmpty);
  });
  testWidgets('Discovery bloquear retira inmediatamente tarjeta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          uid: 'ana',
          onPreferences: () {},
          onProfile: () {},
          service: DiscoveryService(firestore: db),
          safetyService: service(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Roberto, 22'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discovery-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquear usuario'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('safety-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Roberto, 22'), findsNothing);
    expect(find.text('Usuario bloqueado.'), findsOneWidget);
  });
  testWidgets(
    'Chat ofrece ambas acciones y reporte no deshabilita conversación',
    (tester) async {
      await pair();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            matchId: 'ana.bob',
            uid: 'ana',
            service: ChatService(firestore: db),
            safetyService: service(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-options')));
      await tester.pumpAndSettle();
      expect(find.text('Bloquear usuario'), findsOneWidget);
      await tester.tap(find.text('Reportar usuario'));
      await tester.pumpAndSettle();
      await choose(tester);
      await tester.tap(find.byKey(const ValueKey('safety-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Reporte enviado.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-draft')))
            .enabled,
        true,
      );
    },
  );
}

class _ControlledSafety extends SafetyService {
  _ControlledSafety(FirebaseFirestore db)
    : super(firestore: db, currentUid: () => 'ana');
  int blocks = 0, reports = 0;
  bool fail = false;
  Completer<void>? pending;
  Future<void> wait() async {
    if (fail) throw StateError('offline');
    if (pending != null) await pending!.future;
  }

  @override
  Future<bool> block(String target) async {
    blocks++;
    await wait();
    return super.block(target);
  }

  @override
  Future<void> report(String target, String reason, String details) async {
    reports++;
    await wait();
    await super.report(target, reason, details);
  }
}

// Adapta únicamente la respuesta del backend a FirebaseException. El fake
// básico lanza Exception genérica y no interpreta las Rules de producción.
class _PermissionFirestore extends FakeFirebaseFirestore {
  final Set<String> deniedReads = {}, deniedWrites = {};
  @override
  Future<void> maybeThrowSecurityException(String path, dynamic method) async {
    if ((method.toString() == 'Method.read' && deniedReads.contains(path)) ||
        (method.toString() == 'Method.write' && deniedWrites.contains(path))) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    await super.maybeThrowSecurityException(path, method);
  }
}
