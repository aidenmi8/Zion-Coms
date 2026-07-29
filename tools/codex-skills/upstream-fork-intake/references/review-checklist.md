# Upstream topic review checklist

Use this after discovery and before choosing decisions. Review a coherent
upstream PR or dependency chain, not isolated commit titles.

## Provenance

- Confirm previous, requested, and pinned full SHAs.
- Read every commit, diff, changed test, linked PR, issue, advisory, and release
  note in the topic.
- Record every SHA once. Do not infer provenance from a fork implementation.

## Dependency graph

- Identify prerequisite commits, packages, migrations, schemas, feature flags,
  generated outputs, and later fixups.
- Distinguish behavior dependencies from implementation conveniences.
- If a dependency is rejected, mark every blocked entry. Choose a tested
  `adapt_without_dependency`, queue a concrete plan, defer the decision, or
  reject the dependent work.

## Security fast lane

- Flag authentication, authorization, permissions, secrets, credentials,
  cryptography, Keychain, entitlements, transport, and advisory/CVE changes.
- Put high/critical candidates in a dedicated security batch.
- Review complete dependency/test context before `take`; urgency never removes
  provenance or verification.

## Licensing and attribution

- Verify the upstream and fork SPDX declarations against actual files.
- Review new dependencies, copied assets, notices, headers, generated code, and
  attribution requirements.
- If identifiers differ or compatibility is uncertain, block `take` and
  `adapt` until a written compatibility review exists.

## Compatibility contracts

Check the repository's declared environment variables, deep links, protocols,
package/binary names, bundle identifiers, storage formats, database
migrations, relay/API paths, container names, legacy URLs, aliases, signing,
privacy, branding, design, accessibility, and reduced-motion behavior.

## Product decision

- `accept`: the fork wants the behavior.
- `reject`: the fork intentionally does not want it; write why.
- `defer`: the decision lacks an owner/input; add owner or tracking plus a
  concrete trigger.
- Wanted but too large now is `accept + queued`, not `defer`.

For accepted work choose:

- `take`: substantially apply the reviewed upstream patch and dependency
  context.
- `adapt`: reproduce the behavior with a fork-owned implementation while
  retaining upstream provenance.

## Batch boundary

Default to one local batch PR. Split for:

- high/critical security;
- incompatible licensing or attribution;
- schema/migration sequencing;
- generated changes that cannot be reviewed coherently;
- dependency chains that require an independent decision;
- release/signing/deployment work;
- a change too large for the configured cap.

Do not split merely to produce one PR per upstream commit.

## Evidence

- Add focused regression tests for each adaptation or conflict-sensitive take.
- Run protected brand/identifier/privacy/sidecar contracts.
- Run the configured profile gates, then full local CI.
- Record exact commands, results, skipped infrastructure, and manual device or
  simulator checks.
- Audit queued work, triggered deferrals, pointers, duplicates, omissions, and
  missing evidence before advancing `reviewed_through`.

## Release separation

Local commits, push, PR creation, merge, signing, packaging, TestFlight,
deployment, database migration, server rollout, and app installation are
separate actions. Perform only the actions the user explicitly authorized.
