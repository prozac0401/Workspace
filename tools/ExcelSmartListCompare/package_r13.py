"""Package RC13 only after exact-source build, focused and narrow native evidence.

This is an unsigned focused-wording evaluation profile, never full acceptance.
Missing/failed evidence denies packaging, except the explicit, narrowly validated
RC13 StatusBar limitation decision. R12's no-tests decision is not reused.
The command may compile Inno Setup; it never starts Excel, installs or publishes.
BuildOnly requires separately approved temporary VBOM access and restored security.
Native/installation records must come from later actual owned trials. An existing
user R12 installation is not authority to remove/upgrade it or fabricate T11 PASS.
"""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

REPO = Path(__file__).resolve().parents[2]
TOOL = REPO / "tools/ExcelSmartListCompare"
VERSION = "0.2.0-rc.13"
FILE_VERSION = "0.2.0.13001"
BASE = "excel-smart-list-compare-v0.2.0-rc.12"
PROFILE = "focused-wording-evaluation"
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
FOCUSED_TEST_NAMES = {"test_usability.UsabilitySourceContracts." + name for name in FOCUSED_METHODS}
EXCLUDED_TEST_NAME = "test_usability.UsabilitySourceContracts.test_difference_is_one_sheet_and_preview_has_locations"
COMPONENTS = {
    "CSLCList": "CSLCList.cls", "CSLCAppEvents": "CSLCAppEvents.cls",
    "modSLCNormalize": "modSLCNormalize.bas", "modSLCMain": "modSLCMain.bas",
    "modSLCReport": "modSLCReport.bas", "ThisWorkbook": "ThisWorkbook_events.txt",
}
INPUTS = tuple(COMPONENTS.values()) + ("customUI14.xml",)
PAIRS = ("CSLCList.cls", "CSLCAppEvents.cls", "modSLCNormalize.bas",
         "modSLCMain.bas", "modSLCReport.bas")
GUIDANCE = '    rows.Add Array("원본을 수정했다면", "수정한 범위를 선택해 [첫 번째 목록 바꾸기]를 누르세요. 이 파일은 담았을 때의 내용이며 자동으로 바뀌지 않습니다.")'
UNCHANGED = tuple("src/" + name for name in INPUTS if name not in ("modSLCMain.bas", "modSLCReport.bas")) + (
    "src/CSLCList_utf8.cls", "src/CSLCAppEvents_utf8.cls", "src/modSLCNormalize_utf8.bas",
    "Install.cmd", "Uninstall.cmd", "installer/SingleFile.iss")
SNAPSHOT = tuple("src/" + name for name in INPUTS) + tuple(
    "src/" + Path(name).stem + "_utf8" + Path(name).suffix for name in PAIRS) + (
    "Setup.ps1", "Install.cmd", "Uninstall.cmd", "installer/SingleFile.iss", "package_r13.py",
    "tests/export_ascii.py", "tests/audit_candidate.py", "tests/test_usability.py", "tests/test_reference.py",
    "tests/run_rc13_focused.py", "tests/test_rc13_known_statusbar_gate.py",
    "tests/Build-ExcelCandidate.ps1", "tests/Invoke-IsolatedExcelCandidate.ps1",
    "docs/RC13_USER_GUIDE.md", "docs/RC13_RELEASE_REPORT.md", "docs/ACCEPTANCE_TESTS.md",
    "docs/ADR-0021-R13-focused-wording-evaluation.md",
    "docs/ADR-0022-R13-known-statusbar-evaluation.md")
NATIVE_CHECKS = ("summaryGuidanceObserved", "previousPreviewUnchanged", "previewNotAutoRefreshed",
                 "replaceActionUsed", "newPreviewUpdated", "originalWorkbookPreserved",
                 "excelGlobalsPreserved", "securitySettingsPreserved", "existingInstallationPreserved",
                 "existingExcelPreserved", "ownedResultsClosed", "excelExited")
INSTALL_CHECKS = ("installedExactCandidate", "normalExcelStart", "comparisonExecuted",
                  "resultWorkbookObserved", "sourceWorkbookPreserved", "userSettingsPreserved",
                  "unrelatedAddinsPreserved", "securitySettingsPreserved", "removalCompleted",
                  "preexistingProductStateRestored", "ownedResultsClosed", "excelExited")
