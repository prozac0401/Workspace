"""Create an RC10 local test package from exact-file audit and runtime evidence.

Does not run Excel, install, publish, change security, or waive release acceptance.
An optional --iscc compiles an unsigned wrapper only after local package checks.
"""
import argparse
import hashlib
import html
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile
from urllib.parse import urlsplit

REPO = Path(__file__).resolve().parents[1]
VERSION = "0.2.0-rc.10"
TOOL_PATH = "tools/ExcelSmartListCompare/"
COMPONENTS = {
    "CSLCList": "CSLCList.cls", "CSLCAppEvents": "CSLCAppEvents.cls",
    "modSLCNormalize": "modSLCNormalize.bas", "modSLCMain": "modSLCMain.bas",
    "modSLCReport": "modSLCReport.bas", "ThisWorkbook": "ThisWorkbook_events.txt",
}
SOURCE_FILES = tuple(COMPONENTS.values()) + ("customUI14.xml",)
PAYLOAD_FILES = ("Install.cmd", "Uninstall.cmd", "Setup.ps1", "README.md", "ExcelSmartListCompare.xlam")
SNAPSHOT_FILES = tuple(TOOL_PATH + "src/" + name for name in SOURCE_FILES) + tuple(
    TOOL_PATH + name for name in (
        "src/CSLCList_utf8.cls", "src/CSLCAppEvents_utf8.cls", "src/modSLCNormalize_utf8.bas",
        "src/modSLCMain_utf8.bas", "src/modSLCReport_utf8.bas", "Setup.ps1", "Install.cmd", "Uninstall.cmd",
        "installer/SingleFile.iss", "docs/USABILITY_CANDIDATE_GUIDE.md", "docs/USABILITY_RC10_REPORT.md",
        "docs/ADR-0016-Comparison-usability.md", "docs/ACCEPTANCE_TESTS.md", "docs/RELEASE_README.md",
        "tests/audit_candidate.py", "tests/export_ascii.py", "tests/Build-ExcelCandidate.ps1",
        "tests/windows-usability.ps1",
    )
) + (
    "docs/tools/excel-list-compare/specification.md", "docs/policies/tools.md", "docs/policies/documentation.md",
    "scripts/package-excel-local-candidate.py", "scripts/build-excel-onefile.py",
)
OPTIONAL_SNAPSHOT_FILES = (TOOL_PATH + "tests/Invoke-IsolatedExcelCandidate.ps1",)
CHECK_NAMES = (
    "sourceMatchesBinary", "normalizationAndIntegration", "wordingAndState", "selectionMatrix",
    "cancellation", "autoLoad", "reinstall", "uninstall", "python", "docs", "windowState", "upgrade",
    "contextMenuContent", "nativeContextMenu",
)
STATUSES = {"PASS", "FAIL", "PARTIAL", "NOT_RUN", "NEEDS_MANUAL", "BLOCKED_ENV", "BLOCKED_ENVIRONMENT", "BLOCKED_POLICY"}


class PackageError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def no_redirects(path):
    for item in (path.absolute(), *path.absolute().parents):
        try:
            stat = item.lstat()
        except FileNotFoundError:
            continue
        if item.is_symlink() or getattr(stat, "st_file_attributes", 0) & 0x400:
            raise PackageError("Paths must not traverse a symlink or reparse point")


def fresh_output(path):
    no_redirects(path)
    output = path.resolve()
    artifacts = (REPO / "artifacts").resolve()
    if output == artifacts or not output.is_relative_to(artifacts) or output.exists():
        raise PackageError("Choose a fresh output directory below repository artifacts")
    return output


def read_input(path):
    no_redirects(path)
    return path.read_bytes()


def read_json(data):
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise PackageError("Duplicate JSON field: " + key)
            result[key] = value
        return result
    value = json.loads(data.decode("utf-8-sig"), object_pairs_hook=unique_pairs)
    if not isinstance(value, dict):
        raise PackageError("Evidence must be a JSON object")
    return value


