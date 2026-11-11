import 'package:flutter/material.dart';

// Zion presentation colors; protocol and community theme preferences stay intact.
// Light mode remains available; dark mode uses the Sentra charcoal/silver/blue palette.
const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF262626),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF0F0F0),
  onPrimaryContainer: Color(0xFF0A0A0A),
  secondary: Color(0xFF646464),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF0F0F0),
  onSecondaryContainer: Color(0xFF0A0A0A),
  tertiary: Color(0xFF0B5FA8),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFE6F4FE),
  onTertiaryContainer: Color(0xFF113264),
  error: Color(0xFFCE2C31),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFEEBEC),
  onErrorContainer: Color(0xFF641723),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF0A0A0A),
  onSurfaceVariant: Color(0xFF646464),
  outline: Color(0xFFE8E8E8),
  outlineVariant: Color(0xFFE8E8E8),
  inverseSurface: Color(0xFF262626),
  onInverseSurface: Color(0xFFFFFFFF),
  inversePrimary: Color(0xFFE5E5E5),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF5F5F6),
  surfaceContainer: Color(0xFFF0F0F0),
  surfaceContainerHigh: Color(0xFFE8E8E8),
  surfaceContainerHighest: Color(0xFFF5F5F6),
  surfaceTint: Colors.transparent,
);

const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF4E7CFF),
  onPrimary: Color(0xFF0A0A0A),
  primaryContainer: Color(0xFF1C1C1E),
  onPrimaryContainer: Color(0xFFF5F5F7),
  secondary: Color(0xFFA6A6A8),
  onSecondary: Color(0xFF0A0A0A),
  secondaryContainer: Color(0xFF1C1C1E),
  onSecondaryContainer: Color(0xFFF5F5F7),
  tertiary: Color(0xFF4E7CFF),
  onTertiary: Color(0xFF0A0A0A),
  tertiaryContainer: Color(0xFF1C1C1E),
  onTertiaryContainer: Color(0xFFA6A6A8),
  error: Color(0xFFFF9592),
  onError: Color(0xFF191111),
  errorContainer: Color(0xFF3B1219),
  onErrorContainer: Color(0xFFFFD1D9),
  surface: Color(0xFF0A0A0A),
  onSurface: Color(0xFFF5F5F7),
  onSurfaceVariant: Color(0xFFA6A6A8),
  outline: Color(0x66A6A6A8),
  outlineVariant: Color(0x66A6A6A8),
  inverseSurface: Color(0xFFF5F5F7),
  onInverseSurface: Color(0xFF0A0A0A),
  inversePrimary: Color(0xFF0A0A0A),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceContainerLowest: Color(0xFF0A0A0A),
  surfaceContainerLow: Color(0xFF1C1C1E),
  surfaceContainer: Color(0xFF1C1C1E),
  surfaceContainerHigh: Color(0xFF2C2C2E),
  surfaceContainerHighest: Color(0xFF2C2C2E),
  surfaceTint: Colors.transparent,
);

/// Compute a contrast-safe foreground color for a given background.
/// Uses WCAG contrast ratio (higher ratio wins) instead of a simple luminance
/// cutoff, so colors like Blue (#3B82F6) correctly get black text (5.7:1)
/// rather than white (3.7:1).
Color contrastForeground(Color bg) {
  final lum = bg.computeLuminance();
  // WCAG contrast ratio: (L1 + 0.05) / (L2 + 0.05), L1 >= L2
  final contrastWithBlack = (lum + 0.05) / 0.05; // black luminance = 0
  final contrastWithWhite = 1.05 / (lum + 0.05); // white luminance = 1
  return contrastWithBlack >= contrastWithWhite
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
}
