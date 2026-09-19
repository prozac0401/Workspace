"""RC10 publication preserves exact evidence and cannot silently waive acceptance."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

REPO = Path(__file__).resolve().parents[3]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, REPO / "scripts" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {"markdown": Mock()}):
        spec.loader.exec_module(module)
    return module


gate = load_script("package-excel-wording-release")
builder = load_script("build-excel-onefile")


class RC10PublicationTests(unittest.TestCase):
    def setUp(self):
        self.checks = gate.CHECKS + ("windowState", "upgrade", "contextMenuContent", "nativeContextMenu")
        results = {name: "PASS: synthetic core evidence" if name in gate.RC10_EXCEPTION_CORE_CHECKS
                   else "PARTIAL: actual outstanding scope" for name in self.checks}
        results["wordingAndState"] = "FAIL: unresolved state restoration"
        results["upgrade"] = "NOT_RUN: rebuilt wrapper has not been installed"
        self.validation = {
            "installerVersion": "0.2.0-rc.10", "fullAcceptancePassed": False,
            "releaseProfile": "documented-exceptions", "releaseDecision": "PUBLISH_WITH_RECORDED_RESULTS",
            "checks": results, "xlamSha256": "a" * 64, "installerSha256": "b" * 64,
            "releaseExceptions": {
                "userAuthorized": True, "fullAcceptancePassed": False,
                "decisionRecord": "tools/ExcelSmartListCompare/docs/ADR-0017-RC10-publication.md",
                "acceptedIncompleteChecks": [name for name in self.checks if not results[name].startswith("PASS:")],
            },
        }

    def validate(self):
        return gate.validate_acceptance_profile(self.validation, self.checks, 10, "documented-exceptions")

    def test_publication_preserves_all_actual_results(self):
        before = copy.deepcopy(self.validation)
        self.assertEqual(self.validate(), self.validation["releaseExceptions"]["acceptedIncompleteChecks"])
        self.assertEqual(self.validation, before)

    def test_rc9_authorization_cannot_be_reused(self):
        self.validation["releaseExceptions"].pop("decisionRecord")
        with self.assertRaisesRegex(SystemExit, "own publication decision"):
            self.validate()

    def test_incomplete_acceptance_cannot_be_reclassified(self):
        for value in (True, "false", 0, None):
            with self.subTest(value=value):
                self.validation["fullAcceptancePassed"] = value
                with self.assertRaisesRegex(SystemExit, "incomplete acceptance"):
                    self.validate()

    def test_every_core_check_still_requires_pass(self):
        for name in gate.RC10_EXCEPTION_CORE_CHECKS:
            with self.subTest(name=name):
                original = self.validation["checks"][name]
                self.validation["checks"][name] = "FAIL: no exact evidence"
                with self.assertRaisesRegex(SystemExit, "require PASS for " + name):
                    self.validate()
                self.validation["checks"][name] = original

    def test_authorized_incomplete_set_cannot_be_changed(self):
        self.validation["releaseExceptions"]["acceptedIncompleteChecks"].remove("selectionMatrix")
        with self.assertRaisesRegex(SystemExit, "exactly match"):
            self.validate()

    def test_default_full_gate_remains_strict(self):
        with self.assertRaisesRegex(SystemExit, "explicit documented-exceptions profile"):
            gate.validate_acceptance_profile(self.validation, self.checks, 10, "full")
        for key in ("releaseProfile", "releaseDecision", "releaseExceptions"):
            self.validation.pop(key)
        with self.assertRaisesRegex(SystemExit, "incomplete or failed"):
            gate.validate_acceptance_profile(self.validation, self.checks, 10, "full")

    def test_wrapper_requires_unchanged_evidence_and_matching_payload(self):
        with tempfile.TemporaryDirectory(dir=REPO / "artifacts") as directory:
            evidence = Path(directory) / "validation.json"
            evidence.write_text(json.dumps(self.validation), encoding="utf-8")
            pins = {
                "releaseDecision": "PUBLISH_WITH_RECORDED_RESULTS", "fullAcceptancePassed": False,
                "validationSha256": builder.sha256(evidence),
                "sha256": {"ExcelSmartListCompare.xlam": "a" * 64, "Setup.ps1": "b" * 64},
            }
            with patch.object(builder, "RC10_VALIDATION", evidence), patch.dict(sys.modules, {"markdown": Mock()}):
                builder.validate_rc10_publication(pins)
                for filename in pins["sha256"]:
                    altered = copy.deepcopy(pins)
                    altered["sha256"][filename] = "c" * 64
                    with self.assertRaisesRegex(SystemExit, "does not match the selected payload"):
                        builder.validate_rc10_publication(altered)
                evidence.write_text(json.dumps({**self.validation, "fullAcceptancePassed": True}), encoding="utf-8")
                with self.assertRaisesRegex(SystemExit, "pinned matching decision evidence"):
                    builder.validate_rc10_publication(pins)


if __name__ == "__main__":
    unittest.main()
