import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';
import 'package:tinder_universitario/features/matches/student_match.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tinder_universitario/main_ligo_staging.dart' as staging;
import 'package:tinder_universitario/features/verification/administration_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('LIGO Android: acceso real al staging y paneles por rol', (
    t,
  ) async {
    await staging.main();
    await FirebaseAuth.instance.signOut();
    await binding.convertFlutterSurfaceToImage();
    Future<void> waitFor(Finder f) async {
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (DateTime.now().isBefore(deadline)) {
        await t.pump(const Duration(milliseconds: 100));
        if (f.evaluate().isNotEmpty) return;
      }
      await binding.takeScreenshot('android-timeout');
      debugPrint(
        'Pantalla al agotar la espera: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((s) => !s.contains('@')).join(' | ')}',
      );
      fail('No apareció $f');
    }

    Future<void> shot(String name) async {
      await t.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot(name);
    }

    await waitFor(find.text('Iniciar sesión'));
    expect(Firebase.app().options.projectId, 'demo-ligo-staging');
    await shot('android-login');
    Future<void> login(String email) async {
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), email);
      await t.enterText(fields.at(1), 'Ligo-staging-2026!');
      await t.ensureVisible(find.text('Iniciar sesión'));
      await t.tap(find.text('Iniciar sesión'));
    }

    await login('ligo_root@ligo.test');
    await waitFor(find.byType(AdministrationScreen));
    await waitFor(find.text('El pulso de tu comunidad'));
    await waitFor(find.text('Usuarios'));
    await shot('android-superadmin');
    await FirebaseAuth.instance.signOut();
    await waitFor(find.text('Iniciar sesión'));
    await login('ligo_admin@ligo.test');
    await waitFor(find.byType(AdministrationScreen));
    await waitFor(find.text('El pulso de tu comunidad'));
    await waitFor(find.text('Usuarios'));
    await shot('android-admin');
    await t.tap(find.byTooltip('Menú de administración'));
    await t.pumpAndSettle();
    expect(find.text('Universidades'), findsNothing);
    expect(find.text('Roles y permisos'), findsNothing);
    expect(find.text('Carreras'), findsOneWidget);
    await shot('android-admin-menu');
    // Cerrar drawer antes de cambiar sesión; ninguna escritura de roles o documentos.
    Navigator.of(t.element(find.byType(Drawer))).pop();
    await t.pumpAndSettle();
    await FirebaseAuth.instance.signOut();
    await waitFor(find.text('Iniciar sesión'));
    await login('ligo_visual_ana@ligo.test');
    await waitFor(find.text('Descubrir personas'));
    await t.ensureVisible(find.text('Descubrir personas'));
    await t.tap(find.text('Descubrir personas'));
    await waitFor(find.byKey(const ValueKey('swipe-card-gesture')));
    await waitFor(
      find.byWidgetPredicate((w) => w is RawImage && w.image != null),
    );
    await shot('android-discovery');
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(const ValueKey('swipe-card-gesture'))),
    );
    await gesture.moveBy(const Offset(105, 0));
    await t.pump();
    await shot('android-swipe-like');
    await gesture.cancel();
    await t.pumpAndSettle();
    // Likes reales de dos cuentas ficticias: mismas operaciones y reglas del producto.
    await t.tap(find.byTooltip('Me gusta · LIKE'));
    await waitFor(find.text('No hay más perfiles compatibles por ahora.'));
    await FirebaseAuth.instance.signOut();
    await waitFor(find.text('Iniciar sesión'));
    await login('ligo_visual_bob@ligo.test');
    await waitFor(find.text('Descubrir personas'));
    await t.ensureVisible(find.text('Descubrir personas'));
    await t.tap(find.text('Descubrir personas'));
    await waitFor(find.byKey(const ValueKey('swipe-card-gesture')));
    await t.tap(find.byTooltip('Me gusta · LIKE'));
    await waitFor(find.text('No hay más perfiles compatibles por ahora.'));
    await t.tap(find.byType(NavigationDestination).at(2));
    await waitFor(find.text('Abrir chat'));
    await t.pump(const Duration(seconds: 2));
    await shot('android-matches');
    await t.tap(find.text('Abrir chat'));
    await waitFor(find.byTooltip('Enviar'));
    final chat = ChatService();
    final matchId = StudentMatch.idFor('ligo_visual_ana', 'ligo_visual_bob');
    await chat.send(
      matchId,
      'ligo_visual_bob',
      '¡Hola! Este es un mensaje ficticio de LIGO.',
    );
    await chat.sendMedia(
      matchId,
      'ligo_visual_bob',
      _audioFixture(),
      'audio',
      'audio/wav',
      durationMs: 1000,
    );
    final image = await rootBundle.load('assets/branding/ligo/campus-hero.png');
    await chat.sendMedia(
      matchId,
      'ligo_visual_bob',
      image.buffer.asUint8List(),
      'image',
      'image/png',
    );
    await waitFor(find.byType(Image));
    await t.pump(const Duration(seconds: 2));
    await shot('android-chat-enviado');
    await t.pageBack();
    await FirebaseAuth.instance.signOut();
    await waitFor(find.text('Iniciar sesión'));
    await login('ligo_visual_ana@ligo.test');
    await waitFor(find.text('Descubrir personas'));
    await t.tap(find.byType(NavigationDestination).at(2));
    await waitFor(find.text('Abrir chat'));
    await t.tap(find.text('Abrir chat'));
    await waitFor(find.textContaining('Cargar audio'));
    await t.ensureVisible(find.textContaining('Cargar audio'));
    await t.tap(find.textContaining('Cargar audio'));
    await waitFor(find.byTooltip('Reproducir audio'));
    await t.pump(const Duration(seconds: 2));
    await shot('android-chat-recibido-audio');
    expect(t.takeException(), isNull);
  });
}

Uint8List _audioFixture() {
  const n = 16000;
  final bytes = Uint8List(44 + n * 2), v = ByteData.sublistView(bytes);
  void text(int p, String s) => bytes.setRange(p, p + s.length, s.codeUnits);
  text(0, 'RIFF');
  v.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVEfmt ');
  v.setUint32(16, 16, Endian.little);
  v.setUint16(20, 1, Endian.little);
  v.setUint16(22, 1, Endian.little);
  v.setUint32(24, 16000, Endian.little);
  v.setUint32(28, 32000, Endian.little);
  v.setUint16(32, 2, Endian.little);
  v.setUint16(34, 16, Endian.little);
  text(36, 'data');
  v.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    v.setInt16(
      44 + i * 2,
      (7000 * math.sin(i * 2 * math.pi * 440 / 16000)).round(),
      Endian.little,
    );
  }
  return bytes;
}
