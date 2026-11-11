import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/academic_selector.dart';
import 'discovery_preferences.dart';
import '../profile/student_profile.dart';

class PreferencesService {
  PreferencesService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Future<List<CatalogItem>> careers() async {
    final snapshot = await _db
        .collection('careers')
        .where('isActive', isEqualTo: true)
        .get(const GetOptions(source: Source.server));
    return snapshot.docs
        .map((d) => CatalogItem(d.id, d.data()['name'] as String))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<CatalogItem>> academicOptions(String collection) async {
    final options = await AcademicDirectory(_db).options(collection);
    return options.map((item) => CatalogItem(item.id, item.name)).toList();
  }

  Future<bool> hasUniversity(String uid) async =>
      (await _db.doc('users/$uid').get(const GetOptions(source: Source.server)))
              .data()?['universityId']
          is String;

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
    final current = await load(uid);
    final activeCareers = (await careers()).map((x) => x.id).toSet();
    if (value.careerIds.any(
      (id) =>
          !activeCareers.contains(id) &&
          !(current?.careerIds.contains(id) ?? false),
    )) {
      throw const DiscoveryException(
        'Selecciona carreras activas del catálogo.',
      );
    }
    // La transacción confirma en servidor y no anuncia un guardado solo local.
    await _db.runTransaction((tx) async {
      final ref = _db.collection('preferences').doc(uid);
      final current = await tx.get(ref);
      final fields = value.toFirestore();
      if (current.exists) {
        if (value.universityMode != 'selected' &&
            current.data()!.containsKey('universityIds') &&
            current.data()!.containsKey('universityMode')) {
          fields['universityIds'] = FieldValue.delete();
        }
        tx.update(ref, fields);
      } else {
        tx.set(ref, fields);
      }
    });
  }
}
