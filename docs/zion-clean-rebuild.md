# Clean Zion rebuild — execution record

Approved plan: “Clean Zion Rebuild on Current Upstream”, 2026-11-06.

## Fixed scope

Fresh upstream foundation, a small Zion presentation/distribution layer, fresh
database/storage, configuration-only agent transfer with new identities and no
memory import. Existing platforms, databases, application data, Keychain and
uncommitted work are preservation inputs, never migration or cleanup targets.
No old database bridge, old custom features or accumulated vendor patches.

Relay/mobile/CLI upstream: `block/buzz` at
`96af488d968a1ae9d961c2132bea27822735f8da`.
Local branch: `codex/zion-clean-refresh-20261106`.

## Rulings and authorization boundaries

- The owner's explicit fresh clone overrides automatic worktree reuse. The old
  primary and compatibility/refresh worktrees remain untouched.
- Upstream now deprecates `desktop/` and directs new desktop/web work to
  `block/buzz-app`. Owner explicitly approved a second clean clone. The legacy
  desktop is not a branding or packaging target for Zion, and no separate Zion
  maintenance release of it is planned. The new app in `Zion-App-clean` is the
  sole desktop candidate. Keep the old source and its completed dependency
  repairs intact for now because it remains in the shared workspace and checks;
  do not build, sign, install, or publish a legacy desktop artifact. Both apps
  currently declare `xyz.block.buzz.app`, so they are not parallel installable
  products. A paired release manifest will bind the relay/mobile and new
  desktop repositories' exact source revisions; pretending they have one Git
  SHA would be inaccurate.
- Keep historical intake decisions unchanged and do not mark queued work as
  delivered. This is a new baseline adoption, not incremental completion claims.
- Existing app identifiers, compatible Keychain/storage namespaces, `BUZZ_*`,
  `buzz://`, package and wire identifiers remain where needed. Never globally
  replace “buzz”. Accurate third-party names and legal attribution remain.
- No publication, PR, signing, installation or production endpoint cutover is
  authorized yet. Candidate preparation must use distinct project/ports/storage.
  Keep changes local and uncommitted until the source checkpoint is approved.
- Reuse approved artwork; no new design project, new product APIs, schema,
  authentication policy, protocol changes or security exceptions.
- New frontend previews use isolated/mock data and no production credentials.
  Browser plugin unavailable: use the repository's Playwright workflow.

## Release-candidate artifact allowlist (not yet built)

| Artifact | Source | Decision |
| --- | --- | --- |
| Zion macOS app and installer | `Zion-App-clean` | Include after signed source checkpoint and packaging approval. |
| Zion iPhone app | `Zion-Coms-clean/mobile/` | Include after signed source checkpoint and packaging approval. |
| Zion relay image | `Zion-Coms-clean/Dockerfile` | Include; the same image contains the relay, pairing-relay binary, and relay web/admin assets. Record one immutable digest for both relay services. |
| Zion push-gateway image | `Zion-Coms-clean/Dockerfile.push-gateway` | Candidate artifact only; its separate database and activation require later approval. |
| Legacy Buzz 0.X desktop app/DMG | `Zion-Coms-clean/desktop/` | **Exclude. Do not build, sign, install, publish, or list it as a Zion release artifact.** Its separate Rust lockfile still has advisory failures; no security exception is granted. |

This allowlist does not authorize a build, signature, publication, installation,
server start, or deployment. The final paired manifest must record separate
source SHAs for the two clones and the exact produced checksums/digests. Never
use this repository's legacy `desktop-v*` release workflow to package Zion.

## Tasks

- [x] Resolve current upstream once; clone into the approved separate directory;
  create the named branch and configure upstream/publication remotes.
- [x] Pin and clone the separately approved newest desktop/web source:
  `block/buzz-app` at `cd9090ee07dcffe8737543dcef74bd8d5899962d`, in
  `/Users/Aiden-Mi8/Documents/Zion-App-clean`, same local branch name.
- [x] Preserve one protected local settings/agent-definition snapshot and a
  sanitized inventory. Privileged server/storage inventory is complete.
  The protected server preservation set is now verified and accepted. The
  separately approved Hermes-only pause lasted 8.892 seconds; no service
  restarted, upgraded or deployed. All original services are running/unpaused.
- [x] Implement Zion presentation in the current desktop/web and mobile source;
  preserve identifiers. Desktop browser and readable mobile widget previews
  exist. The completed local validation follow-through is recorded below.
- [x] Apply relay/OCI identity and prepare fresh, isolated server configuration.
  No candidate services have been created or started.
- [ ] Screen the actual dependency graphs; run focused checks, then one final
  configured validation per completed candidate. Do not repeatedly rebuild
  unchanged inputs or treat a skipped platform as passing.
