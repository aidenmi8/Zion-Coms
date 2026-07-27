import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const desktopRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const repositoryRoot = path.resolve(desktopRoot, "..");
const manifestPath = path.join(
  repositoryRoot,
  "branding/zion-brand-manifest.json",
);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

const REQUIRED_ASSET_OUTPUTS = [
  "desktop/public/branding/sentra-v2-2.png",
  "desktop/public/branding/sentra-v2-3.png",
  "desktop/public/branding/sentra-v2-4.png",
  "desktop/public/branding/sentra-v2-5.png",
  "desktop/public/branding/sentra-v2-6.png",
  "desktop/public/branding/sentra-v2-7.png",
  "desktop/public/branding/sentra-v2-10.png",
  "desktop/public/branding/zion-app-icon-1024.png",
  "desktop/public/branding/zion-app-icon@2x.png",
  "desktop/public/branding/zion-app-icon@3x.png",
  "desktop/public/branding/sentra-dmg-background-1200x800.png",
  "desktop/public/branding/sentra-dmg-background-600x400.png",
  "desktop/public/branding/sentra-wordmark.svg",
  "desktop/public/branding/sentra-lockup-horizontal.svg",
  "desktop/public/branding/sentra-lockup-light.svg",
  "desktop/public/branding/sentra-lockup-dark.svg",
  "desktop/public/branding/zion-mark.svg",
  "desktop/public/branding/sentra-status-glyph.svg",
];

const REQUIRED_ALIAS_OUTPUTS = [
  "desktop/public/app-icon@2x.png",
  "desktop/public/app-icon@3x.png",
  "desktop/public/buzz.svg",
  "desktop/public/landing/buzz-wordmark.png",
  "admin-web/public/zion-mark.svg",
  "admin-web/public/favicon.svg",
  "web/src/assets/zion-app-icon@3x.png",
  "web/src/assets/app-icon@3x.png",
];

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function parseSipsOutput(stdout) {
  const metadata = {};
  for (const line of stdout.split("\n")) {
    const match = line.match(/^\s*(\w+):\s*(.*)$/);
    if (match) metadata[match[1]] = match[2];
  }
  return metadata;
}

function inspectPng(relativePath, filePath, bytes) {
  if (bytes.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a") {
    throw new Error(`Invalid PNG signature: ${relativePath}`);
  }

  const metadata = parseSipsOutput(
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
    format: metadata.format.toLowerCase(),
    width: Number(metadata.pixelWidth),
    height: Number(metadata.pixelHeight),
    hasAlpha: metadata.hasAlpha === "yes",
    colorSpace: metadata.space,
  };
}

function inspectSvg(relativePath, filePath, bytes) {
  const text = bytes.toString("utf8");
  if (!/<svg\b[^>]*>[\s\S]*<\/svg>\s*$/.test(text)) {
    throw new Error(`Invalid SVG root: ${relativePath}`);
  }

  try {
    execFileSync("xmllint", ["--noout", filePath], { stdio: "pipe" });
  } catch (error) {
    const detail =
      error && typeof error === "object" && "stderr" in error
        ? String(error.stderr).trim()
        : String(error);
    throw new Error(`Invalid SVG XML: ${relativePath}: ${detail}`);
  }

  const width = Number(text.match(/\bwidth="([0-9.]+)"/)?.[1]);
  const height = Number(text.match(/\bheight="([0-9.]+)"/)?.[1]);
  if (!Number.isFinite(width) || !Number.isFinite(height)) {
    throw new Error(`SVG is missing numeric dimensions: ${relativePath}`);
  }

  const embeddedPng = text.match(
    /\bhref="data:image\/png;base64,([^"]+)"/,
  )?.[1];
  if (!embeddedPng) {
    throw new Error(`SVG is missing its embedded PNG source: ${relativePath}`);
  }
  const embeddedBytes = Buffer.from(embeddedPng, "base64");
  if (embeddedBytes.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a") {
    throw new Error(`SVG contains an invalid embedded PNG: ${relativePath}`);
  }

  return { format: "svg", width, height };
}

