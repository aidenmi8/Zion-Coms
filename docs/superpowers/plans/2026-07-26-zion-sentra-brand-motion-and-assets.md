# Zion/Sentra Brand Motion and Asset Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every product-facing Buzz bee/logo animation and branded asset with the approved calm, precise Zion/Sentra system across desktop, mobile, web, admin, and DMG packaging while preserving all Buzz compatibility surfaces.

**Architecture:** A provenance-checked asset intake produces canonical Zion/Sentra derivatives and a checked-in manifest. Desktop, web, admin, and Flutter consume small platform adapters that share variant names, timings, reduced-motion behavior, and accessibility rules. Product-facing consumers migrate by explicit file path; internal Buzz identifiers and legacy asset URLs remain aliases.

**Tech Stack:** React 19, Vite, CSS, `motion` 12, Playwright, Biome, Node test runner, Flutter/Riverpod/hooks, Tauri 2/Rust, `sips`, and existing packaging scripts.

## Global Constraints

- The authoritative artwork source is `/Users/Aiden-Mi8/Library/Mobile Documents/com~apple~CloudDocs/SENTRA-MAIN/logo and media/`.
- The previous `Sentra-Main/media/sentra-identity-v1/production-final` folder is not an approved source and must not be used for production replacement.
- Preserve `BUZZ_*`, `buzz://`, `buzz` package/module names, bundle identifier `xyz.block.buzz.app`, relay paths, Docker names, protocol names, and internal storage/theme keys.
- Do not perform substring renames; strings such as `bSion`, `BUZZ_*`, package names, and protocol identifiers require explicit allowlisting.
- Preserve `/buzz.svg`, `/favicon.svg`, `/app-icon@2x.png`, `/app-icon@3x.png`, and `/landing/buzz-wordmark.png` as legacy aliases serving approved Zion artwork.
- Use deep-purple/near-black surfaces, graphite panels, silver/white marks, and muted lavender accents for brand surfaces and motion.
- Use calm precise motion: luminance breathe, one-way reveal, gentle settling, and single connection pulses; no spinning or bee/flapping motion.
- Reduced motion always resolves to a static mark or fully settled state.
- Generic UI transitions remain unchanged unless they visibly carry Buzz/bee/logo branding.
- `Logos-sentra-v2-1.png` is typography reference-only; static PNGs are never duplicated as fake animation frames.
- Stage only exact task paths. Do not use `git add .`, `git reset --hard`, or broad checkout commands.
- Activate the repository toolchain before Git/hooks and use the existing Hermit/pre-commit workflow where the environment permits it.

---

## Task 0: Freeze the baseline and classify existing draft changes

**Files:**

- Read: `AGENTS.md`
- Read: `docs/superpowers/specs/2026-07-26-zion-sentra-brand-motion-design.md`
- Read: current `git status --short` and `git diff --name-only`
- Create outside the repository: `/private/tmp/zion-brand-motion-implementation-baseline.txt`

**Interfaces:**

- Consumes: the already-dirty worktree containing the earlier Zion rebrand draft.
- Produces: a path-level baseline that prevents the implementation from
  reverting unrelated user changes or silently mixing old and new rebrand work.

- [ ] **Step 1: Record the worktree without changing it**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-
git status --short
git diff --name-only
git ls-files --others --exclude-standard
```

Save the output to `/private/tmp/zion-brand-motion-implementation-baseline.txt`.

- [ ] **Step 2: Partition paths into explicit buckets**

Classify each path as `brand-scope`, `pre-existing-user-change`, or
`untracked-worktree`. The brand bucket includes the paths named in Tasks 1–8;
the other buckets are preserved and never staged by this plan.

- [ ] **Step 3: Verify the compatibility baseline**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-
rg -n -w 'bSion|Sion|Zion' desktop mobile web admin-web crates --glob '*.{ts,tsx,rs,dart,css,html,json,yaml}'
rg -n 'BUZZ_|buzz://|xyz\.block\.buzz\.app' desktop mobile web admin-web crates --glob '*.{ts,tsx,rs,dart,css,html,json,yaml}'
```

Do not edit results from this step. They are the protection list for later
visible-brand scans.

- [ ] **Step 4: Keep the baseline record outside Git**

Do not stage or commit the baseline record or any existing application change
in this task. The record is an execution safeguard and remains at
`/private/tmp/zion-brand-motion-implementation-baseline.txt`.

---

## Task 1: Intake the authoritative artwork and create the canonical manifest

**Files:**

- Create: `scripts/intake-zion-brand-assets.mjs`
- Create: `branding/zion-brand-manifest.json`
- Modify: `desktop/scripts/validate-zion-brand-assets.mjs`
- Modify: `desktop/src/shared/ui/zion-brand/brandAssetManifest.ts`
- Test: `desktop/src/shared/ui/zion-brand/brandAssetManifest.test.mjs`
- Output assets: canonical files under `desktop/public/branding/`, the canonical web icon under `web/src/assets/`, the canonical admin mark under `admin-web/public/`, and the explicit legacy aliases consumed by those apps

