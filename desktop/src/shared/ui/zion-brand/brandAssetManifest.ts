import BRAND_MANIFEST from "../../../../../branding/zion-brand-manifest.json" with {
  type: "json",
};

export type ZionMotionVariant =
  | "loader"
  | "onboarding"
  | "liveness"
  | "pairing"
  | "agent-entrance";

export type ZionBrandAsset = {
  canonicalPath: string;
  compatibilityPaths?: readonly string[];
  role: "mark" | "appIcon" | "wordmark" | "lockup" | "status" | "packaging";
  source: string;
};

export { BRAND_MANIFEST };

export const ZION_BRAND_ASSETS = {
  mark: {
    canonicalPath: BRAND_MANIFEST.assets.zionMark.canonicalPath,
    compatibilityPaths: BRAND_MANIFEST.assets.zionMark.compatibilityPaths,
    role: "mark",
    source: BRAND_MANIFEST.assets.zionMark.sourceFile,
  },
  appIcon: {
    canonicalPath: BRAND_MANIFEST.assets.appIcon.canonicalPath,
    compatibilityPaths: BRAND_MANIFEST.assets.appIcon.compatibilityPaths,
    role: "appIcon",
    source: BRAND_MANIFEST.assets.appIcon.sourceFile,
  },
  sentraWordmark: {
    canonicalPath: BRAND_MANIFEST.assets.sentraWordmark.canonicalPath,
    role: "wordmark",
    source: BRAND_MANIFEST.assets.sentraWordmark.sourceFile,
  },
  sentraLockup: {
    canonicalPath: BRAND_MANIFEST.assets.sentraLockup.canonicalPath,
    role: "lockup",
    source: BRAND_MANIFEST.assets.sentraLockup.sourceFile,
  },
  sentraStatusGlyph: {
    canonicalPath: BRAND_MANIFEST.assets.sentraStatusGlyph.canonicalPath,
    role: "status",
    source: BRAND_MANIFEST.assets.sentraStatusGlyph.sourceFile,
  },
  dmgBackground: {
    canonicalPath: BRAND_MANIFEST.assets.dmgBackground.canonicalPath,
    role: "packaging",
    source: BRAND_MANIFEST.assets.dmgBackground.sourceFile,
  },
} satisfies Record<string, ZionBrandAsset>;

export const ZION_MOTION_FRAMES: Readonly<
  Record<ZionMotionVariant, readonly string[]>
> = {
  loader: [],
  onboarding: [],
  liveness: [],
  pairing: [],
  "agent-entrance": [],
};

export function framesForVariant(variant: ZionMotionVariant) {
  return ZION_MOTION_FRAMES[variant];
}

export function frameAtTime(
  frames: readonly string[],
  elapsedMs: number,
  frameDurationMs: number,
  loop = true,
) {
  if (frames.length === 0 || frameDurationMs <= 0) return null;
  const rawIndex = Math.floor(Math.max(elapsedMs, 0) / frameDurationMs);
  const index = loop
    ? rawIndex % frames.length
    : Math.min(rawIndex, frames.length - 1);
  return frames[index] ?? null;
}
