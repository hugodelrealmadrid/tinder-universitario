import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/verification/admin_dossier_photo.dart';

void main() {
  testWidgets(
    'Carga, reintenta y abre la foto ampliada sin descargarla otra vez',
    (tester) async {
      final pending = Completer<Uint8List>();
      final bytes = File('staging/fixtures/ana-ficticia.png').readAsBytesSync();
      var requests = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminDossierPhoto(
              path: 'profile_photos/fixture/main',
              label: 'Foto principal',
              load: (path) {
                expect(path, 'profile_photos/fixture/main');
                return ++requests == 1 ? pending.future : Future.value(bytes);
              },
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.completeError(StateError('sin acceso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foto no disponible. Reintentar'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(requests, 2);
      await tester.tap(find.byTooltip('Cerrar foto'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    },
  );
}
