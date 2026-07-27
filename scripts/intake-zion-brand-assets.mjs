#!/usr/bin/env node

import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const DEFAULT_SOURCE_DIR =
  "/Users/Aiden-Mi8/Library/Mobile Documents/com~apple~CloudDocs/SENTRA-MAIN/logo and media";
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST_PATH = path.join(ROOT, "branding", "zion-brand-manifest.json");

const sourceDirectory = process.env.ZION_BRAND_SOURCE_DIR || DEFAULT_SOURCE_DIR;

const MARK_SOURCE_NAME = "Logos-sentra-v2-2.png";

const SHIPPED_SOURCES = {
  "Logos-sentra-v2-2.png": {
    assetId: "sentraV2_2",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-2.png",
    aliases: [],
    sourceSubdir: "",
  },
  "Logos-sentra-v2-3.png": {
    assetId: "sentraV2_3",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-3.png",
    aliases: [],
    sourceSubdir: "",
  },
  "Logos-sentra-v2-4.png": {
    assetId: "sentraV2_4",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-4.png",
    aliases: [],
    sourceSubdir: "",
  },
  "Logos-sentra-v2-5.png": {
    assetId: "sentraV2_5",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-5.png",
    aliases: [],
    sourceSubdir: "",
  },
  "Logos-sentra-v2-6.png": {
    assetId: "sentraV2_6",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-6.png",
    aliases: [],
    sourceSubdir: "",
  },
  "Logos-sentra-v2-7.png": {
    assetId: "sentraV2_7",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-7.png",
    aliases: [],
    sourceSubdir: "",
  },
  "Logos-sentra-v2-8.png": {
    assetId: "appIcon",
    role: "appIcon",
    canonicalPath: "/branding/zion-app-icon-1024.png",
    canonicalDimensions: { width: 1024, height: 1024 },
    aliases: [
      "/app-icon@2x.png",
      "/app-icon@3x.png",
      "web/src/assets/zion-app-icon@3x.png",
      "web/src/assets/app-icon@3x.png",
    ],
    aliasSourceMap: {
      "/app-icon@2x.png": "desktop/public/branding/zion-app-icon@2x.png",
      "/app-icon@3x.png": "desktop/public/branding/zion-app-icon@3x.png",
      "web/src/assets/zion-app-icon@3x.png":
        "desktop/public/branding/zion-app-icon@3x.png",
      "web/src/assets/app-icon@3x.png":
        "desktop/public/branding/zion-app-icon@3x.png",
    },
    derivatives: [
      {
        path: "desktop/public/branding/zion-app-icon@2x.png",
        width: 2048,
        height: 2048,
      },
      {
        path: "desktop/public/branding/zion-app-icon@3x.png",
        width: 3072,
        height: 3072,
      },
    ],
    sourceSubdir: "",
  },
  "Logos-sentra-v2-9.png": {
    assetId: "dmgBackground",
    role: "dmgBackground",
    canonicalPath: "/branding/sentra-dmg-background-1200x800.png",
    canonicalDimensions: { width: 1200, height: 800 },
    aliases: ["/branding/sentra-dmg-background-600x400.png"],
    aliasSourceMap: {
      "/branding/sentra-dmg-background-600x400.png":
        "desktop/public/branding/sentra-dmg-background-600x400.png",
    },
    derivatives: [
      {
        path: "desktop/public/branding/sentra-dmg-background-600x400.png",
        width: 600,
        height: 400,
      },
    ],
    sourceSubdir: "",
  },
  "Logos-sentra-v2-10.png": {
    assetId: "sentraV2_10",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-10.png",
    aliases: [],
    sourceSubdir: "",
  },
  "logo-TW-wordmark.png": {
    assetId: "sentraWordmark",
    role: "sentraWordmark",
    canonicalPath: "/branding/sentra-wordmark.svg",
    aliases: ["desktop/public/landing/buzz-wordmark.png"],
    wrappers: ["desktop/public/branding/sentra-wordmark.svg"],
    sourceSubdir: "transparent -logos",
  },
  "logo-TW2-wordmark.png": {
    assetId: "sentraLockup",
    role: "sentraLockup",
    canonicalPath: "/branding/sentra-lockup-horizontal.svg",
    aliases: ["/branding/sentra-lockup-light.svg"],
    wrappers: [
      "desktop/public/branding/sentra-lockup-horizontal.svg",
      "desktop/public/branding/sentra-lockup-light.svg",
    ],
    sourceSubdir: "transparent -logos",
  },
  "logo-TB-wordmark.png": {
    assetId: "sentraLockupDark",
    role: "sentraLockupDark",
    canonicalPath: "/branding/sentra-lockup-dark.svg",
    aliases: [],
    wrappers: ["desktop/public/branding/sentra-lockup-dark.svg"],
    sourceSubdir: "transparent -logos",
  },
};

const REFERENCE_SOURCES = [
  "Logos-sentra-v2-1.png",
  "sentra-agent-ARQ-and Agents.png",
  "sentra-logo-branding -jul-2026.png",
];

