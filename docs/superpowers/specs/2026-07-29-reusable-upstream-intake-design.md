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

Implementation and activation are deliberately separated. The complete
repository process, portable personal skill package, Apple project profiles,
templates, and validation suite are built and tested locally now. They remain
on an isolated branch until activation is approved. Applying the system later
means merging the checked-in repository process, installing the already-tested
skill package into the user's Codex profile, and enabling it per project; it
does not mean designing or implementing the system again.

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
- Review related changes as upstream PR or topic units while recording every
  commit SHA before changing the fork.
- Support exact patches and fork-specific adaptations.
- Allow large features to be accepted and queued without importing them
  immediately.
- Record rejected and deferred commits so they do not repeatedly appear as new.
- Preserve fork branding, compatibility contracts, and product decisions.
- Use one batch PR by default to control review, CI, and token overhead.
- Cap normal batch size and route urgent security work through a dedicated fast
  lane.
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
- Creating a plugin or hosted service before the local skill and repository
  ledger prove insufficient.
- Installing or activating the locally built skill in every project as part of
  this implementation branch.
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
    open/
      YYYY-MM-DD-<pinned-short-sha>.json
    archive/
.github/
  workflows/
    upstream-discovery.yml
  PULL_REQUEST_TEMPLATE/
    upstream-intake.md
