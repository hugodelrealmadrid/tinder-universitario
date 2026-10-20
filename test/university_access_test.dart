import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tinder_universitario/features/verification/account_access.dart';
import 'package:tinder_universitario/features/verification/university_gate.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';
import 'auth_service_test.dart' show LocalAuth;
import 'verification_fixtures.dart';
import 'package:tinder_universitario/features/verification/administration_screen.dart';

void main() {
  testWidgets(
    'Revocar rol administrativo cierra también la vista privada abierta',
    (tester) async {
      final db = FakeFirebaseFirestore(), auth = LocalAuth();
      final service = AuthService(auth: auth, firestore: db),
          api = FakeVerificationClient();
      await db.doc('accountAccess/admin').set({
        'role': 'admin',
        'verificationStatus': 'approved',
        'suspended': false,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: UniversityGate(
            service: service,
            uid: 'admin',
            client: api,
            child: const Scaffold(body: Text('CITAS')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Administración'), findsOneWidget);
      showDialog<void>(
        context: tester.element(find.byType(AdministrationScreen)),
        builder: (_) => PrivateDocumentView(client: api, requestId: 'r'),
      );
      await tester.pumpAndSettle();
      await db.doc('accountAccess/admin').update({'role': 'user'});
      await tester.pumpAndSettle();
      expect(find.text('CITAS'), findsOneWidget);
      expect(find.byType(PrivateDocumentView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
      service.dispose();
    },
  );
  test(
    'Acceso universitario deniega documentos ausentes, inválidos, pendientes y suspendidos',
    () {
      for (final d in <Map<String, dynamic>?>[
        null,
        {},
        {'role': 'admin'},
        {'role': 'user', 'verificationStatus': 'pending', 'suspended': false},
        {
          'role': 'superadmin',
          'verificationStatus': 'approved',
          'suspended': true,
        },
        {'role': 'owner', 'verificationStatus': 'approved', 'suspended': false},
        {'role': 'user', 'verificationStatus': 'approved'},
      ]) {
        expect(AccountAccess.fromMap(d).canDate, false);
      }
      for (final role in AccountRole.values) {
        final a = AccountAccess.fromMap({
          'role': role.name,
          'verificationStatus': 'approved',
          'suspended': false,
        });
        expect(a.canDate, true);
        expect(a.canAdminister, role != AccountRole.user);
      }
    },
  );
  test('Estado de solicitud es independiente del rol', () {
    final r = UniversityRequest.fromMap('r', {
      'uid': 'ana',
      'status': 'rejected',
      'documentStage': 'deleted',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 19)),
    });
    expect(r.status, UniversityStatus.rejected);
    expect(r.documentStage, 'deleted');
    expect(r.createdAt?.toUtc(), DateTime.utc(2026, 10, 19));
  });
  testWidgets(
    'Barrera cambia en vivo: ausencia, pendiente, aprobación y suspensión',
    (tester) async {
      final db = FakeFirebaseFirestore(), auth = LocalAuth();
      final service = AuthService(auth: auth, firestore: db);
      await tester.pumpWidget(
        MaterialApp(
          home: UniversityGate(
            client: FakeVerificationClient(),
            service: service,
            uid: 'ana',
            child: const Scaffold(body: Text('CITAS AUTORIZADAS')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CITAS AUTORIZADAS'), findsNothing);
      await db.doc('accountAccess/ana').set({
        'role': 'user',
        'verificationStatus': 'pending',
        'suspended': false,
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('está pendiente'), findsOneWidget);
      await db.doc('accountAccess/ana').update({
        'verificationStatus': 'approved',
      });
      await tester.pumpAndSettle();
      expect(find.text('CITAS AUTORIZADAS'), findsOneWidget);
      Navigator.of(tester.element(find.text('CITAS AUTORIZADAS'))).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('CHAT ABIERTO')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CHAT ABIERTO'), findsOneWidget);
      await db.doc('accountAccess/ana').update({'suspended': true});
      await tester.pumpAndSettle();
      expect(
        find.textContaining('suspendida administrativamente'),
        findsOneWidget,
      );
      expect(find.text('CITAS AUTORIZADAS'), findsNothing);
      expect(find.text('CHAT ABIERTO'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
      service.dispose();
    },
  );
}
