import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/theme/app_theme.dart';
import 'package:tinder_universitario/widgets/app_ui.dart';
import 'package:tinder_universitario/features/auth/auth_form.dart';
import 'package:tinder_universitario/features/auth/auth_service.dart';
import 'package:tinder_universitario/features/chat/chat_screen.dart';
import 'package:tinder_universitario/features/chat/chat_service.dart';
import 'package:tinder_universitario/features/discovery/discovery_models.dart';
import 'package:tinder_universitario/features/discovery/discovery_screen.dart';
import 'package:tinder_universitario/features/discovery/discovery_service.dart';
import 'package:tinder_universitario/features/matches/matches_screen.dart';
import 'package:tinder_universitario/features/matches/matches_service.dart';
import 'package:tinder_universitario/features/preferences/preferences_screen.dart';
import 'package:tinder_universitario/features/preferences/preferences_service.dart';
import 'package:tinder_universitario/features/profile/profile_screen.dart';
import 'package:tinder_universitario/features/profile/profile_service.dart';
import 'package:tinder_universitario/features/safety/safety_dialog.dart';
import 'package:tinder_universitario/features/home/home_screen.dart';
import 'auth_service_test.dart' show LocalAuth;
import 'profile_test.dart' show MemoryPhotos;

const _candidate = DiscoveryCandidate(
  id: 'bob',
  firstName: 'Roberto',
  age: 24,
  gender: 'masculino',
  careerId: 'sistemas',
  mainPhotoUrl: '',
  interestIds: ['musica', 'cine'],
  description:
      'Entre clases, música y planes improvisados. Siempre hay una buena historia por compartir.',
  isActive: true,
);

