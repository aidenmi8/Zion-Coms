import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('default accent', () {
    test('uses Zion violet on the default Zion Orbit scheme', () {
      final resolved = resolveSchemes(null, ThemeMode.system);
      final accented = applyAccent(resolved.light, defaultAccentIndex);

      expect(defaultSchemeName, 'zion-orbit');
      expect(resolved.forcedMode, ThemeMode.dark);
      expect(accented.primary, const Color(0xFFA78BFA));
    });

    test('uses Zion violet on other dark schemes', () {
      final resolved = resolveSchemes('github-dark', ThemeMode.dark);
      final accented = applyAccent(resolved.dark, defaultAccentIndex);

      expect(resolved.forcedMode, ThemeMode.dark);
      expect(accented.primary, const Color(0xFFA78BFA));
      expect(
        _contrastRatio(accented.primary, accented.surface),
        greaterThanOrEqualTo(3),
      );
    });
  });
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