KNOWN_STATUSBAR_ID = "STATUSBAR_BOOLEAN_FALSE_TO_STRING_FALSE"
KNOWN_STATUSBAR_CANDIDATE_SHA256 = "484419befa0cd763635b1f9592cff43bd13e657e19d5a693d76a78fa071ed14e"
KNOWN_STATUSBAR_DECISION = "ADR-0022-R13-known-statusbar-evaluation.md"
KNOWN_STATUSBAR_AUTHORITY = "USER_REQUESTED_ANALYSIS_AND_RELEASE_CONDITION_ADJUSTMENT"
KNOWN_STATUSBAR_FIELDS = ("knownLimitation", "globalDifferences", "statusBarUiText",
                         "globalsBefore", "globalsAfter", "globalsAfterActions")
NATIVE_ACTIONS = ("capture", "preview-original", "preview-stale", "replace", "preview-updated")
GLOBAL_TYPES = {"StatusBar": None, "ScreenUpdating": "System.Boolean", "EnableEvents": "System.Boolean",
                "DisplayAlerts": "System.Boolean", "Calculation": "System.Int32", "Interactive": "System.Boolean",
                "EnableCancelKey": "System.Int32", "AutomationSecurity": "System.Int32"}
KNOWN_STATUSBAR_PUBLIC_REASON = (
    'Boolean False becomes String "FALSE" and remains visible after the observed native flow. '
    'The exact cause is not established. This is an accepted UI limitation for RC13 evaluation only; '
    'the native restoration failure is preserved, not relabeled PASS.')
PRIVATE = re.compile(r"(?i)(?:file://|[A-Z]:[\\/](?:Users|Documents and Settings)[\\/]|"
                     r"[\\/](?:home|Users)[\\/]|\\\\[^\\\s]+\\|(?:artifacts|\.tools)[\\/]|"
                     r"[A-Za-z0-9_.-]+\.private\.(?:json|log|bin|txt))")


class PackageError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def no_redirects(path):
    for item in (path.absolute(), *path.absolute().parents):
        try:
            stat = item.lstat()
        except FileNotFoundError:
            continue
        if item.is_symlink() or getattr(stat, "st_file_attributes", 0) & 0x400:
            raise PackageError("Input/output paths must not traverse symlinks or reparse points.")


def read(path):
    no_redirects(path)
    return path.read_bytes()


def parse_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise PackageError("Duplicate evidence field: " + key)
            result[key] = value
        return result
    value = json.loads(data.decode("utf-8-sig"), object_pairs_hook=unique)
    if not isinstance(value, dict):
        raise PackageError("Evidence must be a JSON object.")
    return value


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO)


def normalized(data):
    return data.replace(b"\r\n", b"\n")


def scope_guard(snapshot, exporter):
    def baseline(name):
        return normalized(git("show", BASE + ":tools/ExcelSmartListCompare/" + name))
    for name in UNCHANGED:
        if normalized(snapshot[name]) != baseline(name):
            raise PackageError("RC13 narrow source scope exceeded: " + name)
    for suffix in (".bas", "_utf8.bas"):
        name = "src/modSLCMain" + suffix
        if normalized(snapshot[name]).replace(b'"0.2.0-rc.13"', b'"0.2.0-rc.12"') != baseline(name):
            raise PackageError("Main module may change its RC12 version string only: " + name)
    setup = normalized(snapshot["Setup.ps1"])
    if setup.replace(b"$InstallerVersion = '0.2.0-rc.13'", b"$InstallerVersion = '0.2.0-rc.12'") != baseline("Setup.ps1"):
        raise PackageError("Installer engine may change its RC12 version string only.")
    name = "src/modSLCReport_utf8.bas"
    old = baseline(name).decode("utf-8").splitlines()
    new = normalized(snapshot[name]).decode("utf-8").splitlines()
    old_guidance = [i for i, line in enumerate(old) if 'rows.Add Array("원본을 수정했다면",' in line]
    new_guidance = [i for i, line in enumerate(new) if 'rows.Add Array("원본을 수정했다면",' in line]
    if len(old_guidance) != 1 or old_guidance != new_guidance or new[new_guidance[0]] != GUIDANCE:
        raise PackageError("Expected exactly the selected RC13 summary guidance line.")
    new[new_guidance[0]] = old[old_guidance[0]]
    if new != old:
        raise PackageError("Report logic/layout must remain the RC12 source outside one summary line.")
    old_ascii = baseline("src/modSLCReport.bas").decode("ascii").splitlines()
    new_ascii = normalized(snapshot["src/modSLCReport.bas"]).decode("ascii").splitlines()
    index = new_guidance[0]
    if (len(new_ascii) != len(old_ascii) or new_ascii[index] != exporter.export_line(GUIDANCE)
            or old_ascii[index] != exporter.export_line(old[old_guidance[0]])):
        raise PackageError("RC12/current ASCII report snapshot is not the exact corresponding summary line.")
    new_ascii[index] = old_ascii[index]
    if new_ascii != old_ascii:
        raise PackageError("ASCII report must also differ from the actual RC12 tag in that one line only.")
    for filename in PAIRS:
        utf8 = "src/" + Path(filename).stem + "_utf8" + Path(filename).suffix
        generated = "\n".join(exporter.export_line(line) for line in snapshot[utf8].decode("utf-8").splitlines()) + "\n"
        if normalized(snapshot["src/" + filename]) != generated.encode("ascii"):
            raise PackageError("ASCII import and UTF-8 review source differ: " + filename)
    if snapshot["src/modSLCMain.bas"].count(b'SLC_ReleaseVersion = "0.2.0-rc.13"') != 1:
        raise PackageError("Exactly one current release-version declaration is required.")
    return {"baselineTag": BASE, "baselineCommit": git("rev-parse", BASE + "^{commit}").decode().strip(),
            "report": "one selected summary guidance line only", "mainAndSetup": "RC13 version only",
            "asciiUtf8SourcesMatch": True, "unchangedFiles": list(UNCHANGED)}


