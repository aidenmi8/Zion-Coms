import { createHash } from "node:crypto";
import { expect, test } from "@playwright/test";

const ZION_RELEASES_PAGE = "https://github.com/aidenmi8/Zion-Coms/releases";

test.beforeEach(async ({ page }) => {
  // Platform-specific tests override this fallback; never query live releases.
  await page.route("https://api.github.com/**", (route) =>
    route.fulfill({ json: [] }),
  );
});

test("empty community shows Zion identity and a compatible connect control", async ({
  page,
}) => {
  await page.routeWebSocket("ws://127.0.0.1:4173/**", (socket) => {
    socket.onMessage((message) => {
      const [type, subscription] = JSON.parse(String(message));
      if (type === "REQ") socket.send(JSON.stringify(["EOSE", subscription]));
    });
  });
  await page.goto("/");
  await expect(page).toHaveTitle("Zion");
  const logo = page
    .getByRole("main")
    .getByRole("img", { name: "Zion", exact: true });
  await expect(logo).toBeVisible();
  await expect(logo).toHaveJSProperty("naturalWidth", 1024);
  await expect(
    page.getByRole("heading", { name: "This community is empty" }),
  ).toBeVisible();
  await expect(
    page.getByRole("link", { name: "Open in Zion" }),
  ).toHaveAttribute("href", "buzz://connect?relay=ws%3A%2F%2F127.0.0.1%3A4173");
  await expect(page.getByRole("link", { name: "Open in Zion" })).toHaveCSS(
    "background-color",
    "rgb(78, 124, 255)",
  );
});

test("repository search keeps working with Zion connect branding", async ({
  page,
}) => {
  await page.routeWebSocket("ws://127.0.0.1:4173/**", (socket) => {
    socket.onMessage((message) => {
      const [type, subscription] = JSON.parse(String(message));
      if (type !== "REQ") return;
      socket.send(
        JSON.stringify([
          "EVENT",
          subscription,
          {
            id: "a".repeat(64),
            pubkey: "b".repeat(64),
            kind: 30617,
            created_at: 1,
            content: "Example repository",
            sig: "c".repeat(128),
            tags: [
              ["d", "example"],
              ["name", "Example"],
              ["clone", "https://example.org/example.git"],
            ],
          },
        ]),
      );
      socket.send(JSON.stringify(["EOSE", subscription]));
    });
  });
  await page.goto("/");
  await expect(page.getByText("Repositories")).toBeVisible();
  await expect(
    page.getByRole("link", { name: "Open in Zion" }).last(),
  ).toHaveAttribute("href", /^buzz:\/\/connect\?relay=/);
  await page.getByPlaceholder("Find a repository...").fill("no match");
  await expect(
    page.getByRole("heading", { name: "No matching repositories" }),
  ).toBeVisible();
  await page.getByPlaceholder("Find a repository...").fill("example");
  await expect(
    page.getByRole("link", { name: "Example", exact: true }),
  ).toBeVisible();
});

