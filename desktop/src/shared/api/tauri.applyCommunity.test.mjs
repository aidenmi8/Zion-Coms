import assert from "node:assert/strict";
import test from "node:test";

import { applyCommunity } from "./tauri.ts";

test("applyCommunity sends only the args declared by apply_workspace", async () => {
  const calls = [];
  const hadWindow = "window" in globalThis;
  const previousWindow = globalThis.window;
  globalThis.window = {
    __TAURI_INTERNALS__: {
      invoke: async (cmd, args) => {
        calls.push({ cmd, args });
      },
    },
  };

  try {
    await applyCommunity("wss://relay.example.com", undefined, "/repos", true);

    assert.equal(calls.length, 1);
    assert.equal(calls[0].cmd, "apply_workspace");
    assert.deepEqual(Object.keys(calls[0].args).sort(), [
      "agentManagedProfiles",
      "nsec",
      "relayUrl",
      "reposDir",
    ]);
    assert.equal(calls[0].args.relayUrl, "wss://relay.example.com");
    assert.equal(calls[0].args.nsec, null);
    assert.equal(calls[0].args.reposDir, "/repos");
    assert.equal(calls[0].args.agentManagedProfiles, true);
  } finally {
    if (hadWindow) {
      globalThis.window = previousWindow;
    } else {
      delete globalThis.window;
    }
  }
});
