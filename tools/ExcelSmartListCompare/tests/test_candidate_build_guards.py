"""Candidate host parser/output guards only; never opens Excel or a registry key."""
import os
from pathlib import Path
import subprocess
import unittest
import uuid

REPO = Path(__file__).resolve().parents[3]
HOST = Path(__file__).with_name("Build-ExcelCandidate.ps1")
POWERSHELL = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"


@unittest.skipUnless(os.name == "nt" and POWERSHELL.exists(), "Requires Windows PowerShell")
class CandidateBuildGuards(unittest.TestCase):
    def invoke_guard(self, output):
        # Deliberately never supplies ApprovedTemporaryVbaAccess.
        return subprocess.run(
            [str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-File", str(HOST),
             "-OutputDirectory", str(output)], capture_output=True, timeout=15,
        )

    def test_script_parses(self):
        env = os.environ.copy()
        env["SLC_CANDIDATE_PARSE"] = str(HOST)
        result = subprocess.run(
            [str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command",
             "$tokens=$null; $errors=$null; "
             "[void][Management.Automation.Language.Parser]::ParseFile($env:SLC_CANDIDATE_PARSE,[ref]$tokens,[ref]$errors); "
             "if($errors.Count){$errors | ForEach-Object Message; exit 1}"],
            env=env, capture_output=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_output_escape_is_rejected_before_creation(self):
        name = "candidate-guard-" + uuid.uuid4().hex[:8]
        target = REPO / name
        for output in (target, REPO / "artifacts" / ".." / name):
            with self.subTest(output=output):
                result = self.invoke_guard(output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"below this repository artifacts", result.stderr)
                self.assertFalse(target.exists())

    def test_existing_output_is_preserved(self):
        output = REPO / "artifacts" / "excel-candidate-guard-selftest" / uuid.uuid4().hex[:8]
        output.mkdir(parents=True)
        marker = output / "preserve.txt"
        marker.write_bytes(b"previous evidence remains unchanged\r\n")
        result = self.invoke_guard(output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"OutputDirectory already exists", result.stderr)
        self.assertEqual(marker.read_bytes(), b"previous evidence remains unchanged\r\n")
        self.assertEqual(list(output.iterdir()), [marker])


if __name__ == "__main__":
    unittest.main()
