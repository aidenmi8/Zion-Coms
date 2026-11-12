part of '../pairing_page.dart';

// Zion onboarding roles, independent of the user's chat bubble color.
extension _OnboardingColors on BuildContext {
  bool get _onboardingIsDark => Theme.of(this).brightness == Brightness.dark;
  Color get _onboardingInk =>
      _onboardingIsDark ? const Color(0xFFF5F5F7) : colors.onSurface;
  Color get _onboardingMutedInk =>
      _onboardingIsDark ? const Color(0xFFA6A6A8) : colors.onSurfaceVariant;
  Color get _onboardingCtaLabel => const Color(0xFF0A0A0A);
  Color get _onboardingErrorInk => colors.error;
  Color get _onboardingInputSurface => _onboardingIsDark
      ? const Color(0xFF1C1C1E)
      : Colors.white.withValues(alpha: 0.7);

  OutlineInputBorder get _inputBorder => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide(color: _onboardingInk.withValues(alpha: 0.18)),
  );

  ButtonStyle get _onboardingButtonStyle => FilledButton.styleFrom(
    minimumSize: const Size(0, 52),
    padding: const EdgeInsets.symmetric(
      horizontal: Grid.lg,
      vertical: Grid.twelve,
    ),
    backgroundColor: const Color(0xFF4E7CFF),
    foregroundColor: _onboardingCtaLabel,
    disabledBackgroundColor: _onboardingInk.withValues(alpha: 0.38),
    disabledForegroundColor: _onboardingCtaLabel.withValues(alpha: 0.7),
    shape: const StadiumBorder(),
  );

  ButtonStyle get _onboardingSecondaryButtonStyle => TextButton.styleFrom(
    minimumSize: const Size(0, 52),
    padding: const EdgeInsets.symmetric(
      horizontal: Grid.md,
      vertical: Grid.xxs,
    ),
    backgroundColor: _onboardingInk.withValues(alpha: 0.1),
    foregroundColor: _onboardingInk,
    disabledBackgroundColor: _onboardingInk.withValues(alpha: 0.05),
    disabledForegroundColor: _onboardingInk.withValues(alpha: 0.45),
    shape: const StadiumBorder(),
  );
}
