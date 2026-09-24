import 'package:cloud_firestore/cloud_firestore.dart';
import 'discovery_preferences.dart';

class PreferencesService {
  PreferencesService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Future<DiscoveryPreferences?> load(String uid) async {
    final doc = await _db
        .collection('preferences')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.exists ? DiscoveryPreferences.fromMap(doc.data()!) : null;
  }

  Future<void> save(String uid, DiscoveryPreferences value) async {
    if (!value.isValid) {
      throw const DiscoveryException(
        'Selecciona un género y un rango de edad entre 18 y 100, con mínimo menor o igual al máximo.',
      );
    }
    // La transacción confirma en servidor y no anuncia un guardado solo local.
    await _db.runTransaction((tx) async {
      final ref = _db.collection('preferences').doc(uid);
      await tx.get(ref);
      tx.set(ref, value.toFirestore());
    });
  }
}
