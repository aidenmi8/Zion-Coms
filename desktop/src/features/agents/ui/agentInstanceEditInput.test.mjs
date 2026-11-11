import assert from "node:assert/strict";
import test from "node:test";

import * as formModel from "./personaRuntimeModel.ts";

const agent = {
  pubkey: "agent-pubkey",
  name: "Original",
  acpCommand: "acp",
  agentArgs: ["--old"],
  parallelism: 2,
  systemPrompt: null,
  model: null,
  provider: null,
  envVars: {},
  respondTo: "owner-only",
  respondToAllowlist: [],
};

function draft(overrides = {}) {
  return {
    agent,
    name: agent.name,
    acpCommand: agent.acpCommand,
    agentCommandUpdate: undefined,
    inheritHarness: true,
    agentArgs: agent.agentArgs.join(","),
    parallelism: String(agent.parallelism),
    systemPrompt: "",
    linkedPersona: false,
    inheritedSubmission: { provider: null, model: null, envVars: {} },
    prospectiveRuntimeId: "custom",
    respondTo: agent.respondTo,
    respondToAllowlist: [],
    ...overrides,
  };
}

test("edit payload keeps a linked agent's unchanged configuration untouched", () => {
  assert.equal(typeof formModel.buildEditAgentUpdateInput, "function");
  const input = formModel.buildEditAgentUpdateInput(
    draft({
      name: "  Renamed  ",
      linkedPersona: true,
    }),
  );
  assert.deepEqual(input, {
    pubkey: agent.pubkey,
    name: "Renamed",
    acpCommand: undefined,
    agentCommand: undefined,
    harnessOverride: undefined,
    agentArgs: undefined,
    parallelism: undefined,
    systemPrompt: undefined,
    model: undefined,
    provider: undefined,
    envVars: undefined,
    respondTo: undefined,
    respondToAllowlist: undefined,
  });
});

test("edit payload preserves the inherit sentinel and the gate-validated provider snapshot", () => {
  assert.equal(typeof formModel.buildEditAgentUpdateInput, "function");
  const input = formModel.buildEditAgentUpdateInput(
    draft({
      agentCommandUpdate: "",
      agentArgs: " --new, --flag, ",
      parallelism: "3",
      systemPrompt: " Prompt ",
      inheritedSubmission: {
        provider: "anthropic",
        model: "sonnet",
        envVars: { ANTHROPIC_API_KEY: "test-only" },
      },
      prospectiveRuntimeId: "buzz-agent",
      respondTo: "allowlist",
      respondToAllowlist: ["allowed-pubkey"],
    }),
  );
  assert.deepEqual(input, {
    pubkey: agent.pubkey,
    name: undefined,
    acpCommand: undefined,
    agentCommand: "",
    harnessOverride: false,
    agentArgs: ["--new", "--flag"],
    parallelism: 3,
    systemPrompt: "Prompt",
    model: "sonnet",
    provider: "anthropic",
    envVars: { ANTHROPIC_API_KEY: "test-only" },
    respondTo: "allowlist",
    respondToAllowlist: ["allowed-pubkey"],
  });
});

test("edit payload omits an unknown runtime's provider and inactive allowlist", () => {
  assert.equal(typeof formModel.buildEditAgentUpdateInput, "function");
  const input = formModel.buildEditAgentUpdateInput(
    draft({
      agent: {
        ...agent,
        provider: "anthropic",
        respondTo: "allowlist",
        respondToAllowlist: ["old-pubkey"],
      },
      inheritedSubmission: { provider: null, model: null, envVars: {} },
      respondTo: "anyone",
      respondToAllowlist: ["new-pubkey"],
    }),
  );
  assert.equal(input.provider, undefined);
  assert.equal(input.respondTo, "anyone");
  assert.equal(input.respondToAllowlist, undefined);
});