def load_auditor():
    spec = importlib.util.spec_from_file_location("slc_local_source_auditor", REPO / TOOL_PATH / "tests/audit_candidate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_evidence(xlam, audit, runtime, sources):
    exact = digest(xlam)
    if (audit.get("schemaVersion") != 1 or audit.get("status") != "PASS" or audit.get("errors") != []
            or audit.get("xlamSha256Before") != exact or audit.get("xlamSha256After") != exact):
        raise PackageError("Source audit must PASS for the unchanged exact XLAM")
    expected_hashes = {name: digest(data) for name, data in sources.items()}
    if audit.get("sourceHashes") != expected_hashes:
        raise PackageError("Current source files differ from the audited source snapshot")
    auditor = load_auditor()
    if audit.get("scriptSha256") != digest(read_input(REPO / TOOL_PATH / "tests/audit_candidate.py")):
        raise PackageError("Source audit was produced by a different auditor revision")
    package = audit.get("package") or {}
    serialized = audit.get("serializedVba") or {}
    if package.get("status") != "PASS" or serialized.get("status") != "PASS" or serialized.get("errors") != []:
        raise PackageError("Serialized VBA and RibbonX audit must both PASS")
    seen = set()
    for record in serialized.get("modules", []):
        if record.get("status") != "PASS":
            raise PackageError("A serialized module did not PASS")
        name = record.get("component")
        if name is None and record.get("kind") == "empty worksheet module":
            continue
        if name not in COMPONENTS or name in seen:
            raise PackageError("Unexpected or duplicate audited VBA component")
        expected = digest(auditor.canonicalize_vba(sources[COMPONENTS[name]].decode("ascii")).encode("utf-8"))
        if record.get("sourceNormalizedSha256") != expected or record.get("serializedNormalizedSha256") != expected:
            raise PackageError("Serialized module hashes differ from current source")
        seen.add(name)
    if seen != set(COMPONENTS):
        raise PackageError("Source audit is missing required VBA components")
    # Re-check actual Office structure and payload; never trust only a PASS label.
    import io
    inspected, _ = auditor.inspect_package(io.BytesIO(xlam), sources["customUI14.xml"])
    for key in ("ribbonSha256", "vbaProjectSha256", "menuCount", "workbookCodeName", "worksheetCodeNames"):
        if package.get(key) != inspected.get(key):
            raise PackageError("XLAM package no longer matches the serialized audit")
    if (runtime.get("schemaVersion") != 1 or runtime.get("status") != "PASS"
            or runtime.get("releaseVersion") != VERSION
            or any(runtime.get(key) != exact for key in ("expectedSha256", "actualSha256", "finalSha256"))):
        raise PackageError("Runtime evidence must PASS for this exact RC10 XLAM")
    if runtime.get("failure") is not None or runtime.get("cleanupErrors") != [] or runtime.get("excelExited") is not True:
        raise PackageError("Runtime evidence must confirm clean owned-Excel exit")
    if runtime.get("releaseApproved") is not False:
        raise PackageError("Runtime evidence must not claim release approval")
    tests = runtime.get("tests")
    if not isinstance(tests, list) or len(tests) != 2 or {test.get("name") for test in tests} != {"SLC_TestAll", "SLC_UsabilityTests"}:
        raise PackageError("Both exact-file runtime self-tests are required")
    for test in tests:
        if test.get("status") != "PASS" or not isinstance(test.get("result"), str) or not test["result"].startswith("PASS:"):
            raise PackageError("Both actual runtime self-tests must PASS")
    for key in ("nativeInputTests", "installedTests"):
        if runtime.get(key) not in STATUSES - {"PASS"}:
            raise PackageError("Runtime harness must preserve explicit incomplete native and installation checks")
    return exact


def standalone_markdown(text):
    # Repository document links are not published commit links for this dirty-tree
    # candidate. Include their source snapshot separately; leave actual web URLs.
    def link(match):
        label, href = match.groups()
        parsed = urlsplit(href)
        if not parsed.scheme and not parsed.netloc:
            return label + " (원본은 SourceSnapshot.zip 참고)"
        return match[0]
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)


def html_guide(text):
    import markdown
    body = markdown.markdown(text, extensions=["tables", "fenced_code"])
    return ('<!doctype html><html lang="ko"><meta charset="utf-8"><title>Excel 명단 비교 RC10 로컬 시험 후보</title>'
            '<style>body{max-width:960px;margin:32px auto;font:16px/1.6 sans-serif}table{border-collapse:collapse}'
            'td,th{border:1px solid #ddd;padding:8px}code{background:#eee}</style><body>' + body + '</body></html>').encode("utf-8")


def write_zip(path, files):
    if any(name.startswith("/") or ".." in Path(name).parts or "\\" in name for name in files):
        raise PackageError("Unsafe archive member")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            archive.writestr(name, data)
    with zipfile.ZipFile(path) as archive:
        if len(archive.namelist()) != len(files) or set(archive.namelist()) != set(files) or archive.testzip() is not None:
            raise PackageError("Archive membership or integrity failed")
        for name, expected in files.items():
            if archive.read(name) != expected:
                raise PackageError("Archived bytes changed: " + name)
    Path(str(path) + ".sha256").write_text(digest(path.read_bytes()) + "  " + path.name + "\n", encoding="ascii")


