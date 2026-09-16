"""Windows launcher integration; never installs a product or opens Excel.

Fixtures and raw output remain under repository-local artifacts. Group Policy
cases inject the policy reader into the exact bootstrap text; they do not write
HKCU/HKLM policies. The real Setup test holds its mutex before starting it.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
LAUNCHERS = {"Install.cmd": "Install", "Uninstall.cmd": "Uninstall", "Test_Excel.cmd": "Test"}
POWERSHELL = shutil.which("powershell.exe")
STUB = r'''param([string]$Action, [string]$ConfirmProduct)
$ErrorActionPreference = 'Stop'
[ordered]@{
    action = $Action
    confirmProduct = $ConfirmProduct
    policy = [string](Get-ExecutionPolicy)
    processPolicy = [string](Get-ExecutionPolicy -Scope Process)
    root = $PSScriptRoot
    apartment = [string][Threading.Thread]::CurrentThread.GetApartmentState()
    hostVersion = $PSVersionTable.PSVersion.ToString()
    hostExecutable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    hostIs64Bit = [Environment]::Is64BitProcess
} | ConvertTo-Json | Set-Content -LiteralPath $env:SLC_TEST_RESULT -Encoding UTF8
exit ([int]$env:SLC_TEST_EXIT)
'''
INVOKE = r'''
$before = @(Get-ExecutionPolicy -List | Select-Object Scope,ExecutionPolicy)
$parentPolicy = $env:PSExecutionPolicyPreference
& $env:SLC_TEST_LAUNCHER -ConfirmProduct SLC-68A45C44-2026
$code = $LASTEXITCODE
[ordered]@{
    before = $before
    after = @(Get-ExecutionPolicy -List | Select-Object Scope,ExecutionPolicy)
    parentPolicyBefore = $parentPolicy
    parentPolicyAfter = $env:PSExecutionPolicyPreference
    launcherVariableLeaked = (Test-Path Env:SLC_SETUP_SCRIPT)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $env:SLC_TEST_PARENT -Encoding UTF8
exit $code
'''
MOCK_POLICY = r'''
function Get-ExecutionPolicy {
    param([string]$Scope)
    switch ($Scope) {
        'MachinePolicy' { return $env:SLC_TEST_MACHINE }
        'UserPolicy' { return $env:SLC_TEST_USER }
        default { return $env:SLC_TEST_EFFECTIVE }
    }
}
'''


def zone(path):
    return Path(str(path) + ":Zone.Identifier")


def has_zone(path):
    try:
        return "ZoneId=3" in zone(path).read_text(encoding="ascii")
    except FileNotFoundError:
        return False


@unittest.skipUnless(os.name == "nt" and POWERSHELL, "Requires Windows PowerShell and NTFS")
class WindowsLaunchers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = REPO / "artifacts" / "excel-rc4-launchers" / uuid.uuid4().hex[:8]
        cls.output.mkdir(parents=True)
        print("Launcher evidence: " + str(cls.output))

    def fixture(self, launcher="Install.cmd", real_setup=False):
        folder = self.output / uuid.uuid4().hex[:8] / "한글 공백 & (1) ' $() ! `"
        folder.mkdir(parents=True)
        shutil.copyfile(ROOT / launcher, folder / launcher)
        setup = folder / "Setup.ps1"
        if real_setup:
            shutil.copyfile(ROOT / "Setup.ps1", setup)
        else:
            setup.write_text(STUB, encoding="utf-8-sig")
        (folder / "other.ps1").write_text("throw 'Must not run'", encoding="ascii")
        (folder / "business.txt").write_text("fixture to preserve", encoding="ascii")
        for name in ("Setup.ps1", "other.ps1", "business.txt"):
            zone(folder / name).write_text("[ZoneTransfer]\r\nZoneId=3\r\n", encoding="ascii")
        self.assertTrue(has_zone(setup))
        return folder

    def run_ps(self, folder, command, launcher="Install.cmd", policy="Restricted", **extra):
        # Match a normal Explorer launch, not the coding host's injected PS7
        # module search path (whose type files cannot load under Restricted).
        env = {key: value for key, value in os.environ.items()
               if key.upper() not in {"PSMODULEPATH", "SLC_SETUP_SCRIPT"}}
        env.update({
            "SLC_SETUP_NO_PAUSE": "1",
            "SLC_TEST_LAUNCHER": str(folder / launcher),
            "SLC_TEST_RESULT": str(folder / "result.json"),
            "SLC_TEST_PARENT": str(folder / "parent.json"),
            "SLC_TEST_EXIT": "0",
        })
        env.update(extra)
        result = subprocess.run(
            [POWERSHELL, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", policy,
             "-Command", "$ErrorActionPreference = 'Stop'; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); " + command],
            env=env, cwd=REPO, capture_output=True, encoding="utf-8", errors="replace", timeout=40,
        )
        (folder / "process.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        return result

    def assert_parent_preserved(self, folder):
        parent = json.loads((folder / "parent.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(parent["before"], parent["after"])
        self.assertEqual(parent["parentPolicyBefore"], parent["parentPolicyAfter"])
        self.assertFalse(parent["launcherVariableLeaked"])

    def test_restricted_launchers_unblock_only_setup_and_preserve_exit_codes(self):
        for (launcher, action), exit_code in zip(LAUNCHERS.items(), (0, 2, 37)):
            with self.subTest(launcher=launcher, exit_code=exit_code):
                folder = self.fixture(launcher)
                original = (folder / "Setup.ps1").read_bytes()
                result = self.run_ps(folder, INVOKE, launcher, SLC_TEST_EXIT=str(exit_code))
                self.assertEqual(result.returncode, exit_code, result.stdout + result.stderr)
                state = json.loads((folder / "result.json").read_text(encoding="utf-8-sig"))
                self.assertEqual(state["action"], action)
                self.assertEqual(state["confirmProduct"], "SLC-68A45C44-2026")
                self.assertEqual(state["policy"], "RemoteSigned")
                self.assertEqual(state["processPolicy"], "RemoteSigned")
                self.assertEqual(state["apartment"], "STA")
                self.assertTrue(state["hostVersion"].startswith("5.1."), state)
                self.assertEqual(Path(state["hostExecutable"]), Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe")
                self.assertEqual(Path(state["root"]), folder)
                self.assertEqual(original, (folder / "Setup.ps1").read_bytes())
                self.assertFalse(has_zone(folder / "Setup.ps1"))
                self.assertTrue(has_zone(folder / "other.ps1"))
                self.assertTrue(has_zone(folder / "business.txt"))
                self.assert_parent_preserved(folder)

    def test_missing_setup_stops_preparation(self):
        folder = self.fixture()
        (folder / "Setup.ps1").unlink()  # One known fixture file, never a directory.
        result = self.run_ps(folder, INVOKE)
        self.assertEqual(result.returncode, 1)
        self.assertIn("설치에 필요한 Setup.ps1 파일이 없습니다", result.stdout + result.stderr)
        self.assertFalse((folder / "result.json").exists())
        self.assert_parent_preserved(folder)

    def test_launchers_ignore_a_powershell_executable_on_path(self):
        # A file in the distribution/PATH must not select the host. This invalid
        # executable would make the old unqualified invocation fail to start.
        for launcher, action in LAUNCHERS.items():
            with self.subTest(launcher=launcher):
                folder = self.fixture(launcher)
                (folder / "powershell.exe").write_bytes(b"not a Windows executable")
                result = self.run_ps(folder, INVOKE, launcher, PATH=str(folder), SLC_SETUP_DIAGNOSTICS="1")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                state = json.loads((folder / "result.json").read_text(encoding="utf-8-sig"))
                self.assertEqual(state["action"], action)
                self.assertTrue(state["hostVersion"].startswith("5.1."), state)
                self.assertEqual(Path(state["hostExecutable"]), Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe")
                self.assertIn("SLC_LAUNCHER_PREPARE_ENTERED", result.stdout)
                self.assertIn("SLC_LAUNCHER_ENGINE_EXIT=0", result.stdout)
                self.assert_parent_preserved(folder)

    def test_failed_host_launch_preserves_stage_and_exit_without_retry(self):
        for phase in ("PREPARE", "ENGINE"):
            with self.subTest(phase=phase):
                folder = self.fixture()
                launcher = folder / "Install.cmd"
                lines = launcher.read_text(encoding="ascii").splitlines()
                selector = " -Command " if phase == "PREPARE" else " -STA "
                index = next(i for i, line in enumerate(lines) if selector in line)
                lines[index] = '"%ComSpec%" /D /C exit 5'
                launcher.write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))
                result = self.run_ps(folder, INVOKE, SLC_SETUP_DIAGNOSTICS="1")
                self.assertEqual(result.returncode, 5, result.stdout + result.stderr)
                self.assertIn(f"SLC_LAUNCHER_{phase}_EXIT=5", result.stdout)
                self.assertEqual(result.stdout.count(f"SLC_LAUNCHER_{phase}_START"), 1)
                self.assertFalse((folder / "result.json").exists())
                if phase == "PREPARE":
                    self.assertNotIn("SLC_LAUNCHER_ENGINE_START", result.stdout)
                self.assert_parent_preserved(folder)

    def test_unblock_failure_stops_before_setup(self):
        folder = self.fixture()
        launcher = folder / "Install.cmd"
        code = launcher.read_text(encoding="ascii")
        fault = "function Unblock-File { param([string]$LiteralPath) throw 'Injected access denied' }; "
        launcher.write_text(code.replace('-Command "try {', '-Command "' + fault + 'try {'), encoding="ascii")
        result = self.run_ps(folder, INVOKE)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Injected access denied", result.stdout + result.stderr)
        self.assertFalse((folder / "result.json").exists())
        self.assertTrue(has_zone(folder / "Setup.ps1"))
        self.assert_parent_preserved(folder)

    def test_existing_allsigned_policy_is_not_relaxed(self):
        folder = self.fixture()
        result = self.run_ps(folder, INVOKE, policy="AllSigned")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("기존 PowerShell 보안 정책에 따라 실행합니다", result.stdout + result.stderr)
        self.assertFalse((folder / "result.json").exists())
        self.assertTrue(has_zone(folder / "Setup.ps1"))
        self.assert_parent_preserved(folder)

    def test_group_policy_bootstrap_preserves_download_marker(self):
        cases = (
            ("Restricted", "Undefined", "Restricted"),
            ("Undefined", "Restricted", "Restricted"),
            ("AllSigned", "Undefined", "AllSigned"),
            ("Undefined", "RemoteSigned", "RemoteSigned"),
        )
        for launcher in LAUNCHERS:
            for machine, user, effective in cases:
                with self.subTest(launcher=launcher, machine=machine, user=user):
                    folder = self.fixture(launcher)
                    line = next(line for line in (ROOT / launcher).read_text(encoding="ascii").splitlines()
                                if ' -Command "' in line and 'Get-ExecutionPolicy' in line)
                    bootstrap = line.split(' -Command "', 1)[1][:-1]
                    result = self.run_ps(folder, MOCK_POLICY + bootstrap, launcher,
                                         SLC_SETUP_SCRIPT=str(folder / "Setup.ps1"),
                                         SLC_TEST_MACHINE=machine, SLC_TEST_USER=user,
                                         SLC_TEST_EFFECTIVE=effective)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertTrue(has_zone(folder / "Setup.ps1"))
                    self.assertFalse((folder / "result.json").exists())

    def test_actual_setup_keeps_mutex_guard_and_exit_code(self):
        command = r'''
$mutex = New-Object Threading.Mutex($false, 'Local\ExcelSmartListCompare-Setup')
$held = $mutex.WaitOne(0)
if (-not $held) { $mutex.Dispose(); exit 99 }
try {
''' + INVOKE.replace("exit $code", "") + r'''
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
exit $code
'''
        for launcher in ("Install.cmd", "Uninstall.cmd"):
            with self.subTest(launcher=launcher):
                folder = self.fixture(launcher, real_setup=True)
                result = self.run_ps(folder, command, launcher, SLC_SETUP_DIAGNOSTICS="1")
                if result.returncode == 99:
                    self.skipTest("Another setup owns the product mutex")
                self.assertEqual(result.returncode, 4, result.stdout + result.stderr)
                # Windows PowerShell wraps error text based on the full fixture
                # path; wrapping may split a Korean word as well as whitespace.
                self.assertIn("Excel명단비교를설치하거나제거하는작업이진행중입니다",
                              re.sub(r"\s+", "", result.stdout + result.stderr))
                self.assertIn("SLC_SETUP_PHASE=EngineEntered", result.stdout)
                self.assertIn("SLC_SETUP_FAILURE_PHASE=AcquireMutex", result.stdout)
                self.assert_parent_preserved(folder)


if __name__ == "__main__":
    unittest.main(verbosity=2)
