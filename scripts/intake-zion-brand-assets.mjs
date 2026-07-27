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
    sourceSubdir: "",
  },
  "Logos-sentra-v2-3.png": {
    sourceSubdir: "",
  },
  "Logos-sentra-v2-4.png": {
    sourceSubdir: "",
  },
  "Logos-sentra-v2-5.png": {
    sourceSubdir: "",
  },
  "Logos-sentra-v2-6.png": {
    sourceSubdir: "",
  },
  "Logos-sentra-v2-7.png": {
    sourceSubdir: "",
  },
  "Logos-sentra-v2-8.png": {
    sourceSubdir: "",
  },
  "Logos-sentra-v2-9.png": {
    sourceSubdir: "",
  },
  "Logos-sentra-v2-10.png": {
    sourceSubdir: "",
  },
  "logo-TW-wordmark.png": {
    sourceSubdir: "transparent -logos",
  },
  "logo-TW2-wordmark.png": {
    sourceSubdir: "transparent -logos",
  },
  "logo-TB-wordmark.png": {
    sourceSubdir: "transparent -logos",
  },
};

const REFERENCE_SOURCES = [
  "Logos-sentra-v2-1.png",
  "sentra-agent-ARQ-and Agents.png",
  "sentra-logo-branding -jul-2026.png",
];

