import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingChatUpload {
  const PendingChatUpload(
    this.matchId,
    this.uid,
    this.messageId,
    this.createdAt,
  );
  final String matchId, uid, messageId;
  final DateTime createdAt;
  String get path => 'chat_media/$matchId/$uid/$messageId';
  bool get valid =>
      RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$').hasMatch(matchId) &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(uid) &&
      matchId.split('.').contains(uid) &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(messageId);
}

abstract interface class PendingChatUploads {
  Future<void> add(PendingChatUpload upload);
  Future<void> remove(PendingChatUpload upload);
  Future<List<PendingChatUpload>> list(String uid);
}

/// Registro de reintentos, sin bytes ni credenciales. No es una cola garantizada.
class PreferencesPendingChatUploads implements PendingChatUploads {
  PreferencesPendingChatUploads(this.namespace);
  final String namespace;
  final _prefs = SharedPreferencesAsync();
  String _prefix(String uid) => 'chat_pending:$namespace:$uid:';
  String _key(PendingChatUpload upload) =>
      '${_prefix(upload.uid)}${upload.messageId}';

  @override
  Future<void> add(PendingChatUpload upload) => _prefs.setString(
    _key(upload),
    jsonEncode({
      'matchId': upload.matchId,
      'uid': upload.uid,
      'messageId': upload.messageId,
      'createdAt': upload.createdAt.millisecondsSinceEpoch,
    }),
  );

  @override
  Future<void> remove(PendingChatUpload upload) => _prefs.remove(_key(upload));

  @override
  Future<List<PendingChatUpload>> list(String uid) async {
    final result = <PendingChatUpload>[];
    for (final key in await _prefs.getKeys()) {
      if (!key.startsWith(_prefix(uid))) continue;
      try {
        final raw = await _prefs.getString(key);
        if (raw == null) continue;
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final upload = PendingChatUpload(
          data['matchId'] as String,
          data['uid'] as String,
          data['messageId'] as String,
          DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
        );
        if (upload.uid == uid && upload.valid && _key(upload) == key) {
          result.add(upload);
        }
      } catch (_) {
        // No transformar datos locales corruptos en solicitudes de borrado.
      }
    }
    return result;
  }
}
