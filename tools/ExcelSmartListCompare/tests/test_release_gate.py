"""Full RC9 acceptance stays mandatory unless a bounded evaluation is explicit."""
import contextlib
import copy
import hashlib
import io
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import Mock, patch

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "slc_release_gate", REPO / "scripts/package-excel-wording-release.py"
)
gate = importlib.util.module_from_spec(spec)
# Rejection must happen before HTML generation. Keep these early-gate tests
# independent of the optional MkDocs/Markdown documentation environment.
markdown_stub = Mock()
markdown_stub.markdown.side_effect = AssertionError("Rendering an unaccepted release")
with patch.dict(sys.modules, {"markdown": markdown_stub}):
    spec.loader.exec_module(gate)


class RC9ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="rc9-gate-", dir=REPO / "artifacts")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.xlam = self.root / "synthetic.xlam"
        self.xlam.write_bytes(b"Synthetic pre-validation fixture; never installed.")
        self.output = self.root / "release"
        self.validation = {
            "installerVersion": "0.2.0-rc.9",
            "xlamSha256": hashlib.sha256(self.xlam.read_bytes()).hexdigest(),
            "installerSha256": gate.sha256(gate.TOOL / "Setup.ps1"),
            "checks": {name: "PASS: synthetic gate fixture" for name in gate.CHECKS + (
                "windowState", "upgrade", "contextMenuContent", "nativeContextMenu")},
        }

    def reject(self, expected, profile=None):
        manifest = self.root / "validation.json"
        manifest.write_text(json.dumps(self.validation), encoding="utf-8")
        argv = ["package", "--installer-version", "0.2.0-rc.9", "--xlam", str(self.xlam),
                "--validation", str(manifest), "--output-directory", str(self.output)]
        if profile is not None:
            argv += ["--release-profile", profile]
        # A clean source tree is an independent gate; isolate acceptance here.
        with patch.object(sys, "argv", argv), patch.object(gate, "git", return_value=""), \
                self.assertRaisesRegex(SystemExit, expected):
            gate.main()
        self.assertFalse(self.output.exists())

    def test_injected_cancellation_cannot_replace_native_esc(self):
        self.validation["checks"]["cancellation"] = "NOT_RUN: only cooperative injection passed"
        self.reject("cancellation needs a result")

    def test_missing_ui_tool_does_not_waive_native_menu(self):
        self.validation["checks"]["nativeContextMenu"] = "NEEDS_MANUAL: no UI tool"
        self.reject("nativeContextMenu needs a result")

    def test_first_install_failure_remains_a_release_failure(self):
        self.validation["checks"]["reinstall"] = "FAIL: first install denied, retry succeeded"
        self.reject("Required validation is incomplete or failed")

    def limited_manifest(self):
        self.validation.update({"status": "BLOCKED_ENVIRONMENT", "releaseProfile": "limited-evaluation",
                                "releaseDecision": "LIMITED_EVALUATION"})
        incomplete = {
            "wordingAndState": "FAIL: default status restoration unresolved",
            "cancellation": "PARTIAL: controlled replacement only",
            "autoLoad": "NOT_RUN: normal-start acceptance pending",
            "reinstall": "NOT_RUN: final package not installed",
            "uninstall": "NOT_RUN: final package not uninstalled",
            "windowState": "NOT_RUN: complete window matrix pending",
            "upgrade": "NOT_RUN: final installer not upgraded",
            "contextMenuContent": "PARTIAL: three native contexts only",
        }
        self.validation["checks"].update(incomplete)
        self.validation["limitedEvaluation"] = {
            "userAuthorized": True, "notForProduction": True,
            "acceptedIncompleteChecks": list(incomplete),
        }

    def test_limited_cli_alone_cannot_waive_acceptance(self):
        self.validation["checks"]["wordingAndState"] = "FAIL: unresolved"
        self.reject("explicit matching user-authorized decision", "limited-evaluation")

    def test_limited_metadata_alone_cannot_change_default_full_profile(self):
        self.limited_manifest()
        self.reject("requires the explicit limited-evaluation profile")
        for name in self.validation["checks"]:
            self.validation["checks"][name] = "PASS: incorrectly relabeled fixture"
        self.reject("requires the explicit limited-evaluation profile")

    def test_limited_requires_actual_boolean_authorization(self):
        for value in (False, "true", 1, None):
            with self.subTest(authorization=value):
                self.limited_manifest()
                self.validation["limitedEvaluation"]["userAuthorized"] = value
                self.reject("explicit matching user-authorized decision", "limited-evaluation")

    def test_limited_still_requires_each_core_check(self):
        self.limited_manifest()
        baseline = copy.deepcopy(self.validation)
        for name in ("sourceMatchesBinary", "normalizationAndIntegration", "selectionMatrix", "nativeContextMenu", "python", "docs"):
            with self.subTest(check=name):
                self.validation = copy.deepcopy(baseline)
                self.validation["checks"][name] = "FAIL: no accepted core proof"
                self.validation["limitedEvaluation"]["acceptedIncompleteChecks"].append(name)
                self.reject("Limited evaluation requires PASS for " + name, "limited-evaluation")

    def test_limited_requires_all_fourteen_named_checks(self):
        for change in ("missing", "extra"):
            with self.subTest(change=change):
                self.limited_manifest()
                if change == "missing":
                    del self.validation["checks"]["uninstall"]
                else:
                    self.validation["checks"]["unreviewedGate"] = "PASS: not part of this profile"
                self.reject("Required validation is incomplete or failed", "limited-evaluation")
                # Reset the check shape for the next independent subcase.
                self.validation["checks"].pop("unreviewedGate", None)

    def test_limited_requires_matching_decision_and_nonproduction_scope(self):
        for change in ("decision", "scope", "profile"):
            with self.subTest(change=change):
                self.limited_manifest()
                if change == "decision":
                    self.validation["releaseDecision"] = "HOLD"
                elif change == "scope":
                    self.validation["limitedEvaluation"]["notForProduction"] = False
                else:
                    self.validation["releaseProfile"] = "full"
                self.reject("explicit matching user-authorized decision", "limited-evaluation")

    def test_limited_requires_exact_unchanged_incomplete_check_set(self):
        for change in ("missing", "extra", "duplicate", "relabel", "unknown"):
            with self.subTest(change=change):
                self.limited_manifest()
                accepted = self.validation["limitedEvaluation"]["acceptedIncompleteChecks"]
                if change == "missing":
                    accepted.pop()
                elif change == "extra":
                    accepted.append("docs")
                elif change == "duplicate":
                    accepted.append(accepted[0])
                elif change == "relabel":
                    self.validation["checks"]["wordingAndState"] = "PASS: relabeled without updating the reviewed decision"
                else:
                    self.validation["checks"]["cancellation"] = "MAYBE: no classified outcome"
                self.reject("Unknown limited evaluation check status" if change == "unknown" else "exactly match", "limited-evaluation")

    def test_limited_keeps_exact_file_source_and_installer_gates(self):
        self.limited_manifest()
        baseline = copy.deepcopy(self.validation)
        for field, expected in (("xlamSha256", "exact XLAM"), ("installerSha256", "Installer changed"),
                                ("sourceTextSha256", "Sources have changed")):
            with self.subTest(field=field):
                self.validation = copy.deepcopy(baseline)
                self.validation[field] = {} if field == "sourceTextSha256" else "0" * 64
                self.reject(expected, "limited-evaluation")

    def test_limited_is_not_available_for_earlier_releases(self):
        self.limited_manifest()
        with self.assertRaisesRegex(SystemExit, "defined only for RC9"):
            gate.validate_acceptance_profile(self.validation, tuple(self.validation["checks"]), 8, "limited-evaluation")

    def make_package_fixture(self, readme_marker=True):
        """Synthetic package bytes only; no Excel, installer, or VBA execution."""
        tool = self.root / "tool"
        (tool / "src").mkdir(parents=True)
        (tool / "docs").mkdir()
        sources = gate.SOURCES + ("src/CSLCAppEvents.cls", "src/customUI14.xml")
        for name in sources + ("Install.cmd", "Uninstall.cmd", "Test_Excel.cmd", "Setup.ps1"):
            (tool / name).write_bytes((gate.TOOL / name).read_bytes())
        readme = ("LIMITED EVALUATION\n" if readme_marker else "") + "Synthetic package regression fixture.\n"
        (tool / "docs/RELEASE_README.md").write_bytes(readme.encode("utf-8"))
        for name in gate.release_report_layout(9)[0]:
            (tool / "docs" / name).write_text("# Synthetic report\n", encoding="utf-8")
        with zipfile.ZipFile(self.xlam, "w") as archive:
            archive.writestr("customUI/customUI14.xml", (tool / "src/customUI14.xml").read_bytes())
            archive.writestr("_rels/.rels", '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="ui" Type="http://schemas.microsoft.com/office/2007/relationships/ui/extensibility" Target="customUI/customUI14.xml"/></Relationships>')
            archive.writestr("[Content_Types].xml", '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/customUI/customUI14.xml" ContentType="application/xml"/></Types>')
        self.limited_manifest()
        self.validation["xlamSha256"] = gate.sha256(self.xlam)
        self.validation["installerSha256"] = gate.sha256(tool / "Setup.ps1")
        self.validation["sourceTextSha256"] = {name: gate.text_hash((tool / name).read_bytes()) for name in sources}
        return tool, sources

    def test_limited_requires_source_readme_notice_before_writing_output(self):
        tool, _ = self.make_package_fixture(readme_marker=False)
        with patch.object(gate, "TOOL", tool):
            self.reject("visible LIMITED EVALUATION marker", "limited-evaluation")

    def test_limited_package_preserves_raw_failures_readme_bytes_and_identity(self):
        tool, sources = self.make_package_fixture()
        manifest = self.root / "validation.json"
        manifest.write_text(json.dumps(self.validation), encoding="utf-8")
        before = manifest.read_bytes()
        commit = "a" * 40
        argv = ["package", "--installer-version", "0.2.0-rc.9", "--release-profile", "limited-evaluation",
                "--xlam", str(self.xlam), "--validation", str(manifest), "--output-directory", str(self.output)]

        def fake_git(*args):
            return "" if args[0] in {"status", "cat-file"} else commit

        def fake_render(source, output, source_commit, **kwargs):
            self.assertEqual(source_commit, commit)
            output.write_text("<html><body>synthetic report</body></html>", encoding="utf-8")

        def fake_archive(command, **kwargs):
            self.assertEqual(command[:3], ["git", "archive", "--format=zip"])
            target = Path(next(arg.removeprefix("--output=") for arg in command if arg.startswith("--output=")))
            prefix = next(arg.removeprefix("--prefix=") for arg in command if arg.startswith("--prefix="))
            with zipfile.ZipFile(target, "w") as archive:
                for name in sources + ("Install.cmd", "Uninstall.cmd", "Test_Excel.cmd", "Setup.ps1"):
                    archive.writestr(prefix + "tools/ExcelSmartListCompare/" + name, (tool / name).read_bytes())

        with patch.object(sys, "argv", argv), patch.object(gate, "TOOL", tool), \
                patch.object(gate, "git", side_effect=fake_git), patch.object(gate.rendering, "render", side_effect=fake_render), \
                patch.object(gate.subprocess, "run", side_effect=fake_archive), contextlib.redirect_stdout(io.StringIO()):
            gate.main()
        self.assertEqual(manifest.read_bytes(), before)
        install = self.output / "ExcelSmartListCompare-0.2.0-rc.9-limited-evaluation-win-x64.zip"
        self.assertTrue((self.output / "ExcelSmartListCompare-0.2.0-rc.9-limited-evaluation-Source.zip").is_file())
        with zipfile.ZipFile(install) as archive:
            self.assertEqual(json.loads(archive.read("Release/Validation.json")), self.validation)
            self.assertEqual(archive.read("Release/README.md"), (tool / "docs/RELEASE_README.md").read_bytes())
            self.assertEqual(archive.read("Release/ExcelSmartListCompare.xlam"), self.xlam.read_bytes())
            info = json.loads(archive.read("Release/BUILD_INFO.json"))
            self.assertEqual(info["releaseProfile"], "limited-evaluation")
            self.assertEqual(info["releaseDecision"], "LIMITED_EVALUATION")
            self.assertEqual(info["validationStatus"], "BLOCKED_ENVIRONMENT")
            self.assertFalse(info["fullAcceptancePassed"])
            self.assertTrue(info["notForProduction"])
            self.assertEqual(set(info["acceptedIncompleteChecks"]), set(self.validation["limitedEvaluation"]["acceptedIncompleteChecks"]))
            self.assertIn(b"wordingAndState: FAIL:", archive.read("Release/RELEASE_STATUS.txt"))
            self.assertTrue(archive.read("Release/EXCEL_TEST_RESULT.txt").startswith(b"LIMITED EVALUATION:"))


if __name__ == "__main__":
    unittest.main()
