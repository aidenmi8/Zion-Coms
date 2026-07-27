import assert from "node:assert/strict";
import test from "node:test";

import {
  formatZionActivityCommand,
  formatZionAgentText,
  isCodexSkillsContextWarning,
} from "./agentSessionBranding.ts";

test("formatZionActivityCommand presents the compatibility CLI as Zion", () => {
  assert.equal(
    formatZionActivityCommand("buzz messages send --help"),
    "Zion messages send --help",
  );
  assert.equal(
    formatZionActivityCommand(
      "sleep 1; buzz messages send --channel channel-1",
    ),
    "sleep 1; Zion messages send --channel channel-1",
  );
});

test("formatZionActivityCommand leaves unrelated commands unchanged", () => {
  assert.equal(formatZionActivityCommand("git status"), "git status");
  assert.equal(
    formatZionActivityCommand("rg buzz desktop/src"),
    "rg buzz desktop/src",
  );
});

test("formatZionAgentText uses Zion for product-facing relay prose", () => {
  assert.equal(
    formatZionAgentText(
      "The Buzz relay failed. Retry the buzz relay, then check BUZZ_RELAY_URL.",
    ),
    "The Zion relay failed. Retry the Zion relay, then check BUZZ_RELAY_URL.",
  );
});

test("isCodexSkillsContextWarning matches only the known catalog warning", () => {
  assert.equal(
    isCodexSkillsContextWarning(
      "Warning: Skill descriptions were shortened to fit the 2% skills context budget. Codex can still see every skill.",
    ),
    true,
  );
  assert.equal(
    isCodexSkillsContextWarning("Warning: The Zion relay is unavailable."),
    false,
  );
});
