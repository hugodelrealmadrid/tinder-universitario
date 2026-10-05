import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/discovery/discovery_models.dart';
import 'package:tinder_universitario/features/discovery/discovery_publication.dart';
import 'package:tinder_universitario/features/discovery/discovery_screen.dart';
import 'package:tinder_universitario/features/discovery/discovery_service.dart';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';
import 'package:tinder_universitario/features/preferences/preferences_service.dart';
import 'package:tinder_universitario/features/preferences/preferences_screen.dart';
import 'package:tinder_universitario/features/profile/student_profile.dart';

void main() {
  const both = DiscoveryPreferences(
    minAge: 18,
    maxAge: 100,
    preferredGender: PreferredGender.both,
  );
  final now = DateTime.now().toUtc();
  final birth = DateTime.utc(now.year - 22, now.month, now.day);
  late FakeFirebaseFirestore db;
  Map<String, dynamic> user(String uid) => {
    'firstName': 'Estudiante',
    'lastName': 'Prueba',
    'email': '$uid@example.com',
    'birthDate': Timestamp.fromDate(birth),
    'gender': ProfileGender.female,
    'description': 'Lectura y música',
    'careerId': 'sistemas',
    'photoUrls': ['https://example.test/photo.jpg'],
    'mainPhotoUrl': 'https://example.test/photo.jpg',
    'interestIds': ['musica'],
    'role': 'user',
    'isActive': true,
    'createdAt': Timestamp.fromDate(now),
    'updatedAt': Timestamp.fromDate(now),
  };
  Future<void> publish(String uid) async {
    final data = user(uid);
    await db.collection('users').doc(uid).set(data);
    await db
        .collection('discoveryCards')
        .doc(uid)
        .set(DiscoveryPublication.card(data));
    await db.collection('discoveryIndex').doc(uid).set({
      'isActive': true,
      'updatedAt': data['updatedAt'],
    });
    await PreferencesService(firestore: db).save(uid, both);
  }

  DiscoveryCandidate candidate({
    String id = 'bob',
    bool active = true,
    String photo = 'https://example.test/photo.jpg',
  }) => DiscoveryCandidate(
    id: id,
    firstName: 'Bob',
    age: ageOn(birth),
    gender: ProfileGender.female,
    careerId: 'sistemas',
    mainPhotoUrl: photo,
    interestIds: ['musica'],
    description: 'Lectura',
    isActive: active,
  );
  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('careers').doc('sistemas').set({
      'name': 'Ingeniería de Sistemas Informáticos',
      'isActive': true,
    });
    await db.collection('interests').doc('musica').set({
      'name': 'Música',
      'isActive': true,
    });
  });
  test(
    'Preferencias: mínimo, orden, máximo y género inválido rechazados sin escritura',
    () async {
      final service = PreferencesService(firestore: db);
      for (final value in [
        const DiscoveryPreferences(
          minAge: 17,
          maxAge: 30,
          preferredGender: PreferredGender.both,
        ),
        const DiscoveryPreferences(
          minAge: 30,
          maxAge: 20,
          preferredGender: PreferredGender.both,
        ),
        const DiscoveryPreferences(
          minAge: 18,
          maxAge: 101,
          preferredGender: PreferredGender.both,
        ),
        const DiscoveryPreferences(
          minAge: 18,
          maxAge: 30,
          preferredGender: 'otro',
        ),
      ]) {
        expect(value.isValid, isFalse);
        await expectLater(
          service.save('ana', value),
          throwsA(isA<DiscoveryException>()),
        );
      }
      expect((await db.collection('preferences').get()).docs, isEmpty);
    },
  );
  test('Masculino, femenino y ambos se guardan y cargan exactamente', () async {
    final service = PreferencesService(firestore: db);
    for (final gender in PreferredGender.labels.keys) {
      final value = DiscoveryPreferences(
        minAge: 18,
        maxAge: 40,
        preferredGender: gender,
      );
      await service.save('ana', value);
      expect((await service.load('ana'))!.preferredGender, gender);
      expect(
        (await db.collection('preferences').doc('ana').get())
            .data()!['updatedAt'],
        isA<Timestamp>(),
      );
    }
  });
  test('Edad calculada en UTC, cumpleaños y 29 de febrero', () {
    expect(
      ageOn(DateTime.utc(2004, 9, 24), today: DateTime.utc(2026, 9, 23)),
      21,
    );
    expect(
      ageOn(DateTime.utc(2004, 9, 24), today: DateTime.utc(2026, 9, 24)),
      22,
    );
    expect(
      ageOn(DateTime.utc(2008, 2, 29), today: DateTime.utc(2026, 2, 28)),
      17,
    );
    expect(
      ageOn(DateTime.utc(2008, 2, 29), today: DateTime.utc(2026, 3, 1)),
      18,
    );
  });
  test('Compatibilidad de género y rango inclusivo', () {
    const pref = DiscoveryPreferences(
      minAge: 20,
      maxAge: 25,
      preferredGender: ProfileGender.female,
    );
    final today = DateTime.utc(2026, 9, 23);
    expect(
      pref.accepts(
        gender: ProfileGender.female,
        birthDate: DateTime.utc(2006, 9, 23),
        today: today,
      ),
      isTrue,
    );
    expect(
      pref.accepts(
        gender: ProfileGender.female,
        birthDate: DateTime.utc(2001, 9, 23),
        today: today,
      ),
      isTrue,
    );
    expect(
      pref.accepts(
        gender: ProfileGender.male,
        birthDate: DateTime.utc(2004),
        today: today,
      ),
      isFalse,
    );
    expect(
      pref.accepts(
        gender: ProfileGender.female,
        birthDate: DateTime.utc(2007),
        today: today,
      ),
      isFalse,
    );
    expect(
      pref.accepts(
        gender: ProfileGender.female,
        birthDate: DateTime.utc(1999),
        today: today,
      ),
      isFalse,
    );
    for (final gender in ProfileGender.labels.keys) {
      expect(both.accepts(gender: gender, birthDate: birth), isTrue);
    }
  });
  test(
    'Filtros locales: propio, inactivo, evaluado y sin foto no aparecen',
    () {
      expect(candidate(id: 'ana').eligibleFor('ana', both, {}), isFalse);
      expect(candidate(active: false).eligibleFor('ana', both, {}), isFalse);
      expect(candidate().eligibleFor('ana', both, {'bob'}), isFalse);
      expect(candidate(photo: '').eligibleFor('ana', both, {}), isFalse);
      expect(candidate().eligibleFor('ana', both, {}), isTrue);
    },
  );
  test('ID direccional sin colisiones ni rutas; rechazo de auto-swipe', () {
    expect(SwipeDecision.idFor('ana', 'bob'), 'ana.bob');
    expect(SwipeDecision.idFor('bob', 'ana'), isNot('ana.bob'));
    expect(
      SwipeDecision.idFor('a_b', 'c'),
      isNot(SwipeDecision.idFor('a', 'b_c')),
    );
    for (final uid in ['a/b', 'a.b', '', 'a b']) {
      expect(
        () => SwipeDecision.idFor(uid, 'bob'),
        throwsA(isA<DiscoveryException>()),
      );
    }
    expect(
      () => SwipeDecision.idFor('ana', 'ana'),
      throwsA(isA<DiscoveryException>()),
    );
  });
  test(
    'LIKE/PASS: auto-swipe, tipo inválido y segunda decisión rechazados',
    () async {
      await publish('ana');
      await publish('bob');
      final service = DiscoveryService(firestore: db);
      await expectLater(
        service.decide('ana', 'ana', SwipeDecision.like),
        throwsA(isA<DiscoveryException>()),
      );
      await expectLater(
        service.decide('ana', 'bob', 'match'),
        throwsA(isA<DiscoveryException>()),
      );
      await service.decide('ana', 'bob', SwipeDecision.like);
      await expectLater(
        service.decide('ana', 'bob', SwipeDecision.pass),
        throwsA(isA<DiscoveryException>()),
      );
      final data = (await db.collection('swipes').doc('ana.bob').get()).data()!;
      expect(data['type'], SwipeDecision.like);
      expect(data['createdAt'], isA<Timestamp>());
      expect((await db.collection('swipes').get()).docs, hasLength(1));
    },
  );
  test(
    'Descubrimiento excluye decisiones persistidas y resuelve catálogos',
    () async {
      await publish('ana');
      await publish('bob');
      await publish('carol');
      final service = DiscoveryService(firestore: db);
      await service.decide('ana', 'bob', SwipeDecision.pass);
      await service.start('ana');
      expect((await service.next())!.id, 'carol');
      expect(await service.next(), isNull);
      expect(
        service.careerNames['sistemas'],
        'Ingeniería de Sistemas Informáticos',
      );
      expect(service.interestNames['musica'], 'Música');
      final restarted = DiscoveryService(firestore: db);
      await restarted.start('ana');
      expect((await restarted.next())!.id, 'carol');
    },
  );
  test(
    'Paginación no confunde una primera página descartada con lista vacía',
    () async {
      await publish('ana');
      for (var i = 0; i < 30; i++) {
        final id = 'a${i.toString().padLeft(2, '0')}';
        await publish(id);
        await db.collection('swipes').doc(SwipeDecision.idFor('ana', id)).set({
          'fromUserId': 'ana',
          'toUserId': id,
          'type': SwipeDecision.pass,
          'createdAt': Timestamp.now(),
        });
      }
      await publish('zCompatible');
      final service = DiscoveryService(firestore: db);
      await service.start('ana');
      expect((await service.next())!.id, 'zCompatible');
    },
  );
  test('Ficha publicada contiene solo edad derivada y ningún dato privado', () {
    final card = DiscoveryPublication.card(user('ana'));
    for (final field in [
      'email',
      'role',
      'preferredGender',
      'birthDate',
      'createdAt',
    ]) {
      expect(card.containsKey(field), isFalse);
    }
    expect(card['age'], 22);
  });
  testWidgets('Preferencias usa selectores sin escritura manual', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PreferencesScreen(
          uid: 'ana',
          onBack: () {},
          service: PreferencesService(firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
    await tester.ensureVisible(find.text('Guardar preferencias'));
    await tester.tap(find.text('Guardar preferencias'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona una opción.'), findsOneWidget);
    expect((await db.collection('preferences').get()).docs, isEmpty);
  });
  testWidgets(
    'Tarjeta a 360px muestra nombres y edad sin UID ni fecha exacta',
    (tester) async {
      tester.view.physicalSize = const Size(360, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CandidateView(
                candidate: candidate(id: 'uidPrivado'),
                careerName: 'Ingeniería de Sistemas Informáticos',
                interests: const ['Música'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bob, 22'), findsOneWidget);
      expect(find.text('Ingeniería de Sistemas Informáticos'), findsOneWidget);
      expect(find.text('Música'), findsOneWidget);
      expect(find.text('uidPrivado'), findsNothing);
      expect(find.text(birth.toIso8601String()), findsNothing);
      expect(find.text('sistemas'), findsNothing);
      expect(find.text('musica'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
