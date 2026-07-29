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
from unittest import mock


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

    def test_skill_routes_every_mandatory_workflow_boundary(self) -> None:
        text = (SKILL_ROOT / "SKILL.md").read_text(encoding="utf-8")
        normalized = " ".join(text.split())
        description = next(
            line for line in text.splitlines() if line.startswith("description:")
        )
        self.assertTrue(description.startswith("description: Use when"))
        required = (
            "Read `AGENTS.md`",
            "git status --short --branch",
            "git worktree list",
            "git remote -v",
            "read-only discovery",
            "immutable full SHAs",
            "`accept`",
            "`reject`",
            "`defer`",
            "`take`",
            "`adapt`",
            "`accept + queued`",
            "security batch",
            "rejected dependency",
            "repository-specific license",
            "one local batch PR",
            "hard boundary",
            "Do not automatically push",
            "macOS host",
        )
        for phrase in required:
            self.assertIn(phrase, normalized)
        self.assertLess(len(text.split()), 500)

    def test_skill_routes_directly_to_all_heavy_references(self) -> None:
        text = (SKILL_ROOT / "SKILL.md").read_text(encoding="utf-8")
        normalized = " ".join(text.split())
        for reference in (
            "references/ledger-schema.md",
            "references/review-checklist.md",
            "references/apple-platform-checks.md",
        ):
            self.assertIn(reference, text)
        self.assertIn(
            "before editing configuration, state, or batches", normalized
        )
        self.assertIn("before classifying an upstream topic", normalized)
        self.assertIn(
            "before running platform-specific commands", normalized
        )

    def test_references_cover_schema_review_and_all_apple_profiles(self) -> None:
        ledger = (
            SKILL_ROOT / "references/ledger-schema.md"
        ).read_text(encoding="utf-8")
        review = (
            SKILL_ROOT / "references/review-checklist.md"
        ).read_text(encoding="utf-8")
        apple = (
            SKILL_ROOT / "references/apple-platform-checks.md"
        ).read_text(encoding="utf-8")

        for phrase in (
            "Exit codes",
            "Archive immutability",
            "Reclassification",
            "accept + queued",
            "adapt_without_dependency",
        ):
            self.assertIn(phrase, ledger)
        for phrase in (
            "Dependency graph",
            "Security fast lane",
            "Licensing and attribution",
            "Compatibility contracts",
            "Batch boundary",
            "Release separation",
        ):
            self.assertIn(phrase, review)
        for profile in (
            "native-xcode",
            "flutter-ios",
            "tauri-macos",
            "swiftpm-macos",
        ):
            self.assertIn(profile, apple)
        for phrase in (
            "signing",
            "privacy",
            "accessibility",
            "reduced motion",
            "bundle identifier",
            "prohibited commands",
        ):
            self.assertIn(phrase, apple.casefold())

    def test_generic_templates_fail_closed_until_initializer_renders_them(
        self,
    ) -> None:
        template_root = SKILL_ROOT / "assets/project-template"
        config = (
            template_root / ".upstream-intake/config.json"
        ).read_text(encoding="utf-8")
        state = (
            template_root / ".upstream-intake/state.json"
        ).read_text(encoding="utf-8")
        workflow = (
            template_root / ".github/workflows/upstream-sync.yml"
        ).read_text(encoding="utf-8")

        self.assertIn("__REQUIRED__", config)
        self.assertIn("__REQUIRED__", state)
        self.assertIn("__REQUIRED__", workflow)
        self.assertFalse((SKILL_ROOT / "README.md").exists())


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


