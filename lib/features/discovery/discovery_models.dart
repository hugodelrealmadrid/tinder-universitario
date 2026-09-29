import '../preferences/discovery_preferences.dart';
import '../profile/student_profile.dart';

abstract final class SwipeDecision {
  static const like = 'like', pass = 'pass';
  static bool isValid(String value) => value == like || value == pass;
  static final _uid = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// El punto no pertenece al alfabeto permitido: no hay ambigüedad entre UID.
  static String idFor(String from, String to) {
    if (!_uid.hasMatch(from) || !_uid.hasMatch(to)) {
      throw const DiscoveryException('Identificador de cuenta no compatible.');
    }
    if (from == to) {
      throw const DiscoveryException('No puedes evaluar tu propio perfil.');
    }
    return '$from.$to';
  }
}

class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.id,
    required this.firstName,
    required this.age,
    required this.gender,
    required this.careerId,
    required this.mainPhotoUrl,
    required this.interestIds,
    required this.description,
    required this.isActive,
  });
  final String id, firstName, gender, careerId, mainPhotoUrl, description;
  final int age;
  final List<String> interestIds;
  final bool isActive;
  factory DiscoveryCandidate.fromMap(String id, Map<String, dynamic> data) =>
      DiscoveryCandidate(
        id: id,
        firstName: data['firstName'] as String,
        age: data['age'] as int,
        gender: data['gender'] as String,
        careerId: data['careerId'] as String? ?? '',
        mainPhotoUrl: data['mainPhotoUrl'] as String? ?? '',
        interestIds: List<String>.from(data['interestIds'] as List),
        description: data['description'] as String,
        isActive: data['isActive'] == true,
      );
  bool eligibleFor(
    String viewer,
    DiscoveryPreferences preferences,
    Set<String> decided,
  ) =>
      id != viewer &&
      isActive &&
      firstName.trim().isNotEmpty &&
      careerId.isNotEmpty &&
      ProfileGender.isValid(gender) &&
      Uri.tryParse(mainPhotoUrl)?.scheme == 'https' &&
      !decided.contains(id) &&
      preferences.acceptsAge(gender: gender, age: age);
}
