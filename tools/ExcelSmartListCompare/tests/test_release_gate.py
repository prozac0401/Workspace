"""Full RC9 acceptance stays mandatory unless recorded exceptions are explicit."""
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
            "packageRevision": 2,
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

    def exceptions_manifest(self):
        self.validation.update({"status": "BLOCKED_ENVIRONMENT", "releaseProfile": "documented-exceptions",
                                "releaseDecision": "PUBLISH_WITH_RECORDED_RESULTS"})
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
        self.validation["releaseExceptions"] = {
            "userAuthorized": True, "fullAcceptancePassed": False,
            "acceptedIncompleteChecks": list(incomplete),
        }

    def test_exception_cli_alone_cannot_waive_acceptance(self):
        self.validation["checks"]["wordingAndState"] = "FAIL: unresolved"
        self.reject("explicit matching user-authorized decision", "documented-exceptions")

    def test_exception_metadata_alone_cannot_change_default_full_profile(self):
        self.exceptions_manifest()
        self.reject("requires the explicit documented-exceptions profile")
        for name in self.validation["checks"]:
            self.validation["checks"][name] = "PASS: incorrectly relabeled fixture"
        self.reject("requires the explicit documented-exceptions profile")

    def test_exceptions_require_actual_boolean_authorization(self):
        for value in (False, "true", 1, None):
            with self.subTest(authorization=value):
                self.exceptions_manifest()
                self.validation["releaseExceptions"]["userAuthorized"] = value
                self.reject("explicit matching user-authorized decision", "documented-exceptions")

    def test_exceptions_still_require_each_core_check(self):
        self.exceptions_manifest()
        baseline = copy.deepcopy(self.validation)
        for name in ("sourceMatchesBinary", "normalizationAndIntegration", "selectionMatrix", "nativeContextMenu", "python", "docs"):
            with self.subTest(check=name):
                self.validation = copy.deepcopy(baseline)
                self.validation["checks"][name] = "FAIL: no accepted core proof"
                self.validation["releaseExceptions"]["acceptedIncompleteChecks"].append(name)
                self.reject("Documented exceptions require PASS for " + name, "documented-exceptions")

    def test_exceptions_require_all_fourteen_named_checks(self):
        for change in ("missing", "extra"):
            with self.subTest(change=change):
                self.exceptions_manifest()
                if change == "missing":
                    del self.validation["checks"]["uninstall"]
                else:
                    self.validation["checks"]["unreviewedGate"] = "PASS: not part of this profile"
                self.reject("Required validation is incomplete or failed", "documented-exceptions")
                # Reset the check shape for the next independent subcase.
                self.validation["checks"].pop("unreviewedGate", None)

    def test_exceptions_require_matching_decision_and_incomplete_acceptance(self):
        for change in ("decision", "scope", "profile"):
            with self.subTest(change=change):
                self.exceptions_manifest()
                if change == "decision":
                    self.validation["releaseDecision"] = "HOLD"
                elif change == "scope":
                    self.validation["releaseExceptions"]["fullAcceptancePassed"] = True
                else:
                    self.validation["releaseProfile"] = "full"
                self.reject("explicit matching user-authorized decision", "documented-exceptions")

    def test_exceptions_require_exact_unchanged_incomplete_check_set(self):
        for change in ("missing", "extra", "duplicate", "relabel", "unknown"):
            with self.subTest(change=change):
                self.exceptions_manifest()
                accepted = self.validation["releaseExceptions"]["acceptedIncompleteChecks"]
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
                self.reject("Unknown documented-exceptions check status" if change == "unknown" else "exactly match", "documented-exceptions")

    def test_exceptions_keep_exact_file_source_and_installer_gates(self):
        self.exceptions_manifest()
        baseline = copy.deepcopy(self.validation)
        for field, expected in (("xlamSha256", "exact XLAM"), ("installerSha256", "Installer changed"),
                                ("sourceTextSha256", "Sources have changed")):
            with self.subTest(field=field):
                self.validation = copy.deepcopy(baseline)
                self.validation[field] = {} if field == "sourceTextSha256" else "0" * 64
                self.reject(expected, "documented-exceptions")

    def test_exceptions_are_not_available_for_earlier_releases(self):
        self.exceptions_manifest()
        with self.assertRaisesRegex(SystemExit, "defined only for RC9"):
            gate.validate_acceptance_profile(self.validation, tuple(self.validation["checks"]), 8, "documented-exceptions")

    def make_package_fixture(self):
        """Synthetic package bytes only; no Excel, installer, or VBA execution."""
        tool = self.root / "tool"
        (tool / "src").mkdir(parents=True)
        (tool / "docs").mkdir()
        sources = gate.SOURCES + ("src/CSLCAppEvents.cls", "src/customUI14.xml")
        for name in sources + ("Install.cmd", "Uninstall.cmd", "Test_Excel.cmd", "Setup.ps1"):
            (tool / name).write_bytes((gate.TOOL / name).read_bytes())
        readme = "Synthetic package regression fixture.\n"
        (tool / "docs/RELEASE_README.md").write_bytes(readme.encode("utf-8"))
        for name in gate.release_report_layout(9)[0]:
            (tool / "docs" / name).write_text("# Synthetic report\n", encoding="utf-8")
        with zipfile.ZipFile(self.xlam, "w") as archive:
            archive.writestr("customUI/customUI14.xml", (tool / "src/customUI14.xml").read_bytes())
            archive.writestr("_rels/.rels", '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="ui" Type="http://schemas.microsoft.com/office/2007/relationships/ui/extensibility" Target="customUI/customUI14.xml"/></Relationships>')
            archive.writestr("[Content_Types].xml", '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/customUI/customUI14.xml" ContentType="application/xml"/></Types>')
        self.exceptions_manifest()
        self.validation["xlamSha256"] = gate.sha256(self.xlam)
        self.validation["installerSha256"] = gate.sha256(tool / "Setup.ps1")
        self.validation["sourceTextSha256"] = {name: gate.text_hash((tool / name).read_bytes()) for name in sources}
        return tool, sources

    def test_exceptions_require_actual_false_for_full_acceptance(self):
        for value in (True, "false", 0, None):
            with self.subTest(full_acceptance=value):
                self.exceptions_manifest()
                self.validation["releaseExceptions"]["fullAcceptancePassed"] = value
                self.reject("explicit matching user-authorized decision", "documented-exceptions")

    def test_html_links_must_resolve_inside_each_separate_package(self):
        release = self.root / "Release"
        verification = self.root / "Verification"
        release.mkdir()
        verification.mkdir()
        for directory in (release, verification):
            (directory / "QuickGuide.html").write_text("<html>guide</html>", encoding="utf-8")
        (verification / "Completion-Report.html").write_text('<a href="QuickGuide.html">guide</a>', encoding="utf-8")
        gate.validate_release_local_links(release)
        gate.validate_release_local_links(verification)
        (release / "QuickGuide.html").write_text('<a href="../Verification/Completion-Report.html">report</a>', encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "Broken local HTML reference"):
            gate.validate_release_local_links(release)
        (verification / "Completion-Report.html").write_text('<a href="../Release/QuickGuide.html">guide</a>', encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "Broken local HTML reference"):
            gate.validate_release_local_links(verification)

    def test_exception_package_preserves_raw_results_without_adding_classifiers(self):
        tool, sources = self.make_package_fixture()
        manifest = self.root / "validation.json"
        manifest.write_text(json.dumps(self.validation), encoding="utf-8")
        before = manifest.read_bytes()
        commit = "a" * 40
        argv = ["package", "--installer-version", "0.2.0-rc.9", "--release-profile", "documented-exceptions",
                "--xlam", str(self.xlam), "--validation", str(manifest), "--output-directory", str(self.output)]

        def fake_git(*args):
            return "" if args[0] in {"status", "cat-file"} else commit

        def fake_render(source, output, source_commit, **kwargs):
            self.assertEqual(source_commit, commit)
            if output.name == "QuickGuide.html":
                self.assertEqual(source, tool / "docs/RELEASE_README.md")
                output.write_text("<html><body>synthetic user guide</body></html>", encoding="utf-8")
            else:
                self.assertEqual(output.parent.name, "Verification")
                output.write_text('<html><body>synthetic report<a href="QuickGuide.html">guide</a></body></html>', encoding="utf-8")

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
        install = self.output / "ExcelSmartListCompare-0.2.0-rc.9-win-x64.zip"
        self.assertTrue((self.output / "ExcelSmartListCompare-0.2.0-rc.9-Source.zip").is_file())
        self.assertEqual({path.name for path in self.output.glob("*.zip")}, {
            "ExcelSmartListCompare-0.2.0-rc.9-win-x64.zip", "ExcelSmartListCompare-0.2.0-rc.9-Source.zip",
            "ExcelSmartListCompare-0.2.0-rc.9-Verification.zip"})
        for path in self.output.glob("*.zip"):
            recorded_hash = Path(str(path) + ".sha256").read_text(encoding="ascii").split()[0]
            self.assertEqual(recorded_hash, gate.sha256(path))
        with zipfile.ZipFile(install) as archive:
            self.assertEqual(set(archive.namelist()), {"Release/" + name for name in (
                "ExcelSmartListCompare.xlam", "Setup.ps1", "Install.cmd", "Uninstall.cmd", "README.md",
                "QuickGuide.html", "SHA256SUMS.txt")})
            self.assertEqual(archive.read("Release/README.md"), (tool / "docs/RELEASE_README.md").read_bytes())
            self.assertEqual(archive.read("Release/ExcelSmartListCompare.xlam"), self.xlam.read_bytes())
            user_bytes = {Path(name).name: archive.read(name) for name in archive.namelist()}
            sums = archive.read("Release/SHA256SUMS.txt").decode("ascii").splitlines()
            for line in sums:
                expected, name = line.split("  ", 1)
                self.assertEqual(hashlib.sha256(user_bytes[name]).hexdigest(), expected)
        with zipfile.ZipFile(self.output / "ExcelSmartListCompare-0.2.0-rc.9-Verification.zip") as archive:
            self.assertEqual(json.loads(archive.read("Verification/Validation.json")), self.validation)
            self.assertEqual(archive.read("Verification/QuickGuide.html"), user_bytes["QuickGuide.html"])
            self.assertNotIn("Verification/Test_Excel.cmd", archive.namelist())
            self.assertIn("Verification/Completion-Report.html", archive.namelist())
            self.assertIn("Verification/RC9-Initial-Report.html", archive.namelist())
            self.assertEqual(archive.read("Verification/SOURCE_COMMIT.txt").decode("ascii").strip(), commit)
            info = json.loads(archive.read("Verification/BUILD_INFO.json"))
            self.assertEqual(info["releaseProfile"], "documented-exceptions")
            self.assertEqual(info["releaseDecision"], "PUBLISH_WITH_RECORDED_RESULTS")
            self.assertEqual(info["status"], "unsigned prerelease")
            self.assertEqual(info["packageRevision"], 2)
            self.assertFalse(info["xlamRebuiltThisRun"])
            self.assertTrue(info["xlamReused"])
            self.assertEqual(info["xlamSha256"], hashlib.sha256(user_bytes["ExcelSmartListCompare.xlam"]).hexdigest())
            self.assertEqual(info["userPackageFileSha256"], {
                name: hashlib.sha256(data).hexdigest() for name, data in user_bytes.items() if name != "SHA256SUMS.txt"})
            self.assertEqual(info["validationStatus"], "BLOCKED_ENVIRONMENT")
            self.assertFalse(info["fullAcceptancePassed"])
            self.assertNotIn("notForProduction", info)
            self.assertEqual(set(info["acceptedIncompleteChecks"]), set(self.validation["releaseExceptions"]["acceptedIncompleteChecks"]))
            expected_status = ("Validation results\n"
                               "Full acceptance is incomplete. Raw results remain in Validation.json.\n\n")
            expected_status += "\n".join(name + ": " + self.validation["checks"][name]
                                         for name in self.validation["releaseExceptions"]["acceptedIncompleteChecks"]) + "\n"
            self.assertEqual(archive.read("Verification/RELEASE_STATUS.txt").decode("utf-8").replace("\r\n", "\n"),
                             expected_status)
            self.assertEqual(archive.read("Verification/EXCEL_TEST_RESULT.txt").decode("utf-8").replace("\r\n", "\n"),
                             self.validation["checks"]["normalizationAndIntegration"] + "\n")


if __name__ == "__main__":
    unittest.main()
