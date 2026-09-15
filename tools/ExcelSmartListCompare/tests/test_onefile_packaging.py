"""Exercise distribution guards without running a compiler or installing anything."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / "scripts/build-excel-onefile.py"


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


if __name__ == "__main__":
    unittest.main()
