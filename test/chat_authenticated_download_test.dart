import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tinder_universitario/features/chat/chat_authenticated_download.dart';
import 'package:tinder_universitario/features/chat/chat_message.dart';

class StreamClient extends http.BaseClient {
  StreamClient(this.response);
  final http.StreamedResponse response;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      response;
}

void main() {
  const path = 'chat_media/ana.bob/ana/m1';
  test(
    'Descarga lleva autorización, URL sin token y no sigue redirecciones',
    () async {
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Firebase session-id-token');
        expect(request.url.queryParameters, {'alt': 'media'});
        expect(request.url.pathSegments.last, path);
        expect(request.followRedirects, isFalse);
        return http.Response.bytes([1, 2, 3], 200);
      });
      final download = ChatAuthenticatedDownload(
        idToken: () async => 'session-id-token',
        client: client,
      );
      expect(
        await download.read('demo-tinder-universitario.appspot.com', path, 5),
        [1, 2, 3],
      );
    },
  );
  test('Sin sesión nunca se realiza petición de red', () async {
    final download = ChatAuthenticatedDownload(
      idToken: () async => null,
      client: MockClient((_) async {
        fail('No debe llamar al servidor');
      }),
    );
    await expectLater(
      download.read('demo-bucket', path, 5),
      throwsA(isA<ChatException>()),
    );
  });
  for (final status in [302, 401, 403, 404, 500]) {
    test('HTTP $status no entrega bytes al reproductor', () async {
      final download = ChatAuthenticatedDownload(
        idToken: () async => 'id',
        client: MockClient((_) async => http.Response('error', status)),
      );
      await expectLater(
        download.read('demo-bucket', path, 5),
        throwsA(isA<ChatException>()),
      );
    });
  }
  test('Límite se aplica también a un stream sin Content-Length', () async {
    final download = ChatAuthenticatedDownload(
      idToken: () async => 'id',
      client: StreamClient(
        http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
            [4, 5, 6],
          ]),
          200,
        ),
      ),
    );
    await expectLater(
      download.read('demo-bucket', path, 5),
      throwsA(isA<ChatException>()),
    );
  });
  test('Límite de cabecera rechaza antes de leer cuerpo', () async {
    final download = ChatAuthenticatedDownload(
      idToken: () async => 'id',
      client: StreamClient(
        http.StreamedResponse(Stream<List<int>>.empty(), 200, contentLength: 6),
      ),
    );
    await expectLater(
      download.read('demo-bucket', path, 5),
      throwsA(isA<ChatException>()),
    );
  });
  test('Ruta externa, traversal y endpoint ajeno se rechazan', () async {
    for (final origin in [
      'https://evil.test',
      'http://firebasestorage.googleapis.com',
      'https://firebasestorage.googleapis.com/?token=abc',
    ]) {
      expect(
        () => ChatAuthenticatedDownload(
          idToken: () async => 'id',
          origin: Uri.parse(origin),
        ),
        throwsArgumentError,
      );
    }
    final download = ChatAuthenticatedDownload(idToken: () async => 'id');
    for (final path in [
      'https://evil.test/file',
      'chat_media/ana.bob/ana/../secret',
      'profile_photos/ana/m1',
    ]) {
      await expectLater(
        download.read('demo-bucket', path, 5),
        throwsA(isA<ChatException>()),
      );
    }
  });
  test('Endpoint loopback demo compatible con mismo contrato HTTP', () async {
    final download = ChatAuthenticatedDownload(
      idToken: () async => 'id',
      origin: Uri.parse('http://127.0.0.1:9198'),
      client: MockClient((request) async {
        expect(request.url.host, '127.0.0.1');
        expect(request.url.port, 9198);
        expect(request.url.queryParameters.containsKey('token'), isFalse);
        return http.Response.bytes(Uint8List.fromList([1]), 200);
      }),
    );
    expect(await download.read('demo-bucket', path, 5), [1]);
  });
}
