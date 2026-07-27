# Zion/Sentra Brand Motion and Asset Migration

## Status

Design approved from the review package at
`/private/tmp/zion-brand-motion-review-v2/`. This document defines the
implementation boundary. Production code and shipped assets remain unchanged
until the implementation plan is reviewed.

## Goal

Replace every product-facing Buzz bee, Buzz logo animation, and branded motion
surface with the Zion/Sentra visual system. Zion is the installed product
identity. Sentra is the umbrella identity and appears only in approved
umbrella, pairing lockup, marketing, release, and packaging contexts.

The approved visual direction is calm and precise:

- deep-purple / near-black backgrounds;
- graphite surfaces;
- silver/white Zion marks and wordmarks;
- muted lavender for controls, status, and restrained glow;
- slow breathing luminance, one-way reveal, gentle settling, and single
  connection pulses;
- reduced motion always resolves to a static or fully settled state.

The mockups are directional design references. They are not final animation
frames and must not be copied into shipped assets without the asset-intake
gate below.

## Safety and compatibility boundaries

- Preserve `BUZZ_*`, `buzz://`, `buzz` package/module names, bundle identifier
  `xyz.block.buzz.app`, relay paths, Docker names, protocol names, and internal
  storage/theme keys.
- Do not perform substring renames. A visible label changes only when its
  source is an explicit product-facing branding surface. Strings such as
  `bSion`, `BUZZ_*`, embedded package names, and protocol identifiers remain
  protected unless individually reviewed.
- Preserve legacy public asset URLs as aliases while serving approved Zion
  artwork: `/buzz.svg`, `/favicon.svg`, `/app-icon@2x.png`,
  `/app-icon@3x.png`, and `/landing/buzz-wordmark.png`.
- Decorative marks remain `aria-hidden`. Status and loading animations expose
  their meaning through the parent status region, not through repeated visual
  announcements.
- Existing semantic warning/status colors, including yellow/amber, remain
  available. They are not used as Zion/Sentra brand motion or brand-surface
  colors unless separately approved.
- Generic UI transitions remain functional motion. They are changed only when
  they visibly carry Buzz/bee/logo branding.

## Brand hierarchy

| Context | Visible identity | Rule |
| --- | --- | --- |
| Installed application, desktop UI, mobile UI, web invite, admin | Zion | Product copy and primary product mark use Zion. |
| Mobile pairing welcome lockup | Sentra mark/wordmark plus Zion product copy | Sentra identifies the umbrella; “Welcome to Zion” remains the action context. |
| DMG and release/marketing artwork | Sentra lockup plus Zion app icon | Sentra may lead the composition; the installed app remains Zion. |
| Internal compatibility and protocols | Buzz | Preserve exactly; do not expose or mechanically rename these surfaces. |

## Color direction

The first implementation tokens are derived from the approved review direction,
then calibrated against the authoritative artwork during intake:

| Role | Directional value | Use |
| --- | --- | --- |
| Deep-purple background | `#0b0812` | Boot, pairing, web/admin brand surfaces |
| Graphite panel | `#151020` | Cards, dialogs, DMG/app treatment |
| Purple surface edge | `#332842` | Quiet borders and dividers |
| Silver mark | `#f3efff` | Zion mark and high-contrast wordmark |
| Lavender accent | `#b99aff` | Primary CTA, status, motion glow |
| Soft gray text | `#b9aecf` | Secondary copy and supporting status text |

These are brand-surface tokens, not a global rewrite of Catppuccin or semantic
theme tokens. Contrast must be measured for every text/control combination.

## Motion system

### Canonical motion contract

Create a shared brand-motion contract with platform adapters:

- desktop/web/admin use a React/CSS implementation;
- mobile uses a Flutter implementation;
- native packaging surfaces remain static;
- all platforms consume the same named motion manifest, timing intent, and
  reduced-motion policy.

The implementation may use CSS/vector transforms for smooth motion around the
approved static mark. If a dedicated frame sequence is created, it must be a
real animation asset with its own manifest entry; a static PNG must not be
pretended to be an animation by duplicating it as frames.

### Motion variants

