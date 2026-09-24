import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/discovery/discovery_models.dart';
import 'package:tinder_universitario/features/discovery/discovery_service.dart';
import 'package:tinder_universitario/features/discovery/discovery_screen.dart';
import 'package:tinder_universitario/features/matches/student_match.dart';
import 'package:tinder_universitario/features/matches/matches_service.dart';
import 'package:tinder_universitario/features/matches/matches_screen.dart';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';

void main() {
  late FakeFirebaseFirestore db;
  late DiscoveryService discovery;
  final now = DateTime.now().toUtc();
  setUp(() async {
    db = FakeFirebaseFirestore();
    discovery = DiscoveryService(firestore: db);
    await db.collection('careers').doc('sistemas').set({
      'name': 'Ingeniería de Sistemas Informáticos',
      'isActive': true,
    });
    for (final uid in ['ana', 'bob', 'carol', 'dave']) {
      await db.collection('discoveryCards').doc(uid).set({
        'firstName': uid == 'bob' ? 'Roberto' : 'Estudiante',
        'birthDate': Timestamp.fromDate(
          DateTime.utc(now.year - 22, now.month, now.day),
        ),
        'gender': 'masculino',
        'description': '',
        'careerId': 'sistemas',
        'mainPhotoUrl': 'https://example.test/photo.jpg',
        'interestIds': <String>[],
        'isActive': true,
        'updatedAt': Timestamp.now(),
      });
    }
  });

  test(
    'ID del match ordenado, simétrico, sin colisiones; dos UID distintos obligatorios',
    () {
      expect(StudentMatch.idFor('ana', 'bob'), 'ana.bob');
      expect(StudentMatch.idFor('bob', 'ana'), 'ana.bob');
      expect(StudentMatch.orderedUsers('bob', 'ana'), ['ana', 'bob']);
      expect(StudentMatch.idFor('A', 'a'), StudentMatch.idFor('a', 'A'));
      expect(
        StudentMatch.idFor('a_b', 'c'),
        isNot(StudentMatch.idFor('a', 'b_c')),
      );
      for (final uid in ['ana', '', 'a.b', 'a/b', 'a b']) {
        expect(
          () => StudentMatch.idFor('ana', uid),
          throwsA(isA<DiscoveryException>()),
        );
      }
    },
  );
  test('LIKE unilateral persiste swipe pero no crea match', () async {
    expect(await discovery.decide('ana', 'bob', SwipeDecision.like), isFalse);
    expect((await db.collection('swipes').get()).docs, hasLength(1));
    expect((await db.collection('matches').get()).docs, isEmpty);
  });
  test(
    'LIKE recíproco crea exactamente un match activo con timestamp y campos mínimos',
    () async {
      await discovery.decide('ana', 'bob', SwipeDecision.like);
      expect(await discovery.decide('bob', 'ana', SwipeDecision.like), isTrue);
      final matches = (await db.collection('matches').get()).docs;
      expect(matches, hasLength(1));
      expect(matches.single.id, 'ana.bob');
      expect(
        matches.single.data().keys,
        unorderedEquals(['users', 'createdAt', 'isActive']),
      );
      expect(matches.single.data()['users'], ['ana', 'bob']);
      expect(matches.single.data()['isActive'], isTrue);
      expect(matches.single.data()['createdAt'], isA<Timestamp>());
      await expectLater(
        discovery.decide('ana', 'bob', SwipeDecision.like),
        throwsA(isA<DiscoveryException>()),
      );
      expect((await db.collection('matches').get()).docs, hasLength(1));
    },
  );
  for (final first in [SwipeDecision.like, SwipeDecision.pass]) {
    test('LIKE + PASS sin match: primer voto $first', () async {
      await discovery.decide('ana', 'bob', first);
      final second = first == SwipeDecision.like
          ? SwipeDecision.pass
          : SwipeDecision.like;
      expect(await discovery.decide('bob', 'ana', second), isFalse);
      expect((await db.collection('matches').get()).docs, isEmpty);
    });
  }
  test(
    'Lista filtra participantes y ordena por fecha descendente sin índice compuesto',
    () async {
      for (final entry in [
        (['ana', 'bob'], 10),
        (['ana', 'carol'], 20),
        (['carol', 'dave'], 30),
      ]) {
        await db
            .collection('matches')
            .doc(StudentMatch.idFor(entry.$1[0], entry.$1[1]))
            .set({
              'users': entry.$1,
              'createdAt': Timestamp.fromMillisecondsSinceEpoch(entry.$2),
              'isActive': true,
            });
      }
      final rows = await MatchesService(firestore: db).load('ana');
      expect(rows, hasLength(2));
      expect(rows.map((row) => row.match.otherUser('ana')), ['carol', 'bob']);
      expect(rows.last.profile!.firstName, 'Roberto');
      expect(rows.last.careerName, 'Ingeniería de Sistemas Informáticos');
    },
  );
  test(
    'Ficha ausente/inactiva conserva match con perfil no disponible',
    () async {
      await discovery.decide('ana', 'bob', SwipeDecision.like);
      await discovery.decide('bob', 'ana', SwipeDecision.like);
      await db.collection('discoveryCards').doc('bob').update({
        'isActive': false,
      });
      expect(
        (await MatchesService(firestore: db).load('ana')).single.profile,
        isNull,
      );
      await db.collection('discoveryCards').doc('bob').delete();
      expect(
        (await MatchesService(firestore: db).load('ana')).single.profile,
        isNull,
      );
      expect((await db.collection('matches').get()).docs, hasLength(1));
    },
  );
  testWidgets('Mis Matches muestra estado vacío', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatchesScreen(
          uid: 'ana',
          service: MatchesService(firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Todavía no tienes matches.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Mis Matches a 360px muestra nombre edad carrera sin datos privados',
    (tester) async {
      await discovery.decide('ana', 'bob', SwipeDecision.like);
      await discovery.decide('bob', 'ana', SwipeDecision.like);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MatchesScreen(
            uid: 'ana',
            service: MatchesService(firestore: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Roberto, 22'), findsOneWidget);
      expect(find.text('Ingeniería de Sistemas Informáticos'), findsOneWidget);
      for (final text in [
        'ana',
        'bob',
        'ana.bob',
        'sistemas',
        'masculino',
        'birthDate',
      ]) {
        expect(find.text(text), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('LIKE con match muestra aviso y permite continuar', (
    tester,
  ) async {
    final service = _FeedbackDiscovery(db);
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          uid: 'ana',
          onPreferences: () {},
          onProfile: () {},
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('like-button')));
    await tester.tap(find.byKey(const ValueKey('like-button')));
    await tester.pumpAndSettle();
    expect(find.text('¡Es un match!'), findsOneWidget);
    expect(
      find.text('No hay más perfiles compatibles por ahora.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _FeedbackDiscovery extends DiscoveryService {
  _FeedbackDiscovery(FirebaseFirestore db) : super(firestore: db);
  bool consumed = false;
  @override
  Future<void> start(String uid) async {
    careerNames['sistemas'] = 'Sistemas';
  }

  @override
  Future<DiscoveryCandidate?> next() async {
    if (consumed) return null;
    consumed = true;
    return DiscoveryCandidate(
      id: 'bob',
      firstName: 'Roberto',
      birthDate: DateTime.utc(2000),
      gender: 'masculino',
      careerId: 'sistemas',
      mainPhotoUrl: 'https://example.test/photo.jpg',
      interestIds: [],
      description: '',
      isActive: true,
    );
  }

  @override
  Future<bool> decide(String from, String to, String type) async => true;
}
