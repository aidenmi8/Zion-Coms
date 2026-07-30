# Complete Local Upstream Intake System Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and validate the complete selective-upstream-intake system
locally so later project activation requires only installation, configuration,
and a dry run.

**Architecture:** A standard-library Python CLI is the deterministic core. Its
canonical copy lives in the source-controlled Codex skill package, and project
activation vendors the exact same file into `.upstream-intake/tools/` so
repository CI never depends on a personal Codex installation. Each repository
owns its mutable JSON state, protected contracts, commands, and license
declarations. GitHub discovery is read-only; product changes, pushes, PRs,
merges, releases, and deployments remain separate explicit actions.

**Tech Stack:** Python 3 standard library, Git, JSON, GitHub Actions, Just,
Markdown, Codex skill metadata.

**Scope boundary:** Implement in
`/private/tmp/zion-upstream-intake-process` on
`codex/upstream-intake-process`. Do not modify the dirty primary checkout, push,
open a PR, install the skill under `~/.codex/skills`, ingest upstream product
changes, deploy, release, or install an application.

---

### Task 1: Commit the complete-build design and establish the clean baseline

**Files:**

- Modify:
  `docs/superpowers/specs/2026-07-29-reusable-upstream-intake-design.md`
- Create:
  `docs/superpowers/plans/2026-07-29-complete-local-upstream-intake.md`

**Step 1: Verify isolation and branch state**

Run:

```bash
git status --short --branch
git worktree list --porcelain
git rev-parse --git-dir
git rev-parse --git-common-dir
```

Expected: only the design and plan are modified in the isolated worktree; the
primary and other worktrees remain untouched.

**Step 2: Verify the design has no deferred-MVP language**

Run:

```bash
rg -n "MVP|Later Personal|two or three real batches|after proof" \
  docs/superpowers/specs/2026-07-29-reusable-upstream-intake-design.md
```

Expected: no matches.

**Step 3: Run the pre-implementation repository baseline**

Run:

```bash
. ./bin/activate-hermit
git diff --check
just ci
```

Expected: the existing branch baseline passes before code changes. If a
pre-existing failure occurs, record the exact failing command and determine
whether it also fails at `origin/main` before continuing.

**Step 4: Commit the design and execution plan**

Run:

```bash
git add \
  docs/superpowers/specs/2026-07-29-reusable-upstream-intake-design.md \
  docs/superpowers/plans/2026-07-29-complete-local-upstream-intake.md
git diff --cached --check
git commit -m "docs: plan complete upstream intake implementation"
```

Expected: one documentation-only commit.

### Task 2: Scaffold the portable skill and specify configuration contracts

**Files:**

- Create: `tools/codex-skills/upstream-fork-intake/SKILL.md`
- Create: `tools/codex-skills/upstream-fork-intake/agents/openai.yaml`
- Create: `tools/codex-skills/upstream-fork-intake/scripts/upstream_intake.py`
- Create: `tools/codex-skills/upstream-fork-intake/references/ledger-schema.md`
- Create:
  `tools/codex-skills/upstream-fork-intake/references/review-checklist.md`
- Create:
  `tools/codex-skills/upstream-fork-intake/references/apple-platform-checks.md`
- Create: `tools/codex-skills/upstream-fork-intake/assets/project-template/`
- Create: `scripts/test_upstream_intake.py`
- Create: `scripts/fixtures/upstream-intake/config-apache.json`
- Create: `scripts/fixtures/upstream-intake/config-mit.json`

**Step 1: Write failing skill-distribution and configuration tests**

Add tests that assert:

- The required skill files and directories exist.
- `SKILL.md` has `name: upstream-fork-intake`, a trigger-rich description, and
  no template TODO markers.
- `agents/openai.yaml` names `$upstream-fork-intake` in its default prompt.
- Apache and MIT configurations both validate when their declared license file
  matches.
- An Apache declaration over an MIT license body fails.
- A changed upstream/fork SPDX pair fails unless
  `licensing.compatibility_review` is non-empty.
- Only `ios` and `macos` target platforms are accepted.
- Only `native-xcode`, `flutter-ios`, `tauri-macos`, and `swiftpm-macos`
  profiles are accepted.
- `__REQUIRED__` template markers always fail validation.

Run:

```bash
python3 -m unittest scripts/test_upstream_intake.py -v
```

Expected: fail because the skill and validator do not exist.

**Step 2: Initialize the skill with the required creator**

