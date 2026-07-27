import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../../../..");

test("web Zion motion exposes all shared variants and reduced-motion hooks", async () => {
  const source = await readFile(
    resolve(root, "web/src/shared/ui/zion-brand/ZionBrandMotion.tsx"),
    "utf8",
  );
  const css = await readFile(
    resolve(root, "web/src/shared/ui/zion-brand/zion-brand-motion.css"),
    "utf8",
  );

  for (const variant of [
    "loader",
    "onboarding",
    "liveness",
    "pairing",
    "agent-entrance",
  ]) {
    assert.match(
      source,
      new RegExp(`"${variant}"|${variant.replace("-", "")}`),
    );
    assert.match(css, new RegExp(`zion-brand-motion--${variant}`));
  }
  assert.match(source, /data-brand-surface="zion-motion"/);
  assert.match(source, /data-reduced-motion/);
  assert.match(source, /data-loop/);
  assert.doesNotMatch(source, /className="sr-only"/);
  assert.match(css, /prefers-reduced-motion/);
  assert.match(css, /animation:\s*none/);
  assert.match(css, /data-loop="false"/);
  assert.match(css, /data-loop="true"/);
});

test("invite keeps the Buzz deep-link compatibility contract", async () => {
  const source = await readFile(
    resolve(root, "web/src/features/invite/ui/InvitePage.tsx"),
    "utf8",
  );
  assert.match(source, /buzz:\/\/join\?\$\{query\.toString\(\)\}/);
  assert.match(source, /buzz:\/\/join\?relay=/);
});
