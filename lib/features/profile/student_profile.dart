import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/auth_service.dart' show isAdult;

const maxPhotos = 6;
const maxInterests = 5;
const maxPhotoBytes = 5 * 1024 * 1024;
const maxDescriptionLength = 500;

/// Valores persistidos compartidos por el modelo, servicio y formulario.
abstract final class ProfileGender {
  static const male = 'masculino';
  static const female = 'femenino';
  static const labels = {male: 'Masculino', female: 'Femenino'};

  static bool isValid(String? value) => labels.containsKey(value);
}

class CatalogItem {
  const CatalogItem(this.id, this.name);
  final String id;
  final String name;
}

class StudentProfile {
  const StudentProfile({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.birthDate,
    this.gender = '',
    this.description = '',
    this.careerId,
    this.photoUrls = const [],
    this.mainPhotoUrl,
    this.interestIds = const [],
    this.isActive = false,
  });
  final String firstName, lastName, email, gender, description;
  final DateTime? birthDate;
  final String? careerId, mainPhotoUrl;
  final List<String> photoUrls, interestIds;
  final bool isActive;

  factory StudentProfile.fromMap(Map<String, dynamic> data) => StudentProfile(
    firstName: data['firstName'] as String? ?? '',
    lastName: data['lastName'] as String? ?? '',
    email: data['email'] as String? ?? '',
    birthDate: (data['birthDate'] as Timestamp?)?.toDate().toUtc(),
    gender: data['gender'] as String? ?? '',
    description: data['description'] as String? ?? '',
    careerId: data['careerId'] as String?,
    photoUrls: List<String>.from(data['photoUrls'] as List? ?? []),
    mainPhotoUrl: data['mainPhotoUrl'] as String?,
    interestIds: List<String>.from(data['interestIds'] as List? ?? []),
    isActive: data['isActive'] == true,
  );

  List<String> missingFields({DateTime? today}) => [
    if (firstName.trim().isEmpty) 'Nombre',
    if (lastName.trim().isEmpty) 'Apellido',
    if (birthDate == null || !isAdult(birthDate!, today: today))
      'Fecha de nacimiento (18 años o más)',
    if (!ProfileGender.isValid(gender)) 'Género',
    if (careerId == null || careerId!.isEmpty) 'Una carrera activa',
    if (photoUrls.isEmpty) 'Al menos una fotografía',
    if (mainPhotoUrl == null || !photoUrls.contains(mainPhotoUrl))
      'Foto principal',
  ];
  bool get isComplete => missingFields().isEmpty;

  StudentProfile withPhotos(List<String> urls, String? main) => StudentProfile(
    firstName: firstName,
    lastName: lastName,
    email: email,
    birthDate: birthDate,
    gender: gender,
    description: description,
    careerId: careerId,
    photoUrls: urls,
    mainPhotoUrl: main,
    interestIds: interestIds,
    isActive: isActive,
  );

  Map<String, dynamic> editableFields() => {
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    'birthDate': birthDate == null
        ? null
        : Timestamp.fromDate(
            DateTime.utc(birthDate!.year, birthDate!.month, birthDate!.day),
          ),
    'gender': gender,
    'description': description.trim(),
    'careerId': careerId,
    'interestIds': interestIds,
  };
}

class ProfileException implements Exception {
  const ProfileException(this.message);
  final String message;
}

/// También se comprueba en Storage Rules. No confiamos en la extensión.
String imageContentType(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return 'image/webp';
  }
  throw const ProfileException('Selecciona una imagen JPG, PNG o WebP.');
}
