import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class VerificationFailure implements Exception {
  const VerificationFailure(this.code);
  final String code;
  String get message => switch (code) {
    'invalid-media' => 'El archivo está dañado o su contenido no coincide con el formato permitido.',
    'conflict' => 'La solicitud cambió o ya fue resuelta. Actualiza la lista.',
    'invalid-image' || 'payload-too-large' =>
      'Utiliza una foto JPG, PNG o WebP válida de hasta 5 MB.',
    'rate-limited' => 'Demasiadas operaciones. Espera un minuto y reintenta.',
    'unauthenticated' => 'Tu sesión venció. Vuelve a iniciar sesión.',
    'permission-denied' =>
      'No tienes autorización o el estado de la cuenta cambió.',
    'last-superadmin' =>
      'Debe permanecer al menos un superadministrador activo.',
    _ =>
      'No se pudo completar la operación. Comprueba la conexión y reintenta.',
  };
}

String verificationError(Object error) => error is VerificationFailure
    ? error.message
    : 'No se pudo completar la operación. Comprueba la conexión y reintenta.';

/// En producción se requiere configurar un backend HTTPS confiable por separado.
/// El demo utiliza solo el proxy del mismo servidor local, protegido por su CSP.
class VerificationClient {
  VerificationClient({FirebaseAuth? auth, Uri? endpoint, http.Client? client})
    : _auth = auth ?? FirebaseAuth.instance,
      _endpoint = endpoint ?? _configuredEndpoint(),
      _client = client ?? http.Client();
  final FirebaseAuth _auth;
  final Uri? _endpoint;
  final http.Client _client;
  static Uri? _configuredEndpoint() {
    if (const bool.fromEnvironment('TINDER_DEMO')) {
      return Uri.parse('http://127.0.0.1:7357/__demo/api/');
    }
    const endpoint = String.fromEnvironment('VERIFICATION_BACKEND_URL');
    return endpoint.isEmpty ? null : Uri.parse(endpoint);
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Object? data,
    Uint8List? bytes,
    Map<String, String> headers = const {},
  }) async {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('El backend de verificación no está configurado.');
    }
    if (_auth.app.options.projectId.startsWith('demo-') &&
        endpoint.origin != 'http://127.0.0.1:7357') {
      throw StateError('El demo exige el backend local.');
    }
    if (!_auth.app.options.projectId.startsWith('demo-') &&
        endpoint.scheme != 'https') {
      throw StateError('Se requiere HTTPS.');
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('Inicia sesión.');
    final token = await user.getIdToken();
    final request = http.Request(method, endpoint.resolve(path))
      ..headers.addAll({'Authorization': 'Bearer $token', ...headers});
    if (bytes != null) {
      request.bodyBytes = bytes;
    } else if (method == 'POST') {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(data ?? {});
    }
    final response = await (() async => http.Response.fromStream(
      await _client.send(request),
    ))().timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      String code = 'operation-failed';
      try {
        code = (jsonDecode(response.body) as Map)['error'] as String;
      } catch (_) {}
      throw VerificationFailure(code);
    }
    return response;
  }

  Future<void> provision() async {
    await _request('POST', 'account/provision');
  }

  Future<String> begin() async =>
      (jsonDecode((await _request('POST', 'verification/begin')).body)
              as Map<String, dynamic>)['requestId']
          as String;
  Future<void> upload(String id, Uint8List bytes) async {
    await _request(
      'POST',
      'verification/upload/${Uri.encodeComponent(id)}',
      bytes: bytes,
      headers: {'Content-Type': 'image/png'},
    );
  }

  Future<void> withdraw(String id) async {
    await _request('POST', 'verification/withdraw', data: {'requestId': id});
  }

  Future<void> decide(String id, String status, String reasonCode) async {
    await _request(
      'POST',
      'verification/decide',
      data: {'requestId': id, 'status': status, 'reasonCode': reasonCode},
    );
  }

  Future<void> role(String uid, String role) async {
    await _request(
      'POST',
      'administration/role',
      data: {'uid': uid, 'role': role},
    );
  }

  Future<void> suspend(String uid, bool suspended, String reasonCode) async {
    await _request(
      'POST',
      'administration/suspend',
      data: {'uid': uid, 'suspended': suspended, 'reasonCode': reasonCode},
    );
  }

  Future<Uint8List> document(String id) async => (await _request(
    'GET',
    'verification/document/${Uri.encodeComponent(id)}',
  )).bodyBytes;
  Future<void> uploadChat(String path, Uint8List bytes, String mime) async {
    await _request(
      'POST',
      'chat/upload',
      bytes: bytes,
      headers: {'Content-Type': mime, 'X-Chat-Path': path},
    );
  }

  void close() => _client.close();
  Future<void> uploadPhoto(String path, Uint8List bytes, String mime) async {
    await _request(
      'POST',
      'profile/upload',
      bytes: bytes,
      headers: {'Content-Type': mime, 'X-Chat-Path': path},
    );
  }

  Future<Uint8List> photoBytes(String path) async => (await _request(
    'GET',
    'profile/media/${Uri.encodeComponent(path)}',
  )).bodyBytes;
  Future<void> deletePhoto(String path) async {
    await _request('POST', 'profile/delete', data: {'path': path});
  }

  Future<void> deleteChat(String path) async {
    await _request('POST', 'chat/delete', data: {'path': path});
  }

  Future<Map<String, dynamic>?> ownRequest() async =>
      jsonDecode((await _request('GET', 'verification/own')).body)
          as Map<String, dynamic>?;
  Future<List<dynamic>> audit({String? cursor}) async =>
      jsonDecode(
            (await _request(
              'GET',
              'administration/audit${cursor == null ? '' : '?cursor=${Uri.encodeComponent(cursor)}'}',
            )).body,
          )
          as List<dynamic>;
  Future<List<dynamic>> requests({
    String status = 'pending',
    String? cursor,
  }) async =>
      jsonDecode(
            (await _request(
              'GET',
              'verification/requests?status=$status${cursor == null ? '' : '&cursor=${Uri.encodeComponent(cursor)}'}',
            )).body,
          )
          as List<dynamic>;
  Future<List<dynamic>> reports() async =>
      jsonDecode((await _request('GET', 'administration/reports')).body)
          as List<dynamic>;
  Future<Map<String, dynamic>> account(String uid) async =>
      jsonDecode(
            (await _request(
              'GET',
              'administration/account/${Uri.encodeComponent(uid)}',
            )).body,
          )
          as Map<String, dynamic>;
  Future<void> reviewReport(String reportId, String resolution) async {
    await _request(
      'POST',
      'administration/report',
      data: {'reportId': reportId, 'resolution': resolution},
    );
  }

  Future<Map<String, dynamic>> chatMetadata(String path) async =>
      jsonDecode(
            (await _request(
              'GET',
              'chat/metadata/${Uri.encodeComponent(path)}',
            )).body,
          )
          as Map<String, dynamic>;
  Future<Uint8List> chatBytes(String path) async => (await _request(
    'GET',
    'chat/media/${Uri.encodeComponent(path)}',
  )).bodyBytes;
}
