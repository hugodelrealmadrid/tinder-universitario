import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';
import 'package:tinder_universitario/features/chat/chat_message.dart';
import 'package:tinder_universitario/features/chat/chat_media_widget.dart';
import 'package:tinder_universitario/features/chat/pending_chat_uploads.dart';
import 'chat_media_fixtures.dart';

class MemoryMedia implements ChatMediaStore {
  final files = <String, ChatMediaData>{};
  final reads = <String>[];
  bool failUpload = false, failDelete = false;
  bool failVerify = false;
  final deleted = <String>[];
  Future<void> Function()? afterUpload;
  @override
  Future<void> upload(String path, Uint8List bytes, String mime) async {
    if (failUpload) throw StateError('upload failure');
    files[path] = ChatMediaData(bytes, mime);
    await afterUpload?.call();
  }

  @override
  Future<void> delete(String path) async {
    if (failDelete) throw StateError('cleanup failure');
    deleted.add(path);
    files.remove(path);
  }

  @override
  Future<void> verifyUpload(String path, int size, String mime) async {
    final file = files[path];
    if (failVerify ||
        file == null ||
        file.bytes.length != size ||
        file.contentType != mime) {
      throw StateError('verification failure');
    }
  }

  @override
  Future<ChatMediaData> read(String path) async {
    reads.add(path);
    if (!files.containsKey(path)) throw StateError('missing');
    return files[path]!;
  }
}

class MemoryPendingUploads implements PendingChatUploads {
  final uploads = <String, PendingChatUpload>{};
  bool failAdd = false;
  bool failRemove = false;
  @override
  Future<void> add(PendingChatUpload upload) async {
    if (failAdd) throw StateError('journal unavailable');
    uploads[upload.path] = upload;
  }

  @override
  Future<void> remove(PendingChatUpload upload) async {
    if (failRemove) throw StateError('journal removal failure');
    uploads.remove(upload.path);
  }

