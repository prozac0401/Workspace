"""Render public evidence links without copying local diagnostics into a release."""
import importlib.util
import html
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

REPO = Path(__file__).resolve().parents[3]
HAS_MARKDOWN = importlib.util.find_spec("markdown") is not None
spec = importlib.util.spec_from_file_location(
    "slc_release_document_links", REPO / "scripts/package-excel-wording-release.py"
)
packaging = importlib.util.module_from_spec(spec)
if HAS_MARKDOWN:
    spec.loader.exec_module(packaging)
else:
    # The normal engine suite need not install the documentation environment.
    # Actual renderer regressions run in the repository docs virtualenv below.
    with patch.dict(sys.modules, {"markdown": Mock()}):
        spec.loader.exec_module(packaging)


class ReleaseDocumentLinksTests(unittest.TestCase):
    def setUp(self):
        (REPO / "artifacts").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="release-links-", dir=REPO / "artifacts")
        self.output = Path(self.temp.name).resolve()
        self.assertTrue(self.output.is_relative_to((REPO / "artifacts").resolve()))
        self.addCleanup(self.temp.cleanup)
        self.commit = packaging.git("rev-parse", "HEAD")

    @unittest.skipUnless(HAS_MARKDOWN, "Run renderer cases in .tools/docs-venv")
    def test_completion_and_history_are_distinct_and_keep_committed_public_links(self):
        for number in (8, 9):
            with self.subTest(release=number):
                output = self.output / ("RC" + str(number))
                output.mkdir()
                names, completion = packaging.release_report_layout(number)
                self.assertEqual(completion, "Completion-Report.html")
                self.assertEqual(len(names.values()), len(set(names.values())))
                expected_source = "RC8_COMPLETION_REPORT.md" if number == 8 else "RC9_APPROVED_RETEST_20260917.md"
                self.assertEqual(names[expected_source], completion)
                if number == 9:
                    self.assertEqual(names["RC9_STABILITY_REPORT.md"], "RC9-Initial-Report.html")
                    self.assertEqual(names["RC8_COMPLETION_REPORT.md"], "RC8-Previous-Report.html")
                else:
                    self.assertNotIn("RC9_APPROVED_RETEST_20260917.md", names)
                    self.assertNotIn("RC9_STABILITY_REPORT.md", names)
                for source_name, target_name in names.items():
                    source = packaging.TOOL / "docs" / source_name
                    packaging.rendering.render(
                        source, output / target_name, self.commit,
                        html_names=packaging.public_report_link_map(source, self.commit, names),
                    )
                completed = (output / completion).read_text(encoding="utf-8")
                heading = (packaging.TOOL / "docs" / expected_source).read_text(encoding="utf-8-sig").splitlines()[0].removeprefix("# ")
                self.assertIn("<h1>" + html.escape(heading) + "</h1>", completed)
                summary_report = completion if number == 8 else "RC9-Initial-Report.html"
                rendered = (output / summary_report).read_text(encoding="utf-8")
                expected = ("https://github.com/prozac0401/Workspace/blob/" + self.commit
                            + "/tools/ExcelSmartListCompare/evidence/rc" + str(number) + "/validation.json")
                self.assertIn('href="' + expected + '"', rendered)
                self.assertNotIn('href="../evidence/', rendered)
                if number == 9:
                    self.assertIn('href="Completion-Report.html"', rendered)
                packaging.validate_release_local_links(output)
                self.assertEqual(list(output.glob("*.json")), [])

    def test_public_summary_must_exist_in_the_exact_release_commit(self):
        missing = subprocess.CalledProcessError(128, ["git", "cat-file"])
        source = packaging.TOOL / "docs/RC9_STABILITY_REPORT.md"
        with patch.object(packaging, "git", side_effect=missing), \
                self.assertRaisesRegex(SystemExit, "absent from the release commit"):
            packaging.public_report_link_map(source, self.commit, {})
        self.assertEqual(list(self.output.iterdir()), [])

    def test_private_json_link_is_not_mapped_or_accepted(self):
        source = packaging.TOOL / "docs/RC9_STABILITY_REPORT.md"
        links = packaging.public_report_link_map(source, self.commit, {})
        self.assertNotIn("../../../artifacts/diagnostics.private.json", links)
        (self.output / "Report.html").write_text(
            '<a href="../../../artifacts/diagnostics.private.json">Private diagnostic</a>', encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "Broken local HTML reference"):
            packaging.validate_release_local_links(self.output)


if __name__ == "__main__":
    unittest.main()