function readSipsMetadata(sourcePath) {
  const stdout = execFileSync(
    "sips",
    [
      "-g",
      "pixelWidth",
      "-g",
      "pixelHeight",
      "-g",
      "hasAlpha",
      "-g",
      "format",
      "-g",
      "space",
      sourcePath,
    ],
    { encoding: "utf8" },
  );

  const map = {};
  for (const line of stdout.split("\n")) {
    const match = line.match(/^\s*(\w+):\s*(.*)$/);
    if (match) map[match[1]] = match[2];
  }

  return {
    width: Number(map.pixelWidth),
    height: Number(map.pixelHeight),
    hasAlpha: map.hasAlpha === "yes",
    sourceFormat: map.format,
    colorSpace: map.space,
  };
}

function sha256(filePath) {
  return createHash("sha256")
    .update(fs.readFileSync(filePath))
    .digest("hex");
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function copyFile(sourcePath, destPath) {
  ensureParent(destPath);
  fs.copyFileSync(sourcePath, destPath);
}

function resizePng(sourcePath, destinationPath, width, height) {
  ensureParent(destinationPath);
  execFileSync("sips", ["-z", String(height), String(width), sourcePath, "--out", destinationPath]);
}

function writeSvgWrapper(sourcePath, destinationPath, label) {
  const { width, height } = readSipsMetadata(sourcePath);
  const png = fs.readFileSync(sourcePath).toString("base64");
  const svg = [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<svg xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${label}" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}">`,
    `<image href="data:image/png;base64,${png}" width="${width}" height="${height}"/>`,
    `</svg>`,
    "",
  ].join("\n");
  ensureParent(destinationPath);
  fs.writeFileSync(destinationPath, svg);
}

function toRepoPath(filePath) {
  if (filePath.startsWith("/")) {
    if (filePath.startsWith("/branding/")) {
      filePath = `desktop/public${filePath}`;
    } else {
      filePath = `desktop/public${filePath}`;
    }
  }
  return path.join(ROOT, filePath);
}

function canonicalToRepoPath(canonicalPath) {
  return toRepoPath(`desktop/public${canonicalPath}`);
}

function outputAliasPath(aliasPath) {
  if (aliasPath.startsWith("/")) {
    return toRepoPath(aliasPath);
  }

  return path.join(ROOT, aliasPath);
}

function buildAssetRecord(sourceFileName, spec, sourceMetadata) {
  return {
    role: spec.role,
    canonicalPath: spec.canonicalPath,
    aliases: spec.aliases,
    sourceFile: sourceFileName,
    sourceFormat: sourceMetadata.sourceFormat,
    sha256: sourceMetadata.sha256,
    width: sourceMetadata.width,
    height: sourceMetadata.height,
    hasAlpha: sourceMetadata.hasAlpha,
    colorSpace: sourceMetadata.colorSpace,
  };
}

function writeManifest(manifest) {
  const manifestJson = JSON.stringify(manifest, null, 2) + "\n";
  const tempPath = `${MANIFEST_PATH}.tmp`;
  ensureParent(tempPath);
  fs.writeFileSync(tempPath, manifestJson);
  fs.renameSync(tempPath, MANIFEST_PATH);
}

function normalizeRootPath(inputPath) {
  return path.resolve(inputPath);
}

function assertSourceReadable(directory) {
  try {
    return fs.readdirSync(directory);
  } catch (error) {
    const cause = error instanceof Error ? `${error.message}` : String(error);
    throw new Error(`${directory}: ${cause}`);
  }
}

function resolveSourcePath(sourceFileName, sourceSubdir) {
  if (sourceSubdir) {
    return path.join(sourceDirectory, sourceSubdir, sourceFileName);
  }

  return path.join(sourceDirectory, sourceFileName);
}

function writeRequiredFiles(sourcePath, spec) {
  const canonicalPath = canonicalToRepoPath(spec.canonicalPath);
  if (spec.wrappers?.length) {
    for (const wrapperPath of spec.wrappers) {
      writeSvgWrapper(sourcePath, path.join(ROOT, wrapperPath), spec.role);
    }
  } else if (spec.canonicalDimensions) {
    resizePng(
      sourcePath,
      canonicalPath,
      spec.canonicalDimensions.width,
      spec.canonicalDimensions.height,
    );
  } else {
    copyFile(sourcePath, canonicalPath);
  }

  if (Array.isArray(spec.derivatives)) {
    for (const derivative of spec.derivatives) {
      resizePng(sourcePath, path.join(ROOT, derivative.path), derivative.width, derivative.height);
    }
  }

  for (const aliasPath of spec.aliases ?? []) {
    const aliasSourcePath = spec.aliasSourceMap?.[aliasPath];
    const copySource = aliasSourcePath
      ? path.join(ROOT, aliasSourcePath)
      : sourcePath;
    copyFile(copySource, outputAliasPath(aliasPath));
  }
}

function writeMarkAliasOutputs(markSourcePath) {
  const markCanonicalPath = path.join(ROOT, "desktop/public/branding/zion-mark.svg");
  const buzzAliasPath = path.join(ROOT, "desktop/public/buzz.svg");
  const adminMarkAliasPath = path.join(ROOT, "admin-web/public/zion-mark.svg");
  const adminFaviconAliasPath = path.join(ROOT, "admin-web/public/favicon.svg");

  writeSvgWrapper(markSourcePath, markCanonicalPath, "Zion mark");
  writeSvgWrapper(
    markSourcePath,
    path.join(ROOT, "desktop/public/branding/sentra-status-glyph.svg"),
    "Sentra status glyph",
  );
  for (const alias of [buzzAliasPath, adminMarkAliasPath, adminFaviconAliasPath]) {
    copyFile(markCanonicalPath, alias);
  }
}

function main() {
  const normalizedSourceDirectory = normalizeRootPath(sourceDirectory);

  if (!fs.existsSync(normalizedSourceDirectory)) {
    throw new Error(
      `${normalizedSourceDirectory}: ENOENT: no such file or directory, stat '${normalizedSourceDirectory}'`,
    );
  }

  assertSourceReadable(normalizedSourceDirectory);
  const requiredSourceNames = new Set([
    ...Object.keys(SHIPPED_SOURCES),
    ...REFERENCE_SOURCES,
  ]);

  const requiredList = [...requiredSourceNames];
  const sourceMetadataByName = new Map();

  for (const sourceFileName of requiredList) {
    const spec = SHIPPED_SOURCES[sourceFileName];
    const sourceSubdir = spec?.sourceSubdir ?? "";
    const sourcePath = resolveSourcePath(sourceFileName, sourceSubdir);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Missing required source file: ${sourcePath}`);
    }

    const { width, height, hasAlpha, sourceFormat, colorSpace } = readSipsMetadata(sourcePath);
    const sha = sha256(sourcePath);
    const disposition = Object.hasOwn(SHIPPED_SOURCES, sourceFileName)
      ? "shipped"
      : "reference-only";

    sourceMetadataByName.set(sourceFileName, {
      width,
      height,
      hasAlpha,
      sourceFormat,
      colorSpace,
      sha256: sha,
      disposition,
      sourcePath,
      sourceSubdir: spec?.sourceSubdir,
    });
  }

  const assets = {};

  for (const [sourceFileName, spec] of Object.entries(SHIPPED_SOURCES)) {
    const source = sourceMetadataByName.get(sourceFileName);
    if (!source) {
      throw new Error(`Missing source metadata for shipped file: ${sourceFileName}`);
    }

    writeRequiredFiles(source.sourcePath, spec);
    assets[spec.assetId] = buildAssetRecord(sourceFileName, spec, source);
  }

  const markSource = sourceMetadataByName.get(MARK_SOURCE_NAME);
  if (!markSource) {
    throw new Error(`Missing required mark source file: ${MARK_SOURCE_NAME}`);
  }
  writeMarkAliasOutputs(markSource.sourcePath);

  assets.webAppIcon = {
    role: "webAppIcon",
    canonicalPath: "/branding/zion-app-icon-1024.png",
    aliases: ["web/src/assets/app-icon@3x.png"],
    sourceFile: "Logos-sentra-v2-8.png",
    sourceFormat: assets.appIcon.sourceFormat,
    sha256: assets.appIcon.sha256,
    width: assets.appIcon.width,
    height: assets.appIcon.height,
    hasAlpha: assets.appIcon.hasAlpha,
    colorSpace: assets.appIcon.colorSpace,
  };

  assets.adminMark = {
    role: "adminMark",
    canonicalPath: "/branding/zion-mark.svg",
    aliases: ["admin-web/public/favicon.svg"],
    sourceFile: MARK_SOURCE_NAME,
    sourceFormat: markSource.sourceFormat,
    sha256: markSource.sha256,
    width: markSource.width,
    height: markSource.height,
    hasAlpha: markSource.hasAlpha,
    colorSpace: markSource.colorSpace,
  };

  const sources = Object.fromEntries(
    [...sourceMetadataByName.entries()].map(([sourceFileName, metadata]) => [
      sourceFileName,
      {
        disposition: metadata.disposition,
      },
    ]),
  );

  const manifest = {
    version: 1,
    sourceDirectory: normalizedSourceDirectory,
    assets,
    sources,
    motion: {
      frameSourcePolicy: "dedicated-frame-or-code-native",
      variants: ["loader", "onboarding", "liveness", "pairing", "agent-entrance"],
      loader: {
        durationMs: 1800,
        loop: true,
        mode: "code-native",
        reducedMotion: "static",
      },
      onboarding: {
        durationMs: 900,
        settleMs: 2400,
        loop: false,
        mode: "code-native",
        reducedMotion: "settled",
      },
      liveness: {
        durationMs: 1400,
        loop: true,
        mode: "code-native",
        reducedMotion: "static",
      },
      pairing: {
        durationMs: 1800,
        loop: false,
        mode: "code-native",
        reducedMotion: "settled",
      },
      "agent-entrance": {
        durationMs: 900,
        staggerMs: 320,
        loop: false,
        mode: "code-native",
        reducedMotion: "settled",
      },
    },
  };

  writeManifest(manifest);
  console.log(`Wrote ${MANIFEST_PATH}`);
}

main();
