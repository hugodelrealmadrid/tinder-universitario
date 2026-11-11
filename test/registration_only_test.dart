import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/auth/auth_form.dart';
import 'package:tinder_universitario/features/auth/registration_only.dart';
import 'package:tinder_universitario/features/verification/university_gate.dart';
import 'package:tinder_universitario/features/home/home_screen.dart';
import 'auth_service_test.dart' show LocalAuth, TestUser;

void main() {
  test('Rechaza otras cuentas antes de contactar Auth o Firestore', () async {
    final auth = LocalAuth(), db = FakeFirebaseFirestore();
    final service = RegistrationOnlyService(
      auth: auth,
      firestore: db,
      allowedEmail: 'candidate@example.test',
    );
    expect(
      () => service.register('other@example.test', 'SYNTHETIC', DateTime(2000)),
      throwsStateError,
    );
    expect(
      () => service.login('other@example.test', 'SYNTHETIC'),
      throwsStateError,
    );
    expect(
      () => service.ensureProfile(TestUser(), birthDate: DateTime(2000)),
      throwsStateError,
    );
    expect(auth.registrations, 0);
    expect(auth.logins, 0);
    expect((await db.collection('users').get()).docs, isEmpty);
    await auth.changes.close();
    service.dispose();
  });
  test(
    'Registro propio solo crea perfil básico y conserva perfiles existentes',
    () async {
      final auth = LocalAuth(), db = FakeFirebaseFirestore();
      await db.doc('users/unrelated').set({'synthetic': 'unchanged'});
      final service = RegistrationOnlyService(
        auth: auth,
        firestore: db,
        allowedEmail: 'ana@example.com',
      );
      await service.register('ana@example.com', 'SYNTHETIC', DateTime(2000));
      expect(
        await service.ensureProfile(auth.current!, birthDate: DateTime(2000)),
        true,
      );
      final own = (await db.doc('users/ana').get()).data()!;
      expect(own['role'], 'user');
      expect(own['isActive'], false);
      expect((await db.collection('accountAccess').get()).docs, isEmpty);
      expect((await db.doc('users/unrelated').get()).data(), {
        'synthetic': 'unchanged',
      });
      await auth.changes.close();
      service.dispose();
    },
  );
  testWidgets('Cuenta verificada termina sin UniversityGate ni citas', (
    tester,
  ) async {
    final auth = LocalAuth()..current = TestUser(verified: true),
        db = FakeFirebaseFirestore();
    await db.doc('users/ana').set({'synthetic': true});
    final service = RegistrationOnlyService(
      auth: auth,
      firestore: db,
      allowedEmail: 'ana@example.com',
    );
    await tester.pumpWidget(
      MaterialApp(home: RegistrationOnlyGate(service: service)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Cuenta registrada y correo verificado'),
      findsOneWidget,
    );
    expect(find.byType(UniversityGate), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    service.dispose();
  });
  testWidgets('Correo autorizado aparece fijo y no editable', (tester) async {
    final auth = LocalAuth(), db = FakeFirebaseFirestore();
    final service = RegistrationOnlyService(
      auth: auth,
      firestore: db,
      allowedEmail: 'candidate@example.test',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AuthForm(
          service: service,
          register: false,
          onSwitch: () {},
          fixedEmail: service.allowedEmail,
        ),
      ),
    );
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(TextFormField).first,
        matching: find.byType(TextField),
      ),
    );
    expect(field.readOnly, true);
    expect(field.controller!.text, 'candidate@example.test');
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    service.dispose();
  });
}