scripts/
  upstream-intake.mjs
  upstream-intake.test.mjs
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
  "licensing": {
    "upstream_spdx": "Apache-2.0",
    "fork_spdx": "Apache-2.0",
    "license_files": ["LICENSE"],
    "notice_files": []
  },
  "batch_limits": {
    "max_commits": 25,
    "max_changed_files": 250
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

Licensing is repository-specific. Zion-Coms declares `Apache-2.0`; a fork whose
upstream and fork are MIT-licensed declares `MIT` instead. The validator must
never assume one license for every project. A missing, changed, or incompatible
license declaration blocks `take` and `adapt` until it is reviewed.

Normal discovery pins no more than 25 commits or 250 changed files per batch by
default. Projects may choose lower limits. When either cap would be exceeded,
discovery pins an earlier upstream SHA and leaves the remainder for the next
batch. Critical security work and hard-boundary changes use dedicated batches
instead of increasing the cap.

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
  "kind": "normal",
  "status": "reviewing",
  "topics": [
    {
      "topic_id": "relay-lock-inversion",
      "title": "Relay subscription lock inversion",
      "upstream_pr": null,
      "entry_shas": ["<sha>"]
    }
  ],
  "entries": [
    {
      "upstream_sha": "<sha>",
      "topic_id": "relay-lock-inversion",
      "title": "Fix a relay race",
      "areas": ["relay"],
      "risk": "high",
      "decision": "accept",
      "integration_method": "take",
      "delivery": "included",
      "rationale": "Wanted reliability fix with compatible dependencies.",
      "dependencies": [],
      "blocked_by_rejected": [],
      "dependency_resolution": null,
      "security_candidate": false,
      "security_reasons": [],
      "tracking": {
        "issue": null,
        "pull_request": null,
        "fork_commits": []
      },
      "verification": [],
      "revisit": null
    }
  ],
  "reclassifications": []
}
```

Required invariants:

- The commit set equals the pinned upstream range exactly.
- Each upstream SHA appears once in the batch and once globally.
- Every entry belongs to exactly one reviewed topic, normally an upstream PR or
  coherent change chain.
- Accepted entries specify `take` or `adapt`.
- Rejected entries include a non-empty rationale.
- Deferred entries include an owner or tracking reference and a concrete
  revisit trigger.
- Accepted work uses `included` or `queued`.
- Accepted queued work includes a tracking reference before the reviewed
  pointer advances.
- A fork commit or PR may map to multiple upstream SHAs only when the changes
  are inseparable, and the rationale explains the grouping.
- An entry blocked by a rejected dependency can never use `take`.
- An entry blocked by a rejected dependency can be `included` only as a tested
  `adapt` with `dependency_resolution` set to `adapt_without_dependency`.
- An accepted queued entry blocked by a rejected dependency must link to a
  concrete implementation plan; otherwise it must be rejected or deferred.
- A closed batch under `batches/archive/` is immutable unless the change adds a
  reclassification record containing the old decision, new decision, reason,
  date, and tracking reference.

A durable tracking reference may be a GitHub, Linear, Jira, or other issue URL,
or a repository-local backlog record when no external tracker is configured.
`kind` is `normal` or `security`. A reclassification record contains the
affected upstream SHA, old and new decisions, reason, date, and tracking
reference; it never rewrites the original historical decision without an audit
record.

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
- The upstream and fork license identifiers, license files, notice files,
  copyright headers, and attribution requirements.

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
5. Pins an earlier head when the configured commit or changed-file cap would be
   exceeded.
6. Proposes topic groups using upstream PRs and coherent change chains; a human
   or reviewing agent confirms the groups.
7. Collects commit titles, files, statistics, upstream PR links when available,
   test changes, dependencies, and risk indicators.
8. Flags security candidates using CVE or advisory references, security labels,
   and changes to authentication, authorization, cryptography, permissions, or
   secret-handling code.
9. Performs a synthetic merge or patch applicability check without changing
   the fork.
10. Produces an Actions summary or updates one intake issue.

Discovery must not create a code branch, merge, push, or open one PR per commit.
If there are no new commits, it exits successfully without changing state.

If upstream advances while a batch is being reviewed, the pinned batch remains
unchanged. The newer commits wait for the next batch.

Security detection is a prioritization signal, not an approval. A high or
critical security candidate pauses normal batch publication and receives a
dedicated security intake batch and PR. It still receives full dependency,
license, contract, and test review. Embargoed details remain in an appropriately
private tracker rather than a public intake report.

### 3. Create an isolated local intake workspace

Before implementation:

1. Inspect `git status` and `git worktree list`.
2. Leave dirty and unrelated worktrees untouched.
3. Create a clean worktree and branch from the exact fork main SHA.
4. Record that base SHA in the batch notes.
5. Establish a clean project CI baseline when proportionate to the batch.

All review and implementation happens against the pinned upstream SHA. A later
upstream head never silently changes the active scope.

### 4. Review topic groups and every upstream SHA

Use the upstream PR or coherent topic group as the decision unit to avoid
re-deciding a feature, fixup, and partial revert separately. Still inspect and
record every SHA so range completeness remains deterministic.

For each topic and its commits, inspect:

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

If accepted change B depends on rejected change A, choose exactly one outcome:

- Adapt B without A and prove the replacement dependency path with tests.
- Accept B as queued with a durable plan that explicitly removes the dependency
  on A.
- Reject B because A is required.
- Defer B until the dependency decision changes.

Never mark B as `take` or `included` while A is absent. The reviewed pointer may
advance only after the dependency outcome is explicit and valid.

High priority changes are reviewed sooner, not less thoroughly. High or
critical security candidates leave the normal queue through the dedicated
fast lane described above.

### 5. Choose take or adapt for accepted changes

Start UI, design, branding, server, schema, package, build, release, and
deployment changes as `adapt` candidates. Reclassify one as `take` only after
dependency and contract review proves the patch is isolated. Pure
dependency-free logic fixes, tests, and documentation may start as `take`
candidates. These are review defaults, not automatic decisions.

Use `take` only when:

- The behavior is wanted.
- The patch is cohesive and compatible.
- Its required dependencies are already present or also accepted.
- It does not import unwanted product behavior.
- Upstream tests cover the important failure mode.

Apply exact patches with provenance, preserving the original author where Git
supports it and recording `Upstream-Source` and `Upstream-Commit` in the commit
body.

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
6. Record `Upstream-Source: owner/repository` and `Upstream-Commit: sha`.
7. Preserve required license and attribution notices.

Before either method:

1. Read the repository's configured upstream and fork licenses.
2. Confirm the checked-in license files match the declarations.
3. Preserve copyright headers when taking or adapting substantial files.
4. Preserve or update `NOTICE` and third-party attribution when the applicable
   license or redistribution requires it.
5. Stop for explicit review when license compatibility or attribution is
   unclear.

Zion-Coms follows Apache-2.0. Other repositories may declare MIT or another
license; the workflow applies the declared license rather than assuming
Zion-Coms rules everywhere.

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
- Topic groups and their upstream PRs when available.
- Every upstream commit and its decision.
- Accepted integration methods.
- Rejected dependencies and their resolutions.
- Security-candidate disposition.
- License and attribution review.
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
- Would exceed the configured commit or changed-file cap.
- Is a high or critical security candidate requiring the security fast lane.

When a split is required, the primary batch PR still records the decision.
Large accepted work becomes `accept + queued` with a durable tracking issue.
Its later implementation PR updates the original batch entry. This avoids a
separate controller PR and prevents accepted work from being misclassified as
deferred.

### 8. Run fork-owned CI

Upstream CI is supporting evidence; fork CI is authoritative.

The repository implementation adds a normal CI job for the ledger validator.
The validator checks:

- JSON parsing and schema version.
- Pinned range completeness and uniqueness.
- Topic membership for every SHA.
- Decision, integration method, and delivery invariants.
- Rejected-dependency resolution.
- Required tracking and revisit fields.
- License declarations and provenance fields.
- Batch-size limits.
- Archived-batch immutability and valid reclassification records.

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

Zion-Coms batches use its existing `just` gates, visible-brand scanner,
platform-brand contract, mobile checks, admin checks, and relevant integration
tests. The portable implementation includes the complete supported Apple
profile matrix. Each repository selects only the profiles it actually uses:

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
- No included entry remains blocked by a rejected dependency.
- Deferred work has an owner and revisit trigger.
- Rejected work has a reason.
- License declarations, required attribution, and provenance are complete.
- High or critical security candidates are not hidden inside a normal batch.
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
- Keeps only active batches hot and moves closed batches under
  `batches/archive/`.
- Rejects archived-batch edits that lack an explicit reclassification record.

Rejected work is not reopened automatically. It may be reclassified by a
deliberate ledger change with a new rationale.

## PR and CI Cost Controls

- Discovery produces a report or issue, not a PR.
- Topic classification and SHA-level recording happen locally.
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

- Apache-2.0 licensing and applicable attribution.
- Visible Zion branding.
- `BUZZ_*` environment variables.
- `buzz://` links.
- Buzz package, crate, binary, and sidecar names.
- `xyz.block.buzz.app` and existing mobile bundle identifiers.
- Relay routes, Docker names, legacy URLs, and asset aliases.