const OUTPUT_ASSET_SPECS = [
  {
    id: "sentraV2_2",
    sourceFile: "Logos-sentra-v2-2.png",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-2.png",
    outputPath: "desktop/public/branding/sentra-v2-2.png",
    strategy: { kind: "copy" },
    aliases: [],
  },
  {
    id: "sentraV2_3",
    sourceFile: "Logos-sentra-v2-3.png",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-3.png",
    outputPath: "desktop/public/branding/sentra-v2-3.png",
    strategy: { kind: "copy" },
    aliases: [],
  },
  {
    id: "sentraV2_4",
    sourceFile: "Logos-sentra-v2-4.png",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-4.png",
    outputPath: "desktop/public/branding/sentra-v2-4.png",
    strategy: { kind: "copy" },
    aliases: [],
  },
  {
    id: "sentraV2_5",
    sourceFile: "Logos-sentra-v2-5.png",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-5.png",
    outputPath: "desktop/public/branding/sentra-v2-5.png",
    strategy: { kind: "copy" },
    aliases: [],
  },
  {
    id: "sentraV2_6",
    sourceFile: "Logos-sentra-v2-6.png",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-6.png",
    outputPath: "desktop/public/branding/sentra-v2-6.png",
    strategy: { kind: "copy" },
    aliases: [],
  },
  {
    id: "sentraV2_7",
    sourceFile: "Logos-sentra-v2-7.png",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-7.png",
    outputPath: "desktop/public/branding/sentra-v2-7.png",
    strategy: { kind: "copy" },
    aliases: [],
  },
  {
    id: "appIcon",
    sourceFile: "Logos-sentra-v2-8.png",
    role: "appIcon",
    canonicalPath: "/branding/zion-app-icon-1024.png",
    outputPath: "desktop/public/branding/zion-app-icon-1024.png",
    strategy: { kind: "resize", width: 1024, height: 1024 },
    aliases: [],
    compatibilityPaths: ["/app-icon@2x.png", "/app-icon@3x.png"],
  },
  {
    id: "appIcon2x",
    sourceFile: "Logos-sentra-v2-8.png",
    role: "appIcon",
    canonicalPath: "/branding/zion-app-icon@2x.png",
    outputPath: "desktop/public/branding/zion-app-icon@2x.png",
    strategy: { kind: "resize", width: 2048, height: 2048 },
    aliases: [
      {
        path: "desktop/public/app-icon@2x.png",
        publicPath: "/app-icon@2x.png",
      },
    ],
  },
  {
    id: "appIcon3x",
    sourceFile: "Logos-sentra-v2-8.png",
    role: "appIcon",
    canonicalPath: "/branding/zion-app-icon@3x.png",
    outputPath: "desktop/public/branding/zion-app-icon@3x.png",
    strategy: { kind: "resize", width: 3072, height: 3072 },
    aliases: [
      {
        path: "desktop/public/app-icon@3x.png",
        publicPath: "/app-icon@3x.png",
      },
      {
        path: "web/src/assets/zion-app-icon@3x.png",
      },
      {
        path: "web/src/assets/app-icon@3x.png",
      },
    ],
  },
  {
    id: "dmgBackground",
    sourceFile: "Logos-sentra-v2-9.png",
    role: "dmgBackground",
    canonicalPath: "/branding/sentra-dmg-background-1200x800.png",
    outputPath: "desktop/public/branding/sentra-dmg-background-1200x800.png",
    strategy: { kind: "resize", width: 1200, height: 800 },
    aliases: [],
  },
  {
    id: "dmgBackgroundSmall",
    sourceFile: "Logos-sentra-v2-9.png",
    role: "dmgBackground",
    canonicalPath: "/branding/sentra-dmg-background-600x400.png",
    outputPath: "desktop/public/branding/sentra-dmg-background-600x400.png",
    strategy: { kind: "resize", width: 600, height: 400 },
    aliases: [],
  },
  {
    id: "sentraV2_10",
    sourceFile: "Logos-sentra-v2-10.png",
    role: "sentraV2",
    canonicalPath: "/branding/sentra-v2-10.png",
    outputPath: "desktop/public/branding/sentra-v2-10.png",
    strategy: { kind: "copy" },
    aliases: [],
  },
  {
    id: "sentraWordmark",
    sourceFile: "logo-TW-wordmark.png",
    role: "sentraWordmark",
    canonicalPath: "/branding/sentra-wordmark.svg",
    outputPath: "desktop/public/branding/sentra-wordmark.svg",
    strategy: { kind: "svg-wrapper", label: "Zion wordmark" },
    aliases: [
      {
        path: "desktop/public/landing/buzz-wordmark.png",
        source: "logo-TW-wordmark.png",
        publicPath: "/landing/buzz-wordmark.png",
      },
    ],
  },
  {
    id: "sentraLockup",
    sourceFile: "logo-TW2-wordmark.png",
    role: "sentraLockup",
    canonicalPath: "/branding/sentra-lockup-horizontal.svg",
    outputPath: "desktop/public/branding/sentra-lockup-horizontal.svg",
    strategy: { kind: "svg-wrapper", label: "Sentra lockup" },
    aliases: [],
  },
  {
    id: "sentraLockupLight",
    sourceFile: "logo-TW2-wordmark.png",
    role: "sentraLockupLight",
    canonicalPath: "/branding/sentra-lockup-light.svg",
    outputPath: "desktop/public/branding/sentra-lockup-light.svg",
    strategy: {
      kind: "copy-output",
      source: "desktop/public/branding/sentra-lockup-horizontal.svg",
    },
    aliases: [],
  },
  {
    id: "sentraLockupDark",
    sourceFile: "logo-TB-wordmark.png",
    role: "sentraLockupDark",
    canonicalPath: "/branding/sentra-lockup-dark.svg",
    outputPath: "desktop/public/branding/sentra-lockup-dark.svg",
    strategy: { kind: "svg-wrapper", label: "Sentra lockup dark" },
    aliases: [],
  },
  {
    id: "zionMark",
    sourceFile: MARK_SOURCE_NAME,
    role: "mark",
    canonicalPath: "/branding/zion-mark.svg",
    outputPath: "desktop/public/branding/zion-mark.svg",
    strategy: { kind: "svg-wrapper", label: "Zion mark" },
    aliases: [
      {
        path: "desktop/public/buzz.svg",
        publicPath: "/buzz.svg",
      },
      {
        path: "admin-web/public/zion-mark.svg",
        publicPath: "/zion-mark.svg",
      },
      {
        path: "admin-web/public/favicon.svg",
        publicPath: "/favicon.svg",
      },
    ],
    compatibilityPaths: ["/buzz.svg", "/favicon.svg"],
  },
  {
    id: "sentraStatusGlyph",
    sourceFile: MARK_SOURCE_NAME,
    role: "status",
    canonicalPath: "/branding/sentra-status-glyph.svg",
    outputPath: "desktop/public/branding/sentra-status-glyph.svg",
    strategy: { kind: "svg-wrapper", label: "Sentra status glyph" },
    aliases: [],
  },
];

function parseSipsOutput(stdout) {
  const map = {};
  for (const line of stdout.split("\n")) {
    const match = line.match(/^\s*(\w+):\s*(.*)$/);
    if (match) {
      map[match[1]] = match[2];
    }
  }

  return map;
}

function readPngMetadata(filePath) {
  const map = parseSipsOutput(
    execFileSync(
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
        filePath,
      ],
      { encoding: "utf8" },
    ),
  );

  return {
    width: Number(map.pixelWidth),
    height: Number(map.pixelHeight),
    hasAlpha: map.hasAlpha === "yes",
    format: map.format.toLowerCase(),
    colorSpace: map.space,
  };
}

function readSvgMetadata(filePath, sourceMetadata) {
  const text = fs.readFileSync(filePath, "utf8");
  if (!/<svg\b[^>]*>[\s\S]*<\/svg>\s*$/.test(text)) {
    throw new Error(`Invalid generated SVG: ${filePath}`);
  }
  const widthMatch = text.match(/\bwidth="([0-9.]+)"/);
  const heightMatch = text.match(/\bheight="([0-9.]+)"/);

  return {
    width: Number(widthMatch?.[1] ?? sourceMetadata.width),
    height: Number(heightMatch?.[1] ?? sourceMetadata.height),
    hasAlpha: sourceMetadata.hasAlpha,
    format: "svg",
    colorSpace: sourceMetadata.colorSpace,
  };
}

