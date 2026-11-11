import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/auth/academic_selector.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';
import 'package:tinder_universitario/features/auth/auth_form.dart'
    show BirthDateField;
import 'package:tinder_universitario/features/auth/guided_registration.dart';

import 'auth_service_test.dart' show LocalAuth;

class _Directory extends AcademicDirectory {
  _Directory(super.db);
  @override
  Future<List<AcademicOption>> options(String path) async => switch (path) {
    'universities' => [(id: 'u1', name: 'Univalle'), (id: 'u2', name: 'UCB')],
    'universities/u1/campuses' => [(id: 'c1', name: 'Sede Univalle')],
    'universities/u2/campuses' => [(id: 'c2', name: 'Sede UCB')],
    'universities/u1/campuses/c1/offerings' => [
      (id: 'r1', name: 'Carrera Univalle'),
    ],
    'universities/u2/campuses/c2/offerings' => [
      (id: 'r2', name: 'Carrera UCB'),
    ],
    'interests' => [(id: 'reading', name: 'Lectura')],
    _ => [],
  };
}

class _Service extends AuthService {
  _Service(LocalAuth auth, FakeFirebaseFirestore db)
    : _directory = _Directory(db),
      super(auth: auth, firestore: db);
  final AcademicDirectory _directory;
  @override
  AcademicDirectory get academicDirectory => _directory;
}

void main() {
  testWidgets(
    'Los siete pasos conservan el borrador y solo el último crea Auth',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = LocalAuth();
      addTearDown(auth.changes.close);
      final db = FakeFirebaseFirestore();
      final service = _Service(auth, db);
      await tester.pumpWidget(
        MaterialApp(
          home: GuidedRegistration(service: service, onLogin: () {}),
        ),
      );
      Future<void> press(String label) async {
        final item = find.text(label).first;
        await tester.ensureVisible(item);
        await tester.tap(item);
        await tester.pumpAndSettle();
      }

      final values = [
        'Ana',
        'Ficticia',
        'ana@example.com',
        'Prueba-2026!',
        'Prueba-2026!',
      ];
      for (final (index, value) in values.indexed) {
        await tester.enterText(find.byType(TextFormField).at(index), value);
      }
      await press('Siguiente');
      await press('Atrás');
      expect(find.text('Ana'), findsOneWidget);
      await press('Siguiente');
      final birth = find.byType(BirthDateField);
      final date = DateTime(2000, 1, 1);
      final field = find.descendant(
        of: birth,
        matching: find.byType(FormField<DateTime>),
      );
      tester.state<FormFieldState<DateTime>>(field).didChange(date);
      tester.widget<BirthDateField>(birth).onChanged(date);
      await tester.pumpAndSettle();
      await press('Siguiente');
      await press('Univalle');
      await press('Siguiente');
      await press('Sede Univalle');
      await press('Siguiente');
      await press('Carrera Univalle');
      await press('Atrás');
      await press('Atrás');
      await press('UCB');
      await press('Siguiente');
      expect(find.text('Sede Univalle'), findsNothing);
      await press('Siguiente');
      expect(find.text('Selecciona una sede activa.'), findsOneWidget);
      await press('Sede UCB');
      await press('Siguiente');
      expect(find.text('Carrera Univalle'), findsNothing);
      await press('Carrera UCB');
      await press('Siguiente');
      await press('Lectura');
      await press('Siguiente');
      expect(find.text('Paso 7 de 7'), findsOneWidget);
      expect(auth.registrations, 0);
      await press('Crear cuenta');
      expect(auth.registrations, 1);
      expect(await service.ensureProfile(auth.currentUser!), isTrue);
      final profile = (await db.doc('users/ana').get()).data()!;
      expect(profile['firstName'], 'Ana');
      expect(profile['campusId'], 'c2');
      expect(profile['careerId'], 'r2');
      expect(profile['interestIds'], ['reading']);
      expect((await db.doc('preferences/ana').get()).exists, isTrue);
    },
  );
}