The current upstream batch should be processed as one decision ledger and one
default implementation PR. Small correctness, documentation, and CI changes
may share that PR. Mobile presentation, shared server, infrastructure, and
release changes start as adapt candidates. A dependency-free fix may become a
take after review. A large optional feature should be accepted and queued,
rejected, or deferred based on product intent; if accepted for immediate
implementation, it should be split only when the hard-boundary rules require
it.

The local implementation must remove merge, push, and PR creation from the existing
`.github/workflows/upstream-sync.yml` before its next scheduled run. The
replacement remains report-only after activation; repository state changes
still require a reviewed local batch.

## Complete Local Build and Staged Activation

Stages 1 through 4 are implemented and validated now on the isolated branch.
Stage 5 is the later application step. This makes activation a bounded copy,
merge, and configuration operation rather than a second development project.

### Stage 1: establish protected contracts

- Inventory the existing Zion visible-brand, platform-brand, identifier, route,
  sidecar, mobile, admin, and release contracts.
- Add only missing executable checks needed to protect an upstream intake.
- Record Zion-Coms as Apache-2.0 and identify applicable attribution files.
- Establish a clean baseline for the existing repository checks.

### Stage 2: build the repository engine

- Check in configuration, state, and open/archive batch directories.
- Add the repo-local discovery, validation, rendering, and audit commands.
- Add focused fixtures for every required state and failure mode.
- Add validation as a normal required CI job.
- Rewrite the scheduled sync as report-only discovery with no write permission,
  branch creation, merge, push, or PR creation.
