# Zion Cold-Launch Bounce

## Status

Approved direction: implement the motion in code on the existing transparent
inline Zion SVG. The user declined a separate visual mockup and approved a
smooth, friction-like bounce between the mark's two rectangles.

## Goal

Make the Zion mark feel intentional during a true desktop cold launch:

- keep the splash visible for at least 2.5 seconds;
- animate the two mark pieces with one damped, friction-like bounce;
- retain the existing 200 ms fade;
- keep the app loading and interactive underneath the overlay; and
- never replay the launch sequence for community switching or ordinary window
  reactivation.

## Motion

The two SVG paths animate independently along opposing diagonal vectors:

1. The upper piece moves slightly up and right while the lower piece moves
   slightly down and left.
2. Both reverse past their resting positions with a smaller overshoot.
3. Two decreasing rebounds create the impression of momentum losing energy to
   friction.
4. Both pieces settle exactly on the canonical Zion geometry by about 1.6
   seconds.
5. The settled mark remains still until the 2.5-second splash hold ends, then
   the existing 200 ms opacity fade removes the overlay.

The movement is one-shot and bounded. It does not loop, rotate, distort the
paths, or change the final artwork.

## Implementation boundary

Add a named, code-native `launch` variant to the existing Zion motion contract.
`AppLoadingGate` opts into that variant. `CommunitySwitchGate` and all shared
loader, onboarding, pairing, transcript, and liveness consumers keep their
current variants.

Give the two paths in `ZionMark` stable upper/lower piece hooks. Launch-specific
CSS animates only those hooks beneath `.zion-motion--launch`. The base mark
continues to render as a transparent `currentColor` SVG on the first frame, so
missing animation support still produces the correct settled Zion mark.

Move the production splash timing into a small testable timing module:

- minimum cold-launch hold: 2,500 ms;
- fade: 200 ms;
- E2E override: unchanged, so unrelated browser tests can still skip the hold.

No animation library, raster frame sequence, video, Rive runtime, Lottie
runtime, or new dependency is introduced.

## Accessibility and fallback

- The existing status text remains the accessible loading signal.
- The SVG pieces remain decorative inside the status region.
- `prefers-reduced-motion: reduce` disables all piece motion and displays the
  final settled mark.
- Timer cleanup remains on unmount.
- If CSS animation is unavailable, the inline SVG remains visible and correct.

## Testing

Follow a red-green sequence:

1. Add a timing contract test proving the production default is 2,500 ms and
   the E2E zero/explicit overrides still work.
2. Extend the brand manifest contract to require the one-shot code-native
   `launch` variant.
3. Extend the Zion mark/motion contract to require distinct upper and lower
   pieces plus launch and reduced-motion CSS.
4. Update the boot Playwright test to prove:
   - the cold-launch overlay uses `data-zion-variant="launch"`;
   - exactly one transparent SVG mark is rendered;
   - both pieces receive distinct animation names;
   - the ready app is mounted underneath the overlay;
   - the overlay remains through the configured hold and then fades/unmounts;
   - reduced motion produces no piece animation.
5. Run the focused unit and Playwright suites, full desktop checks, production
   build, and rendered browser QA.

## Release and compatibility

Build and install only the desktop application change. Verify the arm64
`buzz-desktop` executable, all five non-empty executable sidecars, strict
bundle signature, and installed launch.

Preserve `BUZZ_*`, `buzz://`, package and executable names, bundle identifier
`xyz.block.buzz.app`, relay paths, Docker names, internal storage keys, and all
legacy URLs.
