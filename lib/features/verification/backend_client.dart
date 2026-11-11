import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../stories/story_upload.dart';

class VerificationFailure implements Exception {
  const VerificationFailure(this.code);
  final String code;
  String get message => switch (code) {
    'duplicate-catalog' =>
      'Ya existe un elemento con ese nombre en el mismo ámbito.',
    'immutable-affiliation' =>
      'No se puede reasignar la universidad de una carrera existente.',
    'inactive-university' =>
      'Selecciona una universidad activa para crear la carrera.',
    'academic-registration-required' =>
      'Completa tu universidad y carrera antes de solicitar verificación.',
    'invalid-affiliation' =>
      'La universidad y la carrera no coinciden. Revisa tu registro.',
    'invalid-argument' => 'Revisa los datos y sus formatos antes de guardar.',
    'invalid-media' =>
      'El archivo está dañado o su contenido no coincide con el formato permitido.',
    'already-decided' => 'Ya evaluaste este perfil.',
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
    if (const bool.fromEnvironment('LIGO_STAGING')) {
      return Uri.parse('http://127.0.0.1:7466/');
    }
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
    void Function(double)? progress,
  }) async {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('El backend de verificación no está configurado.');
    }
    final project = _auth.app.options.projectId;
    if (const String.fromEnvironment('APP_ENV') == 'production') {
      if (project.startsWith('demo-') || endpoint.scheme != 'https') {
        throw StateError('Producción requiere un proyecto alojado y HTTPS.');
      }
    } else if (project == 'demo-ligo-staging') {
      if (!const bool.fromEnvironment('LIGO_STAGING') ||
          endpoint.origin != 'http://127.0.0.1:7466' ||
          endpoint.path != '/') {
        throw StateError('El staging exige su backend local exclusivo.');
      }
    } else if (project.startsWith('demo-') &&
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
    final uri = endpoint.resolve(path);
    final authorization = {'Authorization': 'Bearer $token', ...headers};
    final browserUpload = bytes != null && progress != null
        ? storyBrowserUpload(uri, authorization, bytes, progress)
        : null;
    final response =
        await (browserUpload ??
                _send(method, uri, authorization, data, bytes, progress))
            .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      String code = 'operation-failed';
      try {
        code = (jsonDecode(response.body) as Map)['error'] as String;
      } catch (_) {}
      throw VerificationFailure(code);
    }
    return response;
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? data,
    Uint8List? bytes,
    void Function(double)? progress,
  ) async {
    if (bytes != null && progress != null) {
      final upload = http.StreamedRequest(method, uri)
        ..contentLength = bytes.length
        ..headers.addAll(headers);
      final writing = upload.sink
          .addStream(_uploadChunks(bytes, progress))
          .whenComplete(upload.sink.close);
      final reading = _client.send(upload).then(http.Response.fromStream);
      final results = await Future.wait([writing, reading], eagerError: true);
      return results.last as http.Response;
    }
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (bytes != null) {
      request.bodyBytes = bytes;
    } else if (method == 'POST') {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(data ?? {});
    }
    return http.Response.fromStream(await _client.send(request));
  }

  Stream<List<int>> _uploadChunks(
    Uint8List bytes,
    void Function(double) progress,
  ) async* {
    for (var start = 0; start < bytes.length; start += 65536) {
      final end = math.min(start + 65536, bytes.length);
      yield Uint8List.sublistView(bytes, start, end);
      progress(end / bytes.length);
    }
  }

  Future<Map<String, dynamic>> stories(
    String action, {
    String? id,
    String? cursor,
  }) async {
    final uri = Uri(
      path: 'stories/$action',
      queryParameters: {'id': ?id, 'cursor': ?cursor},
    );
    return jsonDecode((await _request('GET', uri.toString())).body)
        as Map<String, dynamic>;
  }

  Future<Uint8List> storyMedia(String id) async => (await _request(
    'GET',
    Uri(path: 'stories/media', queryParameters: {'id': id}).toString(),
  )).bodyBytes;
  Future<void> storyAction(String action, String id, {String? text}) async {
    await _request(
      'POST',
      Uri(path: 'stories/$action', queryParameters: {'id': id}).toString(),
      bytes: text == null ? null : Uint8List.fromList(utf8.encode(text)),
      headers: text == null
          ? const {}
          : {'Content-Type': 'text/plain; charset=utf-8'},
    );
  }

  Future<void> publishStory(
    Uint8List bytes,
    String mime,
    String caption,
    void Function(double) progress,
  ) async {
    await _request(
      'POST',
      'stories/publish',
      bytes: bytes,
      headers: {
        'Content-Type': mime,
        'X-Story-Caption': Uri.encodeComponent(caption),
      },
      progress: progress,
    );
  }

  Future<void> readNotification(String id) async {
    await _request('POST', 'notifications/read', data: {'id': id});
  }

  static const datingWritesEnabled = bool.fromEnvironment(
    'LIGO_BACKEND_WRITES',
  );

  Future<bool> decideDiscovery(String target, String type) async {
    final response = await _request(
      'POST',
      'discovery/decide',
      data: {'target': target, 'type': type},
    );
    return (jsonDecode(response.body) as Map)['createdMatch'] == true;
  }

  Future<void> sendChatMessage(
    String matchId,
    String messageId,
    String text, {
    String type = 'text',
    int? durationMs,
  }) async {
    await _request(
      'POST',
      'chat/send',
      data: {
        'matchId': matchId,
        'messageId': messageId,
        'text': text,
        'type': type,
        'durationMs': ?durationMs,
      },
    );
  }

  Future<void> sendChatReceipt(String matchId, String messageId) async {
    await _request(
      'POST',
      'chat/receipt',
      data: {'matchId': matchId, 'messageId': messageId},
    );
  }

  Future<void> notificationPreferences(bool push) async {
    await _request('POST', 'notifications/preferences', data: {'push': push});
  }

  Future<void> notificationDevice(String token, String platform) async {
    await _request(
      'POST',
      'notifications/device',
      data: {'token': token, 'platform': platform},
    );
  }

  Future<void> removeNotificationDevice(String token) async {
    await _request(
      'POST',
      'notifications/device/remove',
      data: {'token': token},
    );
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

  Future<Map<String, dynamic>> catalogs(String kind, {String? cursor}) async =>
      jsonDecode(
            (await _request(
              'GET',
              'administration/catalogs/${Uri.encodeComponent(kind)}${cursor == null ? '' : '?cursor=${Uri.encodeComponent(cursor)}'}',
            )).body,
          )
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> saveCatalog(
    String kind,
    Map<String, dynamic> data, {
    String? id,
    int? expectedRevision,
    required String requestId,
  }) async =>
      jsonDecode(
            (await _request(
              'POST',
              'administration/catalog',
              data: {
                'kind': kind,
                'id': id,
                'data': data,
                'expectedRevision': expectedRevision,
                'requestId': requestId,
              },
            )).body,
          )
          as Map<String, dynamic>;
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
  Future<Map<String, dynamic>> academicCatalog({
    String? university,
    String? campus,
    String? cursor,
  }) async {
    final query = Uri(
      queryParameters: {
        'university': ?university,
        'campus': ?campus,
        'cursor': ?cursor,
      },
    ).query;
    return jsonDecode(
          (await _request('GET', 'administration/academic?$query')).body,
        )
        as Map<String, dynamic>;
  }

  Future<void> saveAcademic(Map<String, dynamic> data) async {
    await _request('POST', 'administration/academic', data: data);
  }

  Future<Map<String, dynamic>> administrationSummary() async =>
      Map<String, dynamic>.from(
        jsonDecode((await _request('GET', 'administration/summary')).body)
            as Map,
      );
  Future<Uint8List> administrationPhoto(String path) async => (await _request(
    'GET',
    'administration/profile-photo?photo=${Uri.encodeQueryComponent(path)}',
  )).bodyBytes;

  Future<Map<String, dynamic>> administrationDossier(String uid) async =>
      Map<String, dynamic>.from(
        jsonDecode(
              (await _request(
                'GET',
                'administration/dossier?user=${Uri.encodeQueryComponent(uid)}',
              )).body,
            )
            as Map,
      );

  Future<Map<String, dynamic>> dossierHistory(
    String uid,
    String kind, {
    String? cursor,
  }) async {
    final query = Uri(
      queryParameters: {'user': uid, 'kind': kind, 'cursor': ?cursor},
    ).query;
    return jsonDecode(
          (await _request('GET', 'administration/dossier/history?$query')).body,
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> administrationUsers({
    String? cursor,
  }) async => Map<String, dynamic>.from(
    jsonDecode(
          (await _request(
            'GET',
            'administration/users${cursor == null ? '' : '?cursor=${Uri.encodeComponent(cursor)}'}',
          )).body,
        )
        as Map,
  );
  Future<Map<String, dynamic>> eventFeed({
    String? cursor,
  }) async => Map<String, dynamic>.from(
    jsonDecode(
          (await _request(
            'GET',
            'administration/event-feed${cursor == null ? '' : '?cursor=${Uri.encodeComponent(cursor)}'}',
          )).body,
        )
        as Map,
  );
  Future<Map<String, dynamic>> reportFeed({
    String status = 'pending',
    String? cursor,
  }) async => Map<String, dynamic>.from(
    jsonDecode(
          (await _request(
            'GET',
            'administration/report-feed?status=${Uri.encodeComponent(status)}${cursor == null ? '' : '&cursor=${Uri.encodeComponent(cursor)}'}',
          )).body,
        )
        as Map,
  );
  Future<List<Map<String, dynamic>>> identities(List<String> ids) async {
    final raw =
        jsonDecode(
              (await _request(
                'GET',
                'administration/identities?ids=${Uri.encodeComponent(ids.join(','))}',
              )).body,
            )
            as Map;
    return (raw['items'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

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
