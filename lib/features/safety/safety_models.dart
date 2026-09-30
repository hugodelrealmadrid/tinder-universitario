import '../discovery/discovery_models.dart';

abstract final class SafetyIds {
  static String idFor(String from, String to) => SwipeDecision.idFor(from, to);
}

abstract final class ReportReasons {
  static const fakeProfile = 'fake_profile';
  static const inappropriateContent = 'inappropriate_content';
  static const harassment = 'harassment';
  static const spam = 'spam';
  static const other = 'other';
  static const pending = 'pending';
  static const maxDetailsLength = 500;
  static const labels = {
    fakeProfile: 'Perfil falso',
    inappropriateContent: 'Contenido inapropiado',
    harassment: 'Acoso',
    spam: 'Spam',
    other: 'Otro',
  };
  static bool isValid(String? value) => labels.containsKey(value);
}

class SafetyException implements Exception {
  const SafetyException(this.message);
  final String message;
}

String safetyError(Object error) => error is SafetyException
    ? error.message
    : 'No se pudo completar la acción. Revisa tu conexión e inténtalo de nuevo.';
