import 'package:cloud_firestore/cloud_firestore.dart';

/// Proyección explícita, sin email, rol ni preferencias. Se sincroniza dentro
/// de la misma transacción que Guardar perfil o una acción sobre sus fotos.
abstract final class DiscoveryPublication {
  static Map<String, dynamic> card(Map<String, dynamic> user) => {
    for (final field in [
      'firstName',
      'birthDate',
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