**Interfaces:**

- Consumes: the iCloud source folder and the source filenames listed in the
  design spec.
- Produces: canonical files, compatibility aliases, provenance metadata, and a
  manifest consumed by all later motion and packaging tasks.

The manifest must provide this typed shape; the intake script populates every
record from the source files rather than accepting hand-entered dimensions or
hashes:

```ts
type BrandManifest = {
  version: 1;
  sourceDirectory: string;
  assets: Record<string, {
    role: string;
    canonicalPath: string;
    aliases: string[];
    sourceFile: string;
    sha256: string;
    width: number;
    height: number;
    hasAlpha: boolean;
    colorSpace: string;
  }>;
  motion: {
    frameSourcePolicy: "dedicated-frame-or-code-native";
    variants: string[];
    reducedMotion: "static";
    loader: { durationMs: number; loop: boolean; mode: "code-native" | "dedicated-frame"; reducedMotion: "static" | "settled" };
    onboarding: { durationMs: number; settleMs: number; loop: boolean; mode: "code-native" | "dedicated-frame"; reducedMotion: "static" | "settled" };
    liveness: { durationMs: number; loop: boolean; mode: "code-native" | "dedicated-frame"; reducedMotion: "static" | "settled" };
    pairing: { durationMs: number; loop: boolean; mode: "code-native" | "dedicated-frame"; reducedMotion: "static" | "settled" };
    "agent-entrance": { durationMs: number; staggerMs: number; loop: boolean; mode: "code-native" | "dedicated-frame"; reducedMotion: "static" | "settled" };
  };
};
```

- [ ] **Step 1: Add the manifest contract test first**

Add assertions for canonical paths, the five variants, explicit aliases,
source provenance fields, and the rule that the typography reference is not a
shipped asset.

Run:

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/desktop
node --import ./test-loader.mjs --experimental-strip-types --test src/shared/ui/zion-brand/brandAssetManifest.test.mjs
```

Expected: the new provenance/variant assertions fail against the current
draft manifest.

- [ ] **Step 2: Implement the intake script**

`intake-zion-brand-assets.mjs` must:

1. read `ZION_BRAND_SOURCE_DIR` or default to the exact iCloud path;
2. fail with the full path and the OS error when the directory is unreadable;
3. never inspect or copy `production-final` as a fallback;
4. enumerate selected PNG/SVG source files and preserve the source format in the manifest;
5. calculate SHA-256 with Node `crypto`;
6. collect dimensions, alpha, and format using `sips -g pixelWidth -g
   pixelHeight -g hasAlpha -g format`;
7. copy only approved source files to canonical destinations;
8. generate derivatives with `sips` without changing source files; and
9. write `branding/zion-brand-manifest.json` atomically.

If TCC blocks the iCloud path, stop and report the exact error. The permitted
recovery is an explicit user-staged copy under `/private/tmp/zion-brand-source/`;
the script must not choose another folder automatically.

- [ ] **Step 3: Run intake and verify every recorded value**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-
ZION_BRAND_SOURCE_DIR="/Users/Aiden-Mi8/Library/Mobile Documents/com~apple~CloudDocs/SENTRA-MAIN/logo and media" \
node scripts/intake-zion-brand-assets.mjs
cd desktop
pnpm validate:brand-assets
```

Compare the manifest’s filenames and hashes with the source folder. A missing
source or derivative is a failed gate, not a reason to use the old pack.

- [ ] **Step 4: Make React consumers read the manifest**

Replace hard-coded source descriptions and extensions in
`brandAssetManifest.ts` with the checked-in manifest data while preserving typed
exports used by `ZionMark` and later adapters. Consumers must ask the manifest
for the canonical URL instead of assuming that the source is SVG.