- Generate a pinned dry-run topic report without modifying product code.
- Verify archived-batch immutability, security fast-lane routing, rejected
  dependencies, batch caps, and license declarations.

### Stage 3: build the portable skill package

- Initialize the complete `upstream-fork-intake` skill package under the
  source-controlled tooling directory on the isolated branch.
- Include the mandatory workflow, deterministic Python tool, ledger schema,
  review checklist, Apple platform routing, project template, and agent
  metadata.
- Keep mutable project state outside the skill in each repository's
  `.upstream-intake/` directory.
- Include native Xcode, Flutter iOS, Tauri macOS, and SwiftPM profile support
  now, while requiring each repository to configure only the profiles it uses.
- Do not install the skill into the user's personal Codex profile during this
  stage.

### Stage 4: validate the complete distribution

- Run repository-unit fixtures for no-change, mixed-decision, force-push,
  missing-commit, invalid-transition, deferred-without-trigger,
  accepted-without-method, rejected-dependency, archive mutation, security
  routing, batch-cap, and license cases.
- Run the repo-local and portable skill validators against the same fixtures and
  require equivalent decisions.
- Run a non-mutating dry run against Zion-Coms.
- Run synthetic forward tests for native Xcode, Flutter iOS, Tauri macOS, and
  SwiftPM repositories with different license declarations and contracts.
- Run the skill creator's structural validator and a negative non-macOS test.
- Run focused repository checks followed by the full applicable local gate.
- Confirm a fresh Codex session can operate the process using only the
  repository state and packaged skill resources.

### Stage 5: apply and activate later

- Review and merge or cherry-pick the isolated implementation branch.
- Install the exact validated skill package into the user's Codex skill
  directory.
- Instantiate the project template in each selected repository.
- Declare that repository's real license, upstream, platforms, profiles,
  protected contracts, authorized commands, and prohibited commands.
- Run discovery and validation in dry-run mode before enabling its schedule.
- Process the first real upstream batch locally and publish only after explicit
  approval.

No push, PR, merge, deployment, release, application install, or other-project
activation is part of stages 1 through 4.

## Portable Personal Codex Skill

### Why a skill

A skill is sufficient because this is a repeatable local reasoning and Git
workflow running on the user's Mac. It needs instructions, deterministic
validation scripts, and templates, but no dedicated hosted service or
third-party connector.

A plugin should be considered later only if the process needs a central
cross-repository dashboard, a GitHub App, organization-wide credentials,
automatic tracker synchronization, or a remote policy service.

### Skill source, installation, and ownership

The canonical, reviewable source package is built locally on the isolated
branch at:

```text
tools/codex-skills/upstream-fork-intake/
```

The later installation target on the user's Mac is:

```text
${CODEX_HOME:-$HOME/.codex}/skills/upstream-fork-intake/
```

The source package is structurally and behaviorally validated before
installation. Activation copies that exact package into the personal skill
directory and verifies it again. The skill must never store
repository-specific state. It reads the checked-in `.upstream-intake/`
directory of the active repository.

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
- `review-checklist.md` defines dependency, risk, compatibility, license,
  attribution, test, and release checks.
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
- Review coherent topics while recording every SHA.
- Never advance the reviewed pointer with unclassified commits.
- Never include a change whose rejected dependency remains unresolved.
- Route high and critical security candidates to the dedicated fast lane.
- Never auto-merge or auto-deploy.
- Preserve repository-specific protected contracts.
- Read and apply the repository's declared license and attribution rules rather
  than assuming Apache-2.0 or MIT globally.
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
- Batch over the configured cap: pin an earlier upstream SHA.
- High or critical security candidate in a normal batch: pause and create a
  dedicated security intake.
