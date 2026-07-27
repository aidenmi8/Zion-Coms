Task 4 report — fix round completed

Date: 2026-07-27
Status: GREEN with formatter false-positive recorded
Workspace: /Users/Aiden-Mi8/Documents/buzz-

Summary

- Replaced the motion hero’s app-icon usage with approved manifest-derived SVG assets:
  - `mobile/assets/images/zion-mark.svg`
  - `mobile/assets/images/sentra-lockup-light.svg`
  - `mobile/assets/images/sentra-lockup-dark.svg`
- Updated `mobile/assets/images/zion-icon.png` to exactly match the approved manifest app icon bytes from `desktop/public/branding/zion-app-icon-1024.png`.
- Updated `ZionBrandMotion` and tokens to select:
  - Zion mark for `loader`, `liveness`, and `agent-entrance`
  - brightness-appropriate Sentra lockup for `onboarding` and `pairing`
- Moved loading/connecting announcement ownership into PairingPage’s parent status region and kept the motion surface decorative there.
- Preserved the five variant names, hook-based controller, reduced-motion immediate static fallback, unchanged `nostrpair://... or buzz://...` hint, scanner flow, SAS flow, controls, provider behavior, and error/status colors.

Scoped files changed

- `mobile/assets/images/zion-icon.png`
- `mobile/assets/images/zion-mark.svg`
- `mobile/assets/images/sentra-lockup-light.svg`
- `mobile/assets/images/sentra-lockup-dark.svg`
- `mobile/lib/shared/brand/zion_brand_tokens.dart`
- `mobile/lib/shared/brand/zion_brand_motion.dart`
- `mobile/lib/features/pairing/pairing_page.dart`
- `mobile/test/shared/brand/zion_brand_motion_test.dart`
- `mobile/test/features/pairing/pairing_page_test.dart`
- `mobile/pubspec.yaml`

Approved source/output hashes

```text
fd0d912d30cb3b817df0b3167b7c77f6929cfa0d0b8f1407c9b1d6d9e7acd124  desktop/public/branding/zion-mark.svg
fd0d912d30cb3b817df0b3167b7c77f6929cfa0d0b8f1407c9b1d6d9e7acd124  mobile/assets/images/zion-mark.svg

fe7a257f666946b064571bcd73700f30ebf33e0bcd5076f47790bda076c9b01d  desktop/public/branding/sentra-lockup-light.svg
fe7a257f666946b064571bcd73700f30ebf33e0bcd5076f47790bda076c9b01d  mobile/assets/images/sentra-lockup-light.svg

087a92c1efdaba769e851fc72638f777e8f89adb8530f6661428536ee4b0c9d5  desktop/public/branding/sentra-lockup-dark.svg
087a92c1efdaba769e851fc72638f777e8f89adb8530f6661428536ee4b0c9d5  mobile/assets/images/sentra-lockup-dark.svg

4ea736a6dad74fddcb3ef19690ffaf6e62a5dfb738207d628121cfdc7c6cab50  desktop/public/branding/zion-app-icon-1024.png
4ea736a6dad74fddcb3ef19690ffaf6e62a5dfb738207d628121cfdc7c6cab50  mobile/assets/images/zion-icon.png
```

Verification

1. Safe mobile checks under Hermit:

- `cd /Users/Aiden-Mi8/Documents/buzz-/mobile && . ../bin/activate-hermit && flutter analyze`

```text
Analyzing mobile...
No issues found! (ran in 6.5s)
```

- `cd /Users/Aiden-Mi8/Documents/buzz-/mobile && . ../bin/activate-hermit && flutter test test/shared/brand/zion_brand_motion_test.dart test/features/pairing/pairing_page_test.dart`

```text
00:01 +11: All tests passed!
```

2. Formatter blocker, reproduced again on the fix-round tree:

- `cd /Users/Aiden-Mi8/Documents/buzz-/mobile && . ../bin/activate-hermit && dart format --output=none --set-exit-if-changed lib test`

```text
Changed lib/features/pairing/pairing_page.dart
Changed lib/shared/brand/zion_brand_motion.dart
Changed lib/shared/brand/zion_brand_tokens.dart
Changed test/features/pairing/pairing_page_test.dart
Changed test/shared/brand/zion_brand_motion_test.dart
Formatted 210 files (5 changed) in 0.68 seconds.
```

- Re-running the formatter against only the five Task 4 fix-round Dart files still reported `Formatted 5 files (5 changed)` while the hashes before and after remained identical:

```text
609966976a42e69cbe8916bd173a85fa1e72f9d08536f669cd87ed2ab300e39e  lib/features/pairing/pairing_page.dart
936ab46bd1a336ba2bad47e0e4c4ab15977d209176a5c527be715c62fbd24073  lib/shared/brand/zion_brand_motion.dart
9e9397514cbc8cf7f0fedf248d047b6e1e0fcd7857d51256e988642ad460de52  lib/shared/brand/zion_brand_tokens.dart
25c2743d081701e45429266cb15dd8cab268713777a08a789a0f1cd4d12d47fe  test/features/pairing/pairing_page_test.dart
38a1489572292c6ac42fcf8a474510a7357a1865dcf69384a9c27efe4cde33ad  test/shared/brand/zion_brand_motion_test.dart
```

Focused test coverage added/updated

- asset selection by variant and brightness
- reduced-motion static rendering
- motion label ownership for standalone callers
- welcome state still uses the unchanged input hint
- connecting state uses the pairing pulse
- transferring state uses the loader motion
- PairingPage parent status region owns the spoken label and the motion stays decorative

Concerns

- The only unresolved issue is the Hermit/Dart formatter false-positive behavior above. The analyzer and focused tests passed on the fix-round tree.
