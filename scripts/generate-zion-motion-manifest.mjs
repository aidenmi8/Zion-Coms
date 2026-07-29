#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const KNOWN_VARIANTS = [
  "loader",
  "onboarding",
  "liveness",
  "pairing",
  "agent-entrance",
];

function fail(message) {
  throw new Error(message);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function parseArgs(argv) {
  const options = {
    manifestPath: path.resolve("branding/zion-brand-manifest.json"),
    outPath: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--out") {
      const next = argv[index + 1];
      if (!next) fail("Missing value after --out");
      options.outPath = path.resolve(next);
      index += 1;
      continue;
    }

    if (argument.startsWith("--")) {
      fail(`Unknown flag: ${argument}`);
    }

    options.manifestPath = path.resolve(argument);
  }

  return options;
}

function normalizeFrames(variant, definition) {
  const frames = definition.frames ?? [];
  if (!Array.isArray(frames)) {
    fail(`${variant}.frames must be an array when provided`);
  }

  return frames.map((frame, index) => {
    if (!isObject(frame)) {
      fail(
        `${variant}.frames[${index}] must be an object with path and dedicatedAnimationFrame=true`,
      );
    }

    if (frame.dedicatedAnimationFrame !== true) {
      fail(
        `${variant}.frames[${index}] must set dedicatedAnimationFrame=true`,
      );
    }

    if (typeof frame.path !== "string" || frame.path.length === 0) {
      fail(`${variant}.frames[${index}].path must be a non-empty string`);
    }

    return frame.path;
  });
}

function normalizeVariant(variant, definition) {
  if (!isObject(definition)) {
    fail(`${variant} must be an object`);
  }

  if (!Number.isFinite(definition.durationMs) || definition.durationMs <= 0) {
    fail(`${variant}.durationMs must be a positive number`);
  }

  if (typeof definition.loop !== "boolean") {
    fail(`${variant}.loop must be a boolean`);
  }

  if (
    definition.mode !== "code-native" &&
    definition.mode !== "dedicated-frame"
  ) {
    fail(`${variant}.mode must be "code-native" or "dedicated-frame"`);
  }

  if (
    definition.reducedMotion !== "static" &&
    definition.reducedMotion !== "settled"
  ) {
    fail(`${variant}.reducedMotion must be "static" or "settled"`);
  }

  if (variant === "onboarding") {
    if (!Number.isFinite(definition.settleMs) || definition.settleMs <= 0) {
      fail("onboarding.settleMs must be a positive number");
    }
  }

  if (variant === "agent-entrance") {
    if (!Number.isFinite(definition.staggerMs) || definition.staggerMs <= 0) {
      fail("agent-entrance.staggerMs must be a positive number");
    }
  }

  const frames = normalizeFrames(variant, definition);
  if (definition.mode === "code-native" && frames.length > 0) {
    fail(`${variant} cannot declare frames when mode is code-native`);
  }

  const normalized = {
    durationMs: definition.durationMs,
    frames,
    loop: definition.loop,
    mode: definition.mode,
    reducedMotion: definition.reducedMotion,
  };

  if (variant === "onboarding") {
    normalized.settleMs = definition.settleMs;
  }

  if (variant === "agent-entrance") {
    normalized.staggerMs = definition.staggerMs;
  }

  return normalized;
}

function normalizeMotionContract(manifest) {
  if (!isObject(manifest.motion)) {
    fail("manifest.motion must exist");
  }

  const { motion } = manifest;
  if (motion.frameSourcePolicy !== "dedicated-frame-or-code-native") {
    fail(
      'motion.frameSourcePolicy must be "dedicated-frame-or-code-native"',
    );
  }

  const supportedKeys = new Set([
    "frameSourcePolicy",
    "variants",
    ...KNOWN_VARIANTS,
  ]);
  for (const key of Object.keys(motion)) {
    if (!supportedKeys.has(key)) {
      fail(`Unknown motion variant or field: ${key}`);
    }
  }

  if (motion.variants !== undefined) {
    if (!Array.isArray(motion.variants)) {
      fail("motion.variants must be an array when provided");
    }

    const unexpectedVariant = motion.variants.find(
      (variant) => !KNOWN_VARIANTS.includes(variant),
    );
    if (unexpectedVariant) {
      fail(`Unknown variant in motion.variants: ${unexpectedVariant}`);
    }
  }

  return {
    frameSourcePolicy: motion.frameSourcePolicy,
    variants: [...KNOWN_VARIANTS],
    loader: normalizeVariant("loader", motion.loader),
    onboarding: normalizeVariant("onboarding", motion.onboarding),
    liveness: normalizeVariant("liveness", motion.liveness),
    pairing: normalizeVariant("pairing", motion.pairing),
    "agent-entrance": normalizeVariant(
      "agent-entrance",
      motion["agent-entrance"],
    ),
  };
}

function writeOutput(outPath, content) {
  if (!outPath) {
    process.stdout.write(content);
    return;
  }

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, content);
}

function main() {
  const { manifestPath, outPath } = parseArgs(process.argv.slice(2));
  const manifest = readJson(manifestPath);
  const normalizedMotion = normalizeMotionContract(manifest);
  writeOutput(outPath, `${JSON.stringify(normalizedMotion, null, 2)}\n`);
}

main();
