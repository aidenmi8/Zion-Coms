export const ZionReleaseChannel = {
  Developer: "developer",
  Release: "release",
} as const;

export type ZionReleaseChannel =
  (typeof ZionReleaseChannel)[keyof typeof ZionReleaseChannel];

export function resolveZionReleaseChannel(
  value: string | undefined,
): ZionReleaseChannel {
  return value === ZionReleaseChannel.Release
    ? ZionReleaseChannel.Release
    : ZionReleaseChannel.Developer;
}

// Zion stays visibly pre-release unless a production build explicitly sets
// VITE_ZION_RELEASE_CHANNEL=release.
export const currentZionReleaseChannel = resolveZionReleaseChannel(
  import.meta.env?.VITE_ZION_RELEASE_CHANNEL,
);

export function formatZionReleaseLabel(
  version: string,
  channel: ZionReleaseChannel,
): string {
  const developerSuffix = channel === ZionReleaseChannel.Developer ? " DV" : "";
  return `Zion - V${version}${developerSuffix}`;
}