- [ ] **Step 5: Run the focused test and commit the intake unit**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/desktop
node --import ./test-loader.mjs --experimental-strip-types --test src/shared/ui/zion-brand/brandAssetManifest.test.mjs
# Add each generated canonical asset path listed in branding/zion-brand-manifest.json explicitly;
# never pass public/branding as a directory operand.
git add ../branding/zion-brand-manifest.json ../scripts/intake-zion-brand-assets.mjs scripts/validate-zion-brand-assets.mjs src/shared/ui/zion-brand/brandAssetManifest.ts src/shared/ui/zion-brand/brandAssetManifest.test.mjs public/branding/sentra-dmg-background-1200x800.png public/branding/sentra-dmg-background-600x400.png public/branding/sentra-lockup-dark.svg public/branding/sentra-lockup-horizontal.svg public/branding/sentra-lockup-light.svg public/branding/sentra-status-glyph.svg public/branding/sentra-wordmark.svg public/branding/zion-app-icon-1024.png public/branding/zion-app-icon@2x.png public/branding/zion-app-icon@3x.png public/branding/zion-mark.svg public/buzz.svg public/landing/buzz-wordmark.png ../web/src/assets/app-icon@3x.png ../web/src/assets/zion-app-icon@3x.png ../admin-web/public/favicon.svg ../admin-web/public/zion-mark.svg
git commit -m "feat: intake canonical Zion brand assets"
```

Include only files actually produced by the intake gate in the `git add`
command.

---

## Task 2: Implement the shared calm-precise motion contract

**Files:**

- Create: `scripts/generate-zion-motion-manifest.mjs`
- Modify: `desktop/src/shared/ui/zion-brand/ZionMotion.tsx`
- Modify: `desktop/src/shared/ui/zion-brand/ZionMark.tsx`
- Modify: `desktop/src/shared/ui/zion-brand/zion-motion.css`
- Modify: `desktop/src/shared/ui/zion-brand/ZionBrandField.tsx`
- Modify: `desktop/src/shared/ui/zion-brand/brandAssetManifest.ts`
- Test: `desktop/src/shared/ui/zion-brand/ZionMotion.test.mjs`

**Interfaces:**

- Consumes: the `motion` section of `branding/zion-brand-manifest.json` and the canonical asset
  manifest from Task 1.
- Produces: `ZionMotion` with the stable interface
  `variant`, `playing`, `loop`, `ariaLabel`, `className`, and `decorative`; a
  deterministic `frameAtTime`/CSS fallback contract; and a field that pauses
  under reduced motion.

Extend the `motion` section of `branding/zion-brand-manifest.json` to encode:

```json
{
  "frameSourcePolicy": "dedicated-frame-or-code-native",
  "loader": { "durationMs": 1800, "loop": true, "mode": "code-native", "reducedMotion": "static" },
  "onboarding": { "durationMs": 900, "settleMs": 2400, "loop": false, "mode": "code-native", "reducedMotion": "settled" },
  "liveness": { "durationMs": 1400, "loop": true, "mode": "code-native", "reducedMotion": "static" },
  "pairing": { "durationMs": 1800, "loop": false, "mode": "code-native", "reducedMotion": "settled" },
  "agent-entrance": { "durationMs": 900, "staggerMs": 320, "loop": false, "mode": "code-native", "reducedMotion": "settled" }
}
```

- [ ] **Step 1: Write sequencing and accessibility tests**

Cover the following cases in `ZionMotion.test.mjs`:

```js
assert.equal(frameAtTime(["a", "b", "c"], 250, 100), "c");
assert.equal(frameAtTime(["a", "b", "c"], 350, 100), "a");
assert.equal(frameAtTime(["a", "b", "c"], 350, 100, false), "c");
assert.equal(frameAtTime([], 0, 100), null);
assert.match(css, /prefers-reduced-motion: reduce/);
assert.match(css, /animation: none/);
```

Add a render-contract assertion that decorative marks have an empty `alt` and
status marks expose the caller’s label once through the parent status region.

- [ ] **Step 2: Implement the manifest generator**

The generator reads the JSON contract and writes platform-neutral timing data
without creating fake frame files. It must fail on an unknown variant, a
non-positive duration, or a frame path that is not explicitly marked as a
dedicated animation frame.

- [ ] **Step 3: Implement `ZionMotion` and CSS behavior**

Use these state attributes so tests and platform adapters have a stable hook:

```tsx
<span
  className={`zion-motion zion-motion--${variant}`}
  data-brand-surface="zion-motion"
  data-zion-variant={variant}
  data-playing={playing ? "true" : "false"}
  data-loop={loop ? "true" : "false"}
>
  <ZionMark decorative={decorative} />
</span>
```

Implement loader breathe, onboarding reveal/settle, liveness pulse, pairing
one-shot pulse, and an agent-entrance class. `playing=false`, `loop=false`, and
reduced motion must produce deterministic settled output.

- [ ] **Step 4: Implement the sparse field**

Keep the field deterministic and `aria-hidden`, reduce the number of marks to a
quiet composition matching the approved mockup, and cancel its animation frame
on unmount or reduced-motion preference.

- [ ] **Step 5: Run focused tests and commit the motion core**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/desktop
node --import ./test-loader.mjs --experimental-strip-types --test src/shared/ui/zion-brand/ZionMotion.test.mjs src/shared/ui/zion-brand/brandAssetManifest.test.mjs
pnpm typecheck
git add ../branding/zion-brand-manifest.json ../scripts/generate-zion-motion-manifest.mjs src/shared/ui/zion-brand/ZionMotion.tsx src/shared/ui/zion-brand/ZionMark.tsx src/shared/ui/zion-brand/zion-motion.css src/shared/ui/zion-brand/ZionBrandField.tsx src/shared/ui/zion-brand/brandAssetManifest.ts src/shared/ui/zion-brand/ZionMotion.test.mjs
git commit -m "feat: add calm Zion brand motion contract"
```

