import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

import { frameAtTime } from "./brandAssetManifest.ts";
import { ZionBrandField } from "./ZionBrandField.tsx";
import {
  resolveMotionElapsedMs,
  resolveMotionRenderAsset,
  ZionMotion,
} from "./ZionMotion.tsx";

function installDOMShim() {
  class EventTargetShim {
    constructor() {
      this.listeners = new Map();
    }
    addEventListener(type, listener) {
      this.listeners.set(type, [...(this.listeners.get(type) ?? []), listener]);
    }
    removeEventListener(type, listener) {
      this.listeners.set(
        type,
        (this.listeners.get(type) ?? []).filter((entry) => entry !== listener),
      );
    }
    dispatchEvent(event) {
      for (const listener of this.listeners.get(event.type) ?? []) {
        listener(event);
      }
      return true;
    }
  }

  class NodeShim extends EventTargetShim {
    constructor(tagName) {
      super();
      this.tagName = tagName;
      this.nodeName = tagName.toUpperCase();
      this.nodeType = 1;
      this.namespaceURI = "http://www.w3.org/1999/xhtml";
      this.children = [];
      this.childNodes = [];
      this.style = {
        setProperty(name, value) {
          this[name] = String(value);
        },
        removeProperty(name) {
          delete this[name];
        },
      };
      this.parentNode = null;
      this.attributes = {};
    }
    setAttribute(name, value) {
      this.attributes[name] = String(value);
    }
    getAttribute(name) {
      return this.attributes[name] ?? null;
    }
    removeAttribute(name) {
      delete this.attributes[name];
    }
    get ownerDocument() {
      return globalThis.document;
    }
    get firstChild() {
      return this.children[0] ?? null;
    }
    get lastChild() {
      return this.children.at(-1) ?? null;
    }
    get nextSibling() {
      return null;
    }
    get nodeValue() {
      return null;
    }
    appendChild(child) {
      this.children.push(child);
      this.childNodes.push(child);
      child.parentNode = this;
      return child;
    }
    removeChild(child) {
      this.children = this.children.filter((entry) => entry !== child);
      this.childNodes = this.childNodes.filter((entry) => entry !== child);
      child.parentNode = null;
      return child;
    }
    insertBefore(child, reference) {
      if (!reference) return this.appendChild(child);
      const index = this.children.indexOf(reference);
      if (index < 0) return this.appendChild(child);
      this.children.splice(index, 0, child);
      this.childNodes.splice(index, 0, child);
      child.parentNode = this;
      return child;
    }
    contains(node) {
      return this === node || this.children.some((child) => child.contains(node));
    }
  }

  class DocumentShim extends EventTargetShim {
    constructor() {
      super();
      this.nodeType = 9;
      this.defaultView = globalThis;
    }
    createElement(tagName) {
      return new NodeShim(tagName);
    }
    createTextNode(value) {
      const node = new NodeShim("#text");
      node.nodeType = 3;
      node.nodeValue = value;
      return node;
    }
    createComment(value) {
      const node = new NodeShim("#comment");
      node.nodeType = 8;
      node.nodeValue = value;
      return node;
    }
    get activeElement() {
      return null;
    }
  }

  globalThis.document = new DocumentShim();
  globalThis.HTMLIFrameElement = NodeShim;
  globalThis.HTMLElement = NodeShim;
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  process.env.IS_REACT_ACT_ENVIRONMENT = "true";
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    writable: true,
    value: globalThis,
  });
  globalThis.MutationObserver = class {
    observe() {}
    disconnect() {}
    takeRecords() {
      return [];
    }
  };
}

installDOMShim();

function findFirstByTag(node, tagName) {
  if (!node) return null;
  if (node.tagName === tagName) return node;
  for (const child of node.children ?? []) {
    const match = findFirstByTag(child, tagName);
    if (match) return match;
  }
  return null;
}

test("frameAtTime loops, clamps, and safely handles empty frame sets", () => {
  assert.equal(frameAtTime(["a", "b", "c"], 250, 100), "c");
  assert.equal(frameAtTime(["a", "b", "c"], 350, 100), "a");
  assert.equal(frameAtTime(["a", "b", "c"], 350, 100, false), "c");
  assert.equal(frameAtTime([], 0, 100), null);
});

test("CSS defines reduced-motion fallback and all five Zion motion variants", () => {
  const css = fs.readFileSync(
    new URL("./zion-motion.css", import.meta.url),
    "utf8",
  );

  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(css, /animation: none/);
  assert.match(css, /\.zion-motion--loader/);
  assert.match(css, /\.zion-motion--onboarding/);
  assert.match(css, /\.zion-motion--liveness/);
  assert.match(css, /\.zion-motion--pairing/);
  assert.match(css, /\.zion-motion--agent-entrance/);
});

