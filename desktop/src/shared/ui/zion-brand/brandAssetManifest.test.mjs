import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import {
  BRAND_MANIFEST,
  ZION_BRAND_ASSETS,
  ZION_MOTION_FRAMES,
  frameAtTime,
  framesForVariant,
} from "./brandAssetManifest.ts";

test("manifest records exact canonical metadata for every derived output", () => {
  const expected = {
    sentraV2_2: {
      outputPath: "desktop/public/branding/sentra-v2-2.png",
      format: "png",
      sha256:
        "c52e77b57c3e24284bd0794fa917da612a3d953a8725eece6fc4798d43a62e6a",
      width: 1254,
      height: 1254,
    },
    sentraV2_3: {
      outputPath: "desktop/public/branding/sentra-v2-3.png",
      format: "png",
      sha256:
        "6af0cd4ab5b72e52e4aa2712e0dae003aaaf2ccef774b95e669a3bc75d3b9cd7",
      width: 1254,
      height: 1254,
    },
    sentraV2_4: {
      outputPath: "desktop/public/branding/sentra-v2-4.png",
      format: "png",
      sha256:
        "f6ef000cad2cc1dddbd68bc86ca93336ae5299e8f1f0c591bb6053f46cd1de45",
      width: 1254,
      height: 1254,
    },
    sentraV2_5: {
      outputPath: "desktop/public/branding/sentra-v2-5.png",
      format: "png",
      sha256:
        "f44dfea9e6e9b423729ac76f47a7366ae19df304da6a77204b81599c8ff9850f",
      width: 1254,
      height: 1254,
    },
    sentraV2_6: {
      outputPath: "desktop/public/branding/sentra-v2-6.png",
      format: "png",
      sha256:
        "9836d450544705316dc4b0bc894b89922b6470d9006835558ad0227e28bce43f",
      width: 1254,
      height: 1254,
    },
    sentraV2_7: {
      outputPath: "desktop/public/branding/sentra-v2-7.png",
      format: "png",
      sha256:
        "88acc7498b4532393b837b53c89cbe3cbf0dde7d5c887ae49ef28c66eb0da16d",
      width: 1254,
      height: 1254,
    },
    sentraV2_10: {
      outputPath: "desktop/public/branding/sentra-v2-10.png",
      format: "png",
      sha256:
        "8b171011068555e7a6e89cce1355480ce46dc180df2a1b484117601fe4ab3433",
      width: 1254,
      height: 1254,
    },
    appIcon: {
      outputPath: "desktop/public/branding/zion-app-icon-1024.png",
      format: "png",
      sha256:
        "4ea736a6dad74fddcb3ef19690ffaf6e62a5dfb738207d628121cfdc7c6cab50",
      width: 1024,
      height: 1024,
    },
    appIcon2x: {
      outputPath: "desktop/public/branding/zion-app-icon@2x.png",
      format: "png",
      sha256:
        "ce3220c0502d51544d0a393ac4d1a366e7af702e132e96708dffc0f1898fb50f",
      width: 2048,
      height: 2048,
    },
    appIcon3x: {
      outputPath: "desktop/public/branding/zion-app-icon@3x.png",
      format: "png",
      sha256:
        "b9b1b8cad55b1f42db611296ad6d908442b916c79107b5b811fb3a59e4c3f23f",
      width: 3072,
      height: 3072,
    },
    dmgBackground: {
      outputPath: "desktop/public/branding/sentra-dmg-background-1200x800.png",
      format: "png",
      sha256:
        "9a410e738605f7a3ad0a04ccc8df0f87e4875c9634a182768ab509bdad02890f",
      width: 1200,
      height: 800,
    },
    dmgBackgroundSmall: {
      outputPath: "desktop/public/branding/sentra-dmg-background-600x400.png",
      format: "png",
      sha256:
        "7b571fff21fb8028883f6c576eba5bec317e122f94b901d72fc29e0ee6369195",
      width: 600,
      height: 400,
    },
    sentraWordmark: {
      outputPath: "desktop/public/branding/sentra-wordmark.svg",
      format: "svg",
      sha256:
        "6928f865105f6a15b2786ad59d8a0fa8c2f6dcfb921ee35b9699a9c1c273b4a8",
      width: 1024,
      height: 1024,
    },
    sentraLockup: {
      outputPath: "desktop/public/branding/sentra-lockup-horizontal.svg",
      format: "svg",
      sha256:
        "fe7a257f666946b064571bcd73700f30ebf33e0bcd5076f47790bda076c9b01d",
      width: 1024,
      height: 1024,
    },
    sentraLockupLight: {
      outputPath: "desktop/public/branding/sentra-lockup-light.svg",
      format: "svg",
      sha256:
        "fe7a257f666946b064571bcd73700f30ebf33e0bcd5076f47790bda076c9b01d",
      width: 1024,
      height: 1024,
    },
    sentraLockupDark: {
      outputPath: "desktop/public/branding/sentra-lockup-dark.svg",
      format: "svg",
      sha256:
        "087a92c1efdaba769e851fc72638f777e8f89adb8530f6661428536ee4b0c9d5",
      width: 1024,
      height: 1024,
    },
    zionMark: {
      outputPath: "desktop/public/branding/zion-mark.svg",
      format: "svg",
      sha256:
        "fd0d912d30cb3b817df0b3167b7c77f6929cfa0d0b8f1407c9b1d6d9e7acd124",
      width: 1254,
      height: 1254,
    },
    sentraStatusGlyph: {
      outputPath: "desktop/public/branding/sentra-status-glyph.svg",
      format: "svg",
      sha256:
        "11eb0f043a2fa5ae10804d9c6b3f96acc41a8958075852b701f65255e6a0338d",
      width: 1254,
      height: 1254,
    },
  };

  for (const [assetId, metadata] of Object.entries(expected)) {
    const asset = BRAND_MANIFEST.assets[assetId];
    for (const [field, value] of Object.entries(metadata)) {
      assert.equal(asset[field], value, `${assetId}.${field}`);
    }
  }

  assert.equal(Object.keys(BRAND_MANIFEST.assets).length, 18);
  for (const asset of Object.values(BRAND_MANIFEST.assets)) {
    assert.match(asset.sha256, /^[a-f0-9]{64}$/);
    assert.equal(typeof asset.hasAlpha, "boolean");
    assert.ok(asset.colorSpace.length > 0);
  }
});

