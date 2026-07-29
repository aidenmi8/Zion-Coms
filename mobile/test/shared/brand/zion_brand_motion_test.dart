import 'package:buzz/shared/brand/zion_brand_motion.dart';
import 'package:buzz/shared/brand/zion_brand_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../helpers/widget_helpers.dart';

void main() {
  group('ZionBrandMotion', () {
    test(
      'selects the approved mark and lockup assets by variant and brightness',
      () {
        expect(
          zionBrandMotionAssetFor(
            variant: ZionBrandMotionVariants.loader,
            brightness: Brightness.light,
          ).path,
          ZionBrandAssets.zionMarkSvg,
        );
        expect(
          zionBrandMotionAssetFor(
            variant: ZionBrandMotionVariants.liveness,
            brightness: Brightness.dark,
          ).path,
          ZionBrandAssets.zionMarkSvg,
        );
        expect(
          zionBrandMotionAssetFor(
            variant: ZionBrandMotionVariants.agentEntrance,
            brightness: Brightness.light,
          ).path,
          ZionBrandAssets.zionMarkSvg,
        );
        expect(
          zionBrandMotionAssetFor(
            variant: ZionBrandMotionVariants.onboarding,
            brightness: Brightness.light,
          ).path,
          ZionBrandAssets.sentraLockupDarkSvg,
        );
        expect(
          zionBrandMotionAssetFor(
            variant: ZionBrandMotionVariants.pairing,
            brightness: Brightness.dark,
          ).path,
          ZionBrandAssets.sentraLockupLightSvg,
        );
      },
    );

    testWidgets('renders reduced-motion fallback immediately without looping', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const ZionBrandMotion(
              variant: ZionBrandMotionVariants.loader,
              label: 'Zion loading',
            ),
          ),
        ),
      );

      final motionFinder = find.byType(ZionBrandMotion);
      final fadeTransition = tester.widget<FadeTransition>(
        find.descendant(
          of: motionFinder,
          matching: find.byType(FadeTransition),
        ),
      );
      final scaleTransition = tester.widget<ScaleTransition>(
        find.descendant(
          of: motionFinder,
          matching: find.byType(ScaleTransition),
        ),
      );

      expect(fadeTransition.opacity.value, 0.9);
      expect(scaleTransition.scale.value, 1);
      expect(find.bySemanticsLabel('Zion loading'), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('owns a single accessible label on the wrapper', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(
          child: const ZionBrandMotion(
            variant: ZionBrandMotionVariants.pairing,
            label: 'Zion pairing in progress',
          ),
        ),
      );

      expect(find.bySemanticsLabel('Zion pairing in progress'), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
    });
  });
}
