import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:buzz/features/pairing/pairing_page.dart';
import 'package:buzz/features/pairing/pairing_provider.dart';
import 'package:buzz/shared/brand/zion_brand_motion.dart';
import 'package:buzz/shared/brand/zion_brand_tokens.dart';

import '../../helpers/widget_helpers.dart';

void main() {
  group('PairingPage', () {
    testWidgets('renders the static welcome treatment and unchanged hint text', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );

      final motion = tester.widget<ZionBrandMotion>(find.byType(ZionBrandMotion));

      expect(motion.variant, ZionBrandMotionVariants.onboarding);
      expect(motion.playing, isFalse);
      expect(find.text('Welcome to Zion'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(find.text('or paste pairing code'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('nostrpair://... or buzz://...'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('connect button is below text field, not beside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );

      final textField = tester.getBottomLeft(find.byType(TextField));
      final connectButton = tester.getTopLeft(
        find.widgetWithText(FilledButton, 'Connect'),
      );

      // The connect button should be below the text field.
      expect(connectButton.dy, greaterThan(textField.dy));
    });

    testWidgets('connect button is full width', (tester) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );

      final connectButton = tester.getSize(
        find.widgetWithText(FilledButton, 'Connect'),
      );
      final textField = tester.getSize(find.byType(TextField));

      // Button width should be close to the text field width (both full-width).
      expect(connectButton.width, closeTo(textField.width, 2.0));
    });

    testWidgets('shows error container when pairing fails', (tester) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(
          overrides: [
            pairingProvider.overrideWith(
              () => _ErrorPairingNotifier('Invalid pairing code: bad input'),
            ),
          ],
          child: const PairingPage(),
        ),
      );
      await tester.pump();

      expect(find.text('Invalid pairing code: bad input'), findsOneWidget);
    });

    testWidgets('uses the pairing pulse when connecting', (tester) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(
          overrides: [
            pairingProvider.overrideWith(() => _ConnectingPairingNotifier()),
          ],
          child: const PairingPage(),
        ),
      );
      await tester.pump();

      final motion = tester.widget<ZionBrandMotion>(find.byType(ZionBrandMotion));

      expect(motion.variant, ZionBrandMotionVariants.pairing);
      expect(motion.playing, isTrue);
      expect(find.text('Connecting…'), findsOneWidget);
    });

    testWidgets('uses the loader motion while transferring', (tester) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(
          overrides: [pairingProvider.overrideWith(() => _LoadingPairingNotifier())],
          child: const PairingPage(),
        ),
      );
      await tester.pump();

      final motion = tester.widget<ZionBrandMotion>(find.byType(ZionBrandMotion));

      expect(motion.variant, ZionBrandMotionVariants.loader);
      expect(motion.playing, isTrue);
      expect(find.text('Syncing…'), findsOneWidget);
    });

    testWidgets('text field and buttons disabled when connecting', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(
          overrides: [
            pairingProvider.overrideWith(() => _ConnectingPairingNotifier()),
          ],
          child: const PairingPage(),
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });
  });
}

class _ErrorPairingNotifier extends Notifier<PairingState>
    implements PairingNotifier {
  final String error;
  _ErrorPairingNotifier(this.error);

  @override
  PairingState build() =>
      PairingState(status: PairingStatus.error, errorMessage: error);

  @override
  Future<void> pair(String rawInput) async {}

  @override
  void reset() {}

  @override
  void confirmSas() {}

  @override
  void denySas() {}
}

class _ConnectingPairingNotifier extends Notifier<PairingState>
    implements PairingNotifier {
  @override
  PairingState build() => const PairingState(status: PairingStatus.connecting);

  @override
  Future<void> pair(String rawInput) async {}

  @override
  void reset() {}

  @override
  void confirmSas() {}

  @override
  void denySas() {}
}

class _LoadingPairingNotifier extends Notifier<PairingState>
    implements PairingNotifier {
  @override
  PairingState build() => const PairingState(status: PairingStatus.transferring);

  @override
  Future<void> pair(String rawInput) async {}

  @override
  void reset() {}

  @override
  void confirmSas() {}

  @override
  void denySas() {}
}
