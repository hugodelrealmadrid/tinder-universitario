import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/chat/chat_message.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';

void main() {
  test('Solo marca mensajes recibidos y conserva el contenido', () async {
    final db = FakeFirebaseFirestore();
    final service = ChatService(firestore: db);
    final ref = db.doc('matches/ana.bob/messages/m1');
    await ref.set({
      'senderId': 'bob',
      'text': 'Hola',
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1),
    });
    final message = ChatMessage.fromMap('m1', (await ref.get()).data()!);
    await service.markRead('ana.bob', 'bob', message);
    expect((await ref.get()).data()!.containsKey('readAt'), false);
    await service.markRead('ana.bob', 'ana', message);
    final data = (await ref.get()).data()!;
    expect(data['readAt'], isA<Timestamp>());
    expect(data['text'], 'Hola');
    final read = ChatMessage.fromMap('m1', data);
    await service.markRead('ana.bob', 'ana', read);
    expect((await ref.get()).data()!['readAt'], data['readAt']);
  });

  test('Los mensajes anteriores siguen siendo mensajes de texto', () {
    final message = ChatMessage.fromMap('old', {
      'senderId': 'ana',
      'text': 'Hola',
      'createdAt': null,
    });
    expect(message.type, 'text');
    expect(message.readAt, isNull);
  });

  testWidgets('El check cambia a azul únicamente después de la lectura', (
    tester,
  ) async {
    Future<void> show(DateTime? readAt) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            own: true,
            message: ChatMessage(
              id: '1',
              senderId: 'ana',
              text: 'Hola',
              createdAt: DateTime(2026),
              readAt: readAt,
            ),
          ),
        ),
      ),
    );
    await show(null);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.done_all)).color,
      Colors.white,
    );
    await show(DateTime(2026, 10, 12));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.done_all)).color,
      Colors.blue.shade900,
    );
  });
}
