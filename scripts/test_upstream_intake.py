#!/usr/bin/env python3
"""Behavioral tests for the portable selective-upstream-intake system."""

from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
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


def load_mutated_batch(name: str) -> dict[str, object]:
    descriptor = load_fixture(name)
    batch = load_fixture(str(descriptor["base_fixture"]))
    mutation = descriptor["mutation"]
    assert isinstance(mutation, dict)
    entry_sha = mutation["entry_sha"]
    entries = batch["entries"]
    assert isinstance(entries, list)
    entry = next(item for item in entries if item["upstream_sha"] == entry_sha)
    entry[str(mutation["field"])] = mutation["value"]
    return batch


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def make_batch(
    shas: list[str],
    previous: str,
    pinned: str,
    *,
    batch_id: str = "synthetic-batch",
) -> dict[str, object]:
    entries = []
    for sha in shas:
        entries.append(
            {
                "upstream_sha": sha,
                "topic_id": "synthetic-topic",
                "title": f"Commit {sha[:7]}",
                "areas": ["ios"],
                "risk": "low",
                "decision": "accept",
                "integration_method": "take",
                "delivery": "included",
                "rationale": "The synthetic fork wants this behavior.",
                "dependencies": [],
                "blocked_by_rejected": [],
                "dependency_resolution": None,
                "security_candidate": False,
                "security_reasons": [],
                "tracking": {
                    "issue": None,
                    "pull_request": None,
                    "local_backlog": None,
                    "implementation_plan": None,
                    "fork_commits": [],
                },
                "verification": [],
                "revisit": None,
            }
        )
    return {
        "schema_version": 1,
        "batch_id": batch_id,
        "previous_reviewed_sha": previous,
        "pinned_upstream_sha": pinned,
        "kind": "normal",
        "status": "reviewing",
        "topics": [
            {
                "topic_id": "synthetic-topic",
                "title": "Synthetic topic",
                "upstream_pr": None,
                "entry_shas": shas,
            }
        ],
        "entries": entries,
        "reclassifications": [],
    }


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


class BatchValidationTests(unittest.TestCase):
    """Each upstream commit receives one coherent and actionable decision."""

    def setUp(self) -> None:
        self.tool = load_tool()
        self.assertTrue(
            hasattr(self.tool, "validate_batch"),
            "production validator must expose validate_batch",
        )

    def test_valid_mixed_batch_covers_all_three_product_decisions(self) -> None:
        self.tool.validate_batch(load_fixture("mixed-batch.json"))

    def test_each_sha_must_belong_to_exactly_one_topic(self) -> None:
        batch = load_fixture("mixed-batch.json")
        topics = batch["topics"]
        assert isinstance(topics, list)
        topics[1]["entry_shas"].append(
            "1111111111111111111111111111111111111111"
        )

        with self.assertRaisesRegex(self.tool.IntakeError, "exactly one topic"):
            self.tool.validate_batch(batch)

    def test_accepted_entry_requires_take_or_adapt(self) -> None:
        batch = load_mutated_batch("invalid-accepted-no-method.json")

        with self.assertRaisesRegex(self.tool.IntakeError, "integration_method"):
            self.tool.validate_batch(batch)

    def test_queued_acceptance_requires_durable_tracking(self) -> None:
        batch = load_fixture("mixed-batch.json")
        entries = batch["entries"]
        assert isinstance(entries, list)
        queued = next(
            entry
            for entry in entries
            if entry["upstream_sha"]
            == "3333333333333333333333333333333333333333"
        )
        queued["tracking"] = {
            "issue": None,
            "pull_request": None,
            "local_backlog": None,
            "implementation_plan": None,
            "fork_commits": [],
        }

        with self.assertRaisesRegex(self.tool.IntakeError, "queued"):
            self.tool.validate_batch(batch)

    def test_rejected_entry_requires_rationale(self) -> None:
        batch = load_fixture("mixed-batch.json")
        entries = batch["entries"]
        assert isinstance(entries, list)
        rejected = entries[0]
        rejected["rationale"] = ""

        with self.assertRaisesRegex(self.tool.IntakeError, "rationale"):
            self.tool.validate_batch(batch)

    def test_rejected_entry_is_not_integrated_or_delivered(self) -> None:
        batch = load_fixture("mixed-batch.json")
        entries = batch["entries"]
        assert isinstance(entries, list)
        rejected = entries[0]
        rejected["integration_method"] = "take"
        rejected["delivery"] = "included"

        with self.assertRaisesRegex(self.tool.IntakeError, "rejected entry"):
            self.tool.validate_batch(batch)

    def test_deferred_entry_requires_owner_or_tracking_and_trigger(self) -> None:
        batch = load_mutated_batch("invalid-deferred-no-revisit.json")

        with self.assertRaisesRegex(self.tool.IntakeError, "deferred entry"):
            self.tool.validate_batch(batch)

    def test_rejected_dependency_forbids_take(self) -> None:
        batch = load_mutated_batch("invalid-rejected-dependency.json")

        with self.assertRaisesRegex(self.tool.IntakeError, "rejected dependency"):
            self.tool.validate_batch(batch)

    def test_included_adaptation_without_dependency_requires_resolution(self) -> None:
        batch = load_fixture("mixed-batch.json")
        entries = batch["entries"]
        assert isinstance(entries, list)
        adapted = entries[1]
        adapted["dependency_resolution"] = None

        with self.assertRaisesRegex(
            self.tool.IntakeError, "adapt_without_dependency"
        ):
            self.tool.validate_batch(batch)

    def test_included_adaptation_without_dependency_requires_verification(
        self,
    ) -> None:
        batch = load_fixture("mixed-batch.json")
        entries = batch["entries"]
        assert isinstance(entries, list)
        adapted = entries[1]
        adapted["verification"] = []

        with self.assertRaisesRegex(self.tool.IntakeError, "verification"):
            self.tool.validate_batch(batch)

    def test_high_security_candidate_requires_dedicated_batch(self) -> None:
        batch = load_fixture("mixed-batch.json")
        entries = batch["entries"]
        assert isinstance(entries, list)
        candidate = entries[1]
        candidate["security_candidate"] = True
        candidate["security_reasons"] = ["authentication path"]

        with self.assertRaisesRegex(self.tool.IntakeError, "security batch"):
            self.tool.validate_batch(batch)

    def test_security_batch_contains_only_security_candidates(self) -> None:
        batch = load_fixture("mixed-batch.json")
        batch["kind"] = "security"
        entries = batch["entries"]
        assert isinstance(entries, list)
        for entry in entries:
            entry["security_candidate"] = True
            entry["security_reasons"] = ["dedicated security review"]

        self.tool.validate_batch(batch)

        entries[-1]["security_candidate"] = False
        entries[-1]["security_reasons"] = []
        with self.assertRaisesRegex(
            self.tool.IntakeError, "only security candidates"
        ):
            self.tool.validate_batch(batch)