function readOutputMetadata(filePath, sourceMetadata) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".png") {
    return readPngMetadata(filePath);
  }
  if (ext === ".svg") {
    return readSvgMetadata(filePath, sourceMetadata);
  }

  throw new Error(`Unsupported output extension: ${filePath}`);
}

function sha256(filePath) {
  return createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function copyFile(sourcePath, destinationPath) {
  ensureParent(destinationPath);
  fs.copyFileSync(sourcePath, destinationPath);
}

function writePng(sourcePath, destinationPath, width, height) {
  ensureParent(destinationPath);
  execFileSync("sips", ["-z", String(height), String(width), sourcePath, "--out", destinationPath]);
}

function writeWrapper(sourcePath, destinationPath, sourceMetadata, label) {
  const pngBytes = fs.readFileSync(sourcePath).toString("base64");
  const svg = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<svg xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${label}" viewBox="0 0 ${sourceMetadata.width} ${sourceMetadata.height}" width="${sourceMetadata.width}" height="${sourceMetadata.height}">`,
    `<image href="data:image/png;base64,${pngBytes}" width="${sourceMetadata.width}" height="${sourceMetadata.height}"/>`,
    "</svg>",
    "",
  ].join("\n");

  ensureParent(destinationPath);
  fs.writeFileSync(destinationPath, svg);
}

