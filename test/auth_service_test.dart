import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/auth/auth_gate.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';

class TestUser implements User {
  @override
  String get uid => 'ana';
  @override
  String get email => 'ana@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCredential implements UserCredential {
  @override
  User get user => TestUser();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LocalAuth implements FirebaseAuth {
  final changes = StreamController<User?>.broadcast();
  User? current;
  int registrations = 0, logins = 0, logouts = 0;
  String? lastEmail;
  bool failLogin = false;
  @override
  Stream<User?> authStateChanges() async* {
    yield current;
    yield* changes.stream;
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    registrations++;
    lastEmail = email;
    current = TestUser();
    changes.add(current);
    return TestCredential();
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    logins++;
    lastEmail = email;
    if (failLogin) throw FirebaseAuthException(code: 'invalid-credential');
    current = TestUser();
    changes.add(current);
    return TestCredential();
  }

  @override
  Future<void> signOut() async {
    logouts++;
    current = null;
    changes.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LocalAuth auth;
  late FakeFirebaseFirestore db;
  late AuthService service;
  setUp(() {
    auth = LocalAuth();
    db = FakeFirebaseFirestore();
    service = AuthService(auth: auth, firestore: db);
  });
  tearDown(() => auth.changes.close());

  test(
    'Registro delega Auth y crea documento privado inactivo sin sobrescribirlo',
    () async {
      await service.register(
        ' ana@example.com ',
        'test-password',
        DateTime(2000, 1, 1),
      );
      expect(auth.registrations, 1);
      expect(auth.lastEmail, 'ana@example.com');
      expect(await service.ensureProfile(TestUser()), isTrue);
      final before = (await db.collection('users').doc('ana').get()).data();
      expect(before!['role'], 'user');
      expect(before['isActive'], isFalse);
      expect(before['birthDate'], Timestamp.fromDate(DateTime.utc(2000)));
      expect(
        await service.ensureProfile(TestUser(), birthDate: DateTime(2001)),
        isTrue,
      );
      expect((await db.collection('users').doc('ana').get()).data(), before);
    },
  );
  test('Menor rechazado antes de llamar Auth o escribir Firestore', () async {
    await expectLater(
      service.register('ana@example.com', 'test-password', DateTime.now()),
      throwsArgumentError,
    );
    expect(auth.registrations, 0);
    expect((await db.collection('users').get()).docs, isEmpty);
  });
  test('Login válido e inválido no crean ni modifican perfiles', () async {
    await service.login(' ana@example.com ', 'test-password');
    expect(auth.lastEmail, 'ana@example.com');
    expect(auth.logins, 1);
    auth.failLogin = true;
    await expectLater(
      service.login('ana@example.com', 'wrong'),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect((await db.collection('users').get()).docs, isEmpty);
  });
  test('Registro interrumpido se completa sin crear otra cuenta', () async {
    expect(await service.ensureProfile(TestUser()), isFalse);
    expect(
      await service.ensureProfile(TestUser(), birthDate: DateTime(2000)),
      isTrue,
    );
    expect(auth.registrations, 0);
    expect((await db.collection('users').get()).docs, hasLength(1));
  });
  test(
    'Logout limpia la fecha temporal de registro y delega signOut',
    () async {
      await service.register(
        'ana@example.com',
        'test-password',
        DateTime(2000),
      );
      await service.logout();
      expect(auth.logouts, 1);
      expect(auth.current, isNull);
      expect(await service.ensureProfile(TestUser()), isFalse);
    },
  );
  testWidgets(
    'AuthGate restaura usuario del stream y vuelve al login al cerrar sesión',
    (tester) async {
      await service.register(
        'ana@example.com',
        'test-password',
        DateTime(2000),
      );
      await service.ensureProfile(TestUser());
      await tester.pumpWidget(MaterialApp(home: AuthGate(service: service)));
      await tester.pumpAndSettle();
      expect(find.text('Univalle · Cochabamba'), findsOneWidget);
      await tester.ensureVisible(find.text('Cerrar sesión'));
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Correo electrónico'), findsOneWidget);
      expect(find.text('Univalle · Cochabamba'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
