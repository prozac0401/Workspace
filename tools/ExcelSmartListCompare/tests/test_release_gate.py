"""RC9 must reject missing native acceptance before creating release files."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
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

    def reject(self, expected):
        manifest = self.root / "validation.json"
        manifest.write_text(json.dumps(self.validation), encoding="utf-8")
        argv = ["package", "--installer-version", "0.2.0-rc.9", "--xlam", str(self.xlam),
                "--validation", str(manifest), "--output-directory", str(self.output)]
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


if __name__ == "__main__":
    unittest.main()