class GitRangeValidationTests(unittest.TestCase):
    """The ledger exactly accounts for the immutable Git range."""

    def setUp(self) -> None:
        self.tool = load_tool()
        for function_name in (
            "expected_range",
            "validate_repository",
            "validate_state",
        ):
            self.assertTrue(
                hasattr(self.tool, function_name),
                f"production validator must expose {function_name}",
            )
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp_dir.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Upstream Intake Test")
        self.git("config", "user.email", "intake@example.test")
        (self.repo / "LICENSE").write_text(MIT_LICENSE, encoding="utf-8")
        self.git("add", "LICENSE")
        self.git("commit", "-q", "-m", "base")
        self.base = self.git("rev-parse", "HEAD")
        self.first = self.commit_file("first.txt", "first\n", "First change")
        self.second = self.commit_file(
            "second.txt", "second\n", "Second change"
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(self.repo), *args],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def commit_file(self, name: str, content: str, message: str) -> str:
        (self.repo / name).write_text(content, encoding="utf-8")
        self.git("add", name)
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def install_policy(self) -> None:
        config = load_fixture("config-mit.json")
        state = {
            "schema_version": 1,
            "reviewed_through": self.base,
            "last_discovered": self.second,
            "open_batches": ["synthetic-batch"],
        }
        batch = make_batch(
            [self.first, self.second],
            self.base,
            self.second,
        )
        write_json(self.repo / ".upstream-intake/config.json", config)
        write_json(self.repo / ".upstream-intake/state.json", state)
        write_json(
            self.repo
            / ".upstream-intake/batches/open/synthetic-batch.json",
            batch,
        )
        (
            self.repo / ".upstream-intake/batches/archive"
        ).mkdir(parents=True, exist_ok=True)

    def test_expected_range_is_oldest_first_and_uses_full_shas(self) -> None:
        self.assertEqual(
            [self.first, self.second],
            self.tool.expected_range(self.repo, self.base, self.second),
        )

    def test_repository_requires_exact_batch_commit_range(self) -> None:
        self.install_policy()
        self.tool.validate_repository(self.repo)
        path = (
            self.repo
            / ".upstream-intake/batches/open/synthetic-batch.json"
        )
        batch = json.loads(path.read_text(encoding="utf-8"))
        batch["entries"].pop()
        batch["topics"][0]["entry_shas"].pop()
        write_json(path, batch)

        with self.assertRaisesRegex(self.tool.IntakeError, "commit set"):
            self.tool.validate_repository(self.repo)

    def test_duplicate_sha_across_open_and_archive_fails(self) -> None:
        self.install_policy()
        batch = make_batch(
            [self.first, self.second],
            self.base,
            self.second,
            batch_id="archived-batch",
        )
        write_json(
            self.repo
            / ".upstream-intake/batches/archive/archived-batch.json",
            batch,
        )

        with self.assertRaisesRegex(self.tool.IntakeError, "duplicate upstream SHA"):
            self.tool.validate_repository(self.repo)

    def test_state_open_batches_exactly_matches_open_files(self) -> None:
        self.install_policy()
        state_path = self.repo / ".upstream-intake/state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["open_batches"] = []
        write_json(state_path, state)

        with self.assertRaisesRegex(self.tool.IntakeError, "open_batches"):
            self.tool.validate_repository(self.repo)

    def test_state_rejects_abbreviated_durable_shas(self) -> None:
        state = {
            "schema_version": 1,
            "reviewed_through": self.base[:12],
            "last_discovered": self.second,
            "open_batches": [],
        }

        with self.assertRaisesRegex(self.tool.IntakeError, "full 40-character"):
            self.tool.validate_state(state)

    def test_validate_cli_returns_json_and_policy_exit_code(self) -> None:
        self.install_policy()
        success = subprocess.run(
            [
                "python3",
                str(TOOL_PATH),
                "validate",
                "--repo",
                str(self.repo),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(0, success.returncode, success.stderr)
        self.assertEqual(
            {
                "batch_count": 1,
                "entry_count": 2,
                "ok": True,
                "reviewed_sha": self.base,
            },
            json.loads(success.stdout),
        )

        state_path = self.repo / ".upstream-intake/state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["reviewed_through"] = self.base[:12]
        write_json(state_path, state)
        failure = subprocess.run(
            [
                "python3",
                str(TOOL_PATH),
                "validate",
                "--repo",
                str(self.repo),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(2, failure.returncode)
        self.assertIn("full 40-character", failure.stderr)


if __name__ == "__main__":
    unittest.main()
