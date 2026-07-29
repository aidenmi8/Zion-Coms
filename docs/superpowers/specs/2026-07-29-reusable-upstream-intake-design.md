# Reusable Selective Upstream Intake Design

Date: 2026-07-29

## Summary

Forks must not choose between blindly merging everything from upstream and
losing all upstream fixes. This design establishes a selective, auditable
intake process that discovers every upstream commit, makes an explicit product
decision, implements only approved behavior, and records enough durable state
that a future Codex session can continue without relying on chat history.

The default delivery unit is one batch pull request, prepared and tested
locally before it is pushed. The batch may be split only across hard review,
risk, release, or rollback boundaries.

The process separates three concerns:

1. A reusable personal Codex skill holds the stable procedure and templates.
2. Each fork stores its changing upstream state and decisions in the repository.
3. Build, release, and deployment remain separate from source intake.

The personal skill is intentionally scoped to Codex running on macOS. Its
first-class application targets are iOS and macOS. An Apple-app repository may
also contain supporting web, relay, API, or container code; the skill can
review that code through repository-configured checks without claiming Windows
or Linux application support.

For Zion-Coms, the process replaces the current all-or-nothing scheduled merge
with report-only discovery and locally prepared, fork-owned intake changes.

## Goals

- Discover every new commit from a pinned upstream branch.
- Review every commit before changing the fork.
- Support exact patches and fork-specific adaptations.
- Allow large features to be accepted and queued without importing them
  immediately.
- Record rejected and deferred commits so they do not repeatedly appear as new.
- Preserve fork branding, compatibility contracts, and product decisions.
- Use one batch PR by default to control review, CI, and token overhead.
- Preserve atomic local commits and upstream provenance inside that batch.
- Make the process portable across iOS and macOS repositories, mixed language
  stacks, design systems, and Codex conversations running on the user's Mac.
- Fail closed when the upstream range, decision record, tests, or provenance is
  incomplete.

## Non-goals

- Automatically merging upstream code.
- Automatically approving security fixes or other high-priority changes.
- Keeping the fork's Git ancestry identical to upstream.
- Automatically deploying servers, installing desktop applications, or
  publishing mobile builds.
- Requiring Linear, Jira, GitHub Issues, or another specific tracker.
- Creating a plugin or hosted service before a local skill and repository
  ledger prove insufficient.
- Running the skill from Windows or Linux Codex hosts.
- Providing Windows or Linux application build, packaging, signing, or release
  profiles.

## Vocabulary and State Model

The process uses separate decision, implementation, and delivery fields.
Combining these concepts into one status would make accepted-but-not-yet-built
features indistinguishable from undecided work.

### Product decision

- `accept`: The fork wants the behavior.
- `reject`: The fork intentionally does not want the behavior.
- `defer`: The product or technical decision cannot be made yet.

### Integration method

Only accepted entries receive an integration method.

- `take`: Apply the upstream patch substantially unchanged after verifying its
  full dependency and test context.
- `adapt`: Reproduce the intended behavior with a fork-owned implementation.

### Delivery disposition

- `included`: The accepted implementation is part of the same atomic repository
  change as the ledger entry.
- `queued`: The accepted implementation will arrive later through durable
  tracking.
- `not_applicable`: Used for rejected or currently deferred entries.

`accept + queued` is the correct state for a large feature the fork wants but
does not want to include in the current batch. `defer` means the decision itself
is postponed. Live implementation progress belongs in the linked issue or PR;
the repository ledger does not duplicate that mutable external state.

### Batch lifecycle

- `discovered`
- `reviewing`
- `implementing`
- `in_pr`
- `reviewed`
- `closed`

A batch becomes `reviewed` when every upstream commit has a valid product
decision and all accepted or deferred work has durable tracking. It becomes
`closed` when accepted work intended for the batch is merged or reclassified.

## Durable Repository State

Conversation memory must not be the source of truth for mutable fork state.
Each participating repository stores the following files:

