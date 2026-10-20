import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'voice_signal.dart';

String voiceCaptureErrorCode(Object error) {
  final text = error.toString();
  if (text.contains('NotAllowed') || text.contains('PermissionDenied')) {
    return 'permission-denied';
  }
  if (text.contains('NotFound') || text.contains('DevicesNotFound')) {
    return 'no-device';
  }
  if (text.contains('NotReadable') || text.contains('TrackStartError')) {
    return 'device-unavailable';
  }
  return 'capture-failed';
}

abstract interface class VoiceCapture {
  Future<bool> permission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class RecordVoiceCapture implements VoiceCapture {
  RecordVoiceCapture({AudioRecorder? recorder}) : _instance = recorder;
  InputDevice? device;
  Future<List<InputDevice>> devices() => _recorder.listInputDevices();
  AudioRecorder? _instance;
  AudioRecorder get _recorder => _instance ??= AudioRecorder();
  @override
  Future<bool> permission() => _recorder.hasPermission();
  @override
  Future<Stream<Uint8List>> start() async {
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        device: device,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    // record_web creates an AudioContext but does not resume it on start.
    // A suspended context must not be reported as successful capture.
    if (kIsWeb && await _recorder.isPaused()) {
      await _recorder.resume();
    }
    return stream;
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() async {
    await _instance?.cancel();
  }

  @override
  Future<void> dispose() async {
    await _instance?.dispose();
  }
}

Uint8List voiceWav(Uint8List pcm) {
  final data = Uint8List(44 + pcm.length);
  final v = ByteData.sublistView(data);
  void text(int p, String s) => data.setRange(p, p + s.length, s.codeUnits);
  text(0, 'RIFF');
  v.setUint32(4, data.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  v.setUint32(16, 16, Endian.little);
  v.setUint16(20, 1, Endian.little);
  v.setUint16(22, 1, Endian.little);
  v.setUint32(24, 16000, Endian.little);
  v.setUint32(28, 32000, Endian.little);
  v.setUint16(32, 2, Endian.little);
  v.setUint16(34, 16, Endian.little);
  text(36, 'data');
  v.setUint32(40, pcm.length, Endian.little);
  data.setRange(44, data.length, pcm);
  return data;
}

class VoiceNoteController extends ChangeNotifier {
  VoiceNoteController(this.capture);
  final VoiceCapture capture;
  static const maxSeconds = 60, maxBytes = 16000 * 2 * maxSeconds;
  BytesBuilder _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  final _clock = Stopwatch();
  Future<void>? _starting;
  bool recording = false, starting = false, stopping = false, sending = false;
  bool _discardRequested = false, _disposed = false;
  Uint8List? draft;
  String? error;
  String? warning;
  VoiceSignal signal = VoiceSignal();
  int get seconds => _clock.elapsed.inSeconds;
  bool get busy =>
      recording || starting || stopping || sending || draft != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> begin() async {
    if (busy || _disposed) return;
    starting = true;
    error = null;
    warning = null;
    signal = VoiceSignal();
    _discardRequested = false;
    _pcm = BytesBuilder(copy: false);
    _notify();
    _starting = _begin();
    await _starting;
  }

  Future<void> _begin() async {
    try {
      if (!await capture.permission()) {
        error = 'Permite el acceso al micrófono para grabar.';
        return;
      }
      if (_discardRequested || _disposed) return;
      final stream = await capture.start();
      if (_discardRequested || _disposed) {
        await capture.cancel();
        return;
      }
      recording = true;
      _clock.reset();
      _clock.start();
      _subscription = stream.listen(
        (bytes) {
          if (!recording) return;
          if (_pcm.length + bytes.length > maxBytes) {
            unawaited(finish());
            return;
          }
          _pcm.add(Uint8List.fromList(bytes));
          signal.add(bytes);
        },
        onError: (Object e) {
          error = 'No se pudo grabar. Revisa el micrófono.';
          unawaited(discard());
        },
        onDone: () {
          if (recording && !stopping) unawaited(finish());
        },
      );
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (seconds >= 3 && signal.samples == 0) {
          error =
              'No llegan muestras del micrófono. Revisa el permiso y la entrada seleccionada.';
          unawaited(discard());
        } else if (seconds >= maxSeconds) {
          unawaited(finish());
        } else {
          _notify();
        }
      });
    } catch (failure) {
      final code = voiceCaptureErrorCode(failure);
      debugPrint('VoiceNote: $code');
      error = switch (code) {
        'permission-denied' =>
          'Permite el acceso al micrófono en tu navegador o dispositivo.',
        'no-device' => 'No se encontró un micrófono. Conecta uno y reintenta.',
        'device-unavailable' =>
          'No se pudo abrir el micrófono. Revisa si otra aplicación lo está usando.',
        _ => 'No se pudo iniciar la grabación. Revisa permisos y micrófono.',
      };
      await capture.cancel().catchError((_) {});
    } finally {
      starting = false;
      _notify();
    }
  }

  Future<void> finish() async {
    await _starting;
    if (!recording || stopping || _disposed) return;
    stopping = true;
    _timer?.cancel();
    _clock.stop();
    _notify();
    try {
      await capture.stop();
      await _subscription?.cancel();
      if (_discardRequested || _disposed) return;
      final pcm = _pcm.takeBytes();
      if (pcm.length < 1600) {
        error = 'La grabación es demasiado corta.';
        return;
      }
      if (signal.silent) {
        error =
            'No se detectó sonido. Revisa el micrófono seleccionado, su volumen y si está silenciado.';
        return;
      }
      if (signal.quiet) {
        warning =
            'El volumen grabado es muy bajo. Escucha la nota antes de enviarla o prueba otra entrada.';
      }
      draft = voiceWav(pcm.sublist(0, pcm.length - pcm.length % 2));
    } catch (_) {
      error = 'No se pudo completar la grabación.';
      await capture.cancel().catchError((_) {});
    } finally {
      recording = false;
      stopping = false;
      _pcm = BytesBuilder(copy: false);
      _notify();
    }
  }

  Future<void> discard() async {
    if (sending) return;
    recording = false;
    _discardRequested = true;
    _timer?.cancel();
    _clock.stop();
    draft = null;
    await _starting;
    await capture.cancel().catchError((_) {});
    await _subscription?.cancel();
    _pcm = BytesBuilder(copy: false);
    recording = false;
    _notify();
  }

  Future<void> send(Future<void> Function(Uint8List) publish) async {
    if (draft == null || sending || _disposed) return;
    sending = true;
    error = null;
    _notify();
    try {
      await publish(draft!);
      draft = null;
    } catch (_) {
      draft = null;
      error =
          'No se pudo confirmar el envío. Revisa el chat antes de volver a grabar.';
    } finally {
      sending = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _discardRequested = true;
    _timer?.cancel();
    _clock.stop();
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    await _starting;
    await capture.cancel().catchError((_) {});
    await _subscription?.cancel();
    await capture.dispose().catchError((_) {});
    draft = null;
    _pcm = BytesBuilder(copy: false);
  }
}
