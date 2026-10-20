import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tinder_universitario/features/matches/match_profile_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';
import 'package:tinder_universitario/features/preferences/preferences_service.dart';
import 'package:tinder_universitario/features/discovery/discovery_models.dart';
import 'package:tinder_universitario/features/discovery/discovery_publication.dart';

void main() {
  testWidgets('Perfil del match muestra galería pública sin correo ni rol', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('matches/ana.bob').set({
      'users': ['ana', 'bob'],
      'isActive': true,
    });
    await db.doc('matchProfiles/bob').set({
      'firstName': 'Bob',
      'age': 24,
      'gender': 'masculino',
      'careerId': 'sistemas',
      'description': 'Lectura',
      'mainPhotoUrl': 'https://example.test/a',
      'photoUrls': ['https://example.test/a', 'https://example.test/b'],
      'interestIds': ['musica'],
      'isActive': true,
    });
    await db.doc('users/bob').set({
      'email': 'secret@private.test',
      'role': 'superadmin',
    });
    await db.doc('careers/sistemas').set({'name': 'Sistemas'});
    await db.doc('interests/musica').set({'name': 'Música'});
    await tester.pumpWidget(
      MaterialApp(
        home: MatchProfileScreen(viewer: 'ana', target: 'bob', firestore: db),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bob, 24'), findsOneWidget);
    expect(find.text('2 fotos · Desliza para verlas'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('superadmin'), findsNothing);
    await db.doc('matches/ana.bob').update({'isActive': false});
    await tester.pumpAndSettle();
    expect(find.text('Este perfil ya no está disponible.'), findsOneWidget);
  });
  test('Preferencias anteriores no restringen carreras', () {
    final p = DiscoveryPreferences.fromMap({
      'minAge': 18,
      'maxAge': 40,
      'preferredGender': 'ambos',
    });
    expect(p.acceptsCareer('sistemas'), true);
    expect(p.acceptsCareer('medicina'), true);
  });
  test(
    'Una o varias carreras filtran y persisten, vacías incluyen todas',
    () async {
      final db = FakeFirebaseFirestore();
      for (final id in ['sistemas', 'medicina']) {
        await db.doc('careers/$id').set({'name': id, 'isActive': true});
      }
      final s = PreferencesService(firestore: db);
      const p = DiscoveryPreferences(
        minAge: 18,
        maxAge: 40,
        preferredGender: 'ambos',
        careerIds: ['sistemas', 'medicina'],
      );
      await s.save('ana', p);
      expect((await s.load('ana'))!.careerIds, p.careerIds);
      expect(p.acceptsCareer('derecho'), false);
      await expectLater(
        s.save(
          'ana',
          const DiscoveryPreferences(
            minAge: 18,
            maxAge: 40,
            preferredGender: 'ambos',
            careerIds: ['inventada'],
          ),
        ),
        throwsA(isA<DiscoveryException>()),
      );
    },
  );
  test('Límites de edad, duplicados y máximo de carreras se conservan', () {
    expect(
      const DiscoveryPreferences(
        minAge: 17,
        maxAge: 40,
        preferredGender: 'ambos',
      ).isValid,
      false,
    );
    expect(
      const DiscoveryPreferences(
        minAge: 18,
        maxAge: 40,
        preferredGender: 'ambos',
        careerIds: ['sistemas', 'sistemas'],
      ).isValid,
      false,
    );
    expect(
      const DiscoveryPreferences(
        minAge: 18,
        maxAge: 40,
        preferredGender: 'ambos',
        careerIds: ['a', 'b', 'c', 'd', 'e', 'f'],
      ).isValid,
      false,
    );
  });
  test('El modelo público solo interpreta campos públicos y galería', () {
    final p = DiscoveryCandidate.fromMap('bob', {
      'firstName': 'Bob',
      'age': 24,
      'gender': 'masculino',
      'description': 'hola',
      'careerId': 'sistemas',
      'mainPhotoUrl': 'https://example.test/1',
      'photoUrls': ['https://example.test/1', 'https://example.test/2'],
      'interestIds': [],
      'isActive': true,
      'email': 'privado',
      'role': 'admin',
    });
    expect(p.photoUrls.length, 2);
    const prefs = DiscoveryPreferences(
      minAge: 18,
      maxAge: 40,
      preferredGender: 'ambos',
      careerIds: ['medicina'],
    );
    expect(p.eligibleFor('ana', prefs, {}), false);
  });
  test('Ficha de descubrimiento sigue sin galería ni campos privados', () {
    final card = DiscoveryPublication.card({
      'firstName': 'Ana',
      'email': 'privado',
      'role': 'admin',
      'photoUrls': ['x'],
    });
    expect(card.containsKey('email'), false);
    expect(card.containsKey('role'), false);
    expect(card.containsKey('photoUrls'), false);
  });
}
