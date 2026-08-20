import unittest
from datetime import date

from scripts.check_dependency_policy import evaluate_dependency_policy


KNOWN_ADVISORY = """
{"type":"diagnostic","fields":{"severity":"error","code":"unmaintained","advisory":{"id":"RUSTSEC-2026-0243","package":"nostr-relay-pool"}}}
{"type":"summary","fields":{"advisories":{"errors":1,"warnings":3},"bans":{"errors":0},"licenses":{"errors":0},"sources":{"errors":0}}}
""".strip()

KNOWN_ADVISORY_WITH_WARNING = """
{"type":"diagnostic","fields":{"severity":"error","code":"unmaintained","advisory":{"id":"RUSTSEC-2026-0243","package":"nostr-relay-pool"}}}
{"type":"diagnostic","fields":{"severity":"warning","code":"yanked"}}
{"type":"summary","fields":{"advisories":{"errors":1,"warnings":1},"bans":{"errors":0},"licenses":{"errors":0},"sources":{"errors":0}}}
""".strip()

UNKNOWN_ADVISORY = """
{"type":"diagnostic","fields":{"severity":"error","code":"vulnerability","advisory":{"id":"RUSTSEC-2099-0001","package":"unexpected-crate"}}}
{"type":"summary","fields":{"advisories":{"errors":1},"bans":{"errors":0},"licenses":{"errors":0},"sources":{"errors":0}}}
""".strip()

NON_ADVISORY_ERROR = """
{"type":"diagnostic","fields":{"severity":"error","code":"banned","message":"crate is explicitly banned"}}
{"type":"summary","fields":{"advisories":{"errors":0},"bans":{"errors":1},"licenses":{"errors":0},"sources":{"errors":0}}}
""".strip()

CLEAN_RESULT = (
    '{"type":"summary","fields":{"advisories":{"errors":0},'
    '"bans":{"errors":0},"licenses":{"errors":0},"sources":{"errors":0}}}'
)


