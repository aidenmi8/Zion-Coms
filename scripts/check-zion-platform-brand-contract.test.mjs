import assert from "node:assert/strict";
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
