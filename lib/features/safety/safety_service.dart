import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../matches/student_match.dart';
import 'safety_models.dart';

class SafetyService {
  SafetyService({FirebaseFirestore? firestore, String? Function()? currentUid})
    : _db = firestore ?? FirebaseFirestore.instance,
      _currentUid =
          currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);
  final FirebaseFirestore _db;
  final String? Function() _currentUid;

  String _actor(String target) {
    final uid = _currentUid();
    if (uid == null) {
      throw const SafetyException('Inicia sesión para continuar.');
    }
    if (uid == target) {
      throw const SafetyException(
        'No puedes realizar esta acción contigo mismo.',
      );
    }
    try {
      SafetyIds.idFor(uid, target);
    } catch (_) {
      throw const SafetyException('La cuenta no está disponible.');
    }
    return uid;
  }

  /// true: creado; false: ya existía. Nunca reescribe un bloqueo.
  Future<bool> block(String target) async {
    final uid = _actor(target);
    final ref = _db.collection('blocks').doc(SafetyIds.idFor(uid, target));
    final pairRef = _db
        .collection('matches')
        .doc(StudentMatch.idFor(uid, target));
    Future<bool> commit() => _db.runTransaction<bool>((tx) async {
      if (_currentUid() != uid) {
        throw const SafetyException(
          'La sesión cambió. Vuelve a iniciar sesión.',
        );
      }
      final existing = await tx.get(ref);
      final snapshot = await tx.get(pairRef);
      StudentMatch? pair;
      if (snapshot.exists) {
        pair = StudentMatch.fromMap(snapshot.data()!);
        if (pair.otherUser(uid) != target) {
          throw const SafetyException('El match no está disponible.');
        }
      }
      // También repara un match activo inconsistente con un bloqueo propio
      // previo, sin modificar el bloqueo ni los cierres ya confirmados.
      if (pair?.isActive == true) {
        tx.update(pairRef, StudentMatch.closeFields(uid));
      }
      if (!existing.exists) {
        tx.set(ref, {
          'blockerId': uid,
          'blockedId': target,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return !existing.exists;
    });
    try {
      return await commit();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
      // Una creación/cierre concurrente puede invalidar la propuesta antes
      // del reintento del SDK. Releer una vez; no ignorar rechazos persistentes.
      return commit();
    }
  }

  Future<void> report(String target, String reason, String details) async {
    final uid = _actor(target);
    if (!ReportReasons.isValid(reason)) {
      throw const SafetyException('Selecciona un motivo válido.');
    }
    if (details.length > ReportReasons.maxDetailsLength) {
      throw const SafetyException(
        'Los detalles no pueden superar 500 caracteres.',
      );
    }
    try {
      // No se lee reports: CREATE único por pareja, UPDATE denegado por Rules.
      await _db.collection('reports').doc(SafetyIds.idFor(uid, target)).set({
        'reporterId': uid,
        'reportedId': target,
        'reason': reason,
        'details': details.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': ReportReasons.pending,
      });
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
      throw const SafetyException(
        'No se pudo enviar el reporte. Es posible que ya hayas reportado a este usuario o que la acción no esté autorizada.',
      );
    }
  }
}
