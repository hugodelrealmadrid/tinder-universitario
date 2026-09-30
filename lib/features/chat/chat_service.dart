import 'package:cloud_firestore/cloud_firestore.dart';
import '../matches/student_match.dart';
import 'chat_message.dart';

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