class DiscoveryTests(unittest.TestCase):
    """Discovery is capped, deterministic, security-aware, and read-only."""

    def setUp(self) -> None:
        self.tool = load_tool()
        for function_name in (
            "classify_topic",
            "discover",
            "render_markdown",
            "security_reasons",
        ):
            self.assertTrue(
                hasattr(self.tool, function_name),
                f"production tool must expose {function_name}",
            )
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp_dir.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Discovery Test")
        self.git("config", "user.email", "discovery@example.test")
        (self.repo / "LICENSE").write_text(MIT_LICENSE, encoding="utf-8")
        self.git("add", "LICENSE")
        self.git("commit", "-q", "-m", "base")
        self.base = self.git("rev-parse", "HEAD")

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

    def commit_files(self, files: dict[str, str], message: str) -> str:
        for name, content in files.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        self.git("add", *files)
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def configure(
        self,
        reviewed: str,
        *,
        max_commits: int = 25,
        max_changed_files: int = 250,
    ) -> None:
        config = load_fixture("config-mit.json")
        limits = copy.deepcopy(config["batch_limits"])
        limits["max_commits"] = max_commits
        limits["max_changed_files"] = max_changed_files
        config["batch_limits"] = limits
        state = {
            "schema_version": 1,
            "reviewed_through": reviewed,
            "last_discovered": reviewed,
            "open_batches": [],
        }
        write_json(self.repo / ".upstream-intake/config.json", config)
        write_json(self.repo / ".upstream-intake/state.json", state)

    def test_no_change_discovery_reports_zero_commits(self) -> None:
        self.configure(self.base)

        report = self.tool.discover(self.repo, "main")

        self.assertEqual(0, report["commit_count"])
        self.assertEqual(0, report["changed_file_count"])
        self.assertEqual(self.base, report["pinned_upstream_sha"])
        self.assertEqual([], report["commits"])

    def test_reviewed_sha_must_be_ancestor_of_requested_ref(self) -> None:
        descendant = self.commit_files({"later.txt": "later\n"}, "Later")
        self.configure(descendant)

        with self.assertRaisesRegex(self.tool.IntakeError, "not an ancestor"):
            self.tool.discover(self.repo, self.base)

    def test_commits_include_metadata_and_stable_topic_grouping(self) -> None:
        first = self.commit_files(
            {"mobile/pairing.dart": "pairing\n"}, "Fix pairing (#123)"
        )
        second = self.commit_files(
            {"desktop/activity.tsx": "activity\n"}, "Polish activity"
        )
        self.configure(self.base)

        report = self.tool.discover(self.repo, "main")
        commits = report["commits"]

        self.assertEqual([first, second], [commit["sha"] for commit in commits])
        self.assertEqual("Fix pairing (#123)", commits[0]["subject"])
        self.assertRegex(
            commits[0]["author_date"],
            r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}",
        )
        self.assertEqual(["mobile/pairing.dart"], commits[0]["files"])
        self.assertEqual(
            {"deletions": 0, "files": 1, "insertions": 1},
            commits[0]["statistics"],
        )
        self.assertEqual("pr-123", commits[0]["topic_id"])
        self.assertEqual(123, commits[0]["upstream_pr"])
        self.assertEqual(f"commit-{second[:12]}", commits[1]["topic_id"])
        self.assertIsNone(commits[1]["upstream_pr"])
        self.assertEqual(
            [first],
            next(
                topic["entry_shas"]
                for topic in report["topics"]
                if topic["topic_id"] == "pr-123"
            ),
        )

    def test_default_commit_cap_pins_the_twenty_fifth_commit(self) -> None:
        shas = []
        for index in range(26):
            shas.append(
                self.commit_files(
                    {f"changes/{index:02d}.txt": f"{index}\n"},
                    f"Change {index:02d}",
                )
            )
        self.configure(self.base)

        report = self.tool.discover(self.repo, "main")

        self.assertEqual(25, report["commit_count"])
        self.assertEqual(shas[24], report["pinned_upstream_sha"])
        self.assertEqual(1, report["remaining_commit_count"])
        self.assertEqual("commit_limit", report["cap"]["reason"])

    def test_configured_lower_file_cap_is_honored(self) -> None:
        first = self.commit_files(
            {"one.txt": "one\n", "two.txt": "two\n"}, "Two files"
        )
        self.commit_files({"three.txt": "three\n"}, "Third file")
        self.configure(self.base, max_changed_files=2)

        report = self.tool.discover(self.repo, "main")

        self.assertEqual(1, report["commit_count"])
        self.assertEqual(first, report["pinned_upstream_sha"])
        self.assertEqual(2, report["changed_file_count"])
        self.assertEqual("changed_file_limit", report["cap"]["reason"])

    def test_single_oversized_commit_is_explicit_dedicated_batch_blocker(
        self,
    ) -> None:
        oversized = self.commit_files(
            {
                "one.txt": "one\n",
                "two.txt": "two\n",
                "three.txt": "three\n",
            },
            "Atomic generated update",
        )
        self.configure(self.base, max_changed_files=2)

        report = self.tool.discover(self.repo, "main")

        self.assertEqual(1, report["commit_count"])
        self.assertEqual(oversized, report["pinned_upstream_sha"])
        self.assertEqual(
            {
                "changed_files": 3,
                "limit": 2,
                "reason": "single_commit_exceeds_changed_file_limit",
                "sha": oversized,
            },
            report["dedicated_batch_blocker"],
        )

    def test_security_reasons_include_title_and_sensitive_path(self) -> None:
        secure = self.commit_files(
            {"crates/buzz-auth/src/secret.rs": "secret\n"},
            "Harden authentication secret handling",
        )
        self.configure(self.base)

        report = self.tool.discover(self.repo, "main")
        commit = report["commits"][0]

        self.assertEqual(secure, commit["sha"])
        self.assertIn("title keyword: authentication", commit["security_reasons"])
        self.assertIn(
            "sensitive path: crates/buzz-auth/src/secret.rs",
            commit["security_reasons"],
        )

    def test_discovery_does_not_modify_repository_or_intake_state(self) -> None:
        self.commit_files({"change.txt": "change\n"}, "Read-only candidate")
        self.configure(self.base)
        before = {
            "status": self.git("status", "--porcelain=v1", "--untracked-files=all"),
            "refs": self.git("show-ref"),
            "head": self.git("rev-parse", "HEAD"),
            "state": (
                self.repo / ".upstream-intake/state.json"
            ).read_bytes(),
            "config": (
                self.repo / ".upstream-intake/config.json"
            ).read_bytes(),
        }

        self.tool.discover(self.repo, "main")

        after = {
            "status": self.git("status", "--porcelain=v1", "--untracked-files=all"),
            "refs": self.git("show-ref"),
            "head": self.git("rev-parse", "HEAD"),
            "state": (
                self.repo / ".upstream-intake/state.json"
            ).read_bytes(),
            "config": (
                self.repo / ".upstream-intake/config.json"
            ).read_bytes(),
        }
        self.assertEqual(before, after)

    def test_markdown_and_json_share_the_same_range_and_counts(self) -> None:
        candidate = self.commit_files(
            {"candidate.txt": "candidate\n"}, "Candidate"
        )
        self.configure(self.base)
        report = self.tool.discover(self.repo, "main")

        markdown = self.tool.render_markdown(report)
        encoded = json.loads(json.dumps(report, sort_keys=True))

        self.assertIn(f"`{self.base}..{candidate}`", markdown)
        self.assertIn("Commits: **1**", markdown)
        self.assertIn("Changed files: **1**", markdown)
        self.assertEqual(candidate, encoded["pinned_upstream_sha"])
        self.assertEqual(1, encoded["commit_count"])
        self.assertEqual(1, encoded["changed_file_count"])


