import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'chat_message.dart';

/// Descarga REST con ID token, sin obtener ni consumir download tokens.
class ChatAuthenticatedDownload {
  ChatAuthenticatedDownload({required this.idToken, this._client, Uri? origin})
    : origin = origin ?? Uri.parse('https://firebasestorage.googleapis.com') {
    final endpoint = this.origin;
    final production =
        endpoint.scheme == 'https' &&
        endpoint.host == 'firebasestorage.googleapis.com' &&
        (!endpoint.hasPort || endpoint.port == 443);
    final emulator =
        endpoint.scheme == 'http' &&
        ['127.0.0.1', 'localhost', '10.0.2.2'].contains(endpoint.host);
    if ((!production && !emulator) ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        !['', '/'].contains(endpoint.path)) {
      throw ArgumentError('Endpoint de Storage no permitido.');
    }
  }
  final Future<String?> Function() idToken;
  final http.Client? _client;
  final Uri origin;

  Future<Uint8List> read(String bucket, String path, int maxBytes) async {
    if (!RegExp(
          r'^chat_media/[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$',
        ).hasMatch(path) ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(bucket) ||
        maxBytes <= 0) {
      throw const ChatException('Ruta multimedia no válida.');
    }
    final token = await idToken();
    if (token == null || token.isEmpty) {
      throw const ChatException('Inicia sesión para descargar este archivo.');
    }
    final client = _client ?? http.Client();
    try {
      final uri = Uri.parse(
        '$origin/v0/b/${Uri.encodeComponent(bucket)}/o/${Uri.encodeComponent(path)}?alt=media',
      );
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Authorization'] = 'Firebase $token';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const ChatException('Archivo no disponible o acceso denegado.');
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        throw const ChatException('El archivo supera el tamaño permitido.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const ChatException('El archivo supera el tamaño permitido.');
        }
        bytes.add(chunk);
      }
      if (bytes.isEmpty) throw const ChatException('Archivo vacío.');
      return bytes.takeBytes();
    } finally {
      if (_client == null) client.close();
    }
  }
}
