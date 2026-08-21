# Zion version and build identity

Zion uses two identifiers so an installed app can be distinguished from an
older build with the same source-era label:

- **Version** is the user-facing release number. Keep these files in sync:
  `desktop/package.json`, `desktop/src-tauri/tauri.conf.json`,
  `desktop/src-tauri/Cargo.toml`, and `desktop/src-tauri/Cargo.lock`.
- **Build identity** is embedded by `desktop/vite.config.ts` from
  `VITE_ZION_BUILD_ID`, `VITE_ZION_COMMIT`, and `VITE_ZION_WORKTREE`.
  Settings displays both the version and build identity in the Zion footer.

## Verified local build

The installed local build on 2026-08-21 is:

- Version: `0.0.11`
- Build: `202608211832`
- Source commit: `47db5cd7143b`
- Provisioning fix commit: `03523c64e`
- Worktree: `dirty` (the signed bundle was built before the fix commit was recorded)
- Bundle: `/Applications/Zion.app`
- Main executable SHA-256: `8afe4f60b2c2f2239737b433fc03f35afc55adf16edfa616575ba5d6cb0fed5c`
- Signing identity: `Developer ID Application: aiden solis (79Z9DG2TCP)`
- Team ID: `79Z9DG2TCP`
- Notarization: `not submitted` (local build; Gatekeeper reports `Unnotarized Developer ID`)

The previous installed app was preserved at
`artifacts/Zion-0.0.9-installed-20260821-live.app` for rollback.

## Build convention

For a local, traceable build, set the three build variables explicitly:

```bash
VITE_ZION_BUILD_ID=202608211832 \
VITE_ZION_COMMIT=47db5cd7143b \
VITE_ZION_WORKTREE=dirty
```

The build system generates a timestamp and reads Git automatically when these
variables are omitted. Release automation should always provide an explicit
build ID and commit so the artifact can be reproduced from its release record.
