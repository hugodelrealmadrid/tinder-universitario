import 'package:cloud_firestore/cloud_firestore.dart';

enum AccountRole { user, admin, superadmin }

enum UniversityStatus { pending, approved, rejected }

/// Ausencia, tipos incorrectos y valores desconocidos siempre deniegan citas.
class AccountAccess {
  const AccountAccess({this.role, this.status, required this.suspended});
  final AccountRole? role;
  final UniversityStatus? status;
  final bool suspended;
  factory AccountAccess.fromMap(Map<String, dynamic>? data) {
    T? parse<T extends Enum>(List<T> values, Object? name) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    return AccountAccess(
      role: parse(AccountRole.values, data?['role']),
      status: parse(UniversityStatus.values, data?['verificationStatus']),
      suspended: data?['suspended'] != false,
    );
  }
  bool get canDate =>
      role != null && status == UniversityStatus.approved && !suspended;
  bool get canAdminister => canDate && role != AccountRole.user;
}

class UniversityRequest {
  const UniversityRequest(
    this.id,
    this.uid,
    this.status,
    this.documentStage, {
    this.createdAt,
    this.resolvedAt,
    this.reasonCode,
  });
  final String id, uid, documentStage;
  final UniversityStatus? status;
  final DateTime? createdAt, resolvedAt;
  final String? reasonCode;
  factory UniversityRequest.fromMap(String id, Map<String, dynamic> data) =>
      UniversityRequest(
        id,
        data['uid'] as String,
        AccountAccess.fromMap({'verificationStatus': data['status']}).status,
        data['documentStage'] as String? ?? 'unknown',
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
        reasonCode: data['reasonCode'] as String?,
      );
}