test("manifest inventories every compatibility alias with exact metadata", () => {
  assert.deepEqual(BRAND_MANIFEST.assets.appIcon2x.aliases, [
    "desktop/public/app-icon@2x.png",
  ]);
  assert.deepEqual(BRAND_MANIFEST.assets.appIcon3x.aliases, [
    "desktop/public/app-icon@3x.png",
    "web/src/assets/zion-app-icon@3x.png",
    "web/src/assets/app-icon@3x.png",
  ]);
  assert.deepEqual(BRAND_MANIFEST.assets.sentraWordmark.aliases, [
    "desktop/public/landing/buzz-wordmark.png",
  ]);
  assert.deepEqual(BRAND_MANIFEST.assets.zionMark.aliases, [
    "desktop/public/buzz.svg",
    "admin-web/public/zion-mark.svg",
    "admin-web/public/favicon.svg",
  ]);

  assert.deepEqual(Object.keys(BRAND_MANIFEST.aliasInventory), [
    "desktop/public/app-icon@2x.png",
    "desktop/public/app-icon@3x.png",
    "web/src/assets/zion-app-icon@3x.png",
    "web/src/assets/app-icon@3x.png",
    "desktop/public/landing/buzz-wordmark.png",
    "desktop/public/buzz.svg",
    "admin-web/public/zion-mark.svg",
    "admin-web/public/favicon.svg",
  ]);

  const exactAliases = {
    "desktop/public/app-icon@2x.png": {
      format: "png",
      sha256:
        "ce3220c0502d51544d0a393ac4d1a366e7af702e132e96708dffc0f1898fb50f",
      width: 2048,
      height: 2048,
    },
    "desktop/public/app-icon@3x.png": {
      format: "png",
      sha256:
        "b9b1b8cad55b1f42db611296ad6d908442b916c79107b5b811fb3a59e4c3f23f",
      width: 3072,
      height: 3072,
    },
    "web/src/assets/zion-app-icon@3x.png": {
      format: "png",
      sha256:
        "b9b1b8cad55b1f42db611296ad6d908442b916c79107b5b811fb3a59e4c3f23f",
      width: 3072,
      height: 3072,
    },
    "web/src/assets/app-icon@3x.png": {
      format: "png",
      sha256:
        "b9b1b8cad55b1f42db611296ad6d908442b916c79107b5b811fb3a59e4c3f23f",
      width: 3072,
      height: 3072,
    },
    "desktop/public/landing/buzz-wordmark.png": {
      format: "png",
      sha256:
        "9b44ba56ecde2204c2f05c8dcde8274c3618b91ae3ae7a739054a7ff8289e0d6",
      width: 1024,
      height: 1024,
    },
    "desktop/public/buzz.svg": {
      format: "svg",
      sha256:
        "fd0d912d30cb3b817df0b3167b7c77f6929cfa0d0b8f1407c9b1d6d9e7acd124",
      width: 1254,
      height: 1254,
    },
    "admin-web/public/zion-mark.svg": {
      format: "svg",
      sha256:
        "fd0d912d30cb3b817df0b3167b7c77f6929cfa0d0b8f1407c9b1d6d9e7acd124",
      width: 1254,
      height: 1254,
    },
    "admin-web/public/favicon.svg": {
      format: "svg",
      sha256:
        "fd0d912d30cb3b817df0b3167b7c77f6929cfa0d0b8f1407c9b1d6d9e7acd124",
      width: 1254,
      height: 1254,
    },
  };
  for (const [aliasPath, metadata] of Object.entries(exactAliases)) {
    const alias = BRAND_MANIFEST.aliasInventory[aliasPath];
    for (const [field, value] of Object.entries(metadata)) {
      assert.equal(alias[field], value, `${aliasPath}.${field}`);
    }
  }
});

