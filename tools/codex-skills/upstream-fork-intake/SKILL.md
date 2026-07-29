---
name: upstream-fork-intake
description: Use when maintaining an iOS or macOS fork, reviewing upstream commits or PRs, selectively taking or adapting patches, preserving a rebrand or compatibility contract, or replacing blind upstream merges.
---

# Upstream Fork Intake

## Core rule

Treat upstream as evidence, not authority. Account for every pinned commit,
preserve the fork contract, and keep discovery, implementation, publication,
and delivery as separate authorizations.

## Preflight

Read `AGENTS.md` and repository policy first. Run:

```bash
git status --short --branch
git worktree list
git remote -v
```

Confirm a clean isolated worktree, configured upstream/fork refs, immutable full
SHAs, and the repository-specific license. Skill-driven Git and initialization
require a macOS host; pure `validate` may run in hosted CI.

## Workflow

1. Read `references/ledger-schema.md` before editing configuration, state, or
   batches. Validate the repository.
2. Perform read-only discovery. Fetch only when repository policy authorizes
   it; never switch, merge, cherry-pick, rebase, or update durable state during
   discovery.
3. Read `references/review-checklist.md` before classifying an upstream topic.
   Record every SHA exactly once:

   | Product decision | Integration | Delivery |
   |---|---|---|
   | `accept` | `take` or `adapt` | `included` or `queued` |
   | `reject` | null | `not_applicable` |
   | `defer` | null | `not_applicable` plus revisit trigger |

   Use `accept + queued` for a wanted large feature tracked for later. Put
   high/critical candidates in a dedicated security batch. Work blocked by a
   rejected dependency cannot use `take`; included work must use a verified
   `adapt` without that dependency.
4. Build one local batch PR by default. Split only at a security, licensing,
   migration, generated-code, dependency, or other hard boundary. Product code
   changes still require the user's authorization.
5. Read `references/apple-platform-checks.md` before running platform-specific
   commands. Run configured focused checks, then the repository's full local
   gates. Render and audit the ledger.
6. Report exact pins, decisions, adaptations, evidence, and remaining queued
   work. Do not automatically push, open a PR, merge, deploy, release, install,
   or activate this skill in another project.

Use `scripts/upstream_intake.py --help` for deterministic commands.
`assets/project-template/` is fail-closed; render it only with `init-project`,
which is dry-run unless `--apply` is explicit.

## Common mistakes

| Mistake | Correct action |
|---|---|
| Blind merge because conflicts are few | Review and classify the pinned range |
| Reimplement without provenance | Keep upstream SHA and method in the ledger |
| Treat `defer` as implementation backlog | Use `accept + queued` when the decision is yes |
| Copy one license policy to every fork | Validate each repository's declared files |
