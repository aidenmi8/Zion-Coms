import assert from "node:assert/strict";
import test from "node:test";

import {
  BUZZ_RELEASES_URL,
  resolveBuzzDownloadUrlForPlatform,
  selectBuzzDownloadUrl,
} from "./buzz-download.ts";

const WINDOWS = { operatingSystem: "windows", architecture: "x64" };

test("release discovery is scoped to Zion-Coms and Zion-named assets", () => {
  assert.equal(
    BUZZ_RELEASES_URL,
    "https://github.com/aidenmi8/Zion-Coms/releases",
  );
  assert.equal(
    selectBuzzDownloadUrl(
      [
        {
          draft: false,
          prerelease: false,
          assets: [
            {
              name: "Buzz_0.4.9_x64-setup.exe",
              browser_download_url:
                "https://github.com/block/buzz/releases/download/v0.4.9/Buzz_0.4.9_x64-setup.exe",
            },
            {
              name: "Zion_0.4.9_x64-setup.exe",
              browser_download_url:
                "https://github.com/aidenmi8/Zion-Coms/releases/download/v0.4.9/Zion_0.4.9_x64-setup.exe",
            },
          ],
        },
      ],
      WINDOWS,
    ),
    "https://github.com/aidenmi8/Zion-Coms/releases/download/v0.4.9/Zion_0.4.9_x64-setup.exe",
  );
});

test("release discovery rejects Zion-named assets outside Zion-Coms", () => {
  assert.equal(
    selectBuzzDownloadUrl(
      [
        {
          draft: false,
          prerelease: false,
          assets: [
            {
              name: "Zion_0.4.9_x64-setup.exe",
              browser_download_url:
                "https://github.com/block/buzz/releases/download/v0.4.9/Zion_0.4.9_x64-setup.exe",
            },
          ],
        },
      ],
      WINDOWS,
    ),
    undefined,
  );
});

test("release discovery rejects a Zion asset name whose URL basename is legacy-branded", () => {
  assert.equal(
    selectBuzzDownloadUrl(
      [
        {
          draft: false,
          prerelease: false,
          assets: [
            {
              name: "Zion_0.4.9_x64-setup.exe",
              browser_download_url:
                "https://github.com/aidenmi8/Zion-Coms/releases/download/v0.4.9/Buzz_0.4.9_x64-setup.exe",
            },
          ],
        },
      ],
      WINDOWS,
    ),
    undefined,
  );
});

test("an invalid cached installer is removed before Zion release discovery continues", async () => {
  const previousFetch = globalThis.fetch;
  const previousSessionStorage = globalThis.sessionStorage;
  const refreshedUrl =
    "https://github.com/aidenmi8/Zion-Coms/releases/download/v0.5.0/Zion_0.5.0_x64-setup.exe";
  let cachedValue = JSON.stringify({
    expiresAt: Date.now() + 60_000,
    platform: WINDOWS,
    url: "https://github.com/aidenmi8/Zion-Coms/releases/download/v0.4.9/Buzz_0.4.9_x64-setup.exe",
  });
  const removedKeys = [];
  let fetchCount = 0;
  globalThis.sessionStorage = {
    getItem: () => cachedValue,
    removeItem: (key) => {
      removedKeys.push(key);
      cachedValue = null;
    },
    setItem: () => {},
  };
  globalThis.fetch = async () => {
    fetchCount += 1;
    return {
      ok: true,
      json: async () => [
        {
          draft: false,
          prerelease: false,
          assets: [
            {
              name: "Zion_0.5.0_x64-setup.exe",
              browser_download_url: refreshedUrl,
            },
          ],
        },
      ],
    };
  };

  try {
    assert.equal(
      await resolveBuzzDownloadUrlForPlatform(WINDOWS),
      refreshedUrl,
    );
    assert.deepEqual(removedKeys, ["zion.latestDownload.v1"]);
    assert.equal(fetchCount, 1);
  } finally {
    globalThis.fetch = previousFetch;
    globalThis.sessionStorage = previousSessionStorage;
  }
});

test("release discovery returns no direct installer when no Zion asset matches", async () => {
  const previousFetch = globalThis.fetch;
  const previousSessionStorage = globalThis.sessionStorage;
  let requestedUrl;
  globalThis.sessionStorage = {
    getItem: () => null,
    setItem: () => {},
  };
  globalThis.fetch = async (url) => {
    requestedUrl = String(url);
    return {
      ok: true,
      json: async () => [
        {
          draft: false,
          prerelease: false,
          assets: [
            {
              name: "Buzz_0.4.9_x64-setup.exe",
              browser_download_url: "https://example.test/buzz.exe",
            },
          ],
        },
      ],
    };
  };

  try {
    assert.equal(await resolveBuzzDownloadUrlForPlatform(WINDOWS), undefined);
    assert.equal(
      requestedUrl,
      "https://api.github.com/repos/aidenmi8/Zion-Coms/releases?per_page=10",
    );
  } finally {
    globalThis.fetch = previousFetch;
    globalThis.sessionStorage = previousSessionStorage;
  }
});
