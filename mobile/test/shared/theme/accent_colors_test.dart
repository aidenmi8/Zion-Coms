import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buzz/shared/theme/theme.dart';

void main() {
  group('default accent', () {
    test('uses Zion violet on the default Zion Orbit scheme', () {
      final resolved = resolveSchemes(null);

      final accented = applyAccent(resolved.light, defaultAccentIndex);

      expect(defaultSchemeName, 'zion-orbit');
      expect(resolved.forcedMode, ThemeMode.dark);
      expect(accented.primary, const Color(0xFFA78BFA));
    });

    test('uses Zion violet on other dark schemes', () {
      final resolved = resolveSchemes('github-dark');
      final base = resolved.dark;

      final accented = applyAccent(base, defaultAccentIndex);

      expect(resolved.forcedMode, ThemeMode.dark);
      expect(accented.primary, const Color(0xFFA78BFA));
      expect(
        _contrastRatio(accented.primary, accented.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(accented.onPrimary, contrastForeground(accented.primary));
    });
  });
}

double _contrastRatio(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lightest = aLum > bLum ? aLum : bLum;
  final darkest = aLum > bLum ? bLum : aLum;
  return (lightest + 0.05) / (darkest + 0.05);
}
