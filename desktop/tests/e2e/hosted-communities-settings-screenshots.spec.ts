import { expect, test } from "@playwright/test";

import { waitForAnimations } from "../helpers/animations";
import { installMockBridge } from "../helpers/bridge";
import { openSettings } from "../helpers/settings";

const OUTDIR = "test-results/hosted-communities";
const DEFAULT_MOCK_PUBKEY = "deadbeef".repeat(8);

test.beforeEach(async ({ page }) => {
  await installMockBridge(page, {
    builderlabAuth: {
      email: "owner@example.com",
      expiresAt: "2099-01-01T00:00:00Z",
    },
    builderlabIdentity: { pubkey_hex: DEFAULT_MOCK_PUBKEY },
    builderlabCommunities: [
      {
        id: "active-community",
        name: "E2E Test",
        normalized_host: "localhost:3000",
      },
      {
        id: "other-community",
        name: "Design studio",
        normalized_host: "design-studio.communities.buzz.xyz",
      },
    ],
  });
  await page.goto("/");
  await openSettings(page);
});

test("hosted communities settings entry remains disabled", async ({ page }) => {
  const hostedCommunitiesNav = page.getByTestId(
    "settings-nav-hosted-communities",
  );
  await expect(hostedCommunitiesNav).toBeVisible();
  await expect(hostedCommunitiesNav).toBeDisabled();
  await expect(page.getByTestId("settings-panel-profile")).toBeVisible();

  await waitForAnimations(page);
  await page.getByTestId("settings-sidebar").screenshot({
    path: `${OUTDIR}/01-hosted-communities-disabled.png`,
  });
});