- Accepted change blocked by a rejected dependency: adapt with proof, queue
  with a concrete plan, reject, or defer.
- Missing, changed, or unclear license declaration: stop take/adapt work.
- Archived batch changed without a reclassification record: fail validation.
- Take patch with conflicts: re-evaluate as adapt; do not resolve blindly.
- Adaptation without test evidence: block unless the entry is documentation-only
  and records why no executable test applies.
- Local CI failure: do not push.
- Hosted CI failure: keep the PR draft and revise locally.
- Release failure: roll back the release without rewriting the intake decision.

## Applying to Another Project

1. Install or invoke the personal `upstream-fork-intake` skill.
2. Add `.upstream-intake/config.json`.
3. Select `ios`, `macos`, or both as target platforms.
4. Select the applicable native Xcode, Flutter iOS, Tauri macOS, or SwiftPM
   profiles.
5. Declare the repository's actual upstream and fork licenses, commonly MIT in
   the user's other projects and Apache-2.0 for Zion-Coms.
6. Record a deliberately chosen initial `reviewed_through` SHA.
7. Add project-specific design, branding, bundle, entitlement, signing,
   privacy, extension, compatibility, and testing contracts.
8. Add explicit authorized and prohibited commands.
9. Add the report-only discovery workflow.
10. Protect the fork's main branch with required checks.
11. Run discovery in dry-run mode.
12. Review and commit the first batch manually.
13. Enable the recurring schedule only after the dry run and validator pass.

The portable process remains the same; only repository configuration,
Apple project profiles, protected contracts, owners, and test commands change.
Supporting web or server components remain governed by that repository's
additional configured checks.

## Acceptance Criteria

### Complete local implementation

- Another Codex session can determine the exact upstream review state using
  only repository files and Git history.
- Coherent topics are the review unit and every upstream commit receives one
  durable SHA-level record.
- Accepted work distinguishes exact take from manual adaptation.
- Large accepted features can remain queued without being deferred.
- Rejected commits do not reappear as unreviewed.
- Deferred commits have concrete revisit conditions.
- One batch PR is the default.
- Normal batches respect configured size caps.
- Split PRs require a documented hard boundary.
- High and critical security candidates use the dedicated fast lane.
- A rejected dependency cannot hide behind an accepted included entry.
- Each repository declares its actual license and preserves required
  attribution.
- Closed batches are archived and cannot change silently.
- The ledger validator runs as a normal required CI check.
- Fork contracts run in CI.
- Source intake cannot deploy or publish automatically.
- The existing blind merge workflow is report-only.
- The repo-local and portable validators agree on all shared fixtures.
- A synthetic mixed batch proves take, adapt, reject, defer, included, and
  queued invariants without changing product code.
- The personal skill runs from the user's Mac and contains no Zion-specific
  mutable state.
- iOS and macOS repositories can supply different architecture, toolchain,
  design, branding, signing, and test profiles without changing the skill core.
- The skill stops clearly when invoked from an unsupported host.
- A dry run can demonstrate the complete process without modifying the fork.
- The complete skill package and project template are source-controlled and
  structurally validated before personal installation.

### Activation readiness

- Applying the package requires configuration and validation, not new process
  design or tool implementation.
- Zion-Coms declares Apache-2.0; another project may declare MIT or its actual
  license without changing the skill core.
- The first real batch remains a separately reviewed product decision.
- Push, PR, merge, release, deployment, and application installation remain
  explicit user-authorized actions.