def exact_run(record, exact, hashes, scope, checks):
    if (record.get("schemaVersion") != 1 or record.get("status") != "PASS"
            or record.get("releaseVersion") != VERSION or record.get("scope") != scope
            or type(record.get("flowCount")) is not int or record.get("flowCount") != 1 or record.get("failure") is not None
            or record.get("cleanupErrors") != [] or record.get("fullAcceptancePassed") is not False
            or record.get("releaseApproved") is not False or record.get("sourceHashes") != hashes
            or any(record.get(key) != exact for key in ("expectedSha256", "actualSha256", "finalSha256"))
            or any(record.get("checks", {}).get(key) != "PASS" for key in checks)):
        raise PackageError("Missing actual complete exact-candidate evidence: " + scope)


def native_evidence(record, exact, hashes, accept_known_statusbar=False, decision_sha256=None):
    """Schema 1 keeps the all-PASS contract. Schema 2 is a preserved FAIL with
    exactly one declared/observed StatusBar delta, explicitly opted into by CLI.
    Both schemas still require actual native UI, exact source/candidate and owned cleanup.
    Schema 2 additionally binds its decision to the frozen ADR-0022 bytes. Its
    globalsBefore/After are product-action baselines, after intentional security prep.
    No raw record/check is modified by this function.
    """
    if record.get("status") == "PASS":
        if any(name in record for name in KNOWN_STATUSBAR_FIELDS):
            raise PackageError("Schema 1 PASS cannot carry schema 2 failure/exception evidence.")
        exact_run(record, exact, hashes, "preview-summary-and-replace", NATIVE_CHECKS)
        if record.get("nativeUiObserved") is not True:
            raise PackageError("Actual native UI evidence is required.")
        return {"status": "PASS", "excelGlobalsPreserved": "PASS", "acceptedKnownLimitation": None}
    if accept_known_statusbar is not True:
        raise PackageError("Native FAIL requires explicit --accept-known-statusbar-limitation.")
    if exact != KNOWN_STATUSBAR_CANDIDATE_SHA256:
        raise PackageError("ADR-0022 accepts the known limitation only for its actually observed RC13 candidate SHA.")
    checks = record.get("checks")
    if (record.get("schemaVersion") != 2 or record.get("status") != "FAIL"
            or record.get("releaseVersion") != VERSION or record.get("scope") != "preview-summary-and-replace"
            or type(record.get("flowCount")) is not int or record.get("flowCount") != 1
            or "failure" not in record or record["failure"] is not None or record.get("cleanupErrors") != []
            or record.get("fullAcceptancePassed") is not False or record.get("releaseApproved") is not False
            or record.get("nativeUiObserved") is not True or record.get("sourceHashes") != hashes
            or any(record.get(key) != exact for key in ("expectedSha256", "actualSha256", "finalSha256"))
            or not isinstance(checks, dict) or set(checks) != set(NATIVE_CHECKS)
            or checks.get("excelGlobalsPreserved") != "FAIL"
            or any(checks[name] != "PASS" for name in NATIVE_CHECKS if name != "excelGlobalsPreserved")):
        raise PackageError("Known StatusBar acceptance requires one actual exact-candidate flow with no other failed/incomplete check.")
    limitation = record.get("knownLimitation")
    if (not isinstance(limitation, dict)
            or set(limitation) != {"id", "decision", "decisionSha256", "reason", "evaluationOnly", "authorizationRecorded", "decisionAuthority"}
            or limitation["id"] != KNOWN_STATUSBAR_ID or limitation["decision"] != KNOWN_STATUSBAR_DECISION
            or not isinstance(decision_sha256, str) or not re.fullmatch(r"[a-f0-9]{64}", decision_sha256)
            or limitation["decisionSha256"] != decision_sha256
            or not isinstance(limitation["reason"], str) or not limitation["reason"].strip()
            or limitation["evaluationOnly"] is not True or limitation["authorizationRecorded"] is not True
            or limitation["decisionAuthority"] != KNOWN_STATUSBAR_AUTHORITY):
        raise PackageError("Known limitation must match the explicit RC13 evaluation decision and frozen ADR-0022 hash.")
    before, after = record.get("globalsBefore"), record.get("globalsAfter")
    actions = record.get("globalsAfterActions")
    if (not isinstance(actions, list) or len(actions) != len(NATIVE_ACTIONS)
            or any(not isinstance(item, dict) or set(item) != {"action", "globals"} for item in actions)
            or tuple(item["action"] for item in actions) != NATIVE_ACTIONS):
        raise PackageError("Typed globals after all five actual native actions are required in order.")
    for values in (before, after, *(item["globals"] for item in actions)):
        if not isinstance(values, dict) or set(values) != set(GLOBAL_TYPES):
            raise PackageError("All eight typed Excel globals are required.")
        for name, expected_type in GLOBAL_TYPES.items():
            typed = values[name]
            if not isinstance(typed, dict) or set(typed) != {"type", "value"}:
                raise PackageError("Each Excel global needs exact type/value evidence.")
            if name != "StatusBar" and (typed["type"] != expected_type
                    or type(typed["value"]) is not (bool if expected_type == "System.Boolean" else int)):
                raise PackageError("Other Excel global type/value evidence is invalid: " + name)
    if (before["StatusBar"]["type"] != "System.Boolean" or before["StatusBar"]["value"] is not False
            or after["StatusBar"]["type"] != "System.String" or type(after["StatusBar"]["value"]) is not str
            or after["StatusBar"]["value"] != "FALSE"):
        raise PackageError('Only actual Boolean False -> String "FALSE" is accepted; strings/coerced values are not the baseline.')
    if record.get("statusBarUiText") != "FALSE" or type(record.get("statusBarUiText")) is not str:
        raise PackageError('Actual visible StatusBar text "FALSE" must be recorded.')
    differences = [name for name in GLOBAL_TYPES if before[name] != after[name]]
    if differences != ["StatusBar"] or record.get("globalDifferences") != ["StatusBar"]:
        raise PackageError("StatusBar must be the only observed and declared Excel global delta.")
    for item in actions:
        values = item["globals"]
        if (values["StatusBar"] != after["StatusBar"]
                or [name for name in GLOBAL_TYPES if before[name] != values[name]] != ["StatusBar"]):
            raise PackageError("An intermediate native action has an additional or different global delta: " + item["action"])
    if actions[-1]["globals"] != after:
        raise PackageError("Final globals must match the last actual native action.")
    return {"status": "FAIL", "excelGlobalsPreserved": "FAIL",
            "statusBar": 'FAIL: Boolean False -> String "FALSE"; visible UI text persists',
            "acceptedKnownLimitation": {"id": KNOWN_STATUSBAR_ID, "decision": KNOWN_STATUSBAR_DECISION,
                "decisionSha256": decision_sha256, "evaluationOnly": True,
                "decisionAuthority": KNOWN_STATUSBAR_AUTHORITY,
                "reason": KNOWN_STATUSBAR_PUBLIC_REASON},
            "otherExcelGlobalsPreserved": "PASS"}


