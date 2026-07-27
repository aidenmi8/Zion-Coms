import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const appSource = readFileSync(new URL("./App.tsx", import.meta.url), "utf8");
const styleSource = readFileSync(
  new URL("./styles.css", import.meta.url),
  "utf8",
);

describe("Zion admin brand contract", () => {
  test("keeps the visible admin identity and compatibility key", () => {
    expect(appSource).toMatch(/Zion <b>Admin<\/b>/);
    expect(appSource).toMatch(/src="\/sentra-lockup-dark\.svg"/);
    expect(appSource).toMatch(/className="app zion-brand-shell"/);
    expect(appSource).toMatch(/buzz-admin-feedback-status/);
    expect(styleSource).toMatch(/\.zion-brand-shell\s*\{/);
    expect(styleSource).toMatch(/#0b0812/);
  });
});
