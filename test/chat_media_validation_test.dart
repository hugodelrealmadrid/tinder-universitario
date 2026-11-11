import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/chat/chat_media_validation.dart';
import 'package:tinder_universitario/features/chat/chat_message.dart';
import 'chat_media_fixtures.dart';

Uint8List mp4Box(String type, List<int> payload) {
  final b = Uint8List(8 + payload.length);
  ByteData.sublistView(b).setUint32(0, b.length, Endian.big);
  b.setRange(4, 8, type.codeUnits);
  b.setRange(8, b.length, payload);
  return b;
}

Uint8List mp4Fixture(String handler) => Uint8List.fromList([
  ...mp4Box('ftyp', 'M4A \u0000\u0000\u0000\u0000'.codeUnits),
  ...mp4Box(
    'moov',
    mp4Box(
      'trak',
      mp4Box(
        'mdia',
        mp4Box('hdlr', [...List.filled(8, 0), ...handler.codeUnits]),
      ),
    ),
  ),
  ...mp4Box('mdat', [1, 2, 3]),
]);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Cabeceras Web: dimensiones PNG y JPEG sin decodificar píxeles',
    () async {
      expect(
        ChatMediaValidation.imageDimensions(
          await chatPngFixture(width: 37, height: 19),
          'image/png',
        ),
        (37, 19),
      );
      final jpeg = Uint8List.fromList([
        255,
        216,
        255,
        224,
        0,
        2,
        255,
        192,
        0,
        8,
        8,
        0,
        19,
        0,
        37,
        1,
      ]);
      expect(ChatMediaValidation.imageDimensions(jpeg, 'image/jpeg'), (37, 19));
      jpeg[4] = 255;
      expect(
        () => ChatMediaValidation.imageDimensions(jpeg, 'image/jpeg'),
        throwsA(isA<ChatException>()),
      );
    },
  );
  test('Cabeceras WebP VP8, VP8L y VP8X conservan dimensiones', () {
    Uint8List header(String kind) {
      final b = Uint8List(30);
      b.setRange(12, 16, kind.codeUnits);
      return b;
    }

    final extended = header('VP8X');
    extended[24] = 36;
    extended[27] = 18;
    expect(ChatMediaValidation.imageDimensions(extended, 'image/webp'), (
      37,
      19,
    ));
    final lossless = header('VP8L');
    lossless[20] = 0x2f;
    lossless[21] = 36;
    lossless[22] = 128;
    lossless[23] = 4;
    expect(ChatMediaValidation.imageDimensions(lossless, 'image/webp'), (
      37,
      19,
    ));
    final lossy = header('VP8 ');
    lossy.setRange(23, 26, [0x9d, 1, 0x2a]);
    lossy[26] = 37;
    lossy[28] = 19;
    expect(ChatMediaValidation.imageDimensions(lossy, 'image/webp'), (37, 19));
  });
  test('Cabeceras truncadas y JPEG sin SOF no admiten dimensiones', () {
    for (final mime in ChatMediaValidation.images) {
      expect(
        () => ChatMediaValidation.imageDimensions(Uint8List(7), mime),
        throwsA(isA<ChatException>()),
      );
    }
    expect(
      () => ChatMediaValidation.imageDimensions(
        Uint8List.fromList([255, 216, 255, 218, 0, 2]),
        'image/jpeg',
      ),
      throwsA(isA<ChatException>()),
    );
  });
  test('PNG real decodifica y WAV PCM estructurado se admite', () async {
    await ChatMediaValidation.validate(
      await chatPngFixture(),
      'image',
      'image/png',
    );
    await ChatMediaValidation.validate(chatWavFixture(), 'audio', 'audio/wav');
  });
  test(
    'HTML renombrado y MIME falso se rechazan en todos los formatos',
    () async {
      final bytes = Uint8List.fromList('<html>falso</html>'.codeUnits);
      for (final mime in [
        ...ChatMediaValidation.images,
        ...ChatMediaValidation.audios,
      ]) {
        await expectLater(
          ChatMediaValidation.validate(
            bytes,
            mime.startsWith('image/') ? 'image' : 'audio',
            mime,
          ),
          throwsA(isA<ChatException>()),
        );
      }
      await expectLater(
        ChatMediaValidation.validate(
          await chatPngFixture(),
          'image',
          'image/jpeg',
        ),
        throwsA(isA<ChatException>()),
      );
    },
  );
  test('Firmas JPEG y PNG sin contenido decodificable se rechazan', () async {
    for (final fixture in [
      (Uint8List.fromList([255, 216, 255]), 'image/jpeg'),
      (Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]), 'image/png'),
    ]) {
      await expectLater(
        ChatMediaValidation.validate(fixture.$1, 'image', fixture.$2),
        throwsA(isA<ChatException>()),
      );
    }
  });
  test(
    'Imagen con dimensiones excesivas se rechaza antes de obtener frame',
    () async {
      final b = await chatPngFixture(width: 5000, height: 1);
      await expectLater(
        ChatMediaValidation.validate(b, 'image', 'image/png'),
        throwsA(isA<ChatException>()),
      );
    },
  );
  test('WAV truncado o sin chunk de datos se rechaza', () async {
    final b = chatWavFixture();
    await expectLater(
      ChatMediaValidation.validate(
        Uint8List.sublistView(b, 0, 46),
        'audio',
        'audio/wav',
      ),
      throwsA(isA<ChatException>()),
    );
    b.setRange(36, 40, 'junk'.codeUnits);
    await expectLater(
      ChatMediaValidation.validate(b, 'audio', 'audio/wav'),
      throwsA(isA<ChatException>()),
    );
  });
  test(
    'Lectura del selector se corta al superar el límite incluso con tamaño declarado falso',
    () async {
      expect(
        await ChatMediaValidation.readBounded(
          Stream.fromIterable([
            [1, 2],
            [3],
          ]),
          3,
        ),
        [1, 2, 3],
      );
      await expectLater(
        ChatMediaValidation.readBounded(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          3,
        ),
        throwsA(isA<ChatException>()),
      );
    },
  );
  test('MP3 necesita frames completos; ID3 aislado no basta', () async {
    final frame = Uint8List(417)..setRange(0, 4, [255, 251, 144, 0]);
    await ChatMediaValidation.validate(
      Uint8List.fromList([...frame, ...frame]),
      'audio',
      'audio/mpeg',
    );
    await expectLater(
      ChatMediaValidation.validate(
        Uint8List.fromList(
          'ID3\u0004\u0000\u0000\u0000\u0000\u0000\u0000'.codeUnits,
        ),
        'audio',
        'audio/mpeg',
      ),
      throwsA(isA<ChatException>()),
    );
    await expectLater(
      ChatMediaValidation.validate(
        Uint8List.fromList([...frame, ...frame.sublist(0, 10)]),
        'audio',
        'audio/mpeg',
      ),
      throwsA(isA<ChatException>()),
    );
  });
  test(
    'M4A necesita pista de audio y datos; rechaza video y boxes rotos',
    () async {
      await ChatMediaValidation.validate(
        mp4Fixture('soun'),
        'audio',
        'audio/mp4',
      );
      await expectLater(
        ChatMediaValidation.validate(mp4Fixture('vide'), 'audio', 'audio/mp4'),
        throwsA(isA<ChatException>()),
      );
      final b = mp4Fixture('soun');
      ByteData.sublistView(b).setUint32(0, 0xffffffff, Endian.big);
      await expectLater(
        ChatMediaValidation.validate(b, 'audio', 'audio/mp4'),
        throwsA(isA<ChatException>()),
      );
    },
  );
  test('OGG exige páginas completas y cabecera de códec conocido', () async {
    Uint8List page(List<int> data) {
      final header = Uint8List(28)..setRange(0, 4, 'OggS'.codeUnits);
      header[26] = 1;
      header[27] = data.length;
      return Uint8List.fromList([...header, ...data]);
    }

    final good = Uint8List.fromList([
      ...page('OpusHead'.codeUnits),
      ...page([1, 2, 3]),
    ]);
    await ChatMediaValidation.validate(good, 'audio', 'audio/ogg');
    await expectLater(
      ChatMediaValidation.validate(
        Uint8List.sublistView(good, 0, good.length - 1),
        'audio',
        'audio/ogg',
      ),
      throwsA(isA<ChatException>()),
    );
    await expectLater(
      ChatMediaValidation.validate(
        Uint8List.fromList([
          ...page('NotAudio'.codeUnits),
          ...page([1]),
        ]),
        'audio',
        'audio/ogg',
      ),
      throwsA(isA<ChatException>()),
    );
  });
}
