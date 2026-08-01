import { expect, test } from "@playwright/test";

test("invite renders the Zion motion contract and preserves its deep link", async ({
  page,
}) => {
  await page.route("**/api/join-policy", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ policy: null }),
    });
  });
  await page.goto("/invite/zion-motion-smoke");

  const motion = page.locator('[data-brand-surface="zion-motion"]');
  await expect(motion).toHaveAttribute("data-zion-variant", "onboarding");
  await expect(motion).toHaveAttribute("data-playing", "true");
  await expect(motion.locator("img")).toBeVisible();
  await expect(
    page.getByRole("link", { name: "Accept invite in Zion" }),
  ).toHaveAttribute("href", /^zion:\/\/join\?/);
});

test("invite motion is static under reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.route("**/api/join-policy", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ policy: null }),
    });
  });
  await page.goto("/invite/zion-motion-reduced");

  const motion = page.locator('[data-brand-surface="zion-motion"]');
  await expect(motion).toHaveAttribute("data-reduced-motion", "true");
  await expect(motion.locator("img")).toHaveCSS("animation-name", "none");
});
