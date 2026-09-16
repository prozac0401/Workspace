"""Run the real CMD while its synthetic engine removes the running package."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]


@unittest.skipUnless(os.name == "nt", "Windows batch interpreter required")
class UninstallSelfRemoval(unittest.TestCase):
    def test_running_batch_and_working_directory_can_be_removed(self):
        artifacts = (REPO / "artifacts").resolve()
        with tempfile.TemporaryDirectory(prefix="slc-self-removal-", dir=artifacts) as temporary:
            root = Path(temporary).resolve()
            self.assertTrue(root.is_relative_to(artifacts))
            for code, keep_note in ((0, False), (37, False), (0, True)):
                with self.subTest(code=code, keep_note=keep_note):
                    folder = root / f"한글 & ! (100%) {code}-{keep_note}"
                    folder.mkdir()
                    shutil.copyfile(ROOT / "Uninstall.cmd", folder / "Uninstall.cmd")
                    (folder / "install.json").write_text('{"synthetic":true}', encoding="ascii")
                    marker = folder / "business.txt"
                    if keep_note:
                        marker.write_text("preserve this synthetic note", encoding="ascii")
                    (folder / "Setup.ps1").write_text(r'''
param([string]$Action, [string]$ConfirmProduct)
$ErrorActionPreference='Stop'
if($Action -ne 'Uninstall' -or $ConfirmProduct -ne 'SLC-68A45C44-2026'){exit 99}
$owned=[IO.Path]::GetFullPath($env:SLC_TEST_OWN_DIRECTORY)
if(-not $owned.StartsWith(($env:TEMP+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Wrong fixture.'}
foreach($name in @('Uninstall.cmd','Setup.ps1','install.json')){Remove-Item -LiteralPath (Join-Path $owned $name)}
if(@(Get-ChildItem -LiteralPath $owned -Force).Count -eq 0){[IO.Directory]::Delete($owned,$false)}
exit ([int]$env:SLC_TEST_EXIT)
''', encoding="utf-8-sig")
                    env = {k: v for k, v in os.environ.items() if k.upper() != "PSMODULEPATH"}
                    env.update(SLC_SETUP_NO_PAUSE="1", SLC_TEST_EXIT=str(code), SLC_TEST_OWN_DIRECTORY=str(folder), TEMP=str(root), TMP=str(root))
                    result = subprocess.run(
                        [os.environ["COMSPEC"], "/d", "/v:off", "/c", "Uninstall.cmd -ConfirmProduct SLC-68A45C44-2026"],
                        cwd=folder, env=env, capture_output=True, timeout=30,
                    )
                    self.assertEqual(result.returncode, code, repr(result.stdout + result.stderr))
                    self.assertFalse((folder / "Uninstall.cmd").exists())
                    self.assertFalse((folder / "Setup.ps1").exists())
                    if keep_note:
                        self.assertEqual(marker.read_text(), "preserve this synthetic note")
                    else:
                        self.assertFalse(folder.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