```text
.upstream-intake/
  config.json
  state.json
  batches/
    YYYY-MM-DD-<pinned-short-sha>.json
.github/
  workflows/
    upstream-discovery.yml
  PULL_REQUEST_TEMPLATE/
    upstream-intake.md
```

JSON is used for the portable schema because it can be parsed with standard
libraries without adding a YAML dependency. Projects may render Markdown
reports from these files, but generated reports are not authoritative.

### Configuration

`.upstream-intake/config.json` declares:

```json
{
  "schema_version": 1,
  "upstream": {
    "repository": "block/buzz",
    "remote": "upstream",
    "branch": "main"
  },
  "fork": {
    "repository": "aidenmi8/Zion-Coms",
    "main_branch": "main"
  },
  "execution": {
    "host_os": "macos",
    "target_platforms": ["ios", "macos"],
    "project_profiles": ["flutter-ios", "tauri-macos"]
  },
  "protected_contracts": [
    "visible-brand",
    "compatibility-identifiers",
    "protocols-and-routes"
  ],
  "checks": {
    "always": ["git diff --check", "just ci"],
    "relay": ["just test"],
    "mobile": ["just mobile-check", "just mobile-test"],
    "admin": ["pnpm --dir admin-web check"]
  }
}
```

Commands are project configuration, not universal defaults. Agents must still
read and obey the repository's `AGENTS.md` before running them.

`host_os` must be `macos`; the skill stops with a clear scope error before Git
operations on any other Codex host. `target_platforms` may contain `ios`,
`macos`, or both.
`project_profiles` routes the skill to relevant Apple-platform guidance, but
the repository's explicit contracts and commands remain authoritative.
Supporting web, relay, API, or container areas may define additional checks
without becoming first-class application targets.

### State

`.upstream-intake/state.json` contains only current pointers:

```json
{
  "schema_version": 1,
  "reviewed_through": "<immutable-upstream-sha>",
  "last_discovered": "<immutable-upstream-sha>",
  "open_batches": ["2026-07-29-485d03a"]
}
```

`reviewed_through` means every commit through that upstream SHA has a durable
decision. It does not claim that every accepted change has shipped.

### Batch entry

Each batch pins both ends of the reviewed range and lists every commit exactly
once:

```json
{
  "schema_version": 1,
  "batch_id": "2026-07-29-485d03a",
  "previous_reviewed_sha": "<sha>",
  "pinned_upstream_sha": "<sha>",
  "status": "reviewing",
  "entries": [
    {
      "upstream_sha": "<sha>",
      "title": "Fix a relay race",
      "areas": ["relay"],
      "risk": "high",
      "decision": "accept",
      "integration_method": "take",
      "delivery": "included",
      "rationale": "Wanted reliability fix with compatible dependencies.",
      "dependencies": [],
      "tracking": {
        "issue": null,
        "pull_request": null,
        "fork_commits": []
      },
      "verification": [],
      "revisit": null
    }
  ]
}
```

Required invariants:

- The commit set equals the pinned upstream range exactly.
- Each upstream SHA appears once in the batch and once globally.
- Accepted entries specify `take` or `adapt`.
- Rejected entries include a non-empty rationale.
- Deferred entries include an owner or tracking reference and a concrete
  revisit trigger.
- Accepted work uses `included` or `queued`.
- Accepted queued work includes a tracking reference before the reviewed
  pointer advances.
- A fork commit or PR may map to multiple upstream SHAs only when the changes
  are inseparable, and the rationale explains the grouping.

A durable tracking reference may be a GitHub, Linear, Jira, or other issue URL,
or a repository-local backlog record when no external tracker is configured.

## End-to-end Process

### 1. Establish the fork contract

Before the first intake, document:

- The upstream repository and tracked branch.
- The fork's product purpose.
- Visible identity and assets that must remain fork-owned.
- Environment variables, protocols, package names, identifiers, APIs, routes,
  storage formats, and legacy aliases that must remain compatible.
