import 'package:cloud_firestore/cloud_firestore.dart';
import 'account_access.dart';

/// Lecturas de estado propio; las escrituras solo se realizan por el backend.
class VerificationRepository {
  VerificationRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Stream<List<UniversityRequest>> ownRequests(String uid) => _db
      .collection('verificationRequests')
      .where('uid', isEqualTo: uid)
      .limit(20)
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => UniversityRequest.fromMap(d.id, d.data()))
            .toList(),
      );
}
