#!/usr/bin/env python3
"""Check that every PRD acceptance item has tracked, evidenced completion."""

import re
import sys
from pathlib import Path
from typing import NamedTuple


class Audit(NamedTuple):
    ready: bool
    incomplete_acceptance: int
    pending_gates: list
    errors: list


REQUIRED_GATES = ("Build", "Unit tests", "End-to-end")


def section(text, heading):
    match = re.search(r"^## " + re.escape(heading) + r"\s*$([\s\S]*?)(?=^## |\Z)", text, re.M)
    return match.group(1) if match else None


def audit(root):
    root = Path(root)
    requirements_path = root / "PRODUCT_REQUIREMENTS.md"
    status_path = root / "IMPLEMENTATION_STATUS.md"
    errors = []
    if not requirements_path.is_file() or not status_path.is_file():
        return Audit(False, 0, [], ["Missing PRODUCT_REQUIREMENTS.md or IMPLEMENTATION_STATUS.md"])

    requirements = section(requirements_path.read_text(encoding="utf-8"), "Acceptance criteria")
    status = status_path.read_text(encoding="utf-8")
    status_criteria = section(status, "Acceptance criteria")
    gates = section(status, "Verification gates")
    if requirements is None or status_criteria is None or gates is None:
        return Audit(False, 0, [], ["Required Acceptance criteria or Verification gates section is missing"])

    criteria = [line[2:].strip() for line in requirements.splitlines() if line.startswith("- ")]
    rows = {}
    acceptance_rows = re.findall(
        r"^- \[([ x])\] AC-(\d+) — (.+?)\s*$", status_criteria, re.M
    )
    for checked, number, row_text in acceptance_rows:
        criterion, separator, evidence = row_text.partition(" Evidence:")
        rows[int(number)] = (checked == "x", evidence.strip() if separator else "")
    # Require one status row per source criterion; rows cannot silently drift from the PRD.
    expected = set(range(1, len(criteria) + 1))
    if set(rows) != expected or len(rows) != len(acceptance_rows):
        errors.append("Acceptance rows must cover AC-01 through AC-%02d" % len(criteria))
    for index, criterion in enumerate(criteria, 1):
        row = re.search(r"^- \[[ x]\] AC-%02d — (.+?) Evidence:" % index, status_criteria, re.M)
        if not row or row.group(1) != criterion:
            errors.append("AC-%02d text differs from PRODUCT_REQUIREMENTS.md" % index)

    incomplete = sum(
        not complete or not evidence or evidence.lower().startswith("pending")
        for complete, evidence in rows.values()
    )
    gate_rows = {}
    parsed_gates = re.findall(r"^- \[([ x])\] (.+?) — Evidence: (.*)$", gates, re.M)
    for checked, name, evidence in parsed_gates:
        gate_rows[name] = (checked == "x", (evidence or "").strip())
    if set(gate_rows) != set(REQUIRED_GATES) or len(gate_rows) != len(parsed_gates):
        errors.append("Verification gates must be exactly: " + ", ".join(REQUIRED_GATES))
    pending = [
        name for name in REQUIRED_GATES
        if name not in gate_rows or not gate_rows[name][0] or not gate_rows[name][1]
        or gate_rows[name][1].lower().startswith("pending")
    ]
    return Audit(not errors and incomplete == 0 and not pending, incomplete, pending, errors)


def main():
    report = audit(Path(__file__).resolve().parents[1])
    print("DocSec: " + ("ready" if report.ready else "incomplete"))
    print("Acceptance criteria incomplete: %d" % report.incomplete_acceptance)
    print("Verification gates pending: " + (", ".join(report.pending_gates) or "none"))
    for error in report.errors:
        print("Error: " + error)
    if not report.ready:
        print("Completion status requires reviewed evidence; this checker does not validate claims or execute tests.")
    return 0 if report.ready else 1


if __name__ == "__main__":
    sys.exit(main())
