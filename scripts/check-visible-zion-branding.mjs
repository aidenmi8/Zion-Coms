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

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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
  let inRegexClass = false;
  let lastClosedControlParen = false;
  const controlParenStack = [];
  const controlParenWords = new Set([
    "catch",
    "for",
    "if",
    "switch",
    "while",
    "with",
  ]);

  const canStartRegex = () => {
    let index = output.length - 1;
    while (index >= 0 && /\s/.test(output[index])) index -= 1;
    if (index < 0) return true;

    const previous = output[index];
    if (previous === ")") return lastClosedControlParen;
    if ("=([{,:;!&|?+-*%^~<>".includes(previous)) return true;

    const word = output
      .slice(0, index + 1)
      .match(/[A-Za-z_$][A-Za-z0-9_$]*$/)?.[0];
    return new Set([
      "await",
      "case",
      "delete",
      "do",
      "else",
      "in",
      "of",
      "return",
      "throw",
      "typeof",
      "void",
      "yield",
    ]).has(word);
  };

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

    if (state === "regex") {
      output += character;
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === "[") {
        inRegexClass = true;
      } else if (character === "]") {
        inRegexClass = false;
      } else if (character === "/" && !inRegexClass) {
        state = "code";
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

    if (character === "(") {
      const word = output.match(/[A-Za-z_$][A-Za-z0-9_$]*\s*$/)?.[0]?.trim();
      controlParenStack.push(controlParenWords.has(word));
      lastClosedControlParen = false;
      output += character;
    } else if (character === ")") {
      lastClosedControlParen = controlParenStack.pop() ?? false;
      output += character;
    } else if (character === "'" || character === '"' || character === "`") {
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
    } else if (character === "/" && canStartRegex()) {
      output += character;
      state = "regex";
      inRegexClass = false;
      lastClosedControlParen = false;
    } else {
      if (!/\s/.test(character)) lastClosedControlParen = false;
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

function visibleContextPatterns(allowlist) {
  if (!allowlist.visibleAttributeNames || !allowlist.legacyVisibleWords) {
    return allowlist.visibleContextPatterns ?? [];
  }

  const attributes = allowlist.visibleAttributeNames
    .map(escapeRegExp)
    .join("|");
  const words = allowlist.legacyVisibleWords.map(escapeRegExp).join("|");
  const quotedValue = [
    `"[^"\\n]*\\b(?:${words})\\b[^"\\n]*"`,
    `'[^'\\n]*\\b(?:${words})\\b[^'\\n]*'`,
    `\`[^\`\\n]*\\b(?:${words})\\b[^\`\\n]*\``,
  ].join("|");
  const quotedValueGroup = `(?:${quotedValue})`;
  const expressionValue = `\\{\\s*${quotedValueGroup}\\s*\\}`;

  return [
    {
      name: "VISIBLE_BRAND_JSX_ATTRIBUTE",
      pattern: `<[^>\\n]*?\\b(?:${attributes})\\s*=\\s*(?:${quotedValueGroup}|${expressionValue})`,
      reason: "legacy visible brand word in a user-facing JSX/HTML attribute",
    },
    {
      name: "VISIBLE_JSX_TEXT",
      pattern: `>[^<{\\n]*\\b(?:${words})\\b[^<{\\n]*<`,
      reason: "legacy visible brand word in rendered text",
    },
  ];
}

function dynamicVisibleBrandHits(text, filePath, allowlist) {
  if (!allowlist.visibleAttributeNames || !allowlist.legacyVisibleWords) {
    return [];
  }

  const attributes = allowlist.visibleAttributeNames
    .map(escapeRegExp)
    .join("|");
  const words = allowlist.legacyVisibleWords.map(escapeRegExp).join("|");
  const doubleQuote = String.fromCharCode(34);
  const singleQuote = String.fromCharCode(39);
  const quotedValueGroup = [
    "(?:",
    `${doubleQuote}[^${doubleQuote}\\n]*\\b(?:${words})\\b[^${doubleQuote}\\n]*${doubleQuote}|`,
    `${singleQuote}[^${singleQuote}\\n]*\\b(?:${words})\\b[^${singleQuote}\\n]*${singleQuote}`,
    ")",
  ].join("");
  const bindingPattern = new RegExp(
    `\\b(?:const|let|var)\\s+([A-Za-z_$][A-Za-z0-9_$]*)\\s*(?:\\:\\s*[^=;]+)?=\\s*${quotedValueGroup}`,
    "g",
  );
  const hits = [];
  const seen = new Set();

  for (const binding of text.matchAll(bindingPattern)) {
    const identifier = binding[1];
    const escapedIdentifier = escapeRegExp(identifier);
    const contextPatterns = [
      new RegExp(
        `<[^>\\n]*?\\b(?:${attributes})\\s*=\\s*\\{[^}\\n]*\\b${escapedIdentifier}\\b[^}\\n]*\\}`,
        "g",
      ),
      new RegExp(
        `>[^<{\\n]*\\{[^}\\n]*\\b${escapedIdentifier}\\b[^}\\n]*\\}[^<{\\n]*<`,
        "g",
      ),
    ];

    for (const pattern of contextPatterns) {
      for (const match of text.matchAll(pattern)) {
        if (match.index === undefined) continue;
        const key = `${match.index}:${match[0].length}`;
        if (seen.has(key)) continue;
        seen.add(key);
        hits.push({
          file: filePath,
          line: lineNumberAt(text, match.index),
          match: match[0],
          name: "VISIBLE_BRAND_BINDING",
          reason: `legacy visible brand binding: ${identifier}`,
          index: match.index,
          length: match[0].length,
        });
      }
    }
  }

  return hits;
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
  const forbiddenHits = (allowlist.forbiddenPatterns ?? []).flatMap(
    (descriptor) =>
      findPatternHits(protectedText, normalizedFilePath, descriptor),
  );
  const visibleContextHits = visibleContextPatterns(allowlist).flatMap(
    (descriptor) =>
      findPatternHits(protectedText, normalizedFilePath, descriptor),
  );
  const dynamicHits = dynamicVisibleBrandHits(
    protectedText,
    normalizedFilePath,
    allowlist,
  );

  const forbidden = [...forbiddenHits, ...visibleContextHits, ...dynamicHits]
    .sort((left, right) => {
      if (left.index !== right.index) return left.index - right.index;
      return right.length - left.length;
    })
    .filter((hit, index, hits) => {
      if (hit.index < 0) return true;
      return !hits
        .slice(0, index)
        .some(
          (previous) =>
            previous.index >= 0 &&
            hit.index < previous.index + previous.length &&
            previous.index < hit.index + hit.length,
        );
    })
    .sort((left, right) => left.index - right.index);

  return {
    protected: protectedHits,
    forbidden,
  };
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
    if (
      !fs.existsSync(absoluteRoot) ||
      !fs.statSync(absoluteRoot).isDirectory()
    ) {
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
    lines.push(`Missing required roots: ${result.missingRoots.join(", ")}`);
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

export function hasBlockingFindings(result) {
  return result.missingRoots.length > 0 || result.forbidden.length > 0;
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
  process.exitCode = hasBlockingFindings(result) ? 1 : 0;
}
