import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/main.dart';

void main() {
  testWidgets(
    'La compilación demo online se identifica sin cambiar autorización',
    (tester) async {
      await tester.pumpWidget(const TinderUniversitarioApp());
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('SHOWCASE_ONLINE')) {
        expect(find.byType(Banner), findsOneWidget);
        expect(
          tester.widget<Banner>(find.byType(Banner)).message,
          'DEMO ONLINE',
        );
      } else {
        expect(find.byType(Banner), findsNothing);
      }
      expect(find.text('No se pudo iniciar Firebase.'), findsOneWidget);
    },
  );
}
