"""Exercise the supervisor with sleeping/text-only children; never opens Excel.

All generated scripts and local process evidence remain in ignored artifacts.
The tests opt out of the Excel preflight for these non-Office fixtures only.
"""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import time
import unittest
import uuid

REPO = Path(__file__).resolve().parents[3]
RUNNER = Path(__file__).with_name("Invoke-BoundedTest.ps1")
POWERSHELL = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"


@unittest.skipUnless(os.name == "nt" and POWERSHELL.exists(), "Requires Windows PowerShell")
class BoundedRunner(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = REPO / "artifacts" / "excel-bounded-selftest" / uuid.uuid4().hex[:8]
        cls.output.mkdir(parents=True)
        print("Bounded supervisor evidence: " + str(cls.output))

    def fixture(self, text, parameters=None):
        case = self.output / uuid.uuid4().hex[:8] / "한글 공백 & (1) ' $() ! `"
        case.mkdir(parents=True)
        script = case / "fixture.ps1"
        script.write_text(text, encoding="utf-8-sig")
        param_path = case / "parameters.json"
        param_path.write_text(json.dumps(parameters or {}, ensure_ascii=False), encoding="utf-8-sig")
        return case, script, param_path

    def command(self, script, params, *extra):
        run_id = "selftest-" + uuid.uuid4().hex[:12]
        args = [str(POWERSHELL), "-NoLogo", "-NoProfile", "-File", str(RUNNER),
                "-ScriptPath", str(script), "-ParametersPath", str(params), "-RunId", run_id,
                "-AllowExistingExcel", "-MaxBaselineCpuPercent", "100",
                "-MaxBaselineMemoryPercent", "100", "-MinAvailableMemoryGB", "0", *extra]
        return args, REPO / "artifacts" / "excel-bounded" / run_id

    def run_fixture(self, script, params, *extra):
        args, evidence = self.command(script, params, *extra)
        result = subprocess.run(args, capture_output=True, timeout=30)
        self.assertTrue((evidence / "result.private.json").exists(), result.stdout + result.stderr)
        return result, json.loads((evidence / "result.private.json").read_text(encoding="utf-8-sig")), evidence

    def test_parameters_priority_environment_and_telemetry(self):
        case, script, params = self.fixture(r'''param([string]$Literal,[bool]$Enabled,[int]$Count)
[ordered]@{literal=$Literal;enabled=$Enabled;count=$Count;priority=[string][Diagnostics.Process]::GetCurrentProcess().PriorityClass;modulePath=$env:PSModulePath;version=$PSVersionTable.PSVersion.Major} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'observed.json') -Encoding UTF8
Start-Sleep -Seconds 3
exit 0
''', {"Literal": "한글 & $() ` ' (value)", "Enabled": False, "Count": 7})
        result, summary, evidence = self.run_fixture(script, params)
        self.assertEqual(result.returncode, 0, summary)
        observed = json.loads((case / "observed.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(observed["literal"], "한글 & $() ` ' (value)")
        self.assertIs(observed["enabled"], False)
        self.assertEqual(observed["count"], 7)
        self.assertEqual(observed["priority"], "BelowNormal")
        self.assertEqual(observed["version"], 5)
        self.assertNotIn("\\PowerShell\\7\\", observed["modulePath"])
        samples = [json.loads(line) for line in (evidence / "telemetry.private.jsonl").read_text(encoding="utf-8").splitlines()]
        self.assertGreaterEqual(len(samples), 5)
        self.assertTrue(any(sample["child"] for sample in samples))
        self.assertTrue(all(0 <= sample["cpuPercent"] <= 100 for sample in samples if sample["cpuPercent"] is not None))

    def test_child_failure_is_not_a_pass(self):
        _, script, params = self.fixture("exit 17\n")
        result, summary, _ = self.run_fixture(script, params)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(summary["status"], "FAIL")
        self.assertEqual(summary["childExitCode"], 17)

    def test_high_memory_requirement_defers_without_running_script(self):
        case, script, params = self.fixture("Set-Content -LiteralPath (Join-Path $PSScriptRoot 'started') -Value yes\n")
        args, evidence = self.command(script, params)
        args[args.index("-MinAvailableMemoryGB") + 1] = "1024"
        result = subprocess.run(args, capture_output=True, timeout=20)
        summary = json.loads((evidence / "result.private.json").read_text(encoding="utf-8"))
        self.assertEqual(result.returncode, 75, summary)
        self.assertEqual(summary["status"], "BLOCKED_ENV")
        self.assertIsNone(summary["child"])
        self.assertFalse((case / "started").exists())

    def test_timeout_stops_exact_wrapper(self):
        _, script, params = self.fixture("Start-Sleep -Seconds 20\n")
        result, summary, _ = self.run_fixture(script, params, "-TimeoutSeconds", "2")
        self.assertEqual(result.returncode, 124, summary)
        self.assertTrue(summary["wrapperStopped"])
        self.assertEqual(summary["status"], "FAIL")
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x00100000, False, summary["child"]["pid"])
        if handle:
            try:
                self.assertEqual(kernel.WaitForSingleObject(handle, 0), 0)
            finally:
                kernel.CloseHandle(handle)

    def test_second_runner_cannot_start_a_child(self):
        case, script, params = self.fixture("Set-Content -LiteralPath (Join-Path $PSScriptRoot 'started') -Value yes\nStart-Sleep -Seconds 6\n")
        args, evidence = self.command(script, params)
        first = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 15
            while not (case / "started").exists() and time.monotonic() < deadline:
                if first.poll() is not None:
                    break
                time.sleep(0.1)
            self.assertTrue((case / "started").exists())
            _, second_script, second_params = self.fixture("throw 'Must not execute concurrently'\n")
            second, summary, _ = self.run_fixture(second_script, second_params)
            self.assertEqual(second.returncode, 4, summary)
            self.assertEqual(summary["status"], "BLOCKED_ENV")
            self.assertIsNone(summary["child"])
            stdout, stderr = first.communicate(timeout=20)
            self.assertEqual(first.returncode, 0, stdout + stderr)
        finally:
            if first.poll() is None:
                first.wait(timeout=20)
            first.communicate(timeout=1)


if __name__ == "__main__":
    unittest.main()
