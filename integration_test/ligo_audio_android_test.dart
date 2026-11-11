import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tinder_universitario/features/chat/audio_playback.dart';
import 'package:tinder_universitario/features/chat/voice_note_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android decodifica WAV y el reloj del reproductor avanza', (
    tester,
  ) async {
    final pcm = Uint8List(16000 * 2 * 3);
    final samples = ByteData.sublistView(pcm);
    for (var i = 0; i < pcm.length; i += 2) {
      samples.setInt16(i, i % 80 < 40 ? 1200 : -1200, Endian.little);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioPlayback(bytes: voiceWav(pcm), mime: 'audio/wav'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Reproducir audio'));
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    var progressed = false;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No se pudo reproducir el audio.'), findsNothing);
      if (tester.widget<Slider>(find.byType(Slider)).value > 0 &&
          find.byTooltip('Pausar audio').evaluate().isNotEmpty) {
        progressed = true;
        break;
      }
    }
    expect(progressed, isTrue);
    await tester.tap(find.byTooltip('Pausar audio'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reproducir audio'), findsOneWidget);
  });
}
