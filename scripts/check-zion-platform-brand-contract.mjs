#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPOSITORY_ROOT = path.resolve(path.dirname(SCRIPT_PATH), "..");

const REQUIRED_FILES = [
  "desktop/src-tauri/Cargo.toml",
  "desktop/src-tauri/Info.plist",
  "desktop/src-tauri/tauri.conf.json",
  "mobile/android/app/build.gradle.kts",
  "mobile/android/app/src/main/AndroidManifest.xml",
  "mobile/ios/Flutter/Debug.xcconfig",
  "mobile/ios/Flutter/Release.xcconfig",
  "mobile/ios/Flutter/Watch.xcconfig",
  "mobile/ios/Runner/Info.plist",
  "mobile/lib/app.dart",
  "scripts/mobile-worktree-overrides.sh",
];

const PRODUCTION_ROOTS = ["desktop/src", "mobile/lib"];
const PRODUCTION_EXTENSIONS = new Set([
  ".css",
  ".dart",
  ".js",
  ".mjs",
  ".ts",
  ".tsx",
]);
const LEGACY_PRODUCTION_IDENTIFIERS = [
  "BuzzMark",
  "FlappingBee",
  "FuzzyLogo",
  "LandingBees",
  "TappableFlappingBee",
  "bee-sprite",
  "bee-wing-layer",
  "bee-wing-left-flap",
  "bee-wing-right-flap",
];

function normalizePath(filePath) {
  return filePath.split(path.sep).join("/");
}

function isProductionSource(relativePath) {
  const normalized = `/${normalizePath(relativePath)}`;
  if (
    normalized.includes("/testing/") ||
    normalized.includes("/fixtures/") ||
    normalized.includes(".test.") ||
    normalized.includes(".spec.")
  ) {
    return false;
  }
  return PRODUCTION_EXTENSIONS.has(path.extname(relativePath).toLowerCase());
}

function collectProductionSources(rootDirectory) {
  const sources = {};
  const visit = (relativeDirectory) => {
    const absoluteDirectory = path.join(rootDirectory, relativeDirectory);
    if (!fs.existsSync(absoluteDirectory)) return;
    for (const entry of fs.readdirSync(absoluteDirectory, {
      withFileTypes: true,
    })) {
      const relativePath = normalizePath(
        path.join(relativeDirectory, entry.name),
      );
      if (entry.isDirectory()) {
        visit(relativePath);
      } else if (entry.isFile() && isProductionSource(relativePath)) {
        sources[relativePath] = fs.readFileSync(
          path.join(rootDirectory, relativePath),
          "utf8",
        );
      }
    }
  };

  for (const root of PRODUCTION_ROOTS) visit(root);
  return sources;
}

export function loadPlatformBrandSources(rootDirectory = REPOSITORY_ROOT) {
  const sources = collectProductionSources(rootDirectory);
  for (const relativePath of REQUIRED_FILES) {
    const absolutePath = path.join(rootDirectory, relativePath);
    sources[relativePath] = fs.existsSync(absolutePath)
      ? fs.readFileSync(absolutePath, "utf8")
      : null;
  }
  return sources;
}

