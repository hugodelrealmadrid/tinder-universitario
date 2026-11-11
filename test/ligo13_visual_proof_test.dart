import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/theme/app_theme.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';
import 'package:tinder_universitario/features/discovery/discovery_screen.dart';
import 'package:tinder_universitario/features/verification/admin_workspace.dart';
import 'verification_fixtures.dart';
import 'final_redesign_test.dart' show sample;

class ProofApi extends FakeVerificationClient {
  ProofApi() {
    events = [
      {
        'id': 'event_fixture',
        'action': 'verification_approved',
        'actorId': 'reviewer',
        'targetId': 'student',
        'actor': {'name': 'María · ficticia', 'email': 'maria@ligo.test'},
        'target': {'name': 'Juan · ficticio', 'email': 'juan@ligo.test'},
        'at': '2026-11-02T10:15:00Z',
        'reasonCode': 'verified',
      },
    ];
    rows = [
      {
        'id': 'report_fixture',
        'reporter': {'name': 'Ana · ficticia'},
        'reported': {'name': 'Bob · ficticio'},
        'reportedId': 'bob',
        'reporterId': 'ana',
        'reason': 'spam',
        'details':
            'Reporte ficticio para revisar la interfaz. No contiene evidencia real.',
        'status': 'pending',
        'createdAt': '2026-11-02T09:00:00Z',
      },
    ];
  }
}

void main() {
  setUpAll(() async {
    const fonts = String.fromEnvironment('UI_FONT_DIR');
    if (fonts.isEmpty) return;
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(family)..addFont(
            File(
              '$fonts/roboto-regular.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '$fonts/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  Future<void> capture(WidgetTester t, String name) async {
    const dir = String.fromEnvironment('UI_CAPTURE_DIR');
    if (dir.isEmpty) return;
    await t.runAsync(() async {
      final image = await t
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('proof13')),
          )
          .toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [390.0, 1440.0]) {
    for (final module in [
      'audit',
      'reports',
      'users',
      'roles',
      'discovery',
      'chat',
    ]) {
      testWidgets('LIGO13 visual $module $width', (t) async {
        t.view.physicalSize = Size(width, width > 1000 ? 1000 : 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final api = ProofApi();
        Widget body;
        if (module == 'audit' || module == 'reports') {
          body = Scaffold(
            body: AdminHistoryView(client: api, reports: module == 'reports'),
          );
        } else if (module == 'users' || module == 'roles') {
          body = Scaffold(
            body: AdminPeopleView(
              client: api,
              selecting: module == 'roles',
              onInspect: (_) {},
            ),
          );
        } else if (module == 'discovery') {
          body = Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: CandidateView(
                candidate: sample,
                careerName: 'Ingeniería de Sistemas',
                interests: const ['Música', 'Tecnología'],
              ),
            ),
          );
        } else {
          final db = FakeFirebaseFirestore();
          await db.doc('matches/ana.bob').set({
            'users': ['ana', 'bob'],
            'isActive': true,
            'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
          });
          for (final (id, who, text, date) in [
            (
              'a',
              'ana',
              '¡Hola! ¿Cómo estuvo tu exposición?',
              DateTime(2026, 11, 1, 19, 40),
            ),
            (
              'b',
              'bob',
              '¡Muy bien! Me encantó conocer tu proyecto 😊',
              DateTime(2026, 11, 2, 10, 20),
            ),
            (
              'c',
              'ana',
              'Podemos conversar después de clases.',
              DateTime(2026, 11, 2, 10, 21),
            ),
          ]) {
            await db.doc('matches/ana.bob/messages/$id').set({
              'senderId': who,
              'text': text,
              'createdAt': Timestamp.fromDate(date),
            });
          }
          body = ChatScreen(
            matchId: 'ana.bob',
            uid: 'ana',
            service: ChatService(firestore: db),
            profile: sample,
          );
        }
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('proof13'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              home: body,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await capture(t, '$module-${width.toInt()}');
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      });
    }
  }
}
