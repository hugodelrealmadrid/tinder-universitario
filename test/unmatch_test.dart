import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/matches/student_match.dart';
import 'package:tinder_universitario/features/matches/unmatch_service.dart';
import 'package:tinder_universitario/features/matches/matches_service.dart';
import 'package:tinder_universitario/features/matches/matches_screen.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';
import 'package:tinder_universitario/features/chat/chat_message.dart';

void main() {
  late FakeFirebaseFirestore db;
  Map<String, dynamic> active() => {
    'users': ['ana', 'bob'],
    'createdAt': Timestamp.fromMillisecondsSinceEpoch(1),
    'isActive': true,
  };
  UnmatchService service([String? uid = 'ana']) =>
      UnmatchService(firestore: db, currentUid: () => uid);
  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.doc('matches/ana.bob').set(active());
    await db.doc('matches/ana.bob/messages/m1').set({
      'senderId': 'ana',
      'text': 'Historial conservado',
      'createdAt': Timestamp.now(),
    });
    await db.doc('swipes/ana.bob').set({'type': 'like'});
  });
  for (final uid in ['ana', 'bob']) {
    test(
      'HU15 participante $uid cierra con campos mínimos y conserva datos',
      () async {
        await service(uid).unmatch('ana.bob');
        final data = (await db.doc('matches/ana.bob').get()).data()!;
        expect(
          data.keys,
          unorderedEquals([
            'users',
            'createdAt',
            'isActive',
            'closedAt',
            'closedBy',
          ]),
        );
        expect(data['isActive'], false);
        expect(data['closedBy'], uid);
        expect(data['closedAt'], isA<Timestamp>());
        expect(data['users'], active()['users']);
        expect(data['createdAt'], active()['createdAt']);
        expect(
          (await db.doc('matches/ana.bob/messages/m1').get()).exists,
          true,
        );
        expect((await db.doc('swipes/ana.bob').get()).exists, true);
      },
    );
  }
  for (final uid in ['carol', null]) {
    test('HU15 servicio rechaza identidad $uid', () async {
      await expectLater(
        service(uid).unmatch('ana.bob'),
        throwsA(isA<UnmatchException>()),
      );
      expect((await db.doc('matches/ana.bob').get()).data(), active());
    });
  }
  test('HU15 segundo cierre rechazado sin cambiar autor o timestamp', () async {
    await service().unmatch('ana.bob');
    final before = (await db.doc('matches/ana.bob').get()).data();
    await expectLater(
      service('bob').unmatch('ana.bob'),
      throwsA(isA<UnmatchException>()),
    );
    expect((await db.doc('matches/ana.bob').get()).data(), before);
  });
  test('HU15 match inexistente e ID no canónico rechazados', () async {
    await expectLater(
      service().unmatch('ana.carol'),
      throwsA(isA<UnmatchException>()),
    );
    await db.doc('matches/bob.ana').set(active());
    await expectLater(
      service().unmatch('bob.ana'),
      throwsA(isA<UnmatchException>()),
    );
  });
  test('HU15 modelo activo existente sin cierre válido', () {
    final pair = StudentMatch.fromMap(active());
    expect(pair.isCoherent, true);
    expect(pair.closedAt, isNull);
    expect(pair.closedBy, isNull);
  });
  test(
    'HU15 solicitudes simultáneas mantienen estado cerrado coherente',
    () async {
      // El fake no modela conflictos MVCC: la suite del emulador comprueba
      // además que solo UN cierre real gana y su autor/fecha no se sobrescriben.
      await Future.wait(
        ['ana', 'bob'].map((uid) async {
          try {
            await service(uid).unmatch('ana.bob');
          } on UnmatchException {
            // La transacción puede observar el cierre confirmado por el otro.
          }
        }),
      );
      final data = (await db.doc('matches/ana.bob').get()).data()!;
      final pair = StudentMatch.fromMap(data);
      expect(pair.isActive, false);
      expect(pair.isCoherent, true);
      expect(pair.users, ['ana', 'bob']);
      expect(data['createdAt'], active()['createdAt']);
      final before = Map<String, dynamic>.from(data);
      await expectLater(
        service().unmatch('ana.bob'),
        throwsA(isA<UnmatchException>()),
      );
      expect((await db.doc('matches/ana.bob').get()).data(), before);
    },
  );
  test('HU15 modelo cerrado válido y coherencia de metadatos', () {
    final closed = {
      ...active(),
      'isActive': false,
      'closedAt': Timestamp.now(),
      'closedBy': 'bob',
    };
    expect(StudentMatch.fromMap(closed).isCoherent, true);
    for (final data in [
      {...active(), 'closedBy': 'ana'},
      {...active(), 'closedAt': Timestamp.now()},
      {...active(), 'isActive': false},
      {...closed, 'closedBy': 'carol'},
      {...closed, 'closedAt': null},
      {
        ...closed,
        'users': ['ana', 'ana'],
      },
    ]) {
      expect(() => StudentMatch.fromMap(data), throwsA(isA<FormatException>()));
    }
  });
  test(
    'HU15 lista activa retira cerrado para ambos y mantiene historial',
    () async {
      final matches = MatchesService(firestore: db);
      expect(await matches.load('ana'), hasLength(1));
      final stream = StreamIterator(matches.watchActiveIds('bob'));
      addTearDown(stream.cancel);
      await stream.moveNext();
      expect(stream.current, contains('ana.bob'));
      await service().unmatch('ana.bob');
      await stream.moveNext();
      expect(stream.current, isEmpty);
      for (final uid in ['ana', 'bob']) {
        expect(await matches.load(uid), isEmpty);
        final chat = ChatService(firestore: db);
        expect((await chat.watchMatch('ana.bob', uid).first).isActive, false);
        expect(
          (await chat.watchMessages('ana.bob').first).single.text,
          'Historial conservado',
        );
        await expectLater(
          chat.send('ana.bob', uid, 'No'),
          throwsA(isA<ChatException>()),
        );
      }
    },
  );
  Future<void> open(WidgetTester tester, UnmatchService closing) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          matchId: 'ana.bob',
          uid: 'ana',
          service: ChatService(firestore: db),
          unmatchService: closing,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshacer match'));
    await tester.pumpAndSettle();
  }

  testWidgets('HU15 Cancelar no ejecuta cierre', (tester) async {
    final closing = _ControlledUnmatch(db);
    await open(tester, closing);
    expect(find.text('¿Deshacer match?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(closing.calls, 0);
    expect((await db.doc('matches/ana.bob').get()).data()!['isActive'], true);
  });
  testWidgets('HU15 confirmación ejecuta una vez y deshabilita envío a 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final closing = _ControlledUnmatch(db)..pending = Completer<void>();
    await open(tester, closing);
    await tester.tap(find.byKey(const ValueKey('confirm-unmatch')));
    await tester.pumpAndSettle();
    expect(closing.calls, 1);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-send')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const ValueKey('chat-options')),
          )
          .enabled,
      false,
    );
    closing.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Este match ha finalizado'), findsOneWidget);
    expect(find.text('Historial conservado'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-options')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-draft')))
          .enabled,
      false,
    );
    expect(find.text('ana'), findsNothing);
    expect(find.text('closedBy'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('HU15 error muestra feedback sin cerrar ni borrar historial', (
    tester,
  ) async {
    final closing = _ControlledUnmatch(db)..fail = true;
    await open(tester, closing);
    await tester.tap(find.byKey(const ValueKey('confirm-unmatch')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo deshacer'), findsOneWidget);
    expect(find.text('Historial conservado'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-draft')))
          .enabled,
      true,
    );
    expect((await db.doc('matches/ana.bob').get()).data()!['isActive'], true);
  });
  testWidgets('HU15 cierre desde chat vuelve a Matches sin entrada cerrada', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatchesScreen(
          uid: 'ana',
          service: MatchesService(firestore: db),
          chatService: ChatService(firestore: db),
          unmatchService: service(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MatchTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshacer match'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-unmatch')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(MatchTile), findsNothing);
    expect(find.text('Todavía no tienes matches.'), findsOneWidget);
  });
  testWidgets(
    'HU15 otro participante en Matches ve desaparecer cierre sin recargar',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MatchesScreen(
            uid: 'bob',
            service: MatchesService(firestore: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MatchTile), findsOneWidget);
      await service().unmatch('ana.bob');
      await tester.pumpAndSettle();
      expect(find.byType(MatchTile), findsNothing);
    },
  );
}

class _ControlledUnmatch extends UnmatchService {
  _ControlledUnmatch(FirebaseFirestore db)
    : super(firestore: db, currentUid: () => 'ana');
  int calls = 0;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> unmatch(String matchId) async {
    calls++;
    if (fail) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    if (pending != null) await pending!.future;
    await super.unmatch(matchId);
  }
}