def git_state():
    try:
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=REPO, text=True).strip())
        return {"baseCommit": commit, "sourceTreeDirty": dirty}
    except (OSError, subprocess.CalledProcessError):
        return {"baseCommit": None, "sourceTreeDirty": None}


def package_candidate(xlam_path, source_audit_path, runtime_path, output_directory, iscc=None):
    output = fresh_output(output_directory)
    if xlam_path.suffix.lower() != ".xlam":
        raise PackageError("An explicit XLAM candidate is required")
    xlam = read_input(xlam_path)
    audit_data, runtime_data = read_input(source_audit_path), read_input(runtime_path)
    audit, runtime = read_json(audit_data), read_json(runtime_data)
    snapshot = {name: read_input(REPO / name) for name in SNAPSHOT_FILES}
    for name in OPTIONAL_SNAPSHOT_FILES:
        if (REPO / name).is_file():
            snapshot[name] = read_input(REPO / name)
    sources = {name: snapshot[TOOL_PATH + "src/" + name] for name in SOURCE_FILES}
    exact = check_evidence(xlam, audit, runtime, sources)
    if "$InstallerVersion = '" + VERSION + "'" not in snapshot[TOOL_PATH + "Setup.ps1"].decode("utf-8-sig"):
        raise PackageError("Installer version differs from the runtime candidate")
    if iscc is not None and not iscc.is_file():
        raise PackageError("Inno Setup compiler was not found")
    prefix = ("# Excel 명단 비교 RC10 · 로컬 시험 후보\n\n"
              "이 패키지는 로컬 시험용이며 전체 인수·공개 배포·회사 도입 승인을 뜻하지 않습니다. "
              "실제 후보의 소스 대조와 합성 실행은 확인했지만 네이티브 입력과 설치 수명주기는 별도 검증이 필요합니다. "
              "전체 결과는 동봉한 Verification.zip, 정확한 현재 소스는 SourceSnapshot.zip에 있습니다.\n\n")
    guide = prefix + standalone_markdown(snapshot[TOOL_PATH + "docs/USABILITY_CANDIDATE_GUIDE.md"].decode("utf-8-sig"))
    release = {name: snapshot[TOOL_PATH + name] for name in ("Setup.ps1", "Install.cmd", "Uninstall.cmd")}
    release.update({"ExcelSmartListCompare.xlam": xlam, "README.md": guide.encode("utf-8"), "QuickGuide.html": html_guide(guide)})
    release["SHA256SUMS.txt"] = "".join(digest(data) + "  " + name + "\n" for name, data in sorted(release.items())).encode("ascii")
    checks = {name: "NOT_RUN: not established by this local candidate packaging run" for name in CHECK_NAMES}
    checks["sourceMatchesBinary"] = "PASS: serialized source and Office package rechecked for the exact candidate"
    checks["normalizationAndIntegration"] = "PASS: SLC_TestAll and SLC_UsabilityTests on the exact unchanged candidate"
    for name in ("cancellation", "nativeContextMenu"):
        checks[name] = runtime["nativeInputTests"] + ": native input evidence is separate from synthetic self-tests"
    for name in ("autoLoad", "reinstall", "uninstall", "upgrade"):
        checks[name] = runtime["installedTests"] + ": local packaging does not install or modify the existing product"
    validation = {
        "schemaVersion": 1, "product": "Excel Smart List Compare", "installerVersion": VERSION,
        "status": "LOCAL_CANDIDATE", "releaseProfile": "local-candidate", "releaseDecision": "LOCAL_PACKAGE_ONLY",
        "localOnly": True, "fullAcceptancePassed": False, "releaseApproved": False,
        "xlamSha256": exact, "installerSha256": digest(release["Setup.ps1"]),
        "sourceTextSha256": {"src/" + name: digest(data.replace(b"\r\n", b"\n")) for name, data in sources.items()},
        "sourceSnapshotSha256": {name: digest(data) for name, data in snapshot.items()},
        "evidenceSha256": {"sourceAudit": digest(audit_data), "runtime": digest(runtime_data)},
        "checks": checks, "incompleteChecks": [name for name, result in checks.items() if not result.startswith("PASS:")],
        "runtimeTests": [{"name": test["name"], "status": test["status"]} for test in runtime["tests"]],
        "runtimeCleanup": {"excelExited": True, "cleanupErrors": []},
        "nativeInputTests": runtime["nativeInputTests"], "installedTests": runtime["installedTests"],
        "privateEvidenceIncluded": False, "codeSigning": "UNSIGNED", **git_state(),
    }
    validation_data = json_bytes(validation)
    pins = {"engineVersion": VERSION, "packageRevision": 1, "releaseProfile": "local-candidate", "localOnly": True,
            "fullAcceptancePassed": False, "releaseApproved": False,
            "validationFile": "Verification/Candidate-Validation.json", "validationSha256": digest(validation_data),
            "wrapperSha256": digest(snapshot["scripts/build-excel-onefile.py"]),
            "installerWrapperSha256": digest(snapshot[TOOL_PATH + "installer/SingleFile.iss"]),
            "packagerSha256": digest(snapshot["scripts/package-excel-local-candidate.py"]),
            "sha256": {name: digest(release[name]) for name in PAYLOAD_FILES}}
    # Input mismatch never creates an output directory. Partial outputs from an
    # I/O or compiler failure are retained as evidence and never reused.
    output.mkdir(parents=True)
    (output / "Release").mkdir()
    (output / "Verification").mkdir()
    for name, data in release.items():
        (output / "Release" / name).write_bytes(data)
    (output / "Verification/Candidate-Validation.json").write_bytes(validation_data)
    (output / "RC10-Payload.json").write_bytes(json_bytes(pins))
    verification = {
        "Candidate-Validation.json": validation_data,
        "USABILITY_RC10_REPORT.md": snapshot[TOOL_PATH + "docs/USABILITY_RC10_REPORT.md"],
        "USABILITY_CANDIDATE_GUIDE.md": snapshot[TOOL_PATH + "docs/USABILITY_CANDIDATE_GUIDE.md"],
        "RC10-Payload.json": json_bytes(pins),
    }
    stem = "ExcelSmartListCompare-" + VERSION + "-local-candidate"
    install_zip, source_zip, verification_zip = (output / (stem + suffix) for suffix in ("-win-x64.zip", "-SourceSnapshot.zip", "-Verification.zip"))
    write_zip(install_zip, {"Release/" + name: data for name, data in release.items()})
    write_zip(source_zip, snapshot)
    write_zip(verification_zip, {"Verification/" + name: data for name, data in verification.items()})
    # All bytes used by the wrapper are the checked immutable copies above.
    result = {"status": "LOCAL_CANDIDATE", "localOnly": True, "releaseApproved": False,
              "fullAcceptancePassed": False, "xlamSha256": exact, "installZip": str(install_zip),
              "sourceZip": str(source_zip), "verificationZip": str(verification_zip),
              "payloadManifest": str(output / "RC10-Payload.json"), "exe": None}
    if iscc is not None:
        for path, expected in ((REPO / "scripts/build-excel-onefile.py", pins["wrapperSha256"]),
                               (REPO / TOOL_PATH / "installer/SingleFile.iss", pins["installerWrapperSha256"]),
                               (REPO / "scripts/package-excel-local-candidate.py", pins["packagerSha256"])):
            if digest(read_input(path)) != expected:
                raise PackageError("Compiler input changed after source snapshot: " + path.name)
        command = [sys.executable, str(REPO / "scripts/build-excel-onefile.py"),
                   "--release-directory", str(output / "Release"), "--output-directory", str(output / "OneFile"),
                   "--engine-version", VERSION, "--release-profile", "local-candidate",
                   "--payload-manifest", str(output / "RC10-Payload.json"),
                   "--source-audit", str(source_audit_path.resolve()), "--runtime", str(runtime_path.resolve()),
                   "--iscc", str(iscc)]
        completed = subprocess.run(command, capture_output=True)
        (output / "onefile-build.private.log").write_bytes(completed.stdout + completed.stderr)
        if completed.returncode:
            raise PackageError("Local EXE compilation failed; see the retained local build log")
        built = output / "OneFile" / ("ExcelSmartListCompare-" + VERSION + "-Setup.exe")
        metadata = read_json((output / "OneFile/OneFile-Build.json").read_bytes())
        if (metadata.get("releaseProfile") != "local-candidate" or metadata.get("releaseApproved") is not False
                or metadata.get("fullAcceptancePassed") is not False or metadata.get("exeSha256") != digest(built.read_bytes())):
            raise PackageError("Local wrapper metadata does not match the generated EXE")
        result["exe"] = str(built)
    (output / "Local-Candidate.json").write_bytes(json_bytes(result))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xlam", type=Path, required=True)
    parser.add_argument("--source-audit", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--iscc", type=Path, help="Optional existing Inno Setup compiler; never runs the generated installer")
    args = parser.parse_args()
    try:
        result = package_candidate(args.xlam, args.source_audit, args.runtime, args.output_directory, args.iscc)
    except (PackageError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error)) from error
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