---

## Task 3: Migrate desktop branded consumers and starter-team motion

**Files:**

- Modify: `desktop/src/app/App.tsx`
- Modify: `desktop/playwright.config.ts`
- Modify: `desktop/src/shared/ui/zion-brand/zion-motion.css`
- Modify: `desktop/src/features/onboarding/ui/MachineOnboardingFlow.tsx`
- Modify: `desktop/src/features/onboarding/ui/OnboardingChrome.tsx`
- Modify: `desktop/src/features/onboarding/ui/PendingInviteGate.tsx`
- Modify: `desktop/src/features/onboarding/ui/RuntimeIcon.tsx`
- Modify: `desktop/src/features/onboarding/ui/SetupStep.tsx`
- Modify: `desktop/src/features/communities/ui/HostedCommunityOnboarding.tsx`
- Modify: `desktop/src/features/agents/ui/AgentSessionTranscriptList.tsx`
- Modify: `desktop/src/features/agents/ui/TurnLivenessIndicator.tsx`
- Modify: `desktop/src/features/onboarding/ui/CommunityOnboardingFlow.tsx`
- Modify: `desktop/src/features/onboarding/ui/WelcomeKickoffStage.tsx`
- Create: `desktop/src/features/onboarding/ui/StarterTeamPresence.tsx`
- Create: `desktop/src/features/onboarding/ui/starter-team-presence.css`
- Delete after migration: `desktop/src/shared/ui/buzz-logo/*` and `desktop/src/features/onboarding/ui/LandingBees.tsx`
- Modify: `desktop/tests/e2e/boot-splash.spec.ts`
- Create: `desktop/tests/e2e/zion-brand-motion.spec.ts`
- Test: `desktop/src/features/onboarding/ui/StarterTeamPresence.test.mjs`

**Interfaces:**

- Consumes: `ZionMotion` variants from Task 2.
- Produces: all desktop branded surfaces with stable `data-brand-surface`,
  `data-zion-variant`, and existing behavior/test IDs; starter-team persona
  names remain `Fizz`, `Honey`, and `Bumble` while their bee-like artwork is
  replaced by neutral presence forms.

- [ ] **Step 1: Update the boot-splash contract before consumer changes**

Replace the `.bee-wing-left` assertion with checks for:

```ts
await expect(page.locator('[data-brand-surface="zion-motion"]')).toHaveAttribute(
  "data-zion-variant",
  "loader",
);
await expect(page.locator('[data-brand-surface="zion-motion"]')).toHaveAttribute(
  "data-playing",
  "true",
);
```

Add a reduced-motion context that asserts the loader is visible and the
computed animation is `none`.

- [ ] **Step 2: Migrate boot, switch, onboarding, pending, and runtime consumers**

Keep existing status copy, community transactions, runtime install behavior,
and router behavior unchanged. Replace only old brand visuals and branded
colors with explicit `ZionMotion`/`ZionMark` variants.

- [ ] **Step 3: Replace starter-team images with neutral presence forms**

Create `StarterTeamPresence` with a typed variant map:

```ts
type StarterTeamName = "Fizz" | "Honey" | "Bumble";
type StarterTeamPresenceProps = {
  name: StarterTeamName;
  phase: "entering" | "settled" | "reduced-motion";
};
```

Use CSS/SVG geometry rather than bee imagery. Preserve `data-testid`
attributes, decorative semantics, stagger order, exit callback, and the
existing welcome-stage timing contract.

- [ ] **Step 4: Migrate transcript and liveness consumers**

Keep active-turn logic and transcript row spring animations intact. Replace
only the Buzz/Fuzzy mark with the `liveness` variant and ensure the parent
status text remains the only accessible status announcement.

- [ ] **Step 5: Add focused starter-team and motion e2e coverage**

Assert the neutral presence surface, all three persona names, stagger state,
settled state, reduced-motion state, and no `.bee-*`/`buzz-logo` class in the
rendered brand surface.