class ArchiveImmutabilityTests(unittest.TestCase):
    """Closed decision history changes only through append-only records."""

    def setUp(self) -> None:
        self.tool = load_tool()
        self.assertTrue(
            hasattr(self.tool, "validate_archive_changes"),
            "production tool must expose validate_archive_changes",
        )
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp_dir.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Archive Test")
        self.git("config", "user.email", "archive@example.test")
        self.batch = load_fixture("mixed-batch.json")
        self.batch["status"] = "closed"
        self.path = (
            self.repo
            / ".upstream-intake/batches/archive/2026-07-29-4444444.json"
        )
        write_json(self.path, self.batch)
        self.git("add", ".upstream-intake")
        self.git("commit", "-q", "-m", "archive batch")
        self.base_ref = self.git("rev-parse", "HEAD")

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

    def reclassification(self) -> dict[str, object]:
        return {
            "date": "2026-07-29",
            "new_decision": "accept",
            "old_decision": "reject",
            "reason": "The dependency is now approved.",
            "tracking_reference": "https://github.com/example/fork/issues/22",
            "upstream_sha": "1111111111111111111111111111111111111111",
        }

    def test_deleting_archived_batch_fails(self) -> None:
        self.path.unlink()

        with self.assertRaisesRegex(self.tool.IntakeError, "deleted"):
            self.tool.validate_archive_changes(self.repo, self.base_ref)

    def test_editing_original_archived_decision_fails(self) -> None:
        current = json.loads(self.path.read_text(encoding="utf-8"))
        current["entries"][0]["decision"] = "accept"
        write_json(self.path, current)

        with self.assertRaisesRegex(self.tool.IntakeError, "immutable"):
            self.tool.validate_archive_changes(self.repo, self.base_ref)

    def test_append_only_complete_reclassification_passes(self) -> None:
        current = json.loads(self.path.read_text(encoding="utf-8"))
        current["reclassifications"].append(self.reclassification())
        write_json(self.path, current)

        self.tool.validate_archive_changes(self.repo, self.base_ref)

    def test_reclassification_does_not_allow_original_evidence_edit(self) -> None:
        current = json.loads(self.path.read_text(encoding="utf-8"))
        current["entries"][0]["rationale"] = "Rewritten history."
        current["reclassifications"].append(self.reclassification())
        write_json(self.path, current)

        with self.assertRaisesRegex(self.tool.IntakeError, "immutable"):
            self.tool.validate_archive_changes(self.repo, self.base_ref)


