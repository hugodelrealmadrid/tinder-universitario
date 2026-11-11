import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';
import 'package:tinder_universitario/features/notifications/notifications.dart';

import 'auth_service_test.dart' show LocalAuth, TestUser;

void main() {
  testWidgets(
    'Campana y bandeja reaccionan al contador y a un aviso real de Firestore',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = FakeFirebaseFirestore();
      final auth = LocalAuth()..current = TestUser(verified: true);
      addTearDown(auth.changes.close);
      final service = AuthService(auth: auth, firestore: db);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationHub(
            service: service,
            uid: 'ana',
            firestore: db,
            child: Scaffold(
              appBar: AppBar(actions: const [NotificationBell()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Notificaciones'));
      await tester.pumpAndSettle();
      expect(find.text('Todavía no hay notificaciones.'), findsOneWidget);
      final date = Timestamp.fromDate(
        DateTime.now().add(const Duration(seconds: 1)),
      );
      final inbox = db.doc('notificationInboxes/ana');
      final note = inbox.collection('items').doc('example');
      await inbox.set({'unread': 1, 'messages': 0});
      await note.set({
        'kind': 'verification',
        'status': 'approved',
        'createdAt': date,
        'readAt': null,
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Tu acreditación fue aprobada.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Sin leer'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await note.update({'readAt': date});
      await inbox.update({'unread': 0});
      await tester.pumpAndSettle();
      expect(find.byTooltip('Sin leer'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('Una respuesta tiene presentación propia y conserva el match', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('notices').doc('response');
    await ref.set({
      'kind': 'story_reply',
      'sender': 'bruno',
      'matchId': 'alma.bruno',
      'createdAt': Timestamp.now(),
    });
    final response = LigoNotice.fromDoc(await ref.get());
    expect(response.description, 'respondió a tu historia');
    expect(response.icon, Icons.auto_stories_outlined);
    expect(response.matchId, 'alma.bruno');
    expect(response.sender, 'bruno');
    expect(response.unread, isTrue);
    await ref.update({'kind': 'message', 'readAt': Timestamp.now()});
    final historical = LigoNotice.fromDoc(await ref.get());
    expect(historical.title, 'Nuevo mensaje');
    expect(historical.matchId, response.matchId);
    expect(historical.unread, isFalse);
  });
  testWidgets(
    'Al volver aparecen los cuatro avisos pendientes y sus contadores',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = FakeFirebaseFirestore();
      final auth = LocalAuth()..current = TestUser(verified: true);
      addTearDown(auth.changes.close);
      final service = AuthService(auth: auth, firestore: db);
      Future<void> openApp() async {
        await tester.pumpWidget(
          MaterialApp(
            home: NotificationHub(
              service: service,
              uid: 'ana',
              firestore: db,
              child: Scaffold(
                appBar: AppBar(actions: const [NotificationBell()]),
                body: const UnreadChatIcon(Icons.chat),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await openApp();
      await tester.pumpWidget(const SizedBox());
      final inbox = db.doc('notificationInboxes/ana');
      await inbox.set({'unread': 4, 'messages': 2});
      for (final kind in ['message', 'match', 'verification', 'story_reply']) {
        await inbox.collection('items').doc(kind).set({
          'kind': kind,
          'status': 'approved',
          'createdAt': Timestamp.now(),
        });
      }
      await openApp();
      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byTooltip('Notificaciones'));
      await tester.pumpAndSettle();
      for (final title in [
        'Nuevo mensaje',
        'Nuevo match',
        'Acreditación universitaria',
        'Respuesta a historia',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byTooltip('Sin leer'), findsNWidgets(4));
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(find.text('Activar en este dispositivo'), findsNothing);
    },
  );
}