- [ ] Review the complete narrow branding diff and request the bundled delivery
  approvals with exact remaining gates.

## Current evidence

- Relay/mobile clone started clean at the full pin above; no old source copied.
- Tailscale SSH was authorized and the server inspected read-only on November 7.
  Health, liveness and readiness all returned HTTP 200 through Tailscale.
  Public NIP-11 reports Zion Relay, the Zion description/repository and version
  0.2.0, with authentication required and restricted writes. This is the existing
  platform, not the fresh candidate. The server has about 40 GiB available;
  planned candidate ports have no listeners. No services or environment values
  were changed during that read-only inspection. Subsequent authorized backup
  captured secret-bearing data only into root-protected files on the server;
  no secret values or database payloads were displayed or transferred off-host.
  Six running container IDs, image/index digests and storage mappings are pinned.
  The latest previous backup in the inspected locations was September 10.
- Protected local preservation archive: 1,034,240 bytes, SHA-256
  `5dabe7114cca11fa1b62345ea27027134a3e9d9f0471cb16eeb1627b0dc9bbec`.
  Eight settings files, including 32 keyed agent records and 15 keyless
  definitions, were preserved. These counts do not establish running agents.
  Archive member hashes/readability were checked. This is not a server backup,
  atomic SQLite snapshot, restore test or credential export. Originals and
  Keychain remain untouched. The bounded transfer review selected supported
  import if available during acceptance, otherwise fresh recreation from the
  preserved definitions; no agents have been recreated yet.
- Desktop branding was paused before any edit when upstream's repository split
  was discovered; continuing with the deprecated app would violate the owner's
  newest-platform goal.
- Owner requires release identifier `xyz.block.buzz.app`, rather than the new
  upstream desktop identifier. Native installation/launch therefore requires a
  separately approved old-profile archive/fresh-profile cutover. Browser previews
  remain synthetic and isolated. Never let a development launcher seed or share
  old agent data. Upstream Keychain formats remain unchanged; human identity
  import uses the supported old-identity flow only after authorization.
- The new desktop keeps upstream's `buzz://` ingress and package/sidecar behavior;
  cosmetic rebranding does not add new custom schemes or launcher aliases.
- Shared Zion RC core is `0.7.0`: desktop `0.7.0-zion.1`, iOS build
  `0.7.0+2026110601`. These are source configuration values, not produced artifacts.

## Validation checkpoint (2026-11-07 UTC)

- Desktop presentation: 1,277 focused tests across 38 files passed after
  targeted reruns, not a full-suite run. Three Chromium browser journeys and
  actual welcome/join/back previews used synthetic in-memory state only.
  Additional startup/recovery/navigation changes passed 30 focused tests;
  the new recovery regression was observed failing before the wording repair.
  Full design guards, including the exact six approved artwork colors, pass.
- Native shipping metadata, icon hashes and the approved DMG layout passed
  three Node integration tests after a red/green cycle. No DMG was built and
  no native application was launched.
  Independent review caught historical SENTRA lettering in the reused bitmap;
  the local replacement now reads ZION, but requires owner visual acceptance
  before packaging. Its transformation and new hash are recorded in the
  branding manifest. A stale `Buzz.app` launch path was also repaired: the
  helper derives the configured product name and refuses a missing/non-directory
  bundle. Six synthetic regressions were observed red then green; the affected
  helper file passed 50 tests and adjacent worktree fixtures passed three.
- Relay web checks: 11 tests passed; admin checks: 25 passed and four failures
  were reproduced on unmodified upstream. Both frontend builds/lint/typechecks
  passed. The follow-up invite artwork/download-link change passed six affected
  journeys. The download link targets Zion releases; a matching published RC
  artifact must be verified before public cutover. Legal links remain accurate
  upstream legal references rather than being cosmetically mislabeled.
- Isolated deployment-definition checks: six tests pass, including actual
  rendered Compose configuration, immutable image requirements, project-scoped
  fresh storage, loopback ports, separate gateway database and refusal paths.
  Rendering with synthetic settings is not a running-server test.
  Review added explicit rejection of inherited `volumes_from` storage and
  missing/incorrect service storage mappings; negative regression was observed
  failing before the repair, followed by six passing deployment tests.
- Root Rust dependency policy completed with zero errors under the inherited
  upstream configuration, with 128 warnings and existing advisory suppressions.
  This is not a zero-vulnerability finding or approval of inherited exceptions.
  Desktop Rust policy also completed with zero errors under its inherited policy,
  with 158 warnings. Neither result establishes native compilation or accepts
  the inherited suppressions as Zion release policy.