  @override
  Future<List<PendingChatUpload>> list(String uid) async =>
      uploads.values.where((v) => v.uid == uid).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore db;
  late MemoryMedia media;
  late ChatService service;
  late Uint8List bytes;
  late MemoryPendingUploads pending;
  setUp(() async {
    db = FakeFirebaseFirestore();
    media = MemoryMedia();
    pending = MemoryPendingUploads();
    bytes = await chatPngFixture();
    service = ChatService(
      firestore: db,
      mediaStore: media,
      pendingUploads: pending,
    );
    await db.doc('matches/ana.bob').set({
      'users': ['ana', 'bob'],
      'isActive': true,
      'createdAt': Timestamp.now(),
    });
  });
  test('Sube primero y publica ruta exacta del mensaje', () async {
    await service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png');
    final row =
        (await db.collection('matches/ana.bob/messages').get()).docs.single;
    expect(row.data()['mediaPath'], 'chat_media/ana.bob/ana/${row.id}');
    expect(media.files.keys, [row.data()['mediaPath']]);
    expect(row.data()['createdAt'], isA<Timestamp>());
  });
  test(
    'Rechaza combinación de tipo MIME, vacío y exceso antes de subir',
    () async {
      for (final input in [
        ('image', 'audio/mpeg', bytes),
        ('audio', 'image/png', bytes),
        ('video', 'video/mp4', bytes),
        ('image', 'image/jpeg', Uint8List(0)),
        ('image', 'image/jpeg', Uint8List(5 * 1024 * 1024 + 1)),
        ('audio', 'audio/mpeg', Uint8List(15 * 1024 * 1024 + 1)),
      ]) {
        await expectLater(
          service.sendMedia('ana.bob', 'ana', input.$3, input.$1, input.$2),
          throwsA(isA<ChatException>()),
        );
      }
      expect(media.files, isEmpty);
    },
  );
  test('Match inactivo o tercero no sube archivos', () async {
    await expectLater(
      service.sendMedia('ana.bob', 'carol', bytes, 'image', 'image/png'),
      throwsA(anything),
    );
    await db.doc('matches/ana.bob').update({
      'isActive': false,
      'closedBy': 'ana',
      'closedAt': Timestamp.now(),
    });
    await expectLater(
      service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png'),
      throwsA(isA<ChatException>()),
    );
    expect(media.files, isEmpty);
  });
  test('Fallo de subida no crea mensaje', () async {
    media.failUpload = true;
    await expectLater(
      service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png'),
      throwsStateError,
    );
    expect(
      (await db.collection('matches/ana.bob/messages').get()).docs,
      isEmpty,
    );
  });
  test('Bloqueo propio impide subir antes de iniciar el registro', () async {
    await db.doc('blocks/ana.bob').set({
      'blockerId': 'ana',
      'blockedId': 'bob',
    });
    await expectLater(
      service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png'),
      throwsA(isA<ChatException>()),
    );
    expect(media.files, isEmpty);
    expect(pending.uploads, isEmpty);
  });
  test(
    'Limpieza fallida conserva registro y una instancia posterior puede reintentar',
    () async {
      final entry = PendingChatUpload(
        'ana.bob',
        'ana',
        'failed-cleanup',
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      await pending.add(entry);
      media.files[entry.path] = ChatMediaData(bytes, 'image/png');
      media.failDelete = true;
      await service.recoverPendingMedia('ana');
      expect(pending.uploads.length, 1);
      expect(media.files.length, 1);
      media.failDelete = false;
      final restarted = ChatService(
        firestore: db,
        mediaStore: media,
        pendingUploads: pending,
      );
      await restarted.recoverPendingMedia('ana');
      expect(pending.uploads, isEmpty);
      expect(media.files, isEmpty);
    },
  );
  test('Objeto no confirmado nunca se publica y se limpia', () async {
    media.failVerify = true;
    await expectLater(
      service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png'),
      throwsStateError,
    );
    expect(
      (await db.collection('matches/ana.bob/messages').get()).docs,
      isEmpty,
    );
    expect(media.files, isEmpty);
    expect(pending.uploads, isEmpty);
  });
  test('Fallo del registro impide subir archivos', () async {
    pending.failAdd = true;
    await expectLater(
      service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png'),
      throwsStateError,
    );
    expect(media.files, isEmpty);
  });
  for (final failRemove in [false, true]) {
    test(
      'Mensaje guardado con respuesta perdida se reconoce sin borrar; registro falla=$failRemove',
      () async {
        pending.failRemove = failRemove;
        media.failVerify = true; // Simular respuesta fallida tras persistencia.
        media.afterUpload = () async {
          final path = media.files.keys.single;
          await db.doc('matches/ana.bob/messages/${path.split('/').last}').set({
            'senderId': 'ana',
            'type': 'image',
            'text': '',
            'mediaPath': path,
            'createdAt': Timestamp.now(),
          });
        };
        await service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png');
        expect(media.files.length, 1);
        expect(media.deleted, isEmpty);
        expect(pending.uploads.length, failRemove ? 1 : 0);
      },
    );
  }
  test(
    'Respuesta ambigua sin lectura de servidor conserva archivo y registro',
    () async {
      media.afterUpload = () async {
        db.securityRules = FakeFirebaseFirestore(
          securityRules:
              'service cloud.firestore { match /databases/{database}/documents { match /{document=**} { allow read, write: if false; } } }',
        ).securityRules;
      };
      await expectLater(
        service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png'),
        throwsA(isA<ChatMediaPendingException>()),
      );
      expect(media.files.length, 1);
      expect(media.deleted, isEmpty);
      expect(pending.uploads.length, 1);
    },
  );
  test(
    'Nueva instancia recupera huérfanos antiguos y conserva publicados y recientes',
    () async {
      final old = DateTime.now().subtract(const Duration(hours: 1));
      final orphan = PendingChatUpload('ana.bob', 'ana', 'orphan', old);
      final published = PendingChatUpload('ana.bob', 'ana', 'published', old);
      final recent = PendingChatUpload(
        'ana.bob',
        'ana',
        'recent',
        DateTime.now(),
      );
      for (final upload in [orphan, published, recent]) {
        await pending.add(upload);
        media.files[upload.path] = ChatMediaData(bytes, 'image/png');
      }
      await db.doc('matches/ana.bob/messages/published').set({
        'senderId': 'ana',
        'mediaPath': published.path,
      });
      final restarted = ChatService(
        firestore: db,
        mediaStore: media,
        pendingUploads: pending,
      );
      await restarted.recoverPendingMedia('ana');
      expect(media.deleted, [orphan.path]);
      expect(media.files.keys, unorderedEquals([published.path, recent.path]));
      expect(pending.uploads.keys, [recent.path]);
    },
  );
  test(
    'Recuperación rechaza registros corruptos y no limpia subidas de otro usuario',
    () async {
      final old = DateTime.now().subtract(const Duration(hours: 1));
      await pending.add(PendingChatUpload('../escape', 'ana', 'm', old));
      await pending.add(PendingChatUpload('ana.bob', 'bob', 'm', old));
      await service.recoverPendingMedia('ana');
      expect(media.deleted, isEmpty);
      expect(pending.uploads.length, 2);
    },
  );
  test(
    'El receptor rechaza archivos dañados antes de entregarlos al widget',
    () async {
      media.files['bad'] = ChatMediaData(
        Uint8List.fromList('<html>falso</html>'.codeUnits),
        'image/png',
      );
      await expectLater(
        service.mediaData('bad', type: 'image'),
        throwsA(isA<ChatException>()),
      );
      media.files['mismatch'] = ChatMediaData(chatWavFixture(), 'audio/wav');
      await expectLater(
        service.mediaData('mismatch', type: 'image'),
        throwsA(isA<ChatException>()),
      );
    },
  );
  for (final failDelete in [false, true]) {
    test(
      'Fallo Firestore limpia sin ocultar error original; delete falla=$failDelete',
      () async {
        media.failDelete = failDelete;
        media.afterUpload = () async {
          db.securityRules = FakeFirebaseFirestore(
            securityRules:
                'service cloud.firestore { match /databases/{database}/documents { match /{document=**} { allow read; allow write: if false; } } }',
          ).securityRules;
        };
        await expectLater(
          service.sendMedia('ana.bob', 'ana', bytes, 'image', 'image/png'),
          throwsA(predicate((e) => e.toString().contains('not allowed'))),
        );
        expect(media.files.length, failDelete ? 1 : 0);
        expect(pending.uploads.length, failDelete ? 1 : 0);
      },
    );
  }
  testWidgets('Retirar mensaje revocado cierra también la imagen abierta', (
    tester,
  ) async {
    media.files['private'] = ChatMediaData(bytes, 'image/png');
    final visible = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, show, _) => show
                ? SizedBox(
                    width: 200,
                    height: 200,
                    child: ChatMediaWidget(
                      path: 'private',
                      type: 'image',
                      service: service,
                    ),
                  )
                : const Text('Revocado'),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Revocado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
  });
  testWidgets(
    'Archivo fallido puede reintentarse y cambio de ruta se vuelve a cargar',
    (tester) async {
      Future<void> show(String path) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatMediaWidget(
                path: path,
                type: 'audio',
                service: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cargar audio'));
        await tester.pumpAndSettle();
      }

      await show('first');
      expect(find.text('Reintentar archivo'), findsOneWidget);
      media.files['first'] = ChatMediaData(chatWavFixture(), 'audio/wav');
      await tester.tap(find.text('Reintentar archivo'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproducir audio'), findsOneWidget);
      await show('second');
      expect(media.reads, ['first', 'first', 'second']);
      expect(find.text('Reintentar archivo'), findsOneWidget);
    },
  );
}