- [ ] **Step 6: Run desktop focused checks and commit**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/desktop
pnpm typecheck
pnpm test -- src/shared/ui/zion-brand/ZionMotion.test.mjs src/features/onboarding/ui/StarterTeamPresence.test.mjs
pnpm test:e2e:smoke -- --grep "boot splash|Zion brand motion|starter team"
pnpm check
git add playwright.config.ts src/shared/ui/zion-brand/zion-motion.css src/app/App.tsx src/features/onboarding/ui/MachineOnboardingFlow.tsx src/features/onboarding/ui/OnboardingChrome.tsx src/features/onboarding/ui/PendingInviteGate.tsx src/features/onboarding/ui/RuntimeIcon.tsx src/features/onboarding/ui/SetupStep.tsx src/features/onboarding/ui/CommunityOnboardingFlow.tsx src/features/onboarding/ui/WelcomeKickoffStage.tsx src/features/onboarding/ui/StarterTeamPresence.tsx src/features/onboarding/ui/starter-team-presence.css src/features/onboarding/ui/StarterTeamPresence.test.mjs src/features/onboarding/ui/LandingBees.tsx src/features/communities/ui/HostedCommunityOnboarding.tsx src/features/agents/ui/AgentSessionTranscriptList.tsx src/features/agents/ui/TurnLivenessIndicator.tsx src/shared/ui/buzz-logo/BuzzLogoAnimation.tsx src/shared/ui/buzz-logo/BuzzMark.tsx src/shared/ui/buzz-logo/FlappingBee.tsx src/shared/ui/buzz-logo/FuzzyLogo.tsx src/shared/ui/buzz-logo/buzz-logo-animation.css tests/e2e/boot-splash.spec.ts tests/e2e/zion-brand-motion.spec.ts
git commit -m "feat: migrate desktop branded motion to Zion"
```

---

## Task 4: Add the Flutter motion adapter and migrate pairing

**Files:**

- Create: `mobile/lib/shared/brand/zion_brand_tokens.dart`
- Create: `mobile/lib/shared/brand/zion_brand_motion.dart`
- Create: `mobile/test/shared/brand/zion_brand_motion_test.dart`
- Create: `mobile/assets/images/zion-mark.svg` from the manifest `zionMark` derivative
- Create: `mobile/assets/images/sentra-lockup-light.svg` from the manifest `sentraLockupLight` derivative
- Create: `mobile/assets/images/sentra-lockup-dark.svg` from the manifest `sentraLockupDark` derivative
- Modify: `mobile/lib/features/pairing/pairing_page.dart`
- Modify: `mobile/test/features/pairing/pairing_page_test.dart`
- Modify: `mobile/pubspec.yaml` only if a newly approved asset needs an explicit entry
- Modify: `mobile/assets/images/zion-icon.png` only through the approved intake output

**Interfaces:**

- Consumes: the manifest timings from Task 2 and the approved PNG/SVG
  derivatives from Task 1.
- Produces: `ZionBrandMotion(variant:, playing:, loop:, label:)` as a
  `HookConsumerWidget` that honors `MediaQuery.disableAnimations` and exposes
  the same variant names as desktop.

- [ ] **Step 1: Add widget tests for motion states**

Cover initial loading, connection pulse, static reduced-motion rendering,
accessible label ownership, and the unchanged `nostrpair://`/`buzz://` input
hint.

- [ ] **Step 2: Implement the hook-based adapter**

Use `useAnimationController` and `AnimatedBuilder`/`FadeTransition`/`ScaleTransition`;
do not introduce a `StatefulWidget`, `print()`, a new animation dependency, or
an infinite controller when `disableAnimations` is true.

- [ ] **Step 3: Migrate `PairingPage`**

Use `loader` for the initial loading state, `pairing` when connection begins,
and the static Zion/Sentra treatment for the welcome state. Use the Zion mark
derivative for loader/liveness states and the contrast-appropriate Sentra
lockup derivative for onboarding/pairing states. Keep the visual mark
decorative and expose the state label through a parent live status region.
Preserve provider state, SAS verification, scanner navigation, copy, controls,
and error colors.

