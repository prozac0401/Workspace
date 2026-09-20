"""R11 usability regression contracts and independent comparison counterexamples.

These tests do not compile or execute VBA. Run windows-usability.ps1 against an
explicit newly built XLAM for Excel integration; native input remains separate.
"""
from collections import Counter
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

from test_reference import normalize as normalize_rules, snapshot
from functools import partial

# These counterexamples deliberately exercise the optional case-insensitive rule.
normalize = partial(normalize_rules, ignore_case=True)

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


def procedure(source, name):
    match = re.search(
        rf"^(?:Public|Private|Friend)\s+(Sub|Function)\s+{re.escape(name)}\b.*?^End \1\s*$",
        source, re.MULTILINE | re.DOTALL | re.IGNORECASE,
    )
    if not match:
        raise AssertionError(f"Missing VBA procedure: {name}")
    return "\n".join(line for line in match[0].splitlines()
                     if not line.lstrip().startswith("'"))


class ComparisonCounterexamples(unittest.TestCase):
    def test_row_partition_can_create_false_differences(self):
        first, second = ["가", "나"], ["나", "가"]
        self.assertEqual(Counter(map(normalize, first)), Counter(map(normalize, second)))
        self.assertNotEqual(Counter(map(normalize, first[:1])),
                            Counter(map(normalize, second[:1])))

    def test_chunked_reads_must_accumulate_before_comparing(self):
        first = ["USER@a.com", "123.0", "USER@a.com", "00123"]
        second = ["00123", "user@b.com", "123", "user@c.com"]
        def aggregate(values, width):
            counts = Counter()
            for offset in range(0, len(values), width):
                counts.update(normalize(value) for value in values[offset:offset + width])
            return counts
        self.assertEqual(aggregate(first, 1), aggregate(second, 3))
        self.assertEqual(aggregate(first, 2)[normalize("user")], 2)

    def test_safe_partition_keeps_normalized_key_together(self):
        first = ["A@one", "a@two", "B", "00123", "123.0"]
        second = ["123", "b", "a@three", "00123", "A@four"]
        def partitions(values):
            groups = {}
            for value in values:
                key = normalize(value)
                groups.setdefault(key, Counter())[key] += 1
            return groups
        self.assertEqual(partitions(first), partitions(second))

    def test_domain_case_and_numeric_changes_can_match_with_raw_differences(self):
        pairs = [("Kim@a.com", "kim@b.com"), ("ABC", "abc"), ("123.0", "1.23e2")]
        for left, right in pairs:
            with self.subTest(left=left, right=right):
                self.assertEqual(normalize(left), normalize(right))
                self.assertNotEqual(left, right)

    def test_identical_representative_does_not_prove_raw_equality(self):
        first = ["kim@a.com", "kim@b.com", "kim@b.com"]
        second = ["kim@a.com", "kim@a.com", "kim@b.com"]
        self.assertEqual(first[0], second[0])
        self.assertEqual(Counter(map(normalize, first)), Counter(map(normalize, second)))
        self.assertNotEqual(Counter(first), Counter(second))

    def test_scattered_duplicates_keep_multiplicity(self):
        cells = {(1, 1): "a", (2, 1): "b", (99, 1): "a"}
        result = snapshot(cells, [(1, 1, 2, 1), (99, 1, 99, 1)])
        self.assertEqual(result[normalize("a")], 2)
        self.assertEqual(sum(result.values()), 3)

    def test_repeated_comparison_does_not_mutate_captured_counts(self):
        cells = {(1, 1): "a", (2, 1): "a", (3, 1): "b"}
        captured = snapshot(cells, [(1, 1, 3, 1)])
        original = captured.copy()
        cells[(1, 1)] = "changed after capture"
        for other in [Counter({normalize("a"): 1}), original.copy()]:
            _ = captured - other
            _ = other - captured
        self.assertEqual(captured, original)


class UsabilitySourceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.main = (SRC / "modSLCMain_utf8.bas").read_text(encoding="utf-8")
        cls.report = (SRC / "modSLCReport_utf8.bas").read_text(encoding="utf-8")
        cls.model = (SRC / "CSLCList_utf8.cls").read_text(encoding="utf-8")

    def test_equality_exits_before_report_creation(self):
        compare = procedure(self.main, "ShowComparison")
        self.assertIn("SLC_WriteUsabilityResults", compare)
        self.assertNotIn("MsgBox", compare)
        self.assertLess(compare.index("If matched = a.Total And matched = b.Total Then Exit Function"), compare.index("SLC_WriteUsabilityResults"))

    def test_successful_comparison_obeys_keep_setting(self):
        run = procedure(self.main, "RunSelection")
        self.assertIn("If Not keepFirst Then Set mPending = Nothing", run)
        self.assertLess(run.index("Set completedResult = ShowComparison"), run.index("If Not keepFirst Then Set mPending = Nothing"))
        self.assertIn("Set previousPending = mPending", run)
        self.assertIn("Set mPending = previousPending", run)
        clear = procedure(self.main, "SLC_Clear")
        self.assertIn("If mBusy Then Exit Sub", clear)
        self.assertIn("Set mPending = Nothing", clear)

    def test_preview_reads_snapshot_not_current_selection(self):
        wrapper = procedure(self.main, "SLC_Preview")
        self.assertIn("PreviewSnapshot completed", wrapper)
        worker = procedure(self.main, "PreviewSnapshot")
        self.assertIn("Set completedResult = SLC_WriteSnapshotPreview(mPending)", worker)
        for preview in [wrapper, worker]:
            self.assertNotIn("Application.Selection", preview)
            self.assertNotIn(".Value2", preview)
            self.assertNotRegex(preview, r"(?i)Set\s+mPending\s*=")

    def test_report_returns_the_workbook_it_created(self):
        write = procedure(self.report, "WriteReport")
        self.assertIn("Set wb = Application.Workbooks.Add", write)
        self.assertIn("Set WriteReport = wb", write)
        self.assertNotRegex(write, r"(?i)Set\s+WriteReport\s*=\s*Application\.ActiveWorkbook")
        for name in ["SLC_WriteUsabilityResults", "SLC_WriteSnapshotPreview"]:
            public = procedure(self.report, name)
            self.assertIn("As Workbook", public)
            self.assertIn("Set " + name + " = WriteReport(", public)
        self.assertIn("Set completedResult = ShowComparison(mPending, current)",
                      procedure(self.main, "RunSelection"))
        self.assertIn("Set ShowComparison = SLC_WriteUsabilityResults(",
                      procedure(self.main, "ShowComparison"))

    def test_runtime_tests_close_returned_workbooks_not_active_workbook(self):
        main_test = procedure(self.main, "SLC_UsabilityTests")
        for call in ["RunSelection False, firstResult", "PreviewSnapshot preview",
                     "RunSelection False, result"]:
            self.assertIn(call, main_test)
        self.assertNotRegex(main_test,
                            r"(?i)Set\s+(?:result|preview|firstResult)\s*=\s*Application\.ActiveWorkbook")
        report_test = procedure(self.report, "SLC_ReportTests")
        self.assertIn("Set testBook = WriteReport(", report_test)
        self.assertNotRegex(report_test,
                            r"(?i)Set\s+testBook\s*=\s*Application\.ActiveWorkbook")
        for body in [main_test, report_test]:
            self.assertNotIn("ActiveWorkbook.Close", body)
            self.assertNotIn("oldBook.Close", body)

    def test_cancel_request_is_distinct_from_completion(self):
        request = procedure(self.main, "SLC_Cancel")
        self.assertIn("If Not mBusy Then Exit Sub", request)
        self.assertIn("mCancelled = True", request)
        self.assertIn("취소 요청됨", request)
        self.assertNotIn("취소 완료", request)
        self.assertIn("취소 완료", procedure(self.main, "RunSelection"))

    def test_samples_do_not_change_comparison_aggregates(self):
        for name in ["AddOccurrence", "AddError"]:
            body = procedure(self.model, name)
            self.assertNotRegex(body, r"(?im)^\s*(?:Set\s+)?(?:Counts|Total|DuplicateExcess)\b.*=")
            self.assertNotRegex(body, r"(?i)Counts\.(?:Add|Remove|RemoveAll)")
        for field in ["OmittedOccurrences", "OmittedErrors"]:
            self.assertRegex(self.model, rf"{field} = {field} \+ 1")

    def test_sampling_is_bounded_and_snapshot_has_no_live_objects(self):
        for name in ["MAX_OCCURRENCES", "MAX_ERRORS", "MAX_PER_KEY"]:
            match = re.search(rf"Const {name} As Long = (\d+)", self.model)
            self.assertIsNotNone(match)
            self.assertGreater(int(match[1]), 0)
            self.assertLessEqual(int(match[1]), 2000)
        self.assertNotRegex(self.model, r"(?i)As (?:Workbook|Worksheet|Range)\b")

    def test_error_address_comes_from_captured_value(self):
        read = procedure(self.main, "AddValue")
        self.assertIn("list.AddError address, ErrorDescription(v)", read)
        error = procedure(self.main, "ErrorDescription")
        self.assertNotIn(".Text", error)
        self.assertNotIn(".Range", error)
        for label in ["#DIV/0!", "#N/A", "#VALUE!", "#REF!"]:
            self.assertIn(label, error)

    def test_difference_is_one_sheet_and_preview_has_locations(self):
        write = procedure(self.report, "WriteReport")
        for sheet in ["요약", "명단비교_결과", "제외·발생위치"]:
            self.assertIn('"' + sheet + '"', write)
        self.assertIn(".SplitRow = headerRow", procedure(self.report, "FormatTable"))
        self.assertIn("FormatTable ws, outRow - 1, 10, True, 8", procedure(self.report, "WriteDifferences"))
        self.assertNotIn("WriteVariants", self.report)
        self.assertNotIn("VariantSamples", self.model)
        self.assertIn("생략", procedure(self.report, "WriteSummary"))
        self.assertIn("원본 전체", procedure(self.report, "WriteSummary"))

    def test_formula_like_raw_values_are_written_as_text(self):
        safe = procedure(self.report, "SafeText")
        for prefix in ["=", "+", "-", "@", "'"]:
            self.assertIn('"' + prefix + '"', safe)
        self.assertIn("SafeText(CStr(value))", procedure(self.report, "PutRow"))
        flush = procedure(self.report, "FlushRows")
        self.assertLess(flush.index('target.NumberFormat = "@"'), flush.index("target.Value2"))

    def test_report_only_closes_its_provisional_workbook(self):
        write = procedure(self.report, "WriteReport")
        self.assertIn("Set wb = Application.Workbooks.Add", write)
        self.assertIn("If Not wb Is Nothing Then wb.Close SaveChanges:=False", write)
        self.assertNotIn("ActiveWorkbook.Close", write)
        self.assertNotIn("oldBook.Close", write)
        self.assertNotIn("SaveAs", write)

    def test_ribbon_xml_remains_well_formed(self):
        ET.parse(SRC / "customUI14.xml")


class RuntimeHarnessSafetyContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = (ROOT / "tests/windows-usability.ps1").read_text(encoding="utf-8-sig")

    def test_candidate_path_and_hash_are_explicit(self):
        self.assertIn("[Parameter(Mandatory=$true)][string]$AddinPath", self.code)
        self.assertIn("[Parameter(Mandatory=$true)][ValidatePattern", self.code)
        self.assertIn("$audit.actualSha256 -cne $audit.expectedSha256", self.code)
        self.assertNotIn("Join-Path $env:LOCALAPPDATA", self.code)

    def test_existing_excel_guard_precedes_start(self):
        guard = self.code.index("if(@(Get-Process EXCEL")
        start = self.code.index("    Start-OwnExcel -NormalStart")
        self.assertLess(guard, start)
        for forbidden in ["Stop-Process", "taskkill", "AutomationSecurity = 1",
                          "Set-ExecutionPolicy", "SetValue(", "-Action Install"]:
            self.assertNotIn(forbidden, self.code)

    def test_unknown_workbooks_prevent_application_quit(self):
        self.assertIn("if(-not $unknownBooks)", self.code)
        self.assertIn("if($bookOwned -and $null -ne $book)", self.code)
        self.assertIn("if($audit.cleanupErrors.Count -gt 0 -and $audit.status -eq 'PASS')", self.code)


if __name__ == "__main__":
    unittest.main(verbosity=2)
