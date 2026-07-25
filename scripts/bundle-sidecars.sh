#!/usr/bin/env bash
set -euo pipefail

SIDECARS=(buzz-acp buzz-agent buzz-dev-mcp git-credential-nostr buzz)
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
for bin in "${SIDECARS[@]}"; do
    [[ -s "$SRC_DIR/${bin}${EXE}" ]] || missing+=("${bin}${EXE}")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing or empty ${PROFILE} binaries in $SRC_DIR: ${missing[*]}" >&2
    echo "Build the sidecars before bundling them." >&2
    exit 1
fi

mkdir -p "$BINARIES_DIR"
for bin in "${SIDECARS[@]}"; do
    cp "$SRC_DIR/${bin}${EXE}" "$BINARIES_DIR/${bin}-${TARGET}${EXE}"
    [[ "$TARGET" == *windows* ]] || chmod +x "$BINARIES_DIR/${bin}-${TARGET}${EXE}"
done
echo "${PROFILE} sidecars bundled for $TARGET"
