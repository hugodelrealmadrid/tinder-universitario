import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tinder_universitario/features/discovery/discovery_service.dart';
import 'package:tinder_universitario/main_ligo_staging.dart' as staging;
import 'package:tinder_universitario/features/chat/voice_note_controller.dart';
import 'package:tinder_universitario/features/chat/voice_note_recorder.dart';
import 'package:tinder_universitario/features/chat/audio_playback.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';
import 'package:tinder_universitario/theme/app_theme.dart';

/// Entrada sintética declarada: verifica gestos/PCM/reproductor nativo, no un micrófono físico.
class TestPcmCapture implements VoiceCapture {
  final stream = StreamController<Uint8List>();
  Timer? timer;
  bool closed = false;
  @override
  Future<bool> permission() async => true;
  @override
  Future<Stream<Uint8List>> start() async {
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final b = Uint8List(3200), v = ByteData.sublistView(b);
      for (var i = 0; i < 1600; i++) {
        v.setInt16(i * 2, i % 40 < 20 ? 1200 : -1200, Endian.little);
      }
      if (!stream.isClosed) stream.add(b);
    });
    return stream.stream;
  }

  @override
  Future<void> stop() async {
    timer?.cancel();
    if (!stream.isClosed) await stream.close();
  }

  @override
  Future<void> cancel() async {
    timer?.cancel();
    if (!stream.isClosed) unawaited(stream.close());
  }

  @override
  Future<void> dispose() async {
    closed = true;
    await cancel();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LIGO13 Android: staging real, likes ficticios oficiales y gestos de voz sintéticos',
    (t) async {
      await staging.main();
      expect(Firebase.app().options.projectId, 'demo-ligo-staging');
      await FirebaseAuth.instance.signOut();
      await binding.convertFlutterSurfaceToImage();
      Future<void> waitFor(Finder f) async {
        final end = DateTime.now().add(const Duration(seconds: 60));
        while (DateTime.now().isBefore(end)) {
          await t.pump(const Duration(milliseconds: 100));
          if (f.evaluate().isNotEmpty) return;
        }
        await binding.takeScreenshot('ligo13-timeout');
        fail('No apareció $f');
      }

      Future<void> shot(String n) async {
        await t.pump(const Duration(milliseconds: 350));
        await binding.takeScreenshot('ligo13-$n');
      }

      Future<void> login(String email) async {
        await waitFor(find.text('Iniciar sesión'));
        await t.enterText(find.byType(TextFormField).at(0), email);
        await t.enterText(
          find.byType(TextFormField).at(1),
          'Ligo-staging-2026!',
        );
        await t.ensureVisible(find.text('Iniciar sesión'));
        await t.tap(find.text('Iniciar sesión'));
      }

      await waitFor(find.text('Iniciar sesión'));
      await shot('login');
      await login('ligo_root@ligo.test');
      await waitFor(find.text('El pulso de tu comunidad'));
      await waitFor(find.text('Usuarios'));
      await shot('superadmin');
      Future<void> section(String name) async {
        await t.tap(find.byTooltip('Menú de administración'));
        await t.pumpAndSettle();
        final item = find.text(name).last;
        await t.ensureVisible(item);
        await t.tap(item);
        await t.pumpAndSettle();
      }

      await section('Usuarios');
      await waitFor(find.text('Tu comunidad'));
      await shot('users');
      await section('Roles y permisos');
      await waitFor(find.text('Seleccionar persona'));
      await shot('roles');
      await section('Auditoría');
      await waitFor(find.text('Una historia transparente'));
      await shot('audit');
      await section('Reportes');
      await waitFor(find.text('Reportes y moderación'));
      await shot('reports');
      await FirebaseAuth.instance.signOut();
      await login('ligo_admin@ligo.test');
      await waitFor(find.text('El pulso de tu comunidad'));
      await t.tap(find.byTooltip('Menú de administración'));
      await t.pumpAndSettle();
      expect(find.text('Roles y permisos'), findsNothing);
      expect(find.text('Universidades'), findsNothing);
      expect(find.text('Auditoría'), findsNothing);
      await shot('admin-permissions');
      await FirebaseAuth.instance.signOut();
      await login('ligo_visual_ana@ligo.test');
      await waitFor(find.text('Descubrir personas'));
      Future<void> likeFixture(String other) async {
        expect(Firebase.app().options.projectId, 'demo-ligo-staging');
        final uid = FirebaseAuth.instance.currentUser!.uid;
        expect({'ligo_visual_ana', 'ligo_visual_bob'}.contains(uid), true);
        expect({'ligo_visual_ana', 'ligo_visual_bob'}.contains(other), true);
        await t.runAsync(() async {
          final previous = await FirebaseFirestore.instance
              .doc('swipes/$uid.$other')
              .get();
          if (previous.exists) {
            expect(
              previous.data()?['type'],
              'like',
              reason: 'No se sobreescriben decisiones ficticias anteriores.',
            );
            return;
          }
          await DiscoveryService().decide(uid, other, 'like');
        });
      }

      await t.ensureVisible(find.text('Descubrir personas'));
      await t.tap(find.text('Descubrir personas'));
      await waitFor(find.byTooltip('Preferencias').first);
      await t.pump(const Duration(seconds: 2));
      await shot('discovery');
      await likeFixture('ligo_visual_bob');
      await FirebaseAuth.instance.signOut();
      await login('ligo_visual_bob@ligo.test');
      await waitFor(find.text('Descubrir personas'));
      await likeFixture('ligo_visual_ana');
      const fixtureMatch = 'ligo_visual_ana.ligo_visual_bob';
      await t.runAsync(
        () => ChatService().send(
          fixtureMatch,
          'ligo_visual_bob',
          'FICTICIO · Probando el nuevo chat de LIGO 1.3 😊',
        ),
      );
      await t.tap(find.byType(NavigationDestination).at(3));
      await waitFor(find.text('Editar perfil'));
      await shot('profile');
      await t.tap(find.byType(NavigationDestination).at(2));
      await waitFor(find.text('Abrir chat'));
      await shot('matches');
      await t.ensureVisible(find.text('Abrir chat').first);
      await t.tap(find.text('Abrir chat').first);
      await waitFor(find.byKey(const ValueKey('chat-draft')));
      await t.pump(const Duration(seconds: 2));
      await shot('chat');
      // Captura sintética declarada: el envío sí recorre el backend privado del staging.
      final capture = TestPcmCapture();
      var sends = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            appBar: AppBar(title: const Text('Voz · prueba sintética')),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: VoiceNoteRecorder(
                enabled: true,
                capture: capture,
                onBusy: (_) {},
                onSend: (bytes) async {
                  expect(Firebase.app().options.projectId, 'demo-ligo-staging');
                  expect(
                    FirebaseAuth.instance.currentUser!.uid,
                    'ligo_visual_bob',
                  );
                  await ChatService().sendMedia(
                    fixtureMatch,
                    'ligo_visual_bob',
                    bytes,
                    'audio',
                    'audio/wav',
                    durationMs: ((bytes.length - 44) / 32).round(),
                  );
                  sends++;
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final gesture = await t.startGesture(t.getCenter(find.byIcon(Icons.mic)));
      await t.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(const Offset(0, -100));
      await t.pump(const Duration(seconds: 2));
      await gesture.up();
      await t.pump();
      expect(sends, 0);
      expect(find.textContaining('Grabación bloqueada'), findsOneWidget);
      await shot('voice-locked');
      await t.tap(find.byTooltip('Detener y escuchar'));
      await waitFor(find.byType(AudioPlayback));
      await shot('voice-preview');
      await t.tap(find.byTooltip('Reproducir audio'));
      await waitFor(find.byTooltip('Pausar audio'));
      await shot('voice-native-playing');
      await t.tap(find.byTooltip('Pausar audio'));
      await t.tap(find.text('Enviar nota de voz'));
      await t.pumpAndSettle();
      expect(sends, 1);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 200));
      expect(capture.closed, true);
      Future<void> mountVoice(TestPcmCapture input, String id) async {
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              appBar: AppBar(title: const Text('Voz · entrada sintética')),
              body: Align(
                alignment: Alignment.bottomCenter,
                child: VoiceNoteRecorder(
                  key: ValueKey(id),
                  enabled: true,
                  capture: input,
                  onBusy: (_) {},
                  onSend: (bytes) async {
                    expect(
                      Firebase.app().options.projectId,
                      'demo-ligo-staging',
                    );
                    expect(
                      FirebaseAuth.instance.currentUser!.uid,
                      'ligo_visual_bob',
                    );
                    await ChatService().sendMedia(
                      fixtureMatch,
                      'ligo_visual_bob',
                      bytes,
                      'audio',
                      'audio/wav',
                      durationMs: ((bytes.length - 44) / 32).round(),
                    );
                    sends++;
                  },
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      final cancelled = TestPcmCapture();
      await mountVoice(cancelled, 'cancel');
      final cancelGesture = await t.startGesture(
        t.getCenter(find.byIcon(Icons.mic)),
      );
      await t.pump(const Duration(milliseconds: 700));
      await cancelGesture.moveBy(const Offset(-110, 0));
      await t.pump();
      await cancelGesture.up();
      await t.pumpAndSettle();
      expect(sends, 1);
      expect(find.byType(AudioPlayback), findsNothing);
      await shot('voice-cancelled');
      debugPrint('LIGO13_NATIVE_CANCEL_CONFIRMED');
      final released = TestPcmCapture();
      await mountVoice(released, 'release');
      final releaseGesture = await t.startGesture(
        t.getCenter(find.byIcon(Icons.mic)),
      );
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(seconds: 3));
      await releaseGesture.up();
      final sendDeadline = DateTime.now().add(const Duration(seconds: 60));
      while (sends < 2 && DateTime.now().isBefore(sendDeadline)) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(sends, 2);
      expect(find.byType(AudioPlayback), findsNothing);
      debugPrint('LIGO13_NATIVE_AUTO_SEND_CONFIRMED');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 200));
      expect(released.closed, true);
      // El receptor se autentica realmente en Auth Emulator; no se falsifica readAt.
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: 'ligo_visual_ana@ligo.test',
        password: 'Ligo-staging-2026!',
      );
      expect(Firebase.app().options.projectId, 'demo-ligo-staging');
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ChatScreen(matchId: fixtureMatch, uid: 'ligo_visual_ana'),
        ),
      );
      await waitFor(find.textContaining('Cargar audio'));
      await t.tap(find.textContaining('Cargar audio').first);
      await waitFor(find.byType(AudioPlayback));
      await t.tap(find.byTooltip('Reproducir audio').first);
      await waitFor(find.byTooltip('Pausar audio'));
      await shot('received-private-audio-playing');
      await t.tap(find.byTooltip('Pausar audio'));
      await t.pump(const Duration(seconds: 2));
      final history = await ChatService().watchMessages(fixtureMatch).first;
      expect(
        history
            .where((m) => m.type == 'audio' && m.senderId == 'ligo_visual_bob')
            .any((m) => m.readAt != null),
        true,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
