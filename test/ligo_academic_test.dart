import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';
import 'package:tinder_universitario/features/preferences/preferences_service.dart';
import 'package:tinder_universitario/features/academics/catalog_admin_screen.dart';
import 'package:tinder_universitario/features/profile/profile_service.dart';
import 'package:tinder_universitario/features/profile/student_profile.dart';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';
import 'package:tinder_universitario/features/verification/account_access.dart';
import 'package:tinder_universitario/features/verification/backend_client.dart';
import 'auth_service_test.dart' show LocalAuth, TestUser;
import 'profile_test.dart' show MemoryPhotos;
import 'verification_fixtures.dart' show FakeVerificationClient;

class CatalogApi extends FakeVerificationClient {
  final saved = <Map<String, dynamic>>[];
  VerificationFailure? failure;
  Future<void>? wait;
  @override
  Future<Map<String, dynamic>> catalogs(String kind, {String? cursor}) async {
    calls.add('catalog:$kind');
    return {'items': rows, 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> saveCatalog(
    String kind,
    Map<String, dynamic> data, {
    String? id,
    int? expectedRevision,
    required String requestId,
  }) async {
    saved.add({
      'kind': kind,
      'data': data,
      'id': id,
      'revision': expectedRevision,
      'requestId': requestId,
    });
    await wait;
    if (failure != null) throw failure!;
    return {'id': id ?? 'new', 'revision': 2};
  }
}

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
void main() {
  late FakeFirebaseFirestore db;
  late LocalAuth auth;
  late AuthService service;
  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = LocalAuth();
    service = AuthService(auth: auth, firestore: db);
    await db.doc('universities/uni').set({
      'name': 'Universidad ficticia',
      'isActive': true,
      'countryCode': 'BO',
      'city': 'Ciudad ficticia',
    });
    await db.doc('universities/other').set({
      'name': 'Otra universidad',
      'isActive': true,
      'countryCode': 'PE',
      'city': 'Lima',
    });
    await db.doc('careers/career').set({
      'name': 'Carrera A',
      'universityId': 'uni',
      'isActive': true,
    });
    await db.doc('careers/other').set({
      'name': 'Carrera B',
      'universityId': 'other',
      'isActive': true,
    });
    await db.doc('platformSettings/academic').set({
      'multiUniversityEnabled': true,
    });
  });
  tearDown(() async {
    await auth.changes.close();
    service.dispose();
  });
  test(
    'Registro sin universidad incluso con la política histórica activa',
    () async {
      await service.register(
        'ana@example.com',
        'fixture-password',
        DateTime(2000),
      );
      expect(await service.ensureProfile(TestUser()), true);
      final p = (await db.doc('users/ana').get()).data()!;
      expect(p.containsKey('universityId'), false);
      expect(p['careerId'], isNull);
      expect(p['isActive'], false);
      expect(p['role'], 'user');
      expect(p.containsKey('datingAllowed'), false);
    },
  );
  test('Registro rechaza a menores y conserva el perfil histórico', () async {
    await expectLater(
      service.ensureProfile(TestUser(), birthDate: DateTime.now()),
      throwsArgumentError,
    );
    final data = {
      'firstName': 'Histórico',
      'careerId': 'legacy',
      'universityId': 'uni',
    };
    await db.doc('users/ana').set(data);
    expect(await service.ensureProfile(TestUser()), true);
    expect((await db.doc('users/ana').get()).data(), data);
  });
  test(
    'Preferencias ignoran el filtro histórico y lo conservan al guardar',
    () async {
      final stored = {
        'minAge': 18,
        'maxAge': 100,
        'preferredGender': 'ambos',
        'universityIds': ['uni'],
        'careerIds': ['career'],
      };
      await db.doc('preferences/ana').set(stored);
      final preferences = PreferencesService(firestore: db);
      final value = (await preferences.load('ana'))!;
      expect(value.acceptsCareer('career'), true);
      expect(value.acceptsCareer('other'), false);
      expect(value.toFirestore().containsKey('universityIds'), false);
      await preferences.save(
        'ana',
        const DiscoveryPreferences(
          minAge: 21,
          maxAge: 35,
          preferredGender: 'ambos',
        ),
      );
      final saved = (await db.doc('preferences/ana').get()).data()!;
      expect(saved['universityIds'], ['uni']);
      expect(saved['careerIds'], isEmpty);
      expect(saved['minAge'], 21);
    },
  );
  test(
    'Guardar con carrera e interés inactivos conservados no desactiva ni reasigna el perfil',
    () async {
      await db.doc('careers/legacy').set({
        'name': 'Carrera histórica',
        'isActive': false,
      });
      await db.doc('interests/legacy').set({
        'name': 'Interés histórico',
        'isActive': false,
      });
      final p = StudentProfile(
        firstName: 'Ana',
        lastName: 'Ficticia',
        birthDate: DateTime(2000),
        gender: 'femenino',
        careerId: 'legacy',
        interestIds: ['legacy'],
        photoUrls: ['profile_photos/ana/foto'],
        mainPhotoUrl: 'profile_photos/ana/foto',
        isActive: true,
      );
      await db.doc('users/ana').set({
        ...p.editableFields(),
        'photoUrls': p.photoUrls,
        'mainPhotoUrl': p.mainPhotoUrl,
        'isActive': true,
        'role': 'user',
        'email': 'ana@example.com',
        'createdAt': Timestamp.fromDate(DateTime(2020)),
      });
      final profiles = ProfileService(firestore: db, photos: MemoryPhotos());
      final saved = await profiles.save('ana', p, activate: true);
      expect(saved.isActive, true);
      expect(saved.careerId, 'legacy');
      expect(saved.interestIds, ['legacy']);
      expect(
        (await db.doc('users/ana').get()).data()!.containsKey('universityId'),
        false,
      );
      final catalog = await profiles.catalog(
        'careers',
        retainedIds: ['legacy'],
      );
      expect(
        catalog.map((x) => x.id),
        unorderedEquals(['career', 'other', 'legacy']),
      );
    },
  );
  testWidgets(
    'Superadmin no abre gestión de universidades ni consulta el endpoint',
    (t) async {
      final api = CatalogApi();
      await t.pumpWidget(
        MaterialApp(
          home: CatalogAdminScreen(
            client: api,
            access: root,
            kind: 'universities',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Acceso administrativo no autorizado.'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );
  testWidgets(
    'Admin crea interés mediante backend y error de duplicado permanece visible',
    (t) async {
      final api = CatalogApi()
        ..failure = const VerificationFailure('duplicate-catalog');
      await t.pumpWidget(
        MaterialApp(
          home: CatalogAdminScreen(
            client: api,
            access: admin,
            kind: 'interests',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Crear elemento'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Interés ficticio');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(api.saved.single['kind'], 'interests');
      expect(find.textContaining('Ya existe'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Superadmin crea una carrera general', (t) async {
    final api = CatalogApi();
    await t.pumpWidget(
      MaterialApp(
        home: CatalogAdminScreen(client: api, access: root, kind: 'careers'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Crear elemento'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Carrera nueva');
    expect(find.text('Universidad'), findsNothing);
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(api.saved.single['data'], {
      'name': 'Carrera nueva',
      'isActive': true,
    });
    expect(api.saved.single['id'], null);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Desactivar conserva referencias y envía revisión al servidor', (
    t,
  ) async {
    final api = CatalogApi()
      ..rows.add({
        'id': 'interest',
        'name': 'Interés',
        'isActive': true,
        'revision': 3,
      });
    await t.pumpWidget(
      MaterialApp(
        home: CatalogAdminScreen(client: api, access: admin, kind: 'interests'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Desactivar'));
    await t.pumpAndSettle();
    expect(find.textContaining('No suspenderá cuentas'), findsOneWidget);
    await t.tap(find.text('Confirmar'));
    await t.pumpAndSettle();
    expect(api.saved.single['revision'], 3);
    expect((api.saved.single['data'] as Map)['isActive'], false);
  });
  testWidgets(
    'Doble envío no duplica operaciones y espera respuesta del backend',
    (t) async {
      final done = Completer<void>();
      final api = CatalogApi()..wait = done.future;
      await t.pumpWidget(
        MaterialApp(
          home: CatalogAdminScreen(
            client: api,
            access: admin,
            kind: 'interests',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Crear elemento'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Interés ficticio');
      await t.tap(find.text('Guardar'));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'))
            .onPressed,
        null,
      );
      expect(api.saved.length, 1);
      done.complete();
      await t.pumpAndSettle();
    },
  );
  for (final size in [const Size(360, 740), const Size(1280, 900)]) {
    testWidgets('CRUD adaptable a $size sin overflow', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = CatalogApi()
        ..rows.add({
          'id': 'long',
          'name':
              'Nombre académico extenso para comprobar la adaptación del formulario',
          'isActive': true,
          'revision': 1,
        });
      await t.pumpWidget(
        MaterialApp(
          home: CatalogAdminScreen(client: api, access: root, kind: 'careers'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Editar'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
