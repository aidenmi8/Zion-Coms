import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

import {
  STARTER_TEAM_NAMES,
  StarterTeamPresence,
} from "./StarterTeamPresence.tsx";

function renderStarterTeam(phase) {
  return renderToStaticMarkup(
    React.createElement(
      "div",
      null,
      STARTER_TEAM_NAMES.map((name) =>
        React.createElement(
          "div",
          { key: name },
          React.createElement(StarterTeamPresence, { name, phase }),
          React.createElement("span", null, name),
        ),
      ),
    ),
  );
}

test("starter team presence renders neutral Zion surfaces for Fizz, Honey, and Bumble", () => {
  const html = renderStarterTeam("settled");

  assert.equal(
    (html.match(/data-brand-surface="starter-team-presence"/g) ?? []).length,
    3,
  );

  for (const name of STARTER_TEAM_NAMES) {
    assert.match(html, new RegExp(`data-persona="${name}"`));
    assert.match(html, new RegExp(`>${name}<`));
  }

  assert.match(html, /data-zion-variant="agent-entrance"/);
  assert.doesNotMatch(html, /buzz-logo|bee-/);
});

test("starter team presence phase drives the agent-entrance motion contract", () => {
  const enteringHtml = renderStarterTeam("entering");
  const settledHtml = renderStarterTeam("settled");
  const reducedMotionHtml = renderStarterTeam("reduced-motion");

  assert.match(enteringHtml, /data-phase="entering"/);
  assert.match(enteringHtml, /data-playing="true"/);

  assert.match(settledHtml, /data-phase="settled"/);
  assert.match(settledHtml, /data-playing="false"/);

  assert.match(reducedMotionHtml, /data-phase="reduced-motion"/);
  assert.match(reducedMotionHtml, /data-playing="false"/);
});

test("starter team presence CSS preserves settle behavior and reduced-motion fallbacks", () => {
  const css = fs.readFileSync(
    new URL("./starter-team-presence.css", import.meta.url),
    "utf8",
  );

  assert.match(css, /starter-team-presence-enter/);
  assert.match(css, /starter-team-presence-settle/);
  assert.match(css, /starter-team-presence-orbit/);
  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.doesNotMatch(css, /buzz-logo|bee-/);
});
