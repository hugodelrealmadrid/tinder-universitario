import 'package:cloud_firestore/cloud_firestore.dart';

abstract final class ChatLimits {
  // Mantener sincronizado con maxMessageLength/maxChatHistory en firestore.rules.
  // Unidades UTF-16: un emoji fuera del plano básico ocupa dos.
  static const maxTextLength = 1000;
  static const historyLimit = 50;

  static String normalize(String draft) {
    final text = draft.trim();
    if (text.isEmpty) {
      throw const ChatException('Escribe un mensaje antes de enviar.');
    }
    if (text.length > maxTextLength) {
      throw const ChatException(
        'El mensaje admite hasta $maxTextLength caracteres.',
      );
    }
    return text;
  }
}

class ChatException implements Exception {
  const ChatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
  });
  final String id, senderId, text;
  // Un serverTimestamp pendiente puede ser null en el snapshot local.
  final DateTime? createdAt;

  factory ChatMessage.fromMap(String id, Map<String, dynamic> data) =>
      ChatMessage(
        id: id,
        senderId: data['senderId'] as String,
        text: data['text'] as String,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      );

  bool isOwn(String uid) => senderId == uid;
}
