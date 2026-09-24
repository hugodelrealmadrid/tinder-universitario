import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/profile/photo_store.dart';
import 'package:tinder_universitario/features/profile/profile_screen.dart';
import 'package:tinder_universitario/features/profile/profile_service.dart';
import 'package:tinder_universitario/features/profile/student_profile.dart';

class MemoryPhotos implements PhotoStore {
  final Set<String> files = {};
  bool failDelete = false;
  @override
  Future<String> upload(
    String uid,
    String fileId,
    Uint8List bytes,
    String contentType,
  ) async {
    final url = 'https://example.test/$uid/$fileId';
    files.add(url);
    return url;
  }

  @override
  Future<void> delete(String uid, String url) async {
    if (failDelete) throw const ProfileException('Storage no disponible');
    files.remove(url);
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late MemoryPhotos photos;
  late ProfileService service;
  final jpeg = Uint8List.fromList([255, 216, 255, 0]);
  StudentProfile completeDraft() => StudentProfile(
    firstName: 'Ana',
    lastName: 'Pérez',
    birthDate: DateTime(2000, 1, 1),
    gender: ProfileGender.female,
    careerId: 'sistemas',
  );

  setUp(() async {
    db = FakeFirebaseFirestore();
    photos = MemoryPhotos();
    service = ProfileService(firestore: db, photos: photos);
    await db.collection('users').doc('ana').set({
      'firstName': '',
      'lastName': '',
      'email': 'ana@example.com',
      'birthDate': Timestamp.fromDate(DateTime.utc(2000)),
      'gender': '',
      'description': '',
      'careerId': null,
      'photoUrls': <String>[],
      'mainPhotoUrl': null,
      'interestIds': <String>[],
      'role': 'user',
      'isActive': false,
      'createdAt': Timestamp.fromDate(DateTime.utc(2020)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2020)),
    });
    await db.collection('careers').doc('sistemas').set({
      'name': 'Sistemas',
      'isActive': true,
    });
    await db.collection('careers').doc('old').set({
      'name': 'Inactiva',
      'isActive': false,
    });
    await db.collection('interests').doc('musica').set({
      'name': 'Música',
      'isActive': true,
    });
  });

