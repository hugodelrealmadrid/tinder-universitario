import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../matches/student_match.dart';
import 'chat_message.dart';
import '../safety/safety_models.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

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

  Future<String> mediaUrl(String path) =>
      FirebaseStorage.instance.ref(path).getDownloadURL();

  Future<void> sendMedia(
    String matchId,
    String uid,
    Uint8List bytes,
    String type,
    String contentType,
  ) async {
    if (!['image', 'audio'].contains(type) ||
        bytes.isEmpty ||
        bytes.length > (type == 'image' ? 5 : 15) * 1024 * 1024) {
      throw const ChatException('Imagen: máximo 5 MB. Audio: máximo 15 MB.');
    }
    final parent = _db.collection('matches').doc(matchId);
    final match = _participant(
      await parent.get(const GetOptions(source: Source.server)),
      uid,
    );
    if (!match.isActive) throw const ChatException('Este match está inactivo.');
    final message = parent.collection('messages').doc();
    final path = 'chat_media/$matchId/$uid/${message.id}';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    try {
      await message.set({
        'senderId': uid,
        'text': '',
        'type': type,
        'mediaPath': path,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Preserve the original failure even if cleanup cannot reach Storage.
      try {
        await ref.delete();
      } catch (_) {}
      rethrow;
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

String chatError(Object error) {
  if (error is ChatException) return error.message;
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'No tienes permiso para esta acción. El match puede estar inactivo.';
  }
  return 'No se pudo conectar con el chat. Revisa tu conexión e inténtalo de nuevo.';
}
