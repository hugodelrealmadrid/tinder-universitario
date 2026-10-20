import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'chat_message.dart';

/// Validación defensiva del cliente; no sustituye un decodificador del servidor.
abstract final class ChatMediaValidation {
  static const imageLimit = 5 * 1024 * 1024;
  static const audioLimit = 15 * 1024 * 1024;
  static const maxDimension = 4096;
  static const maxPixels = 16 * 1024 * 1024;
  static const images = ['image/jpeg', 'image/png', 'image/webp'];
  static const audios = ['audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/ogg'];

  static int limit(String type) => type == 'image' ? imageLimit : audioLimit;

  static Future<Uint8List> readBounded(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const ChatException('El archivo supera el tamaño permitido.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static Future<void> validate(
    Uint8List bytes,
    String type,
    String? mime,
  ) async {
    if (!['image', 'audio'].contains(type) ||
        !(type == 'image' ? images : audios).contains(mime) ||
        bytes.isEmpty ||
        bytes.length > limit(type)) {
      throw const ChatException('Formato o tamaño de archivo no permitido.');
    }
    if (!_signature(bytes, mime!)) {
      throw const ChatException(
        'El contenido del archivo no coincide con su formato.',
      );
    }
    if (type == 'image') {
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        if (kIsWeb) {
          // ImageDescriptor.width/height no están implementados en Flutter Web.
          // Leer dimensiones antes de decodificar mantiene el límite de memoria.
          final size = imageDimensions(bytes, mime);
          _checkDimensions(size.$1, size.$2);
          codec = await ui.instantiateImageCodec(bytes);
        } else {
          buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          _checkDimensions(descriptor.width, descriptor.height);
          codec = await descriptor.instantiateCodec();
        }
        final frame = await codec.getNextFrame();
        try {
          _checkDimensions(frame.image.width, frame.image.height);
        } finally {
          frame.image.dispose();
        }
      } on ChatException {
        rethrow;
      } catch (_) {
        throw const ChatException('La imagen está dañada o no es compatible.');
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer?.dispose();
      }
    }
  }

  static void _checkDimensions(int width, int height) {
    if (width <= 0 ||
        height <= 0 ||
        width > maxDimension ||
        height > maxDimension ||
        width * height > maxPixels) {
      throw const ChatException('La imagen supera las dimensiones permitidas.');
    }
  }

  /// Solo dimensiones de cabecera; validate exige además decodificación real.
  static (int, int) imageDimensions(Uint8List b, String mime) {
    if (mime == 'image/png' && b.length >= 33 && _text(b, 12, 'IHDR')) {
      return (_u32(b, 16, Endian.big), _u32(b, 20, Endian.big));
    }
    if (mime == 'image/webp') {
      if (b.length >= 30 && _text(b, 12, 'VP8X')) {
        int u24(int p) => b[p] | b[p + 1] << 8 | b[p + 2] << 16;
        return (u24(24) + 1, u24(27) + 1);
      }
      if (b.length >= 25 && _text(b, 12, 'VP8L') && b[20] == 0x2f) {
        return (
          1 + (b[21] | (b[22] & 0x3f) << 8),
          1 + (b[22] >> 6 | b[23] << 2 | (b[24] & 0x0f) << 10),
        );
      }
      if (b.length >= 30 &&
          _text(b, 12, 'VP8 ') &&
          _at(b, 23, [0x9d, 1, 0x2a])) {
        return ((b[26] | b[27] << 8) & 0x3fff, (b[28] | b[29] << 8) & 0x3fff);
      }
    }
    if (mime == 'image/jpeg') {
      var p = 2;
      while (p + 3 < b.length && b[p] == 0xff) {
        while (p < b.length && b[p] == 0xff) {
          p++;
        }
        if (p + 2 >= b.length) break;
        final marker = b[p++];
        if (marker == 0xda || marker == 0xd9) break;
        final length = b[p] << 8 | b[p + 1];
        if (length < 2 || p + length > b.length) break;
        if ([
              0xc0,
              0xc1,
              0xc2,
              0xc3,
              0xc5,
              0xc6,
              0xc7,
              0xc9,
              0xca,
              0xcb,
              0xcd,
              0xce,
              0xcf,
            ].contains(marker) &&
            length >= 8) {
          return (b[p + 5] << 8 | b[p + 6], b[p + 3] << 8 | b[p + 4]);
        }
        p += length;
      }
    }
    throw const ChatException('La imagen está dañada o no es compatible.');
  }

  static bool _at(Uint8List b, int offset, List<int> value) =>
      offset >= 0 &&
      offset + value.length <= b.length &&
      Iterable<int>.generate(
        value.length,
      ).every((i) => b[offset + i] == value[i]);
  static bool _text(Uint8List b, int offset, String value) =>
      _at(b, offset, value.codeUnits);
  static int _u32(Uint8List b, int offset, Endian endian) =>
      ByteData.sublistView(b).getUint32(offset, endian);

