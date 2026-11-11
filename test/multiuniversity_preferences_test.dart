import 'package:flutter_test/flutter_test.dart';
import 'package:tinder_universitario/features/preferences/discovery_preferences.dart';

void main() {
  test('Preferencias académicas respetan históricos y combinan intereses', () {
    final legacy = DiscoveryPreferences.fromMap({
      'minAge': 18,
      'maxAge': 100,
      'preferredGender': 'ambos',
      'universityIds': ['legacy_value'],
    });
    expect(legacy.acceptsAffiliation(null, null, []), isTrue);
    const mine = DiscoveryPreferences(
      minAge: 18,
      maxAge: 30,
      preferredGender: 'ambos',
      universityMode: 'mine',
      interestIds: ['lectura'],
    );
    expect(mine.acceptsAffiliation('umss', 'umss', ['lectura']), isTrue);
    expect(mine.acceptsAffiliation('umss', 'ucb', ['lectura']), isFalse);
    expect(mine.acceptsAffiliation(null, null, ['lectura']), isFalse);
    expect(mine.acceptsAffiliation('umss', 'umss', []), isFalse);
    const selected = DiscoveryPreferences(
      minAge: 20,
      maxAge: 23,
      preferredGender: 'ambos',
      universityMode: 'selected',
      universityIds: ['ucb', 'univalle'],
      careerIds: ['sistemas'],
      interestIds: ['lectura'],
    );
    expect(selected.isValid, isTrue);
    expect(selected.acceptsAffiliation('umss', 'ucb', ['lectura']), isTrue);
    expect(selected.acceptsAffiliation('umss', null, ['lectura']), isFalse);
    expect(selected.acceptsCareer('sistemas'), isTrue);
    expect(selected.acceptsAge(gender: 'masculino', age: 24), isFalse);
    expect(selected.toFirestore()['universityIds'], ['ucb', 'univalle']);
  });
}
