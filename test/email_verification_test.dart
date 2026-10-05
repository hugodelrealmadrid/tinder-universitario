import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/auth/auth_gate.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';
import 'package:tinder_universitario/features/auth/email_verification_screen.dart';
import 'package:tinder_universitario/features/home/home_screen.dart';
import 'package:tinder_universitario/theme/app_theme.dart';
import 'auth_service_test.dart' show LocalAuth;

class _User implements User {
  _User({
    this.verified = false,
    this.id = 'ana',
    this.address = 'ana@example.test',
  });
  final bool verified;
  final String id, address;
  int sends = 0, reloads = 0;
  Future<void> Function()? onSend, onReload;
  @override
  String get uid => id;
  @override
  String get email => address;
  @override
  bool get emailVerified => verified;
  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    sends++;
    await onSend?.call();
  }

  @override
  Future<void> reload() async {
    reloads++;
    await onReload?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credential implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends LocalAuth {
  _User next = _User();
  Object? logoutError;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    registrations++;
    current = next;
    changes.add(current);
    return _Credential(next);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    logins++;
    current = next;
    changes.add(current);
    return _Credential(next);
  }

  @override
  Future<void> signOut() async {
    if (logoutError != null) throw logoutError!;
    await super.signOut();
  }
}

void main() {
  late _Auth auth;
  late FakeFirebaseFirestore db;
  late AuthService service;
  late DateTime now;
  setUp(() {
    auth = _Auth();
    db = FakeFirebaseFirestore();
    now = DateTime.utc(2026, 10, 5);
    service = AuthService(auth: auth, firestore: db, now: () => now);
  });
  tearDown(() async {
    await auth.changes.close();
    service.dispose();
  });

  Future<void> open(
    WidgetTester tester, {
    Widget? screen,
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: screen ?? AuthGate(service: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('Usuario null muestra Auth y ninguna pantalla protegida', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.byType(EmailVerificationScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets(
    'Sesión existente no verificada bloquea Inicio incluso al reabrir',
    (tester) async {
      auth.current = auth.next;
      await db.doc('users/ana').set({'firstName': 'Ana', 'isActive': true});
      final before = (await db.doc('users/ana').get()).data();
      await open(tester);
      expect(find.text('Verifica tu correo'), findsOneWidget);
      expect(find.text('ana@example.test'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(auth.next.sends, 0); // Login/reapertura no envían automáticamente.
      await close(tester);
      await open(tester);
      expect(find.byType(EmailVerificationScreen), findsOneWidget);
      expect((await db.doc('users/ana').get()).data(), before);
    },
  );

  testWidgets('Usuario verificado entra al flujo normal', (tester) async {
    auth.current = _User(verified: true);
    await db.doc('users/ana').set({'firstName': 'Ana'});
    await open(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(EmailVerificationScreen), findsNothing);
  });

  testWidgets(
    'Registro solicita correo y mantiene documento inicial único sin emailVerified',
    (tester) async {
      await service.register(
        'ana@example.test',
        'test-password',
        DateTime(2000),
      );
      expect(auth.registrations, 1);
      expect(auth.next.sends, 1);
      await open(tester);
      expect(
        find.text('Enviamos un enlace de verificación a:'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
      final initial = (await db.doc('users/ana').get()).data()!;
      expect(initial['role'], 'user');
      expect(initial['isActive'], false);
      expect(initial.containsKey('emailVerified'), false);
      await service.ensureProfile(auth.current!);
      expect((await db.doc('users/ana').get()).data(), initial);
      expect((await db.collection('users').get()).docs, hasLength(1));
      await close(tester);
    },
  );

  testWidgets(
    'Login correcto no verificado muestra verificación sin error de contraseña',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'ana@example.test',
      );
      await tester.enterText(find.byType(TextFormField).last, 'test-password');
      await tap(tester, 'Iniciar sesión');
      expect(auth.logins, 1);
      expect(find.text('Verifica tu correo'), findsOneWidget);
      expect(find.text('Correo o contraseña incorrectos.'), findsNothing);
    },
  );

  testWidgets(
    'Ya verifiqué recarga; false mantiene barrera y muestra mensaje',
    (tester) async {
      auth.current = auth.next;
      await open(tester);
      await tap(tester, 'Ya verifiqué mi correo');
      expect(auth.next.reloads, 1);
      expect(
        find.text('Tu correo todavía no ha sido verificado.'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
    },
  );

  testWidgets(
    'Reload lee un nuevo currentUser, no el objeto anterior, y continúa',
    (tester) async {
      auth.current = auth.next;
      await db.doc('users/ana').set({'firstName': 'Ana'});
      auth.next.onReload = () async {
        auth.current = _User(verified: true);
        // Sin evento simulado: el callback también debe volver a evaluar currentUser.
      };
      await open(tester);
      await tap(tester, 'Ya verifiqué mi correo');
      expect(auth.next.emailVerified, false);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(auth.next.reloads, 1);
    },
  );

  testWidgets('userChanges tras reload actualiza la barrera automáticamente', (
    tester,
  ) async {
    auth.current = auth.next;
    await db.doc('users/ana').set({'firstName': 'Ana'});
    await open(tester);
    auth.current = _User(verified: true);
    auth.changes.add(auth.current);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets(
    'Reenvío tiene feedback y cooldown visible que vuelve a habilitarlo',
    (tester) async {
      auth.current = auth.next;
      await open(tester);
      await tap(tester, 'Reenviar correo');
      expect(auth.next.sends, 1);
      expect(
        find.textContaining('Correo de verificación enviado.'),
        findsOneWidget,
      );
      expect(find.text('Podrás reenviar el correo en 30 s'), findsOneWidget);
      final button = find.widgetWithText(OutlinedButton, 'Reenviar correo');
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      await tap(tester, 'Reenviar correo');
      expect(auth.next.sends, 2);
      await close(tester);
    },
  );

  testWidgets(
    'Doble clic durante envío hace una sola llamada y muestra loading',
    (tester) async {
      auth.current = auth.next;
      final pending = Completer<void>();
      auth.next.onSend = () => pending.future;
      await open(tester);
      final button = find.widgetWithText(OutlinedButton, 'Reenviar correo');
      await tester.ensureVisible(button);
      final callback = tester.widget<OutlinedButton>(button).onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(auth.next.sends, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      pending.complete();
      await tester.pumpAndSettle();
      await close(tester);
    },
  );

  testWidgets('Envío automático pendiente comparte bloqueo con Reenviar', (
    tester,
  ) async {
    final pending = Completer<void>();
    auth.next.onSend = () => pending.future;
    final registration = service.register(
      'ana@example.test',
      'test-password',
      DateTime(2000),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthGate(service: service),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(service.sendingVerification, true);
    expect(await service.sendVerificationEmail(), false);
    expect(auth.next.sends, 1);
    pending.complete();
    await registration;
    await tester.pumpAndSettle();
    expect(find.text('Enviamos un enlace de verificación a:'), findsOneWidget);
    await close(tester);
  });

  for (final code in [
    'network-request-failed',
    'too-many-requests',
    'user-disabled',
    'unknown',
  ]) {
    testWidgets('Error de reenvío $code no expone SDK ni permite entrar', (
      tester,
    ) async {
      auth.current = auth.next;
      auth.next.onSend = () async => throw FirebaseAuthException(
        code: code,
        message: 'detalle privado del SDK',
      );
      await open(tester);
      await tap(tester, 'Reenviar correo');
      expect(
        find.text(emailVerificationError(FirebaseAuthException(code: code))),
        findsOneWidget,
      );
      expect(find.textContaining('detalle privado'), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
      expect(service.resendSeconds, code == 'too-many-requests' ? 30 : 0);
      await close(tester);
    });
  }

  testWidgets(
    'Error de envío tras crear cuenta se recupera sin segundo registro',
    (tester) async {
      auth.next.onSend = () async =>
          throw FirebaseAuthException(code: 'network-request-failed');
      await service.register(
        'ana@example.test',
        'test-password',
        DateTime(2000),
      );
      await open(tester);
      expect(find.textContaining('No hay conexión.'), findsOneWidget);
      expect(find.text('Enviamos un enlace de verificación a:'), findsNothing);
      expect((await db.doc('users/ana').get()).exists, true);
      auth.next.onSend = null;
      await tap(tester, 'Reenviar correo');
      expect(auth.registrations, 1);
      expect(auth.next.sends, 2);
      expect((await db.collection('users').get()).docs, hasLength(1));
      await close(tester);
    },
  );

  testWidgets('Error al recargar mantiene barrera y permite reintentar', (
    tester,
  ) async {
    auth.current = auth.next;
    auth.next.onReload = () async =>
        throw FirebaseAuthException(code: 'network-request-failed');
    await open(tester);
    await tap(tester, 'Ya verifiqué mi correo');
    expect(find.textContaining('No hay conexión.'), findsOneWidget);
    auth.next.onReload = null;
    await tap(tester, 'Ya verifiqué mi correo');
    expect(auth.next.reloads, 2);
    expect(
      find.text('Tu correo todavía no ha sido verificado.'),
      findsOneWidget,
    );
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('Cerrar sesión desde verificación vuelve a Login', (
    tester,
  ) async {
    auth.current = auth.next;
    await open(tester);
    await tap(tester, 'Cerrar sesión');
    expect(auth.logouts, 1);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.byType(EmailVerificationScreen), findsNothing);
  });

  testWidgets('Fallo al cerrar sesión se muestra sin habilitar Inicio', (
    tester,
  ) async {
    auth.current = auth.next;
    auth.logoutError = FirebaseAuthException(code: 'network-request-failed');
    await open(tester);
    await tap(tester, 'Cerrar sesión');
    expect(find.textContaining('No hay conexión.'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  test(
    'Usuario nulo antes/después de reload y sesión sustituida no verifican',
    () async {
      await expectLater(
        service.reloadEmailVerification(),
        throwsA(isA<FirebaseAuthException>()),
      );
      await expectLater(
        service.sendVerificationEmail(),
        throwsA(isA<FirebaseAuthException>()),
      );
      for (final replacement in <User?>[
        null,
        _User(id: 'bob', verified: true),
      ]) {
        auth.current = auth.next;
        auth.next.onReload = () async => auth.current = replacement;
        await expectLater(
          service.reloadEmailVerification(),
          throwsA(isA<FirebaseAuthException>()),
        );
      }
    },
  );

  testWidgets(
    'Usuario nulo inesperado muestra recuperación, no excepción técnica',
    (tester) async {
      await open(
        tester,
        screen: EmailVerificationScreen(
          service: service,
          onVerified: () => fail('No debe entrar'),
        ),
      );
      await tap(tester, 'Ya verifiqué mi correo');
      expect(
        find.textContaining('Tu sesión ya no está disponible.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('Respuesta tardía de envío tras logout no afecta otra cuenta', () async {
    auth.current = auth.next;
    final pending = Completer<void>();
    auth.next.onSend = () => pending.future;
    final sending = service.sendVerificationEmail();
    await service.logout();
    auth.current = _User(id: 'bob');
    pending.complete();
    expect(await sending, false);
    expect(service.verificationSent, false);
    expect(service.sendingVerification, false);
    expect(service.resendSeconds, 0);
  });

  test(
    'Sesión invalidada durante envío no deja loading al iniciar de nuevo',
    () async {
      auth.current = auth.next;
      final pending = Completer<void>();
      auth.next.onSend = () => pending.future;
      final sending = service.sendVerificationEmail();
      // Expiración externa del SDK, sin pasar por el botón logout de la app.
      auth.current = null;
      pending.complete();
      expect(await sending, false);
      auth.current = auth.next;
      auth.next.onSend = null;
      expect(service.sendingVerification, false);
      expect(await service.sendVerificationEmail(), true);
      expect(auth.next.sends, 2);
    },
  );

  testWidgets('Verificado sin documento conserva recuperación de registro', (
    tester,
  ) async {
    auth.current = _User(verified: true);
    await open(tester);
    expect(find.text('Completar registro'), findsWidgets);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(EmailVerificationScreen), findsNothing);
  });

  for (final size in [const Size(360, 800), const Size(1280, 900)]) {
    testWidgets('Verificación responsive $size con correo largo sin overflow', (
      tester,
    ) async {
      auth.current = _User(
        address: 'estudiante.nombre.apellido.muy.largo@correo-ejemplo.test',
      );
      await open(tester, size: size);
      await tap(tester, 'Reenviar correo');
      await tester.ensureVisible(find.text('Cerrar sesión'));
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }
}
