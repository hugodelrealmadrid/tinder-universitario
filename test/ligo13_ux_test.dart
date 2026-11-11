import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';
import 'package:tinder_universitario/features/chat/voice_note_recorder.dart';
import 'package:tinder_universitario/features/verification/admin_workspace.dart';
import 'package:tinder_universitario/features/verification/audit_presentation.dart';
import 'verification_fixtures.dart';
import 'voice_note_test.dart' show FakeCapture, audiblePcm;

void main() {
  testWidgets(
    'Un filtro de otra página sigue activo sin mostrar su identificador técnico',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminSelect(
              label: 'Actor',
              value: 'private-uid',
              options: const {'all': 'Todos'},
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Selección anterior'), findsOneWidget);
      expect(find.text('private-uid'), findsNothing);
    },
  );

  test('Fechas locales de chat distinguen hoy, ayer y fechas históricas', () {
    final now = DateTime(2026, 11, 2, 10);
    expect(chatDay(now, now: now), 'Hoy');
    expect(chatDay(DateTime(2026, 11, 1, 23), now: now), 'Ayer');
    expect(chatDay(DateTime(2025, 12, 1), now: now), '01/12/2025');
  });
  test(
    'Auditoría conserva desconocidos y no inventa identidades, fecha ni éxito',
    () {
      expect(
        eventAction('unknown'),
        'Acción histórica sin descripción disponible',
      );
      expect(personName(null), 'Persona no disponible');
      expect(eventResult(null), 'No consignado');
      expect(
        eventSentence({'action': 7}),
        contains('Acción histórica sin descripción disponible'),
      );
      expect(adminDate(null), 'Fecha no disponible');
      expect(
        eventSentence({
          'action': 'verification_approved',
          'actor': {'name': 'Revisora'},
          'target': {'name': 'Estudiante'},
        }),
        contains('Revisora aprobó la verificación de Estudiante'),
      );
    },
  );
  testWidgets(
    'Voz: deslizar arriba bloquea y soltar no envía; descartar cierra la captura',
    (t) async {
      final capture = FakeCapture();
      var sends = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceNoteRecorder(
              enabled: true,
              capture: capture,
              onBusy: (_) {},
              onSend: (Uint8List bytes) async {
                sends++;
              },
            ),
          ),
        ),
      );
      final g = await t.startGesture(t.getCenter(find.byIcon(Icons.mic)));
      await t.pump(const Duration(milliseconds: 650));
      capture.stream.add(audiblePcm(3200));
      await t.pump();
      await g.moveBy(const Offset(0, -100));
      await t.pump();
      await g.up();
      await t.pump();
      expect(find.textContaining('Grabación bloqueada'), findsOneWidget);
      expect(capture.stops, 0);
      expect(sends, 0);
      await t.tap(find.byTooltip('Cancelar grabación'));
      await t.pumpAndSettle();
      expect(capture.cancels, greaterThan(0));
      expect(sends, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'Usuarios responsivos a $width: buscar persona y seleccionar sin UID',
      (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          FlutterError.dumpErrorToConsole(details);
          previous?.call(details);
        };
        addTearDown(() => FlutterError.onError = previous);
        final api = FakeVerificationClient();
        String? selected;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminPeopleView(
                client: api,
                selecting: true,
                onInspect: (id) => selected = id,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('UID de la cuenta'), findsNothing);
        expect(find.text('Persona Ficticia'), findsWidgets);
        await t.enterText(find.byType(TextField), 'persona@ligo.test');
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Seleccionar'));
        await t.tap(find.text('Seleccionar'));
        expect(selected, 'target');
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'Auditoría responsiva a $width oculta identificadores técnicos',
      (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final api = FakeVerificationClient()
          ..events = [
            {
              'id': 'secret-id',
              'action': 'role_admin',
              'actorId': 'actor-id',
              'targetId': 'target-id',
              'actor': {'name': 'Revisora'},
              'target': {'name': 'Estudiante'},
              'at': '2026-11-02T10:00:00Z',
            },
          ];
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AdminHistoryView(client: api)),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.textContaining('Asignó el rol Administrador'),
          findsWidgets,
        );
        expect(find.textContaining('secret-id'), findsNothing);
        expect(find.text('No consignado'), findsWidgets);
        expect(t.takeException(), isNull);
      },
    );
  }
}
