import assert from "node:assert/strict";
import test from "node:test";

import {
  currentZionReleaseChannel,
  formatZionReleaseLabel,
  resolveZionReleaseChannel,
  ZionReleaseChannel,
} from "./zionRelease.ts";

test("unconfigured builds default to the developer channel", () => {
  assert.equal(currentZionReleaseChannel, ZionReleaseChannel.Developer);
  assert.equal(
    resolveZionReleaseChannel(undefined),
    ZionReleaseChannel.Developer,
  );
});

test("developer builds expose the shared Zion 0.0.9 DV label", () => {
  assert.equal(
    formatZionReleaseLabel("0.0.9", ZionReleaseChannel.Developer),
    "Zion - V0.0.9 DV",
  );
});

test("release builds remove only the DV channel label", () => {
  assert.equal(
    formatZionReleaseLabel("0.0.9", ZionReleaseChannel.Release),
    "Zion - V0.0.9",
  );
});