| Variant | Behavior | Initial timing target |
| --- | --- | --- |
| `loader` | Silver mark breathes in luminance and scale; no spinner or rotation | 1.8s loop |
| `onboarding` | Mark/field performs one controlled reveal, then settles; sparse background forms settle gently | 0.9s reveal, 2.4s settle |
| `liveness` | Small mark performs a low-amplitude lavender/silver pulse tied to active work | 1.25–1.5s loop |
| `pairing` | Static lockup holds; one restrained lavender pulse begins when connection starts | 1.8s one-shot or bounded loop |
| `agent-entrance` | Neutral starter-team presence forms enter one-by-one and settle | 280–360ms stagger, 900ms settle |
| `reduced-motion` | Static mark or final settled state, with no decorative movement | immediate |

Motion must be interruptible, deterministic in tests, and paused when its
surface is not visible. Decorative background motion is `aria-hidden`.

### Starter-team animation

The existing `Fizz`, `Honey`, and `Bumble` starter-team artwork is visibly
bee-like. The approved review direction replaces the bee visual language with
three neutral, distinct agent-presence forms. Persona names, agent behavior,
fixtures, and protocol data remain unchanged. This is a visual asset and
animation replacement, not a persona rename.

## Surface and replacement map

### Desktop

| Existing surface | Approved replacement | Implementation targets |
| --- | --- | --- |
| Cold boot and community switch gates | Zion silver loader with calm breathe | `desktop/src/app/App.tsx`, shared brand-motion package |
| Machine onboarding identity landing and background field | Zion mark plus sparse neutral field with one-way reveal/settle | `desktop/src/features/onboarding/ui/MachineOnboardingFlow.tsx`, `desktop/src/shared/ui/zion-brand/ZionBrandField.tsx` |
| Onboarding chrome and step marks | Static Zion mark with approved transition behavior | `OnboardingChrome.tsx`, `SetupStep.tsx`, `RuntimeIcon.tsx`, related onboarding consumers |
| Pending invite and hosted onboarding gates | Zion loader/status state | `PendingInviteGate.tsx`, `desktop/src/features/communities/ui/HostedCommunityOnboarding.tsx` |
| Agent transcript loading and turn liveness | Small Zion liveness pulse with status semantics | `AgentSessionTranscriptList.tsx`, `TurnLivenessIndicator.tsx` |
| Old Buzz animation components and wing CSS | Remove after consumer migration and compatibility scan | `desktop/src/shared/ui/buzz-logo/*`, legacy bee animation rules |
| Starter-team kickoff | Neutral agent-presence entrance and reduced-motion state | `WelcomeKickoffStage.tsx`, `desktop/public/onboarding/starter-team/*.png` |
| Builderlab authentication completion | Deep-purple Zion completion surface; no bee SVG | `desktop/src-tauri/src/builderlab.rs` |

The desktop app may retain its functional Catppuccin product theme. The
approved deep-purple treatment applies to branded boot/onboarding/liveness
surfaces and other explicitly mapped identity surfaces, not to unrelated
content controls.

### Mobile

| Existing surface | Approved replacement | Implementation target |
| --- | --- | --- |
| Initial pairing/loading state | Zion mark with calm luminance breathe | `mobile/lib/features/pairing/pairing_page.dart` |
| Pairing welcome and connection start | Sentra lockup, Zion copy, lavender CTA, one controlled connection pulse | `mobile/lib/features/pairing/pairing_page.dart`, pairing assets |
| Reduced-motion pairing | Static mark and settled controls | Same pairing surface, platform accessibility preference |

The mobile app preserves all pairing behavior, `buzz://` compatibility, and
internal storage keys.

### Web and admin

| Existing surface | Approved replacement | Implementation targets |
| --- | --- | --- |
| Invite gradient, app icon, and branded entrance | Deep-purple invite surface, Zion mark, lavender CTA, one-time reveal | `web/src/features/invite/ui/InvitePage.tsx`, `web/src/assets/*` |
| Admin shell, header mark, favicon, active state | Graphite-purple shell, silver mark, restrained active-state glow | `admin-web/src/styles.css`, `admin-web/src/App.tsx`, `admin-web/public/favicon.svg` |
| Generic skeleton/tooltip motion | Keep behavior unless old branding is present | Existing `web/src` and `admin-web/src` generic motion rules |

