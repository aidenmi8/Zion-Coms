import BRAND_MANIFEST from "../../../../../branding/zion-brand-manifest.json" with {
  type: "json",
};

export const ZION_MOTION_VARIANTS = [
  "loader",
  "onboarding",
  "liveness",
  "pairing",
  "agent-entrance",
] as const;

export type ZionMotionVariant = (typeof ZION_MOTION_VARIANTS)[number];

export type ZionBrandAsset = {
  canonicalPath: string;
  compatibilityPaths?: readonly string[];
  role: "mark" | "appIcon" | "wordmark" | "lockup" | "status" | "packaging";
  source: string;
};

type ZionMotionMode = "code-native" | "dedicated-frame";
type ZionReducedMotionPolicy = "static" | "settled";
type ZionMotionFrameRecord = {
  path: string;
  dedicatedAnimationFrame: true;
};

type ZionMotionDefinitionBase = {
  durationMs: number;
  frames?: readonly ZionMotionFrameRecord[];
  loop: boolean;
  mode: ZionMotionMode;
  reducedMotion: ZionReducedMotionPolicy;
};

type ZionMotionDefinitionMap = {
  loader: ZionMotionDefinitionBase;
  onboarding: ZionMotionDefinitionBase & { settleMs: number };
  liveness: ZionMotionDefinitionBase;
  pairing: ZionMotionDefinitionBase;
  "agent-entrance": ZionMotionDefinitionBase & { staggerMs: number };
};

type ZionMotionManifestRecord = {
  frameSourcePolicy: "dedicated-frame-or-code-native";
  variants?: readonly string[];
} & ZionMotionDefinitionMap;

type ZionNormalizedMotionDefinition = Omit<
  ZionMotionDefinitionBase,
  "frames"
> & {
  frames: readonly string[];
};

export type ZionMotionManifest = {
  frameSourcePolicy: "dedicated-frame-or-code-native";
  variants: readonly ZionMotionVariant[];
} & {
  [Variant in ZionMotionVariant]: ZionNormalizedMotionDefinition &
    (Variant extends "onboarding"
      ? { settleMs: number }
      : Variant extends "agent-entrance"
        ? { staggerMs: number }
        : Record<never, never>);
};

function isZionMotionVariant(value: string): value is ZionMotionVariant {
  return (ZION_MOTION_VARIANTS as readonly string[]).includes(value);
}

function normalizeMotionBase(definition: ZionMotionDefinitionBase) {
  const frames = (definition.frames ?? []).map((frame) => frame.path);

  return {
    durationMs: definition.durationMs,
    frames,
    loop: definition.loop,
    mode: definition.mode,
    reducedMotion: definition.reducedMotion,
  };
}

function normalizeMotionManifest(
  manifest: ZionMotionManifestRecord,
): ZionMotionManifest {
  const manifestVariants =
    manifest.variants?.filter(isZionMotionVariant) ?? ZION_MOTION_VARIANTS;

  return {
    frameSourcePolicy: manifest.frameSourcePolicy,
    variants:
      manifestVariants.length === ZION_MOTION_VARIANTS.length
        ? [...manifestVariants]
        : [...ZION_MOTION_VARIANTS],
    loader: normalizeMotionBase(manifest.loader),
    onboarding: {
      ...normalizeMotionBase(manifest.onboarding),
      settleMs: manifest.onboarding.settleMs,
    },
    liveness: normalizeMotionBase(manifest.liveness),
    pairing: normalizeMotionBase(manifest.pairing),
    "agent-entrance": {
      ...normalizeMotionBase(manifest["agent-entrance"]),
      staggerMs: manifest["agent-entrance"].staggerMs,
    },
  };
}

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

export const ZION_MOTION_MANIFEST = normalizeMotionManifest(
  BRAND_MANIFEST.motion as ZionMotionManifestRecord,
);

export const ZION_MOTION_FRAMES: Readonly<
  Record<ZionMotionVariant, readonly string[]>
> = Object.freeze(
  Object.fromEntries(
    ZION_MOTION_VARIANTS.map((variant) => [
      variant,
      ZION_MOTION_MANIFEST[variant].frames,
    ]),
  ) as Record<ZionMotionVariant, readonly string[]>,
);

export function framesForVariant(variant: ZionMotionVariant) {
  return ZION_MOTION_FRAMES[variant];
}

export function motionForVariant(variant: ZionMotionVariant) {
  return ZION_MOTION_MANIFEST[variant];
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
