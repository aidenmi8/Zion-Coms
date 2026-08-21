import { expect, test } from "@playwright/test";

import { waitForAnimations } from "../helpers/animations";
import { installMockBridge } from "../helpers/bridge";
import { openSettings } from "../helpers/settings";

const OUTDIR = "test-results/local-communities";

test.beforeEach(async ({ page }) => {
  await installMockBridge(page);
  await page.goto("/");
  await openSettings(page, "local-communities");
});

test("local communities settings shows Zion-local creation", async ({
  page,
}) => {
  await expect(page.getByTestId("local-communities-settings")).toBeVisible();
  await expect(
    page.getByText("No external account or hosted service is required."),
  ).toBeVisible();
  await expect(page.getByLabel("Community address")).toBeVisible();
  await waitForAnimations(page);
  await page.getByTestId("settings-sidebar").screenshot({
    path: `${OUTDIR}/01-local-communities.png`,
  });
});

test("settings identifies the installed Zion build", async ({ page }) => {
  await expect(page.getByTestId("settings-version")).toContainText(
    "Zion - V0.0.0-e2e DV",
  );
  await expect(page.getByTestId("settings-build-info")).toContainText("Build ");
  await expect(page.getByTestId("settings-build-info")).toContainText(
    "commit ",
  );
});

test("local creation connects through the active relay path", async ({
  page,
}) => {
  await page.getByLabel("Community address").fill("north-star");
  await expect(page.getByText("That Zion address is available.")).toBeVisible();
  await page.getByTestId("local-community-create-submit").click();
  await expect
    .poll(() =>
      page.evaluate(() => window.localStorage.getItem("buzz-communities")),
    )
    .toContain("ws://localhost:3000/c/north-star");
});
