import 'package:buzz/features/pairing/pairing_page/onboarding_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Zion identity is readable with reduced motion and large text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final reduced in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                disableAnimations: reduced,
                textScaler: const TextScaler.linear(2),
              ),
              child: const Center(
                child: SizedBox(
                  width: 320,
                  height: 134,
                  child: OnboardingWordmark(color: Color(0xFFF5F5F7)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Zion'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(OnboardingWordmark),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
        expect(find.text('ZION'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('ZION')).style!.color,
          const Color(0xFFF5F5F7),
        );
        expect(
          tester.widget<Text>(find.text('ZION')).style!.fontFamily,
          'Michroma',
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });
}
