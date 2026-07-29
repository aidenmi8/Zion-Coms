#!/usr/bin/env python3
"""Deterministic policy tooling for selective upstream intake."""

from __future__ import annotations

import json
import platform
from pathlib import Path
from typing import Any


SUPPORTED_TARGET_PLATFORMS = frozenset({"ios", "macos"})
SUPPORTED_PROJECT_PROFILES = frozenset(
    {"native-xcode", "flutter-ios", "tauri-macos", "swiftpm-macos"}
)
MAX_COMMITS = 25
MAX_CHANGED_FILES = 250


class IntakeError(Exception):
    """A deterministic policy or state validation failure."""


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