Run:

```bash
python3 \
  /Users/Aiden-Mi8/.codex/skills/.system/skill-creator/scripts/init_skill.py \
  upstream-fork-intake \
  --path tools/codex-skills \
  --resources scripts,references,assets \
  --interface display_name="Upstream Fork Intake" \
  --interface short_description="Review and adapt upstream changes safely" \
  --interface default_prompt="Use $upstream-fork-intake to review this Apple app fork read-only first and prepare one fully classified local intake batch."
```

Expected: the complete skill directory skeleton and `agents/openai.yaml` are
created at the source-controlled location, not in the personal skill directory.

**Step 3: Implement configuration validation in the canonical Python tool**

Add these public functions:

```python
class IntakeError(Exception):
    """A deterministic policy or state validation failure."""


def load_json(path: Path) -> dict[str, object]: ...
def validate_config(repo: Path, config: dict[str, object]) -> None: ...
def detect_license(spdx: str, text: str) -> bool: ...
def require_macos() -> None: ...
```

The configuration validator must require:

- `schema_version: 1`.
- Non-empty upstream/fork repository and branch fields.
- `execution.host_os: "macos"`.
- At least one target platform and supported profile.
- Repository-specific upstream and fork SPDX declarations.
- Existing, non-empty license/notice files.
- A compatibility review when SPDX identifiers differ.
- Positive commit/file caps no greater than the configured policy maximum.
- Non-empty protected contracts and `checks.always`.
- Explicit `commands.authorized` and `commands.prohibited` arrays.
- No `__REQUIRED__` marker anywhere in the configuration.

The host guard belongs to skill-driven Git and initialization operations.
Pure validation remains usable in hosted repository CI.

**Step 4: Make the configuration tests pass**

Run:

```bash
python3 -m unittest \
  scripts.test_upstream_intake.ConfigurationTests \
  scripts.test_upstream_intake.SkillDistributionTests -v
```

Expected: pass.

**Step 5: Commit the scaffold and configuration contract**

Run:

```bash
git add tools/codex-skills/upstream-fork-intake \
  scripts/test_upstream_intake.py \
  scripts/fixtures/upstream-intake
git diff --cached --check
git commit -m "feat: scaffold portable upstream intake skill"
```

### Task 3: Implement batch, decision, dependency, and range validation

**Files:**

- Modify:
  `tools/codex-skills/upstream-fork-intake/scripts/upstream_intake.py`
- Modify: `scripts/test_upstream_intake.py`
- Create: `scripts/fixtures/upstream-intake/mixed-batch.json`
- Create:
  `scripts/fixtures/upstream-intake/invalid-accepted-no-method.json`
- Create:
  `scripts/fixtures/upstream-intake/invalid-deferred-no-revisit.json`
- Create:
  `scripts/fixtures/upstream-intake/invalid-rejected-dependency.json`

**Step 1: Write failing batch invariant tests**

Cover:

- Every entry SHA appears exactly once and belongs to exactly one topic.
- `accept` requires `take` or `adapt` and `included` or `queued`.
- `accept + queued` requires a durable tracking reference.
- `reject` requires rationale, null integration method, and
  `not_applicable` delivery.
- `defer` requires a concrete owner or tracking reference plus revisit trigger.
- A rejected dependency forbids `take`.
- Included work blocked by a rejected dependency requires `adapt`,
  `dependency_resolution: adapt_without_dependency`, and verification.
- A high/critical security candidate is invalid in a normal batch.
- `kind: security` contains only the dedicated security range.
- The batch commit set exactly equals
  `previous_reviewed_sha..pinned_upstream_sha`.
- Duplicate SHAs across open/archive batches fail globally.
- `state.open_batches` exactly names the open batch files.

Run:

```bash
python3 -m unittest \
  scripts.test_upstream_intake.BatchValidationTests \
  scripts.test_upstream_intake.GitRangeValidationTests -v
```

Expected: fail on the first unimplemented invariant.

**Step 2: Implement state, batch, and Git range validation**

Add:

```python
def run_git(repo: Path, *args: str) -> str: ...
def validate_state(state: dict[str, object]) -> None: ...
def validate_batch(batch: dict[str, object]) -> None: ...
def expected_range(repo: Path, previous: str, pinned: str) -> list[str]: ...
def validate_repository(repo: Path, base_ref: str | None = None) -> None: ...
```

