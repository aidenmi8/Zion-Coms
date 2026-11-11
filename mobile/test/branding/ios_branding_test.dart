import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in ['Debug', 'Release']) {
    test('$mode iOS app and extension share the Zion container convention', () {
      final settings = <String, String>{};
      for (final line in File('ios/Flutter/$mode.xcconfig').readAsLinesSync()) {
        final match = RegExp(r'^(\w+)\s*=\s*(.+)$').firstMatch(line);
        if (match != null) settings[match[1]!] = match[2]!.trim();
      }
      String resolve(String name) => settings[name]!.replaceAllMapped(
        RegExp(r'\$\((\w+)\)'),
        (match) => settings[match[1]] ?? match[0]!,
      );
      expect(resolve('BUNDLE_IDENTIFIER'), 'do.agente.zion');
      expect(resolve('APP_DISPLAY_NAME'), 'Zion');
      expect(resolve('BUZZ_APP_GROUP_IDENTIFIER'), 'group.do.agente.zion');
      expect(resolve('BUZZ_KEYCHAIN_ACCESS_GROUP'), 'do.agente.zion');
    });
  }

  test('bundled Zion icon is the approved artifact, not generated artwork', () {
    expect(
      sha256
          .convert(File('assets/images/zion-icon.png').readAsBytesSync())
          .toString(),
      '4ea736a6dad74fddcb3ef19690ffaf6e62a5dfb738207d628121cfdc7c6cab50',
    );
  });

  test(
    'iPhone home-screen icon is the approved silver mark without a wordmark',
    () {
      final icon = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      );
      expect(icon.existsSync(), isTrue);
      expect(
        sha256.convert(icon.readAsBytesSync()).toString(),
        'dce25adef22442dfed4a4a182ebd759fcab6df5daf33aa8f2faf3536f65f3a42',
      );
    },
  );

  test('iPhone launch image is also logo-only', () {
    final launch = File(
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
    );
    expect(
      sha256.convert(launch.readAsBytesSync()).toString(),
      '71dbc7215cad7fafedbcd70f3bb6fb166950d7c7f2b12462e4a3ac889d39f842',
    );
  });

  test('open-source display font and license are bundled on each client', () {
    for (final root in [
      'assets/fonts',
      '../web/public/fonts',
      '../admin-web/public/fonts',
    ]) {
      expect(
        sha256
            .convert(File('$root/Michroma-Regular.ttf').readAsBytesSync())
            .toString(),
        'b62301163788bc5b7f8fcac0b74b184e34e1827e577b499ecb724da065098f87',
      );
      expect(
        sha256
            .convert(File('$root/Michroma-OFL.txt').readAsBytesSync())
            .toString(),
        'e349ddd05b7028171de95f5dbacf58043e2511c6d2a80ba59c6f211bf3056e10',
      );
    }
  });
}
