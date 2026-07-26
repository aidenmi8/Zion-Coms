import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS builds use the owned bundle ID and retain the buzz URL scheme', () {
    for (final configuration in ['Debug.xcconfig', 'Release.xcconfig']) {
      final contents = File('ios/Flutter/$configuration').readAsStringSync();
      expect(contents, contains('BUNDLE_IDENTIFIER = do.agente.zion'));
    }

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
}
