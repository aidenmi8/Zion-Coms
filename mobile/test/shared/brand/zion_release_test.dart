import 'package:buzz/shared/brand/zion_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unconfigured builds default to the developer channel', () {
    expect(currentZionReleaseChannel, ZionReleaseChannel.developer);
    expect(resolveZionReleaseChannel(null), ZionReleaseChannel.developer);
  });

  test('developer builds expose the shared Zion 0.0.9 DV label', () {
    expect(
      formatZionReleaseLabel('0.0.9', ZionReleaseChannel.developer),
      'Zion - V0.0.9 DV',
    );
  });

  test('release builds remove only the DV channel label', () {
    expect(
      formatZionReleaseLabel('0.0.9', ZionReleaseChannel.release),
      'Zion - V0.0.9',
    );
  });
}