### Packaging and static assets

| Existing surface | Approved replacement | Implementation targets |
| --- | --- | --- |
| DMG background | Purple/graphite treatment from the approved DMG mockup | `desktop/src-tauri/icons/dmg-background.png`, Tauri DMG config |
| Tauri and web app icons | Approved dark Zion icon derivatives at every required size | `desktop/src-tauri/icons/*`, `desktop/public/*`, `web/src/assets/*` |
| Favicon and wordmark aliases | Canonical Zion assets with explicit legacy URL aliases | `admin-web/public/favicon.svg`, desktop/web public assets |

## Asset intake gate

The authoritative artwork source is:

`/Users/Aiden-Mi8/Library/Mobile Documents/com~apple~CloudDocs/SENTRA-MAIN/logo and media/`

The previous `Sentra-Main/media/sentra-identity-v1/production-final` folder is
not an approved source and must not be used for production replacement.

Before shipping assets:

1. Verify the authoritative iCloud folder is readable. If macOS privacy blocks
   it, stage an explicit user-approved copy; do not silently fall back to the
   previous folder.
2. Record every source filename, role, dimensions, alpha channel, color space,
   and SHA-256 value.
3. Treat `Logos-sentra-v2-1.png` as a typography reference only.
4. Use `logo-TW-wordmark.png`, `logo-TW2-wordmark.png`, and
   `logo-TB-wordmark.png` only according to measured contrast and transparency;
   do not infer light/dark behavior from the filename alone.
5. Generate optimized derivatives only from approved source artwork.
6. Add a canonical asset manifest with source provenance, roles, derivatives,
   aliases, frame sequences, timing, and reduced-motion fallback.
7. Validate dimensions, transparency, color space, and missing derivatives
   before any consumer migration.

The attached screenshots and review mockups are visual references, not a
substitute for this intake gate.

## Accessibility and behavior

- Brand motion never carries the only meaning of a state.
- Loading, pairing, and liveness surfaces use a parent `role="status"` or
  equivalent accessible status region with stable text.
- Decorative marks, fields, glows, and transition halos are hidden from assistive
  technology.
- `prefers-reduced-motion` and Flutter `disableAnimations` produce static or
  settled states without a delayed reveal.
- Contrast is tested for silver/lavender text, CTA labels, focus rings, status
  indicators, and dark/light edge cases.

## Verification and acceptance

### Unit and component tests

- Manifest roles, source provenance, aliases, dimensions, and frame sequencing.
- Loop, bounded playback, pause/play, interruption, and safe empty fallback.
- Reduced-motion static fallback on desktop/web and mobile.
- Accessible status semantics and decorative-mark behavior.
- Starter-team entrance ordering and settled fallback.

### End-to-end and platform checks

- Desktop boot splash, community switch, onboarding identity, pending invite,
  hosted onboarding, transcript loading, turn liveness, and starter-team kickoff.
- Update the boot-splash e2e contract from `.bee-wing-left` to the Zion motion
  contract and add reduced-motion coverage.
- Web invite and admin visual smoke checks, including favicon and icon aliases.
- Flutter widget tests and `flutter analyze`; no mobile build command is used
  by the agent workflow.
- Tauri icon and DMG packaging validation, then inspect the resulting
  `Zion.app` and DMG while confirming `xyz.block.buzz.app` is unchanged.
- Final allowlisted scan: no visible Buzz/bee branding remains outside the
  explicit compatibility/internal allowlist.

## Rollout and rollback

Implementation should be split into reviewable commits:

1. authoritative asset intake and manifest;
2. shared motion contract and platform adapters;
3. desktop branded motion and starter-team migration;
4. mobile pairing migration;
5. web/admin/auth-complete migration;
6. static aliases, Tauri icons, DMG, tests, and visual QA.

Do not delete the old component or asset until all consumers are migrated and
the allowlisted scan passes. Each commit must be revertible without touching
protocol, package, bundle, relay, Docker, or compatibility identifiers.

## Review artifacts

The approved visual references are in:

`/private/tmp/zion-brand-motion-review-v2/`

The contact sheet is `00-contact-sheet.png`; the exact surface mapping is in
`REPLACEMENT-MAP.md`.
