import 'package:cloud_firestore/cloud_firestore.dart';
import '../preferences/discovery_preferences.dart';

/// Proyección sin birthDate, email, rol ni preferencias. La edad se renueva al
/// guardar perfil/fotos y las reglas rechazan edades vencidas tras un cumpleaños.
abstract final class DiscoveryPublication {
  static Map<String, dynamic> card(
    Map<String, dynamic> user, {
    DateTime? today,
  }) => {
    'age': user['birthDate'] is Timestamp
        ? ageOn((user['birthDate'] as Timestamp).toDate(), today: today)
        : null,
    for (final field in [
      'firstName',
      'gender',
      'description',
      'careerId',
      'mainPhotoUrl',
      'interestIds',
      'isActive',
      'updatedAt',
    ])
      field: user[field],
  };
  static void write(
    Transaction tx,
    FirebaseFirestore db,
    String uid,
    Map<String, dynamic> user,
  ) {
    tx.set(db.collection('discoveryIndex').doc(uid), {
      'isActive': user['isActive'],
      'updatedAt': user['updatedAt'],
    });
    tx.set(db.collection('discoveryCards').doc(uid), card(user));
  }
}
