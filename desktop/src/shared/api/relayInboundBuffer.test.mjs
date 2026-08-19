import assert from "node:assert/strict";
import test from "node:test";

import {
  createRelayInboundBuffer,
  MAX_PENDING_RELAY_FRAMES,
} from "./relayInboundBuffer.ts";

test("drains queued frames in order, including frames received during drain", async () => {
  const handled = [];
  let releaseFirst;
  const firstBlocked = new Promise((resolve) => {
    releaseFirst = resolve;
  });
  const inbound = createRelayInboundBuffer(async (message) => {
    handled.push(message);
    if (message === "first") await firstBlocked;
  }, assert.fail);

  inbound.receive("first");
  const drain = inbound.drain();
  inbound.receive("second");
  releaseFirst();
  await drain;
  inbound.receive("live");
  await new Promise((resolve) => setTimeout(resolve));

  assert.deepEqual(handled, ["first", "second", "live"]);
});

test("rejects the 257th safely sized frame while connecting", async () => {
  let observedError;
  const inbound = createRelayInboundBuffer(
    async () => {},
    (error) => {
      observedError = error;
    },
  );

  for (let index = 0; index <= MAX_PENDING_RELAY_FRAMES; index += 1) {
    inbound.receive(`frame-${index}`);
  }

  await assert.rejects(
    inbound.overflow,
    /Relay sent too many frames while connecting/,
  );
  assert.match(observedError.message, /too many frames/);
});

test("rejects only when aggregate raw and native text bytes exceed 1 MiB", async () => {
  let observedError;
  const inbound = createRelayInboundBuffer(
    async () => {},
    (error) => {
      observedError = error;
    },
  );

  inbound.receive({ type: "Text", data: "a".repeat(700_000) });
  assert.equal(observedError, undefined);
  inbound.receive("b".repeat(400_000));

  assert.ok(
    observedError instanceof Error,
    "aggregate buffered bytes should fail closed",
  );
  await assert.rejects(inbound.overflow, /too much data while connecting/);
});

test("rejects only when aggregate native binary bytes exceed 1 MiB", async () => {
  let observedError;
  const inbound = createRelayInboundBuffer(
    async () => {},
    (error) => {
      observedError = error;
    },
  );

  inbound.receive({ type: "Binary", data: new Array(700_000).fill(0) });
  assert.equal(observedError, undefined);
  inbound.receive({ type: "Binary", data: new Array(400_000).fill(0) });

  assert.ok(observedError instanceof Error, "binary data should fail closed");
  await assert.rejects(inbound.overflow, /too much data while connecting/);
});

test("fails closed when a pre-auth frame cannot be safely sized", async () => {
  let observedError;
  const inbound = createRelayInboundBuffer(
    async () => {},
    (error) => {
      observedError = error;
    },
  );

  inbound.receive({ type: "Text", data: { untrusted: true } });

  assert.ok(observedError instanceof Error, "unknown frame should fail closed");
  await assert.rejects(inbound.overflow, /could not be safely sized/);
});
