import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'student_match.dart';

class UnmatchException implements Exception {
  const UnmatchException(this.message);
  final String message;
}

class UnmatchService {
  UnmatchService({FirebaseFirestore? firestore, String? Function()? currentUid})
    : _db = firestore ?? FirebaseFirestore.instance,
      _currentUid =
          currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);
  final FirebaseFirestore _db;
  final String? Function() _currentUid;

  Future<void> unmatch(String matchId) async {
    final uid = _currentUid();
    if (uid == null) {
      throw const UnmatchException('Inicia sesión para deshacer el match.');
    }
    final ref = _db.collection('matches').doc(matchId);
    await _db.runTransaction((tx) async {
      if (_currentUid() != uid) {
        throw const UnmatchException(
          'La sesión cambió. Vuelve a iniciar sesión.',
        );
      }
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) {
        throw const UnmatchException('Este match no está disponible.');
      }
      final pair = StudentMatch.fromMap(snapshot.data()!);
      if (!pair.users.contains(uid)) {
        throw const UnmatchException('No puedes deshacer este match.');
      }
      if (StudentMatch.idFor(pair.users[0], pair.users[1]) != matchId) {
        throw const UnmatchException('Este match no está disponible.');
      }
      if (!pair.isActive) {
        throw const UnmatchException('Este match ya ha finalizado.');
      }
      tx.update(ref, {
        'isActive': false,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': uid,
      });
    });
  }
}

String unmatchError(Object error) => error is UnmatchException
    ? error.message
    : 'No se pudo deshacer el match. Revisa tu conexión y el estado del match antes de reintentar.';