Use `git rev-list --reverse --topo-order <previous>..<pinned>` as the
authoritative range. Do not accept abbreviated SHAs in durable state.

**Step 3: Add the `validate` CLI**

Expose:

```bash
python3 upstream_intake.py validate --repo PATH [--base-ref REF]
```

Success prints a one-line JSON result containing `ok`, batch count, entry count,
and reviewed SHA. Policy failures print one actionable error to stderr and exit
2; environment/Git failures exit 3.

**Step 4: Run focused and full unit tests**

Run:

```bash
python3 -m unittest scripts/test_upstream_intake.py -v
```

Expected: pass.

**Step 5: Commit the ledger engine**

Run:

```bash
git add tools/codex-skills/upstream-fork-intake/scripts/upstream_intake.py \
  scripts/test_upstream_intake.py \
  scripts/fixtures/upstream-intake
git diff --cached --check
git commit -m "feat: validate selective upstream decisions"
```

### Task 4: Implement capped read-only discovery and deterministic reports

**Files:**

- Modify:
  `tools/codex-skills/upstream-fork-intake/scripts/upstream_intake.py`
- Modify: `scripts/test_upstream_intake.py`

**Step 1: Write failing discovery tests with temporary Git repositories**

Cover:

- No-change discovery exits successfully and reports zero commits.
- `reviewed_through` must be an ancestor of the requested upstream ref.
- Commits are emitted oldest first with full SHA, subject, author date, files,
  and statistics.
- Subjects ending in `(#123)` group under upstream PR topic `123`; commits
  without a PR reference receive a stable SHA-derived topic.
- Discovery stops at 25 commits or 250 changed files by default.
- A configured lower cap is honored.
- A single commit larger than the file cap is reported as a dedicated-batch
  blocker rather than silently skipped.
- Security/auth/permission/crypto/secret paths and title keywords add explicit
  security reasons.
- Output does not modify refs, the index, the worktree, state files, or batches.
- Markdown and JSON render the same pinned range and counts.

Run:

```bash
python3 -m unittest scripts.test_upstream_intake.DiscoveryTests -v
```

Expected: fail because discovery is not implemented.

**Step 2: Implement discovery and render functions**

Add:

```python
def discover(repo: Path, upstream_ref: str) -> dict[str, object]: ...
def classify_topic(subject: str, sha: str) -> str: ...
def security_reasons(subject: str, files: list[str]) -> list[str]: ...
def render_markdown(report: dict[str, object]) -> str: ...
```

Use Git plumbing only. Discovery may read configured remotes but must not fetch,
switch, merge, cherry-pick, commit, push, or write project state.

**Step 3: Add `discover` and `render` CLI commands**

Expose:

```bash
python3 upstream_intake.py discover \
  --repo PATH --upstream-ref REF --format markdown
python3 upstream_intake.py render --repo PATH --batch BATCH.json
```

Skill-driven invocations add `--require-macos`; report-only hosted CI does not.

**Step 4: Run discovery tests and mutation guard**

Run:

```bash
python3 -m unittest scripts.test_upstream_intake.DiscoveryTests -v
python3 -m unittest scripts/test_upstream_intake.py -v
```

Expected: pass with identical `git status --porcelain` before and after each
discovery test.

**Step 5: Commit discovery**

Run:

```bash
git add tools/codex-skills/upstream-fork-intake/scripts/upstream_intake.py \
  scripts/test_upstream_intake.py
git diff --cached --check
git commit -m "feat: add report-only upstream discovery"
```

### Task 5: Implement audit, archive immutability, and safe initialization

**Files:**

- Modify:
  `tools/codex-skills/upstream-fork-intake/scripts/upstream_intake.py`
- Modify: `scripts/test_upstream_intake.py`
- Create:
  `tools/codex-skills/upstream-fork-intake/assets/project-template/.upstream-intake/config.json`
- Create:
  `tools/codex-skills/upstream-fork-intake/assets/project-template/.upstream-intake/state.json`
- Create:
  `tools/codex-skills/upstream-fork-intake/assets/project-template/.upstream-intake/batches/open/.gitkeep`
- Create:
  `tools/codex-skills/upstream-fork-intake/assets/project-template/.upstream-intake/batches/archive/.gitkeep`
- Create:
  `tools/codex-skills/upstream-fork-intake/assets/project-template/.github/workflows/upstream-sync.yml`
