import 'dart:io';
import 'dart:ui' as ui;

import 'package:buzz/features/pairing/pairing_page.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:buzz/shared/widgets/onboarding_loading_page.dart';
import 'package:buzz/shared/widgets/mobile_tab_footer_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/InterVariable.ttf',
      'Michroma': 'assets/fonts/Michroma-Regular.ttf',
      'GeistMono': 'assets/fonts/GeistMono-Variable.ttf',
      'BuzzTabler': 'assets/fonts/TablerIcons.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  testWidgets(
    'Zion welcome retains connection actions and accessible identity',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var connected = false;

        for (final scale in [1.0, 2.0]) {
          connected = false;
          await tester.pumpWidget(
            _preview(
              child: PairingPage(
                connectionLanding: true,
                onCommunityLink: () => connected = true,
                onAlreadyUseBuzz: () {},
              ),
              textScale: scale,
              brightness: scale == 1 ? Brightness.light : Brightness.dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.bySemanticsLabel('Zion'), findsOneWidget);
          final background = tester.widget<DecoratedBox>(
            find.byKey(const Key('pairing-website-welcome-background')),
          );
          final gradient =
              (background.decoration as BoxDecoration).gradient!
                  as LinearGradient;
          expect(gradient.colors, const [
            Color(0xFF0A0A0A),
            Color(0xFF1C1C1E),
            Color(0xFF0A0A0A),
          ]);
          final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byKey(const Key('pairing-onboarding-system-overlay')),
          );
          expect(overlay.value.statusBarIconBrightness, Brightness.light);
          expect(find.bySemanticsLabel('Buzz'), findsNothing);
          expect(find.text('Enter a community link'), findsOneWidget);
          expect(find.text('Scan a QR code'), findsOneWidget);
          await tester.ensureVisible(find.text('Enter a community link'));
          await tester.tap(find.text('Enter a community link'));
          expect(connected, isTrue);
          expect(tester.takeException(), isNull);
          if (scale == 1) await _capture(tester, 'welcome.png');
          await tester.pumpWidget(const SizedBox.shrink());
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('the production footer fades into the Zion bottom surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      _preview(
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MobileTabFooterBackdrop(height: 180),
          ),
        ),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(MobileTabFooterBackdrop),
        matching: find.byType(DecoratedBox),
      ),
    );
    final gradient =
        (box.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors.last, const Color(0xFF0A0A0A));
  });

  testWidgets('loading uses Zion art without animation under reduced motion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _preview(
        child: const OnboardingLoadingPage(
          title: 'Connecting to your community',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/zion-icon.png',
      ),
      findsOneWidget,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'loading.png');
  });
}

Widget _preview({
  required Widget child,
  double textScale = 1,
  Brightness brightness = Brightness.dark,
}) => ProviderScope(
  child: MaterialApp(
    theme: mobileAppearanceTheme(brightness, 'neutral'),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(393, 852),
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: RepaintBoundary(key: const Key('zion-preview'), child: child),
    ),
  ),
);

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['ZION_MOBILE_PREVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/zion-icon.png'),
      tester.element(find.byKey(const Key('zion-preview'))),
    ),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('zion-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
