import assert from "node:assert/strict";
import test from "node:test";

import {
  currentZionReleaseChannel,
  currentZionBuild,
  formatZionBuildLabel,
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

test("build labels preserve the source identity", () => {
  assert.equal(
    formatZionBuildLabel({
      buildId: "20260821.1",
      commit: "5a1bb5349",
      worktree: "dirty",
    }),
    "Build 20260821.1 · commit 5a1bb5349 · local changes",
  );
});

test("unconfigured builds retain a readable local identity", () => {
  assert.deepEqual(currentZionBuild, {
    buildId: "local",
    commit: "unknown",
    worktree: "unknown",
  });
});