test("invite requires age and legal consent before opening Zion", async ({
  page,
}) => {
  await page.route("**/api/join-policy", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        policy: {
          terms_markdown: "# Terms",
          privacy_markdown: "# Privacy",
          age_attestation_required: true,
          version: "policy-v1",
        },
      }),
    });
  });
  await page.route("https://api.github.com/**", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      headers: { "Access-Control-Allow-Origin": "*" },
      body: JSON.stringify([
        { draft: false, prerelease: true, assets: [] },
        {
          draft: false,
          prerelease: true,
          assets: [
            {
              name: "Buzz_0.4.9_aarch64.dmg",
              browser_download_url:
                "https://github.com/block/buzz-app/releases/download/v0.4.9/Buzz_0.4.9_aarch64.dmg",
            },
            {
              name: "Buzz_0.4.9_x86_64.AppImage",
              browser_download_url:
                "https://github.com/block/buzz-app/releases/download/v0.4.9/Buzz_0.4.9_x86_64.AppImage",
            },
            {
              name: "Buzz_0.4.9_x64_unsigned.exe",
              browser_download_url:
                "https://github.com/block/buzz-app/releases/download/v0.4.9/Buzz_0.4.9_x64_unsigned.exe",
            },
          ],
        },
      ]),
    });
  });
  await page.goto("/invite/demo-code");
  await expect(
    page.getByRole("img", { name: "Zion", exact: true }),
  ).toBeVisible();
  await expect(page.getByText("Join your community on Zion.")).toBeVisible();
  await expect(page.locator(".invite-page")).toHaveCSS(
    "background-color",
    "rgb(10, 10, 10)",
  );

  await expect(
    page.getByRole("link", { name: "Download Zion" }),
  ).toHaveAttribute("href", ZION_RELEASES_PAGE);
  await expect(page.getByRole("link", { name: "Browse releases" })).toHaveCount(
    0,
  );

  const ageConfirmation = page.getByLabel("I am 18 years of age or older.");
  const agreementConfirmation = page.getByLabel(
    "I agree to the Buzz Terms of Service and Privacy Policy.",
  );
  const acceptInvite = page.getByRole("button", {
    name: "Accept invite in Zion",
  });

  await expect(ageConfirmation).toBeVisible();
  await expect(agreementConfirmation).toBeVisible();
  await expect(acceptInvite).toBeDisabled();

  const termsLink = page.getByRole("button", { name: "Terms of Service" });
  const privacyLink = page.getByRole("button", { name: "Privacy Policy" });
  await expect(termsLink).toHaveCSS("text-decoration-line", "none");
  await expect(privacyLink).toHaveCSS("text-decoration-line", "none");
  await termsLink.hover();
  await expect(termsLink).toHaveCSS("text-decoration-line", "underline");
  await page.mouse.move(0, 0);
  await privacyLink.hover();
  await expect(privacyLink).toHaveCSS("text-decoration-line", "underline");

  await page
    .locator("label")
    .filter({ hasText: "I am 18 years of age or older." })
    .click();
  await expect(ageConfirmation).toBeChecked();
  await expect(acceptInvite).toBeDisabled();
  await page
    .locator("label")
    .filter({
      hasText: "I agree to the Buzz Terms of Service and Privacy Policy.",
    })
    .click({ position: { x: 8, y: 8 } });
  await expect(agreementConfirmation).toBeChecked();
  await expect(acceptInvite).toBeEnabled();

  const consentBox = await page
    .getByTestId("invite-join-policy-notice")
    .boundingBox();
  const acceptButtonBox = await acceptInvite.boundingBox();
  expect(consentBox?.y).toBeLessThan(acceptButtonBox?.y ?? 0);
  expect(consentBox?.width).toBe(acceptButtonBox?.width);
});

test("invite can enroll a NIP-07 identity for browser access", async ({
  page,
}) => {
  const pubkey = "ab".repeat(32);
  await page.addInitScript((extensionPubkey) => {
    (
      window as Window & {
        nostr?: {
          getPublicKey(): Promise<string>;
          signEvent(
            event: Record<string, unknown>,
          ): Promise<Record<string, unknown>>;
        };
      }
    ).nostr = {
      async getPublicKey() {
        return extensionPubkey;
      },
      async signEvent(event) {
        return {
          ...event,
          id: "cd".repeat(32),
          pubkey: extensionPubkey,
          sig: "ef".repeat(64),
        };
      },
    };
  }, pubkey);
  await page.route("**/api/join-policy", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ policy: null }),
    });
  });

  let claimObserved = false;
  await page.route("**/api/invites/claim", async (route) => {
    claimObserved = true;
    const request = route.request();
    const body = request.postData() ?? "";
    expect(JSON.parse(body)).toEqual({
      code: "browser-code",
    });

    const authorization = request.headers().authorization;
    expect(authorization).toMatch(/^Nostr /);
    const event = JSON.parse(
      Buffer.from(authorization.slice("Nostr ".length), "base64").toString(
        "utf8",
      ),
    ) as {
      pubkey: string;
      tags: string[][];
    };
    expect(event.pubkey).toBe(pubkey);
    expect(event.tags).toContainEqual(["u", request.url()]);
    expect(event.tags).toContainEqual(["method", "POST"]);
    expect(event.tags).toContainEqual([
      "payload",
      createHash("sha256").update(body).digest("hex"),
    ]);

    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        status: "joined",
        community_id: "community-id",
        host: "127.0.0.1",
        role: "member",
      }),
    });
  });

  await page.goto("/invite/browser-code");
  await page.getByRole("button", { name: "Join in browser" }).click();
  await expect(page).toHaveURL("/");
  expect(claimObserved).toBe(true);
});

