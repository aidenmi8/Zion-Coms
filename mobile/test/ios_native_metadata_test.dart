import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS builds use the owned bundle ID and retain the buzz URL scheme', () {
    for (final configuration in ['Debug.xcconfig', 'Release.xcconfig']) {
      final contents = File('ios/Flutter/$configuration').readAsStringSync();
      expect(contents, contains('BUNDLE_IDENTIFIER = do.agente.zion'));
    }
    final watchConfiguration = File(
      'ios/Flutter/Watch.xcconfig',
    ).readAsStringSync();
    expect(
      watchConfiguration,
      contains('BUNDLE_IDENTIFIER = do.agente.zion'),
      reason: 'the embedded Watch app must identify the Zion iPhone companion',
    );

    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      infoPlist,
      contains(r'<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>'),
    );
    expect(infoPlist, contains('<string>buzz</string>'));

    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(
      project,
      contains(r'PRODUCT_BUNDLE_IDENTIFIER = "$(BUNDLE_IDENTIFIER)";'),
    );
    expect(
      project,
      contains('PRODUCT_MODULE_NAME = Buzz;'),
      reason: 'the public Zion rename must preserve the internal Swift module',
    );

    final runnerTests = File(
      'ios/RunnerTests/RunnerTests.swift',
    ).readAsStringSync();
    expect(runnerTests, contains('@testable import Buzz'));
  });

  test('iOS device builds re-sign Flutter native asset frameworks', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(project, contains('[Zion] Sign Flutter Native Assets'));
    expect(project, contains('Flutter/sign_native_assets.sh'));

    final script = File('ios/Flutter/sign_native_assets.sh').readAsStringSync();
    expect(script, contains('io.flutter.flutter.native-assets.*'));
    expect(script, contains('EXPANDED_CODE_SIGN_IDENTITY'));
    expect(script, contains('/usr/bin/codesign --force --sign'));
  });

  test('watchOS uses the completed Zion artwork and app icon', () {
    final suppliedWordmark = File(
      'assets/images/sentra-wordmark-white.png',
    ).readAsBytesSync();
    final watchWordmark = File(
      'ios/ZionWatch/Assets.xcassets/SentraWordmark.imageset/'
      'SentraWordmark.png',
    );
    expect(watchWordmark.existsSync(), isTrue);
    expect(watchWordmark.readAsBytesSync(), orderedEquals(suppliedWordmark));

    final phoneIcon = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    ).readAsBytesSync();
    final watchIcon = File(
      'ios/ZionWatch/Assets.xcassets/AppIcon.appiconset/'
      'ZionWatchIcon.png',
    );
    expect(watchIcon.existsSync(), isTrue);
    expect(watchIcon.readAsBytesSync(), orderedEquals(phoneIcon));

    final iconMetadata = File(
      'ios/ZionWatch/Assets.xcassets/AppIcon.appiconset/Contents.json',
    ).readAsStringSync();
    expect(iconMetadata, contains('"platform" : "watchos"'));
    expect(iconMetadata, contains('"filename" : "ZionWatchIcon.png"'));

    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(
      RegExp(
        'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;',
      ).allMatches(project).length,
      6,
      reason:
          'Runner and ZionWatch each need Debug, Profile, and Release icons',
    );
  });
}
