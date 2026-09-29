import 'package:cloud_firestore/cloud_firestore.dart';
import '../preferences/discovery_preferences.dart';
import '../preferences/preferences_service.dart';
import '../profile/student_profile.dart';
import 'discovery_models.dart';
import '../matches/student_match.dart';

class DiscoveryService {
  DiscoveryService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  final Set<String> _decided = {};
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _pending = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _exhausted = false;
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  String? _uid;
  DiscoveryPreferences? _preferences;
  final Map<String, String> careerNames = {}, interestNames = {};

  Future<void> start(String uid) async {
    _cancelled = false;
    _uid = uid;
    _cursor = null;
    _exhausted = false;
    _pending.clear();
    _decided.clear();
    final user = await _db
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!user.exists) {
      throw const DiscoveryException('Completa tu perfil antes de descubrir.');
    }
    final profile = StudentProfile.fromMap(user.data()!);
    if (!profile.isActive || !profile.isComplete) {
      throw const DiscoveryException(
        'Completa y activa tu perfil para descubrir personas.',
      );
    }
    _preferences = await PreferencesService(firestore: _db).load(uid);
    if (_preferences == null || !_preferences!.isValid) {
      throw const DiscoveryException(
        'Guarda tus preferencias antes de descubrir.',
      );
    }
    final publication = await _db
        .collection('discoveryCards')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!publication.exists ||
        publication.data()?['updatedAt'] != user.data()?['updatedAt'] ||
        publication.data()!.containsKey('birthDate') ||
        publication.data()?['age'] != ageOn(profile.birthDate!)) {
      throw const DiscoveryException(
        'Abre Perfil y pulsa Guardar perfil para actualizar tu ficha y tu edad de descubrimiento.',
      );
    }
    final swipes = await _db
        .collection('swipes')
        .where('fromUserId', isEqualTo: uid)
        .get(const GetOptions(source: Source.server));
    _decided.addAll(swipes.docs.map((doc) => doc.data()['toUserId'] as String));
    careerNames.clear();
    interestNames.clear();
    for (final collection in ['careers', 'interests']) {
      final snapshot = await _db
          .collection(collection)
          .where('isActive', isEqualTo: true)
          .get(const GetOptions(source: Source.server));
      final names = collection == 'careers' ? careerNames : interestNames;
      for (final doc in snapshot.docs) {
        names[doc.id] = doc.data()['name'] as String;
      }
    }
    if (!careerNames.containsKey(profile.careerId)) {
      throw const DiscoveryException(
        'Selecciona una carrera activa y guarda tu perfil.',
      );
    }
  }

  Future<DiscoveryCandidate?> next() async {
    if (_uid == null || _preferences == null) {
      throw const DiscoveryException('Carga tus preferencias para comenzar.');
    }
    while (!_cancelled) {
      if (_pending.isEmpty) {
        if (_exhausted) return null;
        Query<Map<String, dynamic>> query = _db
            .collection('discoveryIndex')
            .where('isActive', isEqualTo: true)
            .orderBy(FieldPath.documentId);
        if (_cursor != null) query = query.startAfterDocument(_cursor!);
        query = query.limit(DiscoveryLimits.pageSize);
        final page = await query.get(const GetOptions(source: Source.server));
        _exhausted = page.docs.length < DiscoveryLimits.pageSize;
        if (page.docs.isEmpty) return null;
        _cursor = page.docs.last;
        _pending.addAll(page.docs);
      }
      final index = _pending.removeAt(0);
      if (index.id == _uid || _decided.contains(index.id)) continue;
      try {
        // Las reglas comprueban aquí AMBAS preferencias. No se leen las
        // preferencias ajenas ni se utiliza una consulta como filtro de reglas.
        final card = await _db
            .collection('discoveryCards')
            .doc(index.id)
            .get(const GetOptions(source: Source.server));
        if (!card.exists) continue;
        final candidate = DiscoveryCandidate.fromMap(card.id, card.data()!);
        if (candidate.eligibleFor(_uid!, _preferences!, _decided) &&
            careerNames.containsKey(candidate.careerId)) {
          return candidate;
        }
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          continue; // No compatible o dejó de estar disponible.
        }
        rethrow;
      }
    }
    return null;
  }

  /// Devuelve true solamente si esta transacción creó un match nuevo.
  Future<bool> decide(String from, String to, String type) async {
    final id = SwipeDecision.idFor(from, to);
    if (!SwipeDecision.isValid(type)) {
      throw const DiscoveryException('Decisión inválida.');
    }
    Future<bool> commit() => _db.runTransaction<bool>((tx) async {
      final ref = _db.collection('swipes').doc(id);
      if ((await tx.get(ref)).exists) {
        throw const DiscoveryException(
          'Ya evaluaste este perfil.',
          alreadyDecided: true,
        );
      }
      final card = await tx.get(_db.collection('discoveryCards').doc(to));
      if (!card.exists || card.data()?['isActive'] != true) {
        throw const DiscoveryException('El perfil ya no está disponible.');
      }
      // Todas las lecturas preceden a las escrituras. Leer incluso el inverso
      // inexistente permite que Firestore reintente dos LIKE simultáneos.
      final matchRef = _db
          .collection('matches')
          .doc(StudentMatch.idFor(from, to));
      bool createMatch = false;
      if (type == SwipeDecision.like) {
        final inverse = await tx.get(
          _db.collection('swipes').doc(SwipeDecision.idFor(to, from)),
        );
        final existing = await tx.get(matchRef);
        createMatch =
            inverse.data()?['type'] == SwipeDecision.like && !existing.exists;
      }
      tx.set(ref, {
        'fromUserId': from,
        'toUserId': to,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (createMatch) {
        tx.set(matchRef, {
          'users': StudentMatch.orderedUsers(from, to),
          'createdAt': FieldValue.serverTimestamp(),
          'isActive': true,
        });
      }
      return createMatch;
    });
    bool createdMatch;
    try {
      createdMatch = await commit();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied' || type != SwipeDecision.like) {
        rethrow;
      }
      // Si el LIKE inverso apareció tras nuestra lectura, las reglas pueden
      // exigir el match antes de que el SDK detecte el conflicto de versión.
      // Releer UNA vez desde una nueva transacción resuelve esa carrera;
      // cualquier denegación persistente se devuelve a la UI sin bucles.
      createdMatch = await commit();
    }
    _decided.add(to);
    return createdMatch;
  }
}
