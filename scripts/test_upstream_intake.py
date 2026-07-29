#!/usr/bin/env python3
"""Behavioral tests for the portable selective-upstream-intake system."""

from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parents[1]
SKILL_ROOT = REPO_ROOT / "tools/codex-skills/upstream-fork-intake"
TOOL_PATH = SKILL_ROOT / "scripts/upstream_intake.py"
FIXTURE_ROOT = REPO_ROOT / "scripts/fixtures/upstream-intake"

MIT_LICENSE = """MIT License

Copyright (c) 2026 Example

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
"""


def load_tool() -> ModuleType:
    """Load the canonical tool or fail with the missing production artifact."""
    if not TOOL_PATH.is_file():
        raise AssertionError(f"canonical intake tool is missing: {TOOL_PATH}")
    spec = importlib.util.spec_from_file_location("upstream_intake", TOOL_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load canonical intake tool: {TOOL_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_fixture(name: str) -> dict[str, object]:
    return json.loads((FIXTURE_ROOT / name).read_text(encoding="utf-8"))


class SkillDistributionTests(unittest.TestCase):
    """The source-controlled skill is complete enough to package and install."""

    def test_required_skill_distribution_exists(self) -> None:
        required_files = [
            SKILL_ROOT / "SKILL.md",
            SKILL_ROOT / "agents/openai.yaml",
            TOOL_PATH,
            SKILL_ROOT / "references/ledger-schema.md",
            SKILL_ROOT / "references/review-checklist.md",
            SKILL_ROOT / "references/apple-platform-checks.md",
        ]
        required_directories = [
            SKILL_ROOT / "assets/project-template",
        ]

        missing = [
            str(path.relative_to(REPO_ROOT))
            for path in [*required_files, *required_directories]
            if not path.exists()
        ]

        self.assertEqual([], missing, f"missing skill distribution paths: {missing}")

    def test_skill_metadata_is_installable_and_specific(self) -> None:
        skill_path = SKILL_ROOT / "SKILL.md"
        self.assertTrue(skill_path.is_file(), f"missing {skill_path}")
        text = skill_path.read_text(encoding="utf-8")

        self.assertIn("name: upstream-fork-intake", text)
        self.assertIn("description:", text)
        self.assertNotIn("TODO", text)

        agent_path = SKILL_ROOT / "agents/openai.yaml"
        self.assertTrue(agent_path.is_file(), f"missing {agent_path}")
        agent_text = agent_path.read_text(encoding="utf-8")
        self.assertIn("$upstream-fork-intake", agent_text)


class ConfigurationTests(unittest.TestCase):
    """Repository policy is explicit, portable, and license-aware."""

    def setUp(self) -> None:
        self.tool = load_tool()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_license(self, text: str) -> None:
        (self.repo / "LICENSE").write_text(text, encoding="utf-8")

    def apache_config(self) -> dict[str, object]:
        return load_fixture("config-apache.json")

    def mit_config(self) -> dict[str, object]:
        return load_fixture("config-mit.json")

    def test_apache_repository_validates_against_apache_license(self) -> None:
        self.write_license((REPO_ROOT / "LICENSE").read_text(encoding="utf-8"))

        self.tool.validate_config(self.repo, self.apache_config())

    def test_mit_repository_validates_against_mit_license(self) -> None:
        self.write_license(MIT_LICENSE)

        self.tool.validate_config(self.repo, self.mit_config())

    def test_declared_apache_repository_rejects_mit_license_body(self) -> None:
        self.write_license(MIT_LICENSE)

        with self.assertRaisesRegex(
            self.tool.IntakeError, "does not match declared SPDX Apache-2.0"
        ):
            self.tool.validate_config(self.repo, self.apache_config())

    def test_different_upstream_and_fork_licenses_require_review(self) -> None:
        self.write_license(MIT_LICENSE)
        config = self.mit_config()
        licensing = copy.deepcopy(config["licensing"])
        licensing["fork_spdx"] = "Apache-2.0"
        licensing["compatibility_review"] = ""
        config["licensing"] = licensing

        with self.assertRaisesRegex(
            self.tool.IntakeError, "licensing.compatibility_review"
        ):
            self.tool.validate_config(self.repo, config)

    def test_only_apple_target_platforms_are_supported(self) -> None:
        self.write_license(MIT_LICENSE)
        config = self.mit_config()
        execution = copy.deepcopy(config["execution"])
        execution["target_platforms"] = ["ios", "windows"]
        config["execution"] = execution

        with self.assertRaisesRegex(self.tool.IntakeError, "target platform"):
            self.tool.validate_config(self.repo, config)

    def test_only_known_apple_project_profiles_are_supported(self) -> None:
        self.write_license(MIT_LICENSE)
        config = self.mit_config()
        execution = copy.deepcopy(config["execution"])
        execution["project_profiles"] = ["native-xcode", "electron-windows"]
        config["execution"] = execution

        with self.assertRaisesRegex(self.tool.IntakeError, "project profile"):
            self.tool.validate_config(self.repo, config)

    def test_required_template_marker_fails_closed_at_any_depth(self) -> None:
        self.write_license(MIT_LICENSE)
        config = self.mit_config()
        checks = copy.deepcopy(config["checks"])
        checks["always"] = ["git diff --check", "__REQUIRED__"]
        config["checks"] = checks

        with self.assertRaisesRegex(self.tool.IntakeError, "__REQUIRED__"):
            self.tool.validate_config(self.repo, config)

    def test_batch_caps_cannot_exceed_process_maximum(self) -> None:
        self.write_license(MIT_LICENSE)
        config = self.mit_config()
        limits = copy.deepcopy(config["batch_limits"])
        limits["max_commits"] = 26
        config["batch_limits"] = limits

        with self.assertRaisesRegex(self.tool.IntakeError, "max_commits"):
            self.tool.validate_config(self.repo, config)


if __name__ == "__main__":
    unittest.main()