- Desktop JavaScript audit reported 32 alerts (15 high, 16 moderate, one low):
  six production-path advisories and 26 development-only advisories. All remain
  `needs_review` pending source-to-sink assessment; no new suppressions, version
  changes or risk acceptance were made. Exact screening/triage records are in
  protected Codex Security artifact storage, not committed source or backups.
- Earlier SDK/cache disappearance blocked mobile checks. The pinned Flutter
  3.47.7 / Dart 3.13.5 SDK is now verified and retained in this validation's
  private tool directory, with locked dependencies restored into a private Pub
  cache. The shared cache's disappearance remains unexplained; no project tool
  version, dependency lock or hook was changed to work around it.
- The normal desktop Biome executable link remains missing. The exact pinned
  2.5.14 executable in a temporary tool cache runs the unchanged configured
  checks. Native compilation and the selected WebKit checks are now complete;
  see the repaired final results below. No check was disabled.
- The final service/runtime wording pass ran 44 affected test files: 43 passed,
  with one stale product-wording assertion failing in the agent screen. That
  assertion was corrected; rerunning its affected file passed all 140 tests.
  One existing skipped test remains in the earlier run. These are focused
  checks, not a single full-suite CI result. Formatter-only repairs were applied
  to eight newly updated assertion files rather than altering test behavior.

## Application validation follow-through (2026-11-07)

All changes remain local and uncommitted on the two pinned clean candidates.
The owner approved the focused desktop identity/native-test repairs, readable
mobile light-mode roles and missing labels, then selected the existing Iris
accent for fresh desktop profiles. Valid saved accents, preference keys,
credential formats, protocol identifiers and legacy migration rules remain
unchanged. The old native app/profile has not been launched or altered.

- **Desktop native:** full workspace tests pass: 1,571 passed, zero failed,
  four existing ignored tests. All-target Clippy with warnings denied and Rust
  formatting pass after the repairs. The inherited MockRuntime crash came from
  a fake NSWindow reaching AppKit; only that OS effect is substituted in unit
  tests. Production window behavior and geometry assertions remain intact.
- **Desktop components:** the initial full run covered 1,036 files with 19,534
  passed, 35 failed and 22 pending tests. Focused wording/callback repairs and
  reruns resolved those failures. The Iris-related run covered 94 files: 2,930
  passed and six failed (four stale default assertions and two timeouts).
  Only default expectations were updated; explicit Citrus coverage was retained
  and an Iris-default palette assertion added. The six affected files then
  passed all 189 tests at one worker, with original timeout limits unchanged.
  Latest-per-file coverage totals 19,570 passed, zero remaining failed and 22
  pending tests. This is full-suite coverage plus affected reruns, **not one
  fresh all-green run or remote CI**.
- **Desktop checks and rendering:** configured lint/type/design checks pass;
  30 inherited informational diagnostics and existing design contrast
  exceptions remain visible. Both startup paths use Iris when no valid choice
  is saved; all explicit modern and valid legacy color choices keep their
  mappings. Chromium/WebKit pass all 24 selected startup/presentation journeys,
  with zero retries. Real shell screenshots were inspected in both modes.
- **Mobile:** pinned-tool formatting (1,080 files, zero changes) and analysis
  pass. The repaired full suite recorded 4,540 passed, one failed and 60
  configured skips. The sole failure was an unchanged iOS gateway-validation
  child process unable to find Dart because the direct retained-SDK invocation
  omitted Hermit activation. With Hermit activated, the failed file passes all
  four tests; no source, assertion or timeout was changed. Full run plus that
  failed-file rerun yields 4,541 passed, zero remaining failed and 60 skips.
  This is not a single fresh all-green run. An initial rerun from the repo root
  was rejected before tests because the Flutter project is in `mobile/`.
- **Focused mobile acceptance:** all 48 theme/label and enabled-auth synthetic
  hosted journeys pass. The contrast and full-screen/modal Zion-label
  regressions were observed red before their repairs. Seven earlier branding/
  wordmark tests, four no-gateway safety tests, 27 secp256k1 tests and nine
  gateway/Xcode recipe fixture cases remain applicable where inputs are
  unchanged. Real-font welcome/loading PNGs were inspected; these are widget
  renders, not an installed iPhone app or physical notification acceptance.
- **Scope review:** independent final read-only review found no concrete
  regression or weakened assertion in the focused repairs. It did not clear
  the broader dependency findings or establish native/runtime acceptance.
  Root/desktop/mobile dependency locks are unchanged by this validation batch.
  No new security exception, source checkpoint, push, signing, app installation,
  deployment or production-data change occurred.

Detailed local reports and the cumulative-results summary are retained in
`/private/tmp/zion-app-validation-20261107.TDdp1w`. The inherited dependency
findings above remain open. Conditional/pending tests have not been converted
into pass claims. This closes the approved local application-validation batch,
not the final release, server/client integration or delivery gate.

