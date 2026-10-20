import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/verification/account_access.dart';
import 'package:tinder_universitario/features/verification/backend_client.dart';
import 'package:tinder_universitario/features/verification/administration_screen.dart';
import 'package:tinder_universitario/features/verification/university_verification_screen.dart';
import 'verification_fixtures.dart';
import 'chat_media_fixtures.dart';

const pending = AccountAccess(
  role: AccountRole.user,
  status: UniversityStatus.pending,
  suspended: false,
);
const admin = AccountAccess(
  role: AccountRole.admin,
  status: UniversityStatus.approved,
  suspended: false,
);
const root = AccountAccess(
  role: AccountRole.superadmin,
  status: UniversityStatus.approved,
  suspended: false,
);
Future<void> tap(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.runAsync(() async {
    await tester.tap(f);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

Map<String, dynamic> request() => {
  'id': 'r',
  'uid': 'student',
  'status': 'pending',
  'documentStage': 'ready',
  'canReview': true,
  'createdAt': '2026-10-19T12:00:00Z',
};
Widget panel(FakeVerificationClient api, {AccountAccess access = admin}) =>
    MaterialApp(
      home: AdministrationScreen(
        client: api,
        access: access,
        uid: 'admin',
        logout: const Text('SALIR'),
        onDating: () {},
      ),
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List pngFixture;
  setUpAll(() async {
    pngFixture = await chatPngFixture();
  });
  test('Mensajes seguros de error y motivos comprensibles', () {
    expect(
      verificationError(const VerificationFailure('conflict')),
      contains('ya fue resuelta'),
    );
    expect(
      verificationError(StateError('token-super-secreto')),
      isNot(contains('secreto')),
    );
    expect(rejectionReasons['unreadable'], contains('legible'));
  });
  test(
    'Carnet valida tamaño, extensión, firma y decodificación real',
    () async {
      final png = pngFixture;
      await validateUniversityPhoto(png, 'png');
      for (final bytes in [
        Uint8List(0),
        Uint8List(5 * 1024 * 1024 + 1),
        Uint8List.fromList('<svg/>'.codeUnits),
      ]) {
        await expectLater(
          validateUniversityPhoto(bytes, 'png'),
          throwsA(isA<VerificationFailure>()),
        );
      }
      await expectLater(
        validateUniversityPhoto(png, 'jpg'),
        throwsA(isA<VerificationFailure>()),
      );
      await expectLater(
        validateUniversityPhoto(png, 'exe'),
        throwsA(isA<VerificationFailure>()),
      );
    },
  );
  testWidgets(
    'Estudiante selecciona, valida, envía al backend y retira con confirmación',
    (tester) async {
      final api = FakeVerificationClient();
      final png = pngFixture;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversityVerificationScreen(
            client: api,
            access: pending,
            logout: const Text('SALIR'),
            picker: () async => (png, 'png'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Seleccionar foto del carnet');
      expect(find.text('Enviar carnet'), findsOneWidget);
      await tap(tester, 'Enviar carnet');
      expect(
        api.calls,
        containsAllInOrder(['provision', 'begin', 'upload:new']),
      );
      expect(find.text('Enviar carnet'), findsNothing);
      expect(find.textContaining('Solicitud recibida'), findsOneWidget);
      await tap(tester, 'Retirar solicitud');
      expect(api.calls, isNot(contains('withdraw:new')));
      await tap(tester, 'Confirmar');
      expect(api.calls, contains('withdraw:new'));
    },
  );
  testWidgets(
    'Rechazado muestra motivo y permite reenviar; descartar no sube',
    (tester) async {
      final api = FakeVerificationClient()
        ..own = {'id': 'old', 'status': 'rejected', 'reasonCode': 'unreadable'};
      final png = pngFixture;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversityVerificationScreen(
            client: api,
            access: const AccountAccess(
              role: AccountRole.user,
              status: UniversityStatus.rejected,
              suspended: false,
            ),
            logout: const Text('SALIR'),
            picker: () async => (png, 'png'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(rejectionReasons['unreadable']!), findsOneWidget);
      await tap(tester, 'Seleccionar nuevo carnet');
      await tap(tester, 'Descartar foto');
      expect(api.calls.any((c) => c.startsWith('upload')), false);
      await tap(tester, 'Seleccionar nuevo carnet');
      await tap(tester, 'Enviar carnet');
      expect(api.calls, contains('upload:new'));
    },
  );
  testWidgets('Suspendido no ofrece carga ni consultas administrativas', (
    tester,
  ) async {
    final api = FakeVerificationClient();
    await tester.pumpWidget(
      MaterialApp(
        home: UniversityVerificationScreen(
          client: api,
          access: const AccountAccess(
            role: AccountRole.user,
            status: UniversityStatus.approved,
            suspended: true,
          ),
          logout: const Text('SALIR'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('suspendida administrativamente'),
      findsOneWidget,
    );
    expect(find.text('Seleccionar foto del carnet'), findsNothing);
    expect(api.calls, isEmpty);
  });
  testWidgets('Usuario normal no abre el dashboard ni consulta endpoints', (
    tester,
  ) async {
    final api = FakeVerificationClient();
    await tester.pumpWidget(panel(api, access: pending));
    await tester.pumpAndSettle();
    expect(find.text('Acceso administrativo no autorizado.'), findsOneWidget);
    expect(api.calls, isEmpty);
  });
  testWidgets(
    'Admin confirma aprobación; cancelación no decide y conflicto actualiza lista',
    (tester) async {
      final api = FakeVerificationClient()..rows = [request()];
      await tester.pumpWidget(panel(api));
      await tester.pumpAndSettle();
      expect(find.text('Auditoría'), findsNothing);
      await tap(tester, 'Aprobar');
      await tap(tester, 'Cancelar');
      expect(api.calls.any((c) => c.startsWith('decide')), false);
      api.decisionFailure = const VerificationFailure('conflict');
      await tap(tester, 'Aprobar');
      await tap(tester, 'Confirmar');
      expect(api.calls, contains('decide:r:approved:verified'));
      expect(find.textContaining('ya fue resuelta'), findsOneWidget);
    },
  );
  testWidgets('Rechazo exige escoger motivo antes de llamar al servidor', (
    tester,
  ) async {
    final api = FakeVerificationClient()..rows = [request()];
    await tester.pumpWidget(panel(api));
    await tester.pumpAndSettle();
    await tap(tester, 'Rechazar');
    expect(api.calls.any((c) => c.startsWith('decide')), false);
    await tap(tester, 'Fotografía ilegible');
    expect(api.calls, contains('decide:r:rejected:unreadable'));
  });
  testWidgets('Admin consulta cuenta y suspende con motivo y confirmación', (
    tester,
  ) async {
    final api = FakeVerificationClient();
    await tester.pumpWidget(panel(api));
    await tester.pumpAndSettle();
    await tap(tester, 'Cuentas');
    await tester.enterText(find.byType(TextField), 'target');
    await tap(tester, 'Consultar cuenta');
    expect(find.text('Asignar rol de administrador'), findsNothing);
    await tap(tester, 'Suspender cuenta');
    await tap(tester, 'Seguridad');
    await tap(tester, 'Confirmar');
    expect(api.calls, contains('suspend:target:true:safety'));
    expect(find.text('Restablecer cuenta'), findsOneWidget);
  });
  testWidgets('Superadmin gestiona rol ajeno y ve auditoría mínima', (
    tester,
  ) async {
    final api = FakeVerificationClient()
      ..events = [
        {
          'id': 'event',
          'action': 'role_admin',
          'actorId': 'root',
          'targetId': 'target',
          'reasonCode': 'role_management',
          'at': '2026-10-19T12:00:00Z',
        },
      ];
    await tester.pumpWidget(panel(api, access: root));
    await tester.pumpAndSettle();
    await tap(tester, 'Cuentas');
    await tester.enterText(find.byType(TextField), 'target');
    await tap(tester, 'Consultar cuenta');
    await tap(tester, 'Asignar rol de administrador');
    await tap(tester, 'Confirmar');
    expect(api.calls, contains('role:target:admin'));
    await tap(tester, 'Revocar rol de administrador');
    await tap(tester, 'Confirmar');
    expect(api.calls, contains('role:target:user'));
    await tap(tester, 'Auditoría');
    expect(api.calls, contains('audit'));
    expect(find.textContaining('role_admin'), findsOneWidget);
  });
  testWidgets('Panel no ofrece cambios del propio rol', (tester) async {
    final api = FakeVerificationClient()
      ..target = {
        'uid': 'admin',
        'role': 'superadmin',
        'verificationStatus': 'approved',
        'suspended': false,
      };
    await tester.pumpWidget(panel(api, access: root));
    await tester.pumpAndSettle();
    await tap(tester, 'Cuentas');
    await tap(tester, 'Consultar cuenta');
    expect(
      find.textContaining('No puedes modificar tu propia'),
      findsOneWidget,
    );
    expect(find.text('Suspender cuenta'), findsNothing);
    expect(find.text('Revocar rol de administrador'), findsNothing);
  });
  testWidgets('Vista privada maneja error y se cierra tras 60 segundos', (
    tester,
  ) async {
    final api = FakeVerificationClient();
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateDocumentView(client: api, requestId: 'r'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls, contains('document:r'));
    expect(find.textContaining('No tienes autorización'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(find.textContaining('Vista cerrada'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Carnet decodificado no entra en ImageCache y se oculta al perder foco',
    (tester) async {
      final api = FakeVerificationClient()..documentBytes = pngFixture;
      final before = PaintingBinding.instance.imageCache.currentSize;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: PrivateDocumentView(client: api, requestId: 'r'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(PaintingBinding.instance.imageCache.currentSize, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(find.textContaining('Vista cerrada'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Dashboard adaptable a 360 píxeles sin desbordar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeVerificationClient()..rows = [request()];
    await tester.pumpWidget(panel(api, access: root));
    await tester.pumpAndSettle();
    await tap(tester, 'Ver carnet privado');
    expect(tester.takeException(), isNull);
    await tap(tester, 'Cerrar');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Decisión en curso desactiva botones y evita duplicados', (
    tester,
  ) async {
    final completed = Completer<void>();
    final api = FakeVerificationClient()
      ..rows = [request()]
      ..decisionWait = completed.future;
    await tester.pumpWidget(panel(api));
    await tester.pumpAndSettle();
    await tap(tester, 'Aprobar');
    await tester.runAsync(() async {
      await tester.tap(find.text('Confirmar'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Aprobar'))
          .onPressed,
      isNull,
    );
    expect(api.calls.where((e) => e.startsWith('decide')).length, 1);
    await tester.runAsync(() async {
      completed.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  });
  testWidgets('Revisión de reportes usa backend y confirmación', (
    tester,
  ) async {
    final api = FakeVerificationClient()
      ..rows = [
        {
          'id': 'report',
          'reportedId': 'target',
          'reason': 'spam',
          'details': 'FICTICIO',
          'createdAt': '2026-10-19T12:00:00Z',
        },
      ];
    await tester.pumpWidget(panel(api));
    await tester.pumpAndSettle();
    await tap(tester, 'Reportes');
    expect(find.text('FICTICIO'), findsOneWidget);
    await tap(tester, 'Marcar revisado');
    await tap(tester, 'Confirmar');
    expect(api.calls, contains('report:report:reviewed'));
  });
}
