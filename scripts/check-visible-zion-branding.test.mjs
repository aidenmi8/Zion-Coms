import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  formatReport,
  hasBlockingFindings,
  scanRepository,
  scanText,
} from "./check-visible-zion-branding.mjs";

const allowlist = {
  legacyAssetPaths: [
    "/buzz.svg",
    "/favicon.svg",
    "/app-icon@2x.png",
    "/app-icon@3x.png",
    "/landing/buzz-wordmark.png",
  ],
  protectedPatterns: [
    {
      name: "BUZZ_ENV",
      pattern: "\\bBUZZ_[A-Z0-9_]+\\b",
      reason: "BUZZ_* environment/API compatibility",
    },
    {
      name: "DEEP_LINK",
      pattern: "\\bbuzz://[^\\s\"'`<>)]*",
      reason: "buzz:// deep-link compatibility",
    },
    {
      name: "SIDECAR_COMMAND",
      pattern: "\\bbuzz-agent\\b",
      reason: "buzz-agent sidecar command compatibility",
    },
    {
      name: "BUNDLE_ID",
      pattern: "\\bxyz\\.block\\.buzz\\.app(?:\\.[A-Za-z0-9._-]+)?\\b",
      reason: "bundle identifier compatibility",
    },
  ],
  forbiddenPatterns: [
    {
      name: "VISIBLE_LABEL",
      pattern:
        "\\b(?:Buzz|buzz)\\s+(?:Agent|app|Desktop|Web|releases?|will|Bee|bee)\\b",
      reason: "legacy visible product label",
    },
  ],
  visibleAttributeNames: [
    "aria-label",
    "ariaLabel",
    "alt",
    "title",
    "placeholder",
    "label",
    "description",
    "heading",
    "text",
    "children",
    "displayName",
    "productName",
  ],
  legacyVisibleWords: [
    "Buzz",
    "buzz",
    "BUZZ",
    "Sion",
    "sion",
    "Bee",
    "bee",
    "BEE",
  ],
};

