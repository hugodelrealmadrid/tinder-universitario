import 'package:cloud_firestore/cloud_firestore.dart';
import '../profile/student_profile.dart';

/// Límites compartidos por validación, formularios y cálculo de preferencias.
abstract final class DiscoveryLimits {
  static const minAge = 18;
  static const maxAge = 100;
  static const pageSize = 25;
}

abstract final class PreferredGender {
  static const both = 'ambos';
  static const labels = {...ProfileGender.labels, both: 'Ambos'};
  static bool isValid(String? value) => labels.containsKey(value);
}

/// Edad cumplida por fecha de calendario UTC, igual que las reglas Firestore.
/// La ficha pública guarda solo esta edad; las reglas comprueban su vigencia.
int ageOn(DateTime birthDate, {DateTime? today}) {
  final now = (today ?? DateTime.now()).toUtc();
  final birth = birthDate.toUtc();
  var age = now.year - birth.year;
  if (now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day)) {
    age--;
  }
  return age;
}

class DiscoveryPreferences {
  const DiscoveryPreferences({
    required this.minAge,
    required this.maxAge,
    required this.preferredGender,
    this.careerIds = const [],
  });
  final int minAge, maxAge;
  final String preferredGender;

  /// Vacío conserva el comportamiento anterior: cualquier carrera.
  final List<String> careerIds;
  bool acceptsCareer(String id) => careerIds.isEmpty || careerIds.contains(id);
  bool get isValid =>
      minAge >= DiscoveryLimits.minAge &&
      minAge <= maxAge &&
      maxAge <= DiscoveryLimits.maxAge &&
      PreferredGender.isValid(preferredGender) &&
      careerIds.length <= 5 &&
      careerIds.toSet().length == careerIds.length &&
      careerIds.every((id) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id));
  bool accepts({
    required String gender,
    required DateTime birthDate,
    DateTime? today,
  }) {
    return acceptsAge(
      gender: gender,
      age: ageOn(birthDate, today: today),
    );
  }

  bool acceptsAge({required String gender, required int age}) {
    return isValid &&
        ProfileGender.isValid(gender) &&
        age >= minAge &&
        age <= maxAge &&
        (preferredGender == PreferredGender.both || preferredGender == gender);
  }

  factory DiscoveryPreferences.fromMap(Map<String, dynamic> data) =>
      DiscoveryPreferences(
        minAge: data['minAge'] as int,
        maxAge: data['maxAge'] as int,
        preferredGender: data['preferredGender'] as String,
        careerIds: List<String>.from(data['careerIds'] as List? ?? []),
      );
  Map<String, dynamic> toFirestore() => {
    'minAge': minAge,
    'maxAge': maxAge,
    'preferredGender': preferredGender,
    'careerIds': careerIds,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class DiscoveryException implements Exception {
  const DiscoveryException(this.message, {this.alreadyDecided = false});
  final String message;
  final bool alreadyDecided;
}