class DependencyPolicyTest(unittest.TestCase):
    def test_accepts_only_tracked_advisory_before_expiry(self):
        decision = evaluate_dependency_policy(
            KNOWN_ADVISORY,
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertTrue(decision.allowed)
        self.assertEqual(decision.advisory_ids, ("RUSTSEC-2026-0243",))

    def test_accepts_tracked_advisory_on_expiry_date(self):
        decision = evaluate_dependency_policy(
            KNOWN_ADVISORY,
            command_exit_code=1,
            today=date(2026, 9, 3),
        )

        self.assertTrue(decision.allowed)

    def test_rejects_tracked_advisory_when_command_reports_success(self):
        decision = evaluate_dependency_policy(
            KNOWN_ADVISORY,
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("successful exit", decision.reason)

    def test_rejects_abnormal_cargo_deny_exit(self):
        decision = evaluate_dependency_policy(
            KNOWN_ADVISORY,
            command_exit_code=101,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("unexpected exit code 101", decision.reason)

    def test_rejects_more_than_the_single_tracked_error(self):
        output = "\n".join(
            (
                KNOWN_ADVISORY.splitlines()[0],
                KNOWN_ADVISORY.splitlines()[0],
                '{"type":"summary","fields":{"advisories":{"errors":2},'
                '"bans":{"errors":0},"licenses":{"errors":0},'
                '"sources":{"errors":0}}}',
            )
        )
        decision = evaluate_dependency_policy(
            output,
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("exactly one", decision.reason)

    def test_rejects_tracked_advisory_after_expiry(self):
        decision = evaluate_dependency_policy(
            KNOWN_ADVISORY,
            command_exit_code=1,
            today=date(2026, 9, 4),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("expired", decision.reason)

    def test_rejects_any_other_advisory(self):
        decision = evaluate_dependency_policy(
            UNKNOWN_ADVISORY,
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("RUSTSEC-2099-0001", decision.reason)

    def test_rejects_tracked_advisory_for_an_unexpected_package(self):
        output = """
{"type":"diagnostic","fields":{"severity":"error","code":"unmaintained","advisory":{"id":"RUSTSEC-2026-0243","package":"unexpected-crate"}}}
{"type":"summary","fields":{"advisories":{"errors":1},"bans":{"errors":0},"licenses":{"errors":0},"sources":{"errors":0}}}
""".strip()

        decision = evaluate_dependency_policy(
            output,
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("unexpected-crate", decision.reason)

    def test_rejects_non_advisory_policy_errors(self):
        decision = evaluate_dependency_policy(
            NON_ADVISORY_ERROR,
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("banned", decision.reason)

    def test_rejects_error_in_wrong_summary_category(self):
        output = "\n".join(
            (
                KNOWN_ADVISORY.splitlines()[0],
                '{"type":"summary","fields":{"advisories":{"errors":0},'
                '"bans":{"errors":1},"licenses":{"errors":0},'
                '"sources":{"errors":0}}}',
            )
        )
        decision = evaluate_dependency_policy(
            output,
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("advisories", decision.reason)

    def test_rejects_malformed_json(self):
        decision = evaluate_dependency_policy(
            '{"type":"diagnostic"',
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("malformed", decision.reason)

    def test_rejects_non_object_json_record(self):
        decision = evaluate_dependency_policy(
            "[]",
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("JSON object", decision.reason)

    def test_rejects_unknown_json_record_type(self):
        decision = evaluate_dependency_policy(
            '{"type":"progress","fields":{}}\n' + CLEAN_RESULT,
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("unknown record type", decision.reason)

    def test_rejects_failed_command_without_error_diagnostics(self):
        decision = evaluate_dependency_policy(
            CLEAN_RESULT,
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("without a recognized error", decision.reason)

    def test_rejects_success_without_a_summary(self):
        decision = evaluate_dependency_policy(
            "",
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("without a summary", decision.reason)

    def test_rejects_summary_missing_policy_checks(self):
        decision = evaluate_dependency_policy(
            '{"type":"summary","fields":{"advisories":{"errors":0}}}',
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("complete summary", decision.reason)

    def test_rejects_duplicate_summaries(self):
        decision = evaluate_dependency_policy(
            "\n".join((CLEAN_RESULT, CLEAN_RESULT)),
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("exactly one summary", decision.reason)

    def test_rejects_malformed_summary_error_count(self):
        decision = evaluate_dependency_policy(
            '{"type":"summary","fields":{"advisories":{"errors":"0"},'
            '"bans":{"errors":0},"licenses":{"errors":0},'
            '"sources":{"errors":0}}}',
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("nonnegative integer", decision.reason)

    def test_rejects_unknown_summary_check(self):
        decision = evaluate_dependency_policy(
            '{"type":"summary","fields":{"advisories":{"errors":0},'
            '"bans":{"errors":0},"licenses":{"errors":0},'
            '"sources":{"errors":0},"future":{"errors":0}}}',
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("complete summary", decision.reason)

    def test_rejects_error_summary_without_diagnostics(self):
        decision = evaluate_dependency_policy(
            '{"type":"summary","fields":{"advisories":{"errors":1},'
            '"bans":{"errors":0},"licenses":{"errors":0},"sources":{"errors":0}}}',
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertFalse(decision.allowed)
        self.assertIn("without an error diagnostic", decision.reason)

    def test_accepts_clean_dependency_policy(self):
        decision = evaluate_dependency_policy(
            CLEAN_RESULT,
            command_exit_code=0,
            today=date(2026, 8, 20),
        )

        self.assertTrue(decision.allowed)
        self.assertEqual(decision.advisory_ids, ())

    def test_ignores_warnings_when_only_error_is_tracked_advisory(self):
        decision = evaluate_dependency_policy(
            KNOWN_ADVISORY_WITH_WARNING,
            command_exit_code=1,
            today=date(2026, 8, 20),
        )

        self.assertTrue(decision.allowed)


if __name__ == "__main__":
    unittest.main()
