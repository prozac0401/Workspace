"""Synthetic evidence fixtures; no Excel, real compiler, install, or publication."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("slc_local_packager", REPO / "scripts/package-excel-local-candidate.py")
pack = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pack)
WRAPPER_SPEC = importlib.util.spec_from_file_location("slc_local_wrapper", REPO / "scripts/build-excel-onefile.py")
wrapper = importlib.util.module_from_spec(WRAPPER_SPEC)
WRAPPER_SPEC.loader.exec_module(wrapper)


class LocalCandidatePackageTests(unittest.TestCase):
    def setUp(self):
        artifacts = (REPO / "artifacts").resolve()
        artifacts.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="local-candidate-guard-", dir=artifacts)
        self.root = Path(self.temp.name).resolve()
        self.assertTrue(self.root.is_relative_to(artifacts))
        self.addCleanup(self.temp.cleanup)
        for name in pack.SNAPSHOT_FILES:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((REPO / name).read_bytes())
        # This is explicitly an RC10 synthetic fixture, independent of the current release.
        setup = self.root / pack.TOOL_PATH / "Setup.ps1"
        setup.write_bytes(setup.read_bytes().replace(b"$InstallerVersion = '0.2.0-rc.11'", b"$InstallerVersion = '0.2.0-rc.10'"))
        (self.root / "artifacts").mkdir()
        self.repo_patch = patch.object(pack, "REPO", self.root)
        self.repo_patch.start()
        self.addCleanup(self.repo_patch.stop)
        self.git_patch = patch.object(pack, "git_state", return_value={"baseCommit": "a" * 40, "sourceTreeDirty": True})
        self.git_patch.start()
        self.addCleanup(self.git_patch.stop)
        self.xlam = self.root / "synthetic-candidate.xlam"
        ribbon = (self.root / pack.TOOL_PATH / "src/customUI14.xml").read_bytes()
        with zipfile.ZipFile(self.xlam, "w") as archive:
            archive.writestr("customUI/customUI14.xml", ribbon)
            archive.writestr("_rels/.rels", '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="ui" Type="http://schemas.microsoft.com/office/2007/relationships/ui/extensibility" Target="customUI/customUI14.xml"/></Relationships>')
            archive.writestr("[Content_Types].xml", '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/customUI/customUI14.xml" ContentType="application/xml"/></Types>')
            archive.writestr("xl/workbook.xml", '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><workbookPr codeName="ThisWorkbook"/><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>')
            archive.writestr("xl/_rels/workbook.xml.rels", '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
            archive.writestr("xl/worksheets/sheet1.xml", '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetPr codeName="Sheet1"/></worksheet>')
            archive.writestr("xl/vbaProject.bin", b"Synthetic evidence-schema test; never executed")
        exact = pack.digest(self.xlam.read_bytes())
        auditor = pack.load_auditor()
        inspected, _ = auditor.inspect_package(self.xlam, ribbon)
        sources = {name: (self.root / pack.TOOL_PATH / "src" / name).read_bytes() for name in pack.SOURCE_FILES}
        records = []
        for name, filename in pack.COMPONENTS.items():
            normalized = pack.digest(auditor.canonicalize_vba(sources[filename].decode("ascii")).encode("utf-8"))
            records.append({"component": name, "status": "PASS", "sourceNormalizedSha256": normalized,
                            "serializedNormalizedSha256": normalized})
        self.audit = {"schemaVersion": 1, "status": "PASS", "errors": [],
                      "xlamSha256Before": exact, "xlamSha256After": exact,
                      "sourceHashes": {name: pack.digest(data) for name, data in sources.items()},
                      "package": inspected, "serializedVba": {"status": "PASS", "errors": [], "modules": records},
                      "scriptSha256": pack.digest((self.root / pack.TOOL_PATH / "tests/audit_candidate.py").read_bytes()),
                      "xlamPath": "C:/Users/PRIVATE_USER/business-secrets.xlsx"}
        self.runtime = {"schemaVersion": 1, "status": "PASS", "releaseVersion": pack.VERSION,
                        "expectedSha256": exact, "actualSha256": exact, "finalSha256": exact,
                        "tests": [{"name": name, "status": "PASS", "result": "PASS: synthetic fixture"}
                                  for name in ("SLC_TestAll", "SLC_UsabilityTests")],
                        "failure": None, "cleanupErrors": [], "excelExited": True,
                        "releaseApproved": False, "nativeInputTests": "NOT_RUN", "installedTests": "NOT_RUN",
                        "addinPath": "C:/Users/PRIVATE_USER/local-candidate.xlam"}
        self.audit_path, self.runtime_path = self.root / "audit.private.json", self.root / "runtime.private.json"
        self.output = self.root / "artifacts/package"

    def invoke(self, output=None, iscc=None):
        self.audit_path.write_bytes(pack.json_bytes(self.audit))
        self.runtime_path.write_bytes(pack.json_bytes(self.runtime))
        return pack.package_candidate(self.xlam, self.audit_path, self.runtime_path, output or self.output, iscc)

    def assert_rejected(self, message):
        with self.assertRaisesRegex(pack.PackageError, message):
            self.invoke()
        self.assertFalse(self.output.exists())

    def test_exact_candidate_creates_local_only_packages_without_running_compiler(self):
        (self.root / "secret.private.json").write_text("DO_NOT_PACKAGE", encoding="ascii")
        with patch.object(pack.subprocess, "run") as process:
            result = self.invoke()
        process.assert_not_called()
        self.assertIsNone(result["exe"])
        self.assertFalse(result["releaseApproved"])
        manifest = json.loads((self.output / "Verification/Candidate-Validation.json").read_text(encoding="utf-8"))
        self.assertTrue(manifest["sourceTreeDirty"])
        self.assertEqual(manifest["releaseDecision"], "LOCAL_PACKAGE_ONLY")
        self.assertIs(manifest["fullAcceptancePassed"], False)
        self.assertIs(manifest["releaseApproved"], False)
        self.assertEqual(manifest["nativeInputTests"], "NOT_RUN")
        self.assertEqual(manifest["installedTests"], "NOT_RUN")
        self.assertIn("cancellation", manifest["incompleteChecks"])
        for key in ("installZip", "sourceZip", "verificationZip"):
            archive_path = Path(result[key])
            recorded = Path(str(archive_path) + ".sha256").read_text(encoding="ascii").split()[0]
            self.assertEqual(recorded, hashlib.sha256(archive_path.read_bytes()).hexdigest())
            with zipfile.ZipFile(archive_path) as archive:
                self.assertIsNone(archive.testzip())
                self.assertFalse(any("private" in name.lower() or "secret" in name.lower() for name in archive.namelist()))
                self.assertFalse(any(b"PRIVATE_USER" in archive.read(name) for name in archive.namelist()))
        with zipfile.ZipFile(result["installZip"]) as archive:
            self.assertEqual(set(archive.namelist()), {"Release/" + name for name in (
                "Install.cmd", "Uninstall.cmd", "Setup.ps1", "ExcelSmartListCompare.xlam", "README.md", "QuickGuide.html", "SHA256SUMS.txt")})
            self.assertEqual(archive.read("Release/ExcelSmartListCompare.xlam"), self.xlam.read_bytes())
            self.assertNotIn(b"](USABILITY_RC10_REPORT.md)", archive.read("Release/README.md"))
        with zipfile.ZipFile(result["sourceZip"]) as archive:
            self.assertEqual(set(archive.namelist()), set(pack.SNAPSHOT_FILES))
            self.assertEqual(archive.read(pack.TOOL_PATH + "src/modSLCReport.bas"),
                             (self.root / pack.TOOL_PATH / "src/modSLCReport.bas").read_bytes())

    def test_changed_current_source_is_rejected(self):
        path = self.root / pack.TOOL_PATH / "src/modSLCReport.bas"
        path.write_bytes(path.read_bytes() + b"\n' changed after audit\n")
        self.assert_rejected("Current source files differ")

    def test_missing_report_module_audit_is_rejected(self):
        self.audit["serializedVba"]["modules"] = [r for r in self.audit["serializedVba"]["modules"] if r["component"] != "modSLCReport"]
        self.assert_rejected("missing required VBA")

    def test_audit_success_label_does_not_hide_serialized_failure(self):
        self.audit["serializedVba"]["modules"][0]["serializedNormalizedSha256"] = "0" * 64
        self.assert_rejected("Serialized module hashes differ")

    def test_audit_revision_change_requires_new_audit(self):
        self.audit["scriptSha256"] = "0" * 64
        self.assert_rejected("different auditor revision")

    def test_audit_hash_mismatch_is_rejected(self):
        self.audit["xlamSha256After"] = "0" * 64
        self.assert_rejected("unchanged exact XLAM")

    def test_runtime_hash_mismatch_is_rejected(self):
        self.runtime["finalSha256"] = "0" * 64
        self.assert_rejected("exact RC10 XLAM")

    def test_dirty_runtime_cleanup_is_rejected(self):
        for field, value in (("excelExited", False), ("cleanupErrors", ["owned process remains"]), ("failure", "unexpected workbook")):
            with self.subTest(field=field):
                original = self.runtime[field]
                self.runtime[field] = value
                self.assert_rejected("clean owned-Excel exit")
                self.runtime[field] = original

    def test_incomplete_or_duplicate_runtime_tests_are_rejected(self):
        for tests in ([self.runtime["tests"][0]], [self.runtime["tests"][0], self.runtime["tests"][0]]):
            with self.subTest(tests=tests):
                original = self.runtime["tests"]
                self.runtime["tests"] = tests
                self.assert_rejected("Both exact-file runtime")
                self.runtime["tests"] = original

    def test_runtime_test_failure_is_rejected(self):
        self.runtime["tests"][1]["result"] = "FAIL: output changed"
        self.assert_rejected("Both actual runtime")

    def test_release_approval_cannot_be_inferred_from_a_candidate(self):
        for approval in (True, 0, None):
            with self.subTest(approval=approval):
                self.runtime["releaseApproved"] = approval
                self.assert_rejected("must not claim release approval")

    def test_native_failure_is_preserved_without_becoming_full_acceptance(self):
        self.runtime["nativeInputTests"] = "FAIL"
        result = self.invoke()
        manifest = json.loads((self.output / "Verification/Candidate-Validation.json").read_text(encoding="utf-8"))
        self.assertTrue(manifest["checks"]["cancellation"].startswith("FAIL:"))
        self.assertIs(result["fullAcceptancePassed"], False)

    def test_existing_output_is_preserved(self):
        self.output.mkdir()
        marker = self.output / "existing.txt"
        marker.write_text("preserve", encoding="ascii")
        with self.assertRaisesRegex(pack.PackageError, "fresh output"):
            self.invoke()
        self.assertEqual(marker.read_text(encoding="ascii"), "preserve")

    def test_output_outside_artifacts_is_rejected(self):
        with self.assertRaisesRegex(pack.PackageError, "below repository artifacts"):
            self.invoke(output=self.root / "outside")
        self.assertFalse((self.root / "outside").exists())

    def test_duplicate_json_properties_are_rejected(self):
        with self.assertRaisesRegex(pack.PackageError, "Duplicate JSON"):
            pack.read_json(b'{"status":"FAIL","status":"PASS"}')

    def test_source_snapshot_is_an_allowlist(self):
        self.assertEqual(len(pack.SNAPSHOT_FILES), len(set(pack.SNAPSHOT_FILES)))
        self.assertTrue(all(not name.startswith(("artifacts/", ".git/")) for name in pack.SNAPSHOT_FILES))

    def test_missing_compiler_is_rejected_before_output(self):
        with self.assertRaisesRegex(pack.PackageError, "compiler was not found"):
            self.invoke(iscc=self.root / "missing-compiler.exe")
        self.assertFalse(self.output.exists())

    def test_local_wrapper_requires_exact_validation_and_keeps_local_metadata(self):
        self.invoke()
        output = self.root / "artifacts/onefile"
        compiler = self.root / "synthetic-compiler.exe"
        compiler.write_bytes(b"Compiler process is mocked")
        argv = ["wrapper", "--release-directory", str(self.output / "Release"), "--output-directory", str(output),
                "--engine-version", pack.VERSION, "--release-profile", "local-candidate",
                "--payload-manifest", str(self.output / "RC10-Payload.json"),
                "--source-audit", str(self.audit_path), "--runtime", str(self.runtime_path), "--iscc", str(compiler)]

        def fake_compile(command, **kwargs):
            self.assertIn("/DFileVersion=0.2.0.10001", command)
            self.assertEqual(Path(command[-1]), output / "payload/SingleFile.iss")
            self.assertEqual(Path(command[-1]).read_bytes(), (self.root / pack.TOOL_PATH / "installer/SingleFile.iss").read_bytes())
            (output / ("ExcelSmartListCompare-" + pack.VERSION + "-Setup.exe")).write_bytes(b"synthetic compiled output")
            return subprocess.CompletedProcess(command, 0, b"test compiler", b"")

        with patch.object(wrapper, "REPO", self.root), patch.object(wrapper, "INSTALLER", self.root / pack.TOOL_PATH / "installer/SingleFile.iss"), \
                patch.object(sys, "argv", argv), patch.object(wrapper.subprocess, "run", side_effect=fake_compile), \
                patch.object(wrapper.subprocess, "check_output", return_value=""), patch("sys.stdout", new=io.StringIO()):
            wrapper.main()
        metadata = json.loads((output / "OneFile-Build.json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["status"], "unsigned local test candidate")
        self.assertIs(metadata["releaseApproved"], False)
        self.assertIs(metadata["fullAcceptancePassed"], False)
        self.assertEqual(metadata["releaseProfile"], "local-candidate")

    def test_local_wrapper_requires_original_evidence_even_with_passing_summary(self):
        self.invoke()
        pins = json.loads((self.output / "RC10-Payload.json").read_text(encoding="utf-8"))
        with patch.object(wrapper, "REPO", self.root), self.assertRaisesRegex(SystemExit, "requires the original"):
            wrapper.validate_local_manifest(self.output / "RC10-Payload.json", pins)

    def test_local_wrapper_rechecks_forged_summary_against_original_runtime(self):
        self.invoke()
        self.runtime["tests"][1]["result"] = "FAIL: direct wrapper cannot use summary PASS"
        self.runtime_path.write_bytes(pack.json_bytes(self.runtime))
        evidence = self.output / "Verification/Candidate-Validation.json"
        validation = json.loads(evidence.read_text(encoding="utf-8"))
        validation["evidenceSha256"]["runtime"] = pack.digest(self.runtime_path.read_bytes())
        evidence.write_bytes(pack.json_bytes(validation))
        pins = json.loads((self.output / "RC10-Payload.json").read_text(encoding="utf-8"))
        pins["validationSha256"] = pack.digest(evidence.read_bytes())
        with patch.object(wrapper, "REPO", self.root), patch.object(wrapper, "INSTALLER", self.root / pack.TOOL_PATH / "installer/SingleFile.iss"), \
                self.assertRaisesRegex(SystemExit, "Both actual runtime self-tests"):
            wrapper.validate_local_manifest(self.output / "RC10-Payload.json", pins,
                                            self.audit_path, self.runtime_path, self.output / "Release/ExcelSmartListCompare.xlam")

    def test_local_wrapper_rejects_compiler_source_changes_after_snapshot(self):
        self.invoke()
        pins = json.loads((self.output / "RC10-Payload.json").read_text(encoding="utf-8"))
        source = self.root / pack.TOOL_PATH / "installer/SingleFile.iss"
        source.write_bytes(source.read_bytes() + b"\n; changed after validation\n")
        with patch.object(wrapper, "REPO", self.root), patch.object(wrapper, "INSTALLER", source), \
                self.assertRaisesRegex(SystemExit, "changed after the source snapshot"):
            wrapper.validate_local_manifest(self.output / "RC10-Payload.json", pins,
                                            self.audit_path, self.runtime_path, self.output / "Release/ExcelSmartListCompare.xlam")

    def test_local_wrapper_rejects_changed_validation(self):
        self.invoke()
        pins = json.loads((self.output / "RC10-Payload.json").read_text(encoding="utf-8"))
        path = self.output / "Verification/Candidate-Validation.json"
        path.write_bytes(path.read_bytes() + b" ")
        with patch.object(wrapper, "REPO", self.root), self.assertRaisesRegex(SystemExit, "validation is missing or changed"):
            wrapper.validate_local_manifest(self.output / "RC10-Payload.json", pins)


if __name__ == "__main__":
    unittest.main()
