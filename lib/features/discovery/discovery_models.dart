import '../preferences/discovery_preferences.dart';
import '../profile/student_profile.dart';
import '../profile/private_photo_path.dart';

/// HTTP solo para fotografías del bucket y origen exactos del demo.
bool validCandidatePhoto(String value, {bool demoMode = false}) {
  return isPrivatePhotoPath(value);
}

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
    this.photoUrls = const [],
    this.universityId,
    this.campusId,
  });
  final String id, firstName, gender, careerId, mainPhotoUrl, description;
  final int age;
  final String? universityId, campusId;
  final List<String> interestIds;
  final List<String> photoUrls;
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
        photoUrls: List<String>.from(data['photoUrls'] as List? ?? []),
        universityId: data['universityId'] as String?,
        campusId: data['campusId'] as String?,
      );
  bool eligibleFor(
    String viewer,
    DiscoveryPreferences preferences,
    Set<String> decided, {
    bool demoMode = false,
    String? viewerUniversity,
  }) =>
      id != viewer &&
      isActive &&
      firstName.trim().isNotEmpty &&
      careerId.isNotEmpty &&
      ProfileGender.isValid(gender) &&
      validCandidatePhoto(mainPhotoUrl, demoMode: demoMode) &&
      !decided.contains(id) &&
      preferences.acceptsCareer(careerId) &&
      preferences.acceptsAffiliation(
        viewerUniversity,
        universityId,
        interestIds,
      ) &&
      preferences.acceptsAge(gender: gender, age: age);
}