class AuditTests(unittest.TestCase):
    """Audit surfaces action and evidence gaps without rewriting the ledger."""

    def setUp(self) -> None:
        self.tool = load_tool()
        self.assertTrue(
            hasattr(self.tool, "audit_repository"),
            "production tool must expose audit_repository",
        )
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp_dir.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Audit Test")
        self.git("config", "user.email", "audit@example.test")
        (self.repo / "LICENSE").write_text(MIT_LICENSE, encoding="utf-8")
        self.git("add", "LICENSE")
        self.git("commit", "-q", "-m", "base")
        self.base = self.git("rev-parse", "HEAD")
        self.first = self.commit_file("first.txt", "first\n", "First")
        self.second = self.commit_file("second.txt", "second\n", "Second")
        self.third = self.commit_file("third.txt", "third\n", "Third")
        self.fourth = self.commit_file("fourth.txt", "fourth\n", "Fourth")
        self.install_auditable_state()

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

    def install_auditable_state(self) -> None:
        config = load_fixture("config-mit.json")
        batch = make_batch(
            [self.first, self.second, self.third],
            self.base,
            self.fourth,
            batch_id="audit-batch",
        )
        batch["status"] = "reviewed"
        entries = batch["entries"]
        entries[0]["delivery"] = "queued"
        entries[0]["tracking"]["issue"] = (
            "https://github.com/example/fork/issues/30"
        )
        entries[1]["decision"] = "defer"
        entries[1]["integration_method"] = None
        entries[1]["delivery"] = "not_applicable"
        entries[1]["revisit"] = {
            "owner": "ios-owner",
            "tracking": None,
            "trigger": "The upstream API stabilizes.",
            "triggered": True,
        }
        entries[2]["verification"] = []

        archive = make_batch(
            [self.first],
            self.base,
            self.first,
            batch_id="prior-batch",
        )
        archive["status"] = "closed"
        archive["entries"][0]["verification"] = ["archived verification"]

        state = {
            "schema_version": 1,
            "reviewed_through": self.base,
            "last_discovered": "ffffffffffffffffffffffffffffffffffffffff",
            "open_batches": ["audit-batch"],
        }
        write_json(self.repo / ".upstream-intake/config.json", config)
        write_json(self.repo / ".upstream-intake/state.json", state)
        write_json(
            self.repo / ".upstream-intake/batches/open/audit-batch.json",
            batch,
        )
        write_json(
            self.repo / ".upstream-intake/batches/archive/prior-batch.json",
            archive,
        )

    def test_audit_reports_action_and_range_evidence_gaps(self) -> None:
        report = self.tool.audit_repository(self.repo)

        self.assertFalse(report["ok"])
        self.assertEqual(
            [self.first],
            [item["upstream_sha"] for item in report["queued_acceptances"]],
        )
        self.assertEqual(
            [self.second],
            [item["upstream_sha"] for item in report["triggered_deferrals"]],
        )
        self.assertIn(
            "ffffffffffffffffffffffffffffffffffffffff",
            [item["sha"] for item in report["unreachable_pointers"]],
        )
        self.assertIn(
            self.third,
            [item["upstream_sha"] for item in report["missing_evidence"]],
        )
        self.assertEqual([self.first], report["duplicate_shas"])
        self.assertEqual([self.fourth], report["omitted_shas"])