test("status markup keeps the visual mark decorative and exposes the label once", () => {
  const html = renderToStaticMarkup(
    React.createElement(
      "div",
      { role: "status" },
      React.createElement(ZionMotion, {
        ariaLabel: "Waiting for Zion",
        loop: false,
        playing: false,
        variant: "pairing",
      }),
    ),
  );

  assert.match(html, /data-brand-surface="zion-motion"/);
  assert.match(html, /data-zion-variant="pairing"/);
  assert.match(html, /data-playing="false"/);
  assert.match(html, /data-loop="false"/);
  assert.match(html, /alt=""/);
  assert.equal((html.match(/Waiting for Zion/g) ?? []).length, 1);
});

test("ZionBrandField renders deterministic inline transforms on first paint and is settled immediately for reduced motion", () => {
  const originalMatchMedia = globalThis.window.matchMedia;
  const makeWindow = (matches) => ({
    matchMedia: () => ({
      matches,
      addEventListener() {},
      removeEventListener() {},
      addListener() {},
      removeListener() {},
    }),
  });

  try {
    globalThis.window.matchMedia = makeWindow(false).matchMedia;
    const firstPaintHtml = renderToStaticMarkup(
      React.createElement(ZionBrandField),
    );
    assert.match(firstPaintHtml, /opacity:0\.24/);
    assert.match(
      firstPaintHtml,
      /transform:translate\(-8px, 7px\) rotate\(-8deg\) scale\(0\.9\)/,
    );

    globalThis.window.matchMedia = makeWindow(true).matchMedia;
    const reducedMotionHtml = renderToStaticMarkup(
      React.createElement(ZionBrandField),
    );
    assert.match(reducedMotionHtml, /opacity:0\.76/);
    assert.match(
      reducedMotionHtml,
      /transform:translate\(0px, 0px\) rotate\(-8deg\) scale\(1\)/,
    );
  } finally {
    globalThis.window.matchMedia = originalMatchMedia;
  }
});

test("dedicated-frame motion contracts resolve frames via mode and frameAtTime with static fallbacks", () => {
  const dedicatedFrameContract = {
    durationMs: 300,
    frames: ["/frame-1.svg", "/frame-2.svg", "/frame-3.svg"],
    loop: true,
    mode: "dedicated-frame",
    reducedMotion: "static",
  };

  assert.deepEqual(
    resolveMotionRenderAsset(dedicatedFrameContract, { elapsedMs: 250 }),
    { mode: "dedicated-frame", src: "/frame-3.svg" },
  );
  assert.deepEqual(
    resolveMotionRenderAsset(dedicatedFrameContract, { playing: false }),
    { mode: "dedicated-frame", src: "/frame-1.svg" },
  );
  assert.deepEqual(
    resolveMotionRenderAsset(dedicatedFrameContract, { reducedMotion: true }),
    { mode: "dedicated-frame", src: "/frame-1.svg" },
  );
  assert.deepEqual(
    resolveMotionRenderAsset({
      ...dedicatedFrameContract,
      mode: "code-native",
      frames: [],
    }),
    { mode: "code-native", src: null },
  );
});

test("dedicated-frame timing contract advances elapsed time for looping and one-shot playback", () => {
  assert.equal(
    resolveMotionElapsedMs({
      durationMs: 300,
      loop: true,
      nowMs: 150,
      startMs: 0,
    }),
    150,
  );
  assert.equal(
    resolveMotionElapsedMs({
      durationMs: 300,
      loop: false,
      nowMs: 150,
      startMs: 0,
    }),
    150,
  );
  assert.equal(
    resolveMotionElapsedMs({
      durationMs: 300,
      loop: false,
      nowMs: 450,
      startMs: 0,
    }),
    300,
  );

  const dedicatedFrameContract = {
    durationMs: 300,
    frames: ["/frame-1.svg", "/frame-2.svg", "/frame-3.svg"],
    loop: true,
    mode: "dedicated-frame",
    reducedMotion: "static",
  };

  assert.deepEqual(
    resolveMotionRenderAsset(dedicatedFrameContract, {
      elapsedMs: resolveMotionElapsedMs({
        durationMs: 300,
        loop: true,
        nowMs: 150,
        startMs: 0,
      }),
      loop: true,
      playing: true,
      reducedMotion: false,
    }),
    { mode: "dedicated-frame", src: "/frame-2.svg" },
  );
  assert.deepEqual(
    resolveMotionRenderAsset(dedicatedFrameContract, {
      elapsedMs: resolveMotionElapsedMs({
        durationMs: 300,
        loop: true,
        nowMs: 250,
        startMs: 0,
      }),
      loop: true,
      playing: true,
      reducedMotion: false,
    }),
    { mode: "dedicated-frame", src: "/frame-3.svg" },
  );
});