export function validatePlatformBrandSources(sources) {
  const failures = [];

  const source = (relativePath) => {
    const value = sources[relativePath];
    if (typeof value !== "string") {
      failures.push(`${relativePath}: required platform file is missing`);
      return "";
    }
    return value;
  };
  const mustContain = (relativePath, expected, reason) => {
    if (!source(relativePath).includes(expected)) {
      failures.push(`${relativePath}: ${reason}; expected ${JSON.stringify(expected)}`);
    }
  };
  const mustNotContain = (relativePath, forbidden, reason) => {
    if (source(relativePath).includes(forbidden)) {
      failures.push(`${relativePath}: ${reason}; found ${JSON.stringify(forbidden)}`);
    }
  };
  const mustMatch = (relativePath, pattern, reason) => {
    if (!pattern.test(source(relativePath))) {
      failures.push(`${relativePath}: ${reason}`);
    }
  };

  mustContain(
    "desktop/src-tauri/Cargo.toml",
    'name = "buzz-desktop"',
    "desktop package compatibility name changed",
  );
  mustContain(
    "desktop/src-tauri/Cargo.toml",
    'version = "0.5.0"',
    "desktop package version must track upstream 0.5.0",
  );
  mustContain(
    "desktop/src-tauri/Cargo.toml",
    'description = "Zion desktop app"',
    "desktop package description must remain visibly Zion",
  );

  const tauriPath = "desktop/src-tauri/tauri.conf.json";
  const tauriSource = source(tauriPath);
  if (tauriSource) {
    try {
      const tauri = JSON.parse(tauriSource);
      if (tauri.productName !== "Zion") {
        failures.push(`${tauriPath}: productName must be Zion`);
      }
      if (tauri.version !== "0.5.0") {
        failures.push(`${tauriPath}: version must be 0.5.0`);
      }
      if (tauri.identifier !== "xyz.block.buzz.app") {
        failures.push(`${tauriPath}: compatibility identifier changed`);
      }
      if (tauri.plugins?.["deep-link"]?.desktop?.schemes?.[0] !== "buzz") {
        failures.push(`${tauriPath}: buzz:// deep-link compatibility changed`);
      }
      const expectedSidecars = [
        "binaries/buzz-acp",
        "binaries/buzz-agent",
        "binaries/buzz-dev-mcp",
        "binaries/git-credential-nostr",
        "binaries/buzz",
      ];
      if (
        JSON.stringify(tauri.bundle?.externalBin) !==
        JSON.stringify(expectedSidecars)
      ) {
        failures.push(`${tauriPath}: five-sidecar compatibility set changed`);
      }
    } catch (error) {
      failures.push(`${tauriPath}: invalid JSON (${error.message})`);
    }
  }

  const desktopInfo = "desktop/src-tauri/Info.plist";
  mustMatch(
    desktopInfo,
    /<key>CFBundleDisplayName<\/key>\s*<string>Zion<\/string>/,
    "desktop display name must be Zion",
  );
  mustMatch(
    desktopInfo,
    /<key>CFBundleName<\/key>\s*<string>Zion<\/string>/,
    "desktop bundle name must be Zion",
  );
  for (const privacyKey of [
    "NSMicrophoneUsageDescription",
    "NSCameraUsageDescription",
    "NSLocalNetworkUsageDescription",
  ]) {
    mustMatch(
      desktopInfo,
      new RegExp(`<key>${privacyKey}</key>\\s*<string>Zion\\b`),
      `${privacyKey} must visibly name Zion`,
    );
  }
  mustNotContain(
    desktopInfo,
    "<string>Buzz",
    "desktop metadata restored visible Buzz branding",
  );

  const androidGradle = "mobile/android/app/build.gradle.kts";
  mustContain(
    androidGradle,
    'namespace = "xyz.block.buzz.mobile"',
    "Android namespace compatibility changed",
  );
  mustContain(
    androidGradle,
    'applicationId = "xyz.block.buzz.mobile"',
    "Android applicationId compatibility changed",
  );
  mustContain(
    androidGradle,
    'resValue("string", "app_name", "Zion")',
    "Android release/profile display name must be Zion",
  );
  mustContain(
    androidGradle,
    'resValue("string", "app_name", "Zion ($worktreeLabel)")',
    "Android worktree display name must remain visibly Zion",
  );
  mustNotContain(
    androidGradle,
    'resValue("string", "app_name", "Buzz',
    "Android display name restored visible Buzz branding",
  );
  mustContain(
    "mobile/android/app/src/main/AndroidManifest.xml",
    'android:label="@string/app_name"',
    "Android manifest must use the display-name indirection",
  );

  for (const xcconfig of [
    "mobile/ios/Flutter/Debug.xcconfig",
    "mobile/ios/Flutter/Release.xcconfig",
  ]) {
    mustContain(
      xcconfig,
      "BUNDLE_IDENTIFIER = do.agente.zion",
      "owned Zion iOS bundle identifier changed",
    );
    mustContain(
      xcconfig,
      "APP_DISPLAY_NAME = Zion",
      "iOS display name must be Zion",
    );
    mustNotContain(
      xcconfig,
      "APP_DISPLAY_NAME = Buzz",
      "iOS display name restored visible Buzz branding",
    );
  }
  mustContain(
    "mobile/ios/Flutter/Watch.xcconfig",
    "BUNDLE_IDENTIFIER = do.agente.zion",
    "Zion Watch companion bundle identifier changed",
  );

  const iosInfo = "mobile/ios/Runner/Info.plist";
  mustContain(
    iosInfo,
    "<string>$(APP_DISPLAY_NAME)</string>",
    "iOS Info.plist must use APP_DISPLAY_NAME indirection",
  );
  mustContain(
    iosInfo,
    "<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>",
    "iOS Info.plist must preserve bundle identifier indirection",
  );
  mustMatch(
    iosInfo,
    /<key>CFBundleName<\/key>\s*<string>Zion<\/string>/,
    "iOS bundle name must be Zion",
  );
  mustContain(
    iosInfo,
    "<string>com.buzz.deeplink</string>",
    "iOS legacy deep-link name changed",
  );
  mustMatch(
    iosInfo,
    /<key>CFBundleURLSchemes<\/key>\s*<array>\s*<string>buzz<\/string>/,
    "iOS buzz:// deep-link scheme changed",
  );
  for (const privacyKey of [
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "NSPhotoLibraryAddUsageDescription",
  ]) {
    mustMatch(
      iosInfo,
      new RegExp(`<key>${privacyKey}</key>\\s*<string>Zion\\b`),
      `${privacyKey} must visibly name Zion`,
    );
  }
  mustNotContain(
    iosInfo,
    "<string>Buzz",
    "iOS metadata restored visible Buzz branding",
  );

  mustContain(
    "mobile/lib/app.dart",
    "title: 'Zion'",
    "Flutter application title must be Zion",
  );
  mustContain(
    "scripts/mobile-worktree-overrides.sh",
    "APP_DISPLAY_NAME = Zion (${label})",
    "iOS worktree display-name generator must remain visibly Zion",
  );
  mustNotContain(
    "scripts/mobile-worktree-overrides.sh",
    "APP_DISPLAY_NAME = Buzz",
    "iOS worktree generator restored visible Buzz branding",
  );

  for (const [relativePath, text] of Object.entries(sources)) {
    if (
      typeof text !== "string" ||
      !PRODUCTION_ROOTS.some(
        (root) => relativePath === root || relativePath.startsWith(`${root}/`),
      ) ||
      !isProductionSource(relativePath)
    ) {
      continue;
    }
    for (const identifier of LEGACY_PRODUCTION_IDENTIFIERS) {
      if (text.includes(identifier)) {
        failures.push(
          `${relativePath}: legacy production bee component or selector ${JSON.stringify(identifier)} is forbidden`,
        );
      }
    }
  }

  if ("mobile/lib/shared/widgets/tappable_flapping_bee.dart" in sources) {
    failures.push(
      "mobile/lib/shared/widgets/tappable_flapping_bee.dart: legacy bee widget must remain deleted",
    );
  }

  return [...new Set(failures)];
}

export function formatPlatformBrandReport(failures) {
  if (failures.length === 0) {
    return "Zion platform-brand contract\nPASS: platform labels, compatibility identifiers, and production marks are valid.";
  }
  return [
    "Zion platform-brand contract",
    ...failures.map((failure) => `- ${failure}`),
    `FAIL: ${failures.length} platform-brand contract violation(s).`,
  ].join("\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === SCRIPT_PATH) {
  const failures = validatePlatformBrandSources(loadPlatformBrandSources());
  console.log(formatPlatformBrandReport(failures));
  process.exitCode = failures.length === 0 ? 0 : 1;
}
