import 'package:tinder_universitario/features/verification/administration_screen.dart';
import 'package:tinder_universitario/features/verification/account_access.dart';
import 'package:tinder_universitario/features/verification/admin_theme.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tinder_universitario/features/discovery/discovery_screen.dart';
import 'package:tinder_universitario/features/discovery/discovery_service.dart';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';
import 'package:tinder_universitario/features/verification/admin_visual.dart';
import 'package:tinder_universitario/theme/app_theme.dart';
import 'verification_fixtures.dart';

void main() {
  late Uint8List portrait;
  setUpAll(() async {
    portrait = await File('staging/fixtures/bob-ficticio.png').readAsBytes();
    const fonts = String.fromEnvironment('UI_FONT_DIR');
    if (fonts.isNotEmpty) {
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(
              File(
                '$fonts/roboto-regular.ttf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$fonts/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  Future<DiscoveryService> service({
    bool complete = true,
    bool mutual = false,
  }) async {
    final db = FakeFirebaseFirestore(),
        stamp = Timestamp.fromDate(DateTime(2026, 11, 2));
    final profile = {
      'firstName': 'Ana',
      'lastName': 'Ficticia',
      'birthDate': Timestamp.fromDate(DateTime(2000, 4, 17)),
      'gender': 'femenino',
      'careerId': 'career_a',
      'universityId': 'uni_a',
      'photoUrls': complete ? ['profile_photos/ana/portrait'] : <String>[],
      'mainPhotoUrl': complete ? 'profile_photos/ana/portrait' : null,
      'interestIds': ['music'],
      'isActive': complete,
      'updatedAt': stamp,
    };
    await db.doc('users/ana').set(profile);
    await db.doc('preferences/ana').set({
      'minAge': 18,
      'maxAge': 100,
      'preferredGender': 'ambos',
      'careerIds': [],
    });
    await db.doc('careers/career_a').set({
      'name': 'Ingeniería de Sistemas',
      'isActive': true,
    });
    await db.doc('universities/uni_a').set({
      'name': 'Universidad ficticia A',
      'isActive': true,
    });
    await db.doc('interests/music').set({'name': 'Música', 'isActive': true});
    await db
        .doc('discoveryCards/ana')
        .set(
          {...profile, 'age': ageOn(DateTime(2000, 4, 17))}
            ..remove('birthDate'),
        );
    await db.doc('discoveryIndex/bob').set({'isActive': true});
    await db.doc('discoveryCards/bob').set({
      'firstName': 'Bob',
      'age': 25,
      'gender': 'masculino',
      'careerId': 'career_a',
      'universityId': 'uni_a',
      'mainPhotoUrl': 'profile_photos/bob/portrait',
      'interestIds': ['music'],
      'description':
          'Entre clases, música y nuevas historias. Perfil ficticio para revisar la experiencia de LIGO.',
      'isActive': true,
    });
    if (mutual) {
      await db.doc('swipes/bob.ana').set({
        'fromUserId': 'bob',
        'toUserId': 'ana',
        'type': 'like',
        'createdAt': stamp,
      });
    }
    return DiscoveryService(firestore: db);
  }

  Future<void> open(WidgetTester t, Size size, Widget child) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('review'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: child is AdminShell
              ? AdminTheme.dark
              : const bool.fromEnvironment('LIGO_VISUAL_NIGHT') &&
                    child is! AdminShell
              ? AppTheme.night.copyWith(
                  filledButtonTheme: FilledButtonThemeData(
                    style: AppTheme.night.filledButtonTheme.style?.copyWith(
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
              : AppTheme.light,
          home: child,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> capture(WidgetTester t, String name) async {
    const dir = String.fromEnvironment('UI_REVIEW_CAPTURE_DIR');
    if (dir.isEmpty) return;
    await t.runAsync(() async {
      final image = await t
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('review')),
          )
          .toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('Motion: gesto cancelado, swipe rápido y match mutuo', (t) async {
    final svc = await service(mutual: true);
    final ownPortrait = await t.runAsync(
      () => File('staging/fixtures/ana-ficticia.png').readAsBytes(),
    );
    await open(
      t,
      const Size(390, 844),
      DiscoveryScreen(
        uid: 'ana',
        onPreferences: () {},
        onProfile: () {},
        service: svc,
        photoBuilder: (path) => Image.memory(
          path.contains('/ana/') ? ownPortrait! : portrait,
          fit: BoxFit.cover,
        ),
      ),
    );
    final photoContext = t.element(find.byType(DiscoveryScreen));
    await t.runAsync(() async {
      await precacheImage(MemoryImage(portrait), photoContext);
      await precacheImage(MemoryImage(ownPortrait!), photoContext);
    });
    await t.pumpAndSettle();
    final card = find.byKey(const ValueKey('swipe-card-gesture'));
    final gesture = await t.startGesture(t.getCenter(card));
    await gesture.moveBy(const Offset(72, 0));
    await t.pump();
    await capture(t, 'motion-swipe');
    await gesture.cancel();
    await t.pumpAndSettle();
    expect(find.text('¡Es un match!'), findsNothing);
    expect(find.text('Bob, 25'), findsWidgets);
    await t.fling(card, const Offset(95, 0), 1500);
    await t.pumpAndSettle();
    expect(find.text('¡Es un match!'), findsOneWidget);
    await capture(t, 'motion-match');
    await t.tap(find.text('Continuar descubriendo'));
    await t.pumpAndSettle();
    expect(find.text('Ya viste los perfiles compatibles'), findsOneWidget);
  });

  testWidgets(
    'Resumen usa cifras recibidas y no consulta auditoría para admin',
    (t) async {
      final api = FakeVerificationClient();
      String? destination;
      await open(
        t,
        const Size(390, 844),
        AdminOverview(client: api, onNavigate: (value) => destination = value),
      );
      expect(find.text('Usuarios registrados'), findsOneWidget);
      expect(api.calls, isNot(contains('audit')));
      final metric = find.text('Usuarios registrados');
      await t.ensureVisible(metric);
      await t.pumpAndSettle();
      await t.tap(metric);
      expect(destination, 'users');
      await t.scrollUntilVisible(
        find.text('Todavía no hay acreditaciones registradas.'),
        200,
      );
      expect(
        find.text('Todavía no hay acreditaciones registradas.'),
        findsOneWidget,
      );
    },
  );

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('Filtros de usuarios a ${size.width}', (t) async {
      await open(
        t,
        size,
        AdministrationScreen(
          client: FakeVerificationClient(),
          access: const AccountAccess(
            role: AccountRole.superadmin,
            status: UniversityStatus.approved,
            suspended: false,
          ),
          uid: 'reviewer',
          logout: const Text('Salir'),
          onDating: () {},
          initialPage: 'users',
        ),
      );
      final card = find.widgetWithText(ExpansionTile, 'Filtros y orden');
      Finder label(String text) =>
          find.descendant(of: card, matching: find.text(text));
      final role = label('Rol'), status = label('Acreditación / cuenta');
      expect(role, findsOneWidget);
      expect(status, findsOneWidget);
      expect(label('Carrera'), findsOneWidget);
      if (size.width < 600) {
        expect(t.getTopLeft(role).dx, t.getTopLeft(status).dx);
        expect(t.getTopLeft(status).dy, greaterThan(t.getTopLeft(role).dy));
      } else {
        expect(t.getTopLeft(role).dy, t.getTopLeft(status).dy);
        expect(t.getTopLeft(status).dx, greaterThan(t.getTopLeft(role).dx));
      }
      final fields = find.descendant(
        of: card,
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await t.tap(fields.at(1));
      await t.pumpAndSettle();
      await t.tap(find.text('Rechazados').last);
      await t.pumpAndSettle();
      final list = find
          .ancestor(of: card, matching: find.byType(Scrollable))
          .first;
      await t.scrollUntilVisible(
        find.text('No hay coincidencias'),
        160,
        scrollable: list,
      );
      expect(find.text('No hay coincidencias'), findsOneWidget);
      final clear = find.text('Limpiar filtros');
      await t.ensureVisible(clear);
      await t.tap(clear);
      await t.pumpAndSettle();
      expect(find.text('No hay coincidencias'), findsNothing);
      final refresh = find.text('Actualizar');
      await t.ensureVisible(refresh);
      await t.tap(refresh);
      await t.pumpAndSettle();
      expect(find.text('Persona Ficticia'), findsOneWidget);
      final heading = find.text('Filtros y orden');
      Scrollable.of(t.element(heading)).position.jumpTo(0);
      await t.pumpAndSettle();
      await t.tap(heading);
      await t.pumpAndSettle();
      expect(role, findsNothing);
      await t.tap(heading);
      await t.pumpAndSettle();
      expect(role, findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Expediente administrativo a ${size.width}', (t) async {
      final api = _DossierFixture();
      await open(
        t,
        size,
        AdministrationScreen(
          client: api,
          access: const AccountAccess(
            role: AccountRole.superadmin,
            status: UniversityStatus.approved,
            suspended: false,
          ),
          uid: 'reviewer',
          logout: const Text('Salir'),
          onDating: () {},
          initialPage: 'users',
        ),
      );
      final detail = find.text('Ver detalle').first;
      if (size.width < 600) {
        await t.tap(find.text('Filtros y orden'));
        await t.pumpAndSettle();
      }
      await t.ensureVisible(detail);
      await t.tap(detail);
      await t.pumpAndSettle();
      expect(find.text('Expediente individual'), findsOneWidget);
      expect(find.text('Persona Ficticia'), findsOneWidget);
      expect(find.text('fixture-private-id'), findsNothing);
      expect(api.calls, contains('dossier'));
      await capture(t, 'dossier-${size.width.toInt()}');
      await t.tap(find.text('Volver a usuarios'));
      await t.pumpAndSettle();
      expect(find.text('Tu comunidad'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(360, 740),
    const Size(390, 844),
    const Size(1280, 600),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('Revisión visual: descubrir completo $label', (t) async {
      final svc = await service();
      await open(
        t,
        size,
        DiscoveryScreen(
          uid: 'ana',
          onPreferences: () {},
          onProfile: () {},
          service: svc,
          photoBuilder: (_) => Image.memory(
            portrait,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
      );
      expect(find.text('Bob, 25'), findsWidgets);
      expect(find.text('Universidad ficticia A'), findsNothing);
      expect(find.byKey(const ValueKey('like-button')), findsOneWidget);
      await capture(t, 'discovery-complete-$label');
    });
    testWidgets('Revisión visual: menú $label', (t) async {
      await open(
        t,
        size,
        AdminShell(
          root: true,
          catalogsAllowed: true,
          selected: 'dashboard',
          onSelected: (_) {},
          logout: const Text('Salir'),
          onDating: () {},
          child: AdminOverview(
            client: _OverviewFixture(),
            onNavigate: (_) {},
            showAudit: true,
          ),
        ),
      );
      await capture(t, 'admin-open-$label');
      final collapse = find.byTooltip('Contraer menú');
      if (collapse.evaluate().isNotEmpty) {
        await t.tap(collapse);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await capture(t, 'admin-closed-$label');
      } else if (size.width < 1050) {
        await t.tap(find.byTooltip('Menú de administración'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await capture(t, 'admin-drawer-$label');
      }
    });
  }
  testWidgets('Perfil incompleto mantiene su bloqueo y no ofrece decisiones', (
    t,
  ) async {
    final svc = await service(complete: false);
    await open(
      t,
      const Size(390, 844),
      DiscoveryScreen(
        uid: 'ana',
        onPreferences: () {},
        onProfile: () {},
        service: svc,
      ),
    );
    expect(
      find.text('Completa y activa tu perfil para descubrir personas.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('like-button')), findsNothing);
    await capture(t, 'discovery-incomplete-390x844');
  });
  for (final small in [false, true]) {
    testWidgets(
      'Menú: todas las secciones y pie fijo ${small ? "móvil" : "escritorio"}',
      (t) async {
        String selected = 'dashboard';
        var opened = 0;
        await open(
          t,
          small ? const Size(360, 540) : const Size(1280, 440),
          StatefulBuilder(
            builder: (context, update) => AdminShell(
              root: true,
              catalogsAllowed: true,
              selected: selected,
              onSelected: (v) => update(() => selected = v),
              logout: const Text('Salir'),
              onDating: () => opened++,
              child: Center(child: Text('Contenido $selected')),
            ),
          ),
        );
        for (final key in [
          'dashboard',
          'users',
          'roles',
          'requests',
          'reports',
          'audit',
          'careers',
          'interests',
          'settings',
        ]) {
          if (small) {
            await t.tap(find.byTooltip('Menú de administración'));
            await t.pumpAndSettle();
          }
          final footerBefore = t.getRect(
            find.byKey(const ValueKey('admin-fixed-footer')),
          );
          if (find.byKey(ValueKey('admin-nav-$key')).evaluate().isEmpty) {
            await t.scrollUntilVisible(
              find.byKey(ValueKey('admin-nav-$key')),
              120,
              scrollable: find.descendant(
                of: find.byKey(const ValueKey('admin-menu-scroll')),
                matching: find.byType(Scrollable),
              ),
            );
          }
          await t.ensureVisible(find.byKey(ValueKey('admin-nav-$key')));
          await t.pumpAndSettle();
          expect(
            t.getRect(find.byKey(const ValueKey('admin-fixed-footer'))),
            footerBefore,
          );
          expect(footerBefore.bottom, lessThanOrEqualTo(small ? 540 : 440));
          await t.tap(find.byKey(ValueKey('admin-nav-$key')));
          await t.pumpAndSettle();
          expect(selected, key);
          expect(find.text('Contenido $key'), findsOneWidget);
          expect(t.takeException(), isNull);
        }
        if (!small) {
          await t.tap(find.byTooltip('Contraer menú'));
          await t.pumpAndSettle();
          expect(
            t.getSize(find.byKey(const ValueKey('admin-sidebar'))).width,
            76,
          );
          await t.tap(find.byTooltip('Expandir menú'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 50));
          expect(t.takeException(), isNull);
          await t.pumpAndSettle();
          expect(
            t.getSize(find.byKey(const ValueKey('admin-sidebar'))).width,
            220,
          );
        } else {
          await t.tap(find.byTooltip('Menú de administración'));
          await t.pumpAndSettle();
        }
        await t.tap(find.byKey(const ValueKey('admin-open-app')));
        await t.pumpAndSettle();
        expect(opened, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('Menú admin conserva secciones permitidas en ancho reducido', (
    t,
  ) async {
    await open(
      t,
      const Size(320, 480),
      AdminShell(
        root: false,
        catalogsAllowed: true,
        selected: 'requests',
        onSelected: (_) {},
        logout: const Text('Salir'),
        onDating: () {},
        child: const SizedBox(),
      ),
    );
    await t.tap(find.byTooltip('Menú de administración'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-nav-roles')), findsNothing);
    expect(find.byKey(const ValueKey('admin-nav-universities')), findsNothing);
    expect(find.byKey(const ValueKey('admin-nav-audit')), findsNothing);
    expect(find.byKey(const ValueKey('admin-nav-requests')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Descubrir: altura reducida y texto ampliado conserva controles',
    (t) async {
      final svc = await service();
      await open(
        t,
        const Size(700, 390),
        MediaQuery(
          data: const MediaQueryData(
            size: Size(700, 390),
            textScaler: TextScaler.linear(1.4),
          ),
          child: DiscoveryScreen(
            uid: 'ana',
            onPreferences: () {},
            onProfile: () {},
            service: svc,
            photoBuilder: (_) => Image.memory(
              portrait,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
        ),
      );
      await t.ensureVisible(find.byKey(const ValueKey('like-button')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('like-button')).hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await capture(t, 'discovery-landscape-text140');
    },
  );
  testWidgets('Descubrir completo dentro de navegación móvil', (t) async {
    final svc = await service();
    await open(
      t,
      const Size(390, 844),
      Scaffold(
        body: DiscoveryScreen(
          uid: 'ana',
          onPreferences: () {},
          onProfile: () {},
          service: svc,
          photoBuilder: (_) => Image.memory(
            portrait,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
        bottomNavigationBar: NavigationBar(
          height: 68,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.rose,
          selectedIndex: 1,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_rounded),
              label: 'Descubrir',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline),
              label: 'Matches',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
    expect(
      t.getRect(find.byKey(const ValueKey('like-button'))).bottom,
      lessThan(t.getRect(find.byType(NavigationBar)).top),
    );
    await capture(t, 'discovery-navigation-390x844');
  });
}

class _OverviewFixture extends FakeVerificationClient {
  @override
  Future<Map<String, dynamic>> administrationSummary() async => {
    'totalUsers': 34,
    'verified': 21,
    'pending': 9,
    'rejected': 4,
    'pendingRequests': 5,
    'reports': 2,
  };

  @override
  Future<Map<String, dynamic>> eventFeed({String? cursor}) async => {
    'items': [
      <String, dynamic>{
        'action': 'verification_approved',
        'actor': {'name': 'Revisora ficticia'},
        'target': {'name': 'Estudiante ficticio'},
        'result': 'success',
        'at': '2026-11-06T14:25:00Z',
      },
    ],
  };
}

class _DossierFixture extends FakeVerificationClient {
  @override
  Future<Map<String, dynamic>> dossierHistory(
    String uid,
    String kind, {
    String? cursor,
  }) async => {
    'items': [
      {
        'person': {'name': 'Contacto ficticio'},
        'active': true,
        'date': '2026-11-06T14:25:00Z',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> administrationDossier(String uid) async {
    calls.add('dossier');
    return {
      'profile': {
        'name': 'Persona Ficticia',
        'email': 'persona@ligo.test',
        'age': 22,
        'university': null,
        'career': 'Sistemas',
        'interests': ['Tecnología'],
        'role': 'user',
        'suspended': false,
        'verificationStatus': 'approved',
        'id': 'fixture-private-id',
      },
      'activity': {
        'sent': 8,
        'received': 3,
        'matches': 2,
        'messages': 15,
        'active': 1,
        'reportsReceived': 1,
        'reportsSent': 0,
        'complete': true,
        'contacts': [
          {'name': 'Contacto ficticio', 'messages': 9},
        ],
      },
      'verifications': [
        {
          'status': 'approved',
          'reviewer': 'Revisora ficticia',
          'date': '2026-11-06T14:25:00Z',
        },
      ],
      'audit': [
        {
          'action': 'verification_approved',
          'actor': 'Revisora ficticia',
          'result': 'success',
          'date': '2026-11-06T14:25:00Z',
        },
      ],
    };
  }
}
