#!/usr/bin/env python3

"""Enforce Zion's temporary cargo-deny exception as a fail-closed policy."""

import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import date, datetime, timezone


TRACKED_ADVISORY = "RUSTSEC-2026-0243"
TRACKED_PACKAGE = "nostr-relay-pool"
EXCEPTION_EXPIRES = date(2026, 9, 3)
POLICY_CHECKS = ("advisories", "bans", "licenses", "sources")
POLICY_FAILURE_EXIT_CODE = 1
TRACKER_URL = (
    "https://linear.app/mi8/issue/MI8-23/"
    "security-retire-unmaintained-nostr-relay-pool-from-mesh-dependencies"
)


@dataclass(frozen=True)
class PolicyDecision:
    """Result of evaluating one cargo-deny JSON report."""

    allowed: bool
    reason: str
    advisory_ids: tuple[str, ...]


def evaluate_dependency_policy(
    output: str,
    *,
    command_exit_code: int,
    today: date,
) -> PolicyDecision:
    """Return whether a complete cargo-deny report satisfies Zion policy."""

    diagnostics: list[dict[str, object]] = []
    summary_errors: dict[str, int] | None = None

    for line_number, line in enumerate(output.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            return PolicyDecision(
                False,
                f"cargo-deny emitted malformed JSON on line {line_number}",
                (),
            )

        if not isinstance(record, dict):
            return PolicyDecision(
                False,
                f"cargo-deny JSON record on line {line_number} is not a JSON object",
                (),
            )

        record_type = record.get("type")
        if record_type not in ("diagnostic", "summary"):
            return PolicyDecision(
                False,
                f"cargo-deny emitted an unknown record type on line {line_number}",
                (),
            )

        fields = record.get("fields")
        if record_type == "summary":
            if not isinstance(fields, dict):
                return PolicyDecision(
                    False,
                    f"cargo-deny emitted a malformed summary on line {line_number}",
                    (),
                )
            if summary_errors is not None:
                return PolicyDecision(
                    False,
                    "cargo-deny must emit exactly one summary",
                    (),
                )
            if set(fields) != set(POLICY_CHECKS):
                return PolicyDecision(
                    False,
                    "cargo-deny did not emit a complete summary for "
                    + ", ".join(POLICY_CHECKS),
                    (),
                )

            parsed_errors: dict[str, int] = {}
            for check_name in POLICY_CHECKS:
                check_result = fields[check_name]
                if not isinstance(check_result, dict):
                    return PolicyDecision(
                        False,
                        f"cargo-deny summary {check_name} is malformed",
                        (),
                    )
                errors = check_result.get("errors")
                if type(errors) is not int or errors < 0:
                    return PolicyDecision(
                        False,
                        f"cargo-deny summary {check_name}.errors must be a nonnegative integer",
                        (),
                    )
                parsed_errors[check_name] = errors
            summary_errors = parsed_errors
            continue

        if not isinstance(fields, dict) or not isinstance(fields.get("severity"), str):
            return PolicyDecision(
                False,
                f"cargo-deny emitted a malformed diagnostic on line {line_number}",
                (),
            )
        if fields["severity"] == "error":
            diagnostics.append(fields)

    advisory_ids = tuple(
        sorted(
            {
                advisory["id"]
                for fields in diagnostics
                if isinstance((advisory := fields.get("advisory")), dict)
                and isinstance(advisory.get("id"), str)
            }
        )
    )

    if summary_errors is None:
        return PolicyDecision(False, "cargo-deny completed without a summary", advisory_ids)

    if command_exit_code not in (0, POLICY_FAILURE_EXIT_CODE):
        return PolicyDecision(
            False,
            f"cargo-deny returned unexpected exit code {command_exit_code}",
            advisory_ids,
        )

    if any(summary_errors.values()) and not diagnostics:
        return PolicyDecision(
            False,
            "cargo-deny reported errors without an error diagnostic",
            advisory_ids,
        )

    if not diagnostics:
        if command_exit_code == 0:
            return PolicyDecision(True, "dependency policy passed", ())
        return PolicyDecision(
            False,
            "cargo-deny failed without a recognized error diagnostic",
            advisory_ids,
        )

    if command_exit_code == 0:
        return PolicyDecision(
            False,
            "cargo-deny emitted error diagnostics with a successful exit",
            advisory_ids,
        )

    if len(diagnostics) != 1:
        return PolicyDecision(
            False,
            "temporary exception requires exactly one dependency policy error",
            advisory_ids,
        )

    unexpected_errors: list[str] = []
    for fields in diagnostics:
        advisory = fields.get("advisory")
        if not isinstance(advisory, dict):
            unexpected_errors.append(str(fields.get("code", "unknown error")))
            continue

        advisory_id = advisory.get("id")
        package = advisory.get("package")
        if (
            fields.get("code") != "unmaintained"
            or advisory_id != TRACKED_ADVISORY
            or package != TRACKED_PACKAGE
        ):
            unexpected_errors.append(
                f"{advisory_id or fields.get('code', 'unknown error')} ({package or 'unknown package'})"
            )

    if unexpected_errors:
        return PolicyDecision(
            False,
            "unexpected dependency policy errors: " + ", ".join(unexpected_errors),
            advisory_ids,
        )

    expected_summary_errors = dict.fromkeys(POLICY_CHECKS, 0)
    expected_summary_errors["advisories"] = 1
    if summary_errors != expected_summary_errors:
        return PolicyDecision(
            False,
            "temporary exception requires advisories.errors=1 and all other policy errors=0",
            advisory_ids,
        )

    if today > EXCEPTION_EXPIRES:
        return PolicyDecision(
            False,
            f"{TRACKED_ADVISORY} exception expired on {EXCEPTION_EXPIRES.isoformat()}",
            advisory_ids,
        )

    return PolicyDecision(
        True,
        (
            f"temporary exception active for {TRACKED_ADVISORY} through "
            f"{EXCEPTION_EXPIRES.isoformat()} ({TRACKER_URL})"
        ),
        advisory_ids,
    )


def main() -> int:
    try:
        result = subprocess.run(
            ["cargo-deny", "--format", "json", "check"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        print(f"dependency policy failed: could not run cargo-deny: {error}", file=sys.stderr)
        return 1

    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)

    decision = evaluate_dependency_policy(
        "\n".join(part for part in (result.stdout, result.stderr) if part),
        command_exit_code=result.returncode,
        today=datetime.now(timezone.utc).date(),
    )
    stream = sys.stdout if decision.allowed else sys.stderr
    print(f"dependency policy: {decision.reason}", file=stream)
    return 0 if decision.allowed else 1


if __name__ == "__main__":
    raise SystemExit(main())
