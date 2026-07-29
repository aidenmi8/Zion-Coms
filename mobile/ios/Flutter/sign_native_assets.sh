#!/bin/sh

# Flutter 3.41.7 copies Dart native assets into an iOS app after its embed
# phase, but device builds retain the assets' ad-hoc signature. iOS requires
# embedded frameworks to use the same signing identity as the containing app.
set -eu

if [ "${PLATFORM_NAME:-}" != "iphoneos" ] ||
  [ "${CODE_SIGNING_REQUIRED:-YES}" = "NO" ] ||
  [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] ||
  [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

for framework_path in "$frameworks_dir"/*.framework; do
  [ -d "$framework_path" ] || continue

  bundle_identifier="$(
    /usr/libexec/PlistBuddy \
      -c 'Print :CFBundleIdentifier' \
      "$framework_path/Info.plist" 2>/dev/null || true
  )"

  case "$bundle_identifier" in
    io.flutter.flutter.native-assets.*)
      /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
        ${OTHER_CODE_SIGN_FLAGS:-} \
        --preserve-metadata=identifier,entitlements \
        "$framework_path"
      ;;
  esac
done
