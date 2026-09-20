"""R11 cannot inherit an earlier release waiver or skip an essential result."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from test_rc10_publication import gate, builder


class R11PublicationTests(unittest.TestCase):
    def setUp(self):
        self.checks = gate.CHECKS + ("windowState", "upgrade", "contextMenuContent", "nativeContextMenu") + gate.R11_EXTRA_CHECKS
        results = {name: "PASS: synthetic essential evidence" if name in gate.R11_EXCEPTION_CORE_CHECKS
                   else "NOT_RUN: user verification after release" for name in self.checks}
        self.value = {
            "installerVersion": "0.2.0-rc.11", "fullAcceptancePassed": False,
            "releaseProfile": "documented-exceptions", "releaseDecision": "PUBLISH_WITH_RECORDED_RESULTS",
            "checks": results, "xlamSha256": "a" * 64, "installerSha256": "b" * 64,
            "releaseExceptions": {
                "userAuthorized": True, "fullAcceptancePassed": False,
                "decisionRecord": "tools/ExcelSmartListCompare/docs/ADR-0019-R11-release-scope.md",
                "acceptedIncompleteChecks": [name for name, value in results.items() if not value.startswith("PASS:")],
            },
        }

    def validate(self):
        return gate.validate_acceptance_profile(self.value, self.checks, 11, "documented-exceptions")

    def test_records_deferred_checks_without_reclassifying_them(self):
        before = copy.deepcopy(self.value)
        self.assertEqual(self.validate(), self.value["releaseExceptions"]["acceptedIncompleteChecks"])
        self.assertEqual(before, self.value)

    def test_every_r11_essential_check_requires_pass(self):
        for name in gate.R11_EXCEPTION_CORE_CHECKS:
            with self.subTest(name=name):
                old = self.value["checks"][name]
                self.value["checks"][name] = "NOT_RUN: pending"
                with self.assertRaisesRegex(SystemExit, "require PASS for " + name):
                    self.validate()
                self.value["checks"][name] = old

    def test_rc10_decision_cannot_authorize_r11(self):
        self.value["releaseExceptions"]["decisionRecord"] = "tools/ExcelSmartListCompare/docs/ADR-0017-RC10-publication.md"
        with self.assertRaisesRegex(SystemExit, "own publication decision"):
            self.validate()

    def test_full_acceptance_cannot_be_claimed(self):
        self.value["fullAcceptancePassed"] = True
        with self.assertRaisesRegex(SystemExit, "incomplete acceptance"):
            self.validate()

    def test_wrapper_pins_the_exact_r11_validation_and_payload(self):
        with tempfile.TemporaryDirectory(dir=gate.REPO / "artifacts") as directory:
            evidence = Path(directory) / "validation.json"
            evidence.write_text(json.dumps(self.value), encoding="utf-8")
            pins = {"releaseDecision": "PUBLISH_WITH_RECORDED_RESULTS", "fullAcceptancePassed": False,
                    "validationSha256": builder.sha256(evidence),
                    "sha256": {"ExcelSmartListCompare.xlam": "a" * 64, "Setup.ps1": "b" * 64}}
            with patch.object(builder, "RC11_VALIDATION", evidence):
                builder.validate_rc11_publication(pins)
                pins["sha256"]["ExcelSmartListCompare.xlam"] = "c" * 64
                with self.assertRaisesRegex(SystemExit, "does not match"):
                    builder.validate_rc11_publication(pins)

    def test_r11_reports_are_separate_from_the_user_package(self):
        names, report = gate.release_report_layout(11)
        self.assertEqual(names["RC11_USER_VALIDATION.md"], "User-Validation.html")
        self.assertEqual(names["RC11_TEST_REPORT.md"], report)
        self.assertEqual(gate.release_user_guide(11), "RC11_USER_GUIDE.md")
        self.assertEqual(len(names.values()), len(set(names.values())))


if __name__ == "__main__":
    unittest.main()