class InitializationTests(unittest.TestCase):
    """Project activation is explicit, preflighted, and dry-run first."""

    def setUp(self) -> None:
        self.tool = load_tool()
        self.assertTrue(
            hasattr(self.tool, "initialize_project"),
            "production tool must expose initialize_project",
        )
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp_dir.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Initialization Test")
        self.git("config", "user.email", "init@example.test")
        (self.repo / "LICENSE").write_text(MIT_LICENSE, encoding="utf-8")
        self.git("add", "LICENSE")
        self.git("commit", "-q", "-m", "base")
        self.reviewed_sha = self.git("rev-parse", "HEAD")

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

    def settings(self) -> dict[str, object]:
        return {
            "compatibility_review": "",
            "fork_main_branch": "main",
            "fork_repository": "example/mit-fork",
            "fork_spdx": "MIT",
            "license_files": ["LICENSE"],
            "notice_files": [],
            "project_profiles": ["native-xcode"],
            "reviewed_sha": self.reviewed_sha,
            "target_platforms": ["ios"],
            "upstream_branch": "main",
            "upstream_remote": "upstream",
            "upstream_repository": "example/upstream",
            "upstream_spdx": "MIT",
        }

    def expected_paths(self) -> list[str]:
        return sorted(
            [
                ".github/PULL_REQUEST_TEMPLATE/upstream-intake.md",
                ".github/workflows/upstream-sync.yml",
                ".upstream-intake/batches/archive/.gitkeep",
                ".upstream-intake/batches/open/.gitkeep",
                ".upstream-intake/config.json",
                ".upstream-intake/state.json",
                ".upstream-intake/tools/upstream_intake.py",
            ]
        )

    def test_default_initialization_is_dry_run(self) -> None:
        result = self.tool.initialize_project(
            self.repo, self.settings(), apply=False
        )

        self.assertFalse(result["applied"])
        self.assertEqual(self.expected_paths(), result["files"])
        self.assertFalse((self.repo / ".upstream-intake").exists())

    def test_apply_refuses_dirty_repository(self) -> None:
        (self.repo / "dirty.txt").write_text("dirty\n", encoding="utf-8")

        with self.assertRaisesRegex(self.tool.IntakeError, "clean repository"):
            self.tool.initialize_project(self.repo, self.settings(), apply=True)

    def test_apply_refuses_conflicting_existing_target(self) -> None:
        workflow = self.repo / ".github/workflows/upstream-sync.yml"
        workflow.parent.mkdir(parents=True)
        workflow.write_text("name: Existing policy\n", encoding="utf-8")
        self.git("add", ".github")
        self.git("commit", "-q", "-m", "existing workflow")
        settings = self.settings()
        settings["reviewed_sha"] = self.git("rev-parse", "HEAD")

        with self.assertRaisesRegex(self.tool.IntakeError, "existing target differs"):
            self.tool.initialize_project(self.repo, settings, apply=True)

    def test_initialization_requires_full_existing_reviewed_sha(self) -> None:
        settings = self.settings()
        settings["reviewed_sha"] = self.reviewed_sha[:12]

        with self.assertRaisesRegex(
            self.tool.IntakeError, "full 40-character"
        ):
            self.tool.initialize_project(self.repo, settings, apply=False)

    def test_initialization_requires_explicit_platform_and_profile(self) -> None:
        settings = self.settings()
        settings["project_profiles"] = []

        with self.assertRaisesRegex(self.tool.IntakeError, "project_profiles"):
            self.tool.initialize_project(self.repo, settings, apply=False)

    def test_apply_renders_complete_files_and_exact_canonical_tool(self) -> None:
        result = self.tool.initialize_project(
            self.repo, self.settings(), apply=True
        )

        self.assertTrue(result["applied"])
        self.assertEqual(self.expected_paths(), result["written"])
        generated_text = "\n".join(
            path.read_text(encoding="utf-8")
            for path in self.repo.rglob("*")
            if path.is_file() and ".git" not in path.parts
        )
        self.assertNotIn("__REQUIRED__", generated_text)
        self.assertEqual(
            TOOL_PATH.read_bytes(),
            (
                self.repo / ".upstream-intake/tools/upstream_intake.py"
            ).read_bytes(),
        )

    def test_reapply_is_idempotent_only_when_generated_files_match(self) -> None:
        self.tool.initialize_project(self.repo, self.settings(), apply=True)
        self.git("add", ".upstream-intake", ".github")
        self.git("commit", "-q", "-m", "initialize intake")
        settings = self.settings()
        settings["reviewed_sha"] = self.reviewed_sha

        result = self.tool.initialize_project(self.repo, settings, apply=True)

        self.assertEqual([], result["written"])
        self.assertEqual(self.expected_paths(), result["unchanged"])

    def test_init_project_cli_is_dry_run_without_apply(self) -> None:
        command = [
            "python3",
            str(TOOL_PATH),
            "init-project",
            "--repo",
            str(self.repo),
            "--upstream-repository",
            "example/upstream",
            "--upstream-remote",
            "upstream",
            "--upstream-branch",
            "main",
            "--fork-repository",
            "example/mit-fork",
            "--fork-main-branch",
            "main",
            "--reviewed-sha",
            self.reviewed_sha,
            "--target-platform",
            "ios",
            "--project-profile",
            "native-xcode",
            "--upstream-spdx",
            "MIT",
            "--fork-spdx",
            "MIT",
            "--license-file",
            "LICENSE",
        ]

        result = subprocess.run(command, capture_output=True, text=True)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(json.loads(result.stdout)["applied"])
        self.assertFalse((self.repo / ".upstream-intake").exists())


