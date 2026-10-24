import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/app_environment.dart';

void main() {
  AppEnvironment config({
    bool demoFlag = false,
    String name = 'production',
    String project = 'tinder-hosted-test',
    String backend = 'https://api.test/',
  }) => AppEnvironment(
    demoFlag: demoFlag,
    name: name,
    projectId: project,
    bucket: 'tinder-hosted-test.firebasestorage.app',
    apiKey: 'AIza00000000000000000000000000000000000',
    appId: '1:123:android:test',
    senderId: '123',
    authDomain: 'tinder-hosted-test.firebaseapp.com',
    backend: backend,
  );
  test(
    'El arranque alojado sin configuración falla antes de inicializar Firebase',
    () {
      expect(
        () => AppEnvironment.configured(web: true).validate(),
        throwsStateError,
      );
    },
  );
  test('Configuración explícita para desarrollo y producción', () {
    expect(config().options.projectId, 'tinder-hosted-test');
    expect(config(name: 'development').options.projectId, 'tinder-hosted-test');
  });
  test('Rechaza demo, URLs locales y endpoints ambiguos', () {
    expect(() => config(demoFlag: true).validate(), throwsStateError);
    expect(() => config(name: 'demo').validate(), throwsStateError);
    expect(() => config(project: 'demo-tinder').validate(), throwsStateError);
    for (final url in [
      'http://localhost:7360/',
      'https://localhost/',
      'https://api.test/api',
      'https://api.test/?token=x',
      'https://user:pass@api.test/',
      'https://api.example/',
      '',
    ]) {
      expect(() => config(backend: url).validate(), throwsStateError);
    }
  });
}