function normalizeOutputPath(outputPath) {
  if (outputPath.startsWith("/")) {
    return path.join(ROOT, "desktop/public", outputPath.replace(/^\//, ""));
  }

  return path.join(ROOT, outputPath);
}

function resolveSourcePath(sourceFileName) {
  const subdir = SHIPPED_SOURCES[sourceFileName]?.sourceSubdir;
  return subdir ? path.join(sourceDirectory, subdir, sourceFileName) : path.join(sourceDirectory, sourceFileName);
}

function resolveAliasSource(aliasSource, canonicalPath, sourceMetadataByName) {
  if (!aliasSource) {
    return canonicalPath;
  }

  const sourceMetadata = sourceMetadataByName.get(aliasSource);
  if (sourceMetadata) {
    return sourceMetadata.sourcePath;
  }

  if (aliasSource.endsWith(".png")) {
    return normalizeOutputPath(aliasSource);
  }

  return path.join(ROOT, aliasSource);
}

function writeAsset(assetSpec, sourceMetadataByName) {
  const sourceMetadata = sourceMetadataByName.get(assetSpec.sourceFile);
  if (!sourceMetadata) {
    throw new Error(`Missing source metadata for asset source file ${assetSpec.sourceFile}`);
  }

  const sourcePath = sourceMetadata.sourcePath;
  const canonicalOutputPath = normalizeOutputPath(assetSpec.outputPath);

  switch (assetSpec.strategy.kind) {
    case "copy":
      copyFile(sourcePath, canonicalOutputPath);
      break;
    case "resize":
      writePng(
        sourcePath,
        canonicalOutputPath,
        assetSpec.strategy.width,
        assetSpec.strategy.height,
      );
      break;
    case "svg-wrapper":
      writeWrapper(
        sourcePath,
        canonicalOutputPath,
        sourceMetadata,
        assetSpec.strategy.label ?? "Zion brand asset",
      );
      break;
    case "copy-output":
      copyFile(
        normalizeOutputPath(assetSpec.strategy.source),
        canonicalOutputPath,
      );
      break;
    default:
      throw new Error(`Unknown asset strategy for ${assetSpec.id}: ${assetSpec.strategy.kind}`);
  }

  if (assetSpec.aliases?.length) {
    for (const alias of assetSpec.aliases) {
      const aliasEntry = typeof alias === "string" ? { path: alias } : alias;
      const aliasTarget = resolveAliasSource(
        aliasEntry.source,
        canonicalOutputPath,
        sourceMetadataByName,
      );
      if (!aliasTarget) {
        throw new Error(`Unable to resolve alias source for ${assetSpec.id} alias ${aliasEntry.path}`);
      }

      const aliasPath = normalizeOutputPath(aliasEntry.path);
      copyFile(aliasTarget, aliasPath);
    }
  }
}

function buildManifestAsset(assetSpec, sourceMetadataByName) {
  const sourceMetadata = sourceMetadataByName.get(assetSpec.sourceFile);
  if (!sourceMetadata) {
    throw new Error(`Missing source metadata for asset ${assetSpec.id}`);
  }

  const canonicalOutputPath = normalizeOutputPath(assetSpec.outputPath);
  const outputMetadata = readOutputMetadata(canonicalOutputPath, sourceMetadata);

  return {
    role: assetSpec.role,
    canonicalPath: assetSpec.canonicalPath,
    outputPath: assetSpec.outputPath,
    aliases: (assetSpec.aliases ?? []).map((alias) =>
      typeof alias === "string" ? alias : alias.path,
    ),
    sourceFile: assetSpec.sourceFile,
    format: outputMetadata.format,
    sha256: sha256(canonicalOutputPath),
    width: outputMetadata.width,
    height: outputMetadata.height,
    hasAlpha: outputMetadata.hasAlpha,
    colorSpace: outputMetadata.colorSpace,
    ...(assetSpec.compatibilityPaths ? { compatibilityPaths: assetSpec.compatibilityPaths } : {}),
  };
}

function buildAliasInventory(assetSpec, sourceMetadataByName) {
  const sourceMetadata = sourceMetadataByName.get(assetSpec.sourceFile);
  if (!sourceMetadata) {
    throw new Error(`Missing source metadata for alias inventory ${assetSpec.id}`);
  }

  return Object.fromEntries(
    (assetSpec.aliases ?? []).map((alias) => {
      const aliasEntry = typeof alias === "string" ? { path: alias } : alias;
      const aliasPath = normalizeOutputPath(aliasEntry.path);
      const outputMetadata = readOutputMetadata(aliasPath, sourceMetadata);
      return [
        aliasEntry.path,
        {
          sourceAsset: assetSpec.id,
          sourceFile: assetSpec.sourceFile,
          ...(aliasEntry.publicPath ? { publicPath: aliasEntry.publicPath } : {}),
          format: outputMetadata.format,
          sha256: sha256(aliasPath),
          width: outputMetadata.width,
          height: outputMetadata.height,
          hasAlpha: outputMetadata.hasAlpha,
          colorSpace: outputMetadata.colorSpace,
        },
      ];
    }),
  );
}

function writeManifest(manifest) {
  const manifestJson = JSON.stringify(manifest, null, 2) + "\n";
  const tempPath = `${MANIFEST_PATH}.tmp`;
  ensureParent(tempPath);
  fs.writeFileSync(tempPath, manifestJson);
  fs.renameSync(tempPath, MANIFEST_PATH);
}

function assertSourceReadable(directory) {
  try {
    return fs.readdirSync(directory);
  } catch (error) {
    const cause = error instanceof Error ? `${error.message}` : String(error);
    throw new Error(`${directory}: ${cause}`);
  }
}

function main() {
  const normalizedSourceDirectory = path.resolve(sourceDirectory);

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

  const sourceMetadataByName = new Map();
  for (const sourceFileName of requiredSourceNames) {
    const sourcePath = resolveSourcePath(sourceFileName);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Missing required source file: ${sourcePath}`);
    }

    const sourceMetadata = readPngMetadata(sourcePath);
    const disposition = Object.hasOwn(SHIPPED_SOURCES, sourceFileName)
      ? "shipped"
      : "reference-only";

    sourceMetadataByName.set(sourceFileName, {
      ...sourceMetadata,
      sha256: sha256(sourcePath),
      sourcePath,
      disposition,
    });
  }

  const markSource = sourceMetadataByName.get(MARK_SOURCE_NAME);
  if (!markSource) {
    throw new Error(`Missing required mark source file: ${MARK_SOURCE_NAME}`);
  }

  for (const assetSpec of OUTPUT_ASSET_SPECS) {
    writeAsset(assetSpec, sourceMetadataByName);
  }

  const assets = {};
  for (const assetSpec of OUTPUT_ASSET_SPECS) {
    assets[assetSpec.id] = buildManifestAsset(assetSpec, sourceMetadataByName);
  }

  const aliasInventory = Object.assign(
    {},
    ...OUTPUT_ASSET_SPECS.map((assetSpec) =>
      buildAliasInventory(assetSpec, sourceMetadataByName),
    ),
  );

  const sources = Object.fromEntries(
    [...sourceMetadataByName.entries()].map(([sourceFileName, sourceMetadata]) => [
      sourceFileName,
      {
        disposition: sourceMetadata.disposition,
        relativePath: path.relative(normalizedSourceDirectory, sourceMetadata.sourcePath),
        format: sourceMetadata.format,
        sha256: sourceMetadata.sha256,
        width: sourceMetadata.width,
        height: sourceMetadata.height,
        hasAlpha: sourceMetadata.hasAlpha,
        colorSpace: sourceMetadata.colorSpace,
      },
    ]),
  );

  const manifest = {
    version: 1,
    sourceDirectory: normalizedSourceDirectory,
    assets,
    aliasInventory,
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