  static bool _signature(Uint8List b, String mime) => switch (mime) {
    'image/jpeg' => _at(b, 0, [255, 216, 255]),
    'image/png' => _at(b, 0, [137, 80, 78, 71, 13, 10, 26, 10]),
    'image/webp' =>
      b.length >= 20 &&
          _text(b, 0, 'RIFF') &&
          _text(b, 8, 'WEBP') &&
          _u32(b, 4, Endian.little) + 8 == b.length,
    'audio/wav' => _wav(b),
    'audio/mpeg' => _mp3(b),
    'audio/ogg' => _ogg(b),
    'audio/mp4' => _mp4(b),
    _ => false,
  };

  static bool _wav(Uint8List b) {
    if (b.length < 44 ||
        !_text(b, 0, 'RIFF') ||
        !_text(b, 8, 'WAVE') ||
        _u32(b, 4, Endian.little) + 8 != b.length) {
      return false;
    }
    var format = false, data = false, p = 12;
    while (p + 8 <= b.length) {
      final size = _u32(b, p + 4, Endian.little);
      if (p + 8 + size > b.length) return false;
      if (_text(b, p, 'fmt ')) {
        if (size < 16) return false;
        final view = ByteData.sublistView(b);
        final encoding = view.getUint16(p + 8, Endian.little);
        final channels = view.getUint16(p + 10, Endian.little);
        final rate = _u32(b, p + 12, Endian.little);
        format =
            [1, 3, 0xfffe].contains(encoding) &&
            channels >= 1 &&
            channels <= 8 &&
            rate >= 8000 &&
            rate <= 192000;
      }
      if (_text(b, p, 'data')) data = size > 0;
      p += 8 + size + (size.isOdd ? 1 : 0);
    }
    return format && data && p == b.length;
  }

  static bool _mp3(Uint8List b) {
    var p = 0, frames = 0;
    if (_text(b, 0, 'ID3')) {
      if (b.length < 10 ||
          ![2, 3, 4].contains(b[3]) ||
          b.sublist(6, 10).any((v) => v >= 128)) {
        return false;
      }
      final size = (b[6] << 21) | (b[7] << 14) | (b[8] << 7) | b[9];
      p = 10 + size + (b[3] == 4 && b[5] & 16 != 0 ? 10 : 0);
    }
    while (p + 4 <= b.length) {
      if (b.length - p == 128 && _text(b, p, 'TAG')) return frames >= 2;
      if (b[p] != 255 || b[p + 1] & 224 != 224) return false;
      final version = (b[p + 1] >> 3) & 3;
      final layer = (b[p + 1] >> 1) & 3;
      final bitrateIndex = b[p + 2] >> 4;
      final rateIndex = (b[p + 2] >> 2) & 3;
      if (version == 1 ||
          layer != 1 ||
          bitrateIndex == 0 ||
          bitrateIndex == 15 ||
          rateIndex == 3) {
        return false;
      }
      final rates = [44100, 48000, 32000];
      final rate =
          rates[rateIndex] ~/
          (version == 3
              ? 1
              : version == 2
              ? 2
              : 4);
      final bitrates = version == 3
          ? [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
          : [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
      final length =
          (version == 3 ? 144000 : 72000) * bitrates[bitrateIndex] ~/ rate +
          ((b[p + 2] >> 1) & 1);
      if (p + length > b.length) return false;
      p += length;
      frames++;
    }
    return frames >= 2 && p == b.length;
  }

  static bool _ogg(Uint8List b) {
    var p = 0, pages = 0;
    while (p < b.length) {
      if (p + 27 > b.length || !_text(b, p, 'OggS') || b[p + 4] != 0) {
        return false;
      }
      final segments = b[p + 26];
      final start = p + 27 + segments;
      if (start > b.length) return false;
      var size = 0;
      for (var i = p + 27; i < start; i++) {
        size += b[i];
      }
      if (size == 0 || start + size > b.length) return false;
      if (pages == 0 &&
          !(_text(b, start, 'OpusHead') ||
              (b[start] == 1 && _text(b, start + 1, 'vorbis')))) {
        return false;
      }
      pages++;
      p = start + size;
    }
    return pages >= 2;
  }

  static bool _mp4(Uint8List b) {
    var ftyp = false, audio = false, video = false, data = false;
    bool boxes(int start, int end, int depth) {
      if (depth > 6) return false;
      var p = start;
      while (p < end) {
        if (p + 8 > end) return false;
        var size = _u32(b, p, Endian.big), header = 8;
        if (size == 1) {
          if (p + 16 > end || _u32(b, p + 8, Endian.big) != 0) return false;
          size = _u32(b, p + 12, Endian.big);
          header = 16;
        } else if (size == 0) {
          size = end - p;
        }
        if (size < header || p + size > end) return false;
        final payload = p + header;
        if (depth == 0 && _text(b, p + 4, 'ftyp')) ftyp = size >= header + 8;
        if (depth == 0 && _text(b, p + 4, 'mdat')) data = size > header;
        if (depth == 3 && _text(b, p + 4, 'hdlr') && size >= header + 12) {
          audio |= _text(b, payload + 8, 'soun');
          video |= _text(b, payload + 8, 'vide');
        }
        if (['moov', 'trak', 'mdia'].any((v) => _text(b, p + 4, v)) &&
            !boxes(payload, p + size, depth + 1)) {
          return false;
        }
        p += size;
      }
      return p == end;
    }

    return boxes(0, b.length, 0) && ftyp && audio && !video && data;
  }
}
