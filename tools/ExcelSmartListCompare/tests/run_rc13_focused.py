"""Run exactly thirteen existing RC13 source contracts and record real outcomes.

No Excel, VBA, build, install, security setting, Git or publication is invoked.
The known old sheet-name expectation is explicitly excluded, not counted PASS.
This focused record does not replace native/T11 evidence or full acceptance.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import unittest

REPO = Path(__file__).resolve().parents[3]
TOOL = REPO / "tools/ExcelSmartListCompare"
TESTS = TOOL / "tests"
VERSION = "0.2.0-rc.13"
CLASS_PREFIX = "test_usability.UsabilitySourceContracts."
FOCUSED_METHODS = (
    "test_equality_exits_before_report_creation",
    "test_successful_comparison_obeys_keep_setting",
    "test_preview_reads_snapshot_not_current_selection",
    "test_preview_refresh_guidance_names_the_existing_replace_action",
    "test_report_returns_the_workbook_it_created",
    "test_runtime_tests_close_returned_workbooks_not_active_workbook",
    "test_cancel_request_is_distinct_from_completion",
    "test_samples_do_not_change_comparison_aggregates",
    "test_sampling_is_bounded_and_snapshot_has_no_live_objects",
    "test_error_address_comes_from_captured_value",
    "test_formula_like_raw_values_are_written_as_text",
    "test_report_only_closes_its_provisional_workbook",
    "test_ribbon_xml_remains_well_formed",
)
EXCLUDED_METHOD = "test_difference_is_one_sheet_and_preview_has_locations"
IMPORT_NAMES = ("CSLCList.cls", "CSLCAppEvents.cls", "modSLCNormalize.bas",
                "modSLCMain.bas", "modSLCReport.bas", "ThisWorkbook_events.txt", "customUI14.xml")
UTF8_NAMES = ("CSLCList_utf8.cls", "CSLCAppEvents_utf8.cls", "modSLCNormalize_utf8.bas",
              "modSLCMain_utf8.bas", "modSLCReport_utf8.bas")
EXCLUSION_REASON = ("Existing sheet-name expectation FAIL: the test expects pre-R12 '제외·발생위치', "
                    "while the R12/RC13 report uses '값과 위치'. Excluded explicitly from this focus; "
                    "not fixed by RC13 and not counted as PASS or a newly executed failure.")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def no_redirects(path):
    for item in (path.absolute(), *path.absolute().parents):
        try:
            stat = item.lstat()
        except FileNotFoundError:
            continue
        if item.is_symlink() or getattr(stat, "st_file_attributes", 0) & 0x400:
            raise ValueError("Output/source paths must not traverse a symlink or reparse point.")


def read(path):
    no_redirects(path)
    return path.read_bytes()


class RecordingResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.records = {}

    def addSuccess(self, test):
        super().addSuccess(test)
        self.records[test.id()] = {"name": test.id(), "status": "PASS"}

    def addFailure(self, test, error):
        super().addFailure(test, error)
        self.records[test.id()] = {"name": test.id(), "status": "FAIL"}

    def addError(self, test, error):
        super().addError(test, error)
        self.records[test.id()] = {"name": test.id(), "status": "ERROR"}

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self.records[test.id()] = {"name": test.id(), "status": "SKIP"}

    def addExpectedFailure(self, test, error):
        super().addExpectedFailure(test, error)
        self.records[test.id()] = {"name": test.id(), "status": "EXPECTED_FAILURE"}

    def addUnexpectedSuccess(self, test):
        super().addUnexpectedSuccess(test)
        self.records[test.id()] = {"name": test.id(), "status": "UNEXPECTED_SUCCESS"}

    def addSubTest(self, test, subtest, error):
        super().addSubTest(test, subtest, error)
        if error is not None:
            self.records[test.id()] = {"name": test.id(), "status": "FAIL" if issubclass(error[0], test.failureException) else "ERROR"}


def run(output):
    expected_ids = [CLASS_PREFIX + name for name in FOCUSED_METHODS]
    record = {
        "schemaVersion": 1, "status": "FAIL", "releaseVersion": VERSION,
        "scope": "usability-source-contracts", "executed": False,
        "passed": 0, "failed": 0, "errors": 0, "skipped": 0,
        "testsRun": 0, "tests": [], "sourceHashes": {}, "utf8SourceHashes": {},
        "sourceInputsUnchanged": False, "testSourceSha256": None,
        "referenceSourceSha256": None, "runnerSourceSha256": None,
        "expectedTestNames": expected_ids,
        "excludedTests": [{"name": CLASS_PREFIX + EXCLUDED_METHOD, "status": "NOT_RUN", "reason": EXCLUSION_REASON}],
        "earlierPartialAggregate": {"passed": 82, "failed": 1, "errors": 2, "currentRun": False,
            "scope": "Earlier partial suite; not rerun or replaced by this focused record.",
            "failedCause": "Existing sheet-name expectation mismatch.",
            "errorCause": "Two recorded missing-snapshot errors; not rerun in this focus."},
        "fullAcceptancePassed": False, "releaseApproved": False,
        "nativeTests": "NOT_RUN: source contracts do not execute Excel/VBA or UI",
        "installationTests": "NOT_RUN: this runner does not install, compare in Excel or remove the product",
        "diagnostics": [], "startedUtc": datetime.now(timezone.utc).isoformat(),
    }
    frozen = {}
    result = None
    try:
        frozen = {"src/" + name: read(TOOL / "src" / name) for name in IMPORT_NAMES + UTF8_NAMES}
        for name in ("test_usability.py", "test_reference.py", "run_rc13_focused.py"):
            frozen["tests/" + name] = read(TESTS / name)
        record["sourceHashes"] = {name: digest(frozen["src/" + name]) for name in IMPORT_NAMES}
        record["utf8SourceHashes"] = {name: digest(frozen["src/" + name]) for name in UTF8_NAMES}
        record["testSourceSha256"] = digest(frozen["tests/test_usability.py"])
        record["referenceSourceSha256"] = digest(frozen["tests/test_reference.py"])
        record["runnerSourceSha256"] = digest(frozen["tests/run_rc13_focused.py"])
        versions = []
        for name, encoding in (("modSLCMain.bas", "ascii"), ("modSLCMain_utf8.bas", "utf-8")):
            found = re.findall(r'^\s*SLC_ReleaseVersion\s*=\s*"([^"]+)"\s*$', frozen["src/" + name].decode(encoding), re.MULTILINE)
            if found != [VERSION]:
                raise ValueError("Current ASCII/UTF-8 release-version declaration is not exactly RC13: " + name)
            versions.extend(found)
        record["releaseVersionSource"] = "ASCII and UTF-8 source declarations; VBA not executed"
        sys.path.insert(0, str(TESTS))
        sys.dont_write_bytecode = True
        reference_spec = importlib.util.spec_from_file_location("test_reference", TESTS / "test_reference.py")
        reference = importlib.util.module_from_spec(reference_spec)
        sys.modules["test_reference"] = reference
        reference_spec.loader.exec_module(reference)
        spec = importlib.util.spec_from_file_location("test_usability", TESTS / "test_usability.py")
        source_tests = importlib.util.module_from_spec(spec)
        sys.modules["test_usability"] = source_tests
        spec.loader.exec_module(source_tests)
        actual = set(unittest.TestLoader().getTestCaseNames(source_tests.UsabilitySourceContracts))
        if actual != set(FOCUSED_METHODS) | {EXCLUDED_METHOD}:
            raise ValueError("UsabilitySourceContracts changed; review the explicit RC13 test selection.")
        suite = unittest.TestSuite(source_tests.UsabilitySourceContracts(name) for name in FOCUSED_METHODS)
        record["executed"] = True
        result = unittest.TextTestRunner(verbosity=2, resultclass=RecordingResult).run(suite)
        record["tests"] = [result.records[name] for name in expected_ids if name in result.records]
        record["testsRun"] = result.testsRun
        record["passed"] = sum(item["status"] == "PASS" for item in record["tests"])
        record["failed"] = len(result.failures) + len(result.unexpectedSuccesses)
        record["errors"] = len(result.errors)
        record["skipped"] = len(result.skipped) + len(result.expectedFailures)
        if any(test.id() not in expected_ids for test, _ in result.errors):
            record["diagnostics"].append("Class/module setup produced an error outside an individual selected test.")
    except Exception as error:
        record["errors"] += 1
        record["diagnostics"].append(type(error).__name__ + ": " + str(error))
    finally:
        try:
            changed = [name for name, data in frozen.items() if read(TOOL / name) != data]
            record["sourceInputsUnchanged"] = bool(frozen) and not changed
            if changed:
                record["errors"] += 1
                record["diagnostics"].append("Frozen inputs changed during the run: " + ", ".join(changed))
        except (OSError, ValueError) as error:
            record["errors"] += 1
            record["diagnostics"].append("Final input comparison failed: " + str(error))
        success = (result is not None and record["executed"] and record["sourceInputsUnchanged"]
                   and record["testsRun"] == record["passed"] == 13
                   and record["failed"] == record["errors"] == record["skipped"] == 0
                   and {item["name"] for item in record["tests"]} == set(expected_ids))
        record["status"] = "PASS" if success else "FAIL"
        record["finishedUtc"] = datetime.now(timezone.utc).isoformat()
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(record, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
    print("RC13 focused source contracts: " + record["status"] + "; " + str(record["passed"]) + " PASS; native/T11 NOT_RUN")
    return 0 if success else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    no_redirects(args.output)
    output = args.output.resolve()
    artifacts = (REPO / "artifacts").resolve()
    if not output.is_relative_to(artifacts) or output == artifacts or output.suffix.lower() != ".json" or output.exists():
        raise SystemExit("Use a new .json output below repository artifacts; existing evidence is preserved.")
    return run(output)


if __name__ == "__main__":
    raise SystemExit(main())