function validateOutput(relativePath, record) {
  const filePath = path.join(repositoryRoot, relativePath);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing Zion asset: ${relativePath}`);
  }

  const bytes = fs.readFileSync(filePath);
  const actual =
    path.extname(relativePath).toLowerCase() === ".png"
      ? inspectPng(relativePath, filePath, bytes)
      : inspectSvg(relativePath, filePath, bytes);

  const expected = {
    format: record.format,
    width: record.width,
    height: record.height,
  };
  for (const [field, expectedValue] of Object.entries(expected)) {
    if (actual[field] !== expectedValue) {
      throw new Error(
        `Metadata mismatch for ${relativePath}: ${field}=${actual[field]}, manifest=${expectedValue}`,
      );
    }
  }

  if (sha256(bytes) !== record.sha256) {
    throw new Error(`SHA-256 mismatch: ${relativePath}`);
  }

  if (actual.format === "png") {
    for (const field of ["hasAlpha", "colorSpace"]) {
      if (actual[field] !== record[field]) {
        throw new Error(
          `Metadata mismatch for ${relativePath}: ${field}=${actual[field]}, manifest=${record[field]}`,
        );
      }
    }
  } else {
    const source = manifest.sources[record.sourceFile];
    if (!source) {
      throw new Error(
        `Missing source provenance for ${relativePath}: ${record.sourceFile}`,
      );
    }
    if (
      record.hasAlpha !== source.hasAlpha ||
      record.colorSpace !== source.colorSpace
    ) {
      throw new Error(`SVG provenance metadata mismatch: ${relativePath}`);
    }
  }
}

const manifestAssetOutputs = Object.values(manifest.assets).map(
  (asset) => asset.outputPath,
);
if (
  JSON.stringify([...manifestAssetOutputs].sort()) !==
  JSON.stringify([...REQUIRED_ASSET_OUTPUTS].sort())
) {
  throw new Error(
    "Manifest asset inventory does not match the complete Task 1 output set",
  );
}

const declaredAliases = new Set();
for (const [assetId, asset] of Object.entries(manifest.assets)) {
  if (!manifest.sources[asset.sourceFile]) {
    throw new Error(
      `Asset ${assetId} references unknown source ${asset.sourceFile}`,
    );
  }
  if (`desktop/public${asset.canonicalPath}` !== asset.outputPath) {
    throw new Error(`Canonical path/output path mismatch for ${assetId}`);
  }
  validateOutput(asset.outputPath, asset);

  for (const aliasPath of asset.aliases) {
    if (declaredAliases.has(aliasPath)) {
      throw new Error(`Duplicate manifest alias: ${aliasPath}`);
    }
    declaredAliases.add(aliasPath);
    const alias = manifest.aliasInventory[aliasPath];
    if (!alias) throw new Error(`Missing alias inventory record: ${aliasPath}`);
    if (alias.sourceAsset !== assetId) {
      throw new Error(`Alias sourceAsset mismatch: ${aliasPath}`);
    }
  }
}

const inventoryAliases = Object.keys(manifest.aliasInventory);
if (
  JSON.stringify([...inventoryAliases].sort()) !==
    JSON.stringify([...REQUIRED_ALIAS_OUTPUTS].sort()) ||
  JSON.stringify([...declaredAliases].sort()) !==
    JSON.stringify([...REQUIRED_ALIAS_OUTPUTS].sort())
) {
  throw new Error(
    "Manifest alias inventory does not match the complete Task 1 alias set",
  );
}

for (const aliasPath of REQUIRED_ALIAS_OUTPUTS) {
  validateOutput(aliasPath, manifest.aliasInventory[aliasPath]);
}

console.log(
  `Validated ${manifestAssetOutputs.length} canonical assets and ${inventoryAliases.length} aliases.`,
);
console.log(
  "Animation frame pack: pending supplied frame inventory; CSS fallback active.",
);
