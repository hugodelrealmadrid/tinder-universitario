import 'dart:async';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:tinder_universitario/widgets/swipe_card.dart';
import 'package:tinder_universitario/widgets/app_ui.dart';
import 'package:tinder_universitario/theme/app_theme.dart';
import 'package:tinder_universitario/features/discovery/discovery_models.dart';
import 'package:tinder_universitario/features/discovery/discovery_screen.dart';
import 'package:tinder_universitario/features/discovery/discovery_service.dart';

const sample = DiscoveryCandidate(
  id: 'fixture_bob',
  firstName: 'Estudiante',
  age: 24,
  gender: 'masculino',
  careerId: 'sistemas',
  mainPhotoUrl: '',
  interestIds: [],
  description: 'Intereses y conexiones dentro del campus.',
  isActive: true,
);

class MemoryDiscovery extends DiscoveryService {
  MemoryDiscovery() : super(firestore: FakeFirebaseFirestore());
  final decisions = <String>[];
  bool fail = false;
  @override
  Future<void> start(String uid) async {}
  @override
  Future<DiscoveryCandidate?> next() async => decisions.isEmpty ? sample : null;
  @override
  Future<bool> decide(String from, String to, String type) async {
    if (fail) throw const DiscoveryException('Sin conexión. Reintenta.');
    decisions.add(type);
    return false;
  }
}

void main() {
  Future<void> open(
    WidgetTester t,
    Widget child, {
    Size size = const Size(390, 844),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: SizedBox(width: 340, child: child)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Widget card(
    Future<bool> Function(bool) onDecision, {
    GlobalKey<SwipeCardState>? key,
  }) => SwipeCard(
    key: key,
    onDecision: onDecision,
    child: Container(
      height: 400,
      color: Colors.white,
      child: const Center(child: Text('Perfil ficticio')),
    ),
  );
  for (final direction in [-1.0, 1.0]) {
    testWidgets(
      'Swipe ${direction > 0 ? "derecha LIKE" : "izquierda PASAR"} decide una vez',
      (t) async {
        final calls = <bool>[];
        await open(
          t,
          card((like) async {
            calls.add(like);
            return true;
          }),
        );
        await t.drag(
          find.byKey(const ValueKey('swipe-card-gesture')),
          Offset(180 * direction, 0),
        );
        await t.pumpAndSettle();
        expect(calls, [direction > 0]);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('Gesto corto vuelve al origen sin decidir', (t) async {
    var calls = 0;
    await open(
      t,
      card((_) async {
        calls++;
        return true;
      }),
    );
    final initial = t.getCenter(find.text('Perfil ficticio'));
    await t.drag(
      find.byKey(const ValueKey('swipe-card-gesture')),
      const Offset(45, 0),
    );
    await t.pumpAndSettle();
    expect(calls, 0);
    expect(t.getCenter(find.text('Perfil ficticio')), initial);
  });
  testWidgets('Gestos y botones concurrentes no duplican decisiones', (
    t,
  ) async {
    final key = GlobalKey<SwipeCardState>();
    final gate = Completer<bool>();
    var calls = 0;
    await open(
      t,
      card((_) {
        calls++;
        return gate.future;
      }, key: key),
    );
    final first = key.currentState!.decide(true);
    await key.currentState!.decide(false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    await key.currentState!.decide(true);
    expect(calls, 1);
    gate.complete(true);
    await first;
    await t.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets(
    'Descubrir: error de red conserva tarjeta y permite reintentar sin duplicar',
    (t) async {
      final service = MemoryDiscovery()..fail = true;
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DiscoveryScreen(
            uid: 'fixture_ana',
            onPreferences: () {},
            onProfile: () {},
            service: service,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('like-button')));
      await t.pumpAndSettle();
      expect(find.text('Sin conexión. Reintenta.'), findsOneWidget);
      expect(find.text('Estudiante, 24'), findsWidgets);
      expect(service.decisions, isEmpty);
      service.fail = false;
      await t.tap(find.byKey(const ValueKey('like-button')));
      await t.pumpAndSettle();
      expect(service.decisions, ['like']);
      expect(find.text('Ya viste los perfiles compatibles'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Descubrir: botón accesible PASAR conserva operación existente', (
    t,
  ) async {
    final service = MemoryDiscovery();
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DiscoveryScreen(
          uid: 'fixture_ana',
          onPreferences: () {},
          onProfile: () {},
          service: service,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pass-button')));
    await t.pumpAndSettle();
    expect(service.decisions, ['pass']);
  });
  testWidgets(
    'Salir durante retorno de gesto corto no deja errores de animación',
    (t) async {
      await open(t, card((_) async => true));
      await t.drag(
        find.byKey(const ValueKey('swipe-card-gesture')),
        const Offset(40, 0),
      );
      await t.pump(const Duration(milliseconds: 30));
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Marca LIGO es vectorial y conserva semántica', (t) async {
    await open(t, const AppMark(size: 88));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(Image), findsNothing);
    expect(find.bySemanticsLabel('LIGO · llama'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test('Contraste de botones fucsia y blanco supera 4.5', () {
    final c = AppColors.wine.computeLuminance();
    expect(1.05 / (c + .05), greaterThan(4.5));
  });
}
