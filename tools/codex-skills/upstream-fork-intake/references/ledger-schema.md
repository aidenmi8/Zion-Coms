# Upstream intake ledger schema

## Contents

- Repository configuration
- Durable state
- Batch and topic records
- Decision rules
- Range and dependency invariants
- Archive immutability
- Reclassification
- Commands and Exit codes

All durable files are JSON with `schema_version: 1`. Use full 40-character
lowercase commit SHAs. Generated Markdown is a view, never the source of truth.

## Repository configuration

`.upstream-intake/config.json` contains:

- `upstream`: repository, remote, and branch.
- `fork`: repository and main branch.
- `execution`: `host_os: macos`, one or both of `ios` and `macos`, and supported
  project profiles.
- `licensing`: upstream/fork SPDX identifiers, license files, notice files, and
  a compatibility review when identifiers differ.
- `batch_limits`: positive caps no greater than 25 commits and 250 changed
  files.
- `protected_contracts`: fork-owned behavior that intake cannot silently
  change.
- `checks`: required validation commands.
- `commands.authorized` and `commands.prohibited`: repository policy, not
  universal defaults.

Every listed license or notice file must exist and be non-empty. Templates
contain `__REQUIRED__` markers and must fail until `init-project` renders them.

## Durable state

`.upstream-intake/state.json` holds only:

```json
{
  "schema_version": 1,
  "reviewed_through": "<full-sha>",
  "last_discovered": "<full-sha>",
  "open_batches": ["<batch-id>"]
}
```

`reviewed_through` means every upstream commit through that SHA has a durable
decision. It does not mean every accepted change shipped. `open_batches` must
exactly equal the JSON filenames under `batches/open/`, without extensions.

## Batch and topic records

A batch pins `previous_reviewed_sha` and `pinned_upstream_sha`, declares
`kind: normal|security`, has a lifecycle status, and contains topics, entries,
and `reclassifications`.

Topics have a stable `topic_id`, title, optional upstream PR, and `entry_shas`.
Every entry has provenance, topic, areas, risk, decision, integration method,
delivery, rationale, dependencies, security evidence, tracking, verification,
and optional revisit data.

Lifecycle:

`discovered` → `reviewing` → `implementing` → `in_pr` → `reviewed` → `closed`

## Decision rules

- `accept` requires `take` or `adapt` and `included` or `queued`.
- `accept + queued` requires a durable issue, PR, local backlog, or
  implementation-plan reference.
- `reject` requires rationale, null integration method, and
  `not_applicable` delivery.
- `defer` requires null integration method, `not_applicable` delivery, a
  concrete revisit trigger, and an owner or tracking reference.
- Only accepted entries receive an integration method.

## Range and dependency invariants

- Entry SHAs exactly equal
  `previous_reviewed_sha..pinned_upstream_sha` in oldest-first topological
  order.
- Each SHA appears once in its batch, once in a topic, and once globally.
- A high/critical security candidate is not valid in a normal batch.
- A security batch contains only security candidates.
- `blocked_by_rejected` entries must also be dependencies whose decisions are
  `reject`.
- Such work cannot use `take`.
- Included accepted work must use `adapt`,
  `dependency_resolution: adapt_without_dependency`, and non-empty
  verification.
- Queued accepted work needs a concrete implementation plan.

## Archive immutability

Closed JSON under `batches/archive/` cannot be deleted or have original fields
edited. A new archived file must already be `closed`.

## Reclassification

Append a record; never rewrite the entry:

```json
{
  "upstream_sha": "<full-sha>",
  "old_decision": "reject",
  "new_decision": "accept",
  "reason": "Dependency is now approved.",
  "date": "YYYY-MM-DD",
  "tracking_reference": "https://tracker.example/issue/123"
}
```

Existing reclassification history is also immutable.

## Commands and Exit codes

Run the bundled script or the byte-identical vendored copy:

```bash
python3 upstream_intake.py validate --repo PATH [--base-ref REF]
python3 upstream_intake.py discover --repo PATH --upstream-ref REF --format markdown
python3 upstream_intake.py render --repo PATH --batch BATCH.json
python3 upstream_intake.py audit --repo PATH
python3 upstream_intake.py init-project ...        # dry-run
python3 upstream_intake.py init-project ... --apply
```

Exit codes:

- `0`: success.
- `2`: actionable policy, schema, state, or safety failure.
- `3`: Git or host-environment failure.

Discovery does not fetch or mutate refs, index, worktree, state, or batches.
Initialization requires macOS, a clean Git repository for `--apply`, an
existing reviewed SHA, and byte-identical or absent destinations.
