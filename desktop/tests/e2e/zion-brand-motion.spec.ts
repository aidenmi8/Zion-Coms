import { expect, test, type Locator, type Page } from "@playwright/test";

import { installMockBridge, TEST_IDENTITIES } from "../helpers/bridge";
import { seedActiveIdentity } from "../helpers/onboarding";

const BLANK_TYLER_IDENTITY = {
  ...TEST_IDENTITIES.tyler,
  username: "",
};

const COMMUNITY_ONBOARDING_TRANSACTION_STORAGE_KEY =
  "buzz-community-onboarding-transaction.v1";

async function seedCommunityProfileStage(page: Page, transactionId: string) {
  await seedActiveIdentity(page, BLANK_TYLER_IDENTITY);
  await page.addInitScript(
    ({ pubkey, storageKey, transactionId: currentTransactionId }) => {
      window.localStorage.setItem(
        `buzz-machine-onboarding-complete.v2:${pubkey}`,
        "true",
      );
      const timestamp = new Date().toISOString();
      window.localStorage.setItem(
        storageKey,
        JSON.stringify({
          id: currentTransactionId,
          source: "first-community",
          stage: "profile",
          relayUrl: "wss://default.example.com",
          communityName: "Default",
          communityId: "e2e-default-community",
          addedCommunity: true,
          createdAt: timestamp,
          updatedAt: timestamp,
        }),
      );
    },
    {
      pubkey: BLANK_TYLER_IDENTITY.pubkey,
      storageKey: COMMUNITY_ONBOARDING_TRANSACTION_STORAGE_KEY,
      transactionId,
    },
  );
}

async function openStarterTeam(page: Page, transactionId: string) {
  await seedCommunityProfileStage(page, transactionId);
  await installMockBridge(page, undefined, {
    relayWsUrl: "wss://default.example.com",
    skipOnboardingSeed: true,
  });
  await page.goto("/");
  await page.getByTestId("community-profile-name-key").fill("Morty QA");
  await page.getByTestId("community-profile-next").click();
  await expect(page.getByText("Meet your starter team")).toBeVisible();
}

function starterPersonaCard(page: Page, name: "Fizz" | "Honey" | "Bumble") {
  return page.getByTestId(`starter-persona-${name.toLowerCase()}`);
}

async function expectNoBeeOrBuzzLogoClasses(locator: Locator) {
  const classNames = await locator.evaluate((node) => {
    const elements = [
      node,
      ...Array.from(node.querySelectorAll("[class]")),
    ] as Array<Element & { className?: string | { baseVal?: string } }>;

    return elements
      .map((element) => {
        if (typeof element.className === "string") {
          return element.className;
        }
        return element.className?.baseVal ?? "";
      })
      .join(" ");
  });

  expect(classNames).not.toMatch(/bee-|buzz-logo/);
}

test("Zion brand motion shows neutral starter-team presence with staggered settle", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await openStarterTeam(page, "zion-brand-motion-settle");

  for (const [index, name] of ["Fizz", "Honey", "Bumble"].entries()) {
    const card = starterPersonaCard(page, name);
    const presence = card.locator(
      '[data-brand-surface="starter-team-presence"]',
    );

    await expect(card).toContainText(name);
    await expect(card).toHaveAttribute(
      "style",
      new RegExp(`--stagger-index:\\s*${index}`),
    );
    await expect(presence).toHaveAttribute(
      "data-zion-variant",
      "agent-entrance",
    );
    await expectNoBeeOrBuzzLogoClasses(presence);
  }

  const leadPresence = starterPersonaCard(page, "Fizz").locator(
    '[data-brand-surface="starter-team-presence"]',
  );
  await expect(leadPresence).toHaveAttribute("data-phase", "entering");
  await expect(leadPresence).toHaveAttribute("data-phase", "settled", {
    timeout: 4_000,
  });

  for (const name of ["Fizz", "Honey", "Bumble"] as const) {
    const presence = starterPersonaCard(page, name).locator(
      '[data-brand-surface="starter-team-presence"]',
    );
    await expect(presence).toHaveAttribute("data-phase", "settled");
    await expect(
      presence.locator('[data-brand-surface="zion-motion"]'),
    ).toHaveAttribute("data-playing", "false");
  }
});

test("Zion brand motion keeps starter-team presence settled under reduced motion", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openStarterTeam(page, "zion-brand-motion-reduced");

  for (const name of ["Fizz", "Honey", "Bumble"] as const) {
    const card = starterPersonaCard(page, name);
    const presence = card.locator(
      '[data-brand-surface="starter-team-presence"]',
    );

    await expect(card).toContainText(name);
    await expect(presence).toHaveAttribute("data-phase", "reduced-motion");
    await expect(
      presence.locator('[data-brand-surface="zion-motion"]'),
    ).toHaveAttribute("data-playing", "false");

    const animationName = await presence.evaluate((node) => {
      const mark = node.querySelector(".zion-motion__mark");
      return mark ? getComputedStyle(mark).animationName : null;
    });
    expect(animationName).toBe("none");
    await expectNoBeeOrBuzzLogoClasses(presence);
  }
});
