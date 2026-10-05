import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

/// Mensajes de verificación sin códigos internos ni detalles del SDK.
String emailVerificationError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'network-request-failed' =>
        'No hay conexión. Revisa tu conexión e inténtalo de nuevo.',
      'too-many-requests' =>
        'Se han realizado demasiados intentos. Espera unos minutos antes de volver a intentarlo.',
      'user-disabled' => 'Esta cuenta está deshabilitada. Cierra sesión.',
      'no-current-user' ||
      'user-not-found' ||
      'user-token-expired' ||
      'invalid-user-token' =>
        'Tu sesión ya no está disponible. Vuelve a iniciar sesión.',
      _ => 'No se pudo completar la verificación. Inténtalo de nuevo.',
    };
  }
  return 'No se pudo completar la verificación. Inténtalo de nuevo.';
}

class AuthService extends ChangeNotifier {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    DateTime Function()? now,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance,
       _now = now ?? DateTime.now;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final DateTime Function() _now;
  DateTime? _registrationBirthDate;
  // Incluye los cambios producidos por reload(), además de login/logout.
  Stream<User?> get authChanges => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  static const verificationCooldown = Duration(seconds: 30);
  String? _verificationUid, _verificationError;
  DateTime? _resendAt;
  bool _sendingVerification = false, _verificationSent = false;
  int _verificationGeneration = 0;
  bool get _sameVerificationUser =>
      currentUser != null && currentUser!.uid == _verificationUid;
  bool get sendingVerification => _sameVerificationUser && _sendingVerification;
  bool get verificationSent => _sameVerificationUser && _verificationSent;
  String? get verificationSendError =>
      _sameVerificationUser ? _verificationError : null;
  int get resendSeconds {
    if (!_sameVerificationUser || _resendAt == null) return 0;
    final remaining = _resendAt!.difference(_now()).inMilliseconds;
    return remaining <= 0 ? 0 : (remaining / 1000).ceil();
  }

  void _resetVerification([String? uid]) {
    _verificationGeneration++;
    _verificationUid = uid;
    _verificationError = null;
    _resendAt = null;
    _sendingVerification = false;
    _verificationSent = false;
  }

  /// Protege también el envío automático frente a un reenvío simultáneo.
  /// El estado es solo de presentación, en memoria y asociado a esta sesión.
  Future<bool> sendVerificationEmail() async {
    final user = currentUser;
    if (user == null) throw FirebaseAuthException(code: 'no-current-user');
    if (user.emailVerified) return false;
    if (_verificationUid != user.uid) _resetVerification(user.uid);
    if (sendingVerification || resendSeconds > 0) return false;
    final generation = _verificationGeneration;
    bool stillCurrent() =>
        generation == _verificationGeneration && currentUser?.uid == user.uid;
    _sendingVerification = true;
    _verificationError = null;
    notifyListeners();
    try {
      await user.sendEmailVerification();
      if (!stillCurrent()) return false;
      _verificationSent = true;
      _resendAt = _now().add(verificationCooldown);
      return true;
    } catch (error) {
      if (stillCurrent()) {
        _verificationError = emailVerificationError(error);
        if (error is FirebaseAuthException &&
            error.code == 'too-many-requests') {
          _resendAt = _now().add(verificationCooldown);
        }
      }
      rethrow;
    } finally {
      // Aunque Firebase haya invalidado la sesión durante la petición,
      // esta petición ya terminó. No dejar el envío bloqueado al volver a entrar.
      if (generation == _verificationGeneration) {
        _sendingVerification = false;
        notifyListeners();
      }
    }
  }

  Future<bool> reloadEmailVerification() async {
    final user = currentUser;
    if (user == null) throw FirebaseAuthException(code: 'no-current-user');
    await user.reload();
    // Nunca usar el objeto anterior al reload como fuente de verificación.
    final refreshed = currentUser;
    if (refreshed == null || refreshed.uid != user.uid) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    return refreshed.emailVerified;
  }

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
    // Auth ya creó la cuenta: un fallo de correo no es un fallo de registro.
    // La pantalla autenticada muestra el error y permite reenviar sin duplicar.
    try {
      await sendVerificationEmail();
    } catch (_) {
      // sendVerificationEmail conserva el error visible para la misma sesión.
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    _registrationBirthDate = null;
    _resetVerification();
    notifyListeners();
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
