import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

bool isAdult(DateTime birthDate, {DateTime? today}) {
  final now = today ?? DateTime.now();
  var age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age--;
  }
  return age >= 18;
}

String firebaseError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'email-already-in-use' =>
        'Este correo ya tiene una cuenta. Inicia sesión.',
      'invalid-email' => 'Escribe un correo electrónico válido.',
      'weak-password' =>
        'La contraseña no cumple la política de seguridad del proyecto.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Correo o contraseña incorrectos.',
      'user-disabled' => 'Esta cuenta está deshabilitada.',
      'too-many-requests' => 'Demasiados intentos. Espera unos minutos.',
      'network-request-failed' || 'unavailable' =>
        'No hay conexión con Firebase. Comprueba tu conexión e inténtalo de nuevo.',
      'permission-denied' =>
        'No se pudo acceder al perfil. Revisa las reglas de Firestore.',
      'unauthorized' =>
        'No se pudo acceder a las fotos. Revisa las reglas de Storage.',
      'unauthenticated' => 'Vuelve a iniciar sesión para gestionar tus fotos.',
      'bucket-not-found' ||
      'project-not-found' => 'Firebase Storage aún no está configurado.',
      'quota-exceeded' => 'Se alcanzó la cuota de Firebase Storage.',
      'retry-limit-exceeded' =>
        'La subida tardó demasiado. Comprueba la conexión y reintenta.',
      'canceled' => 'La operación se canceló.',
      'operation-not-allowed' =>
        'El acceso por correo y contraseña no está habilitado en Firebase.',
      _ =>
        'No se pudo completar la operación (${error.code}). Inténtalo de nuevo.',
    };
  }
  return 'No se pudo completar la operación. Inténtalo de nuevo.';
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  DateTime? _registrationBirthDate;
  Stream<User?> get authChanges => _auth.authStateChanges();

  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> register(
    String email,
    String password,
    DateTime birthDate,
  ) async {
    if (!isAdult(birthDate)) {
      throw ArgumentError('Debes tener al menos 18 años.');
    }
    _registrationBirthDate = birthDate;
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } catch (_) {
      _registrationBirthDate = null;
      rethrow;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    _registrationBirthDate = null;
  }

  /// Auth y Firestore no son atómicos. AuthGate espera esta escritura y
  /// permite reintentar sin crear otra cuenta ni sobrescribir perfiles.
  Future<bool> ensureProfile(User user, {DateTime? birthDate}) async {
    final date = birthDate ?? _registrationBirthDate;
    final reference = _db.collection('users').doc(user.uid);
    final ready = await _db.runTransaction<bool>((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) return true;
      if (date == null) return false;
      if (!isAdult(date)) throw ArgumentError('Debes tener al menos 18 años.');
      transaction.set(reference, {
        'firstName': '',
        'lastName': '',
        'email': user.email ?? '',
        'birthDate': Timestamp.fromDate(
          DateTime.utc(date.year, date.month, date.day),
        ),
        'gender': '',
        'description': '',
        'careerId': null,
        'photoUrls': <String>[],
        'mainPhotoUrl': null,
        'interestIds': <String>[],
        'role': 'user',
        'isActive': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (ready) _registrationBirthDate = null;
    return ready;
  }
}
