import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:audioplayers/audioplayers.dart' hide Source;
import 'package:tinder_universitario/main_demo_android.dart' as demo;
import 'package:tinder_universitario/features/verification/backend_client.dart';
import 'package:tinder_universitario/features/profile/profile_service.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';

Uint8List wav() {
  const samples = 16000;
  final b = Uint8List(44 + samples * 2), v = ByteData.sublistView(b);
  void text(int p, String s) => b.setRange(p, p + s.length, s.codeUnits);
  text(0, 'RIFF');
  v.setUint32(4, b.length - 8, Endian.little);
  text(8, 'WAVEfmt ');
  v.setUint32(16, 16, Endian.little);
  v.setUint16(20, 1, Endian.little);
  v.setUint16(22, 1, Endian.little);
  v.setUint32(24, 16000, Endian.little);
  v.setUint32(28, 32000, Endian.little);
  v.setUint16(32, 2, Endian.little);
  v.setUint16(34, 16, Endian.little);
  text(36, 'data');
  v.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    v.setInt16(
      44 + i * 2,
      (8000 * sin(i * 2 * pi * 440 / 16000)).round(),
      Endian.little,
    );
  }
  return b;
}

Future<void> waitText(WidgetTester tester, String text) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(text).evaluate().isNotEmpty) return;
  }
  fail('No apareció: $text');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android demo: autenticación, fotografía privada, galería, texto, imagen, audio y permisos',
    (tester) async {
      await demo.main();
      final auth = FirebaseAuth.instance,
          db = FirebaseFirestore.instance,
          client = VerificationClient();
      expect(
        Firebase.apps.every(
          (a) => a.options.projectId == 'demo-tinder-universitario',
        ),
        true,
      );
      expect(
        FirebaseStorage.instance.bucket,
        'demo-tinder-universitario.appspot.com',
      );
      await auth.signInWithEmailAndPassword(
        email: 'ana.manual@demo.test',
        password: 'DemoTinder2026!',
      );
      await waitText(tester, 'Descubrir personas');
      final before = await ProfileService().load('manual_ana'),
          bytes = await client.photoBytes(before.mainPhotoUrl!);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0));
      frame.image.dispose();
      codec.dispose();
      final profiles = ProfileService();
      await profiles.upload('manual_ana', bytes);
      final after = await profiles.load('manual_ana');
      expect(after.photoUrls.length, before.photoUrls.length + 1);
      final added = after.photoUrls.firstWhere(
        (p) => !before.photoUrls.contains(p),
      );
      await profiles.chooseMain('manual_ana', added);
      expect((await profiles.load('manual_ana')).mainPhotoUrl, added);
      await profiles.remove('manual_ana', added);
      expect((await profiles.load('manual_ana')).photoUrls, before.photoUrls);
      final chat = ChatService();
      await chat.send(
        'manual_ana.manual_bob',
        'manual_ana',
        'Prueba Android demo Fase 5 · documento y medios ficticios.',
      );
      await chat.sendMedia(
        'manual_ana.manual_bob',
        'manual_ana',
        bytes,
        'image',
        'image/png',
      );
      await chat.sendMedia(
        'manual_ana.manual_bob',
        'manual_ana',
        wav(),
        'audio',
        'audio/wav',
        durationMs: 1000,
      );
      final messages = await db
          .collection('matches/manual_ana.manual_bob/messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      final audio = messages.docs.single.data();
      expect(audio['type'], 'audio');
      final received = await chat.mediaData(
        audio['mediaPath'] as String,
        type: 'audio',
      );
      expect(received.bytes.length, 32044);
      final player = AudioPlayer();
      try {
        await player.play(BytesSource(received.bytes, mimeType: 'audio/wav'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(await player.getDuration(), isNotNull);
        expect((await player.getDuration())!.inMilliseconds, greaterThan(500));
      } finally {
        await player.dispose();
      }
      await expectLater(
        FirebaseStorage.instance.ref(before.mainPhotoUrl!).getDownloadURL(),
        throwsA(isA<FirebaseException>()),
      );
      await auth.signOut();
      await auth.signInWithEmailAndPassword(
        email: 'pendiente@demo.test',
        password: 'DemoTinder2026!',
      );
      await waitText(tester, 'Verificación universitaria');
      expect(find.text('Descubrir personas'), findsNothing);
      await expectLater(
        client.photoBytes(before.mainPhotoUrl!),
        throwsA(isA<VerificationFailure>()),
      );
      await expectLater(
        db
            .collection('discoveryIndex')
            .where('isActive', isEqualTo: true)
            .limit(25)
            .get(const GetOptions(source: Source.server)),
        throwsA(isA<FirebaseException>()),
      );
      await expectLater(
        db.doc('users/demo_pending').update({'datingAllowed': true}),
        throwsA(isA<FirebaseException>()),
      );
      await auth.signOut();
      client.close();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
