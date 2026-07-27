#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = path.resolve(SCRIPT_DIR, "..");
const ALLOWLIST_PATH = path.join(SCRIPT_DIR, "visible-brand-allowlist.json");

function normalizePath(filePath) {
  return filePath.split(path.sep).join("/").replace(/^\.\//, "");
}

function lineNumberAt(text, index) {
  return text.slice(0, index).split("\n").length;
}

function replaceEmbeddedData(text) {
  return text.replace(/data:[^,\s]+;base64,[A-Za-z0-9+/=\r\n]+/g, (match) =>
    match.replace(/[^\r\n]/g, " "),
  );
}

function stripComments(text) {
  let output = "";
  let state = "code";
  let quote = null;
  let escaped = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    const next = text[index + 1];

    if (state === "line-comment") {
      if (character === "\n") {
        output += character;
        state = "code";
      } else {
        output += " ";
      }
      continue;
    }

    if (state === "block-comment") {
      if (character === "*" && next === "/") {
        output += "  ";
        index += 1;
      } else if (character === "\n") {
        output += "\n";
      } else {
        output += " ";
      }
      continue;
    }

    if (state === "string") {
      output += character;
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === quote) {
        state = "code";
        quote = null;
      }
      continue;
    }

    if (character === "'" || character === '"' || character === "`") {
      output += character;
      state = "string";
      quote = character;
      escaped = false;
    } else if (character === "/" && next === "/") {
      output += "  ";
      index += 1;
      state = "line-comment";
    } else if (character === "/" && next === "*") {
      output += "  ";
      index += 1;
      state = "block-comment";
    } else {
      output += character;
    }
  }

  return output;
}

function sanitizeSource(text) {
  return stripComments(replaceEmbeddedData(text));
}

function compilePattern(descriptor) {
  const flags = descriptor.flags?.includes("g")
    ? descriptor.flags
    : `${descriptor.flags ?? ""}g`;
  return new RegExp(descriptor.pattern, flags);
}

function findPatternHits(text, filePath, descriptor) {
  const hits = [];
  const pattern = compilePattern(descriptor);

  for (const match of text.matchAll(pattern)) {
    if (match.index === undefined) continue;
    hits.push({
      file: filePath,
      line: lineNumberAt(text, match.index),
      match: match[0],
      name: descriptor.name,
      reason: descriptor.reason,
      index: match.index,
      length: match[0].length,
    });
  }

  return hits;
}

function maskHits(text, hits) {
  if (hits.length === 0) return text;
  const characters = text.split("");
  for (const hit of hits) {
    for (let offset = 0; offset < hit.length; offset += 1) {
      if (characters[hit.index + offset] !== "\n") {
        characters[hit.index + offset] = " ";
      }
    }
  }
  return characters.join("");
}

function matchesLegacyAssetPath(filePath, allowlist) {
  const normalized = `/${normalizePath(filePath)}`;
  for (const alias of allowlist.legacyAssetPaths ?? []) {
    const normalizedAlias = alias.startsWith("/") ? alias : `/${alias}`;
    if (normalized.endsWith(normalizedAlias)) {
      return {
        name: "LEGACY_ASSET_PATH",
        match: normalizedAlias,
        line: 1,
        reason: "legacy asset URL alias",
        file: filePath,
        index: -1,
        length: 0,
      };
    }
  }

  for (const entry of allowlist.compatibilityAssetPaths ?? []) {
    if (normalizePath(filePath) === normalizePath(entry.path)) {
      return {
        name: "COMPATIBILITY_ASSET_PATH",
        match: entry.path,
        line: 1,
        reason: entry.reason,
        file: filePath,
        index: -1,
        length: 0,
      };
    }
  }

  return null;
}

function internalPathReason(filePath, allowlist) {
  const normalized = normalizePath(filePath);
  const prefix = (allowlist.internalPaths ?? []).find((candidate) => {
    const normalizedCandidate = normalizePath(candidate).replace(/\/$/, "");
    return (
      normalized === normalizedCandidate ||
      normalized.startsWith(`${normalizedCandidate}/`)
    );
  });
  return prefix ? `explicit internal compatibility path: ${prefix}` : null;
}