for (const [sentinel, guidance] of [
  [
    "invite_restricted",
    "This account, or the account that owns it, is restricted in this community. Contact a community administrator. If the restriction is temporary, try again after it ends.",
  ],
  [
    "invite_owner_mismatch",
    "This account does not match its recorded owner. Use the correct account or owner identity to join this community.",
  ],
]) {
  test(`invite shows recovery for ${sentinel} without automatically retrying`, async ({
    page,
  }) => {
    await page.addInitScript(() => {
      Object.assign(window, {
        nostr: {
          async getPublicKey() {
            return "ab".repeat(32);
          },
          async signEvent(event: Record<string, unknown>) {
            return {
              ...event,
              id: "cd".repeat(32),
              pubkey: "ab".repeat(32),
              sig: "ef".repeat(64),
            };
          },
        },
      });
    });
    await page.route("**/api/join-policy", (route) =>
      route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ policy: null }),
      }),
    );
    let attempts = 0;
    await page.route("**/api/invites/claim", async (route) => {
      attempts++;
      expect(route.request().postDataJSON()).toEqual({ code: "browser-code" });
      await route.fulfill({
        status: 403,
        contentType: "application/json",
        body: JSON.stringify({ error: sentinel }),
      });
    });
    await page.goto("/invite/browser-code");
    const join = page.getByRole("button", { name: "Join in browser" });
    await join.click();
    await expect(page.getByRole("alert")).toHaveText(guidance);
    await expect(join).toBeEnabled();
    expect(attempts).toBe(1);
    await expect(page).toHaveURL(/\/invite\/browser-code$/);
    await join.click();
    await expect(page.getByRole("alert")).toHaveText(guidance);
    expect(attempts).toBe(2);
  });
}

for (const architecture of ["unknown", "x64"]) {
  test(`invite explains Mac support for ${architecture} architecture`, async ({
    browser,
  }) => {
    const context = await browser.newContext({
      userAgent:
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/26.5 Safari/605.1.15",
    });
    await context.addInitScript((architecture) => {
      Object.defineProperties(navigator, {
        platform: { configurable: true, value: "MacIntel" },
        maxTouchPoints: { configurable: true, value: 0 },
        userAgentData: {
          configurable: true,
          value:
            architecture === "unknown"
              ? undefined
              : {
                  platform: "macOS",
                  getHighEntropyValues: async () => ({
                    architecture: "x86",
                    bitness: "64",
                  }),
                },
        },
      });
    }, architecture);
    await context.route(ZION_RELEASES_PAGE, (route) =>
      route.fulfill({
        contentType: "text/html",
        body: "Installer destination",
      }),
    );
    const page = await context.newPage();
    await page.route("**/api/join-policy", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ policy: null }),
      });
    });
    await page.route("https://api.github.com/**", async (route) => {
      await route.fulfill({
        json: [
          {
            draft: false,
            prerelease: true,
            assets: [
              {
                name: "Buzz_0.4.9_aarch64.dmg",
                browser_download_url:
                  "https://github.com/block/buzz-app/releases/download/v0.4.9/Buzz_0.4.9_aarch64.dmg",
              },
            ],
          },
        ],
      });
    });

    await page.goto("/invite/demo-code");
    const download = page.getByRole("link", { name: "Download Zion" });
    await expect(download).toHaveAttribute("aria-haspopup", "dialog");
    await download.click();

    const chooser = page.getByRole("dialog", {
      name: "Which Mac do you have?",
    });
    await expect(chooser).toBeVisible();
    await expect(
      chooser.getByRole("link", { name: /Apple Silicon Mac/ }),
    ).toContainText("Mac with an Apple M-series chip");
    await expect(chooser.getByRole("link", { name: /Older Mac/ })).toHaveCount(
      0,
    );
    await expect(
      chooser.getByText(
        "Zion for Mac requires Apple Silicon. Intel Macs are not supported.",
      ),
    ).toBeVisible();
    await expect(chooser.getByText("About This Mac")).toBeVisible();

    const openedPagePromise = context.waitForEvent("page");
    await chooser.getByRole("link", { name: /Apple Silicon Mac/ }).click();
    const openedPage = await openedPagePromise;
    await expect(chooser).toBeHidden();
    await expect(openedPage).toHaveURL(ZION_RELEASES_PAGE);
    await expect(page).toHaveURL(/\/invite\/demo-code$/);
    await openedPage.close();

    await download.click();
    await expect(chooser).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(chooser).toBeHidden();
    await expect(download).toBeFocused();
    await context.close();
  });
}

