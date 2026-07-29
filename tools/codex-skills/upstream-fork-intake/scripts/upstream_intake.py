#!/usr/bin/env python3
"""Deterministic policy tooling for selective upstream intake."""

from __future__ import annotations

import argparse
import json
import platform
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


SUPPORTED_TARGET_PLATFORMS = frozenset({"ios", "macos"})
SUPPORTED_PROJECT_PROFILES = frozenset(
    {"native-xcode", "flutter-ios", "tauri-macos", "swiftpm-macos"}
)
MAX_COMMITS = 25
MAX_CHANGED_FILES = 250
REQUIRED_MARKER = "__" + "REQUIRED" + "__"
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
VALID_BATCH_STATUSES = frozenset(
    {"discovered", "reviewing", "implementing", "in_pr", "reviewed", "closed"}
)
VALID_RISKS = frozenset({"low", "medium", "high", "critical"})


class IntakeError(Exception):
    """A deterministic policy or state validation failure."""


class IntakeEnvironmentError(Exception):
    """A Git or host environment failure distinct from policy validation."""


def load_json(path: Path) -> dict[str, object]:
    """Load a JSON object and translate parse/type failures into policy errors."""
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise IntakeError(f"cannot read JSON object {path}: {error}") from error
    if not isinstance(value, dict):
        raise IntakeError(f"{path} must contain a JSON object")
    return value


def detect_license(spdx: str, text: str) -> bool:
    """Return whether a license body matches a supported SPDX declaration."""
    signatures = {
        "Apache-2.0": (
            "Apache License",
            "Version 2.0, January 2004",
            "TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION",
        ),
        "MIT": (
            "MIT License",
            "Permission is hereby granted, free of charge",
            'THE SOFTWARE IS PROVIDED "AS IS"',
        ),
    }
    required = signatures.get(spdx)
    return required is not None and all(fragment in text for fragment in required)


def require_macos() -> None:
    """Fail before skill-driven Git operations on unsupported hosts."""
    if platform.system() != "Darwin":
        raise IntakeError(
            "upstream-fork-intake Git operations require a macOS Codex host"
        )