test("React exports derive paths and provenance only from the manifest", () => {
  assert.deepEqual(ZION_BRAND_ASSETS.mark, {
    canonicalPath: BRAND_MANIFEST.assets.zionMark.canonicalPath,
    compatibilityPaths: BRAND_MANIFEST.assets.zionMark.compatibilityPaths,
    role: "mark",
    source: BRAND_MANIFEST.assets.zionMark.sourceFile,
  });
  assert.deepEqual(ZION_BRAND_ASSETS.appIcon, {
    canonicalPath: BRAND_MANIFEST.assets.appIcon.canonicalPath,
    compatibilityPaths: BRAND_MANIFEST.assets.appIcon.compatibilityPaths,
    role: "appIcon",
    source: BRAND_MANIFEST.assets.appIcon.sourceFile,
  });
  assert.equal(
    ZION_BRAND_ASSETS.sentraWordmark.canonicalPath,
    BRAND_MANIFEST.assets.sentraWordmark.canonicalPath,
  );
  assert.equal(
    ZION_BRAND_ASSETS.sentraLockup.canonicalPath,
    BRAND_MANIFEST.assets.sentraLockup.canonicalPath,
  );
  assert.equal(
    ZION_BRAND_ASSETS.sentraStatusGlyph.canonicalPath,
    BRAND_MANIFEST.assets.sentraStatusGlyph.canonicalPath,
  );
  assert.equal(
    ZION_BRAND_ASSETS.dmgBackground.canonicalPath,
    BRAND_MANIFEST.assets.dmgBackground.canonicalPath,
  );

  const moduleSource = fs.readFileSync(
    new URL("./brandAssetManifest.ts", import.meta.url),
    "utf8",
  );
  assert.doesNotMatch(
    moduleSource,
    /canonicalPath:\s*["'`]\/(?:branding|buzz|app-icon)/,
  );
  assert.doesNotMatch(moduleSource, /compatibilityPaths:\s*\[/);
});

test("manifest records all five code-native motion variants without fake frames", () => {
  assert.deepEqual(BRAND_MANIFEST.motion.variants, [
    "loader",
    "onboarding",
    "liveness",
    "pairing",
    "agent-entrance",
  ]);
  assert.deepEqual(BRAND_MANIFEST.motion.loader, {
    durationMs: 1800,
    loop: true,
    mode: "code-native",
    reducedMotion: "static",
  });
  assert.deepEqual(BRAND_MANIFEST.motion.onboarding, {
    durationMs: 900,
    settleMs: 2400,
    loop: false,
    mode: "code-native",
    reducedMotion: "settled",
  });
  assert.deepEqual(BRAND_MANIFEST.motion.liveness, {
    durationMs: 1400,
    loop: true,
    mode: "code-native",
    reducedMotion: "static",
  });
  assert.deepEqual(BRAND_MANIFEST.motion.pairing, {
    durationMs: 1800,
    loop: false,
    mode: "code-native",
    reducedMotion: "settled",
  });
  assert.deepEqual(BRAND_MANIFEST.motion["agent-entrance"], {
    durationMs: 900,
    staggerMs: 320,
    loop: false,
    mode: "code-native",
    reducedMotion: "settled",
  });
  assert.deepEqual(Object.keys(ZION_MOTION_FRAMES), [
    "loader",
    "onboarding",
    "liveness",
    "pairing",
    "agent-entrance",
  ]);
  assert.deepEqual(framesForVariant("loader"), []);
  assert.notEqual(framesForVariant("loader"), framesForVariant("liveness"));
});

test("checked-in manifest keeps measured provenance and exclusions auditable", () => {
  assert.equal(BRAND_MANIFEST.version, 1);
  assert.equal(
    BRAND_MANIFEST.sourceDirectory,
    "/private/tmp/zion-brand-source",
  );
  assert.doesNotMatch(BRAND_MANIFEST.sourceDirectory, /production-final/);

  const expectedDispositions = {
    "Logos-sentra-v2-2.png": "shipped",
    "Logos-sentra-v2-3.png": "shipped",
    "Logos-sentra-v2-4.png": "shipped",
    "Logos-sentra-v2-5.png": "shipped",
    "Logos-sentra-v2-6.png": "shipped",
    "Logos-sentra-v2-7.png": "shipped",
    "Logos-sentra-v2-8.png": "shipped",
    "Logos-sentra-v2-9.png": "shipped",
    "Logos-sentra-v2-10.png": "shipped",
    "logo-TW-wordmark.png": "shipped",
    "logo-TW2-wordmark.png": "shipped",
    "logo-TB-wordmark.png": "shipped",
    "Logos-sentra-v2-1.png": "reference-only",
    "sentra-agent-ARQ-and Agents.png": "reference-only",
    "sentra-logo-branding -jul-2026.png": "reference-only",
  };
  assert.deepEqual(
    Object.fromEntries(
      Object.entries(BRAND_MANIFEST.sources).map(([sourceFile, source]) => [
        sourceFile,
        source.disposition,
      ]),
    ),
    expectedDispositions,
  );

  for (const [sourceFile, source] of Object.entries(BRAND_MANIFEST.sources)) {
    assert.equal(source.format, "png", `${sourceFile}.format`);
    assert.match(source.sha256, /^[a-f0-9]{64}$/, `${sourceFile}.sha256`);
    assert.ok(source.width > 0, `${sourceFile}.width`);
    assert.ok(source.height > 0, `${sourceFile}.height`);
    assert.equal(typeof source.hasAlpha, "boolean", `${sourceFile}.hasAlpha`);
    assert.equal(source.colorSpace, "RGB", `${sourceFile}.colorSpace`);
  }

  assert.deepEqual(BRAND_MANIFEST.sources["Logos-sentra-v2-8.png"], {
    disposition: "shipped",
    relativePath: "Logos-sentra-v2-8.png",
    format: "png",
    sha256: "9dd5bcf31e3b8d531d9e2df38edd3b61fc41cf579541b6fda41713c76b6e5b1b",
    width: 1254,
    height: 1254,
    hasAlpha: false,
    colorSpace: "RGB",
  });
  assert.ok(
    Object.values(BRAND_MANIFEST.assets).every(
      (asset) => asset.sourceFile !== "Logos-sentra-v2-1.png",
    ),
  );
});

test("frame sequencing clamps, loops, and has a safe empty fallback", () => {
  const frames = ["frame-01.png", "frame-02.png", "frame-03.png"];
  assert.equal(frameAtTime(frames, 0, 100), "frame-01.png");
  assert.equal(frameAtTime(frames, 250, 100), "frame-03.png");
  assert.equal(frameAtTime(frames, 350, 100), "frame-01.png");
  assert.equal(frameAtTime(frames, 350, 100, false), "frame-03.png");
  assert.equal(frameAtTime([], 0, 100), null);
});
