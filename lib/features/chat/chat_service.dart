import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../matches/student_match.dart';
import 'chat_message.dart';
import '../safety/safety_models.dart';
import 'chat_media_validation.dart';
import 'pending_chat_uploads.dart';
import '../verification/backend_client.dart';

class ChatService {
  ChatService({
    FirebaseFirestore? firestore,
    ChatMediaStore? mediaStore,
    this._pendingUploads,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _mediaStore = mediaStore ?? FirebaseChatMediaStore();
  final FirebaseFirestore _db;
  final ChatMediaStore _mediaStore;
  PendingChatUploads? _pendingUploads;
  PendingChatUploads get _pending =>
      _pendingUploads ??= PreferencesPendingChatUploads(
        '${_db.app.options.projectId}:${FirebaseStorage.instance.bucket}',
      );
  static final _activeUploads = <String>{};

  StudentMatch _participant(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String uid,
  ) {
    if (!snapshot.exists) {
      throw const ChatException('Este chat no está disponible.');
    }
    final match = StudentMatch.fromMap(snapshot.data()!);
    final other = match.otherUser(uid);
    if (StudentMatch.idFor(uid, other) != snapshot.id) {
      throw const ChatException('Este chat no está disponible.');
    }
    return match;
  }

  Stream<StudentMatch> watchMatch(String matchId, String uid) => _db
      .collection('matches')
      .doc(matchId)
      .snapshots(includeMetadataChanges: true)
      .where((snapshot) => !snapshot.metadata.hasPendingWrites)
      .map((snapshot) => _participant(snapshot, uid));

  Stream<List<ChatMessage>> watchMessages(String matchId) => _db
      .collection('matches')
      .doc(matchId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(ChatLimits.historyLimit)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.reversed
            .map((doc) => ChatMessage.fromMap(doc.id, doc.data()))
            .toList(),
      );

  Future<void> markRead(String matchId, String uid, ChatMessage message) async {
    if (message.senderId == uid ||
        message.readAt != null ||
        message.createdAt == null) {
      return;
    }
    await _db
        .collection('matches')
        .doc(matchId)
        .collection('messages')
        .doc(message.id)
        .update({'readAt': FieldValue.serverTimestamp()});
  }

  Future<ChatMediaData> mediaData(String path, {String? type}) async {
    final data = await _mediaStore.read(path);
    await ChatMediaValidation.validate(
      data.bytes,
      type ??
          (ChatMediaValidation.images.contains(data.contentType)
              ? 'image'
              : 'audio'),
      data.contentType,
    );
    return data;
  }

  /// Solo borra si una lectura del servidor confirma la ausencia del mensaje.
  Future<bool> _reconcile(PendingChatUpload upload) async {
    DocumentSnapshot<Map<String, dynamic>> message;
    try {
      message = await _db
          .doc('matches/${upload.matchId}/messages/${upload.messageId}')
          .get(const GetOptions(source: Source.server));
    } catch (_) {
      throw const ChatMediaPendingException();
    }
    if (message.metadata.isFromCache || message.metadata.hasPendingWrites) {
      throw const ChatMediaPendingException();
    }
    if (message.exists) {
      if (message.data()?['mediaPath'] != upload.path ||
          message.data()?['senderId'] != upload.uid) {
        throw const ChatException('Referencia multimedia inconsistente.');
      }
      try {
        await _pending.remove(upload);
      } catch (_) {
        // El mensaje está confirmado: fallar al limpiar el registro no revierte el envío.
      }
      return true;
    }
    try {
      await _mediaStore.delete(upload.path);
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
    await _pending.remove(upload);
    return false;
  }

  Future<void> recoverPendingMedia(
    String uid, {
    Duration minimumAge = const Duration(minutes: 30),
  }) async {
    for (final upload in await _pending.list(uid)) {
      if (!upload.valid ||
          upload.uid != uid ||
          _activeUploads.contains(upload.path) ||
          DateTime.now().difference(upload.createdAt) < minimumAge) {
        continue;
      }
      try {
        await _reconcile(upload);
      } catch (_) {
        // Conservar el registro: no borrar a ciegas ante errores o falta de red.
      }
    }
  }

  Future<void> sendMedia(
    String matchId,
    String uid,
    Uint8List bytes,
    String type,
    String contentType, {
    int? durationMs,
  }) async {
    await ChatMediaValidation.validate(bytes, type, contentType);
    if (durationMs != null &&
        (type != 'audio' || durationMs <= 0 || durationMs > 60000)) {
      throw const ChatException('Duración de nota de voz no válida.');
    }
    final parent = _db.collection('matches').doc(matchId);
    final match = _participant(
      await parent.get(const GetOptions(source: Source.server)),
      uid,
    );
    if (!match.isActive) throw const ChatException('Este match está inactivo.');
    final ownBlock = await _db
        .doc('blocks/${SafetyIds.idFor(uid, match.otherUser(uid))}')
        .get(const GetOptions(source: Source.server));
    if (ownBlock.exists) {
      throw const ChatException('No puedes enviar archivos en este chat.');
    }
    final message = parent.collection('messages').doc();
    final path = 'chat_media/$matchId/$uid/${message.id}';
    final pending = PendingChatUpload(matchId, uid, message.id, DateTime.now());
    await _pending.add(pending); // Si falla el registro, no iniciar la subida.
    _activeUploads.add(path);
    try {
      await _mediaStore.upload(path, bytes, contentType);
      await _mediaStore.verifyUpload(path, bytes.length, contentType);
      await message.set({
        'senderId': uid,
        'text': '',
        'type': type,
        'mediaPath': path,
        'durationMs': ?durationMs,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      try {
        // Una respuesta perdida no significa que Firestore no haya guardado.
        if (await _reconcile(pending)) return;
      } on ChatMediaPendingException {
        rethrow;
      } catch (_) {}
      rethrow;
    } finally {
      _activeUploads.remove(path);
    }
    try {
      await _pending.remove(pending);
    } catch (_) {
      // La recuperación futura reconocerá el mensaje publicado y no lo borrará.
    }
  }

  Future<void> send(String matchId, String uid, String draft) async {
    final text = ChatLimits.normalize(draft);
    final parent = _db.collection('matches').doc(matchId);
    final match = _participant(
      await parent.get(const GetOptions(source: Source.server)),
      uid,
    );
    if (!match.isActive) {
      throw const ChatException(
        'Este match está inactivo. No puedes enviar mensajes.',
      );
    }
    final ownBlock = await _db
        .collection('blocks')
        .doc(SafetyIds.idFor(uid, match.otherUser(uid)))
        .get(const GetOptions(source: Source.server));
    if (ownBlock.exists) {
      throw const ChatException('No puedes enviar mensajes en este chat.');
    }
    // Las reglas vuelven a comprobar pertenencia y estado al escribir,
    // incluso si el match se desactiva después de esta lectura.
    await parent.collection('messages').add({
      'senderId': uid,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

class ChatMediaPendingException extends ChatException {
  const ChatMediaPendingException()
    : super(
        'No se pudo confirmar el envío. El archivo queda pendiente de revisión; reenviarlo podría duplicar el mensaje.',
      );
}

class ChatMediaData {
  const ChatMediaData(this.bytes, this.contentType);
  final Uint8List bytes;
  final String? contentType;
}

abstract interface class ChatMediaStore {
  Future<ChatMediaData> read(String path);
  Future<void> upload(String path, Uint8List bytes, String contentType);
  Future<void> delete(String path);
  Future<void> verifyUpload(String path, int size, String contentType);
}

class FirebaseChatMediaStore implements ChatMediaStore {
  FirebaseChatMediaStore({FirebaseStorage? storage, FirebaseAuth? auth})
    : _injectedAuth = auth;
  final FirebaseAuth? _injectedAuth;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;
  @override
  Future<ChatMediaData> read(String path) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const ChatException('Inicia sesión para descargar este archivo.');
    }
    final backend = VerificationClient(auth: _auth);
    try {
      final metadata = await backend.chatMetadata(path);
      final mime = metadata['contentType'] as String;
      final size = metadata['size'] as int;
      if (!ChatMediaValidation.images.contains(mime) &&
          !ChatMediaValidation.audios.contains(mime)) {
        throw const ChatException('Formato multimedia no permitido.');
      }
      final type = ChatMediaValidation.images.contains(mime)
          ? 'image'
          : 'audio';
      final limit = ChatMediaValidation.limit(type);
      if (size <= 0 || size > limit) {
        throw const ChatException('Tamaño multimedia no permitido.');
      }
      final bytes = await backend.chatBytes(path);
      if (bytes.length != size || _auth.currentUser?.uid != uid) {
        throw const ChatException(
          'El archivo o la sesión cambiaron durante la descarga.',
        );
      }
      return ChatMediaData(bytes, mime);
    } finally {
      backend.close();
    }
  }

  @override
  Future<void> verifyUpload(String path, int size, String contentType) async {
    final backend = VerificationClient(auth: _auth);
    try {
      final metadata = await backend.chatMetadata(path);
      if (metadata['size'] != size || metadata['contentType'] != contentType) {
        throw const ChatException('No se pudo confirmar el archivo subido.');
      }
    } finally {
      backend.close();
    }
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    final backend = VerificationClient(auth: _auth);
    try {
      await backend.uploadChat(path, bytes, contentType);
    } finally {
      backend.close();
    }
  }

  @override
  Future<void> delete(String path) async {
    final backend = VerificationClient(auth: _auth);
    try {
      await backend.deleteChat(path);
    } finally {
      backend.close();
    }
  }
}

String chatError(Object error) {
  if(error is VerificationFailure) return error.message;
  if (error is ChatException) return error.message;
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'No tienes permiso para esta acción. El match puede estar inactivo.';
  }
  return 'No se pudo conectar con el chat. Revisa tu conexión e inténtalo de nuevo.';
}
