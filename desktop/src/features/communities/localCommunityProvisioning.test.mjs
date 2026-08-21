import assert from "node:assert/strict";
import test from "node:test";

import { resolveLocalCommunityProvisioningRelay } from "./localCommunityProvisioning.ts";

test("local community creation prefers the configured Zion private relay", () => {
  const relay = resolveLocalCommunityProvisioningRelay(
    [
      {
        id: "sentra",
        name: "sentra",
        relayUrl: "wss://sentra.communities.buzz.xyz",
      },
      {
        id: "zion",
        name: "Zion private relay",
        relayUrl: "wss://zion-coms.tail1bd36d.ts.net",
      },
    ],
    {
      id: "sentra",
      name: "sentra",
      relayUrl: "wss://sentra.communities.buzz.xyz",
    },
  );

  assert.deepEqual(relay, {
    name: "Zion private relay",
    relayUrl: "wss://zion-coms.tail1bd36d.ts.net",
  });
});

test("local community creation falls back to the active relay when Zion is not configured", () => {
  const relay = resolveLocalCommunityProvisioningRelay(
    [
      {
        id: "sentra",
        name: "sentra",
        relayUrl: "wss://sentra.communities.buzz.xyz",
      },
    ],
    {
      id: "sentra",
      name: "sentra",
      relayUrl: "wss://sentra.communities.buzz.xyz",
    },
  );

  assert.deepEqual(relay, {
    name: "sentra",
    relayUrl: "wss://sentra.communities.buzz.xyz",
  });
});
