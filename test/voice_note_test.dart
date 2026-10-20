import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tinder_universitario/features/chat/voice_note_recorder.dart';
import 'package:tinder_universitario/features/chat/voice_note_controller.dart';
import 'package:tinder_universitario/features/chat/chat_media_validation.dart';
import 'package:tinder_universitario/features/chat/voice_signal.dart';
import 'package:record/record.dart';
import 'package:flutter/services.dart';

Uint8List audiblePcm(int length) {
  final b = Uint8List(length);
  final v = ByteData.sublistView(b);
  for (var i = 0; i + 1 < length; i += 2) {
    v.setInt16(i, i % 4 == 0 ? 1024 : -1024, Endian.little);
  }
  return b;
}

class PausedWebRecorder extends AudioRecorder {
  bool resumed = false;
  RecordConfig? config;
  @override
  Future<Stream<Uint8List>> startStream(RecordConfig c) async {
    config = c;
    return const Stream.empty();
  }

  @override
  Future<bool> isPaused() async => true;
  @override
  Future<void> resume() async {
    resumed = true;
  }
}

class FakeCapture implements VoiceCapture {
  bool allowed = true;
  int starts = 0, cancels = 0, stops = 0;
  Completer<bool>? pending;
  final stream = StreamController<Uint8List>();
  @override
  Future<bool> permission() async =>
      pending == null ? allowed : await pending!.future;
  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    return stream.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stream.close();
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (!stream.isClosed) unawaited(stream.close());
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Sin muestras detiene y avisa en vez de aparentar grabación', (
    tester,
  ) async {
    final f = FakeCapture();
    final c = VoiceNoteController(f);
    await c.begin();
    // Stopwatch uses monotonic wall time; widget pumps only advance timers.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
    await tester.pump(const Duration(seconds: 4));
    expect(c.recording, false);
    expect(c.draft, isNull);
    expect(c.error, contains('No llegan muestras'));
    expect(f.cancels, greaterThan(0));
    c.dispose();
    await tester.pump();
  });
  test('PCM detecta silencio digital y señal incluso con chunks impares', () {
    final signal = VoiceSignal();
    signal.add(Uint8List(3200));
    expect(signal.silent, true);
    expect(signal.samples, 1600);
    expect(signal.meter, 0);
    final b = audiblePcm(3200);
    signal.add(b.sublist(0, 3));
    signal.add(b.sublist(3));
    expect(signal.silent, false);
    expect(signal.samples, 3200);
    expect(signal.peak, 1024);
    expect(signal.rms, closeTo(0.022097, 0.00001));
    expect(signal.meter, greaterThan(0));
  });
  test('Adaptador conserva PCM16 mono y entrada elegida', () async {
    const channel = MethodChannel('com.llfbandit.record/messages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final recorder = PausedWebRecorder();
    final capture = RecordVoiceCapture(recorder: recorder)
      ..device = const InputDevice(id: 'selected', label: 'Test');
    await capture.start();
    expect(recorder.config!.device!.id, 'selected');
    expect(recorder.config!.encoder, AudioEncoder.pcm16bits);
    expect(recorder.config!.sampleRate, 16000);
    expect(recorder.config!.numChannels, 1);
  });
  test(
    'Silencio válido de 14 segundos nunca permite vista previa ni envío',
    () async {
      final f = FakeCapture();
      final c = VoiceNoteController(f);
      await c.begin();
      f.stream.add(Uint8List(16000 * 2 * 14));
      await c.finish();
      expect(c.draft, isNull);
      expect(c.error, contains('No se detectó sonido'));
      var sent = false;
      await c.send((_) async {
        sent = true;
      });
      expect(sent, false);
      c.dispose();
    },
  );
  test('Volumen bajo advierte sin bloquear voz no nula', () async {
    final f = FakeCapture();
    final c = VoiceNoteController(f);
    await c.begin();
    final b = Uint8List(3200);
    final v = ByteData.sublistView(b);
    for (var i = 0; i < b.length; i += 2) {
      v.setInt16(i, 2, Endian.little);
    }
    f.stream.add(b);
    await c.finish();
    expect(c.draft, isNotNull);
    expect(c.warning, contains('muy bajo'));
    c.dispose();
  });
  test(
    'Diagnóstico de micrófono clasifica sin exponer detalles de excepción',
    () {
      expect(
        voiceCaptureErrorCode(Exception('NotAllowedError secret')),
        'permission-denied',
      );
      expect(
        voiceCaptureErrorCode(Exception('NotFoundError secret')),
        'no-device',
      );
      expect(
        voiceCaptureErrorCode(Exception('NotReadableError secret')),
        'device-unavailable',
      );
      expect(voiceCaptureErrorCode(Exception('secret')), 'capture-failed');
    },
  );
  testWidgets('Mantener y deslizar cancela sin publicar ni dejar borrador', (
    tester,
  ) async {
    final fake = FakeCapture();
    int sent = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceNoteRecorder(
            enabled: true,
            capture: fake,
            onBusy: (_) {},
            onSend: (b) async {
              sent++;
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic)),
    );
    await tester.pump(const Duration(milliseconds: 650));
    fake.stream.add(Uint8List(3200));
    await tester.pump();
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fake.cancels, greaterThan(0));
    expect(sent, 0);
    expect(find.text('Enviar nota de voz'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test('Sin permiso no abre micrófono ni genera borrador', () async {
    final f = FakeCapture()..allowed = false;
    final c = VoiceNoteController(f);
    await c.begin();
    expect(f.starts, 0);
    expect(c.error, contains('micrófono'));
    expect(c.busy, false);
    c.dispose();
  });
  test(
    'Soltar durante permiso espera inicio y produce vista previa, sin enviar',
    () async {
      final f = FakeCapture()..pending = Completer<bool>();
      final c = VoiceNoteController(f);
      final start = c.begin();
      final stop = c.finish();
      f.pending!.complete(true);
      await start;
      f.stream.add(audiblePcm(3200));
      await stop;
      expect(c.draft, isNotNull);
      expect(c.recording, false);
      expect(f.stops, 1);
      c.dispose();
    },
  );
  test('Cancelar durante permiso impide iniciar grabación', () async {
    final f = FakeCapture()..pending = Completer<bool>();
    final c = VoiceNoteController(f);
    final start = c.begin();
    final cancel = c.discard();
    f.pending!.complete(true);
    await start;
    await cancel;
    expect(f.starts, 0);
    expect(c.draft, isNull);
    c.dispose();
  });
  test(
    'Detener genera WAV validado; enviar solo se ejecuta al confirmar',
    () async {
      final f = FakeCapture();
      final c = VoiceNoteController(f);
      await c.begin();
      f.stream.add(audiblePcm(3200));
      await c.finish();
      await ChatMediaValidation.validate(c.draft!, 'audio', 'audio/wav');
      int sent = 0;
      await c.send((b) async {
        sent++;
        expect(b.length, 3244);
      });
      expect(sent, 1);
      expect(c.draft, isNull);
      c.dispose();
    },
  );
  test('Descarte y grabación corta nunca publican', () async {
    final f = FakeCapture();
    final c = VoiceNoteController(f);
    await c.begin();
    f.stream.add(Uint8List(32));
    await c.finish();
    expect(c.draft, isNull);
    expect(c.error, contains('corta'));
    await c.discard();
    expect(f.cancels, greaterThan(0));
    c.dispose();
  });
  test('Límite de memoria detiene sin acumular un chunk excesivo', () async {
    final f = FakeCapture();
    final c = VoiceNoteController(f);
    await c.begin();
    f.stream.add(audiblePcm(3200));
    f.stream.add(Uint8List(VoiceNoteController.maxBytes + 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.recording, false);
    expect(c.draft!.length, 3244);
    c.dispose();
  });
  test(
    'Envío ambiguo no ofrece reenviar el mismo audio automáticamente',
    () async {
      final f = FakeCapture();
      final c = VoiceNoteController(f);
      await c.begin();
      f.stream.add(audiblePcm(3200));
      await c.finish();
      await c.send((b) async => throw StateError('offline'));
      expect(c.draft, isNull);
      expect(c.error, contains('confirmar'));
      expect(c.sending, false);
      c.dispose();
    },
  );
}
