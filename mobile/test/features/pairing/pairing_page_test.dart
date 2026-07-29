import 'package:buzz/features/pairing/pairing_page.dart';
import 'package:buzz/features/pairing/pairing_provider.dart';
import 'package:buzz/shared/brand/zion_brand_motion.dart';
import 'package:buzz/shared/brand/zion_brand_tokens.dart';
import 'package:buzz/shared/branding/sentra_liquid_orbit.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/widget_helpers.dart';

void main() {
  group('PairingPage', () {
    testWidgets('renders Zion liquid-orbit branding and progressive actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );

      expect(find.byType(SentraLiquidOrbit), findsOneWidget);
      expect(find.byType(ZionBrandMotion), findsNothing);
      expect(find.bySemanticsLabel('Zion welcome mark'), findsOneWidget);
      expect(find.text('Welcome to Zion'), findsOneWidget);
      expect(find.text('Scan a QR code'), findsOneWidget);
      expect(find.text('Use pairing code'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('uses compact desktop-style onboarding actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );

      final scanButton = tester.getSize(
        find.widgetWithText(FilledButton, 'Scan a QR code'),
      );
      final pairingCodeButton = tester.getSize(
        find.widgetWithText(TextButton, 'Use pairing code'),
      );

      expect(scanButton.width, lessThan(440));
      expect(pairingCodeButton.width, lessThan(440));
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('uses dark status-bar icons on the onboarding surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );

      final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byKey(const Key('pairing-onboarding-system-overlay')),
      );

      expect(overlay.value.statusBarIconBrightness, Brightness.dark);
      expect(overlay.value.statusBarColor, Colors.transparent);
    });

    testWidgets('uses light status-bar icons for dark-theme SAS verification', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingProvider.overrideWith(() => _ConfirmingSasPairingNotifier()),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const PairingPage()),
        ),
      );

      final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byKey(const Key('pairing-sas-system-overlay')),
      );

      expect(overlay.value.statusBarIconBrightness, Brightness.light);
      expect(overlay.value.statusBarColor, Colors.transparent);
      expect(find.text('Verify Security Code'), findsOneWidget);
    });

    testWidgets('reveals pairing code field and connect action', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );

      await _expandPairingCode(tester);

      expect(find.text('Hide pairing code'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('connect button is below text field, not beside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );
      await _expandPairingCode(tester);

      final textField = tester.getBottomLeft(find.byType(TextField));
      final connectButton = tester.getTopLeft(
        find.widgetWithText(FilledButton, 'Connect'),
      );

      expect(connectButton.dy, greaterThan(textField.dy));
    });

    testWidgets('connect button is full width', (tester) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );
      await _expandPairingCode(tester);

      final connectButton = tester.getSize(
        find.widgetWithText(FilledButton, 'Connect'),
      );
      final textField = tester.getSize(find.byType(TextField));

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

      final motion = tester.widget<ZionBrandMotion>(
        find.byType(ZionBrandMotion),
      );

      expect(motion.variant, ZionBrandMotionVariants.pairing);
      expect(motion.playing, isTrue);
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Connect'), findsNothing);
    });

    testWidgets('uses the loader motion while transferring', (tester) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(
          overrides: [
            pairingProvider.overrideWith(() => _LoadingPairingNotifier()),
          ],
          child: const PairingPage(),
        ),
      );
      await tester.pump();

      final motion = tester.widget<ZionBrandMotion>(
        find.byType(ZionBrandMotion),
      );

      expect(motion.variant, ZionBrandMotionVariants.loader);
      expect(motion.playing, isTrue);
      expect(find.text('Syncing…'), findsOneWidget);
    });

    testWidgets(
      'parent status region owns semantics and motion stays decorative',
      (tester) async {
        await tester.pumpWidget(
          WidgetHelpers.testable(
            overrides: [
              pairingProvider.overrideWith(() => _ConnectingPairingNotifier()),
            ],
            child: const PairingPage(),
          ),
        );
        await tester.pump();

        final statusRegion = tester.widget<Semantics>(
          find.byKey(const ValueKey('pairing-brand-status-region')),
        );
        final motion = tester.widget<ZionBrandMotion>(
          find.byType(ZionBrandMotion),
        );

        expect(statusRegion.properties.label, 'Zion pairing in progress');
        expect(statusRegion.properties.liveRegion, isTrue);
        expect(motion.label, isNull);
        expect(
          find.descendant(
            of: find.byType(ZionBrandMotion),
            matching: find.byType(ExcludeSemantics),
          ),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel('Zion pairing in progress'),
          findsOneWidget,
        );
      },
    );

    testWidgets('pairing actions are disabled when connecting', (tester) async {
      await tester.pumpWidget(
        WidgetHelpers.testable(
          overrides: [
            pairingProvider.overrideWith(() => _ConnectingPairingNotifier()),
          ],
          child: const PairingPage(),
        ),
      );
      await tester.pump();

      final scanButton = tester.widget<FilledButton>(find.byType(FilledButton));
      final pairingCodeButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Use pairing code'),
      );

      expect(scanButton.onPressed, isNull);
      expect(pairingCodeButton.onPressed, isNull);
    });
  });
}

Future<void> _expandPairingCode(WidgetTester tester) async {
  await tester.tap(find.text('Use pairing code'));
  await tester.pumpAndSettle();
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
  PairingState build() =>
      const PairingState(status: PairingStatus.transferring);

  @override
  Future<void> pair(String rawInput) async {}

  @override
  void reset() {}

  @override
  void confirmSas() {}

  @override
  void denySas() {}
}

class _ConfirmingSasPairingNotifier extends Notifier<PairingState>
    implements PairingNotifier {
  @override
  PairingState build() => const PairingState(
    status: PairingStatus.confirmingSas,
    sasCode: '123456',
  );

  @override
  Future<void> pair(String rawInput) async {}

  @override
  void reset() {}

  @override
  void confirmSas() {}

  @override
  void denySas() {}
}
