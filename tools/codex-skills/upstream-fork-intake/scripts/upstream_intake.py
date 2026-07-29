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
        return "__REQUIRED__" in value
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
        raise IntakeError("configuration contains unresolved __REQUIRED__ marker")
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
        raise IntakeError("batch contains unresolved __REQUIRED__ marker")
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


def validate_state(state: dict[str, object]) -> None:
    """Validate durable repository pointers."""
    if _has_required_marker(state):
        raise IntakeError("state contains unresolved __REQUIRED__ marker")
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
    try:
        ancestor = subprocess.run(
            ["git", "-C", str(repo), "merge-base", "--is-ancestor", previous, pinned],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise IntakeEnvironmentError(f"cannot execute git: {error}") from error
    if ancestor.returncode == 1:
        raise IntakeError(f"{previous} is not an ancestor of {pinned}")
    if ancestor.returncode != 0:
        detail = ancestor.stderr.strip() or "unknown error"
        raise IntakeEnvironmentError(f"cannot verify Git ancestry: {detail}")
    output = run_git(
        repo,
        "rev-list",
        "--reverse",
        "--topo-order",
        f"{previous}..{pinned}",
    )
    return output.splitlines() if output else []


def _batch_paths(repo: Path) -> tuple[list[Path], list[Path]]:
    root = repo / ".upstream-intake/batches"
    return (
        sorted((root / "open").glob("*.json")),
        sorted((root / "archive").glob("*.json")),
    )


def validate_repository(repo: Path, base_ref: str | None = None) -> None:
    """Validate configuration, pointers, ledgers, and exact Git ranges."""
    del base_ref
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