## Delivery gates and next bounded actions

1. Server preservation completed on 2026-11-07 at 22:39:49 UTC. Sixteen recovery
   components are verified, including the full frozen Hermes folder, all five
   copied SQLite database/WAL families, PostgreSQL, Redis, configuration, Git,
   MinIO and all six running images (95 native OCI blobs). The approved
   Hermes-only pause lasted 8.892 seconds. The accepted marker covers 43
   checksummed files; checksum-list SHA-256 is
   `23924374e2e79d14c94ff4a59357d6531fa1f1214d61255ec7fc5044865dc34b`.
   Backup directory on Zion:
   `/var/backups/zion-coms/zion-online-20261107T210729Z-0a6fzsou`.
   All four Tailscale health checks passed; all six original container IDs,
   start times and restart counts remain unchanged and none is paused. The
   disposable, network-isolated SQLite verifier was removed. No restart,
   upgrade, deployment or app installation occurred. Root-protected backup
   payloads remain on-server; sanitized local evidence is
   `server-backup-verified-20261107.json` in the cleanup ledger directory.
   Restore the frozen Hermes folder/database/WAL set together; do not overlay
   the earlier online SQLite snapshots. The rejected first Hermes tar remains
   explicitly excluded from recovery. This is not an atomic cross-service,
   off-host or fully restore-rehearsed backup; independent ACL/xattr restoration
   semantics have not been rehearsed. Earlier partial records remain historical.
2. Local mobile/native validation and the focused repairs are complete as
   documented above. Review inherited dependency alerts and suppressions next;
   new security exceptions still require explicit approval. Obtain owner visual
   acceptance of the installer replacement before packaging, and preserve the
   configured pending/platform/live acceptance gates.
3. Request a source checkpoint/publication decision for the two distinct
   histories and a paired release manifest; no single SHA covers both repos.
   Package only the new Zion desktop from `Zion-App-clean`, never the deprecated
   `desktop/` source in this repository.
4. After explicit delivery approval, build traceable artifacts, provision only
   the separate fresh candidate stack and perform authentication/pairing/message
   and controlled-agent acceptance. Never attach old volumes.
5. Separately approve signing/notarization, old-profile archive/fresh cutover and
   native app installation; perform physical iPhone notification acceptance
   before any endpoint switch or public release. Preserve old-platform rollback.

## Acceptance still required

Rendered Zion previews; fresh-server health/NIP-11; authentication, pairing and
message round-trip; agent import or documented recreation plus a controlled
response; desktop/iPhone connection to the candidate; fresh dependency-policy
checks; traceable artifacts; signed macOS/Gatekeeper and physical iPhone push
acceptance before cutover. Earlier candidate test counts do not validate this
new source. No release or installation is claimed by this record.

## Local candidate review checkpoint (2026-11-08 AST)

- Relay/mobile `just ci` passed on the pinned clone after restoring the exact
  locked Flutter package configuration. The fresh clone has no `origin/main`
  ref, so the documented `CHECK_FILE_SIZES_BASE` override was set to
  `96af488d968a1ae9d961c2132bea27822735f8da`; no ref was created or moved.
  The configured gate covered Rust/desktop/web/mobile checks, unit tests,
  frontend builds, native desktop tests and Flutter tests. It is not an app
  installation, server smoke test or dependency-advisory result.
- New desktop `pnpm check`, `pnpm build`, and `cargo test -p buzzodz-plugins
  --locked` passed. The plugin crate had 31 passing tests. The Zion presentation
  browser spec passed in Chromium and WebKit (2/2) against local synthetic
  fixtures. The broad integration test command was interrupted after the
  restricted shell denied loopback binding; representative hook and loopback
  tests passed with local fixture access.
- Default-parallel desktop Vitest produced timing failures. The known affected
  App-profile case passed alone, and the Builderlab, message-reaction and
  agent-detail files passed together with the supported single-worker setting
  (48/48). A complete single-worker Vitest run was stopped after the bounded
  validation window without a final summary. Thus the complete desktop test
  gate is **not** recorded as passing; no assertion was weakened.
- The manifest's stale fresh-profile accent was corrected from `cobalt` to the
  approved and implemented `iris`. `git diff --check` passed on both clones.
- Fresh online advisory screening remains pending: the execution environment
  rejected `pnpm audit` because it discloses the dependency graph to a public
  registry. An offline Rust policy check lacked cached crates. No exception
  or policy change was made. Obtain explicit disclosure/network approval before
  rerunning the online audits; do not treat earlier audit evidence as fresh.
- No commits, push, PR, source publication, app packaging/signing/installation,
  candidate-server start, or production change occurred in this checkpoint.
