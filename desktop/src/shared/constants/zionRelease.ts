export const ZionReleaseChannel = {
  Developer: "developer",
  Release: "release",
} as const;

export type ZionReleaseChannel =
  (typeof ZionReleaseChannel)[keyof typeof ZionReleaseChannel];

export type ZionBuildInfo = {
  buildId: string;
  commit: string;
  worktree: "clean" | "dirty" | "unknown";
};

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

function readBuildEnv(key: string, fallback: string): string {
  const value = import.meta.env?.[key]?.trim();
  return value || fallback;
}

export const currentZionBuild: ZionBuildInfo = {
  buildId: readBuildEnv("VITE_ZION_BUILD_ID", "local"),
  commit: readBuildEnv("VITE_ZION_COMMIT", "unknown"),
  worktree: (() => {
    const value = readBuildEnv("VITE_ZION_WORKTREE", "unknown");
    return value === "clean" || value === "dirty" ? value : "unknown";
  })(),
};

export function formatZionReleaseLabel(
  version: string,
  channel: ZionReleaseChannel,
): string {
  const developerSuffix = channel === ZionReleaseChannel.Developer ? " DV" : "";
  return `Zion - V${version}${developerSuffix}`;
}

export function formatZionBuildLabel(build: ZionBuildInfo): string {
  const worktreeSuffix = build.worktree === "dirty" ? " · local changes" : "";
  return `Build ${build.buildId} · commit ${build.commit}${worktreeSuffix}`;
}
