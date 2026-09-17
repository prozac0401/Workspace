"""Candidate host parser/output guards only; never opens Excel or a registry key."""
import os
import json
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

    def test_audit_replacement_and_locked_destination_preserve_evidence(self):
        output = REPO / "artifacts" / "excel-candidate-guard-selftest" / uuid.uuid4().hex[:8]
        output.mkdir(parents=True)
        env = os.environ.copy()
        env["SLC_CANDIDATE_PARSE"] = str(HOST)
        env["SLC_AUDIT_FIXTURE"] = str(output)
        # Load only the audit writer, never the host's Excel/security operations.
        command = r'''
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:SLC_CANDIDATE_PARSE,[ref]$tokens,[ref]$errors)
$writer=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-CandidateAudit'},$false)
. ([scriptblock]::Create($writer.Extent.Text))
$evidence=$env:SLC_AUDIT_FIXTURE;$utf8=New-Object Text.UTF8Encoding($false)
$audit=[ordered]@{phase='first';value=('long first value '*100)}
Save-CandidateAudit
$audit.phase='second';$audit.value='short'
Save-CandidateAudit
$destination=Join-Path $evidence 'build-result.private.json'
$before=[IO.File]::ReadAllText($destination)
$locked=[IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
$failed=$false
try{$audit.phase='blocked';try{Save-CandidateAudit}catch{$failed=$true}}finally{$locked.Dispose()}
if(-not $failed -or [IO.File]::ReadAllText($destination) -cne $before){throw 'Locked replacement did not preserve the previous complete audit.'}
$audit.phase='resumed';Save-CandidateAudit
'''
        result = subprocess.run(
            [str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
            env=env, capture_output=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads((output / "build-result.private.json").read_text(encoding="utf-8")),
                         {"phase": "resumed", "value": "short"})
        self.assertEqual([p.name for p in output.iterdir()], ["build-result.private.json"])

    def test_vbe_identifier_case_does_not_hide_literal_or_code_changes(self):
        env = os.environ.copy()
        env["SLC_CANDIDATE_PARSE"] = str(HOST)
        command = r'''
$ErrorActionPreference='Stop';$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:SLC_CANDIDATE_PARSE,[ref]$tokens,[ref]$errors)
$function=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Normalize-Vba'},$false)
. ([scriptblock]::Create($function.Extent.Text))
$prefix="Option Explicit`n"
$a=Normalize-Vba ($prefix+'button.Caption = caption')
$b=Normalize-Vba ($prefix+'button.caption = Caption')
if($a -cne $b){throw 'VBE identifier capitalization is not normalized.'}
foreach($pair in @(
 @('MsgBox "VALUE"','MsgBox "value"'),
 @('MsgBox "Do ""Not"" Fold"','MsgBox "Do ""not"" Fold"'),
 @("x = 1 'Comment","x = 1 'comment"),
 @('x = 1','x = 2'),
 @('x = 1 + 2','x = 1 - 2'),
 @('Call Checkpoint','Call DifferentCheckpoint')
)){
 if((Normalize-Vba ($prefix+$pair[0])) -ceq (Normalize-Vba ($prefix+$pair[1]))){throw 'Meaningful source difference was hidden.'}
}
'''
        result = subprocess.run(
            [str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
            env=env, capture_output=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