class ZionProfileTests(unittest.TestCase):
    """Zion's checked-in profile preserves fork identity and compatibility."""

    REVIEWED_SHA = "60158fce3e670f11bb35d42627857ccaea50ff06"

    def setUp(self) -> None:
        self.tool = load_tool()
        self.config_path = REPO_ROOT / ".upstream-intake/config.json"
        self.state_path = REPO_ROOT / ".upstream-intake/state.json"

    def test_zion_profile_pins_provenance_platforms_and_license(self) -> None:
        self.assertTrue(self.config_path.is_file())
        self.assertTrue(self.state_path.is_file())
        config = json.loads(self.config_path.read_text(encoding="utf-8"))
        state = json.loads(self.state_path.read_text(encoding="utf-8"))

        self.assertEqual(
            {
                "branch": "main",
                "remote": "upstream",
                "repository": "block/buzz",
            },
            config["upstream"],
        )
        self.assertEqual(
            {
                "main_branch": "main",
                "repository": "aidenmi8/Zion-Coms",
            },
            config["fork"],
        )
        self.assertEqual(
            ["ios", "macos"], config["execution"]["target_platforms"]
        )
        self.assertEqual(
            ["flutter-ios", "tauri-macos"],
            config["execution"]["project_profiles"],
        )
        self.assertEqual("Apache-2.0", config["licensing"]["upstream_spdx"])
        self.assertEqual("Apache-2.0", config["licensing"]["fork_spdx"])
        self.assertEqual(["LICENSE"], config["licensing"]["license_files"])
        self.assertEqual(self.REVIEWED_SHA, state["reviewed_through"])
        self.assertEqual(self.REVIEWED_SHA, state["last_discovered"])

        self.tool.validate_config(REPO_ROOT, config)
        self.tool.validate_state(state)

    def test_zion_profile_protects_all_fork_owned_contracts(self) -> None:
        config = json.loads(self.config_path.read_text(encoding="utf-8"))

        self.assertEqual(
            {
                "admin-brand-routes",
                "compatibility-identifiers",
                "desktop-sidecars",
                "mobile-permissions",
                "platform-brand",
                "protocols-and-routes",
                "visible-brand",
            },
            set(config["protected_contracts"]),
        )
        surfaces = "\n".join(config["compatibility_surfaces"])
        for required in (
            "BUZZ_*",
            "buzz://",
            "buzz-*",
            "xyz.block.buzz.app",
            "mobile bundle identifiers",
            "relay paths",
            "Docker",
            "legacy URLs",
        ):
            self.assertIn(required, surfaces)

    def test_zion_vendored_tool_is_byte_identical_to_skill_tool(self) -> None:
        vendored = REPO_ROOT / ".upstream-intake/tools/upstream_intake.py"

        self.assertTrue(vendored.is_file())
        self.assertEqual(TOOL_PATH.read_bytes(), vendored.read_bytes())

    def test_zion_repository_state_validates_without_open_batch(self) -> None:
        self.tool.validate_repository(REPO_ROOT)


class WorkflowSafetyTests(unittest.TestCase):
    """Scheduled discovery can report but cannot integrate or publish."""

    def setUp(self) -> None:
        self.workflow_path = REPO_ROOT / ".github/workflows/upstream-sync.yml"
        self.workflow = self.workflow_path.read_text(encoding="utf-8")
        self.justfile = (REPO_ROOT / "Justfile").read_text(encoding="utf-8")

    def test_workflow_has_read_only_credentials_and_single_upstream_fetch(
        self,
    ) -> None:
        self.assertRegex(
            self.workflow, r"(?m)^permissions:\n  contents: read$"
        )
        self.assertIn("persist-credentials: false", self.workflow)
        self.assertEqual(
            1,
            self.workflow.count("git fetch --no-tags upstream main"),
        )
        self.assertIn(
            "--upstream-ref upstream/main", self.workflow
        )

    def test_workflow_has_no_integration_publication_or_delivery_action(
        self,
    ) -> None:
        forbidden = (
            "contents: write",
            "pull-requests: write",
            "issues: write",
            "persist-credentials: true",
            "GH_TOKEN",
            "git merge",
            "git push",
            "git switch",
            "git checkout -b",
            "git cherry-pick",
            "git rebase",
            "gh pr",
            "deploy",
            "release",
            "install",
        )
        for token in forbidden:
            self.assertNotIn(token, self.workflow)

    def test_workflow_only_publishes_report_to_job_summary(self) -> None:
        self.assertIn("workflow_dispatch:", self.workflow)
        self.assertIn('cron: "17 5 * * 1"', self.workflow)
        self.assertEqual(1, self.workflow.count("$GITHUB_STEP_SUMMARY"))
        self.assertIn(
            '--format markdown >> "$GITHUB_STEP_SUMMARY"', self.workflow
        )

    def test_just_check_runs_upstream_intake_gate(self) -> None:
        check_line = next(
            line for line in self.justfile.splitlines() if line.startswith("check:")
        )
        self.assertIn("upstream-intake-check", check_line)
        self.assertLess(
            check_line.index("upstream-intake-check"),
            check_line.index("fmt-check"),
        )
        self.assertIn(
            "upstream-intake-check:\n"
            "    python3 -m unittest scripts/test_upstream_intake.py\n"
            "    python3 .upstream-intake/tools/upstream_intake.py "
            "validate --repo .",
            self.justfile,
        )


