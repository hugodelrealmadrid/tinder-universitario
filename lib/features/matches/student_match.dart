import 'package:cloud_firestore/cloud_firestore.dart';
import '../discovery/discovery_models.dart';

class StudentMatch {
  const StudentMatch({
    required this.users,
    required this.createdAt,
    required this.isActive,
    this.closedAt,
    this.closedBy,
  });
  final List<String> users;
  final DateTime createdAt;
  final bool isActive;
  final DateTime? closedAt;
  final String? closedBy;

  bool get isCoherent {
    if (users.length != 2) return false;
    try {
      final ordered = orderedUsers(users[0], users[1]);
      if (ordered[0] != users[0] || ordered[1] != users[1]) return false;
    } catch (_) {
      return false;
    }
    return isActive
        ? closedAt == null && closedBy == null
        : closedAt != null && closedBy != null && users.contains(closedBy);
  }

  static List<String> orderedUsers(String a, String b) {
    SwipeDecision.idFor(a, b); // Comparte validación de UID y separador.
    return [a, b]..sort();
  }

  static String idFor(String a, String b) => orderedUsers(a, b).join('.');

  static Map<String, dynamic> closeFields(String uid) => {
    'isActive': false,
    'closedAt': FieldValue.serverTimestamp(),
    'closedBy': uid,
  };

  factory StudentMatch.fromMap(Map<String, dynamic> data) {
    if (data['isActive'] is! bool) {
      throw const FormatException('Estado de match inválido.');
    }
    final result = StudentMatch(
      users: List<String>.from(data['users'] as List),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isActive: data['isActive'] == true,
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      closedBy: data['closedBy'] as String?,
    );
    if (!result.isCoherent) {
      throw const FormatException('Estado de cierre del match inválido.');
    }
    return result;
  }

  String otherUser(String uid) {
    if (users.length != 2 || !users.contains(uid) || users[0] == users[1]) {
      throw const FormatException('Participantes del match inválidos.');
    }
    return users.firstWhere((value) => value != uid);
  }
}
