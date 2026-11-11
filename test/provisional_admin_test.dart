import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';
import 'package:tinder_universitario/features/verification/account_access.dart';
import 'package:tinder_universitario/features/verification/university_gate.dart';
import 'package:tinder_universitario/features/verification/administration_screen.dart';
import 'auth_service_test.dart' show LocalAuth;
import 'verification_fixtures.dart';

void main() {
  Map<String, dynamic> access(DateTime until) => {
    'role': 'superadmin',
    'verificationStatus': 'pending',
    'suspended': false,
    'provisionalAdminUntil': Timestamp.fromDate(until),
  };
  test(
    'Administración provisional separada de citas, sin acceso vencido/suspendido/rechazado',
    () {
      final data = access(DateTime.now().add(const Duration(hours: 1)));
      expect(AccountAccess.fromMap(data).canDate, false);
      expect(AccountAccess.fromMap(data).canAdminister, true);
      for (final override in [
        {'provisionalAdminUntil': Timestamp.fromMillisecondsSinceEpoch(1)},
        {'suspended': true},
        {'verificationStatus': 'rejected'},
        {'role': 'user'},
        {'provisionalAdminUntil': 'invalid'},
      ]) {
        expect(
          AccountAccess.fromMap({...data, ...override}).canAdminister,
          false,
        );
      }
    },
  );
  testWidgets(
    'Pendiente presenta carnet y abre administración sin navegar a citas',
    (tester) async {
      final db = FakeFirebaseFirestore(),
          auth = LocalAuth(),
          client = FakeVerificationClient();
      final service = AuthService(auth: auth, firestore: db);
      await db
          .doc('accountAccess/operator')
          .set(access(DateTime.now().add(const Duration(hours: 1))));
      await tester.pumpWidget(
        MaterialApp(
          home: UniversityGate(
            service: service,
            uid: 'operator',
            client: client,
            child: const Text('DATING_FORBIDDEN'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verificación universitaria'), findsOneWidget);
      await tester.tap(find.text('Administración provisional'));
      await tester.pumpAndSettle();
      expect(find.byType(AdministrationScreen), findsOneWidget);
      expect(find.text('DATING_FORBIDDEN'), findsNothing);
      await tester.tap(find.byTooltip('Menú de administración'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir aplicación'));
      await tester.pumpAndSettle();
      expect(find.text('Verificación universitaria'), findsOneWidget);
      await db.doc('accountAccess/operator').update({
        'provisionalAdminUntil': Timestamp.fromMillisecondsSinceEpoch(1),
      });
      await tester.pumpAndSettle();
      expect(find.text('Administración provisional'), findsNothing);
      expect(find.text('DATING_FORBIDDEN'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
      service.dispose();
      await auth.changes.close();
    },
  );
}