def _mapping(value: object, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise IntakeError(f"{field} must be an object")
    return value


def _non_empty_string(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise IntakeError(f"{field} must be a non-empty string")
    return value.strip()


def _string_list(
    value: object, field: str, *, require_non_empty: bool
) -> list[str]:
    if not isinstance(value, list) or (
        require_non_empty and not value
    ):
        suffix = "non-empty " if require_non_empty else ""
        raise IntakeError(f"{field} must be a {suffix}array")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        raise IntakeError(f"{field} must contain only non-empty strings")
    return [item.strip() for item in value]


def _has_required_marker(value: object) -> bool:
    if isinstance(value, str):
        return REQUIRED_MARKER in value
    if isinstance(value, list):
        return any(_has_required_marker(item) for item in value)
    if isinstance(value, dict):
        return any(
            _has_required_marker(key) or _has_required_marker(item)
            for key, item in value.items()
        )
    return False


def _resolve_policy_file(repo: Path, relative: str, field: str) -> Path:
    path = (repo / relative).resolve()
    root = repo.resolve()
    try:
        path.relative_to(root)
    except ValueError as error:
        raise IntakeError(f"{field} must stay inside the repository") from error
    if not path.is_file() or path.stat().st_size == 0:
        raise IntakeError(f"{field} does not name an existing non-empty file")
    return path


def validate_config(repo: Path, config: dict[str, object]) -> None:
    """Validate a repository-specific upstream intake policy."""
    if _has_required_marker(config):
        raise IntakeError(
            f"configuration contains unresolved {REQUIRED_MARKER} marker"
        )
    if config.get("schema_version") != 1:
        raise IntakeError("schema_version must be 1")

    upstream = _mapping(config.get("upstream"), "upstream")
    for field in ("repository", "remote", "branch"):
        _non_empty_string(upstream.get(field), f"upstream.{field}")

    fork = _mapping(config.get("fork"), "fork")
    for field in ("repository", "main_branch"):
        _non_empty_string(fork.get(field), f"fork.{field}")

    execution = _mapping(config.get("execution"), "execution")
    if execution.get("host_os") != "macos":
        raise IntakeError('execution.host_os must be "macos"')
    target_platforms = _string_list(
        execution.get("target_platforms"),
        "execution.target_platforms",
        require_non_empty=True,
    )
    unsupported_targets = sorted(
        set(target_platforms) - SUPPORTED_TARGET_PLATFORMS
    )
    if unsupported_targets:
        raise IntakeError(
            f"unsupported target platform: {', '.join(unsupported_targets)}"
        )
    profiles = _string_list(
        execution.get("project_profiles"),
        "execution.project_profiles",
        require_non_empty=True,
    )
    unsupported_profiles = sorted(set(profiles) - SUPPORTED_PROJECT_PROFILES)
    if unsupported_profiles:
        raise IntakeError(
            f"unsupported project profile: {', '.join(unsupported_profiles)}"
        )

    licensing = _mapping(config.get("licensing"), "licensing")
    upstream_spdx = _non_empty_string(
        licensing.get("upstream_spdx"), "licensing.upstream_spdx"
    )
    fork_spdx = _non_empty_string(
        licensing.get("fork_spdx"), "licensing.fork_spdx"
    )
    if upstream_spdx != fork_spdx:
        _non_empty_string(
            licensing.get("compatibility_review"),
            "licensing.compatibility_review",
        )
    license_files = _string_list(
        licensing.get("license_files"),
        "licensing.license_files",
        require_non_empty=True,
    )
    notice_files = _string_list(
        licensing.get("notice_files"),
        "licensing.notice_files",
        require_non_empty=False,
    )
    for index, relative in enumerate(license_files):
        path = _resolve_policy_file(
            repo, relative, f"licensing.license_files[{index}]"
        )
        if not detect_license(fork_spdx, path.read_text(encoding="utf-8")):
            raise IntakeError(
                f"{relative} does not match declared SPDX {fork_spdx}"
            )
    for index, relative in enumerate(notice_files):
        _resolve_policy_file(
            repo, relative, f"licensing.notice_files[{index}]"
        )

    limits = _mapping(config.get("batch_limits"), "batch_limits")
    for field, maximum in (
        ("max_commits", MAX_COMMITS),
        ("max_changed_files", MAX_CHANGED_FILES),
    ):
        value = limits.get(field)
        if (
            isinstance(value, bool)
            or not isinstance(value, int)
            or value <= 0
            or value > maximum
        ):
            raise IntakeError(
                f"batch_limits.{field} must be between 1 and {maximum}"
            )

    _string_list(
        config.get("protected_contracts"),
        "protected_contracts",
        require_non_empty=True,
    )
    checks = _mapping(config.get("checks"), "checks")
    _string_list(
        checks.get("always"), "checks.always", require_non_empty=True
    )
    commands = _mapping(config.get("commands"), "commands")
    _string_list(
        commands.get("authorized"),
        "commands.authorized",
        require_non_empty=True,
    )
    _string_list(
        commands.get("prohibited"),
        "commands.prohibited",
        require_non_empty=True,
    )


def _full_sha(value: object, field: str) -> str:
    if not isinstance(value, str) or FULL_SHA.fullmatch(value) is None:
        raise IntakeError(f"{field} must be a full 40-character lowercase SHA")
    return value


def _object_list(value: object, field: str) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise IntakeError(f"{field} must be an array")
    if any(not isinstance(item, dict) for item in value):
        raise IntakeError(f"{field} must contain only objects")
    return value


def _tracking_reference(tracking: dict[str, Any]) -> bool:
    for field in ("issue", "pull_request", "local_backlog", "implementation_plan"):
        value = tracking.get(field)
        if isinstance(value, str) and value.strip():
            return True
    return False


def _validate_entry_shape(entry: dict[str, Any], index: int) -> str:
    prefix = f"entries[{index}]"
    sha = _full_sha(entry.get("upstream_sha"), f"{prefix}.upstream_sha")
    _non_empty_string(entry.get("topic_id"), f"{prefix}.topic_id")
    _non_empty_string(entry.get("title"), f"{prefix}.title")
    _string_list(entry.get("areas"), f"{prefix}.areas", require_non_empty=True)
    if entry.get("risk") not in VALID_RISKS:
        raise IntakeError(f"{prefix}.risk must be low, medium, high, or critical")
    _non_empty_string(entry.get("rationale"), f"{prefix}.rationale")
    _string_list(
        entry.get("dependencies"),
        f"{prefix}.dependencies",
        require_non_empty=False,
    )
    _string_list(
        entry.get("blocked_by_rejected"),
        f"{prefix}.blocked_by_rejected",
        require_non_empty=False,
    )
    _string_list(
        entry.get("security_reasons"),
        f"{prefix}.security_reasons",
        require_non_empty=False,
    )
    if not isinstance(entry.get("security_candidate"), bool):
        raise IntakeError(f"{prefix}.security_candidate must be boolean")
    if entry["security_candidate"] and not entry["security_reasons"]:
        raise IntakeError(
            f"{prefix}.security_reasons must explain a security candidate"
        )
    _mapping(entry.get("tracking"), f"{prefix}.tracking")
    _string_list(
        entry.get("verification"),
        f"{prefix}.verification",
        require_non_empty=False,
    )
    return sha


def _validate_decision(entry: dict[str, Any], index: int) -> None:
    prefix = f"entries[{index}]"
    decision = entry.get("decision")
    integration_method = entry.get("integration_method")
    delivery = entry.get("delivery")
    tracking = _mapping(entry.get("tracking"), f"{prefix}.tracking")

    if decision == "accept":
        if integration_method not in {"take", "adapt"}:
            raise IntakeError(
                f"{prefix}.integration_method must be take or adapt for accept"
            )
        if delivery not in {"included", "queued"}:
            raise IntakeError(
                f"{prefix}.delivery must be included or queued for accept"
            )
        if delivery == "queued" and not _tracking_reference(tracking):
            raise IntakeError(
                f"{prefix} queued acceptance requires durable tracking"
            )
        if entry.get("revisit") is not None:
            raise IntakeError(f"{prefix}.revisit must be null for accept")
        return

    if decision == "reject":
        if integration_method is not None or delivery != "not_applicable":
            raise IntakeError(
                f"{prefix} rejected entry cannot be integrated or delivered"
            )
        if entry.get("revisit") is not None:
            raise IntakeError(f"{prefix}.revisit must be null for reject")
        return

    if decision == "defer":
        if integration_method is not None or delivery != "not_applicable":
            raise IntakeError(
                f"{prefix} deferred entry cannot be integrated or delivered"
            )
        revisit = entry.get("revisit")
        if not isinstance(revisit, dict):
            raise IntakeError(
                f"{prefix} deferred entry requires a concrete revisit record"
            )
        _non_empty_string(revisit.get("trigger"), f"{prefix}.revisit.trigger")
        owner = revisit.get("owner")
        revisit_tracking = revisit.get("tracking")
        has_owner = isinstance(owner, str) and bool(owner.strip())
        has_revisit_tracking = isinstance(revisit_tracking, str) and bool(
            revisit_tracking.strip()
        )
        if not (has_owner or has_revisit_tracking or _tracking_reference(tracking)):
            raise IntakeError(
                f"{prefix} deferred entry requires an owner or tracking reference"
            )
        return

    raise IntakeError(f"{prefix}.decision must be accept, reject, or defer")


def validate_batch(batch: dict[str, object]) -> None:
    """Validate topic coverage and every product/integration decision."""
    if _has_required_marker(batch):
        raise IntakeError(f"batch contains unresolved {REQUIRED_MARKER} marker")
    if batch.get("schema_version") != 1:
        raise IntakeError("batch schema_version must be 1")
    _non_empty_string(batch.get("batch_id"), "batch_id")
    _full_sha(batch.get("previous_reviewed_sha"), "previous_reviewed_sha")
    _full_sha(batch.get("pinned_upstream_sha"), "pinned_upstream_sha")
    kind = batch.get("kind")
    if kind not in {"normal", "security"}:
        raise IntakeError("batch kind must be normal or security")
    if batch.get("status") not in VALID_BATCH_STATUSES:
        raise IntakeError("batch status is invalid")

    topics = _object_list(batch.get("topics"), "topics")
    entries = _object_list(batch.get("entries"), "entries")
    if not topics or not entries:
        raise IntakeError("batch topics and entries must be non-empty")
    if not isinstance(batch.get("reclassifications"), list):
        raise IntakeError("reclassifications must be an array")

    entry_by_sha: dict[str, dict[str, Any]] = {}
    for index, entry in enumerate(entries):
        sha = _validate_entry_shape(entry, index)
        if sha in entry_by_sha:
            raise IntakeError(f"duplicate upstream SHA in entries: {sha}")
        entry_by_sha[sha] = entry
        _validate_decision(entry, index)

    topic_by_id: dict[str, dict[str, Any]] = {}
    topic_occurrences: dict[str, int] = {}
    topic_for_sha: dict[str, str] = {}
    for index, topic in enumerate(topics):
        prefix = f"topics[{index}]"
        topic_id = _non_empty_string(topic.get("topic_id"), f"{prefix}.topic_id")
        if topic_id in topic_by_id:
            raise IntakeError(f"duplicate topic_id: {topic_id}")
        topic_by_id[topic_id] = topic
        _non_empty_string(topic.get("title"), f"{prefix}.title")
        shas = _string_list(
            topic.get("entry_shas"),
            f"{prefix}.entry_shas",
            require_non_empty=True,
        )
        for sha in shas:
            _full_sha(sha, f"{prefix}.entry_shas")
            topic_occurrences[sha] = topic_occurrences.get(sha, 0) + 1
            topic_for_sha.setdefault(sha, topic_id)

    if set(topic_occurrences) != set(entry_by_sha) or any(
        count != 1 for count in topic_occurrences.values()
    ):
        raise IntakeError("every upstream SHA must belong to exactly one topic")
    for sha, entry in entry_by_sha.items():
        if entry["topic_id"] != topic_for_sha[sha]:
            raise IntakeError(
                f"entry {sha} must name the exactly one topic that contains it"
            )

    for index, entry in enumerate(entries):
        prefix = f"entries[{index}]"
        dependencies = entry["dependencies"]
        blocked = entry["blocked_by_rejected"]
        if any(sha not in dependencies for sha in blocked):
            raise IntakeError(
                f"{prefix}.blocked_by_rejected must be listed in dependencies"
            )
        for sha in blocked:
            dependency = entry_by_sha.get(sha)
            if dependency is None or dependency.get("decision") != "reject":
                raise IntakeError(
                    f"{prefix} rejected dependency {sha} is not a rejected entry"
                )
        if blocked and entry.get("integration_method") == "take":
            raise IntakeError(
                f"{prefix} with a rejected dependency cannot use take"
            )
        if (
            blocked
            and entry.get("decision") == "accept"
            and entry.get("delivery") == "included"
        ):
            if entry.get("integration_method") != "adapt":
                raise IntakeError(
                    f"{prefix} must adapt around a rejected dependency"
                )
            if entry.get("dependency_resolution") != "adapt_without_dependency":
                raise IntakeError(
                    f"{prefix}.dependency_resolution must be "
                    "adapt_without_dependency"
                )
            if not entry.get("verification"):
                raise IntakeError(
                    f"{prefix}.verification is required for dependency adaptation"
                )
        if (
            blocked
            and entry.get("decision") == "accept"
            and entry.get("delivery") == "queued"
        ):
            tracking = _mapping(entry.get("tracking"), f"{prefix}.tracking")
            plan = tracking.get("implementation_plan")
            if not isinstance(plan, str) or not plan.strip():
                raise IntakeError(
                    f"{prefix} queued rejected-dependency work requires "
                    "tracking.implementation_plan"
                )

        is_security = entry["security_candidate"]
        if (
            kind == "normal"
            and is_security
            and entry.get("risk") in {"high", "critical"}
        ):
            raise IntakeError(
                f"{prefix} high-risk security candidate requires a security batch"
            )
        if kind == "security" and not is_security:
            raise IntakeError("security batches may contain only security candidates")


def run_git(repo: Path, *args: str) -> str:
    """Run read-only Git plumbing and return trimmed stdout."""
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise IntakeEnvironmentError(f"cannot execute git: {error}") from error
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "unknown error"
        raise IntakeEnvironmentError(
            f"git {' '.join(args)} failed ({result.returncode}): {detail}"
        )
    return result.stdout.strip()


def _is_ancestor(repo: Path, ancestor: str, descendant: str) -> bool:
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(repo),
                "merge-base",
                "--is-ancestor",
                ancestor,
                descendant,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise IntakeEnvironmentError(f"cannot execute git: {error}") from error
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    detail = result.stderr.strip() or result.stdout.strip() or "unknown error"
    raise IntakeEnvironmentError(f"cannot verify Git ancestry: {detail}")


def validate_state(state: dict[str, object]) -> None:
    """Validate durable repository pointers."""
    if _has_required_marker(state):
        raise IntakeError(f"state contains unresolved {REQUIRED_MARKER} marker")
    if state.get("schema_version") != 1:
        raise IntakeError("state schema_version must be 1")
    _full_sha(state.get("reviewed_through"), "state.reviewed_through")
    _full_sha(state.get("last_discovered"), "state.last_discovered")
    batches = _string_list(
        state.get("open_batches"),
        "state.open_batches",
        require_non_empty=False,
    )
    if len(batches) != len(set(batches)):
        raise IntakeError("state.open_batches must not contain duplicates")


def expected_range(repo: Path, previous: str, pinned: str) -> list[str]:
    """Return the authoritative oldest-first topological commit range."""
    _full_sha(previous, "previous_reviewed_sha")
    _full_sha(pinned, "pinned_upstream_sha")
    if not _is_ancestor(repo, previous, pinned):
        raise IntakeError(f"{previous} is not an ancestor of {pinned}")
    output = run_git(
        repo,
        "rev-list",
        "--reverse",
        "--topo-order",
        f"{previous}..{pinned}",
    )
    return output.splitlines() if output else []


def classify_topic(subject: str, sha: str) -> str:
    """Return a stable upstream-PR or SHA-derived topic identifier."""
    match = re.search(r"\(#(\d+)\)\s*$", subject)
    if match is not None:
        return f"pr-{match.group(1)}"
    _full_sha(sha, "discovery commit SHA")
    return f"commit-{sha[:12]}"


def _upstream_pr(subject: str) -> int | None:
    match = re.search(r"\(#(\d+)\)\s*$", subject)
    return int(match.group(1)) if match is not None else None


def security_reasons(subject: str, files: list[str]) -> list[str]:
    """Return deterministic title/path reasons that require security review."""
    reasons: list[str] = []
    lowered_subject = subject.casefold()
    for keyword in (
        "cve-",
        "security",
        "vulnerability",
        "authentication",
        "authorization",
        "permission",
        "crypto",
        "secret",
        "credential",
    ):
        if keyword in lowered_subject:
            reasons.append(f"title keyword: {keyword}")
    path_markers = {
        "auth",
        "authentication",
        "authorization",
        "security",
        "permission",
        "permissions",
        "crypto",
        "cryptography",
        "secret",
        "credential",
        "credentials",
        "keychain",
        "entitlement",
        "entitlements",
    }
    for path in files:
        path_tokens = set(re.split(r"[^a-z0-9]+", path.casefold()))
        if path_tokens & path_markers:
            reasons.append(f"sensitive path: {path}")
    return reasons


def _commit_metadata(repo: Path, sha: str) -> dict[str, object]:
    header = run_git(repo, "show", "-s", "--format=%s%x00%aI", sha)
    try:
        subject, author_date = header.split("\0", 1)
    except ValueError as error:
        raise IntakeEnvironmentError(
            f"cannot parse metadata for commit {sha}"
        ) from error

    parent_line = run_git(repo, "rev-list", "--parents", "-n", "1", sha)
    parent_parts = parent_line.split()
    if len(parent_parts) > 1:
        numstat = run_git(
            repo,
            "diff",
            "--numstat",
            "--find-renames",
            parent_parts[1],
            sha,
        )
    else:
        numstat = run_git(
            repo,
            "diff-tree",
            "--root",
            "--no-commit-id",
            "--numstat",
            "-r",
            "--find-renames",
            sha,
        )

    files: set[str] = set()
    insertions = 0
    deletions = 0
    for line in numstat.splitlines():
        parts = line.split("\t", 2)
        if len(parts) != 3:
            continue
        added, removed, path = parts
        files.add(path)
        if added.isdigit():
            insertions += int(added)
        if removed.isdigit():
            deletions += int(removed)
    sorted_files = sorted(files)
    topic_id = classify_topic(subject, sha)
    return {
        "author_date": author_date,
        "files": sorted_files,
        "security_reasons": security_reasons(subject, sorted_files),
        "sha": sha,
        "statistics": {
            "deletions": deletions,
            "files": len(sorted_files),
            "insertions": insertions,
        },
        "subject": subject,
        "topic_id": topic_id,
        "upstream_pr": _upstream_pr(subject),
    }


def discover(repo: Path, upstream_ref: str) -> dict[str, object]:
    """Inspect a capped upstream range without mutating repository state."""
    root = repo / ".upstream-intake"
    config = load_json(root / "config.json")
    state = load_json(root / "state.json")
    validate_config(repo, config)
    validate_state(state)

    reviewed = str(state["reviewed_through"])
    resolved_head = run_git(
        repo, "rev-parse", "--verify", f"{upstream_ref}^{{commit}}"
    )
    _full_sha(resolved_head, "resolved upstream ref")
    if not _is_ancestor(repo, reviewed, resolved_head):
        raise IntakeError(
            f"reviewed_through {reviewed} is not an ancestor of {resolved_head}"
        )

    range_output = run_git(
        repo,
        "rev-list",
        "--reverse",
        "--topo-order",
        f"{reviewed}..{resolved_head}",
    )
    candidate_shas = range_output.splitlines() if range_output else []
    limits = _mapping(config.get("batch_limits"), "batch_limits")
    max_commits = int(limits["max_commits"])
    max_changed_files = int(limits["max_changed_files"])

    selected: list[dict[str, object]] = []
    changed_files: set[str] = set()
    cap_reason: str | None = None
    dedicated_batch_blocker: dict[str, object] | None = None
    for sha in candidate_shas:
        metadata = _commit_metadata(repo, sha)
        commit_files = set(metadata["files"])
        if not selected and len(commit_files) > max_changed_files:
            selected.append(metadata)
            changed_files.update(commit_files)
            cap_reason = "single_commit_changed_file_limit"
            dedicated_batch_blocker = {
                "changed_files": len(commit_files),
                "limit": max_changed_files,
                "reason": "single_commit_exceeds_changed_file_limit",
                "sha": sha,
            }
            break
        if len(selected) >= max_commits:
            cap_reason = "commit_limit"
            break
        if len(changed_files | commit_files) > max_changed_files:
            cap_reason = "changed_file_limit"
            break
        selected.append(metadata)
        changed_files.update(commit_files)

    remaining = len(candidate_shas) - len(selected)
    if remaining and cap_reason is None:
        cap_reason = "commit_limit"
    pinned = str(selected[-1]["sha"]) if selected else reviewed

    topics_by_id: dict[str, dict[str, object]] = {}
    for commit in selected:
        topic_id = str(commit["topic_id"])
        topic = topics_by_id.get(topic_id)
        if topic is None:
            title = re.sub(r"\s*\(#\d+\)\s*$", "", str(commit["subject"]))
            topic = {
                "entry_shas": [],
                "title": title,
                "topic_id": topic_id,
                "upstream_pr": commit["upstream_pr"],
            }
            topics_by_id[topic_id] = topic
        entry_shas = topic["entry_shas"]
        assert isinstance(entry_shas, list)
        entry_shas.append(commit["sha"])

    return {
        "cap": {
            "max_changed_files": max_changed_files,
            "max_commits": max_commits,
            "reached": cap_reason is not None,
            "reason": cap_reason,
        },
        "changed_file_count": len(changed_files),
        "commit_count": len(selected),
        "commits": selected,
        "dedicated_batch_blocker": dedicated_batch_blocker,
        "pinned_upstream_sha": pinned,
        "remaining_commit_count": remaining,
        "requested_upstream_sha": resolved_head,
        "reviewed_through": reviewed,
        "schema_version": 1,
        "topics": list(topics_by_id.values()),
        "upstream_ref": upstream_ref,
    }


def render_markdown(report: dict[str, object]) -> str:
    """Render a deterministic human-readable discovery report."""
    lines = [
        "# Upstream discovery",
        "",
        (
            f"- Range: `{report['reviewed_through']}.."
            f"{report['pinned_upstream_sha']}`"
        ),
        f"- Requested head: `{report['requested_upstream_sha']}`",
        f"- Commits: **{report['commit_count']}**",
        f"- Changed files: **{report['changed_file_count']}**",
        f"- Remaining commits: **{report['remaining_commit_count']}**",
    ]
    cap = _mapping(report.get("cap"), "report.cap")
    if cap.get("reason") is not None:
        lines.append(f"- Cap result: `{cap['reason']}`")
    blocker = report.get("dedicated_batch_blocker")
    if isinstance(blocker, dict):
        lines.extend(
            [
                "",
                "## Dedicated batch required",
                "",
                (
                    f"`{blocker['sha']}` changes {blocker['changed_files']} files "
                    f"against a limit of {blocker['limit']}."
                ),
            ]
        )

    topics = report.get("topics")
    if isinstance(topics, list) and topics:
        lines.extend(["", "## Topics", ""])
        for topic in topics:
            assert isinstance(topic, dict)
            pr = (
                f" upstream PR #{topic['upstream_pr']}"
                if topic.get("upstream_pr") is not None
                else ""
            )
            lines.append(
                f"- `{topic['topic_id']}`: {topic['title']} "
                f"({len(topic['entry_shas'])} commit(s)){pr}"
            )

    commits = report.get("commits")
    if isinstance(commits, list) and commits:
        lines.extend(["", "## Commits", ""])
        for commit in commits:
            assert isinstance(commit, dict)
            reasons = commit.get("security_reasons")
            security = (
                f" - security review: {', '.join(reasons)}"
                if isinstance(reasons, list) and reasons
                else ""
            )
            lines.append(
                f"- `{commit['sha']}` {commit['subject']} "
                f"({commit['statistics']['files']} file(s)){security}"
            )
    return "\n".join(lines) + "\n"


def _render_batch_markdown(batch: dict[str, object]) -> str:
    validate_batch(batch)
    entries = _object_list(batch.get("entries"), "entries")
    decisions = {"accept": 0, "defer": 0, "reject": 0}
    for entry in entries:
        decisions[str(entry["decision"])] += 1
    lines = [
        f"# Upstream intake batch {batch['batch_id']}",
        "",
        (
            f"- Range: `{batch['previous_reviewed_sha']}.."
            f"{batch['pinned_upstream_sha']}`"
        ),
        f"- Accept: **{decisions['accept']}**",
        f"- Reject: **{decisions['reject']}**",
        f"- Defer: **{decisions['defer']}**",
        "",
        "## Entries",
        "",
    ]
    for entry in entries:
        lines.append(
            f"- `{entry['upstream_sha']}` `{entry['decision']}` "
            f"{entry['title']}"
        )
    return "\n".join(lines) + "\n"


def _validate_reclassification(
    record: object, batch: dict[str, object], index: int
) -> None:
    if not isinstance(record, dict):
        raise IntakeError(f"reclassifications[{index}] must be an object")
    sha = _full_sha(
        record.get("upstream_sha"),
        f"reclassifications[{index}].upstream_sha",
    )
    entries = _object_list(batch.get("entries"), "entries")
    original = next(
        (entry for entry in entries if entry.get("upstream_sha") == sha), None
    )
    if original is None:
        raise IntakeError(
            f"reclassifications[{index}] references a SHA outside the batch"
        )
    old_decision = record.get("old_decision")
    new_decision = record.get("new_decision")
    if old_decision not in {"accept", "reject", "defer"}:
        raise IntakeError(
            f"reclassifications[{index}].old_decision is invalid"
        )
    if new_decision not in {"accept", "reject", "defer"}:
        raise IntakeError(
            f"reclassifications[{index}].new_decision is invalid"
        )
    if old_decision != original.get("decision"):
        raise IntakeError(
            f"reclassifications[{index}].old_decision must match original history"
        )
    if new_decision == old_decision:
        raise IntakeError(
            f"reclassifications[{index}] must change the product decision"
        )
    for field in ("reason", "date", "tracking_reference"):
        _non_empty_string(
            record.get(field), f"reclassifications[{index}].{field}"
        )


def validate_archive_changes(repo: Path, base_ref: str) -> None:
    """Enforce append-only reclassification for already archived batches."""
    base_paths_output = run_git(
        repo,
        "ls-tree",
        "-r",
        "--name-only",
        base_ref,
        "--",
        ".upstream-intake/batches/archive",
    )
    base_paths = {
        path
        for path in base_paths_output.splitlines()
        if path.endswith(".json")
    }
    current_root = repo / ".upstream-intake/batches/archive"
    current_paths = {
        path.relative_to(repo).as_posix()
        for path in current_root.glob("*.json")
    }
    deleted = sorted(base_paths - current_paths)
    if deleted:
        raise IntakeError(f"archived batch deleted: {deleted[0]}")

    for relative in sorted(base_paths):
        base_text = run_git(repo, "show", f"{base_ref}:{relative}")
        try:
            base_batch = json.loads(base_text)
        except json.JSONDecodeError as error:
            raise IntakeError(
                f"archived base batch is invalid JSON: {relative}"
            ) from error
        if not isinstance(base_batch, dict):
            raise IntakeError(f"archived base batch must be an object: {relative}")
        current_batch = load_json(repo / relative)
        base_records = base_batch.get("reclassifications", [])
        current_records = current_batch.get("reclassifications", [])
        if not isinstance(base_records, list) or not isinstance(
            current_records, list
        ):
            raise IntakeError(f"archive reclassifications must be arrays: {relative}")
        base_history = {
            key: value
            for key, value in base_batch.items()
            if key != "reclassifications"
        }
        current_history = {
            key: value
            for key, value in current_batch.items()
            if key != "reclassifications"
        }
        if base_history != current_history:
            raise IntakeError(f"archived batch history is immutable: {relative}")
        if current_records[: len(base_records)] != base_records:
            raise IntakeError(
                f"archived reclassification history is immutable: {relative}"
            )
        for index, record in enumerate(
            current_records[len(base_records) :], start=len(base_records)
        ):
            _validate_reclassification(record, base_batch, index)

    for relative in sorted(current_paths - base_paths):
        batch = load_json(repo / relative)
        validate_batch(batch)
        if batch.get("status") != "closed":
            raise IntakeError(f"new archived batch must be closed: {relative}")


def _git_object_exists(repo: Path, sha: str) -> bool:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), "cat-file", "-e", f"{sha}^{{commit}}"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise IntakeEnvironmentError(f"cannot execute git: {error}") from error
    return result.returncode == 0


def audit_repository(repo: Path) -> dict[str, object]:
    """Return actionable ledger, pointer, and evidence gaps without mutation."""
    root = repo / ".upstream-intake"
    state = load_json(root / "state.json")
    open_paths, archive_paths = _batch_paths(repo)
    queued_acceptances: list[dict[str, object]] = []
    triggered_deferrals: list[dict[str, object]] = []
    unreachable_pointers: list[dict[str, object]] = []
    missing_evidence: list[dict[str, object]] = []
    omitted_shas: set[str] = set()
    unexpected_shas: set[str] = set()
    policy_errors: list[dict[str, str]] = []
    occurrences: dict[str, int] = {}

    for field in ("reviewed_through", "last_discovered"):
        sha = state.get(field)
        if (
            not isinstance(sha, str)
            or FULL_SHA.fullmatch(sha) is None
            or not _git_object_exists(repo, sha)
        ):
            unreachable_pointers.append({"field": f"state.{field}", "sha": sha})

    for path in [*open_paths, *archive_paths]:
        batch = load_json(path)
        batch_id = str(batch.get("batch_id", path.stem))
        try:
            validate_batch(batch)
        except IntakeError as error:
            policy_errors.append({"batch_id": batch_id, "error": str(error)})
        entries_value = batch.get("entries")
        entries = entries_value if isinstance(entries_value, list) else []
        entry_shas: list[str] = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            sha = entry.get("upstream_sha")
            if not isinstance(sha, str):
                continue
            entry_shas.append(sha)
            occurrences[sha] = occurrences.get(sha, 0) + 1
            if (
                entry.get("decision") == "accept"
                and entry.get("delivery") == "queued"
            ):
                queued_acceptances.append(
                    {
                        "batch_id": batch_id,
                        "tracking": entry.get("tracking"),
                        "upstream_sha": sha,
                    }
                )
            revisit = entry.get("revisit")
            if (
                entry.get("decision") == "defer"
                and isinstance(revisit, dict)
                and revisit.get("triggered") is True
            ):
                triggered_deferrals.append(
                    {
                        "batch_id": batch_id,
                        "revisit": revisit,
                        "upstream_sha": sha,
                    }
                )
            tracking = entry.get("tracking")
            fork_commits = (
                tracking.get("fork_commits")
                if isinstance(tracking, dict)
                else None
            )
            if (
                batch.get("status") in {"in_pr", "reviewed", "closed"}
                and entry.get("decision") == "accept"
                and entry.get("delivery") == "included"
                and not entry.get("verification")
                and not fork_commits
            ):
                missing_evidence.append(
                    {
                        "batch_id": batch_id,
                        "reason": "included accepted work lacks verification evidence",
                        "upstream_sha": sha,
                    }
                )

        previous = batch.get("previous_reviewed_sha")
        pinned = batch.get("pinned_upstream_sha")
        for field, sha in (
            ("previous_reviewed_sha", previous),
            ("pinned_upstream_sha", pinned),
        ):
            if (
                not isinstance(sha, str)
                or FULL_SHA.fullmatch(sha) is None
                or not _git_object_exists(repo, sha)
            ):
                unreachable_pointers.append(
                    {"field": f"{batch_id}.{field}", "sha": sha}
                )
        if (
            isinstance(previous, str)
            and isinstance(pinned, str)
            and FULL_SHA.fullmatch(previous) is not None
            and FULL_SHA.fullmatch(pinned) is not None
            and _git_object_exists(repo, previous)
            and _git_object_exists(repo, pinned)
        ):
            try:
                expected = expected_range(repo, previous, pinned)
            except (IntakeError, IntakeEnvironmentError) as error:
                policy_errors.append({"batch_id": batch_id, "error": str(error)})
            else:
                omitted_shas.update(set(expected) - set(entry_shas))
                unexpected_shas.update(set(entry_shas) - set(expected))

    duplicate_shas = sorted(
        sha for sha, count in occurrences.items() if count > 1
    )
    report = {
        "duplicate_shas": duplicate_shas,
        "missing_evidence": missing_evidence,
        "ok": not any(
            (
                triggered_deferrals,
                unreachable_pointers,
                missing_evidence,
                duplicate_shas,
                omitted_shas,
                unexpected_shas,
                policy_errors,
            )
        ),
        "omitted_shas": sorted(omitted_shas),
        "policy_errors": policy_errors,
        "queued_acceptances": queued_acceptances,
        "triggered_deferrals": triggered_deferrals,
        "unexpected_shas": sorted(unexpected_shas),
        "unreachable_pointers": unreachable_pointers,
    }
    return report


def _template_root() -> Path:
    return Path(__file__).resolve().parent.parent / "assets/project-template"


def _render_project_files(
    repo: Path, settings: dict[str, object]
) -> dict[str, bytes]:
    reviewed_sha = _full_sha(settings.get("reviewed_sha"), "reviewed_sha")
    if not _git_object_exists(repo, reviewed_sha):
        raise IntakeError("reviewed_sha must name an existing immutable commit")
    target_platforms = _string_list(
        settings.get("target_platforms"),
        "target_platforms",
        require_non_empty=True,
    )
    project_profiles = _string_list(
        settings.get("project_profiles"),
        "project_profiles",
        require_non_empty=True,
    )
    license_files = _string_list(
        settings.get("license_files"),
        "license_files",
        require_non_empty=True,
    )
    notice_files = _string_list(
        settings.get("notice_files", []),
        "notice_files",
        require_non_empty=False,
    )
    upstream_repository = _non_empty_string(
        settings.get("upstream_repository"), "upstream_repository"
    )
    upstream_remote = _non_empty_string(
        settings.get("upstream_remote"), "upstream_remote"
    )
    upstream_branch = _non_empty_string(
        settings.get("upstream_branch"), "upstream_branch"
    )
    fork_repository = _non_empty_string(
        settings.get("fork_repository"), "fork_repository"
    )
    fork_main_branch = _non_empty_string(
        settings.get("fork_main_branch"), "fork_main_branch"
    )
    upstream_spdx = _non_empty_string(
        settings.get("upstream_spdx"), "upstream_spdx"
    )
    fork_spdx = _non_empty_string(settings.get("fork_spdx"), "fork_spdx")
    compatibility_review = settings.get("compatibility_review", "")
    if not isinstance(compatibility_review, str):
        raise IntakeError("compatibility_review must be a string")

    template_root = _template_root()
    config = load_json(template_root / ".upstream-intake/config.json")
    config["upstream"] = {
        "branch": upstream_branch,
        "remote": upstream_remote,
        "repository": upstream_repository,
    }
    config["fork"] = {
        "main_branch": fork_main_branch,
        "repository": fork_repository,
    }
    config["execution"] = {
        "host_os": "macos",
        "project_profiles": project_profiles,
        "target_platforms": target_platforms,
    }
    config["licensing"] = {
        "compatibility_review": compatibility_review,
        "fork_spdx": fork_spdx,
        "license_files": license_files,
        "notice_files": notice_files,
        "upstream_spdx": upstream_spdx,
    }
    config["protected_contracts"] = ["repository-policy"]
    config["checks"] = {"always": ["git diff --check"]}
    config["commands"] = {
        "authorized": [
            "git status --short --branch",
            "git worktree list",
            f"git fetch --no-tags {upstream_remote} {upstream_branch}",
        ],
        "prohibited": [
            "git push",
            "git merge",
            "git cherry-pick",
            "git rebase",
            "deploy",
            "release",
            "install",
        ],
    }
    validate_config(repo, config)
    state = {
        "last_discovered": reviewed_sha,
        "open_batches": [],
        "reviewed_through": reviewed_sha,
        "schema_version": 1,
    }
    validate_state(state)

    workflow = (
        template_root / ".github/workflows/upstream-sync.yml"
    ).read_text(encoding="utf-8")
    replacements = {
        f"{REQUIRED_MARKER}UPSTREAM_BRANCH__": upstream_branch,
        f"{REQUIRED_MARKER}UPSTREAM_REMOTE__": upstream_remote,
        f"{REQUIRED_MARKER}UPSTREAM_REPOSITORY__": upstream_repository,
    }
    for marker, value in replacements.items():
        workflow = workflow.replace(marker, value)

    files = {
        ".github/PULL_REQUEST_TEMPLATE/upstream-intake.md": (
            template_root
            / ".github/PULL_REQUEST_TEMPLATE/upstream-intake.md"
        ).read_bytes(),
        ".github/workflows/upstream-sync.yml": workflow.encode("utf-8"),
        ".upstream-intake/batches/archive/.gitkeep": b"\n",
        ".upstream-intake/batches/open/.gitkeep": b"\n",
        ".upstream-intake/config.json": (
            json.dumps(config, indent=2, sort_keys=True) + "\n"
        ).encode("utf-8"),
        ".upstream-intake/state.json": (
            json.dumps(state, indent=2, sort_keys=True) + "\n"
        ).encode("utf-8"),
        ".upstream-intake/tools/upstream_intake.py": Path(__file__).read_bytes(),
    }
    unresolved = [
        relative
        for relative, content in files.items()
        if REQUIRED_MARKER.encode("utf-8") in content
    ]
    if unresolved:
        raise IntakeError(
            f"rendered project files contain unresolved markers: {unresolved}"
        )
    return files


def initialize_project(
    repo: Path, settings: dict[str, object], *, apply: bool = False
) -> dict[str, object]:
    """Dry-run or atomically preflight and write a repository distribution."""
    require_macos()
    repo = repo.resolve()
    run_git(repo, "rev-parse", "--git-dir")
    files = _render_project_files(repo, settings)
    relative_paths = sorted(files)
    result: dict[str, object] = {
        "applied": apply,
        "files": relative_paths,
        "unchanged": [],
        "written": [],
    }
    if not apply:
        return result

    if run_git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
        raise IntakeError("init-project --apply requires a clean repository")
    unchanged: list[str] = []
    conflicts: list[str] = []
    for relative in relative_paths:
        destination = repo / relative
        if not destination.exists():
            continue
        if not destination.is_file() or destination.read_bytes() != files[relative]:
            conflicts.append(relative)
        else:
            unchanged.append(relative)
    if conflicts:
        raise IntakeError(
            f"existing target differs from rendered distribution: {conflicts[0]}"
        )

    written: list[str] = []
    for relative in relative_paths:
        if relative in unchanged:
            continue
        destination = repo / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(files[relative])
        written.append(relative)
    result["unchanged"] = unchanged
    result["written"] = written
    return result


def _batch_paths(repo: Path) -> tuple[list[Path], list[Path]]:
    root = repo / ".upstream-intake/batches"
    return (
        sorted((root / "open").glob("*.json")),
        sorted((root / "archive").glob("*.json")),
    )


def validate_repository(repo: Path, base_ref: str | None = None) -> None:
    """Validate configuration, pointers, ledgers, and exact Git ranges."""
    root = repo / ".upstream-intake"
    config = load_json(root / "config.json")
    state = load_json(root / "state.json")
    validate_config(repo, config)
    validate_state(state)

    open_paths, archive_paths = _batch_paths(repo)
    expected_open = sorted(state["open_batches"])
    actual_open = sorted(path.stem for path in open_paths)
    if expected_open != actual_open:
        raise IntakeError(
            "state.open_batches must exactly match open batch files: "
            f"expected {actual_open}, found {expected_open}"
        )

    seen_shas: dict[str, str] = {}
    seen_batch_ids: set[str] = set()
    for path in [*open_paths, *archive_paths]:
        batch = load_json(path)
        validate_batch(batch)
        batch_id = _non_empty_string(batch.get("batch_id"), "batch_id")
        if batch_id != path.stem:
            raise IntakeError(f"{path} batch_id must match its filename")
        if batch_id in seen_batch_ids:
            raise IntakeError(f"duplicate batch_id: {batch_id}")
        seen_batch_ids.add(batch_id)
        entries = _object_list(batch.get("entries"), f"{path}.entries")
        entry_shas = [str(entry["upstream_sha"]) for entry in entries]
        for sha in entry_shas:
            if sha in seen_shas:
                raise IntakeError(
                    f"duplicate upstream SHA across batches: {sha} "
                    f"({seen_shas[sha]} and {batch_id})"
                )
            seen_shas[sha] = batch_id
        git_range = expected_range(
            repo,
            str(batch["previous_reviewed_sha"]),
            str(batch["pinned_upstream_sha"]),
        )
        if entry_shas != git_range:
            raise IntakeError(
                f"{batch_id} commit set must exactly equal its pinned Git range"
            )
    if base_ref is not None:
        validate_archive_changes(repo, base_ref)


def _validate_result(repo: Path) -> dict[str, object]:
    state = load_json(repo / ".upstream-intake/state.json")
    open_paths, archive_paths = _batch_paths(repo)
    entry_count = 0
    for path in [*open_paths, *archive_paths]:
        batch = load_json(path)
        entries = batch.get("entries")
        if isinstance(entries, list):
            entry_count += len(entries)
    return {
        "batch_count": len(open_paths) + len(archive_paths),
        "entry_count": entry_count,
        "ok": True,
        "reviewed_sha": state["reviewed_through"],
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate and review selective upstream intake state."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--repo", type=Path, required=True)
    validate.add_argument("--base-ref")
    discovery = subparsers.add_parser("discover")
    discovery.add_argument("--repo", type=Path, required=True)
    discovery.add_argument("--upstream-ref", required=True)
    discovery.add_argument("--format", choices=("json", "markdown"), default="json")
    discovery.add_argument("--require-macos", action="store_true")
    render = subparsers.add_parser("render")
    render.add_argument("--repo", type=Path, required=True)
    render.add_argument("--batch", type=Path, required=True)
    audit = subparsers.add_parser("audit")
    audit.add_argument("--repo", type=Path, required=True)
    initialize = subparsers.add_parser("init-project")
    initialize.add_argument("--repo", type=Path, required=True)
    initialize.add_argument("--upstream-repository", required=True)
    initialize.add_argument("--upstream-remote", required=True)
    initialize.add_argument("--upstream-branch", required=True)
    initialize.add_argument("--fork-repository", required=True)
    initialize.add_argument("--fork-main-branch", required=True)
    initialize.add_argument("--reviewed-sha", required=True)
    initialize.add_argument(
        "--target-platform", action="append", dest="target_platforms", required=True
    )
    initialize.add_argument(
        "--project-profile", action="append", dest="project_profiles", required=True
    )
    initialize.add_argument("--upstream-spdx", required=True)
    initialize.add_argument("--fork-spdx", required=True)
    initialize.add_argument(
        "--license-file", action="append", dest="license_files", required=True
    )
    initialize.add_argument(
        "--notice-file", action="append", dest="notice_files", default=[]
    )
    initialize.add_argument("--compatibility-review", default="")
    initialize.add_argument("--apply", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the command-line interface with stable exit categories."""
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "validate":
            repo = args.repo.resolve()
            validate_repository(repo, args.base_ref)
            print(json.dumps(_validate_result(repo), sort_keys=True))
            return 0
        if args.command == "discover":
            if args.require_macos:
                require_macos()
            report = discover(args.repo.resolve(), args.upstream_ref)
            if args.format == "markdown":
                print(render_markdown(report), end="")
            else:
                print(json.dumps(report, sort_keys=True))
            return 0
        if args.command == "render":
            repo = args.repo.resolve()
            batch_path = args.batch
            if not batch_path.is_absolute():
                batch_path = repo / batch_path
            print(_render_batch_markdown(load_json(batch_path)), end="")
            return 0
        if args.command == "audit":
            print(
                json.dumps(
                    audit_repository(args.repo.resolve()),
                    sort_keys=True,
                )
            )
            return 0
        if args.command == "init-project":
            settings = {
                "compatibility_review": args.compatibility_review,
                "fork_main_branch": args.fork_main_branch,
                "fork_repository": args.fork_repository,
                "fork_spdx": args.fork_spdx,
                "license_files": args.license_files,
                "notice_files": args.notice_files,
                "project_profiles": args.project_profiles,
                "reviewed_sha": args.reviewed_sha,
                "target_platforms": args.target_platforms,
                "upstream_branch": args.upstream_branch,
                "upstream_remote": args.upstream_remote,
                "upstream_repository": args.upstream_repository,
                "upstream_spdx": args.upstream_spdx,
            }
            print(
                json.dumps(
                    initialize_project(
                        args.repo.resolve(), settings, apply=args.apply
                    ),
                    sort_keys=True,
                )
            )
            return 0
    except IntakeError as error:
        print(f"upstream intake policy error: {error}", file=sys.stderr)
        return 2
    except IntakeEnvironmentError as error:
        print(f"upstream intake environment error: {error}", file=sys.stderr)
        return 3
    parser.error(f"unsupported command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
