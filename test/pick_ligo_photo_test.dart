import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tinder_universitario/widgets/pick_ligo_photo.dart';

void main() {
  testWidgets('Android ofrece cámara y galería y permite cancelar', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                expect(await pickLigoPhoto(context, ImagePicker()), isNull);
                finished = true;
              },
              child: const Text('Añadir foto'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Añadir foto'));
    await tester.pumpAndSettle();
    expect(find.text('Tomar fotografía'), findsOneWidget);
    expect(find.text('Elegir de la galería'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });
}