- Infrastructure and deployment surfaces that must not change implicitly.
- Required local, CI, build, and physical-device gates.
- Owners for each subsystem.
- Xcode projects or workspaces, schemes, deployment targets, bundle IDs,
  entitlements, signing boundaries, extensions, Watch targets, deep links, and
  privacy declarations that apply.
- The app's design system, branding, assets, colors, typography, animation,
  accessibility, and reduced-motion contracts.
- Repository-specific prohibited commands and toolchain activation rules.

Convert fragile requirements into executable contract tests wherever practical.
Text in a policy file is not enough for identifiers or branding that can be
scanned deterministically.

### 2. Discover upstream changes read-only

The scheduled workflow:

1. Fetches the configured upstream branch without tags unless tags are needed.
2. Resolves the current upstream head to an immutable SHA.
3. Verifies that `reviewed_through` is an ancestor of that SHA.
4. Enumerates commits in topological order from `reviewed_through` exclusively
   through the pinned head inclusively.
5. Collects commit titles, files, statistics, upstream PR links when available,
   test changes, and risk indicators.
6. Performs a synthetic merge or patch applicability check without changing
   the fork.
7. Produces an Actions summary or updates one intake issue.

Discovery must not create a code branch, merge, push, or open one PR per commit.
If there are no new commits, it exits successfully without changing state.

If upstream advances while a batch is being reviewed, the pinned batch remains
unchanged. The newer commits wait for the next batch.

### 3. Create an isolated local intake workspace

Before implementation:

1. Inspect `git status` and `git worktree list`.
2. Leave dirty and unrelated worktrees untouched.
3. Create a clean worktree and branch from the exact fork main SHA.
4. Record that base SHA in the batch notes.
5. Establish a clean project CI baseline when proportionate to the batch.

All review and implementation happens against the pinned upstream SHA. A later
upstream head never silently changes the active scope.

### 4. Review every upstream commit

For each commit, inspect:

- The complete diff.
- Parent and neighboring commits.
- Related upstream PR and issue context when available.
- Tests added, changed, or omitted.
- Public interfaces and migration behavior.
- Dependency, lockfile, build, CI, release, and deployment changes.
- Later fixes or partial reversions inside the same pinned batch.
- Assumptions about upstream features the fork previously rejected.
- Impact on the fork contract.

Assign:

- Product decision: `accept`, `reject`, or `defer`.
- Risk: `low`, `medium`, `high`, or `critical`.
- Affected areas.
- Rationale.
- Dependencies.
- Tracking and revisit details when required.

High priority changes are reviewed sooner, not less thoroughly.

### 5. Choose take or adapt for accepted changes

Use `take` only when:

- The behavior is wanted.
- The patch is cohesive and compatible.
- Its required dependencies are already present or also accepted.
- It does not import unwanted product behavior.
- Upstream tests cover the important failure mode.

Apply exact patches with provenance, preserving the original author where Git
supports it and recording the upstream SHA in the commit body.

Use `adapt` when:

- UI, branding, copy, animation, or platform presentation differs.
- The fork's architecture or dependency graph differs.
- Only part of a mixed upstream commit is wanted.
- The upstream patch assumes rejected features.
- Server, schema, package, deployment, or compatibility behavior needs a
  fork-specific implementation.

For adaptations:

1. Reproduce the upstream failure in the fork.
2. Port or recreate the regression test.
3. Confirm the test fails before implementation when practical.
4. Implement the smallest fork-compatible change.
5. Document excluded upstream behavior.
6. Record `Upstream-Source: owner/repository@sha`.
7. Preserve required license and attribution notices.

### 6. Prepare one batch PR locally

One PR is the default publication unit.

Within the local branch:

1. Commit the batch decisions.
2. Create atomic commits for coherent accepted changes.
3. Run focused tests after each implementation.
4. Update the ledger with local commit mappings and verification evidence.
5. Run the full configured local gate.
6. Inspect the complete diff and staged paths.
7. Push once the local batch is coherent.
8. Open one draft PR with the rendered batch report.