test("does not treat bSion or words containing sion as a brand hit", () => {
  const result = scanText(
    'const values = ["bSion", "VERSION", "session", "permission"];',
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.deepEqual(result.forbidden, []);
});

test("reports protected compatibility identifiers with a reason", () => {
  const result = scanText(
    [
      "const relay = process.env.BUZZ_RELAY_URL;",
      'const link = "buzz://join?token=example";',
      'const command = "buzz-agent";',
      'const identifier = "xyz.block.buzz.app";',
    ].join("\n"),
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.deepEqual(result.forbidden, []);
  assert.deepEqual(
    result.protected.map(({ name, reason }) => ({ name, reason })),
    [
      { name: "BUZZ_ENV", reason: "BUZZ_* environment/API compatibility" },
      { name: "DEEP_LINK", reason: "buzz:// deep-link compatibility" },
      {
        name: "SIDECAR_COMMAND",
        reason: "buzz-agent sidecar command compatibility",
      },
      { name: "BUNDLE_ID", reason: "bundle identifier compatibility" },
    ],
  );
});

test("flags visible legacy labels and preserves line evidence", () => {
  const result = scanText(
    ['<div aria-label="Buzz Agent">Buzz app</div>', "const ok = true;"].join(
      "\n",
    ),
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.equal(result.forbidden.length, 2);
  assert.equal(result.forbidden[0].line, 1);
  assert.match(result.forbidden[0].match, /Buzz Agent/);
  assert.match(result.forbidden[1].match, /Buzz app/);
});

test("flags visible brand words in accessibility attributes", () => {
  const result = scanText(
    [
      '<img alt="Bee" />',
      '<img ariaLabel="BUZZ" />',
      '<div title={"Sion"} />',
    ].join("\n"),
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.equal(result.forbidden.length, 3);
  assert.match(result.forbidden[0].match, /alt="Bee"/);
  assert.match(result.forbidden[1].match, /ariaLabel="BUZZ"/);
  assert.match(result.forbidden[2].match, /title=\{"Sion"\}/);
});

test("flags a legacy brand value rendered through a visible binding", () => {
  const result = scanText(
    ['const brand = "Buzz";', "<span aria-label={brand}>{brand}</span>"].join(
      "\n",
    ),
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.equal(result.forbidden.length, 2);
  assert.match(result.forbidden[0].match, /aria-label=\{brand\}/);
  assert.match(result.forbidden[1].match, />\{brand\}</);
});

test("ignores comments and embedded base64 artwork while scanning visible code", () => {
  const result = scanText(
    [
      "// Sion Buzz Agent bee-wing legacy implementation",
      "const mark = 'Zion';",
      'const artwork = "data:image/svg+xml;base64,U2lvbiBCdXp6IEJlZQ==";',
    ].join("\n"),
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.deepEqual(result.forbidden, []);
});

test("does not mistake slashes inside a regex literal for a comment", () => {
  const result = scanText(
    "const re = /[\\/\\/]/; const markup = <span>Sion</span>;",
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.equal(result.forbidden.length, 1);
  assert.match(result.forbidden[0].match, />Sion</);
});

test("recognizes regex literals after control-condition parentheses", () => {
  const result = scanText(
    "if (ok) /[\\/\\/]/; const markup = <span>Sion</span>;",
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.equal(result.forbidden.length, 1);
  assert.match(result.forbidden[0].match, />Sion</);
});

test("does not treat ordinary data properties as visible branding", () => {
  const result = scanText(
    'const data = { label: "Buzz", text: "Sion" }; save({ text: "Sion" });',
    "desktop/src/fixture.tsx",
    allowlist,
  );

  assert.deepEqual(result.forbidden, []);
});

test("does not broadly exempt visible branding under internal API paths", () => {
  const result = scanText(
    "return <span>Sion</span>;",
    "desktop/src/shared/api/fixture.ts",
    allowlist,
  );

  assert.equal(result.forbidden.length, 1);
  assert.deepEqual(result.protected, []);
});

test("reports a legacy alias path without scanning it as a replacement target", () => {
  const result = scanText(
    '<svg aria-label="Zion" />',
    "desktop/public/buzz.svg",
    allowlist,
  );

  assert.deepEqual(result.forbidden, []);
  assert.deepEqual(
    result.protected.map(({ name, match, line, reason }) => ({
      name,
      match,
      line,
      reason,
    })),
    [
      {
        name: "LEGACY_ASSET_PATH",
        match: "/buzz.svg",
        line: 1,
        reason: "legacy asset URL alias",
      },
    ],
  );
});

test("excludes test and fixture paths from the visible production scan", () => {
  const rootDirectory = fs.mkdtempSync(
    path.join(os.tmpdir(), "zion-visible-brand-scan-"),
  );
  fs.mkdirSync(path.join(rootDirectory, "src"), { recursive: true });
  fs.mkdirSync(path.join(rootDirectory, "src/fixtures"), { recursive: true });
  fs.writeFileSync(
    path.join(rootDirectory, "src/production.tsx"),
    "const markup = <span>Sion</span>;",
  );
  fs.writeFileSync(
    path.join(rootDirectory, "src/ignored.test.tsx"),
    'const label = "Sion";',
  );
  fs.writeFileSync(
    path.join(rootDirectory, "src/fixtures/ignored.tsx"),
    'const label = "Sion";',
  );

  const result = scanRepository({
    rootDirectory,
    allowlist: {
      ...allowlist,
      roots: ["src"],
      extensions: [".tsx"],
      excludePathFragments: ["/fixtures/", ".test."],
    },
  });

  fs.rmSync(rootDirectory, { recursive: true, force: true });
  assert.deepEqual(
    result.forbidden.map(({ file, line, match }) => ({ file, line, match })),
    [{ file: "src/production.tsx", line: 1, match: ">Sion<" }],
  );
});

test("treats missing configured roots as a blocking scan failure", () => {
  const result = scanRepository({
    rootDirectory: fs.mkdtempSync(
      path.join(os.tmpdir(), "zion-visible-brand-missing-root-"),
    ),
    allowlist: { ...allowlist, roots: ["missing"] },
  });

  assert.deepEqual(result.missingRoots, ["missing"]);
  assert.equal(hasBlockingFindings(result), true);
  assert.match(formatReport(result), /Missing required roots: missing/);
});