def evidence_guard(args, snapshot, sources, auditor):
    candidate = read(args.candidate)
    exact = digest(candidate)
    hashes = {name: digest(value) for name, value in sources.items()}
    evidence_data = {name: read(getattr(args, name)) for name in (
        "build_record", "source_audit", "focused_record", "native_record", "install_record")}
    records = {name: parse_json(data) for name, data in evidence_data.items()}
    build = records["build_record"]
    inputs = build.get("inputHashes", [])
    if (not isinstance(inputs, list) or len(inputs) != len(INPUTS)
            or {item.get("name") for item in inputs} != set(INPUTS)
            or {item.get("name"): item.get("sha256") for item in inputs} != hashes):
        raise PackageError("Build input hashes must match all seven current import/RibbonX inputs.")
    if (build.get("mode") != "BuildOnly" or build.get("status") != "PASS" or build.get("tests") != []
            or not str(build.get("runtimeTests", "")).startswith("NOT_RUN")
            or build.get("releaseVersion") != VERSION or build.get("cleanupErrors") != []
            or build.get("inMemoryImportAudit") != "PASS" or build.get("releaseVersionSource") != "imported-source"
            or any(build.get(key) is not True for key in ("candidateSaved", "accessRestored", "installedPreserved", "existingExcelPreserved", "excelExited"))
            or Path(build.get("candidatePath", "")).resolve() != args.candidate.resolve()
            or any(build.get(key) != exact for key in ("finalSha256", "expectedSha256"))):
        raise PackageError("RC13 needs a successful exact-file BuildOnly audit with complete owned cleanup.")
    audit = records["source_audit"]
    serialized, package = audit.get("serializedVba") or {}, audit.get("package") or {}
    if (audit.get("status") != "PASS" or audit.get("errors") != [] or audit.get("sourceHashes") != hashes
            or any(audit.get(key) != exact for key in ("xlamSha256Before", "xlamSha256After"))
            or audit.get("scriptSha256") != digest(snapshot["tests/audit_candidate.py"])
            or serialized.get("status") != "PASS" or serialized.get("errors") != [] or package.get("status") != "PASS"):
        raise PackageError("Current saved XLAM needs a matching serialized source/RibbonX audit.")
    modules, seen, empty = serialized.get("modules", []), set(), 0
    if len(modules) != 7 or len(audit.get("extractedModules", [])) != 7:
        raise PackageError("Exactly seven current XLAM modules must be audited.")
    for item in modules:
        component = item.get("component")
        if item.get("status") != "PASS":
            raise PackageError("Every serialized module must PASS.")
        if component is None and item.get("kind") == "empty worksheet module":
            empty += 1
            continue
        if component not in COMPONENTS or component in seen:
            raise PackageError("Unexpected or duplicate serialized component.")
        wanted = digest(auditor.canonicalize_vba(sources[COMPONENTS[component]].decode("ascii")).encode("utf-8"))
        if any(item.get(key) != wanted for key in ("sourceNormalizedSha256", "serializedNormalizedSha256")):
            raise PackageError("Serialized module does not match the frozen current source.")
        seen.add(component)
    if seen != set(COMPONENTS) or empty != 1:
        raise PackageError("Required modules or the one empty worksheet module are missing.")
    inspected, _ = auditor.inspect_package(io.BytesIO(candidate), sources["customUI14.xml"])
    if any(package.get(key) != inspected.get(key) for key in ("ribbonSha256", "vbaProjectSha256", "menuCount", "workbookCodeName", "worksheetCodeNames")):
        raise PackageError("Actual XLAM structure/RibbonX no longer matches its audit.")
    focused = records["focused_record"]
    tests = focused.get("tests", [])
    utf8_hashes = {Path(name).stem + "_utf8" + Path(name).suffix:
                   digest(snapshot["src/" + Path(name).stem + "_utf8" + Path(name).suffix]) for name in PAIRS}
    exclusions = focused.get("excludedTests", [])
    if (focused.get("schemaVersion") != 1 or focused.get("status") != "PASS" or focused.get("releaseVersion") != VERSION
            or focused.get("scope") != "usability-source-contracts" or focused.get("sourceHashes") != hashes
            or focused.get("utf8SourceHashes") != utf8_hashes or focused.get("sourceInputsUnchanged") is not True
            or focused.get("testSourceSha256") != digest(snapshot["tests/test_usability.py"])
            or focused.get("referenceSourceSha256") != digest(snapshot["tests/test_reference.py"])
            or focused.get("runnerSourceSha256") != digest(snapshot["tests/run_rc13_focused.py"])
            or any(type(focused.get(key)) is not int for key in ("passed", "failed", "errors"))
            or focused.get("passed") != 13 or focused.get("failed") != 0 or focused.get("errors") != 0
            or focused.get("executed") is not True or focused.get("testsRun") != 13 or focused.get("skipped") != 0
            or focused.get("fullAcceptancePassed") is not False or focused.get("releaseApproved") is not False
            or len(tests) != 13 or {item.get("name") for item in tests} != FOCUSED_TEST_NAMES
            or focused.get("expectedTestNames") != ["test_usability.UsabilitySourceContracts." + name for name in FOCUSED_METHODS]
            or len(exclusions) != 1 or exclusions[0].get("name") != EXCLUDED_TEST_NAME
            or exclusions[0].get("status") != "NOT_RUN" or not exclusions[0].get("reason")
            or focused.get("earlierPartialAggregate", {}).get("passed") != 82
            or focused.get("earlierPartialAggregate", {}).get("failed") != 1
            or focused.get("earlierPartialAggregate", {}).get("errors") != 2
            or focused.get("earlierPartialAggregate", {}).get("currentRun") is not False
            or any(item.get("status") != "PASS" for item in tests)):
        raise PackageError("Actual focused 13 PASS/0 FAIL/0 ERROR must match the current sources/test revision.")
    native = native_evidence(records["native_record"], exact, hashes,
                             getattr(args, "accept_known_statusbar_limitation", False),
                             digest(snapshot["docs/" + KNOWN_STATUSBAR_DECISION]))
    exact_run(records["install_record"], exact, hashes, "T11-install-compare-result-remove", INSTALL_CHECKS)
    if records["native_record"].get("nativeUiObserved") is not True or records["install_record"].get("actuallyInstalled") is not True:
        raise PackageError("Source-only, simulated or NOT_RUN records cannot satisfy native/installation gates.")
    return candidate, exact, {name: digest(data) for name, data in evidence_data.items()}, native


