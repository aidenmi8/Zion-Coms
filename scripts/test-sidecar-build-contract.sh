#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
justfile="$repo_root/Justfile"
bundler="$repo_root/scripts/bundle-sidecars.sh"

fail() {
    echo "sidecar build contract failed: $*" >&2
    exit 1
}

recipe() {
    local start="$1"
    local end="$2"
    sed -n "/^${start}/,/^${end}/p" "$justfile"
}

release_recipe="$(recipe 'desktop-release-build ' 'desktop-ci:')"
[[ "$release_recipe" == *"cargo build --release"* ]] || fail "desktop-release-build does not build release sidecars"
[[ "$release_recipe" == *"scripts/bundle-sidecars.sh"* ]] || fail "desktop-release-build does not bundle release sidecars"
[[ "$release_recipe" != *'touch "desktop/src-tauri/binaries/'* ]] || fail "desktop-release-build still creates placeholder sidecars"

for pair in \
    "dev \\*ARGS:|desktop-standalone" \
    "desktop-standalone \\*ARGS:|staging \\*ARGS:" \
    "staging \\*ARGS:|production \\*ARGS:" \
    "production \\*ARGS:|$"; do
    start="${pair%%|*}"
    end="${pair#*|}"
    launch_recipe="$(recipe "$start" "$end")"
    [[ "$launch_recipe" == *"scripts/bundle-sidecars.sh"* ]] || fail "$start does not bundle real sidecars"
done

grep -Fq '[[ -s "$SRC_DIR/' "$bundler" || fail "bundler does not reject zero-byte sidecars"
grep -Fq 'chmod 755 "$destination"' "$bundler" || fail "bundler does not set an executable sidecar mode"
grep -Fq -- '--debug' "$bundler" || fail "bundler has no debug profile"

for launcher in \
    zion zion-acp zion-agent zion-dev-mcp \
    buzz buzz-acp buzz-agent buzz-dev-mcp; do
    grep -Eq "\"${launcher}(:|\\\")" "$bundler" ||
        fail "bundler does not include $launcher"
    grep -Fq "\"binaries/$launcher\"" "$repo_root/desktop/src-tauri/tauri.conf.json" ||
        fail "Tauri externalBin does not include $launcher"
done

echo "sidecar build contract passed"
