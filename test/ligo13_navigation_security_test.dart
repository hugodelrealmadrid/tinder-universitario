import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/verification/account_access.dart';
import 'package:tinder_universitario/features/verification/administration_screen.dart';
import 'verification_fixtures.dart';

class _ReadClient extends FakeVerificationClient {
  @override
  Future<Map<String, dynamic>> account(String uid) async {
    calls.add('account:$uid');
    return super.account(uid);
  }

  @override
  Future<List<dynamic>> requests({
    String status = 'pending',
    String? cursor,
  }) async => [];
  @override
  Future<List<Map<String, dynamic>>> identities(List<String> ids) async {
    calls.add('identities');
    return super.identities(ids);
  }
}

void main() {
  const root = AccountAccess(
    role: AccountRole.superadmin,
    status: UniversityStatus.approved,
    suspended: false,
  );
  const admin = AccountAccess(
    role: AccountRole.admin,
    status: UniversityStatus.approved,
    suspended: false,
  );
  Future<void> open(
    WidgetTester t,
    _ReadClient client,
    AccountAccess access, {
    String page = 'audit',
  }) async {
    t.view.physicalSize = const Size(1280, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: AdministrationScreen(
          client: client,
          access: access,
          uid: 'viewer',
          logout: const Text('Salir'),
          onDating: () {},
          initialPage: page,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  _ReadClient fixture() => _ReadClient()
    ..events = [
      {
        'id': 'event',
        'action': 'role_admin',
        'actorId': 'reviewer',
        'targetId': 'student',
        'actor': {'name': 'Revisora ficticia'},
        'target': {'name': 'Estudiante ficticio'},
      },
    ]
    ..rows = [
      {
        'id': 'report',
        'reportedId': 'target',
        'reporterId': 'student',
        'reason': 'spam',
        'status': 'pending',
        'details': 'REPORTE FICTICIO',
      },
    ];
  testWidgets(
    'Navegar Auditoría → Reportes → Auditoría carga cada feed y no mezcla filas',
    (t) async {
      final api = fixture();
      await open(t, api, root);
      expect(find.text('Una historia transparente'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('admin-nav-reports')));
      await t.pumpAndSettle();
      expect(api.calls, contains('reports'));
      expect(find.text('REPORTE FICTICIO'), findsOneWidget);
      expect(find.text('Una historia transparente'), findsNothing);
      await t.tap(find.byKey(const ValueKey('admin-nav-audit')));
      await t.pumpAndSettle();
      expect(api.calls.where((x) => x == 'audit').length, 2);
      expect(find.text('REPORTE FICTICIO'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Revocar superadmin retira inmediatamente el módulo y los datos de auditoría',
    (t) async {
      final api = fixture();
      await open(t, api, root);
      expect(find.textContaining('Revisora ficticia'), findsWidgets);
      await t.pumpWidget(
        MaterialApp(
          home: AdministrationScreen(
            client: api,
            access: admin,
            uid: 'viewer',
            logout: const Text('Salir'),
            onDating: () {},
            initialPage: 'audit',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Una historia transparente'), findsNothing);
      expect(find.textContaining('Revisora ficticia'), findsNothing);
      expect(find.byKey(const ValueKey('admin-nav-roles')), findsNothing);
      expect(api.calls.where((x) => x == 'audit').length, 1);
    },
  );
  testWidgets(
    'Administración provisional conserva moderación sin consultar identidades restringidas',
    (t) async {
      final api = fixture();
      final access = AccountAccess(
        role: AccountRole.superadmin,
        status: UniversityStatus.pending,
        suspended: false,
        provisionalAdminUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      await open(t, api, access, page: 'requests');
      await t.tap(find.byKey(const ValueKey('admin-nav-reports')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Consultar / suspender cuenta'));
      await t.tap(find.text('Consultar / suspender cuenta'));
      await t.pumpAndSettle();
      expect(api.calls, contains('account:target'));
      expect(api.calls, isNot(contains('identities')));
      expect(find.text('Suspender cuenta'), findsOneWidget);
      expect(find.text('Asignar rol de administrador'), findsNothing);
    },
  );
}