The PR body records:

- Fork base SHA.
- Previous reviewed and pinned upstream SHAs.
- Every upstream commit and its decision.
- Accepted integration methods.
- Fork implementation commits.
- Deliberately excluded behavior.
- Compatibility-contract results.
- Test evidence.
- Rollback and release notes.

### 7. Split only across hard boundaries

Do not split merely because upstream used multiple commits. Split when a change:

- Uses a different release or deployment path.
- Includes security-sensitive authentication or authorization behavior.
- Includes a database migration or irreversible data change.
- Is a large optional feature that cannot be reviewed with the batch.
- Requires independent rollback.
- Cannot share the same test or release window.
- Makes the combined review too large to validate reliably.

When a split is required, the primary batch PR still records the decision.
Large accepted work becomes `accept + queued` with a durable tracking issue.
Its later implementation PR updates the original batch entry. This avoids a
separate controller PR and prevents accepted work from being misclassified as
deferred.

### 8. Run fork-owned CI

Upstream CI is supporting evidence; fork CI is authoritative.

Every batch PR runs:

- Ledger schema and range-completeness validation.
- Provenance and state-transition validation.
- Formatting and static analysis.
- Unit and regression tests.
- Fork contract checks.
- Secret and credential checks.
- Changed-subsystem checks.
- Appropriate build checks.

Path-aware jobs may reduce cost, but required global contract tests must never
be skipped. Remote CI runs at least once in a clean hosted environment even
when all local gates passed.

Apple-platform checks are selected from the repository profile:

- Native Swift or Objective-C apps use their configured Xcode workspace,
  project, scheme, simulator or device, signing boundary, and test plan.
- Flutter iOS apps use only repository-authorized Flutter and Xcode commands.
- Tauri macOS apps preserve their configured Rust, frontend, sidecar, bundle,
  signing, and packaging contracts.
- SwiftPM macOS components use their configured package build and test gates.

The skill must prefer enabled Apple build and simulator tooling when repository
instructions require it. It must never invent schemes, bundle IDs, signing
settings, device destinations, or prohibited build commands.

No CI workflow may automatically merge, deploy, publish, migrate, or install
artifacts as part of intake.

### 9. Advance review state safely

The batch PR may update `reviewed_through` to the pinned upstream head only when:

- Every commit in the pinned range appears exactly once.
- Every entry has a valid decision and rationale.
- Accepted work is either included or durably queued.
- Deferred work has an owner and revisit trigger.
- Rejected work has a reason.
- The validator passes.

The reviewed pointer advances when the batch PR merges. Rejected commits then
remain processed without entering Git ancestry. Accepted queued work remains
visible through its delivery disposition and tracking reference.

### 10. Release separately

Source merge does not authorize release.

- Server releases require backups, pinned artifacts or image digests, migration
  verification, health checks, and rollback readiness.
- Desktop releases require signed or explicitly unsigned artifact validation,
  bundle and sidecar contracts, and launch smoke tests.
- Mobile releases require signing, device or TestFlight installation, platform
  permissions, pairing, notification, and attachment acceptance where relevant.
- Web and admin releases require production builds, route checks, and visual or
  browser regression verification.

After verification, attach the release or deployment evidence to the entry in
the next normal repository change or its durable tracking issue. Do not create
a bookkeeping-only PR solely to mirror a live deployment status.

### 11. Audit and revisit

A recurring audit:

- Recomputes all upstream commits since the initial baseline.
- Verifies that each appears exactly once in the ledger.
- Reports accepted work that remains queued.
- Reports deferred work whose revisit trigger has fired.
- Detects missing PR, fork commit, verification, or release references.
- Flags upstream force-pushes or unreachable reviewed SHAs.

Rejected work is not reopened automatically. It may be reclassified by a
deliberate ledger change with a new rationale.

## PR and CI Cost Controls