class ProjectProfileTests(unittest.TestCase):
    """Every supported Apple profile validates with repository-owned policy."""

    CASES = (
        (
            "native-xcode/config.json",
            MIT_LICENSE,
            ["ios"],
            ["native-xcode"],
            "signing-boundaries",
        ),
        (
            "flutter-ios/config.json",
            (REPO_ROOT / "LICENSE").read_text(encoding="utf-8"),
            ["ios"],
            ["flutter-ios"],
            "mobile-privacy-permissions",
        ),
        (
            "tauri-macos/config.json",
            (REPO_ROOT / "LICENSE").read_text(encoding="utf-8"),
            ["macos"],
            ["tauri-macos"],
            "sidecar-artifacts",
        ),
        (
            "swiftpm-macos/config.json",
            MIT_LICENSE,
            ["macos"],
            ["swiftpm-macos"],
            "package-resources",
        ),
    )

    def setUp(self) -> None:
        self.tool = load_tool()

    def test_all_supported_profiles_validate_without_core_changes(self) -> None:
        for relative, license_text, targets, profiles, contract in self.CASES:
            with self.subTest(profile=relative):
                config = load_fixture(f"projects/{relative}")
                with tempfile.TemporaryDirectory() as directory:
                    repo = Path(directory)
                    (repo / "LICENSE").write_text(
                        license_text, encoding="utf-8"
                    )

                    self.tool.validate_config(repo, config)

                self.assertEqual(targets, config["execution"]["target_platforms"])
                self.assertEqual(
                    profiles, config["execution"]["project_profiles"]
                )
                self.assertIn(contract, config["protected_contracts"])
                self.assertTrue(config["commands"]["authorized"])
                self.assertTrue(config["commands"]["prohibited"])
                self.assertTrue(config["project_metadata"])

    def test_windows_linux_and_unknown_profile_fail_closed(self) -> None:
        config = load_fixture("projects/native-xcode/config.json")
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "LICENSE").write_text(MIT_LICENSE, encoding="utf-8")
            execution = copy.deepcopy(config["execution"])
            execution["target_platforms"] = ["linux"]
            config["execution"] = execution
            with self.assertRaisesRegex(self.tool.IntakeError, "target platform"):
                self.tool.validate_config(repo, config)

            execution["target_platforms"] = ["ios"]
            execution["project_profiles"] = ["electron"]
            with self.assertRaisesRegex(self.tool.IntakeError, "project profile"):
                self.tool.validate_config(repo, config)

    def test_skill_git_host_guard_rejects_linux(self) -> None:
        with mock.patch.object(self.tool.platform, "system", return_value="Linux"):
            with self.assertRaisesRegex(self.tool.IntakeError, "macOS Codex host"):
                self.tool.require_macos()

    def test_pure_validation_remains_available_on_hosted_linux_ci(self) -> None:
        config = load_fixture("projects/swiftpm-macos/config.json")
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "LICENSE").write_text(MIT_LICENSE, encoding="utf-8")
            with mock.patch.object(
                self.tool.platform, "system", return_value="Linux"
            ):
                self.tool.validate_config(repo, config)


