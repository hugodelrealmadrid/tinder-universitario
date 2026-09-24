import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/auth/auth_form.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';
import 'package:tinder_universitario/main.dart';

void main() {
  test('Edad: límite exacto, menor y nacimiento futuro', () {
    final today = DateTime(2026, 9, 23);
    expect(isAdult(DateTime(2008, 9, 23), today: today), isTrue);
    expect(isAdult(DateTime(2008, 9, 24), today: today), isFalse);
    expect(isAdult(DateTime(2007, 12, 31), today: today), isTrue);
    expect(isAdult(DateTime(2027), today: today), isFalse);
  });
  test('Edad: nacimiento el 29 de febrero', () {
    expect(
      isAdult(DateTime(2008, 2, 29), today: DateTime(2026, 2, 28)),
      isFalse,
    );
    expect(isAdult(DateTime(2008, 2, 29), today: DateTime(2026, 3, 1)), isTrue);
  });
  test('Errores Firebase no muestran detalles internos', () {
    expect(
      firebaseError(FirebaseAuthException(code: 'invalid-credential')),
      'Correo o contraseña incorrectos.',
    );
    expect(
      firebaseError(FirebaseAuthException(code: 'email-already-in-use')),
      contains('ya tiene una cuenta'),
    );
    expect(
      firebaseError(Exception('detalle privado')),
      isNot(contains('detalle privado')),
    );
  });
  testWidgets('Fecha obligatoria para completar registro', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: key,
            child: BirthDateField(onChanged: (_) {}),
          ),
        ),
      ),
    );
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Selecciona tu fecha de nacimiento.'), findsOneWidget);
  });
  testWidgets('Plataforma sin configuración muestra error recuperable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(const TinderUniversitarioApp());
      await tester.pumpAndSettle();
      expect(find.text('No se pudo iniciar Firebase.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