class _Discovery extends DiscoveryService {
  _Discovery() : super(firestore: FakeFirebaseFirestore()) {
    careerNames['sistemas'] = 'Ingeniería de Sistemas Informáticos';
    interestNames.addAll({'musica': 'Música', 'cine': 'Cine'});
  }
  final decisions = <String>[];
  @override
  Future<void> start(String uid) async {}
  @override
  Future<DiscoveryCandidate?> next() async =>
      decisions.isEmpty ? _candidate : null;
  @override
  Future<bool> decide(String from, String to, String type) async {
    decisions.add(type);
    return false;
  }
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.image_picker_android.ImagePickerApi.retrieveLostResults',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });
  setUpAll(() async {
    // Solo para capturas opcionales: ruta al directorio de fuentes del SDK local.
    const fontDir = String.fromEnvironment('UI_FONT_DIR');
    if (fontDir.isEmpty) return;
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family);
      loader.addFont(
        File(
          '$fontDir/roboto-regular.ttf',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File(
        '$fontDir/materialicons-regular.otf',
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
    await icons.load();
  });
  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(360, 800),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  // Captura opcional local para revisión visual; nunca accede a Firebase real.
  Future<void> capture(WidgetTester tester, String name) async {
    const dir = String.fromEnvironment('UI_CAPTURE_DIR');
    if (dir.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final register in [false, true]) {
    testWidgets(
      '${register ? 'Registro' : 'Login'} a 360: validaciones y teclado sin overflow',
      (tester) async {
        final auth = LocalAuth();
        addTearDown(auth.changes.close);
        await open(
          tester,
          AuthForm(
            service: AuthService(
              auth: auth,
              firestore: FakeFirebaseFirestore(),
            ),
            register: register,
            onSwitch: () {},
          ),
        );
        await capture(tester, register ? 'register' : 'login');
        await tester.ensureVisible(
          find.text(register ? 'Crear cuenta' : 'Iniciar sesión'),
        );
        await tester.tap(
          find.text(register ? 'Crear cuenta' : 'Iniciar sesión'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Escribe un correo válido.'), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.ensureVisible(find.byType(TextFormField).first);
        await tester.tap(find.byType(TextFormField).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(auth.registrations + auth.logins, 0);
      },
    );
  }

  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(412, 915),
    const Size(1280, 900),
  ]) {
    testWidgets('Discovery $size conserva LIKE/PASS sin overflow', (
      tester,
    ) async {
      final service = _Discovery();
      await open(
        tester,
        DiscoveryScreen(
          uid: 'ana',
          onPreferences: () {},
          onProfile: () {},
          service: service,
        ),
        size: size,
      );
      expect(find.text('Roberto, 24'), findsOneWidget);
      expect(
        tester.getSize(find.byType(CandidateView)).width,
        lessThanOrEqualTo(520),
      );
      await capture(tester, 'discovery-${size.width.toInt()}');
      await tester.ensureVisible(find.byKey(const ValueKey('like-button')));
      await tester.tap(find.byKey(const ValueKey('like-button')));
      await tester.pumpAndSettle();
      expect(service.decisions, ['like']);
      expect(
        find.text('No hay más perfiles compatibles por ahora.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Ficha con texto largo y escala 1.5 no recorta descripción', (
    tester,
  ) async {
    await open(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CandidateView(
            candidate: _candidate,
            careerName: 'Ingeniería Mecánica y de Automatización Industrial',
            interests: const [
              'Tecnología',
              'Deportes',
              'Música',
              'Lectura',
              'Cine',
            ],
          ),
        ),
      ),
      scale: 1.5,
    );
    await tester.ensureVisible(find.text(_candidate.description));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Inicio y Discovery a 360 con navegación inferior y acciones visibles',
    (tester) async {
      final auth = LocalAuth();
      addTearDown(auth.changes.close);
      await open(
        tester,
        HomeScreen(
          uid: 'ana',
          service: AuthService(auth: auth, firestore: FakeFirebaseFirestore()),
        ),
      );
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      await capture(tester, 'home');
      await open(
        tester,
        Scaffold(
          body: DiscoveryScreen(
            uid: 'ana',
            onPreferences: () {},
            onProfile: () {},
            service: _Discovery(),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 1,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore),
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
      final like = find.byKey(const ValueKey('like-button'));
      expect(tester.getBottomRight(like).dy, lessThanOrEqualTo(724));
      expect(like.hitTestable(), findsOneWidget);
      await capture(tester, 'discovery-navigation');
    },
  );

  Future<FakeFirebaseFirestore> chatData() async {
    final db = FakeFirebaseFirestore();
    await db.doc('matches/ana.bob').set({
      'users': ['ana', 'bob'],
      'isActive': true,
      'createdAt': Timestamp.fromDate(DateTime(2026)),
    });
    await db.doc('discoveryCards/bob').set({
      'firstName': 'Roberto',
      'age': 24,
      'gender': 'masculino',
      'careerId': 'sistemas',
      'mainPhotoUrl': '',
      'interestIds': ['musica'],
      'description': '',
      'isActive': true,
    });
    await db.doc('careers/sistemas').set({
      'name': 'Ingeniería de Sistemas Informáticos',
      'isActive': true,
    });
    return db;
  }

  testWidgets('Matches a 360 muestra tarjeta y abre chat', (tester) async {
    final db = await chatData();
    await open(
      tester,
      MatchesScreen(
        uid: 'ana',
        service: MatchesService(firestore: db),
        chatService: ChatService(firestore: db),
      ),
    );
    await capture(tester, 'matches');
    await tester.tap(find.byType(MatchTile));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat a 360 con mensajes, teclado y diálogo Unmatch', (
    tester,
  ) async {
    final db = await chatData();
    for (var i = 0; i < 3; i++) {
      await db.doc('matches/ana.bob/messages/m$i').set({
        'senderId': i.isEven ? 'ana' : 'bob',
        'text': i.isEven
            ? '¡Hola! ¿Qué tal estuvo tu día?'
            : 'Muy bien, acabo de salir de clases. ¿Y tú?',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 5, 16, i)),
      });
    }
    await open(
      tester,
      ChatScreen(
        uid: 'ana',
        matchId: 'ana.bob',
        profile: _candidate,
        service: ChatService(firestore: db),
      ),
    );
    await capture(tester, 'chat');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byKey(const ValueKey('chat-draft')));
    await tester.enterText(
      find.byKey(const ValueKey('chat-draft')),
      'Borrador sin enviar',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.tap(find.byKey(const ValueKey('chat-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshacer match'));
    await tester.pumpAndSettle();
    await capture(tester, 'unmatch');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Borrador sin enviar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Perfil a 360: resumen, edición, intereses, fotos y guardar', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/ana').set({
      'firstName': 'Ana',
      'lastName': 'Pérez',
      'email': 'ana@example.test',
      'birthDate': Timestamp.fromDate(DateTime(2002)),
      'gender': 'femenino',
      'careerId': 'sistemas',
      'description': 'Café, libros y buenas conversaciones.',
      'interestIds': ['musica'],
      'photoUrls': <String>[],
      'mainPhotoUrl': null,
      'isActive': false,
    });
    await db.doc('careers/sistemas').set({
      'name': 'Ingeniería de Sistemas Informáticos',
      'isActive': true,
    });
    await db.doc('interests/musica').set({'name': 'Música', 'isActive': true});
    await open(
      tester,
      ProfileScreen(
        uid: 'ana',
        logout: const Text('Cerrar sesión'),
        service: ProfileService(firestore: db, photos: MemoryPhotos()),
      ),
    );
    await capture(tester, 'profile');
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();
    await capture(tester, 'profile-edit');
    await tester.ensureVisible(find.byType(FilterChip));
    await tester.tap(find.byType(FilterChip));
    await tester.ensureVisible(find.text('Fotografías *'));
    await tester.pumpAndSettle();
    await capture(tester, 'photos');
    await tester.ensureVisible(find.text('Guardar perfil'));
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();
    expect((await db.doc('users/ana').get()).data()!['interestIds'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Preferencias a 360 conserva rango 18-100 y validación', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await open(
      tester,
      PreferencesScreen(
        uid: 'ana',
        onBack: () {},
        service: PreferencesService(firestore: db),
      ),
    );
    await capture(tester, 'preferences');
    expect(find.text('18 años'), findsWidgets);
    expect(find.text('100 años'), findsWidgets);
    await tester.ensureVisible(find.text('Guardar preferencias'));
    await tester.tap(find.text('Guardar preferencias'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona una opción.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Seis fotos a 360: cuadrícula, principal y cancelar eliminación',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final urls = List.generate(
        6,
        (i) => 'https://example.invalid/photo$i.jpg',
      );
      await db.doc('users/ana').set({
        'firstName': 'Ana',
        'lastName': 'Pérez',
        'birthDate': Timestamp.fromDate(DateTime(2002)),
        'gender': 'femenino',
        'photoUrls': urls,
        'mainPhotoUrl': urls.first,
        'isActive': false,
      });
      await open(
        tester,
        ProfileScreen(
          uid: 'ana',
          logout: const Text('Cerrar sesión'),
          service: ProfileService(firestore: db, photos: MemoryPhotos()),
        ),
      );
      await tester.ensureVisible(find.text('Fotografías *'));
      await tester.pumpAndSettle();
      await capture(tester, 'photo-grid');
      expect(find.text('Principal'), findsOneWidget);
      final buttons = find.text('Hacer principal');
      await tester.ensureVisible(buttons.first);
      await tester.tap(buttons.first);
      await tester.pumpAndSettle();
      expect(
        (await db.doc('users/ana').get()).data()!['mainPhotoUrl'],
        urls[1],
      );
      await tester.ensureVisible(find.text('Eliminar').first);
      await tester.tap(find.text('Eliminar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect((await db.doc('users/ana').get()).data()!['photoUrls'], urls);
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in SafetyAction.values) {
    testWidgets('Diálogo $action a 360 sin overflow con tema', (tester) async {
      await open(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showSafetyDialog(context, target: 'bob', action: action),
              child: const Text('Abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await capture(tester, action.name);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(SafetyDialog), findsNothing);
    });
  }

  testWidgets('Imagen ausente y error mantienen dimensiones y fallback', (
    tester,
  ) async {
    await open(
      tester,
      const Scaffold(
        body: Column(
          children: [
            SizedBox(width: 150, height: 150, child: AppPhoto(url: '')),
            SizedBox(
              width: 150,
              height: 150,
              child: AppPhoto(url: 'https://example.invalid/photo.jpg'),
            ),
          ],
        ),
      ),
    );
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
