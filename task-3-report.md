# Task 3 report — Zion-only emitted branding

## Outcome

Relay, ACP, agent, CLI, and developer-MCP product-authored output now emits Zion branding. Canonical `ZION_*` configuration names take precedence while legacy `BUZZ_*` inputs remain accepted. Desktop and mobile transcript/config-nudge readers accept both new Zion frames and historical Buzz frames.

Protected compatibility identifiers were intentionally retained: APNs profile IDs, `buzz-channel`, package/bundle and storage paths, the legacy `buzz` launcher, `buzz-agent`/`buzz-acp.toml` compatibility names, Goose's private system-prompt key `"buzz"`, metrics/internal crate identifiers, and operator-provided/user-authored values.

## TDD evidence

### Relay

- RED: `bin/cargo test -p buzz-relay nip11` — missing `RelayBranding`/override builder.
- RED: `bin/cargo test -p buzz-relay status_payload_identifies_zion_relay` — missing status helper.
- RED: `bin/cargo test -p buzz-relay git_auth_challenges_use_zion_realm_for_both_rejection_branches` — missing challenge helper.
- RED: `bin/cargo test -p buzz-relay advertisement_framing_matches_git_oracle_shape` — missing canonical capability.
- GREEN: focused NIP-11 16/16; status, git challenge, and capability tests each 1/1.

### Agent

- RED: `bin/cargo test -p buzz-agent` — missing Zion OAuth/auth/config/metadata helpers and canonical prompt-source selection.
- RED: `bin/cargo test -p buzz-agent noninteractive_auth_guidance_uses_canonical_launcher` — missing canonical auth error helper.
- GREEN: sequential full package: lib 293/293, config aliases 4/4, OAuth 14/14, fake LLM 14/14, golden transcripts 14/14, hints 8/8, auto-upgrade 1/1, regressions 22/22.

### ACP

- RED: `bin/cargo test -p buzz-acp zion` — 0/4, legacy onboarding/heartbeat/setup/event output.
- RED: initialize metadata, shared base prompt, and canvas focused tests each 0/1.
- RED: `bin/cargo test -p buzz-acp public_help_emits_canonical_zion_branding` — 0/1, legacy command/env/help copy.
- GREEN: full package 623/623 plus lifecycle integration 9/9.

### CLI

- RED: recursive help-tree test 0/1 (255 filtered), first failure under `zion agents` with legacy Desktop branding.
- GREEN: full package 256/256 plus launcher integration 1/1.

### Developer MCP

- RED: full package compile failure because the new Zion Windows guidance helper did not exist.
- GREEN: full package 99/99.

### Historical readers

- RED desktop: 73 passed/3 expected failures for canonical Zion event and config-nudge frames.
- GREEN desktop: selected Node suite 76/76; historical Buzz cases remain green.
- RED mobile: 3 passed/1 expected failure for the canonical Zion event frame.
- GREEN mobile: focused Flutter suite 4/4; historical Buzz case remains green.

## Additional verification

- `bin/cargo fmt --all -- --check` — pass.
- Desktop Biome check for all changed reader/test files — pass.
- Dart format check for both changed mobile files — pass.
- `git diff --check` — pass.
- Full relay package: 775 passed, 9 failed, 34 ignored. The nine failures are infrastructure-dependent and outside this patch: seven media tests failed with `Sqlx(PoolTimedOut)` while seeding the test community, and two admin DB lookups returned 500 instead of 404 with the same unavailable database. All owned relay Zion output tests passed in that run.

## Self-review

- Canonical precedence is explicit; legacy environment aliases are fallback-only.
- ACP event framing is centralized in `zion_event_frame()` and shared by queued delivery and native steer.
- Config-nudge emission is canonical Zion; desktop reads both canonical and historical fences.
- No protected APNs, wire tag, package, storage, invite, or private Goose contract was renamed.
- No push, merge, deployment, ledger, audit, or brief mutation was performed.