- Create:
  `tools/codex-skills/upstream-fork-intake/assets/project-template/.github/PULL_REQUEST_TEMPLATE/upstream-intake.md`

**Step 1: Write failing archive, audit, and initialization tests**

Cover:

- Archived batch deletion fails.
- Editing archived decisions or original evidence fails.
- Appending a complete reclassification record while preserving history passes.
- Audit reports queued accepted work, triggered deferrals, unreachable pointers,
  missing evidence, and duplicated/omitted commits.
- `init-project` is dry-run by default.
- `init-project --apply` refuses dirty repositories and existing target files.
- Initialization requires macOS, an immutable reviewed SHA, and explicit
  upstream/fork/license/platform/profile inputs.
- Applied project files contain no unresolved markers and vendor a byte-exact
  copy of the canonical tool.
- Re-running initialization is idempotent only when every generated file is
  already identical.

Run:

```bash
python3 -m unittest \
  scripts.test_upstream_intake.ArchiveImmutabilityTests \
  scripts.test_upstream_intake.AuditTests \
  scripts.test_upstream_intake.InitializationTests -v
```

Expected: fail.

**Step 2: Implement archive comparison and audit**

For `--base-ref`, inspect archive changes with Git and compare the base blob to
the worktree. Existing content must be identical except for append-only
`reclassifications`. Add:

```python
def validate_archive_changes(repo: Path, base_ref: str) -> None: ...
def audit_repository(repo: Path) -> dict[str, object]: ...
```

**Step 3: Implement safe project initialization**

Add `init-project` with explicit arguments and a separate `--apply` flag.
Initialization renders the asset templates, writes the configured JSON, and
vendors its own script into `.upstream-intake/tools/upstream_intake.py`.
Before writing, it must verify clean status and preflight every destination.

**Step 4: Run focused and complete tests**

Run:

```bash
python3 -m unittest scripts/test_upstream_intake.py -v
```

Expected: pass.

**Step 5: Commit audit and initialization**

Run:

```bash
git add tools/codex-skills/upstream-fork-intake \
  scripts/test_upstream_intake.py
git diff --cached --check
git commit -m "feat: audit and initialize upstream intake state"
```

### Task 6: Apply the complete repository process to Zion-Coms locally

**Files:**

- Create: `.upstream-intake/config.json`
- Create: `.upstream-intake/state.json`
- Create: `.upstream-intake/tools/upstream_intake.py`
- Create: `.upstream-intake/batches/open/.gitkeep`
- Create: `.upstream-intake/batches/archive/.gitkeep`
- Modify: `.github/workflows/upstream-sync.yml`
- Create: `.github/PULL_REQUEST_TEMPLATE/upstream-intake.md`
- Modify: `Justfile`
- Modify: `scripts/test_upstream_intake.py`

**Step 1: Write failing Zion profile and workflow safety tests**

Assert:

- `upstream` is `block/buzz` main and fork is `aidenmi8/Zion-Coms` main.
- `reviewed_through` is the full upstream `0.5.0` pin
  `60158fce3e670f11bb35d42627857ccaea50ff06`.
- Zion declares Apache-2.0 and the checked-in `LICENSE` matches.
- Targets are iOS/macOS with Flutter iOS and Tauri macOS profiles.
- Protected contracts include visible brand, platform brand, compatibility
  identifiers, routes, sidecars, mobile permissions, and admin brand routes.
- `BUZZ_*`, `buzz://`, package/binary names, bundle identifiers, relay paths,
  Docker names, and legacy URLs are listed as compatibility surfaces.
- The workflow has only `contents: read`, uses
  `persist-credentials: false`, and contains no merge, push, PR, checkout
  branch, write, deploy, release, or install action.
- The workflow writes only a discovery report to `$GITHUB_STEP_SUMMARY`.
- `Justfile` runs `upstream-intake-check` from `check`.
- The vendored and canonical Python files are byte-identical.

Run:

```bash
python3 -m unittest \
  scripts.test_upstream_intake.ZionProfileTests \
  scripts.test_upstream_intake.WorkflowSafetyTests -v
```

Expected: fail.

**Step 2: Generate Zion's checked-in repository state**

Use `init-project --apply` with:

- Upstream: `block/buzz`, remote `upstream`, branch `main`.
- Fork: `aidenmi8/Zion-Coms`, branch `main`.
- Reviewed SHA:
  `60158fce3e670f11bb35d42627857ccaea50ff06`.