- Discovery produces a report or issue, not a PR.
- Classification happens locally.
- No PR is created for each upstream commit.
- Local focused tests run during implementation.
- Full local CI runs before the first push.
- One batch branch is pushed by default.
- One hosted CI run validates the clean environment.
- Re-pushes occur only for actual review or hosted-CI findings.
- A ledger-only batch PR is allowed when every change is rejected, deferred, or
  accepted for later.

These rules reduce repeated context reconstruction, PR summaries, hosted CI,
and reviewer effort without sacrificing provenance.

## Zion-Coms Profile

Zion-Coms must preserve:

- Visible Zion branding.
- `BUZZ_*` environment variables.
- `buzz://` links.
- Buzz package, crate, binary, and sidecar names.
- `xyz.block.buzz.app` and existing mobile bundle identifiers.
- Relay routes, Docker names, legacy URLs, and asset aliases.

The current upstream batch should be processed as one decision ledger and one
default implementation PR. Small correctness, documentation, and CI changes
may share that PR. Mobile presentation changes should be adapted. A large
optional feature should be accepted and queued, rejected, or deferred based on
product intent; if accepted for immediate implementation, it should be split
only when the hard-boundary rules require it.

The existing `.github/workflows/upstream-sync.yml` must eventually be replaced
or rewritten because it attempts an all-or-nothing merge and produces no
reviewable result when conflicts stop the job.

## Portable Codex Skill

### Why a skill

A skill is sufficient because this is a repeatable local reasoning and Git
workflow running on the user's Mac. It needs instructions, deterministic
validation scripts, and templates, but no dedicated hosted service or
third-party connector.

A plugin should be considered later only if the process needs a central
cross-repository dashboard, a GitHub App, organization-wide credentials,
automatic tracker synchronization, or a remote policy service.

### Skill location and ownership

The default installation target on the user's Mac is:

```text
${CODEX_HOME:-$HOME/.codex}/skills/upstream-fork-intake/
```

That makes the workflow available to Codex across projects and conversations.
The skill must never store repository-specific state. It reads the checked-in
`.upstream-intake/` directory of the active repository.

Installing the skill once makes it available to other local Codex tasks using
the same profile. The skill folder is also the portable distribution unit for
another Mac or Codex profile. Environments that cannot load local skills can
use the checked-in repository process and the skill's default prompt, but they
will not receive automatic skill triggering.

### Proposed skill contents

```text
upstream-fork-intake/
  SKILL.md
  agents/
    openai.yaml
  scripts/
    upstream_intake.py
  references/
    ledger-schema.md
    review-checklist.md
    apple-platform-checks.md
  assets/
    project-template/
```

- `SKILL.md` contains the concise mandatory sequence, safety boundaries,
  classification rules, and resource routing.
- `upstream_intake.py` uses the configured Python 3 runtime on macOS, Python's
  standard library, and Git to discover, validate, and render batches without a
  project-language dependency. It verifies the Darwin host before Git
  operations.
- `ledger-schema.md` defines configuration, state, batch, and transition rules.
- `review-checklist.md` defines dependency, risk, compatibility, test, and
  release checks.
- `apple-platform-checks.md` routes native Xcode, Flutter iOS, Tauri macOS, and
  SwiftPM repositories to the correct project-configured contracts.
- `assets/project-template/` contains generic configuration, state, discovery
  workflow, and PR-body templates that can be instantiated in another fork.
- `agents/openai.yaml` exposes a clear display name and default prompt.

No README, changelog, or duplicate quick-reference files are added.

### Skill trigger and default prompt

The description should trigger when a user on the configured Mac asks to
compare, ingest, port, adapt, reject, defer, synchronize, or review changes
from an upstream repository into a customized iOS or macOS application fork.

The default prompt should be equivalent to:

> Review this fork's new upstream commits using its checked-in intake policy.
> Work read-only first, classify every commit as accept, reject, or defer, use
> take or adapt for accepted work, and do not push or open a PR until the local
> batch and evidence are complete.