- [ ] **Step 4: Run Flutter checks and commit**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test test/shared/brand/zion_brand_motion_test.dart test/features/pairing/pairing_page_test.dart
git add lib/shared/brand/zion_brand_tokens.dart lib/shared/brand/zion_brand_motion.dart lib/features/pairing/pairing_page.dart test/shared/brand/zion_brand_motion_test.dart test/features/pairing/pairing_page_test.dart assets/images/zion-icon.png assets/images/zion-mark.svg assets/images/sentra-lockup-light.svg assets/images/sentra-lockup-dark.svg pubspec.yaml
git commit -m "feat: add calm Zion pairing motion"
```

Do not run `flutter run`, `flutter build`, `flutter clean`, or `flutter upgrade`.

---

## Task 5: Add the web motion adapter and migrate invite/static web branding

**Files:**

- Create: `web/src/shared/ui/zion-brand/ZionBrandMotion.tsx`
- Create: `web/src/shared/ui/zion-brand/zion-brand-motion.css`
- Create: `web/src/shared/ui/zion-brand/zionBrandMotion.test.mjs`
- Create: `web/src/assets/sentra-lockup-dark.svg` as an exact copy of the approved dark transparent lockup derivative; the shared web motion wrapper crops its glyph region for Zion product surfaces so the Sentra wordmark is not shown in product UI
- Modify: `web/src/features/invite/ui/InvitePage.tsx`
- Modify: `web/src/features/repos/ui/ReposPage.tsx`
- Create: `web/tests/e2e/zion-brand-motion.smoke.spec.ts`
- Modify: `web/playwright.config.ts` to preserve the existing `smoke.spec.ts`
  collection and include `**/*.smoke.spec.ts`, so the Zion motion smoke spec is
  included explicitly

**Interfaces:**

- Consumes: the shared variant names/timings and canonical icon/mark aliases.
- Produces: a web invite reveal and pairing CTA motion that uses the same
  deep-purple/lavender direction without changing invite protocol behavior.

- [ ] **Step 1: Add the web reduced-motion and variant contract test**

Assert `loader`, `onboarding`, `pairing`, and `reduced-motion` attributes;
assert that the legacy `buzz://` URL construction remains byte-for-byte
unchanged.

- [ ] **Step 2: Implement the web adapter**

Use CSS keyframes with `@media (prefers-reduced-motion: reduce)` and the same
`data-brand-surface`/`data-zion-variant` hooks as desktop. Keep generic Radix
tooltip and repository skeleton animations unchanged.

- [ ] **Step 3: Migrate invite and repository icon surfaces**

Replace the yellow/blue invite gradient with deep purple/graphite, use the
approved Zion mark and lavender CTA, and retain download URL/platform logic,
policy acceptance, and browser join behavior. Update the visible repository
app icon while preserving the legacy asset URL.

- [ ] **Step 4: Run web checks and commit**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/web
pnpm typecheck
pnpm check
pnpm build
pnpm build && pnpm exec playwright test --project=smoke --grep "invite|Zion brand"
git add src/shared/ui/zion-brand/ZionBrandMotion.tsx src/shared/ui/zion-brand/zion-brand-motion.css src/shared/ui/zion-brand/zionBrandMotion.test.mjs src/assets/sentra-lockup-dark.svg src/features/invite/ui/InvitePage.tsx src/features/repos/ui/ReposPage.tsx tests/e2e/zion-brand-motion.smoke.spec.ts playwright.config.ts
git commit -m "feat: migrate web Zion brand surfaces"
```

---

## Task 6: Migrate admin and Builderlab authentication surfaces

**Files:**

- Create: `admin-web/src/brand-contract.test.ts`
- Create: `admin-web/public/sentra-lockup-dark.svg` as an exact copy of the approved transparent dark lockup derivative for the visible header mark
- Modify: `admin-web/src/styles.css`
- Modify: `admin-web/src/App.tsx`
- Modify: `desktop/src-tauri/src/builderlab.rs`
- Test: inline `#[cfg(test)]` module in `desktop/src-tauri/src/builderlab.rs`

**Interfaces:**

- Consumes: canonical admin mark, the web motion contract, and the deep-purple
  surface tokens.
- Produces: admin header/active-state motion and a Builderlab completion page
  without the inline bee SVG or yellow/blue brand treatment.

- [ ] **Step 1: Add admin visual contract tests**

Assert the header exposes `Zion Admin`, the visible mark source is
`/sentra-lockup-dark.svg`, the shell has the deep-purple brand class, and the
legacy feedback storage key `buzz-admin-feedback-status` remains unchanged.
The legacy `/favicon.svg` alias remains untouched. Keep this as a deterministic
source-contract test in `admin-web/src/brand-contract.test.ts`; the admin app
does not need a second motion component for the single header mark.

- [ ] **Step 2: Replace admin shell styling**

Change only brand surfaces, header mark, active nav, favicon, and restrained
entry glow. Preserve report/feedback routes, record cards, error/status colors,
and data-fetch behavior.

- [ ] **Step 3: Replace Builderlab inline artwork and colors**

Replace `.bee`, `bee-mask`, and the yellow/blue background with the approved
inline Zion mark and deep-purple completion layout. Keep the authentication
callback path, title semantics, and `returnTo` behavior unchanged.

- [ ] **Step 4: Add Rust regression assertions**

In the local test module, assert:

```rust
assert!(AUTH_COMPLETE_HTML.contains("Zion"));
assert!(!AUTH_COMPLETE_HTML.contains("bee-mask"));
assert!(!AUTH_COMPLETE_HTML.contains("#d7d72e"));
assert!(AUTH_COMPLETE_HTML.contains("Authentication complete"));
```

- [ ] **Step 5: Run checks and commit**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/admin-web
pnpm check
pnpm build
cd ../desktop
cargo test --manifest-path src-tauri/Cargo.toml builderlab
git add public/sentra-lockup-dark.svg src/styles.css src/App.tsx src/brand-contract.test.ts ../desktop/src-tauri/src/builderlab.rs
git commit -m "feat: migrate admin and auth brand surfaces"
```

---

## Task 7: Replace packaging artwork and preserve aliases

**Files:**

- Create: `scripts/render-zion-dmg-background.swift`
- Create: `scripts/render-zion-icon.swift`
- Create: `scripts/build-zion-icns.mjs`
- Modify: `desktop/src-tauri/icons/dmg-background.png`
- Modify: `desktop/src-tauri/icons/buzz-source.png`
- Modify: `desktop/src-tauri/icons/icon.icns`
- Modify: required `desktop/src-tauri/icons/*.png` derivatives
- Modify: `desktop/src-tauri/tauri.conf.json` only if the approved asset path changes
- Test: `desktop/scripts/validate-zion-brand-assets.mjs`
- Test: `desktop/src-tauri/src/migration_sync_guard_tests.rs` and existing identifier tests

**Interfaces:**

- Consumes: approved intake derivatives and the DMG mockup.
- Produces: Zion/Sentra packaging artwork with `Zion.app` display name and the
  exact bundle identifier `xyz.block.buzz.app` intact.

- [ ] **Step 1: Validate the packaging source and dimensions**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/desktop
sips -g pixelWidth -g pixelHeight -g hasAlpha -g format src-tauri/icons/dmg-background.png src-tauri/icons/buzz-source.png
pnpm validate:brand-assets
```

Fail if an alias is missing, a PNG signature is invalid, or a required icon
size is absent.

- [ ] **Step 2: Generate required icon derivatives**

Use the intake-approved dark rounded-square Zion icon derivative with the
checked-in RGBA Swift renderer at each required dimension. Tauri rejects
RGB-only PNGs, so this preserves the artwork while satisfying the native
icon contract. Keep the wide Sentra lockup only for DMG/release artwork.
Render the DMG background from the staged transparent wordmark with the
checked-in Swift compositor; this keeps the deep-purple gradient, upright
lockup, and lavender install direction reproducible:

```bash
cd /Users/Aiden-Mi8/Documents/buzz-
swift scripts/render-zion-dmg-background.swift \
  "/private/tmp/zion-brand-source/transparent -logos/logo-TW2-wordmark.png" \
  desktop/src-tauri/icons/dmg-background.png
```

Build the native ICNS from the validated 128px, 256px, 512px, and 1024px
RGBA layers, then extract it with `iconutil -c iconset` for visual inspection:

```bash
node scripts/build-zion-icns.mjs \
  desktop/src-tauri/icons \
  desktop/src-tauri/icons/icon.icns
iconutil -c iconset -o /private/tmp/zion-iconset desktop/src-tauri/icons/icon.icns
```

- [ ] **Step 3: Verify Tauri configuration**

Assert `productName` is `Zion`, `identifier` is exactly
`xyz.block.buzz.app`, the DMG background remains mapped to
`icons/dmg-background.png`, and no bundle/deep-link/sidecar identifier changed.

- [ ] **Step 4: Run packaging validation and commit**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/desktop
pnpm validate:brand-assets
cargo test --manifest-path src-tauri/Cargo.toml migration_sync_guard_tests
git add ../scripts/build-zion-icns.mjs ../scripts/render-zion-dmg-background.swift ../scripts/render-zion-icon.swift src-tauri/icons/128x128.png src-tauri/icons/128x128@2x.png src-tauri/icons/32x32.png src-tauri/icons/64x64.png src-tauri/icons/Square107x107Logo.png src-tauri/icons/Square142x142Logo.png src-tauri/icons/Square150x150Logo.png src-tauri/icons/Square284x284Logo.png src-tauri/icons/Square30x30Logo.png src-tauri/icons/Square310x310Logo.png src-tauri/icons/Square44x44Logo.png src-tauri/icons/Square71x71Logo.png src-tauri/icons/Square89x89Logo.png src-tauri/icons/StoreLogo.png src-tauri/icons/buzz-source.png src-tauri/icons/dmg-background.png src-tauri/icons/icon.icns src-tauri/icons/icon.png
git commit -m "feat: update Zion packaging artwork and aliases"
```

The native icon must contain only the approved Zion layers; inspect the
extracted 1024px layer before accepting the commit. If native generation or
extraction fails, stop and record the packaging gate instead of shipping the
previous Buzz icon.

---

## Task 8: Add the final allowlisted brand scan and visual QA

**Files:**

- Create: `scripts/check-visible-zion-branding.mjs`
- Create: `scripts/check-visible-zion-branding.test.mjs`
- Create: `scripts/visible-brand-allowlist.json`
- Modify: `Justfile` to run the scanner and its unit tests from the standard `just check` path
- Modify: `web/src/features/repos/ui/ReposPage.tsx` when QA finds a user-facing Zion landmark accessibility mismatch
- Test: `scripts/check-visible-zion-branding.test.mjs` and desktop/web/admin/mobile focused test suites

**Interfaces:**

- Consumes: all migrated surfaces and the explicit compatibility allowlist.
- Produces: a repeatable pass/fail report that distinguishes visible branding
  from protected internals.

- [ ] **Step 1: Define the allowlist**

Allow only exact protected patterns and paths, including:

```json
{
  "identifiers": ["BUZZ_*", "buzz://", "xyz.block.buzz.app"],
  "legacyAssetPaths": ["/buzz.svg", "/favicon.svg", "/app-icon@2x.png", "/app-icon@3x.png", "/landing/buzz-wordmark.png"]
}
```

The scanner must report file, line, matched text, and reason for every
allowlisted hit and fail on visible bee/Buzz logo usage outside those reasons.
Missing configured product roots are blocking failures; internal source
directories are never blanket-exempted. The visible-context rules cover
static accessibility attributes, JSX text, and bindings whose values contain
legacy brand words; ordinary data-object properties are not treated as visible
surfaces. Comment stripping must preserve regular-expression literals,
including literals after control-condition parentheses, so a `//` inside a
regex cannot hide a later visible label. Include contract tests for `bSion`,
`VERSION`, `session`, `permission`, `BUZZ_*`,
`buzz://`, the bundle identifier, legacy URL aliases, `alt="Bee"`,
`ariaLabel="BUZZ"`, dynamic visible bindings, missing roots, and regex
literals.

- [ ] **Step 2: Run visual state coverage**

Capture or inspect these exact states:

1. desktop boot loader, community switch, onboarding identity, pending invite,
   provider loading, transcript loading, liveness, starter-team entrance, and
   reduced motion;
2. mobile initial loading, pairing welcome, connection, error, and reduced
   motion;
3. web invite, web repository icon, admin shell, admin favicon, and Builderlab
   auth completion;
4. DMG background, app icon, and legacy alias responses.

- [ ] **Step 3: Run the full safe checks**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-
node scripts/check-visible-zion-branding.mjs
cd desktop
pnpm check
pnpm test
pnpm test:e2e:smoke
cd ../web
pnpm check
pnpm test:e2e:smoke
cd ../admin-web
pnpm check
cd ../mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

- [ ] **Step 4: Run the interactive packaging gate**

From the user’s interactive Terminal, because Finder/AppleScript may time out
in a non-interactive process:

```bash
cd /Users/Aiden-Mi8/Documents/buzz-/desktop
pnpm tauri build --no-sign
```

Inspect `Zion.app` and the generated DMG for display name, icon, purple DMG
background, static reduced-motion fallback, non-zero sidecars, and preserved
agent data.

- [ ] **Step 5: Commit the QA harness and final test updates**

```bash
cd /Users/Aiden-Mi8/Documents/buzz-
git add Justfile scripts/check-visible-zion-branding.mjs scripts/check-visible-zion-branding.test.mjs scripts/visible-brand-allowlist.json web/src/features/repos/ui/ReposPage.tsx
git commit -m "test: verify Zion brand motion and compatibility boundaries"
```

Stage only the paths changed by this task; leave unrelated user changes
unstaged.

---

## Task 9: Update Linear tracking and hand off the release gate

**Files:**

- Read: existing Linear issues `MI8-6` through `MI8-11`
- Do not modify: unrelated `MI8-5` Watch issue
- Update: existing Zion/Sentra master and child issues after each task commit

**Interfaces:**

- Consumes: commit hashes, test output, source intake manifest, and packaging
  evidence from Tasks 1–8.
- Produces: Linear status/comments that point to exact commits and known gates.

- [ ] **Step 1: Keep issue scope aligned**

Use the existing `Sentra Ai` team and `Zion Comunication` project. Keep the
master feature and child improvements scoped to asset intake, shared motion,
desktop migration, mobile/web/admin migration, and compatibility/packaging QA.

- [ ] **Step 2: Record evidence, not narrative**

Each child issue comment must include the relevant commit hash, exact test
command, pass/fail result, and any interactive packaging gate. Do not mark the
master complete while iCloud intake, final DMG inspection, or the allowlisted
scan is incomplete.

- [ ] **Step 3: Final handoff**

Provide the user with the final commit list, source manifest hash list, test
summary, installed app/DMG paths, and any remaining interactive-only step.

---

## Plan self-review checklist

- [ ] Every design-spec requirement maps to Tasks 1–9.
- [ ] No task uses a mechanical substring rename.
- [ ] No task renames compatibility identifiers or legacy URLs.
- [ ] The wrong `production-final` source is explicitly rejected.
- [ ] Starter-team bee-like artwork is included as a visual review/implementation
  surface without renaming persona data.
- [ ] Desktop, mobile, web, admin, Builderlab, static assets, and DMG have
  isolated tests and commit boundaries.
- [ ] The interactive DMG build is a documented user/environment gate.
- [ ] Unrelated dirty-worktree changes are never staged by broad commands.