- Platforms: `ios,macos`.
- Profiles: `flutter-ios,tauri-macos`.
- Upstream and fork SPDX: `Apache-2.0`.
- License file: `LICENSE`.

Then use `apply_patch` to add Zion's protected contracts, exact authorized
commands, and prohibited Flutter/release/deployment commands.

**Step 3: Replace blind sync with report-only discovery**

Keep the existing schedule and manual dispatch. Change permissions to
`contents: read`; checkout with full history and no persisted credential; fetch
only `upstream/main`; run the vendored `discover` command; append Markdown to
`$GITHUB_STEP_SUMMARY`. Do not create an issue or mutate repository state.

**Step 4: Add the local and CI gate**

Add:

```just
upstream-intake-check:
    python3 -m unittest scripts/test_upstream_intake.py
    python3 .upstream-intake/tools/upstream_intake.py validate --repo .
```

Add `upstream-intake-check` to `check` before language-specific gates.

**Step 5: Run the Zion profile, workflow, and repository validator**

Run:

```bash
python3 -m unittest scripts/test_upstream_intake.py -v
python3 .upstream-intake/tools/upstream_intake.py validate --repo .
just upstream-intake-check
```

Expected: all pass; the worktree contains only intended process files.

**Step 6: Commit the Zion repository process**

Run:

```bash
git add .upstream-intake \
  .github/workflows/upstream-sync.yml \
  .github/PULL_REQUEST_TEMPLATE/upstream-intake.md \
  Justfile scripts/test_upstream_intake.py
git diff --cached --check
git commit -m "ci: enforce selective upstream intake"
```

### Task 7: Finish the skill workflow and reference package

**Files:**

- Modify: `tools/codex-skills/upstream-fork-intake/SKILL.md`
- Modify: `tools/codex-skills/upstream-fork-intake/agents/openai.yaml`
- Modify:
  `tools/codex-skills/upstream-fork-intake/references/ledger-schema.md`
- Modify:
  `tools/codex-skills/upstream-fork-intake/references/review-checklist.md`
- Modify:
  `tools/codex-skills/upstream-fork-intake/references/apple-platform-checks.md`
- Modify:
  `tools/codex-skills/upstream-fork-intake/assets/project-template/`
- Modify: `scripts/test_upstream_intake.py`

**Step 1: Write failing content-routing tests**

Assert that `SKILL.md` requires:

- Read `AGENTS.md`, status, worktree list, remotes, and repository policy first.
- Read-only discovery before mutation.
- A clean isolated worktree and immutable SHAs.
- Topic/PR review with every SHA recorded.
- `accept`, `reject`, or `defer`, plus `take` or `adapt` for accepted work.
- `accept + queued` for wanted large features not in the current batch.
- Security fast-lane and rejected-dependency rules.
- Per-repository licensing and attribution.
- One local batch PR by default with hard-boundary splits only.
- Local validation before push and no automatic PR/merge/deploy/release/install.
- Explicit resource routing to all three references.
- The macOS host guard for skill-driven Git operations.

Run:

```bash
python3 -m unittest scripts.test_upstream_intake.SkillDistributionTests -v
```

Expected: fail until the generated placeholder text is replaced.

**Step 2: Write the concise mandatory `SKILL.md` workflow**

Keep mutable schema detail in `ledger-schema.md`, review heuristics in
`review-checklist.md`, and platform-specific commands in
`apple-platform-checks.md`. Do not add a README or duplicate quick-reference
document.

**Step 3: Complete the references**

- `ledger-schema.md`: fields, lifecycle, invariants, exit codes, archive and
  reclassification rules.
- `review-checklist.md`: dependency graph, risk, security, license,
  attribution, compatibility, testing, provenance, batch split, and release
  separation.
- `apple-platform-checks.md`: configured native Xcode, Flutter iOS, Tauri
  macOS, and SwiftPM macOS routing, including prohibited-command and signing
  boundaries.

**Step 4: Complete generic assets**

The asset template must use `__REQUIRED__` markers so an unconfigured copy fails
closed. The `init-project` command is the supported way to render a valid
instance. Keep the discovery workflow report-only and the PR template focused
on pinned SHAs, decisions, adaptations, contracts, tests, and release
separation.

**Step 5: Validate structure and content**

Run:

```bash
python3 \
  /Users/Aiden-Mi8/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  tools/codex-skills/upstream-fork-intake
python3 -m unittest scripts.test_upstream_intake.SkillDistributionTests -v
```

