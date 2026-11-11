import 'package:tinder_universitario/widgets/motion_entrance.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/theme/app_theme.dart';
import 'package:tinder_universitario/widgets/app_ui.dart';
import 'package:tinder_universitario/widgets/swipe_card.dart';
import 'package:tinder_universitario/features/verification/admin_visual.dart';
import 'package:tinder_universitario/features/verification/administration_screen.dart';
import 'package:tinder_universitario/features/verification/account_access.dart';
import 'verification_fixtures.dart';

class VisualApi extends FakeVerificationClient {
  @override
  Future<Map<String, dynamic>> administrationSummary() async => {
    'totalUsers': 3,
    'verified': 2,
    'pending': 1,
    'rejected': 0,
    'suspended': 0,
    'matches': 1,
    'pendingRequests': 1,
    'reports': 0,
  };
  @override
  Future<Map<String, dynamic>> administrationUsers({String? cursor}) async => {
    'items': [
      {
        'uid': 'fixture',
        'name': 'Estudiante ficticio',
        'email': 'fixture@ligo.test',
        'university': 'Universidad ficticia',
        'career': 'Sistemas',
        'role': 'user',
        'verificationStatus': 'approved',
        'suspended': false,
        'createdAt': '2026-11-01T12:00:00Z',
      },
    ],
    'nextCursor': null,
  };
}

void main() {
  setUpAll(() async {
    const fonts = String.fromEnvironment('UI_FONT_DIR');
    if (fonts.isEmpty) return;
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family)
        ..addFont(
          File(
            '$fonts/roboto-regular.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '$fonts/materialicons-regular.otf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    await icons.load();
  });
  Future<void> open(WidgetTester t, Widget child, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('ligo-proof'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: child,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> capture(WidgetTester t, String name) async {
    const dir = String.fromEnvironment('UI_CAPTURE_DIR');
    if (dir.isEmpty) return;
    await t.runAsync(() async {
      final image = await t
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('ligo-proof')),
          )
          .toImage();
      final b = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(b!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final root in [false, true]) {
    for (final width in [390.0, 1440.0]) {
      testWidgets(
        'Dashboard ${root ? 'superadmin' : 'admin'} responsive $width con datos del cliente',
        (t) async {
          await open(
            t,
            AdministrationScreen(
              client: VisualApi(),
              access: AccountAccess(
                role: root ? AccountRole.superadmin : AccountRole.admin,
                status: UniversityStatus.approved,
                suspended: false,
              ),
              uid: 'operator',
              logout: const Text('Cerrar sesión'),
              onDating: () {},
            ),
            Size(width, 960),
          );
          expect(find.text('El pulso de tu comunidad'), findsOneWidget);
          expect(find.text('3'), findsWidgets);
          await capture(
            t,
            'dashboard-${root ? 'superadmin' : 'admin'}-${width.toInt()}',
          );
          if (width < 1050) {
            await t.tap(find.byTooltip('Menú de administración'));
            await t.pumpAndSettle();
          }
          expect(find.text('Universidades'), findsNothing);
          expect(
            find.text('Roles y permisos'),
            root ? findsOneWidget : findsNothing,
          );
          expect(find.text('Carreras'), findsOneWidget);
          expect(find.text('Intereses'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('Tabla busca y filtra sin asignar roles ni escribir datos', (
    t,
  ) async {
    final api = VisualApi();
    String? inspect;
    await open(
      t,
      Scaffold(
        body: AdminUsersView(client: api, onInspect: (uid) => inspect = uid),
      ),
      const Size(1440, 960),
    );
    expect(find.text('Estudiante ficticio'), findsOneWidget);
    await capture(t, 'usuarios-web');
    await t.enterText(find.byType(TextField), 'No coincide');
    await t.pumpAndSettle();
    expect(find.text('Estudiante ficticio'), findsNothing);
    await t.enterText(find.byType(TextField), 'fixture');
    await t.pumpAndSettle();
    expect(find.text('Estudiante ficticio'), findsOneWidget);
    await t.ensureVisible(find.text('Ver detalle'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ver detalle'));
    expect(inspect, 'fixture');
    expect(api.calls.any((c) => c.startsWith('role:')), false);
  });
  testWidgets('Un usuario común no consulta métricas ni abre dashboard', (
    t,
  ) async {
    final api = VisualApi();
    await open(
      t,
      AdministrationScreen(
        client: api,
        access: const AccountAccess(
          role: AccountRole.user,
          status: UniversityStatus.approved,
          suspended: false,
        ),
        uid: 'student',
        logout: const Text('Salir'),
        onDating: () {},
      ),
      const Size(390, 844),
    );
    expect(find.text('Acceso administrativo no autorizado.'), findsOneWidget);
    expect(api.calls, isEmpty);
  });
  testWidgets(
    'Swipe configurable retorna con gesto corto y una sola decisión con gesto suficiente',
    (t) async {
      final calls = <bool>[];
      await open(
        t,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 330,
              child: SwipeCard(
                thresholdFraction: .45,
                maxThreshold: 180,
                onDecision: (like) async {
                  calls.add(like);
                  return false;
                },
                child: Container(
                  height: 460,
                  decoration: BoxDecoration(
                    color: AppColors.rose,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Center(child: LigoLogo(size: 42)),
                ),
              ),
            ),
          ),
        ),
        const Size(390, 844),
      );
      await t.drag(
        find.byKey(const ValueKey('swipe-card-gesture')),
        const Offset(80, 0),
      );
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      final gesture = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('swipe-card-gesture'))),
      );
      await gesture.moveBy(const Offset(-210, 0));
      await t.pump();
      expect(find.text('PASAR'), findsOneWidget);
      await capture(t, 'swipe-nope-mobile');
      await gesture.up();
      await t.pumpAndSettle();
      expect(calls, [false]);
    },
  );
  testWidgets('Motion reducido conserva el acceso y omite la transición', (
    t,
  ) async {
    final routes = <Route<void>>[];
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Builder(
              builder: (context) => MotionEntrance(
                child: TextButton(
                  onPressed: () {
                    final route = conversationRoute(
                      context,
                      (_) => const Scaffold(body: Text('Conversación')),
                    );
                    routes.add(route);
                    Navigator.of(context).push(route);
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Abrir'));
    await t.pumpAndSettle();
    expect(find.text('Conversación'), findsOneWidget);
    expect(
      (routes.single as PageRouteBuilder<void>).transitionDuration,
      Duration.zero,
    );
  });

  test('Paleta oficial y SVG disponibles', () {
    expect(AppColors.coral, const Color(0xFFFF315A));
    expect(AppColors.secondary, const Color(0xFFE91E63));
    expect(AppColors.surface, const Color(0xFFF5F5F7));
    for (final variant in ['light', 'dark', 'mono']) {
      expect(
        File(
          'assets/branding/ligo/logo-horizontal-$variant.svg',
        ).readAsStringSync(),
        contains('<path'),
      );
      expect(
        File('assets/branding/ligo/logo-vertical-$variant.svg').existsSync(),
        true,
      );
    }
  });
}
