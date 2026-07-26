import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buzz/shared/theme/theme.dart';

void main() {
  test('migrates the former automatic black accent to Zion violet', () async {
    SharedPreferences.setMockInitialValues({'buzz_accent_color': 8});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [savedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(accentProvider), 9);
    expect(prefs.getInt('buzz_accent_color'), 9);
  });

  test('preserves existing user-selected accent indexes', () async {
    SharedPreferences.setMockInitialValues({'buzz_accent_color': 6});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [savedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(accentProvider), 6);
    expect(prefs.getInt('buzz_accent_color'), 6);
  });
}