  test('Guardado parcial inactivo sin alterar campos protegidos', () async {
    final result = await service.save(
      'ana',
      const StudentProfile(firstName: ' Ana ', gender: ProfileGender.female),
      activate: true,
    );
    expect(result.firstName, 'Ana');
    expect(result.isActive, isFalse);
    final data = (await db.collection('users').doc('ana').get()).data()!;
    expect(data['email'], 'ana@example.com');
    expect(data['role'], 'user');
    expect(data['createdAt'], Timestamp.fromDate(DateTime.utc(2020)));
    expect(data['updatedAt'], isNot(data['createdAt']));
  });
  test(
    'Activar requiere foto; subir no activa automáticamente; desactivar conserva datos',
    () async {
      expect(
        (await service.save('ana', completeDraft(), activate: true)).isActive,
        isFalse,
      );
      await service.upload('ana', jpeg);
      expect((await service.load('ana')).isActive, isFalse);
      final active = await service.save('ana', completeDraft(), activate: true);
      expect(active.isActive, isTrue);
      expect(active.mainPhotoUrl, active.photoUrls.single);
      final inactive = await service.save(
        'ana',
        completeDraft(),
        activate: false,
      );
      expect(inactive.isActive, isFalse);
      expect(inactive.photoUrls, active.photoUrls);
    },
  );
  test(
    'Cambiar principal, borrar principal y borrar última desactiva',
    () async {
      await service.upload('ana', jpeg);
      await service.upload('ana', jpeg);
      final urls = (await service.load('ana')).photoUrls;
      await service.chooseMain('ana', urls.last);
      await service.save('ana', completeDraft(), activate: true);
      await service.remove('ana', urls.last);
      final remaining = await service.load('ana');
      expect(remaining.mainPhotoUrl, urls.first);
      expect(remaining.isActive, isTrue);
      await service.remove('ana', urls.first);
      final empty = await service.load('ana');
      expect(empty.mainPhotoUrl, isNull);
      expect(empty.photoUrls, isEmpty);
      expect(empty.isActive, isFalse);
      expect(photos.files, isEmpty);
    },
  );
  test(
    'Fallo de Storage tras borrar: referencias consistentes y reintento',
    () async {
      await service.upload('ana', jpeg);
      final url = (await service.load('ana')).photoUrls.single;
      photos.failDelete = true;
      await expectLater(
        service.remove('ana', url),
        throwsA(isA<ProfileException>()),
      );
      expect((await service.load('ana')).photoUrls, isEmpty);
      expect(service.pendingDeletes, contains(url));
      photos.failDelete = false;
      await service.retryDelete('ana', url);
      expect(service.pendingDeletes, isEmpty);
      expect(photos.files, isEmpty);
    },
  );
  test('Formulario antiguo no sobrescribe fotos más recientes', () async {
    final draft = completeDraft();
    await service.upload('ana', jpeg);
    final current = await service.save('ana', draft, activate: false);
    expect(current.photoUrls, hasLength(1));
    expect(current.mainPhotoUrl, isNotNull);
  });
  test(
    'Rechaza menor, carrera inactiva, intereses inexistentes y formatos inválidos',
    () async {
      await expectLater(
        service.save(
          'ana',
          StudentProfile(
            birthDate: DateTime.now(),
            gender: ProfileGender.female,
          ),
          activate: false,
        ),
        throwsA(isA<ProfileException>()),
      );
      await expectLater(
        service.save(
          'ana',
          const StudentProfile(careerId: 'old', gender: ProfileGender.female),
          activate: false,
        ),
        throwsA(isA<ProfileException>()),
      );
      await expectLater(
        service.save(
          'ana',
          const StudentProfile(
            interestIds: ['inventado'],
            gender: ProfileGender.female,
          ),
          activate: false,
        ),
        throwsA(isA<ProfileException>()),
      );
      await expectLater(
        service.upload('ana', Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ProfileException>()),
      );
      await expectLater(
        service.upload('ana', Uint8List(maxPhotoBytes + 1)),
        throwsA(isA<ProfileException>()),
      );
      expect((await service.catalog('careers')).map((item) => item.id), [
        'sistemas',
      ]);
    },
  );
  test(
    'Intereses se guardan y se quitan sin bloquear un perfil parcial',
    () async {
      expect(
        (await service.save(
          'ana',
          const StudentProfile(
            interestIds: ['musica'],
            gender: ProfileGender.female,
          ),
          activate: false,
        )).interestIds,
        ['musica'],
      );
      expect(
        (await service.save(
          'ana',
          const StudentProfile(gender: ProfileGender.female),
          activate: false,
        )).interestIds,
        isEmpty,
      );
    },
  );
  test(
    'Cargar un perfil antiguo no cambia sus datos automáticamente',
    () async {
      await db.collection('users').doc('ana').update({'isActive': true});
      final before = (await db.collection('users').doc('ana').get()).data();
      final profile = await service.load('ana');
      expect(profile.isActive, isTrue);
      expect(profile.isComplete, isFalse);
      expect((await db.collection('users').doc('ana').get()).data(), before);
    },
  );
  testWidgets('Perfil usable a 360px con guardado parcial', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          uid: 'ana',
          service: service,
          logout: const Text('Cerrar sesión'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Perfil incompleto'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Ana');
    await tester.ensureVisible(find.byKey(const ValueKey('gender-none')));
    await tester.tap(find.byKey(const ValueKey('gender-none')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Femenino').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Guardar perfil'),
      450,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();
    expect((await service.load('ana')).firstName, 'Ana');
    expect((await service.load('ana')).isActive, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final gender in [
    ProfileGender.male,
    ProfileGender.female,
    '',
    'masculno',
    'Masculino',
    'femenino ',
  ]) {
    test('Perfil completo requiere género exacto: "$gender"', () {
      final profile = StudentProfile(
        firstName: 'Ana',
        lastName: 'Pérez',
        birthDate: DateTime(2000),
        gender: gender,
        careerId: 'sistemas',
        photoUrls: const ['foto'],
        mainPhotoUrl: 'foto',
      );
      final valid =
          gender == ProfileGender.male || gender == ProfileGender.female;
      expect(ProfileGender.isValid(gender), valid);
      expect(profile.isComplete, valid);
    });

    testWidgets(
      'Selector carga "$gender" sin campo libre ni escrituras automáticas',
      (tester) async {
        await db.collection('users').doc('ana').update({
          'gender': gender,
          'isActive': true,
        });
        final before = (await db.collection('users').doc('ana').get()).data();
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileScreen(
              uid: 'ana',
              service: service,
              logout: const Text('Cerrar sesión'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final selected = ProfileGender.isValid(gender) ? gender : null;
        final finder = find.byKey(ValueKey('gender-${selected ?? 'none'}'));
        expect(finder, findsOneWidget);
        expect(tester.state<FormFieldState<String>>(finder).value, selected);
        expect(
          find.descendant(of: finder, matching: find.byType(EditableText)),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == 'Género *',
          ),
          findsNothing,
        );
        final dropdown = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: finder,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        expect(
          dropdown.items!.map((item) => item.value),
          ProfileGender.labels.keys,
        );
        expect((await db.collection('users').doc('ana').get()).data(), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('El servicio rechaza géneros inválidos sin escribir', () async {
    final before = (await db.collection('users').doc('ana').get()).data();
    for (final gender in ['', 'masculno', 'Masculino', 'femenino ']) {
      await expectLater(
        service.save('ana', StudentProfile(gender: gender), activate: true),
        throwsA(isA<ProfileException>()),
      );
      expect((await db.collection('users').doc('ana').get()).data(), before);
    }
    for (final gender in ProfileGender.labels.keys) {
      final saved = await service.save(
        'ana',
        StudentProfile(gender: gender),
        activate: false,
      );
      expect(saved.gender, gender);
      expect(
        (await db.collection('users').doc('ana').get()).data()!['gender'],
        gender,
      );
    }
  });

  testWidgets('Seleccionar género es obligatorio al guardar', (tester) async {
    final before = (await db.collection('users').doc('ana').get()).data();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          uid: 'ana',
          service: service,
          logout: const Text('Cerrar sesión'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar perfil'));
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona Masculino o Femenino.'), findsOneWidget);
    expect((await db.collection('users').doc('ana').get()).data(), before);
  });
}