test("invite download opens Zion releases instead of upstream artifacts on every platform", async ({
  browser,
}) => {
  const devices = [
    {
      name: "iPhone Safari",
      expectedUrl: ZION_RELEASES_PAGE,
      platform: "iPhone",
      userAgent:
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15",
      maxTouchPoints: 5,
    },
    {
      name: "iPadOS desktop mode",
      expectedUrl: ZION_RELEASES_PAGE,
      platform: "MacIntel",
      userAgent:
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15",
      maxTouchPoints: 5,
    },
    {
      name: "Android phone",
      expectedUrl: ZION_RELEASES_PAGE,
      platform: "Linux armv8l",
      userAgent:
        "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 Mobile",
      maxTouchPoints: 5,
    },
    {
      name: "Fire tablet",
      expectedUrl: ZION_RELEASES_PAGE,
      platform: "Linux armv8l",
      userAgent:
        "Mozilla/5.0 (Linux; Android 9; KFMAWI) AppleWebKit/537.36 Silk/126.0 like Chrome/126.0.0.0 Safari/537.36",
      maxTouchPoints: 5,
    },
    {
      name: "ChromeOS",
      expectedUrl: ZION_RELEASES_PAGE,
      platform: "Linux x86_64",
      userAgent: "Mozilla/5.0 (X11; CrOS x86_64 16093.68.0) AppleWebKit/537.36",
      maxTouchPoints: 0,
    },
  ];

  for (const device of devices) {
    const context = await browser.newContext({ userAgent: device.userAgent });
    await context.addInitScript(({ platform, maxTouchPoints }) => {
      Object.defineProperties(navigator, {
        platform: { configurable: true, value: platform },
        maxTouchPoints: { configurable: true, value: maxTouchPoints },
        userAgentData: {
          configurable: true,
          value: {
            platform,
            mobile: maxTouchPoints > 0,
            // The releases page must not wait for desktop architecture hints.
            getHighEntropyValues: () => new Promise(() => {}),
          },
        },
      });
    }, device);
    await context.addInitScript(() => {
      sessionStorage.setItem(
        "buzz.latestDownload.v2",
        JSON.stringify({
          expiresAt: Date.now() + 60 * 60 * 1000,
          platform: { operatingSystem: "linux", architecture: "x64" },
          url: "https://github.com/block/buzz-app/releases/download/v0.4.9/Buzz_0.4.9_x86_64.AppImage",
        }),
      );
    });
    const page = await context.newPage();
    await page.route("**/api/join-policy", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ policy: null }),
      });
    });
    let releaseRequests = 0;
    await page.route("https://api.github.com/**", async (route) => {
      releaseRequests += 1;
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        headers: { "Access-Control-Allow-Origin": "*" },
        body: JSON.stringify([
          {
            draft: false,
            prerelease: true,
            assets: [
              {
                name: "Buzz_0.4.9_x86_64.AppImage",
                browser_download_url:
                  "https://github.com/block/buzz-app/releases/download/v0.4.9/Buzz_0.4.9_x86_64.AppImage",
              },
            ],
          },
        ]),
      });
    });

    await page.goto("/invite/demo-code");
    await page.waitForLoadState("networkidle");
    await expect(
      page.getByRole("link", { name: "Download Zion" }),
      device.name,
    ).toHaveAttribute("href", device.expectedUrl);
    expect(releaseRequests, device.name).toBe(0);
    await expect(
      page.getByRole("link", { name: "Browse releases" }),
    ).toHaveCount(0);
    await context.route(device.expectedUrl, (route) =>
      route.fulfill({ contentType: "text/html", body: "Store destination" }),
    );
    const destination = context.waitForEvent("page");
    await page.getByRole("link", { name: "Download Zion" }).click();
    await expect(await destination).toHaveURL(device.expectedUrl);
    await context.close();
  }
});

