import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  loadPlatformBrandSources,
  validatePlatformBrandSources,
} from "./check-zion-platform-brand-contract.mjs";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);

test("current platform files satisfy the Zion brand contract", () => {
  const failures = validatePlatformBrandSources(
    loadPlatformBrandSources(repositoryRoot),
  );
  assert.deepEqual(failures, []);
});

test("brand manifest publishes the canonical Zion compatibility facade", () => {
  const manifest = JSON.parse(
    fs.readFileSync(
      path.join(repositoryRoot, "branding/zion-brand-manifest.json"),
      "utf8",
    ),
  );

  assert.deepEqual(manifest.publicContract, {
    productName: "Zion",
    relayName: "Zion Relay",
    canonicalUrlScheme: "zion",
    legacyUrlScheme: "buzz",
    releaseRepositoryUrl: "https://github.com/aidenmi8/Zion-Coms",
    canonicalLaunchers: ["zion", "zion-acp", "zion-agent", "zion-dev-mcp"],
    legacyLaunchers: ["buzz", "buzz-acp", "buzz-agent", "buzz-dev-mcp"],
    environmentAliases: [
      { canonical: "ZION_RELAY_URL", legacy: "BUZZ_RELAY_URL" },
      { canonical: "ZION_PRIVATE_KEY", legacy: "BUZZ_PRIVATE_KEY" },
      { canonical: "ZION_AUTH_TAG", legacy: "BUZZ_AUTH_TAG" },
      { canonical: "ZION_SHELL", legacy: "BUZZ_SHELL" },
      { canonical: "ZION_AGENT_PROVIDER", legacy: "BUZZ_AGENT_PROVIDER" },
      { canonical: "ZION_AGENT_MODEL", legacy: "BUZZ_AGENT_MODEL" },
      {
        canonical: "ZION_AGENT_THINKING_EFFORT",
        legacy: "BUZZ_AGENT_THINKING_EFFORT",
      },
      {
        canonical: "ZION_AGENT_MAX_OUTPUT_TOKENS",
        legacy: "BUZZ_AGENT_MAX_OUTPUT_TOKENS",
      },
      {
        canonical: "ZION_AGENT_MAX_CONTEXT_TOKENS",
        legacy: "BUZZ_AGENT_MAX_CONTEXT_TOKENS",
      },
    ],
  });
});

test("desktop deep-link registration requires Zion before the legacy alias", () => {
  const sources = loadPlatformBrandSources(repositoryRoot);
  const tauriPath = "desktop/src-tauri/tauri.conf.json";
  const tauri = JSON.parse(sources[tauriPath]);
  tauri.plugins["deep-link"].desktop.schemes = ["buzz"];
  sources[tauriPath] = JSON.stringify(tauri);

  const failures = validatePlatformBrandSources(sources);
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes(tauriPath) &&
        failure.includes("Zion canonical and Buzz legacy deep-link schemes"),
    ),
  );
});

test("iOS deep-link registration requires Zion before the legacy alias", () => {
  const sources = loadPlatformBrandSources(repositoryRoot);
  const infoPath = "mobile/ios/Runner/Info.plist";
  sources[infoPath] = sources[infoPath].replace(
    "\t\t\t\t<string>zion</string>\n",
    "",
  );

  const failures = validatePlatformBrandSources(sources);
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes(infoPath) &&
        failure.includes("Zion canonical and Buzz legacy deep-link schemes"),
    ),
  );
});

test("Android deep-link registration requires Zion and the legacy alias", () => {
  const sources = loadPlatformBrandSources(repositoryRoot);
  const manifestPath = "mobile/android/app/src/main/AndroidManifest.xml";
  sources[manifestPath] = sources[manifestPath].replace(
    '                <data android:scheme="zion"/>\n',
    "",
  );

  const failures = validatePlatformBrandSources(sources);
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes(manifestPath) &&
        failure.includes("Zion canonical deep-link scheme"),
    ),
  );
});

test("restoring an Android Buzz label fails closed", () => {
  const sources = loadPlatformBrandSources(repositoryRoot);
  const gradlePath = "mobile/android/app/build.gradle.kts";
  sources[gradlePath] = sources[gradlePath].replace(
    'resValue("string", "app_name", "Zion")',
    'resValue("string", "app_name", "Buzz")',
  );

  const failures = validatePlatformBrandSources(sources);
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes(gradlePath) &&
        failure.includes("Android release/profile display name"),
    ),
  );
});

test("restoring the upstream iOS bundle identifier fails closed", () => {
  const sources = loadPlatformBrandSources(repositoryRoot);
  const xcconfigPath = "mobile/ios/Flutter/Release.xcconfig";
  sources[xcconfigPath] = sources[xcconfigPath].replace(
    "BUNDLE_IDENTIFIER = do.agente.zion",
    "BUNDLE_IDENTIFIER = com.buzz.buzzMobile",
  );

  const failures = validatePlatformBrandSources(sources);
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes(xcconfigPath) &&
        failure.includes("owned Zion iOS bundle identifier"),
    ),
  );
});

test("changing the Zion Watch companion bundle identifier fails closed", () => {
  const sources = loadPlatformBrandSources(repositoryRoot);
  const xcconfigPath = "mobile/ios/Flutter/Watch.xcconfig";
  sources[xcconfigPath] = sources[xcconfigPath].replace(
    "BUNDLE_IDENTIFIER = do.agente.zion",
    "BUNDLE_IDENTIFIER = example.invalid",
  );

  const failures = validatePlatformBrandSources(sources);
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes(xcconfigPath) &&
        failure.includes("Zion Watch companion bundle identifier"),
    ),
  );
});

test("restoring a legacy production bee component fails closed", () => {
  const sources = loadPlatformBrandSources(repositoryRoot);
  sources["mobile/lib/fixture.dart"] =
    "const widgetName = 'TappableFlappingBee';";

  const failures = validatePlatformBrandSources(sources);
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes("mobile/lib/fixture.dart") &&
        failure.includes("TappableFlappingBee"),
    ),
  );
});

test("desktop and mobile release versions cannot drift from Zion 0.0.9", () => {
  const sources = loadPlatformBrandSources(repositoryRoot);
  sources["desktop/package.json"] = (
    sources["desktop/package.json"] ?? ""
  ).replace(
    '"version": "0.0.9"',
    '"version": "0.0.10"',
  );
  sources["mobile/pubspec.yaml"] = (
    sources["mobile/pubspec.yaml"] ?? ""
  ).replace(
    "version: 0.0.9+1",
    "version: 0.0.10+1",
  );

  const failures = validatePlatformBrandSources(sources);
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes("desktop/package.json") &&
        failure.includes("Zion release version"),
    ),
  );
  assert.ok(
    failures.some(
      (failure) =>
        failure.includes("mobile/pubspec.yaml") &&
        failure.includes("Zion release version"),
    ),
  );
});
