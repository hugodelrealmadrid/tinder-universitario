import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:tinder_universitario/features/chat/pending_chat_uploads.dart';

final class MemoryPreferences extends SharedPreferencesAsyncPlatform {
  final values = <String, String>{};
  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    values[key] = value;
  }

  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async => values[key];
  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => values.keys
      .where((key) => parameters.filter.allowList?.contains(key) ?? true)
      .toSet();
  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    values.removeWhere(
      (key, _) => parameters.filter.allowList?.contains(key) ?? true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MemoryPreferences backend;
  SharedPreferencesAsyncPlatform? previous;
  setUp(() {
    previous = SharedPreferencesAsyncPlatform.instance;
    backend = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = backend;
  });
  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = previous;
  });
  test(
    'Registro serializado sobrevive a una nueva instancia y separa usuario/proyecto',
    () async {
      final journal = PreferencesPendingChatUploads('demo:bucket');
      final entry = PendingChatUpload(
        'ana.bob',
        'ana',
        'm1',
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      await journal.add(entry);
      final reloaded = PreferencesPendingChatUploads('demo:bucket');
      expect((await reloaded.list('ana')).single.path, entry.path);
      expect((await reloaded.list('ana')).single.createdAt, entry.createdAt);
      expect(await reloaded.list('bob'), isEmpty);
      expect(
        await PreferencesPendingChatUploads('other:bucket').list('ana'),
        isEmpty,
      );
      expect(backend.values.values.single.contains('token'), isFalse);
      await reloaded.remove(entry);
      expect(await journal.list('ana'), isEmpty);
    },
  );
  test(
    'Registros corruptos, rutas externas y claves manipuladas no activan limpieza',
    () async {
      backend.values['chat_pending:demo:bucket:ana:broken'] = 'invalid json';
      backend.values['chat_pending:demo:bucket:ana:external'] = jsonEncode({
        'matchId': '../escape',
        'uid': 'ana',
        'messageId': 'external',
        'createdAt': 0,
      });
      backend.values['chat_pending:demo:bucket:ana:wrong-key'] = jsonEncode({
        'matchId': 'ana.bob',
        'uid': 'ana',
        'messageId': 'other',
        'createdAt': 0,
      });
      expect(
        await PreferencesPendingChatUploads('demo:bucket').list('ana'),
        isEmpty,
      );
    },
  );
  test(
    'Entradas concurrentes no se pierden por actualizar un índice compartido',
    () async {
      final journal = PreferencesPendingChatUploads('demo:bucket');
      await Future.wait(
        List.generate(
          10,
          (i) => journal.add(
            PendingChatUpload('ana.bob', 'ana', 'm$i', DateTime.now()),
          ),
        ),
      );
      expect(await journal.list('ana'), hasLength(10));
    },
  );
}
