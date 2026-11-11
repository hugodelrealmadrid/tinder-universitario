import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/stories/story_shelf.dart';
import 'package:tinder_universitario/features/verification/backend_client.dart';

class _Stories implements VerificationClient {
  final viewed = <String>[];
  final photo = Uint8List.fromList(const [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    4,
    0,
    0,
    0,
    181,
    28,
    12,
    2,
    0,
    0,
    0,
    11,
    73,
    68,
    65,
    84,
    120,
    218,
    99,
    252,
    255,
    31,
    0,
    3,
    3,
    2,
    0,
    238,
    254,
    95,
    105,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ]);

  @override
  Future<Map<String, dynamic>> stories(
    String action, {
    String? id,
    String? cursor,
  }) async => {
    'serverNow': 100,
    'groups': [
      for (final person in ['Alma', 'Bruno', 'Celia'])
        <String, dynamic>{
          'name': person,
          'own': false,
          'stories': [
            <String, dynamic>{
              'id': person,
              'mime': person == 'Celia' ? 'video/mp4' : 'image/jpeg',
              'caption': 'Historia de $person',
              'expiresAt': 86400100,
              'seen': false,
            },
          ],
        },
    ],
  };

  @override
  Future<Uint8List> storyMedia(String id) async => photo;

  @override
  Future<void> storyAction(String action, String id, {String? text}) async {
    if (action == 'view') viewed.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Carrusel, navegación a otro usuario y registro de vista', (
    tester,
  ) async {
    final service = _Stories();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StoryShelf(client: service)),
      ),
    );
    await tester.pump();
    expect(find.text('Celia'), findsNothing);
    await tester.tap(find.text('Alma'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Historia de Alma'), findsOneWidget);
    expect(service.viewed, ['Alma']);
    await tester.tap(find.byTooltip('Historia siguiente'));
    await tester.pump();
    expect(find.text('Historia de Bruno'), findsOneWidget);
    expect(service.viewed, ['Alma', 'Bruno']);
    await tester.tap(find.byTooltip('Cerrar historia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Historias'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('El compositor nativo ofrece solamente fotografías', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StoryShelf(client: _Stories())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Publicar'));
    await tester.pumpAndSettle();
    expect(find.text('Elegir fotografía'), findsOneWidget);
    expect(find.textContaining('MP4'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
