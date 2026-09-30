import 'package:cloud_firestore/cloud_firestore.dart';
import '../discovery/discovery_models.dart';
import 'student_match.dart';

class MatchEntry {
  const MatchEntry({required this.match, this.profile, this.careerName});
  final StudentMatch match;
  final DiscoveryCandidate? profile;
  final String? careerName;
}

class MatchesService {
  MatchesService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<Set<String>> watchActiveIds(String uid) => _db
      .collection('matches')
      .where('users', arrayContains: uid)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .where((doc) => doc.data()['isActive'] == true)
            .map((doc) => doc.id)
            .toSet(),
      );

  Future<List<MatchEntry>> load(String uid) async {
    final snapshot = await _db
        .collection('matches')
        .where('users', arrayContains: uid)
        .get(const GetOptions(source: Source.server));
    final matches =
        snapshot.docs
            .where((doc) => doc.data()['isActive'] == true)
            .map((doc) => StudentMatch.fromMap(doc.data()))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Orden local: consulta simple con índice array automático, sin compuesto.
    final careers = <String, String>{};
    final entries = <MatchEntry>[];
    for (final match in matches) {
      DiscoveryCandidate? profile;
      String? careerName;
      if (match.isActive) {
        try {
          final card = await _db
              .collection('discoveryCards')
              .doc(match.otherUser(uid))
              .get(const GetOptions(source: Source.server));
          if (card.exists && card.data()?['isActive'] == true) {
            profile = DiscoveryCandidate.fromMap(card.id, card.data()!);
            if (!careers.containsKey(profile.careerId)) {
              final career = await _db
                  .collection('careers')
                  .doc(profile.careerId)
                  .get(const GetOptions(source: Source.server));
              careers[profile.careerId] =
                  career.data()?['name'] as String? ?? 'Carrera no disponible';
            }
            careerName = careers[profile.careerId];
          }
        } on FirebaseException catch (error) {
          if (error.code != 'permission-denied') rethrow;
          // Un perfil desactivado o sin ficha vigente conserva el match.
          profile = null;
        }
      }
      entries.add(
        MatchEntry(match: match, profile: profile, careerName: careerName),
      );
    }
    return entries;
  }
}
