"""Exercise distribution guards without running a compiler or installing anything."""
from pathlib import Path
from contextlib import redirect_stdout
import importlib.util
import io
import json
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
        self.notice = self.installer.parent / "LIMITED_EVALUATION.txt"
        self.notice.write_text("제한 평가판\nLIMITED EVALUATION\nKnown limits.\n", encoding="utf-8")
        self.compiler = self.root / "synthetic-compiler.exe"
        self.compiler.write_bytes(b"Never executed; subprocess.run is mocked.")
        for name in builder.PAYLOAD:
            content = "LIMITED EVALUATION\n" if name == "README.md" else "Synthetic " + name
            (self.release / name).write_text(content, encoding="utf-8")

    def pins(self, version="0.2.0-rc.9", profile="limited-evaluation"):
        document = {"engineVersion": version, "sha256": {
            name: builder.sha256(self.release / name) for name in builder.PAYLOAD}}
        if profile is not None:
            document["releaseProfile"] = profile
        rc = version.rsplit(".", 1)[1]
        (self.installer.parent / f"RC{rc}-Payload.json").write_text(json.dumps(document), encoding="utf-8")

    def invoke(self, version="0.2.0-rc.9", profile="limited-evaluation", compiler_action=None):
        argv = [str(SCRIPT), "--release-directory", str(self.release),
                "--output-directory", str(self.output), "--engine-version", version,
                "--iscc", str(self.compiler)]
        if profile is not None:
            argv.extend(("--release-profile", profile))

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
                redirect_stdout(io.StringIO()):
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

    def test_limited_pins_cannot_be_used_as_default_full_release(self):
        self.pins()
        with self.assertRaisesRegex(SystemExit, "releaseProfile does not match"):
            self.invoke(profile=None)
        self.assertFalse(self.output.exists())

    def test_limited_profile_rejects_older_versions(self):
        for version in ("0.2.0-rc.7", "0.2.0-rc.8"):
            with self.subTest(version=version), self.assertRaisesRegex(SystemExit, "only for RC9"):
                self.invoke(version=version)
        self.assertFalse(self.output.exists())

    def test_limited_readme_requires_explicit_marker(self):
        (self.release / "README.md").write_text("Ordinary package", encoding="utf-8")
        self.pins()
        with self.assertRaisesRegex(SystemExit, "Limited README must contain"):
            self.invoke()
        self.assertFalse(self.output.exists())

    def test_limited_notice_requires_explicit_marker(self):
        self.notice.write_text("Missing classification", encoding="utf-8")
        self.pins()
        with self.assertRaisesRegex(SystemExit, "installation notice must contain"):
            self.invoke()
        self.assertFalse(self.output.exists())

    def test_limited_compiler_receives_standard_notice_and_profile_define(self):
        self.pins()

        def check_command(command):
            self.assertIn("/DLimitedEvaluation=1", command)
            self.assertIn("/DEngineVersion=0.2.0-rc.9", command)
            self.assertIn("/DFileVersion=0.2.0.9001", command)
            staged = (self.output / "payload/LimitedEvaluation.txt").read_bytes()
            self.assertTrue(staged.startswith(b"\xef\xbb\xbf"))
            self.assertEqual(staged.decode("utf-8-sig"), self.notice.read_bytes().decode("utf-8"))

        metadata = self.invoke(compiler_action=check_command)
        self.assertEqual(metadata["releaseProfile"], "limited-evaluation")
        self.assertEqual(metadata["limitedNoticeSourceSha256"], builder.sha256(self.notice))
        self.assertEqual(metadata["limitedNoticeSha256"], builder.sha256(self.output / "payload/LimitedEvaluation.txt"))
        self.assertEqual(set(metadata["payloadHashes"]), set(builder.PAYLOAD))
        self.assertEqual(metadata["runtimeValidation"], "not performed by this build script")
        source = self.installer.read_text(encoding="utf-8-sig")
        self.assertIn('#ifdef LimitedEvaluation\nInfoBeforeFile={#PayloadDir}\\LimitedEvaluation.txt\n#endif',
                      source.replace("\r\n", "\n"))
        self.assertIn('AppName={#DisplayName}', source)
        self.assertIn('SetupWindowTitle={#DisplayName} 설치', source)

    def test_legacy_rc8_default_profile_keeps_full_compiler_behavior(self):
        self.pins(version="0.2.0-rc.8", profile=None)

        def check_command(command):
            self.assertFalse(any(item.startswith("/DLimitedEvaluation") for item in command))
            self.assertFalse((self.output / "payload/LimitedEvaluation.txt").exists())

        metadata = self.invoke(version="0.2.0-rc.8", profile=None, compiler_action=check_command)
        self.assertEqual(metadata["releaseProfile"], "full")
        self.assertIsNone(metadata["limitedNoticeSourceSha256"])
        self.assertIsNone(metadata["limitedNoticeSha256"])


if __name__ == "__main__":
    unittest.main()