def public_text(data, name):
    if PRIVATE.search(data.decode("utf-8-sig")):
        raise PackageError("Private path/diagnostic reference in public text: " + name)


def write_zip(path, files):
    if any(name.startswith("/") or ".." in Path(name).parts or "\\" in name or ".private." in name for name in files):
        raise PackageError("Unsafe/private ZIP member.")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            archive.writestr(name, data)
    with zipfile.ZipFile(path) as archive:
        if len(archive.namelist()) != len(files) or set(archive.namelist()) != set(files) or archive.testzip() is not None:
            raise PackageError("ZIP membership/integrity check failed.")
        if any(archive.read(name) != value for name, value in files.items()):
            raise PackageError("ZIP byte verification failed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("candidate", "build-record", "source-audit", "focused-record", "native-record", "install-record", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--iscc", type=Path, default=Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"))
    parser.add_argument("--accept-known-statusbar-limitation", action="store_true",
                        help="Accept only the frozen ADR-0022 RC13 Boolean-False StatusBar limitation; keep its native FAIL.")
    args = parser.parse_args()
    no_redirects(args.output)
    output = args.output.resolve()
    artifacts = (REPO / "artifacts").resolve()
    if output == artifacts or not output.is_relative_to(artifacts) or output.exists():
        raise PackageError("Use a fresh output directory below repository artifacts.")
    if args.candidate.suffix.lower() != ".xlam":
        raise PackageError("An explicit current RC13 XLAM is required.")
    # Load all evidence before invoking compiler or creating any output.
    records_present = (args.build_record, args.source_audit, args.focused_record, args.native_record, args.install_record)
    if any(not path.is_file() for path in records_present):
        raise PackageError("Publication denied: required build/focused/native/installation evidence is missing.")
    snapshot = {name: read(TOOL / name) for name in SNAPSHOT}
    exporter = module(TOOL / "tests/export_ascii.py", "rc13_ascii_exporter")
    auditor = module(TOOL / "tests/audit_candidate.py", "rc13_source_auditor")
    scope = scope_guard(snapshot, exporter)
    sources = {name: snapshot["src/" + name] for name in INPUTS}
    candidate, exact, evidence_hashes, native = evidence_guard(args, snapshot, sources, auditor)
    commit = git("rev-parse", "HEAD").decode().strip()
    renderer_path = REPO / "scripts/package-excel-launcher-release.py"
    render_source = read(renderer_path)
    renderer = module(renderer_path, "rc13_public_renderer")
    frozen = {"tools/ExcelSmartListCompare/" + name: data for name, data in snapshot.items()}
    frozen["scripts/package-excel-launcher-release.py"] = render_source
    for name in ("docs/policies/tools.md", "docs/policies/documentation.md",
                 "docs/tools/excel-list-compare/specification.md",
                 "docs/tools/excel-list-compare/r11-specification.md",
                 "docs/tools/excel-list-compare/r12-specification.md",
                 "docs/tools/excel-list-compare/r13-specification.md",
                 "docs/delivery/excel-smart-list-compare-rc13-20261003.md"):
        frozen[name] = read(REPO / name)
    for name in ("docs/RC13_USER_GUIDE.md", "docs/RC13_RELEASE_REPORT.md"):
        content = renderer.markdown.markdown(snapshot[name].decode("utf-8-sig"), extensions=["tables", "fenced_code"])
        for relative in set(re.findall(r'<img[^>]+src="([^"]+)"', content)):
            image = ((TOOL / name).parent / relative).resolve()
            if not image.is_relative_to(TOOL / "docs/images"):
                raise PackageError("Unexpected public image reference: " + relative)
            frozen[image.relative_to(REPO).as_posix()] = read(image)
    for name, data in frozen.items():
        if normalized(data) != normalized(git("show", commit + ":" + name)):
            raise PackageError("Commit every RC13 packaging input before packaging: " + name)
    if not args.iscc.is_file():
        raise PackageError("Inno Setup compiler is missing.")
    no_redirects(args.iscc)
    for name in ("docs/RC13_USER_GUIDE.md", "docs/RC13_RELEASE_REPORT.md"):
        public_text(snapshot[name], name)
    history = snapshot["docs/RC13_RELEASE_REPORT.md"].decode("utf-8-sig")
    if any(text not in history for text in ("82 PASS", "1 FAIL", "2 ERROR")):
        raise PackageError("The report must preserve the earlier 82 PASS / 1 FAIL / 2 ERROR aggregate and its scope/causes.")
    output.mkdir(parents=True)
    release, verification, payload = output / "Release", output / "Verification", output / "payload"
    for directory in (release, verification, payload):
        directory.mkdir()
    header = ("# Excel 명단 비교 RC13 · 서명 없는 평가 후보\n\n"
              "선택한 요약 안내의 집중 확인 범위이며 전체 인수·안정판·조직 배포 승인을 뜻하지 않습니다. "
              "현재 후보의 실제 확인과 기존 실패·미실행 범위는 Verification의 기록을 따릅니다.\n\n")
    guide = (header + snapshot["docs/RC13_USER_GUIDE.md"].decode("utf-8-sig")).encode("utf-8")
    (release / "README.md").write_bytes(guide)
    (release / "ExcelSmartListCompare.xlam").write_bytes(candidate)
    for name in ("Setup.ps1", "Install.cmd", "Uninstall.cmd"):
        (release / name).write_bytes(snapshot[name])
    renderer.render(TOOL / "docs/RC13_USER_GUIDE.md", release / "QuickGuide.html", commit, title="Excel 명단 비교 RC13 평가 후보", html_names={})
    quick = release / "QuickGuide.html"
    quick.write_text(quick.read_text(encoding="utf-8").replace("<main>",
        "<main><p><strong>서명 없는 RC13 평가 후보.</strong> 집중 확인 범위이며 전체 인수·안정판·조직 배포 승인을 뜻하지 않습니다.</p>", 1), encoding="utf-8")
    pins, definitions = {}, []
    for name, macro in {"Install.cmd": "InstallHash", "Uninstall.cmd": "UninstallHash", "Setup.ps1": "SetupHash", "README.md": "ReadmeHash", "ExcelSmartListCompare.xlam": "XlamHash"}.items():
        shutil.copyfile(release / name, payload / name)
        pins[name] = digest(read(payload / name))
        definitions.append(f'#define {macro} "{pins[name]}"\n')
    (payload / "PayloadHashes.iss").write_text("".join(definitions), encoding="ascii")
    (payload / "manager.id").write_text("SLC-68A45C44-2026-OneFile-1\n", encoding="ascii")
    result = subprocess.run([str(args.iscc), "/Qp", "/DPayloadDir=" + str(payload), "/DEngineVersion=" + VERSION,
                             "/DFileVersion=" + FILE_VERSION, "/O" + str(output), str(TOOL / "installer/SingleFile.iss")],
                            cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / "compiler.private.log").write_bytes(result.stdout)
    exe = output / ("ExcelSmartListCompare-" + VERSION + "-Setup.exe")
    if result.returncode or not exe.is_file():
        raise PackageError("Inno Setup failed; partial output remains private and must not be published.")
    if (any(read(REPO / name) != data for name, data in frozen.items()) or read(args.candidate) != candidate
            or any(digest(read(getattr(args, name))) != value for name, value in evidence_hashes.items())):
        raise PackageError("Frozen source/candidate changed during packaging; publication denied.")
    validation = {"schemaVersion": 1, "product": "ExcelSmartListCompare", "version": VERSION,
                  "releaseProfile": PROFILE, "releaseDecision": "FOCUSED_EVALUATION_ONLY",
                  "fullAcceptancePassed": False, "releaseApproved": False, "stablePublishAllowed": False,
                  "prereleaseRequired": True, "sourceCommit": commit, "sourceScope": scope,
                  "xlamSha256": exact, "exeSha256": digest(read(exe)), "fileVersion": FILE_VERSION,
                  "compilerSha256": digest(read(args.iscc)),
                  "codeSigning": "UNSIGNED", "payloadSha256": pins, "privateEvidenceIncluded": False,
                  "sourceInputSha256": {name: digest(data) for name, data in frozen.items()},
                  "evidenceSha256": evidence_hashes,
                  "nativeEvidence": native,
                  "checks": {"buildOnlyAndCleanup": "PASS", "sevenModulesAndRibbonX": "PASS",
                             "focusedSourceContracts": "13 PASS / 0 FAIL / 0 ERROR",
                             "nativeSummaryReplace": ("PASS WITH KNOWN LIMITATION: one actual flow"
                                 if native["acceptedKnownLimitation"] else "PASS: one flow"),
                             "T11Installation": "PASS: one flow"},
                  "notEstablished": ["fullAcceptance", "fullPythonSuite", "fullExcelSuite", "performance", "physicalEscCancellation",
                                     "allInstallerLifecycleCases", "newWrapperActualInstallation", "freshProfile", "otherOfficeBuilds", "organizationalApproval"]
                                     + (["defaultBooleanStatusBarRestoration"] if native["acceptedKnownLimitation"] else []),
                  "historicalResults": "Existing failures/errors and incomplete results remain in the release report; narrow PASS does not resolve them.",
                  "earlierPartialAggregate": {"passed": 82, "failed": 1, "errors": 2, "currentRun": False,
                                              "status": "HISTORICAL_INCOMPLETE: see preserved causes and limits in Completion-Report.html"},
                  "packagingDoesNotInstallOrPublish": True}
    data = (json.dumps(validation, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    public_text(data, "Validation.json")
    (verification / "Validation.json").write_bytes(data)
    renderer.render(TOOL / "docs/RC13_RELEASE_REPORT.md", verification / "Completion-Report.html", commit,
                    title="Excel 명단 비교 RC13 집중 검증 기록", html_names={"RC13_RELEASE_REPORT.md": "Completion-Report.html"})
    for path in (*release.glob("*.html"), *verification.glob("*.html")):
        public_text(read(path), path.name)
    assets = [exe]
    prefix = "ExcelSmartListCompare-" + VERSION
    for directory, suffix in ((release, "win-x64"), (verification, "Verification")):
        files = {path.name: read(path) for path in directory.iterdir()}
        sums = "".join(digest(value) + "  " + name + "\n" for name, value in sorted(files.items())).encode("ascii")
        (directory / "SHA256SUMS.txt").write_bytes(sums)
        files["SHA256SUMS.txt"] = sums
        destination = output / (prefix + "-" + suffix + ".zip")
        write_zip(destination, {directory.name + "/" + name: value for name, value in files.items()})
        assets.append(destination)
    source_zip = output / (prefix + "-Source.zip")
    write_zip(source_zip, {"Workspace/" + name: data for name, data in frozen.items()})
    assets.append(source_zip)
    for path in assets:
        path.with_name(path.name + ".sha256").write_text(digest(read(path)) + "  " + path.name + "\n", encoding="ascii")
    (output / "Package.json").write_text(json.dumps({"version": VERSION, "sourceCommit": commit,
        "releaseProfile": PROFILE, "packageComplete": True, "fullAcceptancePassed": False, "stablePublishAllowed": False,
        "nativeEvidence": native,
        "assets": [{"name": path.name, "bytes": path.stat().st_size, "sha256": digest(read(path))} for path in assets]}, indent=2) + "\n", encoding="utf-8")
    print("RC13 unsigned evaluation package prepared. Full acceptance/stable publication: denied.")


if __name__ == "__main__":
    try:
        main()
    except (PackageError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit("RC13 packaging/publication denied: " + str(error)) from error
