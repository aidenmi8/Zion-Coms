#!/usr/bin/env bash
set -euo pipefail

# destination:source — canonical Zion launchers and legacy compatibility names
# point at the same compiled personalities.
SIDECARS=(
    "zion-acp:buzz-acp"
    "zion-agent:buzz-agent"
    "zion-dev-mcp:buzz-dev-mcp"
    "zion:buzz"
    "buzz-acp:buzz-acp"
    "buzz-agent:buzz-agent"
    "buzz-dev-mcp:buzz-dev-mcp"
    "git-credential-nostr:git-credential-nostr"
    "buzz:buzz"
)
HOST=$(rustc -vV | sed -n 's|host: ||p')
PROFILE=release
TARGET=""
EXPLICIT_TARGET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            PROFILE=debug
            ;;
        --release)
            PROFILE=release
            ;;
        -*)
            echo "Error: unsupported option: $1" >&2
            exit 1
            ;;
        *)
            [[ -z "$TARGET" ]] || {
                echo "Error: target specified more than once" >&2
                exit 1
            }
            TARGET="$1"
            EXPLICIT_TARGET=true
            ;;
    esac
    shift
done

TARGET=${TARGET:-$HOST}
BINARIES_DIR="desktop/src-tauri/binaries"

# When --target is passed explicitly to cargo (even if it matches the host),
# binaries land in target/<triple>/release/. Without --target, they land in
# target/release/. The script receives the target as $1 only when cargo was
# invoked with --target, so use the qualified path whenever $1 is set.
if [[ "$EXPLICIT_TARGET" == true ]]; then
    SRC_DIR="target/${TARGET}/${PROFILE}"
else
    SRC_DIR="target/${PROFILE}"
fi

# MSVC emits <name>.exe; Tauri's externalBin then expects binaries/<name>-<triple>.exe.
if [[ "$TARGET" == *windows* ]]; then
    EXE=".exe"
else
    EXE=""
fi

missing=()
for pair in "${SIDECARS[@]}"; do
    source_bin="${pair#*:}"
    [[ -s "$SRC_DIR/${source_bin}${EXE}" ]] || missing+=("${source_bin}${EXE}")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing or empty ${PROFILE} binaries in $SRC_DIR: ${missing[*]}" >&2
    echo "Build the sidecars before bundling them." >&2
    exit 1
fi

mkdir -p "$BINARIES_DIR"
for pair in "${SIDECARS[@]}"; do
    destination_bin="${pair%%:*}"
    source_bin="${pair#*:}"
    destination="$BINARIES_DIR/${destination_bin}-${TARGET}${EXE}"
    cp "$SRC_DIR/${source_bin}${EXE}" "$destination"

    # cp preserves the mode of an existing destination on macOS. Generated
    # sidecar placeholders may not be executable, so make the bundled Unix
    # binaries executable explicitly.
    if [[ -z "$EXE" ]]; then
        chmod 755 "$destination"
    fi
done
echo "${PROFILE} sidecars bundled for $TARGET"
