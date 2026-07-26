import 'package:buzz/shared/branding/sentra_branding.dart';
import 'package:buzz/shared/branding/sentra_liquid_orbit.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'uses the white wordmark and static final state for Reduce Motion',
    (tester) async {
      await tester.pumpWidget(
        _brandingHarness(brightness: Brightness.dark, disableAnimations: true),
      );

      expect(find.bySemanticsLabel('Sentra'), findsOneWidget);
      final wordmark = tester.widget<Image>(
        find.descendant(
          of: find.bySemanticsLabel('Sentra'),
          matching: find.byType(Image),
        ),
      );
      expect(wordmark.image, const AssetImage(sentraWhiteWordmarkAsset));
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uses the black wordmark on light surfaces', (tester) async {
    await tester.pumpWidget(_brandingHarness(brightness: Brightness.light));

    final wordmark = tester.widget<Image>(find.byType(Image));
    expect(wordmark.image, const AssetImage(sentraBlackWordmarkAsset));
  });
}

Widget _brandingHarness({
  required Brightness brightness,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: const Scaffold(body: Center(child: SentraLiquidOrbit())),
  ),
);
