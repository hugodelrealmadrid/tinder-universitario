import 'dart:typed_data';
import 'package:tinder_universitario/features/verification/backend_client.dart';
import 'auth_service_test.dart' show LocalAuth;

class FakeVerificationClient extends VerificationClient {
  FakeVerificationClient() : super(auth: LocalAuth());
  Map<String, dynamic>? own;
  List<Map<String, dynamic>> rows = [], events = [];
  Map<String, dynamic> target = {
    'uid': 'target',
    'role': 'user',
    'verificationStatus': 'approved',
    'suspended': false,
  };
  final List<String> calls = [];
  VerificationFailure? decisionFailure;
  Future<void>? decisionWait;
  Uint8List? documentBytes;
  @override
  Future<Map<String, dynamic>> administrationSummary() async => {
    'totalUsers': 0,
    'verified': 0,
    'pending': 0,
    'rejected': 0,
    'suspended': 0,
    'matches': 0,
    'pendingRequests': rows.where((r) => r['status'] == 'pending').length,
    'reports': 0,
  };
  @override
  Future<Map<String, dynamic>> administrationDossier(String uid) async => {
    'profile': {
      ...target,
      'name': 'Persona Ficticia',
      'email': 'persona@ligo.test',
      'interests': <String>[],
    },
    'activity': {
      'sent': 0,
      'received': 0,
      'matches': 0,
      'reportsReceived': 0,
      'reportsSent': 0,
      'messages': 0,
      'active': 0,
      'complete': true,
      'contacts': <Map<String, dynamic>>[],
    },
    'verifications': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> administrationUsers({String? cursor}) async => {
    'items': [
      {
        ...target,
        'name': 'Persona Ficticia',
        'email': 'persona@ligo.test',
        'career': 'Sistemas',
        'university': null,
        'isActive': true,
      },
    ],
    'nextCursor': null,
  };
  @override
  Future<List<Map<String, dynamic>>> identities(List<String> ids) async => ids
      .map(
        (id) => {
          'uid': id,
          'name': 'Persona Ficticia',
          'email': 'persona@ligo.test',
          'available': true,
        },
      )
      .toList();
  @override
  Future<Map<String, dynamic>> eventFeed({String? cursor}) async {
    calls.add('audit');
    return {'items': events, 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> reportFeed({
    String status = 'pending',
    String? cursor,
  }) async {
    calls.add('reports');
    return {'items': rows, 'nextCursor': null};
  }

  @override
  Future<void> provision() async {
    calls.add('provision');
  }

  @override
  Future<Map<String, dynamic>?> ownRequest() async => own;
  @override
  Future<String> begin() async {
    calls.add('begin');
    return 'new';
  }

  @override
  Future<void> upload(String id, Uint8List bytes) async {
    calls.add('upload:$id');
    own = {
      'id': id,
      'uid': 'student',
      'status': 'pending',
      'documentStage': 'ready',
      'createdAt': '2026-10-19T12:00:00Z',
    };
  }

  @override
  Future<void> withdraw(String id) async {
    calls.add('withdraw:$id');
    own = {...?own, 'status': 'rejected', 'reasonCode': 'withdrawn'};
  }

  @override
  Future<List<dynamic>> requests({
    String status = 'pending',
    String? cursor,
  }) async {
    calls.add('requests:$status');
    return rows;
  }

  @override
  Future<List<dynamic>> reports() async {
    calls.add('reports');
    return rows;
  }

  @override
  Future<List<dynamic>> audit({String? cursor}) async {
    calls.add('audit');
    return events;
  }

  @override
  Future<void> decide(String id, String status, String reasonCode) async {
    calls.add('decide:$id:$status:$reasonCode');
    await decisionWait;
    if (decisionFailure != null) throw decisionFailure!;
    rows = [];
  }

  @override
  Future<Map<String, dynamic>> account(String uid) async => target;
  @override
  Future<void> role(String uid, String role) async {
    calls.add('role:$uid:$role');
    target = {...target, 'role': role};
  }

  @override
  Future<void> suspend(String uid, bool suspended, String reasonCode) async {
    calls.add('suspend:$uid:$suspended:$reasonCode');
    target = {...target, 'suspended': suspended};
  }

  @override
  Future<void> reviewReport(String id, String resolution) async {
    calls.add('report:$id:$resolution');
    rows = [];
  }

  @override
  Future<Uint8List> document(String id) async {
    calls.add('document:$id');
    if (documentBytes != null) return documentBytes!;
    throw const VerificationFailure('permission-denied');
  }
}
