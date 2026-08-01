import assert from "node:assert/strict";
import test from "node:test";

import { canonicalizeInviteOutputUrl } from "./inviteOutput.ts";

test("invite output upgrades legacy custom schemes but preserves HTTPS links", () => {
  assert.equal(
    canonicalizeInviteOutputUrl(
      "buzz://join?relay=wss%3A%2F%2Frelay.example&code=invite",
    ),
    "zion://join?relay=wss%3A%2F%2Frelay.example&code=invite",
  );
  assert.equal(
    canonicalizeInviteOutputUrl("https://relay.example/invite/invite"),
    "https://relay.example/invite/invite",
  );
});
