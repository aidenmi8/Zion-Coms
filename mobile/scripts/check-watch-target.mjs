#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const iosDirectory = join(scriptDirectory, "..", "ios");
const projectPath = join(
  iosDirectory,
  "Runner.xcodeproj",
  "project.pbxproj",
);
const schemePath = join(
  iosDirectory,
  "Runner.xcodeproj",
  "xcshareddata",
  "xcschemes",
  "ZionWatch.xcscheme",
);

const project = readFileSync(projectPath, "utf8");
const failures = [];

function requireMatch(label, pattern) {
  if (!pattern.test(project)) failures.push(label);
}

requireMatch(
  "application target named ZionWatch",
  /PBXNativeTarget[\s\S]*?name = ZionWatch;[\s\S]*?productType = "com\.apple\.product-type\.application";/,
);
requireMatch(
  "unit-test target named ZionWatchTests",
  /PBXNativeTarget[\s\S]*?name = ZionWatchTests;[\s\S]*?productType = "com\.apple\.product-type\.bundle\.unit-test";/,
);
requireMatch("watchOS SDK", /SDKROOT = watchos;/);
requireMatch(
  "watchOS 26 deployment target",
  /WATCHOS_DEPLOYMENT_TARGET = 26\.0;/,
);
requireMatch("watch-only device family", /TARGETED_DEVICE_FAMILY = 4;/);
requireMatch(
  "derived watch bundle identifier",
  /PRODUCT_BUNDLE_IDENTIFIER = "\$\(BUNDLE_IDENTIFIER\)\.watchkitapp";/,
);
requireMatch(
  "companion iPhone bundle identifier",
  /INFOPLIST_KEY_WKCompanionAppBundleIdentifier = "\$\(BUNDLE_IDENTIFIER\)";/,
);
requireMatch(
  "Runner embeds the watch app",
  /Embed Watch Content[\s\S]*?ZionWatch\.app in Embed Watch Content/,
);
requireMatch(
  "Runner depends on ZionWatch",
  /PBXTargetDependency[\s\S]*?target = .*?\/\* ZionWatch \*\//,
);

const sharedMemberships = [
  ...project.matchAll(/WatchWireModels\.swift in Sources/g),
].length;
if (sharedMemberships < 2) {
  failures.push("WatchWireModels.swift belongs to Runner and ZionWatch");
}
if (!existsSync(schemePath)) failures.push("shared ZionWatch scheme");

if (failures.length > 0) {
  console.error("ZionWatch target check failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("ZionWatch target structure is valid.");
