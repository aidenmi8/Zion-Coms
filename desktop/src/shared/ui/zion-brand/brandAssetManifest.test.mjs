import assert from "node:assert/strict";
import test from "node:test";

import {
  BRAND_MANIFEST,
  ZION_BRAND_ASSETS,
  ZION_MOTION_FRAMES,
  frameAtTime,
  framesForVariant,
} from "./brandAssetManifest.ts";

test("canonical Zion assets retain explicit Buzz URL aliases", () => {
  assert.equal(ZION_BRAND_ASSETS.mark.canonicalPath, "/branding/zion-mark.svg");
  assert.deepEqual(ZION_BRAND_ASSETS.mark.compatibilityPaths, [
    "/buzz.svg",
    "/favicon.svg",
  ]);
  assert.deepEqual(ZION_BRAND_ASSETS.appIcon.compatibilityPaths, [
    "/app-icon@2x.png",
    "/app-icon@3x.png",
  ]);
  assert.equal(
    ZION_BRAND_ASSETS.sentraWordmark.canonicalPath,
    "/branding/sentra-wordmark.svg",
  );
  assert.deepEqual(
    BRAND_MANIFEST.assets.sentraWordmark.aliases,
    ["desktop/public/landing/buzz-wordmark.png"],
  );
  assert.deepEqual(BRAND_MANIFEST.assets.webAppIcon.aliases, [
    "web/src/assets/app-icon@3x.png",
  ]);
  assert.deepEqual(BRAND_MANIFEST.assets.adminMark.aliases, [
    "admin-web/public/favicon.svg",
  ]);
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

test("checked-in manifest keeps measured source provenance and exclusions auditable", () => {
  assert.equal(BRAND_MANIFEST.version, 1);
  assert.equal(
    BRAND_MANIFEST.sourceDirectory,
    "/private/tmp/zion-brand-source",
  );

  for (const asset of Object.values(BRAND_MANIFEST.assets)) {
    assert.match(asset.sha256, /^[a-f0-9]{64}$/);
    assert.ok(asset.width > 0);
    assert.ok(asset.height > 0);
    assert.equal(typeof asset.hasAlpha, "boolean");
    assert.ok(asset.colorSpace.length > 0);
    assert.equal(asset.sourceFormat, "png");
    assert.notEqual(asset.sourceFile, "Logos-sentra-v2-1.png");
  }

  assert.equal(
    BRAND_MANIFEST.sources["Logos-sentra-v2-1.png"].disposition,
    "reference-only",
  );
  assert.equal(
    BRAND_MANIFEST.sources["sentra-agent-ARQ-and Agents.png"].disposition,
    "reference-only",
  );
  assert.equal(
    BRAND_MANIFEST.sources["sentra-logo-branding -jul-2026.png"].disposition,
    "reference-only",
  );
  assert.equal(Object.keys(BRAND_MANIFEST.sources).length, 15);
});

test("frame sequencing clamps, loops, and has a safe empty fallback", () => {
  const frames = ["frame-01.png", "frame-02.png", "frame-03.png"];
  assert.equal(frameAtTime(frames, 0, 100), "frame-01.png");
  assert.equal(frameAtTime(frames, 250, 100), "frame-03.png");
  assert.equal(frameAtTime(frames, 350, 100), "frame-01.png");
  assert.equal(frameAtTime(frames, 350, 100, false), "frame-03.png");
  assert.equal(frameAtTime([], 0, 100), null);
});
