import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/discovery/discovery_models.dart';
import 'package:tinder_universitario/widgets/app_ui.dart';
import 'package:tinder_universitario/features/profile/private_profile_photo.dart';
import 'package:tinder_universitario/features/profile/demo_photo_url.dart';

void main() {
  const local =
      'http://127.0.0.1:9198/v0/b/demo-tinder-universitario.appspot.com/o/profile_photos%2Fmanual_bob%2Fmain?alt=media&token=secret';
  test('URLs heredadas no son referencias privadas; parser solo sirve a migración', () {
    expect(validCandidatePhoto(local), isFalse);
    expect(validCandidatePhoto(local, demoMode: true), isFalse);
    expect(demoPhotoObjectPath(local), isNull);
    expect(
      demoPhotoObjectPath(local, demoMode: true),
      'profile_photos/manual_bob/main',
    );
    expect(validCandidatePhoto('https://example.test/photo.png'), isFalse);
    expect(validCandidatePhoto('profile_photos/manual_bob/main'), isTrue);
    for (final bad in [
      local.replaceFirst('127.0.0.1', 'localhost'),
      local.replaceFirst('127.0.0.1', 'example.test'),
      local.replaceFirst('9198', '9199'),
      local.replaceFirst(
        'demo-tinder-universitario.appspot.com',
        'real.appspot.com',
      ),
      local.replaceFirst('profile_photos', 'chat_media'),
      local.replaceFirst('127.0.0.1', 'other@127.0.0.1'),
      local.replaceFirst('main?', '..?'),
      'http://127.0.0.1:9198/photo.png',
      '',
      'blob:http://127.0.0.1:7357/id',
    ]) {
      expect(validCandidatePhoto(bad, demoMode: true), isFalse, reason: bad);
    }
  });
  test('Errores se clasifican sin URL, token ni detalles de excepción', () {
    for (final pair in [
      (403, 'access-denied'),
      (404, 'not-found'),
      (500, 'network'),
    ]) {
      final code = photoFailureCode(
        NetworkImageLoadException(statusCode: pair.$1, uri: Uri.parse(local)),
      );
      expect(code, pair.$2);
      expect(code, isNot(contains('secret')));
    }
    expect(photoFailureCode(Exception(local)), 'load-failed');
  });
  testWidgets('Foto fallida ofrece reintento sin mostrar datos sensibles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 120, height: 120, child: AppPhoto(url: local)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('No se pudo cargar la fotografía. Pulsa para reintentar.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    final before = tester.widget<PrivateProfilePhoto>(find.byType(PrivateProfilePhoto)).key;
    await tester.tap(
      find.byTooltip('No se pudo cargar la fotografía. Pulsa para reintentar.'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<PrivateProfilePhoto>(find.byType(PrivateProfilePhoto)).key, isNot(before));
  });
}
