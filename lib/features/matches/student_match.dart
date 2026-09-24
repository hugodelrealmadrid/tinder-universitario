import 'package:cloud_firestore/cloud_firestore.dart';
import '../discovery/discovery_models.dart';

class StudentMatch {
  const StudentMatch({
    required this.users,
    required this.createdAt,
    required this.isActive,
  });
  final List<String> users;
  final DateTime createdAt;
  final bool isActive;

  static List<String> orderedUsers(String a, String b) {
    SwipeDecision.idFor(a, b); // Comparte validación de UID y separador.
    return [a, b]..sort();
  }

  static String idFor(String a, String b) => orderedUsers(a, b).join('.');

  factory StudentMatch.fromMap(Map<String, dynamic> data) => StudentMatch(
    users: List<String>.from(data['users'] as List),
    createdAt: (data['createdAt'] as Timestamp).toDate(),
    isActive: data['isActive'] == true,
  );

  String otherUser(String uid) {
    if (users.length != 2 || !users.contains(uid) || users[0] == users[1]) {
      throw const FormatException('Participantes del match inválidos.');
    }
    return users.firstWhere((value) => value != uid);
  }
}