### Skill safety requirements

The skill must:

- Verify that Codex is running on macOS before Git operations.
- Read `AGENTS.md` and repository instructions first.
- Run `git status` and `git worktree list` before mutation.
- Use a clean isolated worktree for implementation.
- Pin immutable fork and upstream SHAs.
- Never modify a dirty checkout.
- Never assume a clean merge is semantically acceptable.
- Never advance the reviewed pointer with unclassified commits.
- Never auto-merge or auto-deploy.
- Preserve repository-specific protected contracts.
- Treat app design, branding, accessibility, bundle metadata, signing,
  entitlements, extensions, and privacy declarations as repository-specific.
- Never modify signing identities, provisioning, bundle identifiers, or device
  registrations without explicit project configuration and user authority.
- Stop on force-push, missing ancestry, incomplete state, or unavailable
  required tools.

### Validation

The skill implementation must be validated with:

- The skill creator's structural validator.
- Unit fixtures for no-change, mixed-decision, force-push, missing-commit,
  invalid-transition, deferred-without-trigger, and accepted-without-method
  cases.
- A dry run against Zion-Coms without modifying its main checkout.
- A dry run against at least one differently structured Apple project.
- Profile tests covering native Xcode, Flutter iOS, Tauri macOS, and SwiftPM
  configuration without requiring every project to use every profile.
- A negative test confirming that the skill stops on a non-macOS host.

## Failure Handling

- Dirty primary checkout: create an isolated worktree; never reset user work.
- Upstream force-push or missing ancestry: stop and require a new reviewed
  baseline decision.
- Upstream unavailable: retain state and report discovery as incomplete.
- Commit omitted or duplicated: fail validation.
- Accepted entry without method: fail validation.
- Rejected entry without rationale: fail validation.
- Deferred entry without owner or trigger: fail validation.
- Take patch with conflicts: re-evaluate as adapt; do not resolve blindly.
- Adaptation without test evidence: block unless the entry is documentation-only
  and records why no executable test applies.
- Local CI failure: do not push.
- Hosted CI failure: keep the PR draft and revise locally.
- Release failure: roll back the release without rewriting the intake decision.

## Porting to Another Project

1. Install or invoke the personal `upstream-fork-intake` skill.
2. Add `.upstream-intake/config.json`.
3. Select `ios`, `macos`, or both as target platforms.
4. Select the applicable native Xcode, Flutter iOS, Tauri macOS, or SwiftPM
   profiles.
5. Record a deliberately chosen initial `reviewed_through` SHA.
6. Add project-specific design, branding, bundle, entitlement, signing,
   privacy, extension, compatibility, and testing contracts.
7. Add explicit authorized and prohibited commands.
8. Add the report-only discovery workflow.
9. Protect the fork's main branch with required checks.
10. Run discovery in dry-run mode.
11. Review and commit the first batch manually.
12. Enable the recurring schedule only after the dry run and validator pass.

The portable process remains the same; only repository configuration,
Apple project profiles, protected contracts, owners, and test commands change.
Supporting web or server components remain governed by that repository's
additional configured checks.

## Acceptance Criteria

- Another Codex session can determine the exact upstream review state using
  only repository files and Git history.
- Every upstream commit receives one durable decision.
- Accepted work distinguishes exact take from manual adaptation.
- Large accepted features can remain queued without being deferred.
- Rejected commits do not reappear as unreviewed.
- Deferred commits have concrete revisit conditions.
- One batch PR is the default.
- Split PRs require a documented hard boundary.
- Fork contracts run in CI.
- Source intake cannot deploy or publish automatically.
- The personal skill runs from the user's Mac and contains no Zion-specific
  mutable state.
- iOS and macOS repositories can supply different architecture, toolchain,
  design, branding, signing, and test profiles without changing the skill core.
- The skill stops clearly when invoked from an unsupported host.
- A dry run can demonstrate the complete process without modifying the fork.
