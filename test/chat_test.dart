import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/chat/chat_message.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';
import 'package:tinder_universitario/features/discovery/discovery_models.dart';
import 'package:tinder_universitario/features/matches/matches_screen.dart';
import 'package:tinder_universitario/features/matches/matches_service.dart';
import 'package:tinder_universitario/features/matches/student_match.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ChatService service;
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = ChatService(firestore: db);
    await db.doc('matches/ana.bob').set({
      'users': ['ana', 'bob'],
      'isActive': true,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1),
    });
  });

  Future<void> seedMessage(int time, {String sender = 'ana'}) =>
      db.doc('matches/ana.bob/messages/m$time').set({
        'senderId': sender,
        'text': 'Mensaje $time',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(time),
      });

  Future<void> open(WidgetTester tester, {ChatService? replacement}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          matchId: 'ana.bob',
          uid: 'ana',
          profile: const DiscoveryCandidate(
            id: 'bob',
            firstName: 'Roberto',
            age: 22,
            gender: 'masculino',
            careerId: 'sistemas',
            mainPhotoUrl: '',
            description: '',
            interestIds: [],
            isActive: true,
          ),
          service: replacement ?? service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'Mensaje válido persiste solo los tres campos y timestamp del servidor',
    () async {
      await service.send('ana.bob', 'ana', 'Hola');
      final rows = (await db.collection('matches/ana.bob/messages').get()).docs;
      expect(rows, hasLength(1));
      expect(
        rows.single.data().keys,
        unorderedEquals(['senderId', 'text', 'createdAt']),
      );
      expect(rows.single.data()['senderId'], 'ana');
      expect(rows.single.data()['text'], 'Hola');
      expect(rows.single.data()['createdAt'], isA<Timestamp>());
    },
  );

  for (final entry in [
    ('vacío', ''),
    ('solo espacios', ' \t\n '),
    ('espacios Unicode', '\u00a0\u2000\u202f\ufeff'),
    ('mayor al máximo', 'a' * (ChatLimits.maxTextLength + 1)),
  ]) {
    test('Rechaza mensaje ${entry.$1} sin escribir', () async {
      await expectLater(
        service.send('ana.bob', 'ana', entry.$2),
        throwsA(isA<ChatException>()),
      );
      expect(
        (await db.collection('matches/ana.bob/messages').get()).docs,
        isEmpty,
      );
    });
  }

  test('Trim conserva espacios y saltos de línea internos', () async {
    await service.send('ana.bob', 'bob', ' \n Hola  Ana\n¿Cómo estás? \t');
    final row = (await service.watchMessages('ana.bob').first).single;
    expect(row.text, 'Hola  Ana\n¿Cómo estás?');
    expect(row.senderId, 'bob');
  });

  test('Límite de 1000 admite Unicode y rechaza el siguiente carácter', () {
    expect(
      ChatLimits.normalize('😀' * (ChatLimits.maxTextLength ~/ 2)).length,
      ChatLimits.maxTextLength,
    );
    expect(
      () => ChatLimits.normalize('😀' * (ChatLimits.maxTextLength ~/ 2 + 1)),
      throwsA(isA<ChatException>()),
    );
  });

  test(
    'Historial ordenado ASC aunque las escrituras lleguen desordenadas',
    () async {
      for (final time in [30, 10, 20]) {
        await seedMessage(time);
      }
      expect(
        (await service.watchMessages('ana.bob').first).map((m) => m.text),
        ['Mensaje 10', 'Mensaje 20', 'Mensaje 30'],
      );
    },
  );

  test(
    'Consulta solo los últimos 50, también cuando llega un mensaje nuevo',
    () async {
      for (var time = 1; time <= 55; time++) {
        await seedMessage(time);
      }
      final iterator = StreamIterator(service.watchMessages('ana.bob'));
      addTearDown(iterator.cancel);
      await iterator.moveNext();
      expect(iterator.current, hasLength(ChatLimits.historyLimit));
      expect(iterator.current.first.text, 'Mensaje 6');
      expect(iterator.current.last.text, 'Mensaje 55');
      await seedMessage(56);
      await iterator.moveNext();
      expect(iterator.current, hasLength(ChatLimits.historyLimit));
      expect(iterator.current.first.text, 'Mensaje 7');
      expect(iterator.current.last.text, 'Mensaje 56');
    },
  );

  test('Usuario propio identificado por senderId', () {
    const message = ChatMessage(
      id: 'm',
      senderId: 'ana',
      text: 'Hola',
      createdAt: null,
    );
    expect(message.isOwn('ana'), isTrue);
    expect(message.isOwn('bob'), isFalse);
  });

  test('Timestamp local pendiente no rompe el modelo', () {
    final message = ChatMessage.fromMap('m', {
      'senderId': 'ana',
      'text': 'Hola',
      'createdAt': null,
    });
    expect(message.createdAt, isNull);
  });

  test('Match inactivo bloquea envío y conserva historial', () async {
    await seedMessage(1);
    await db.doc('matches/ana.bob').update({
      'isActive': false,
      'closedAt': Timestamp.now(),
      'closedBy': 'ana',
    });
    await expectLater(
      service.send('ana.bob', 'ana', 'No'),
      throwsA(isA<ChatException>()),
    );
    expect(
      (await service.watchMessages('ana.bob').first).single.text,
      'Mensaje 1',
    );
  });

  test('Match inexistente o ajeno bloquea envío antes de escribir', () async {
    await expectLater(
      service.send('ana.carol', 'ana', 'No'),
      throwsA(isA<ChatException>()),
    );
    await expectLater(
      service.send('ana.bob', 'carol', 'No'),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await db.collection('matches/ana.bob/messages').get()).docs,
      isEmpty,
    );
  });

  test(
    'Nueva instancia recupera historial persistido de ambos participantes',
    () async {
      await service.send('ana.bob', 'ana', 'Hola');
      await service.send('ana.bob', 'bob', 'Hola Ana');
      final reopened = ChatService(firestore: db);
      expect(
        (await reopened.watchMessages('ana.bob').first).map((m) => m.text),
        containsAll(['Hola', 'Hola Ana']),
      );
    },
  );

  testWidgets('Chat vacío muestra invitación y no datos privados', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Aún no hay mensajes. ¡Saluda!'), findsOneWidget);
    expect(find.text('Roberto'), findsOneWidget);
    for (final private in ['ana', 'bob', 'ana.bob', 'birthDate', 'sistemas']) {
      expect(find.text(private), findsNothing);
    }
  });

  testWidgets('Error de envío conserva el borrador y habilita reintento', (
    tester,
  ) async {
    final failing = _ControlledSend(db)..fail = true;
    await open(tester, replacement: failing);
    await tester.enterText(
      find.byKey(const ValueKey('chat-draft')),
      '  Hola Bob  ',
    );
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('  Hola Bob  '), findsOneWidget);
    expect(find.textContaining('Revisa tu conexión'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-send')))
          .onPressed,
      isNotNull,
    );
    failing.fail = false;
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(
      (await service.watchMessages('ana.bob').first).single.text,
      'Hola Bob',
    );
  });

  testWidgets(
    'Guardia síncrona impide doble envío y limpia solo al confirmar',
    (tester) async {
      final sending = _ControlledSend(db)..pending = Completer<void>();
      await open(tester, replacement: sending);
      await tester.enterText(
        find.byKey(const ValueKey('chat-draft')),
        'Un solo envío',
      );
      final callback = tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-send')))
          .onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(sending.calls, 1);
      expect(find.text('Un solo envío'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('chat-send')))
            .onPressed,
        isNull,
      );
      sending.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-draft')))
            .controller!
            .text,
        isEmpty,
      );
      expect((await service.watchMessages('ana.bob').first), hasLength(1));
    },
  );

  testWidgets(
    '360 px: mensajes propios derecha, recibidos izquierda, sin overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await seedMessage(1);
      await seedMessage(2, sender: 'bob');
      await open(tester);
      final bubbles = tester.widgetList<MessageBubble>(
        find.byType(MessageBubble),
      );
      expect(bubbles.map((b) => b.own), containsAll([true, false]));
      for (final bubble in bubbles) {
        final align = tester.widget<Align>(
          find
              .descendant(
                of: find.byKey(bubble.key!),
                matching: find.byType(Align),
              )
              .first,
        );
        expect(
          align.alignment,
          bubble.own ? Alignment.centerRight : Alignment.centerLeft,
        );
      }
      expect(
        tester.getTopLeft(find.text('Mensaje 1')).dy,
        lessThan(tester.getTopLeft(find.text('Mensaje 2')).dy),
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-draft')),
        'Palabra' * 140,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desactivación en tiempo real conserva historial y deshabilita envío',
    (tester) async {
      await seedMessage(1);
      await open(tester);
      await db.doc('matches/ana.bob').update({
        'isActive': false,
        'closedAt': Timestamp.now(),
        'closedBy': 'ana',
      });
      await tester.pumpAndSettle();
      expect(find.text('Mensaje 1'), findsOneWidget);
      expect(
        find.textContaining('Puedes consultar el historial'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('chat-send')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-draft')))
            .enabled,
        isFalse,
      );
    },
  );

  testWidgets('Mensaje recibido aparece sin recargar', (tester) async {
    await open(tester);
    await service.send('ana.bob', 'bob', 'Respuesta en vivo');
    await tester.pumpAndSettle();
    expect(find.text('Respuesta en vivo'), findsOneWidget);
    expect(find.text('Aún no hay mensajes. ¡Saluda!'), findsNothing);
  });

  testWidgets('Mis Matches abre chat y Atrás regresa a la lista', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatchesScreen(
          uid: 'ana',
          service: MatchesService(firestore: db),
          chatService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MatchTile));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Perfil no disponible'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Mis Matches'), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('Error del listener muestra reintento y puede recuperarse', (
    tester,
  ) async {
    final retry = _RetryHistory(db);
    await open(tester, replacement: retry);
    expect(find.textContaining('Revisa tu conexión'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay mensajes. ¡Saluda!'), findsOneWidget);
  });

  testWidgets('Loading y match inaccesible no exponen formulario', (
    tester,
  ) async {
    final loading = _LoadingMatch(db);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(matchId: 'ana.bob', uid: 'ana', service: loading),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(matchId: 'ana.carol', uid: 'ana', service: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Este chat no está disponible.'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send')), findsNothing);
  });
}

class _ControlledSend extends ChatService {
  _ControlledSend(FirebaseFirestore db) : super(firestore: db);
  bool fail = false;
  int calls = 0;
  Completer<void>? pending;
  @override
  Future<void> send(String matchId, String uid, String draft) async {
    calls++;
    if (fail) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    if (pending != null) await pending!.future;
    await super.send(matchId, uid, draft);
  }
}

class _RetryHistory extends ChatService {
  _RetryHistory(FirebaseFirestore db) : super(firestore: db);
  int calls = 0;
  @override
  Stream<List<ChatMessage>> watchMessages(String matchId) => ++calls == 1
      ? Stream.error(StateError('offline'))
      : super.watchMessages(matchId);
}

class _LoadingMatch extends ChatService {
  _LoadingMatch(FirebaseFirestore db) : super(firestore: db);
  @override
  Stream<StudentMatch> watchMatch(String matchId, String uid) =>
      const Stream.empty();
}
