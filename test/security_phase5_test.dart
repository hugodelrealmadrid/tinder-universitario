import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/profile/private_profile_photo.dart';
import 'package:tinder_universitario/features/profile/private_photo_path.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';
import 'package:tinder_universitario/features/chat/chat_media_widget.dart';
import 'package:tinder_universitario/features/chat/chat_message.dart';
import 'chat_media_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Referencias privadas estrictas sin URL, credenciales, escape o subcarpeta',
    () {
      expect(isPrivatePhotoPath('profile_photos/ana/main'), true);
      for (final p in [
        'https://example.test/a?token=secret',
        'http://127.0.0.1:9198/o/a',
        'profile_photos/ana/../x',
        'profile_photos/ana/a/x',
        'profile_photos/ana/%2F',
        'profile_photos/ana/a?token=x',
        'profile_photos//a',
      ]) {
        expect(isPrivatePhotoPath(p), false);
      }
    },
  );
  testWidgets(
    'Foto privada se decodifica sin ImageCache, se oculta y revalida al volver',
    (tester) async {
      final bytes = await tester.runAsync(chatPngFixture);
      var calls = 0, allowed = true;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 120,
              height: 120,
              child: PrivateProfilePhoto(
                path: 'profile_photos/ana/main',
                placeholder: const Text('Cargando'),
                failure: (_, _) => const Text('Bloqueado'),
                loader: (_) async {
                  calls++;
                  if (!allowed) throw StateError('secret-token');
                  return bytes!;
                },
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      allowed = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Bloqueado'), findsOneWidget);
      expect(calls, 2);
      expect(find.textContaining('secret'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'URL antigua nunca se consulta ni se convierte en descarga anónima',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PrivateProfilePhoto(
            path: 'https://example.test/file?token=secret',
            placeholder: const Text('Cargando'),
            failure: (_, _) => const Text('Migración necesaria'),
            loader: (_) async {
              calls++;
              return await chatPngFixture();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Migración necesaria'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Match cerrado elimina reproductores y fotos de mensajes; conserva el texto',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MessageBubble(
            message: ChatMessage(
              id: 'm',
              senderId: 'ana',
              text: 'Historial',
              type: 'audio',
              mediaPath: 'chat_media/ana.bob/ana/m',
              createdAt: null,
            ),
            own: true,
            mediaAllowed: false,
          ),
        ),
      );
      expect(find.byType(ChatMediaWidget), findsNothing);
      expect(find.text('Historial'), findsOneWidget);
      expect(find.textContaining('match está inactivo'), findsOneWidget);
    },
  );
}
