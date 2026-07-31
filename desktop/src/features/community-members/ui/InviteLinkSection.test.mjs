import assert from "node:assert/strict";
import test from "node:test";

import {
  canonicalizeInviteOutputUrl,
  INVITE_PNG_FILENAME,
} from "./inviteOutput.ts";

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

test("invite QR downloads use the Zion filename", () => {
  assert.equal(INVITE_PNG_FILENAME, "zion-community-invite.png");
});
