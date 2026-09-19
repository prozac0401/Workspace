"""Exercise distribution guards without running a compiler or installing anything."""
from pathlib import Path
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / "scripts/build-excel-onefile.py"
SPEC = importlib.util.spec_from_file_location("slc_onefile_build", SCRIPT)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)
LAUNCHER_SPEC = importlib.util.spec_from_file_location("slc_launcher_tests", Path(__file__).with_name("test_launchers.py"))
launchers = importlib.util.module_from_spec(LAUNCHER_SPEC)
LAUNCHER_SPEC.loader.exec_module(launchers)


class OneFilePackagingTests(unittest.TestCase):
    def setUp(self):
        artifacts = REPO / "artifacts"
        artifacts.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="onefile-guard-", dir=artifacts)
        self.root = Path(self.temp.name).resolve()
        self.assertTrue(self.root.is_relative_to(artifacts.resolve()))
        self.addCleanup(self.temp.cleanup)
        self.payload = self.root / "Release"
        self.payload.mkdir()
        self.output = self.root / "output"

    def invoke(self, output=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--release-directory", str(self.payload),
             "--output-directory", str(output or self.output), "--iscc", sys.executable],
            capture_output=True, text=True, encoding="utf-8", cwd=REPO,
        )

    def test_missing_payload_does_not_create_an_installer(self):
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("payload is missing or changed: Install.cmd", result.stderr)
        self.assertFalse(self.output.exists())

    def test_changed_launcher_is_rejected_before_compiler_execution(self):
        (self.payload / "Install.cmd").write_bytes(b"@echo off\r\nexit /b 0\r\n")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("payload is missing or changed: Install.cmd", result.stderr)
        self.assertFalse(self.output.exists())

    def test_output_cannot_overwrite_repository_artifacts(self):
        marker = self.root / "existing.txt"
        marker.write_text("preserve", encoding="ascii")
        result = self.invoke(self.root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fresh output directory", result.stderr)
        self.assertEqual(marker.read_text(encoding="ascii"), "preserve")

    def test_system_chcp_command_has_inner_path_and_outer_cmd_quotes(self):
        source = builder.INSTALLER.read_text(encoding="utf-8-sig")
        match = re.search(r"Started := ExecAndLogOutput\(ExpandConstant\('\{cmd\}'\),\s*(.*?)\s*,\s*Directory,", source, re.S)
        self.assertIsNotNone(match)
        expression = match.group(1)
        self.assertIn("ExpandConstant('{sys}\\chcp.com')", expression)
        # Evaluate only the three permitted Pascal concatenation operand kinds;
        # do not run Inno, CMD, a launcher, or PowerShell.
        operands = re.findall(r"ExpandConstant\('(?:[^']|'')*'\)|'(?:[^']|'')*'|\bAction\b", expression)
        self.assertEqual(re.sub(r"ExpandConstant\('(?:[^']|'')*'\)|'(?:[^']|'')*'|\bAction\b|\s|\+", "", expression), "")
        for system in (r"C:\Windows\System32", r"C:\Windows With Spaces & (1)\System32"):
            for action in ("Install", "Uninstall"):
                with self.subTest(system=system, action=action):
                    rendered = "".join(action if operand == "Action" else
                                       operand[len("ExpandConstant('"):-2].replace("{sys}", system) if operand.startswith("ExpandConstant(") else
                                       operand[1:-1].replace("''", "'") for operand in operands)
                    self.assertTrue(rendered.startswith('/D /V:OFF /C "'))
                    self.assertTrue(rendered.endswith('"'))
                    inner = rendered[len('/D /V:OFF /C "'):-1]
                    self.assertEqual(inner, '"' + system + '\\chcp.com" 65001>nul & ' + action + '.cmd -ConfirmProduct SLC-68A45C44-2026')

    def test_launcher_host_selection_ignores_path_and_preserves_sysnative(self):
        environment = {"SystemRoot": str(self.root), "PATH": str(self.root / "fake-powershell")}
        suffix = Path("WindowsPowerShell/v1.0/powershell.exe")
        native = self.root / "Sysnative" / suffix
        system = self.root / "System32" / suffix
        self.assertEqual(launchers.system_powershell(environment, lambda candidate: candidate in {native, system}), str(native))
        self.assertEqual(launchers.system_powershell(environment, lambda candidate: candidate == system), str(system))
        self.assertIsNone(launchers.system_powershell(environment, lambda candidate: False))
        self.assertIsNone(launchers.system_powershell({"PATH": str(self.root)}, lambda candidate: True))
        self.assertIsNone(launchers.system_powershell({"SystemRoot": "relative"}, lambda candidate: True))

    def test_launcher_start_error_records_private_evidence_and_reraises(self):
        error = PermissionError(13, "Synthetic process creation denied")
        error.winerror = 5
        command = [str(self.root / "powershell.exe"), "-NoProfile", "-Command", "Write-Output 'ENTERED'; exit 0"]
        environment = {"SystemRoot": str(self.root), "Path": "synthetic path", "UNRELATED_SECRET": "never recorded"}
        with patch.object(launchers.subprocess, "run", side_effect=error) as runner:
            with self.assertRaises(PermissionError) as observed:
                launchers.run_recorded_process(command, self.root, cwd=self.root, env=environment, capture_output=True)
        self.assertIs(observed.exception, error)
        runner.assert_called_once()
        record = json.loads((self.root / "host-start-failure.private.json").read_text(encoding="utf-8"))
        self.assertEqual((record["status"], record["winerror"]), ("HOST_START_FAILED", 5))
        self.assertEqual(record["argv"], command)
        self.assertTrue(record["environmentPresent"]["PATH"])
        self.assertFalse(record["environmentPresent"]["PATHEXT"])
        self.assertNotIn("UNRELATED_SECRET", json.dumps(record))
        self.assertNotIn("never recorded", json.dumps(record))
        self.assertFalse((self.root / "process.log").exists())


class OneFileReleaseProfileTests(unittest.TestCase):
    """Exercise profile validation and compiler arguments with a fake compiler."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="onefile-profile-", dir=REPO / "artifacts")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.release = self.root / "Release"
        self.release.mkdir()
        self.output = self.root / "output"
        self.installer = self.root / "installer" / "SingleFile.iss"
        self.installer.parent.mkdir()
        self.installer.write_bytes(builder.INSTALLER.read_bytes())
        self.compiler = self.root / "synthetic-compiler.exe"
        self.compiler.write_bytes(b"Never executed; subprocess.run is mocked.")
        for name in builder.PAYLOAD:
            content = "Known failures and untested behavior.\n" if name == "README.md" else "Synthetic " + name
            (self.release / name).write_text(content, encoding="utf-8")

    def pins(self, version="0.2.0-rc.9", profile="documented-exceptions"):
        document = {"engineVersion": version, "sha256": {
            name: builder.sha256(self.release / name) for name in builder.PAYLOAD}}
        if profile is not None:
            document["releaseProfile"] = profile
        rc = version.rsplit(".", 1)[1]
        (self.installer.parent / f"RC{rc}-Payload.json").write_text(json.dumps(document), encoding="utf-8")

    def invoke(self, version="0.2.0-rc.9", profile="documented-exceptions", revision=None, compiler_action=None):
        argv = [str(SCRIPT), "--release-directory", str(self.release),
                "--output-directory", str(self.output), "--engine-version", version,
                "--iscc", str(self.compiler)]
        if profile is not None:
            argv.extend(("--release-profile", profile))
        if revision is not None:
            argv.extend(("--package-revision", str(revision)))

        def compile_only(command, **kwargs):
            if compiler_action:
                compiler_action(command)
            (self.output / f"ExcelSmartListCompare-{version}-Setup.exe").write_bytes(b"Synthetic compiled bytes")
            return subprocess.CompletedProcess(command, 0, b"Synthetic compiler\n", b"")

        def git_output(command, **kwargs):
            return "a" * 40 if command[1] == "rev-parse" else ""

        with patch.object(builder, "INSTALLER", self.installer), patch.object(sys, "argv", argv), \
                patch.object(builder.subprocess, "run", side_effect=compile_only) as compiler, \
                patch.object(builder.subprocess, "check_output", side_effect=git_output), \
                redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            try:
                builder.main()
            except SystemExit:
                self.assertFalse(compiler.called, "Rejected input reached the compiler")
                raise
        return json.loads((self.output / "OneFile-Build.json").read_text(encoding="utf-8"))

    def test_profile_mismatch_rejected_before_output_or_compiler(self):
        self.pins(profile="full")
        with self.assertRaisesRegex(SystemExit, "releaseProfile does not match"):
            self.invoke()
        self.assertFalse(self.output.exists())

    def test_exception_pins_cannot_be_used_as_default_full_release(self):
        self.pins()
        with self.assertRaisesRegex(SystemExit, "releaseProfile does not match"):
            self.invoke(profile=None)
        self.assertFalse(self.output.exists())

    def test_exception_profile_rejects_older_versions(self):
        for version in ("0.2.0-rc.7", "0.2.0-rc.8"):
            with self.subTest(version=version), self.assertRaisesRegex(SystemExit, "only for RC9"):
                self.invoke(version=version)
        self.assertFalse(self.output.exists())

    def test_readme_without_classification_marker_and_no_notice_are_accepted(self):
        (self.release / "README.md").write_text("Product usage and recorded test results.", encoding="utf-8")
        self.pins()
        metadata = self.invoke()
        self.assertEqual(metadata["releaseProfile"], "documented-exceptions")
        self.assertEqual(set(p.name for p in (self.output / "payload").iterdir()),
                         set(builder.PAYLOAD) | {"PayloadHashes.iss", "manager.id"})
        self.assertFalse(any("notice" in key.lower() for key in metadata))

    def test_invalid_package_revisions_are_rejected_before_compiler(self):
        self.pins()
        for revision in (0, -1, "1.5", "invalid"):
            with self.subTest(revision=revision), self.assertRaises(SystemExit):
                self.invoke(revision=revision)
        self.assertFalse(self.output.exists())

    def test_revision_overflow_is_rejected_before_compiler(self):
        self.pins()
        with self.assertRaisesRegex(SystemExit, "65535 file-version"):
            self.invoke(revision=56536)
        self.assertFalse(self.output.exists())

    def test_revision_two_changes_file_version_and_metadata_only(self):
        self.pins()

        def check_command(command):
            self.assertIn("/DEngineVersion=0.2.0-rc.9", command)
            self.assertIn("/DFileVersion=0.2.0.9002", command)
            definitions = [part.split("=", 1)[0] for part in command if part.startswith("/D")]
            self.assertEqual(definitions, ["/DPayloadDir", "/DEngineVersion", "/DFileVersion"])

        metadata = self.invoke(revision=2, compiler_action=check_command)
        self.assertEqual(metadata["releaseProfile"], "documented-exceptions")
        self.assertEqual(metadata["packageRevision"], 2)
        self.assertEqual(metadata["fileVersion"], "0.2.0.9002")
        self.assertEqual((metadata["xlamRebuiltThisRun"], metadata["xlamReused"]), (False, True))
        self.assertEqual(metadata["exe"], "ExcelSmartListCompare-0.2.0-rc.9-Setup.exe")
        self.assertEqual(set(metadata["payloadHashes"]), set(builder.PAYLOAD))
        self.assertEqual(metadata["status"], "unsigned prerelease")
        self.assertEqual(metadata["runtimeValidation"], "not performed by this build script")
        source = self.installer.read_text(encoding="utf-8-sig")
        self.assertIn('AppName=Excel 명단 비교\n', source)
        self.assertIn('SetupWindowTitle=Excel 명단 비교 설치\n', source)
        self.assertNotIn('InfoBeforeFile=', source)
        self.assertIn('PrivilegesRequired=lowest', source)
        self.assertIn('AlwaysRestart=no', source)

    def test_legacy_rc8_default_profile_keeps_full_compiler_behavior(self):
        self.pins(version="0.2.0-rc.8", profile=None)

        def check_command(command):
            self.assertIn("/DFileVersion=0.2.0.8001", command)
            self.assertEqual(set(p.name for p in (self.output / "payload").iterdir()),
                             set(builder.PAYLOAD) | {"PayloadHashes.iss", "manager.id"})

        metadata = self.invoke(version="0.2.0-rc.8", profile=None, compiler_action=check_command)
        self.assertEqual(metadata["releaseProfile"], "full")
        self.assertEqual(metadata["packageRevision"], 1)
        self.assertEqual(metadata["fileVersion"], "0.2.0.8001")


if __name__ == "__main__":
    unittest.main()