class EndToEndSimulationTests(unittest.TestCase):
    """A fresh non-Zion fork completes the packaged local workflow."""

    def setUp(self) -> None:
        self.tool = load_tool()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.upstream = self.root / "upstream"
        self.fork = self.root / "fork"
        self.upstream.mkdir()
        self.git(self.upstream, "init", "-q", "-b", "main")
        self.git(self.upstream, "config", "user.name", "E2E Upstream")
        self.git(
            self.upstream,
            "config",
            "user.email",
            "upstream@example.test",
        )
        (self.upstream / "LICENSE").write_text(MIT_LICENSE, encoding="utf-8")
        self.git(self.upstream, "add", "LICENSE")
        self.git(self.upstream, "commit", "-q", "-m", "base")
        self.base = self.git(self.upstream, "rev-parse", "HEAD")
        self.first = self.commit_upstream(
            "Sources/AppFeature.swift",
            "struct AppFeature {}\n",
            "Add app feature (#41)",
        )
        self.second = self.commit_upstream(
            "Sources/OptionalTelemetry.swift",
            "struct OptionalTelemetry {}\n",
            "Add optional telemetry (#42)",
        )
        subprocess.run(
            ["git", "clone", "-q", str(self.upstream), str(self.fork)],
            check=True,
            capture_output=True,
            text=True,
        )
        self.git(self.fork, "config", "user.name", "E2E Fork")
        self.git(self.fork, "config", "user.email", "fork@example.test")
        self.git(self.fork, "checkout", "-q", "-B", "main", self.base)
        self.git(self.fork, "remote", "add", "upstream", str(self.upstream))
        self.git(self.fork, "fetch", "-q", "--no-tags", "upstream", "main")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def git(self, repo: Path, *args: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(repo), *args],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def commit_upstream(self, name: str, content: str, message: str) -> str:
        path = self.upstream / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        self.git(self.upstream, "add", name)
        self.git(self.upstream, "commit", "-q", "-m", message)
        return self.git(self.upstream, "rev-parse", "HEAD")

    def settings(self) -> dict[str, object]:
        return {
            "compatibility_review": "",
            "fork_main_branch": "main",
            "fork_repository": "example/apple-fork",
            "fork_spdx": "MIT",
            "license_files": ["LICENSE"],
            "notice_files": [],
            "project_profiles": ["native-xcode"],
            "reviewed_sha": self.base,
            "target_platforms": ["ios"],
            "upstream_branch": "main",
            "upstream_remote": "upstream",
            "upstream_repository": "example/apple-upstream",
            "upstream_spdx": "MIT",
        }

    def make_reviewed_batch(
        self, report: dict[str, object]
    ) -> dict[str, object]:
        commits = report["commits"]
        topics = report["topics"]
        entries = []
        for index, commit in enumerate(commits):
            accepted = index == 0
            entries.append(
                {
                    "areas": ["ios"],
                    "blocked_by_rejected": [],
                    "decision": "accept" if accepted else "reject",
                    "delivery": "included" if accepted else "not_applicable",
                    "dependencies": [],
                    "dependency_resolution": None,
                    "integration_method": "adapt" if accepted else None,
                    "rationale": (
                        "The fork wants this behavior with local adaptation."
                        if accepted
                        else "The fork intentionally omits optional telemetry."
                    ),
                    "revisit": None,
                    "risk": "low",
                    "security_candidate": False,
                    "security_reasons": [],
                    "title": commit["subject"],
                    "topic_id": commit["topic_id"],
                    "tracking": {
                        "fork_commits": [],
                        "implementation_plan": None,
                        "issue": None,
                        "local_backlog": None,
                        "pull_request": None,
                    },
                    "upstream_sha": commit["sha"],
                    "verification": (
                        ["synthetic focused test"] if accepted else []
                    ),
                }
            )
        return {
            "batch_id": "synthetic-intake",
            "entries": entries,
            "kind": "normal",
            "pinned_upstream_sha": report["pinned_upstream_sha"],
            "previous_reviewed_sha": report["reviewed_through"],
            "reclassifications": [],
            "schema_version": 1,
            "status": "reviewing",
            "topics": topics,
        }

    def test_packaged_skill_completes_fresh_local_intake(self) -> None:
        initialized = self.tool.initialize_project(
            self.fork, self.settings(), apply=True
        )
        self.assertTrue(initialized["applied"])
        self.git(self.fork, "add", ".github", ".upstream-intake")
        self.git(self.fork, "commit", "-q", "-m", "initialize intake")
        vendored = self.fork / ".upstream-intake/tools/upstream_intake.py"

        discovery = subprocess.run(
            [
                "python3",
                str(vendored),
                "discover",
                "--repo",
                str(self.fork),
                "--upstream-ref",
                "upstream/main",
                "--format",
                "json",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        report = json.loads(discovery.stdout)
        self.assertEqual([self.first, self.second], [
            commit["sha"] for commit in report["commits"]
        ])

        batch = self.make_reviewed_batch(report)
        write_json(
            self.fork
            / ".upstream-intake/batches/open/synthetic-intake.json",
            batch,
        )
        state_path = self.fork / ".upstream-intake/state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["last_discovered"] = report["pinned_upstream_sha"]
        state["open_batches"] = ["synthetic-intake"]
        write_json(state_path, state)

        validated = subprocess.run(
            ["python3", str(vendored), "validate", "--repo", str(self.fork)],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertTrue(json.loads(validated.stdout)["ok"])
        rendered = subprocess.run(
            [
                "python3",
                str(vendored),
                "render",
                "--repo",
                str(self.fork),
                "--batch",
                ".upstream-intake/batches/open/synthetic-intake.json",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertIn("Accept: **1**", rendered.stdout)
        self.assertIn("Reject: **1**", rendered.stdout)
        audited = subprocess.run(
            ["python3", str(vendored), "audit", "--repo", str(self.fork)],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertTrue(json.loads(audited.stdout)["ok"])


if __name__ == "__main__":
    unittest.main()
