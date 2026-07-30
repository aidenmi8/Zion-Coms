# Apple platform checks

Only iOS and macOS are first-class application targets. Supporting web, relay,
API, or container code may have repository checks, but this skill does not
define Windows or Linux application profiles.

## Common preflight

- Run skill-driven Git operations on a macOS host.
- Read `AGENTS.md`, configuration, authorized commands, and prohibited commands.
- Discover the actual project/workspace/package, schemes, targets, deployment
  versions, extensions, Watch targets, and test plans.
- Preserve each bundle identifier, deep link, entitlement, app group, Keychain
  group, signing boundary, privacy string, and release channel unless the
  intake decision explicitly changes it.
- Review visual identity, assets, colors, typography, accessibility labels,
  Dynamic Type, contrast, reduced motion, and launch/loading behavior.
- Never infer authorization to sign, archive, notarize, upload, deploy, install,
  or replace an installed app.

## Profile routing

| Profile | Discover | Default evidence |
|---|---|---|
| `native-xcode` | `.xcodeproj`, `.xcworkspace`, schemes, destinations | configured XcodeBuildMCP/xcodebuild tests |
| `flutter-ios` | `pubspec.yaml`, iOS Runner/configurations, plugins | `dart format` check, `flutter analyze`, `flutter test` when authorized |
| `tauri-macos` | frontend package, `src-tauri`, config, sidecars | frontend checks, Cargo/Tauri tests, unsigned build only when authorized |
| `swiftpm-macos` | `Package.swift`, products, targets, resources | configured `swift test` and `swift build` |

## native-xcode

Prefer XcodeBuildMCP when available. Verify active project/workspace, scheme,
and simulator before building or testing. Review Info.plist values, xcconfigs,
asset catalogs, privacy manifests, entitlements, extensions, Watch
connectivity, and test targets. Treat provisioning profiles and signing
identities as release credentials, not intake prerequisites.

## flutter-ios

Verify Dart/Flutter constraints, CocoaPods or Swift Package dependencies,
Runner display name, bundle identifier indirection, URL schemes, camera/photo
permissions, notifications, attachments, themes, accessibility, and reduced
motion. Safe analysis commands do not authorize `flutter run`, `flutter build`,
`flutter clean`, or `flutter upgrade`; repository policy decides.

## tauri-macos

Verify Tauri configuration, macOS usage descriptions, bundle identifier,
icons/DMG metadata, updater/release settings, capabilities, entitlements, and
every sidecar's target suffix, executable bit, and non-empty artifact.
Frontend checks do not prove the Rust/Tauri layer, and an unsigned local build
does not authorize signing, notarization, installation, or replacement.

## swiftpm-macos

Verify tools version, platforms, products, executable/library targets,
resources, plugins, and tests. Confirm any app wrapper's bundle identifier,
Info.plist, entitlements, privacy declarations, and signing boundary separately
from `swift test`.

## Evidence and handoff

Run only configured commands. Record exact schemes/destinations, test counts,
artifacts, manual simulator/device checks, and anything not run. Keep source
validation distinct from signed builds, TestFlight, notarization, server
deployment, and installed application state.
