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
    this.universityMode = 'all',
    this.universityIds = const [],
    this.interestIds = const [],
  });
  final int minAge, maxAge;
  final String preferredGender;

  /// Vacío conserva el comportamiento anterior: cualquier carrera.
  final List<String> careerIds, universityIds, interestIds;
  final String universityMode;

  bool acceptsAffiliation(
    String? own,
    String? candidate,
    List<String> interests,
  ) =>
      (interestIds.isEmpty || interestIds.any(interests.contains)) &&
      switch (universityMode) {
        'mine' => own != null && own == candidate,
        'selected' => universityIds.contains(candidate),
        _ => true,
      };
  static bool _validIds(List<String> ids) =>
      ids.length <= 5 &&
      ids.toSet().length == ids.length &&
      ids.every((id) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id));
  bool acceptsCareer(String id) => careerIds.isEmpty || careerIds.contains(id);
  bool get isValid =>
      minAge >= DiscoveryLimits.minAge &&
      minAge <= maxAge &&
      maxAge <= DiscoveryLimits.maxAge &&
      PreferredGender.isValid(preferredGender) &&
      _validIds(careerIds) &&
      _validIds(interestIds) &&
      _validIds(universityIds) &&
      ['all', 'mine', 'selected'].contains(universityMode) &&
      (universityMode != 'selected' || universityIds.isNotEmpty) &&
      careerIds.length +
              interestIds.length +
              (universityMode == 'selected' ? universityIds.length : 0) <=
          9;
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
        universityMode: data['universityMode'] as String? ?? 'all',
        universityIds: data['universityMode'] == 'selected'
            ? List<String>.from(data['universityIds'] as List? ?? [])
            : const [],
        interestIds: List<String>.from(data['interestIds'] as List? ?? []),
      );
  Map<String, dynamic> toFirestore() => {
    'minAge': minAge,
    'maxAge': maxAge,
    'preferredGender': preferredGender,
    'careerIds': careerIds,
    if (universityMode != 'all' ||
        const bool.fromEnvironment('LIGO_MULTIUNIVERSITY'))
      'universityMode': universityMode,
    if (universityMode == 'selected') 'universityIds': universityIds,
    if (interestIds.isNotEmpty ||
        const bool.fromEnvironment('LIGO_MULTIUNIVERSITY'))
      'interestIds': interestIds,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class DiscoveryException implements Exception {
  const DiscoveryException(this.message, {this.alreadyDecided = false});
  final String message;
  final bool alreadyDecided;
}