export function scanText(source, filePath, allowlist) {
  const normalizedFilePath = normalizePath(filePath);
  const protectedHits = [];
  const aliasHit = matchesLegacyAssetPath(normalizedFilePath, allowlist);
  if (aliasHit) protectedHits.push(aliasHit);

  const sanitized = sanitizeSource(source);
  const patternHits = (allowlist.protectedPatterns ?? []).flatMap(
    (descriptor) => findPatternHits(sanitized, normalizedFilePath, descriptor),
  );
  protectedHits.push(...patternHits);

  const protectedText = maskHits(sanitized, patternHits);
  const internalReason = internalPathReason(normalizedFilePath, allowlist);
  const forbiddenHits = (allowlist.forbiddenPatterns ?? []).flatMap(
    (descriptor) =>
      findPatternHits(protectedText, normalizedFilePath, descriptor),
  );
  const visibleContextHits = (allowlist.visibleContextPatterns ?? []).flatMap(
    (descriptor) =>
      findPatternHits(protectedText, normalizedFilePath, descriptor),
  );

  const forbidden = [...forbiddenHits, ...visibleContextHits].map((hit) => {
    if (!internalReason) return hit;
    return {
      ...hit,
      name: `INTERNAL_${hit.name}`,
      reason: `${hit.reason}; ${internalReason}`,
    };
  });

  if (internalReason) {
    protectedHits.push(...forbidden);
    return { protected: protectedHits, forbidden: [] };
  }

  return { protected: protectedHits, forbidden };
}

function isExcluded(relativePath, allowlist) {
  const normalized = `/${normalizePath(relativePath)}`;
  return (allowlist.excludePathFragments ?? []).some((fragment) =>
    normalized.includes(fragment),
  );
}

function collectFiles(rootDirectory, relativeRoot, allowlist) {
  const absoluteRoot = path.join(rootDirectory, relativeRoot);
  if (!fs.existsSync(absoluteRoot)) return [];

  const files = [];
  const visit = (absoluteDirectory) => {
    for (const entry of fs.readdirSync(absoluteDirectory, {
      withFileTypes: true,
    })) {
      const absolutePath = path.join(absoluteDirectory, entry.name);
      const relativePath = normalizePath(
        path.relative(rootDirectory, absolutePath),
      );
      if (isExcluded(relativePath, allowlist)) continue;
      if (entry.isDirectory()) {
        visit(absolutePath);
        continue;
      }
      if (
        entry.isFile() &&
        allowlist.extensions.includes(path.extname(entry.name).toLowerCase())
      ) {
        files.push({ absolutePath, relativePath });
      }
    }
  };

  visit(absoluteRoot);
  return files;
}

export function scanRepository({ rootDirectory = REPOSITORY_ROOT, allowlist }) {
  const result = {
    protected: [],
    forbidden: [],
    skipped: [],
    missingRoots: [],
  };

  for (const relativeRoot of allowlist.roots ?? []) {
    const absoluteRoot = path.join(rootDirectory, relativeRoot);
    if (!fs.existsSync(absoluteRoot)) {
      result.missingRoots.push(relativeRoot);
      continue;
    }

    for (const file of collectFiles(rootDirectory, relativeRoot, allowlist)) {
      const sourceBytes = fs.readFileSync(file.absolutePath);
      if (sourceBytes.includes(0)) {
        result.skipped.push({ file: file.relativePath, reason: "binary file" });
        continue;
      }
      const fileResult = scanText(
        sourceBytes.toString("utf8"),
        file.relativePath,
        allowlist,
      );
      result.protected.push(...fileResult.protected);
      result.forbidden.push(...fileResult.forbidden);
    }
  }

  return result;
}

function formatHit(hit) {
  return `- ${hit.file}:${hit.line}: ${JSON.stringify(hit.match)} — ${hit.reason}`;
}

export function formatReport(result) {
  const lines = ["Zion visible-brand scan"];
  lines.push(`Protected compatibility hits: ${result.protected.length}`);
  for (const hit of result.protected) lines.push(formatHit(hit));
  if (result.skipped.length > 0) {
    lines.push(`Skipped binary files: ${result.skipped.length}`);
  }
  if (result.missingRoots.length > 0) {
    lines.push(`Missing optional roots: ${result.missingRoots.join(", ")}`);
  }
  lines.push(`Forbidden visible-brand hits: ${result.forbidden.length}`);
  for (const hit of result.forbidden) lines.push(formatHit(hit));
  lines.push(
    result.forbidden.length === 0
      ? "PASS: no visible legacy Buzz/Sion bee-brand usage found outside the allowlist."
      : "FAIL: visible legacy branding requires an explicit migration or review.",
  );
  return lines.join("\n");
}

function loadAllowlist() {
  return JSON.parse(fs.readFileSync(ALLOWLIST_PATH, "utf8"));
}

function isMainModule() {
  return (
    process.argv[1] &&
    path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
  );
}

if (isMainModule()) {
  const allowlist = loadAllowlist();
  const result = scanRepository({ allowlist });
  console.log(formatReport(result));
  process.exitCode = result.forbidden.length === 0 ? 0 : 1;
}
