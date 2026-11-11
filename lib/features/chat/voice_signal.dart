import 'dart:math' as math;
import 'dart:typed_data';

/// Measurements of signed little-endian PCM16. Never retains audio samples.
class VoiceSignal {
  int samples = 0, peak = 0;
  double _squares = 0, level = 0;
  int? _lowByte;

  void add(Uint8List bytes) {
    double squares = 0;
    var count = 0;
    for (final byte in bytes) {
      if (_lowByte == null) {
        _lowByte = byte;
        continue;
      }
      var sample = _lowByte! | (byte << 8);
      if (sample >= 32768) sample -= 65536;
      _lowByte = null;
      peak = math.max(peak, sample.abs());
      squares += sample.toDouble() * sample;
      count++;
    }
    samples += count;
    _squares += squares;
    if (count > 0) level = math.sqrt(squares / count) / 32768;
  }

  bool get silent => peak == 0;
  double get rms => samples == 0 ? 0 : math.sqrt(_squares / samples) / 32768;
  bool get quiet => !silent && rms < 0.0031623; // -50 dBFS: warn, don't reject.
  double get meter => level == 0
      ? 0
      : ((20 * math.log(level) / math.ln10 + 60) / 60).clamp(0, 1);
}
