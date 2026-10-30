import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[2] / "Scripts" / "docsec.py"
SPEC = importlib.util.spec_from_file_location("docsec", SCRIPT)
docsec = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(docsec)


class DocSecTests(unittest.TestCase):
    def test_reports_incomplete_acceptance_and_verification_gates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "PRODUCT_REQUIREMENTS.md").write_text(
                "## Acceptance criteria\n- User can browse projects.\n", encoding="utf-8"
            )
            (root / "IMPLEMENTATION_STATUS.md").write_text(
                "## Acceptance criteria\n- [ ] AC-01 — User can browse projects. Evidence: pending\n\n"
                "## Verification gates\n- [ ] Build — Evidence: pending\n- [ ] Unit tests — Evidence: pending\n- [ ] End-to-end — Evidence: pending\n",
                encoding="utf-8",
            )

            report = docsec.audit(root)

        self.assertFalse(report.ready)
        self.assertEqual(1, report.incomplete_acceptance)
        self.assertEqual(["Build", "Unit tests", "End-to-end"], report.pending_gates)

    def test_accepts_complete_rows_with_evidence_and_all_gates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            criterion = "User can browse projects."
            (root / "PRODUCT_REQUIREMENTS.md").write_text(
                "## Acceptance criteria\n- " + criterion + "\n", encoding="utf-8"
            )
            (root / "IMPLEMENTATION_STATUS.md").write_text(
                "## Acceptance criteria\n- [x] AC-01 — " + criterion + " Evidence: UI test\n\n"
                "## Verification gates\n- [x] Build — Evidence: Build log\n- [x] Unit tests — Evidence: Test report\n- [x] End-to-end — Evidence: UI test\n",
                encoding="utf-8",
            )

            report = docsec.audit(root)

        self.assertTrue(report.ready)
        self.assertEqual(0, report.incomplete_acceptance)
        self.assertEqual([], report.pending_gates)

    def test_rejects_requirement_drift_and_removed_e2e_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "PRODUCT_REQUIREMENTS.md").write_text(
                "## Acceptance criteria\n- User can browse projects.\n", encoding="utf-8"
            )
            (root / "IMPLEMENTATION_STATUS.md").write_text(
                "## Acceptance criteria\n- [x] AC-01 — User can browse repositories. Evidence: UI test\n\n"
                "## Verification gates\n- [x] Build — Evidence: build log\n"
                "- [x] Unit tests — Evidence: test report\n",
                encoding="utf-8",
            )

            report = docsec.audit(root)

        self.assertFalse(report.ready)
        self.assertIn("AC-01 text differs from PRODUCT_REQUIREMENTS.md", report.errors)
        self.assertIn("Verification gates must be exactly: Build, Unit tests, End-to-end", report.errors)
        self.assertEqual(["End-to-end"], report.pending_gates)


if __name__ == "__main__":
    unittest.main()
