enum ZionReleaseChannel { developer, release }

// Zion stays visibly pre-release unless the build explicitly passes
// --dart-define=ZION_RELEASE_CHANNEL=release.
const _configuredZionReleaseChannel = String.fromEnvironment(
  'ZION_RELEASE_CHANNEL',
  defaultValue: 'developer',
);

ZionReleaseChannel resolveZionReleaseChannel(String? value) {
  return value == ZionReleaseChannel.release.name
      ? ZionReleaseChannel.release
      : ZionReleaseChannel.developer;
}

final currentZionReleaseChannel = resolveZionReleaseChannel(
  _configuredZionReleaseChannel,
);

String formatZionReleaseLabel(String version, ZionReleaseChannel channel) {
  final developerSuffix = channel == ZionReleaseChannel.developer ? ' DV' : '';
  return 'Zion - V$version$developerSuffix';
}