test("invite shows community artwork and name with a text-only fallback", async ({
  page,
}) => {
  await page.route("**/api/join-policy", (route) =>
    route.fulfill({ json: { policy: null } }),
  );
  await page.route("https://api.github.com/**", (route) =>
    route.fulfill({ json: [] }),
  );
  let metadata: { name: string; icon?: string } = {
    name: "Honeycomb Studios",
    icon:
      "data:image/svg+xml," +
      encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" fill="#D7D72E"/></svg>',
      ),
  };
  await page.route("http://127.0.0.1:4173/", (route) => {
    if (route.request().headers().accept === "application/nostr+json")
      return route.fulfill({ json: metadata });
    return route.continue();
  });
  for (const width of [1280, 375]) {
    await page.setViewportSize({ width, height: 850 });
    await page.goto("/invite/visual-preview");
    await expect(page.locator(".invite-community")).toHaveText(
      "Honeycomb Studios",
    );
    await expect(page.locator(".invite-community-icon")).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Accept invite in Zion" }),
    ).toHaveAttribute(
      "href",
      "buzz://join?relay=ws%3A%2F%2F127.0.0.1%3A4173&code=visual-preview",
    );
    const widths = await page.evaluate(() => ({
      button: document
        .querySelector(".invite-actions a")
        ?.getBoundingClientRect().width,
      row: document.querySelector(".invite-actions")?.getBoundingClientRect()
        .width,
      overflow: document.documentElement.scrollWidth > innerWidth,
    }));
    expect(widths.button).toBe(widths.row);
    expect(widths.overflow).toBe(false);
  }
  metadata = { name: "Honeycomb Studios", icon: "/missing-community-icon.png" };
  await page.goto("/invite/visual-preview");
  await expect(page.locator(".invite-community")).toHaveText(
    "Honeycomb Studios",
  );
  await expect(page.locator(".invite-community-icon")).toBeHidden();
  metadata = { name: "Buzz Relay" };
  await page.goto("/invite/visual-preview");
  await expect(page.locator(".invite-community")).toHaveText("127.0.0.1:4173");
  await expect(page.locator(".invite-community-icon")).toHaveCount(0);
});

test("invite Zion slash marks preserve decorative motion and reduced-motion resizing", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.route("**/api/join-policy", (route) =>
    route.fulfill({ json: { policy: null } }),
  );
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/invite/resize-preview");
  const positions = () =>
    page.locator(".zion-sprite").evaluateAll((sprites) =>
      sprites.map((sprite) => {
        const node = sprite.parentElement;
        const field = node?.parentElement;
        if (!node || !field) throw new Error("Missing bee field");
        const transform = new DOMMatrix(getComputedStyle(node).transform);
        return {
          x: transform.m41 / field.clientWidth,
          y: transform.m42 / field.clientHeight,
        };
      }),
    );
  await expect(page.locator(".zion-sprite")).toHaveCount(24);
  const mark = page.locator(".zion-sprite").first();
  await expect(mark).toHaveAttribute("aria-hidden", "true");
  await expect(mark.locator("path")).toHaveAttribute(
    "d",
    "M16 30 32 12h20L36 30H16Z M12 52 28 34h20L32 52H12Z",
  );
  const original = await positions();
  for (const viewport of [
    { width: 700, height: 1000 },
    { width: 700, height: 700 },
    { width: 1800, height: 1200 },
  ]) {
    await page.setViewportSize(viewport);
    await expect
      .poll(async () => {
        const current = await positions();
        return Math.max(
          ...current.map((p, i) =>
            Math.max(
              Math.abs(p.x - original[i].x),
              Math.abs(p.y - original[i].y),
            ),
          ),
        );
      })
      .toBeLessThan(0.001);
    await expect(page.locator(".zion-sprite")).toHaveCount(24);
  }
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await expect
    .poll(async () => {
      const current = await positions();
      return Math.max(...current.map((p, i) => Math.abs(p.x - original[i].x)));
    })
    .toBeGreaterThan(0.001);
});
