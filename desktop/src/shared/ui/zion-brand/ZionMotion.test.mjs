import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

import { frameAtTime } from "./brandAssetManifest.ts";
import { ZionBrandField } from "./ZionBrandField.tsx";
import { resolveMotionRenderAsset, ZionMotion } from "./ZionMotion.tsx";

test("frameAtTime loops, clamps, and safely handles empty frame sets", () => {
  assert.equal(frameAtTime(["a", "b", "c"], 250, 100), "c");
  assert.equal(frameAtTime(["a", "b", "c"], 350, 100), "a");
  assert.equal(frameAtTime(["a", "b", "c"], 350, 100, false), "c");
  assert.equal(frameAtTime([], 0, 100), null);
});

test("CSS defines reduced-motion fallback and all five Zion motion variants", () => {
  const css = fs.readFileSync(
    new URL("./zion-motion.css", import.meta.url),
    "utf8",
  );

  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(css, /animation: none/);
  assert.match(css, /\.zion-motion--loader/);
  assert.match(css, /\.zion-motion--onboarding/);
  assert.match(css, /\.zion-motion--liveness/);
  assert.match(css, /\.zion-motion--pairing/);
  assert.match(css, /\.zion-motion--agent-entrance/);
});

test("status markup keeps the visual mark decorative and exposes the label once", () => {
  const html = renderToStaticMarkup(
    React.createElement(
      "div",
      { role: "status" },
      React.createElement(ZionMotion, {
        ariaLabel: "Waiting for Zion",
        loop: false,
        playing: false,
        variant: "pairing",
      }),
    ),
  );

  assert.match(html, /data-brand-surface="zion-motion"/);
  assert.match(html, /data-zion-variant="pairing"/);
  assert.match(html, /data-playing="false"/);
  assert.match(html, /data-loop="false"/);
  assert.match(html, /alt=""/);
  assert.equal((html.match(/Waiting for Zion/g) ?? []).length, 1);
});

test("ZionBrandField renders deterministic inline transforms on first paint and is settled immediately for reduced motion", () => {
  const originalWindow = globalThis.window;
  const makeWindow = (matches) => ({
    matchMedia: () => ({
      matches,
      addEventListener() {},
      removeEventListener() {},
      addListener() {},
      removeListener() {},
    }),
  });

  try {
    globalThis.window = makeWindow(false);
    const firstPaintHtml = renderToStaticMarkup(
      React.createElement(ZionBrandField),
    );
    assert.match(firstPaintHtml, /opacity:0\.24/);
    assert.match(
      firstPaintHtml,
      /transform:translate\(-8px, 7px\) rotate\(-8deg\) scale\(0\.9\)/,
    );

    globalThis.window = makeWindow(true);
    const reducedMotionHtml = renderToStaticMarkup(
      React.createElement(ZionBrandField),
    );
    assert.match(reducedMotionHtml, /opacity:0\.76/);
    assert.match(
      reducedMotionHtml,
      /transform:translate\(0px, 0px\) rotate\(-8deg\) scale\(1\)/,
    );
  } finally {
    globalThis.window = originalWindow;
  }
});

test("dedicated-frame motion contracts resolve frames via mode and frameAtTime with static fallbacks", () => {
  const dedicatedFrameContract = {
    durationMs: 300,
    frames: ["/frame-1.svg", "/frame-2.svg", "/frame-3.svg"],
    loop: true,
    mode: "dedicated-frame",
    reducedMotion: "static",
  };

  assert.deepEqual(
    resolveMotionRenderAsset(dedicatedFrameContract, { elapsedMs: 250 }),
    { mode: "dedicated-frame", src: "/frame-3.svg" },
  );
  assert.deepEqual(
    resolveMotionRenderAsset(dedicatedFrameContract, { playing: false }),
    { mode: "dedicated-frame", src: "/frame-1.svg" },
  );
  assert.deepEqual(
    resolveMotionRenderAsset(dedicatedFrameContract, { reducedMotion: true }),
    { mode: "dedicated-frame", src: "/frame-1.svg" },
  );
  assert.deepEqual(
    resolveMotionRenderAsset({
      ...dedicatedFrameContract,
      mode: "code-native",
      frames: [],
    }),
    { mode: "code-native", src: null },
  );
});
