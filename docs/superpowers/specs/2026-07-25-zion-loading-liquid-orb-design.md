# Zion loading liquid-orb design

## Status

Approved visual direction on 2026-07-25. This document locks the motion
design before implementation.

## Goal

Give Zion's initial loading and pairing welcome surfaces a premium, nearly
imperceptible sense of life without delaying connection, competing with the
Sentra wordmark, or introducing a repeating decorative animation.

## Approved visual treatment

- The supplied Sentra wordmark remains still, crisp, centered, and is the only
  sharp visual shape.
- A lavender liquid orb sits behind the wordmark. Its boundary dissolves into
  the obsidian background, leaving only faint internal refraction, slow
  currents, and soft shape deformation.
- The treatment uses a **1% brightness lift** above the surface. It is a
  glass-like refraction, not a visible glow or halo.
- Motion is one non-looping, roughly 7.6-second liquid drift. If loading ends
  first, Zion transitions immediately; the animation never holds the app.
- The orb rests in its final, almost invisible state after its drift. It does
  not restart while the surface remains visible.
- With Reduce Motion enabled, the final static state is shown immediately.

## Surfaces

1. **Initial loading:** replace the bare progress-only splash presentation with
   the centered Sentra wordmark and dissolved liquid orb. Existing session
   restoration and navigation timing remain unchanged.
2. **Pairing welcome:** apply the same branded treatment to the existing
   Sentra wordmark position above "Welcome to Zion." Pairing controls remain
   usable immediately and are not animated or delayed.

The shared Flutter visual seam may be used for these surfaces. Android native
packaging, assets, and release work remain out of scope.

## Implementation shape

- Add a small reusable Flutter branding widget for the Sentra wordmark and
  liquid-orb backdrop rather than duplicating animation code in `App` and the
  pairing page.
- Use Hooks/Riverpod-compatible widgets only; do not introduce a
  `StatefulWidget`.
- Respect the active color scheme when selecting the existing white or black
  wordmark asset. The approved dark Zion Orbit treatment uses the white asset.
- Build the orb from Flutter layers/gradients/transforms with conservative
  opacity, not a video, network asset, or persistent animation controller.
- Keep all `BUZZ_*`, `buzz` protocol parsing, bundle identifiers, stored keys,
  and relay behavior untouched.

## Verification

- Widget tests cover both branded surfaces and their static Reduce Motion
  state.
- Test that the treatment does not introduce layout overflow or delay the
  existing pairing controls.
- Run `just mobile-check`, `just mobile-test`, and an iPhone Simulator build
  and launch.
- Review loading and pairing screenshots on the iPhone 17 Pro Simulator for a
  visible wordmark, dissolved orb edge, and absence of a distracting loop.

## Out of scope

- New app icon work, native iOS launch-screen assets, Android resources,
  distribution, signing changes, or any relay/pairing protocol change.
