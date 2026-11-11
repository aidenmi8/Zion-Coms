import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Zion dark roles and readable light appearance reach the active theme',
    () {
      final light = mobileAppearanceTheme(Brightness.light, 'neutral');
      final dark = mobileAppearanceTheme(Brightness.dark, 'neutral');
      expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(light.colorScheme.onSurface, const Color(0xFF0A0A0A));
      expect(light.colorScheme.onSurfaceVariant, const Color(0xFF646464));
      expect(light.colorScheme.outline, const Color(0xFFE8E8E8));
      expect(dark.scaffoldBackgroundColor, const Color(0xFF0A0A0A));
      expect(dark.appBarTheme.backgroundColor, const Color(0xFF1C1C1E));
      expect(dark.navigationBarTheme.backgroundColor, const Color(0xFF0A0A0A));
      expect(dark.colorScheme.primary, const Color(0xFF4E7CFF));
      expect(dark.colorScheme.onSurface, const Color(0xFFF5F5F7));
      expect(dark.colorScheme.onSurfaceVariant, const Color(0xFFA6A6A8));
      expect(dark.textTheme.bodyMedium?.fontFamily, 'Inter');
    },
  );

  for (final brightness in Brightness.values) {
    test('links, mentions and control labels are readable in $brightness', () {
      final theme = mobileAppearanceTheme(brightness, 'neutral');
      final colors = theme.colorScheme;
      for (final pair in [
        (colors.primary, receivedMessageSurface(brightness)),
        (colors.tertiary, receivedMessageSurface(brightness)),
        (colors.primary, colors.surface),
        (colors.tertiary, colors.surface),
        (colors.onPrimary, colors.primary),
        (colors.onTertiary, colors.tertiary),
      ]) {
        final a = pair.$1.computeLuminance();
        final b = pair.$2.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });

    test('chat colors do not recolor controls in $brightness', () {
      final base = mobileAppearanceTheme(brightness, 'neutral');
      for (final accent in accentColors) {
        final theme = mobileAppearanceTheme(brightness, accent.wireValue);
        expect(theme.colorScheme, base.colorScheme);
        final fill = theme.extension<ChatColors>()!.outgoing;
        final foreground = theme.extension<ChatColors>()!.foreground;
        final a = fill.computeLuminance();
        final b = foreground.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });
  }
}
