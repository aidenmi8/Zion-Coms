---
name: upstream-fork-intake
description: Review upstream changes for an iOS or macOS fork, classify each pinned commit as accept, reject, or defer, and prepare a contract-preserving local intake batch. Use for upstream sync reviews, fork maintenance, selective patch intake, rebrands, and Apple app repositories that must not merge upstream blindly.
---

# Upstream Fork Intake

Use this skill to turn an upstream range into an explicit, locally validated
decision ledger. Start read-only. Do not push, merge, release, deploy, install,
or modify product code unless the user separately authorizes that action.

## Initial workflow

1. Read the repository's `AGENTS.md` and local policy.
2. Confirm Git status, worktrees, remotes, branches, and immutable SHAs.
3. Validate `.upstream-intake/config.json`.
4. Discover the configured range without changing repository state.
5. Review every topic and record every SHA once.
6. Validate the local batch before proposing publication.

Run the deterministic tool from `scripts/upstream_intake.py`. The complete
ledger, review, and Apple-platform procedures live in:

- `references/ledger-schema.md`
- `references/review-checklist.md`
- `references/apple-platform-checks.md`

Project activation uses the templates under `assets/project-template/`, but
initialization is dry-run by default.