Expected: `Skill is valid!` and all content tests pass.

**Step 6: Commit the completed skill**

Run:

```bash
git add tools/codex-skills/upstream-fork-intake \
  scripts/test_upstream_intake.py
git diff --cached --check
git commit -m "docs: complete reusable upstream intake skill"
```

### Task 8: Forward-test all supported Apple project profiles

**Files:**

- Modify: `scripts/test_upstream_intake.py`
- Create:
  `scripts/fixtures/upstream-intake/projects/native-xcode/config.json`
- Create:
  `scripts/fixtures/upstream-intake/projects/flutter-ios/config.json`
- Create:
  `scripts/fixtures/upstream-intake/projects/tauri-macos/config.json`
- Create:
  `scripts/fixtures/upstream-intake/projects/swiftpm-macos/config.json`

**Step 1: Write profile forward tests**

Each synthetic project must declare a different combination of:

- MIT or Apache-2.0 license.
- iOS or macOS target.
- Project/workspace/package metadata.
- Design, branding, accessibility, privacy, signing, bundle, extension, or
  sidecar contracts.
- Authorized and prohibited commands.

Tests must prove:

- All four supported profiles validate without changing the core.
- Unknown profiles and Linux/Windows app targets fail.
- The macOS host guard fails clearly when `platform.system()` is mocked to
  `Linux`.
- Pure `validate` remains usable in hosted CI without invoking the host guard.
- Initialization plus validation works from the packaged skill alone.

Run:

```bash
python3 -m unittest scripts.test_upstream_intake.ProjectProfileTests -v
```

Expected: fail before fixtures/profile routing are complete, then pass.

**Step 2: Run parity and fresh-session simulation**

Create a temporary clean Git repository, initialize it using only the packaged
skill path and explicit arguments, add one synthetic upstream remote, run
discovery, write a complete mixed batch, validate it, render it, and audit it.
Do not reference Zion files from this simulation.

Run:

```bash
python3 -m unittest \
  scripts.test_upstream_intake.ProjectProfileTests \
  scripts.test_upstream_intake.EndToEndSimulationTests -v
```

Expected: pass.

**Step 3: Commit cross-project validation**

Run:

```bash
git add scripts/test_upstream_intake.py \
  scripts/fixtures/upstream-intake/projects
git diff --cached --check
git commit -m "test: forward-test Apple upstream intake profiles"
```

### Task 9: Verify the complete local distribution

**Files:**

- Modify only if validation exposes a defect in files already listed above.

**Step 1: Run deterministic process and skill gates**

Run:

```bash
. ./bin/activate-hermit
python3 -m unittest scripts/test_upstream_intake.py -v
python3 .upstream-intake/tools/upstream_intake.py validate \
  --repo . --base-ref origin/main
python3 \
  /Users/Aiden-Mi8/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  tools/codex-skills/upstream-fork-intake
just upstream-intake-check
git diff --check
```

Expected: all pass.

**Step 2: Run non-mutating Zion discovery**

Run:

```bash
python3 .upstream-intake/tools/upstream_intake.py discover \
  --repo . --upstream-ref upstream/main --format markdown --require-macos
```

Capture the pinned SHA, commit count, changed-file count, cap result, security
flags, and before/after `git status --porcelain`. Do not create a batch.

**Step 3: Run existing fork contracts**

Run:

```bash
just visible-brand-check
just compose-healthcheck-test
just mobile-check
just mobile-test
pnpm --dir admin-web check
```

Expected: all relevant Zion protection gates pass. Do not run prohibited
Flutter build/run/clean/upgrade commands.

**Step 4: Run the full local repository gate**

Run:

```bash
just ci
```

Expected: pass. If infrastructure-only integration tests are not part of
`just ci`, report them as not run rather than starting or mutating shared
services.

**Step 5: Verify history and scope**

Run:

```bash
git status --short --branch
git log --oneline --decorate origin/main..HEAD
git diff --stat origin/main...HEAD
git diff --name-only origin/main...HEAD
git diff --check origin/main...HEAD
```

Expected: clean isolated worktree, only process/design/skill/test files changed,
no product code, no untracked artifacts, and no push or PR.

**Step 6: Perform final review**

Use `superpowers:verification-before-completion`, then
`superpowers:requesting-code-review`. Correct findings locally and repeat the
affected gates. Do not push or open a PR.
