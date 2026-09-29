import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/discovery/discovery_models.dart';
import 'package:tinder_universitario/features/discovery/discovery_publication.dart';
import 'package:tinder_universitario/features/discovery/discovery_service.dart';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';
import 'package:tinder_universitario/features/profile/profile_service.dart';
import 'package:tinder_universitario/features/profile/student_profile.dart';
import 'profile_test.dart' show MemoryPhotos;

void main() {
  Map<String, dynamic> privateUser() => {
    'firstName': 'Ana',
    'lastName': 'Privado',
    'email': 'privado@example.com',
    'birthDate': Timestamp.fromDate(DateTime.utc(2004, 9, 28)),
    'gender': 'femenino',
    'description': 'Lectura',
    'careerId': 'sistemas',
    'photoUrls': ['https://example.test/photo'],
    'mainPhotoUrl': 'https://example.test/photo',
    'interestIds': <String>[],
    'role': 'user',
    'isActive': true,
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
    'minAge': 18,
    'maxAge': 100,
    'preferredGender': 'ambos',
  };
  test(
    'La proyección pública usa una lista exacta de campos y no copia datos privados',
    () {
      final card = DiscoveryPublication.card(
        privateUser(),
        today: DateTime.utc(2026, 9, 28),
      );
      expect(
        card.keys,
        unorderedEquals([
          'firstName',
          'age',
          'gender',
          'description',
          'careerId',
          'mainPhotoUrl',
          'interestIds',
          'isActive',
          'updatedAt',
        ]),
      );
      expect(card['age'], 22);
      for (final field in [
        'birthDate',
        'email',
        'lastName',
        'role',
        'minAge',
        'maxAge',
        'preferredGender',
        'photoUrls',
        'createdAt',
      ]) {
        expect(card.containsKey(field), isFalse);
      }
    },
  );
  test(
    'Edad derivada cambia exactamente el cumpleaños UTC, incluido 29 de febrero',
    () {
      final user = privateUser();
      expect(
        DiscoveryPublication.card(
          user,
          today: DateTime.utc(2026, 9, 27),
        )['age'],
        21,
      );
      expect(
        DiscoveryPublication.card(
          user,
          today: DateTime.utc(2026, 9, 28),
        )['age'],
        22,
      );
      user['birthDate'] = Timestamp.fromDate(DateTime.utc(2008, 2, 29));
      expect(
        DiscoveryPublication.card(
          user,
          today: DateTime.utc(2026, 2, 28),
        )['age'],
        17,
      );
      expect(
        DiscoveryPublication.card(user, today: DateTime.utc(2026, 3, 1))['age'],
        18,
      );
    },
  );
  test('El candidato y el rango de edad funcionan sin recibir birthDate', () {
    final card = DiscoveryPublication.card(
      privateUser(),
      today: DateTime.utc(2026, 9, 28),
    );
    final candidate = DiscoveryCandidate.fromMap('ana', card);
    expect(candidate.age, 22);
    expect(
      candidate.eligibleFor(
        'bob',
        const DiscoveryPreferences(
          minAge: 22,
          maxAge: 22,
          preferredGender: 'femenino',
        ),
        {},
      ),
      isTrue,
    );
    expect(
      candidate.eligibleFor(
        'bob',
        const DiscoveryPreferences(
          minAge: 23,
          maxAge: 30,
          preferredGender: 'ambos',
        ),
        {},
      ),
      isFalse,
    );
    expect(
      candidate.eligibleFor(
        'bob',
        const DiscoveryPreferences(
          minAge: 18,
          maxAge: 30,
          preferredGender: 'masculino',
        ),
        {},
      ),
      isFalse,
    );
  });
  test('Perfil parcial sin nacimiento no inventa edad ni fecha pública', () {
    final card = DiscoveryPublication.card({
      ...privateUser(),
      'birthDate': null,
      'isActive': false,
    });
    expect(card['age'], isNull);
    expect(card.containsKey('birthDate'), isFalse);
  });
  test(
    'Guardar perfil reemplaza ficha legada completa y conserva nacimiento privado',
    () async {
      final db = FakeFirebaseFirestore();
      final data = privateUser()
        ..remove('minAge')
        ..remove('maxAge')
        ..remove('preferredGender');
      await db.collection('users').doc('ana').set(data);
      await db.collection('careers').doc('sistemas').set({
        'name': 'Sistemas',
        'isActive': true,
      });
      await db.collection('discoveryCards').doc('ana').set({
        'birthDate': data['birthDate'],
        'email': data['email'],
      });
      final service = ProfileService(firestore: db, photos: MemoryPhotos());
      await service.save('ana', StudentProfile.fromMap(data), activate: true);
      final card = (await db.collection('discoveryCards').doc('ana').get())
          .data()!;
      expect(card.containsKey('birthDate'), isFalse);
      expect(card.containsKey('email'), isFalse);
      expect(card['age'], ageOn((data['birthDate'] as Timestamp).toDate()));
      expect((await service.load('ana')).birthDate, DateTime.utc(2004, 9, 28));
    },
  );
  test(
    'Ficha propia legada o con edad vencida exige guardar, sin migración automática',
    () async {
      final db = FakeFirebaseFirestore();
      final data = privateUser();
      await db.collection('users').doc('ana').set(data);
      await db
          .collection('preferences')
          .doc('ana')
          .set(
            const DiscoveryPreferences(
              minAge: 18,
              maxAge: 100,
              preferredGender: 'ambos',
            ).toFirestore(),
          );
      for (final card in [
        {...DiscoveryPublication.card(data), 'birthDate': data['birthDate']},
        {...DiscoveryPublication.card(data), 'age': 18},
      ]) {
        await db.collection('discoveryCards').doc('ana').set(card);
        await expectLater(
          DiscoveryService(firestore: db).start('ana'),
          throwsA(
            isA<DiscoveryException>().having(
              (e) => e.message,
              'mensaje',
              contains('Guardar perfil'),
            ),
          ),
        );
        expect(
          (await db.collection('discoveryCards').doc('ana').get()).data(),
          card,
        );
      }
    },
  );
}
