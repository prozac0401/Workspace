"""Build the explicitly authorized R12 wording release without running product tests.

Consumes the isolated helper's BuildOnly record. Earlier release gates remain
unchanged. Private build records are never copied into the public packages.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

REPO = Path(__file__).resolve().parents[2]
TOOL = REPO / "tools/ExcelSmartListCompare"
VERSION = "0.2.0-rc.12"
BASE = "excel-smart-list-compare-v0.2.0-rc.11"
DECISION = "PUBLISH_WORDING_ONLY_WITHOUT_RUNTIME_TESTS"
LITERAL = re.compile(r'"(?:[^"\r\n]|"")*"')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO)


def normalized(data):
    return data.replace(b"\r\n", b"\n")


def baseline(relative):
    return normalized(git("show", BASE + ":tools/ExcelSmartListCompare/" + relative))


def guard_product_scope():
    unchanged = ["src/CSLCList.cls", "src/CSLCList_utf8.cls", "src/CSLCAppEvents.cls",
                 "src/CSLCAppEvents_utf8.cls", "src/modSLCNormalize.bas", "src/modSLCNormalize_utf8.bas",
                 "src/ThisWorkbook_events.txt", "src/customUI14.xml", "Install.cmd", "Uninstall.cmd",
                 "installer/SingleFile.iss"]
    for relative in unchanged:
        if normalized((TOOL / relative).read_bytes()) != baseline(relative):
            raise SystemExit("R12 wording scope exceeded: " + relative)
    main = "src/modSLCMain_utf8.bas"
    if LITERAL.sub('""', (TOOL / main).read_text(encoding="utf-8")) != LITERAL.sub('""', baseline(main).decode("utf-8")):
        raise SystemExit("R12 main module must change string literals only.")
    setup = normalized((TOOL / "Setup.ps1").read_bytes())
    if setup.replace(b"$InstallerVersion = '0.2.0-rc.12'", b"$InstallerVersion = '0.2.0-rc.11'") != baseline("Setup.ps1"):
        raise SystemExit("R12 installer engine must change its version only.")
    report = (TOOL / "src/modSLCReport_utf8.bas").read_text(encoding="utf-8")
    previous = baseline("src/modSLCReport_utf8.bas").decode("utf-8")
    for name in ("WriteReport", "AddDifference", "CountOf", "DictText", "SafeText", "InitBuffer", "PutRow", "FlushRows"):
        pattern = rf"(?ms)^(?:Private|Public) (?:Sub|Function) {name}\b.*?^End (?:Sub|Function)"
        old, new = re.search(pattern, previous), re.search(pattern, report)
        if old is None or new is None or LITERAL.sub('""', old[0]) != LITERAL.sub('""', new[0]):
            raise SystemExit("R12 report data/transaction logic changed: " + name)
    return {"baseline": BASE, "unchangedFiles": unchanged,
            "mainModule": "string literals only", "installerEngine": "version string only",
            "reportDataAndTransactionLogic": "unchanged; display strings only",
            "reportPresentation": "wording, summary rows, widths, merged cells and hidden columns"}


def package(directory, destination):
    paths = sorted(directory.iterdir())
    (directory / "SHA256SUMS.txt").write_text(
        "".join(digest(path) + "  " + path.name + "\n" for path in paths), encoding="ascii")
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(directory.iterdir()):
            archive.write(path, directory.name + "/" + path.name)
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Archive creation failed: " + destination.name)
        for path in directory.iterdir():
            if archive.read(directory.name + "/" + path.name) != path.read_bytes():
                raise SystemExit("Archive content differs: " + path.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--build-record", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--iscc", type=Path, default=Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"))
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(REPO / "artifacts") or output == REPO / "artifacts" or output.exists():
        raise SystemExit("Use a fresh directory below repository artifacts.")
    record = json.loads(args.build_record.read_text(encoding="utf-8-sig"))
    candidate = args.candidate.resolve()
    if (record.get("mode") != "BuildOnly" or record.get("status") != "PASS"
            or record.get("tests") != [] or not record.get("runtimeTests", "").startswith("NOT_RUN")
            or record.get("releaseVersion") != VERSION or record.get("cleanupErrors") != []
            or any(record.get(key) is not True for key in ("candidateSaved", "accessRestored", "installedPreserved", "existingExcelPreserved", "excelExited"))
            or any(record.get(key) != "PASS" for key in ("inMemoryImportAudit", "serializedSourceAudit"))
            or Path(record.get("candidatePath", "")).resolve() != candidate
            or digest(candidate) != record.get("finalSha256") or digest(candidate) != record.get("expectedSha256")):
        raise SystemExit("R12 requires a matching successful BuildOnly record with no product tests and complete cleanup.")
    expected_inputs = {p.name for p in (TOOL / "src").iterdir() if p.name in (
        "CSLCList.cls", "CSLCAppEvents.cls", "modSLCNormalize.bas", "modSLCMain.bas", "modSLCReport.bas", "ThisWorkbook_events.txt", "customUI14.xml")}
    hashes = {item["name"]: item["sha256"] for item in record["inputHashes"]}
    if set(hashes) != expected_inputs or any(digest(TOOL / "src" / name) != value for name, value in hashes.items()):
        raise SystemExit("Build inputs do not match the current source.")
    commit = git("rev-parse", "HEAD").decode().strip()
    names = git("ls-files", "tools/ExcelSmartListCompare", "scripts/package-excel-launcher-release.py").decode().splitlines()
    # Older R11 notes may be edited locally by another task; they are not R12 inputs.
    names = [name for name in names if "/docs/" not in name or name.endswith(("RC12_USER_GUIDE.md", "RC12_RELEASE_REPORT.md", "ADR-0020-R12-wording-release.md"))]
    for name in names:
        if normalized((REPO / name).read_bytes()) != normalized(git("show", commit + ":" + name)):
            raise SystemExit("Commit the release input before packaging: " + name)
    scope = guard_product_scope()
    output.mkdir(parents=True)
    release, verification, payload = output / "Release", output / "Verification", output / "payload"
    for directory in (release, verification, payload):
        directory.mkdir()
    shutil.copyfile(candidate, release / "ExcelSmartListCompare.xlam")
    for name in ("Setup.ps1", "Install.cmd", "Uninstall.cmd"):
        shutil.copyfile(TOOL / name, release / name)
    shutil.copyfile(TOOL / "docs/RC12_USER_GUIDE.md", release / "README.md")
    spec = importlib.util.spec_from_file_location("r12_render", REPO / "scripts/package-excel-launcher-release.py")
    rendering = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rendering)
    rendering.render(TOOL / "docs/RC12_USER_GUIDE.md", release / "QuickGuide.html", commit, title="Excel 명단 비교 R12", html_names={})
    pins = {}
    definitions = []
    for name, macro in {"Install.cmd": "InstallHash", "Uninstall.cmd": "UninstallHash", "Setup.ps1": "SetupHash",
                        "README.md": "ReadmeHash", "ExcelSmartListCompare.xlam": "XlamHash"}.items():
        shutil.copyfile(release / name, payload / name)
        pins[name] = digest(payload / name)
        definitions.append(f'#define {macro} "{pins[name]}"\n')
    (payload / "PayloadHashes.iss").write_text("".join(definitions), encoding="ascii")
    (payload / "manager.id").write_text("SLC-68A45C44-2026-OneFile-1\n", encoding="ascii")
    result = subprocess.run([str(args.iscc), "/Qp", "/DPayloadDir=" + str(payload), "/DEngineVersion=" + VERSION,
                             "/DFileVersion=0.2.0.12001", "/O" + str(output), str(TOOL / "installer/SingleFile.iss")],
                            cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / "compiler.private.log").write_bytes(result.stdout)
    if result.returncode:
        raise SystemExit("Inno Setup failed; see the local compiler log.")
    exe = output / ("ExcelSmartListCompare-" + VERSION + "-Setup.exe")
    if not exe.is_file():
        raise SystemExit("Compiler did not produce the R12 installer.")
    validation = {"schemaVersion": 1, "product": "ExcelSmartListCompare", "version": VERSION,
                  "releaseProfile": "wording-only-no-tests", "releaseDecision": DECISION,
                  "fullAcceptancePassed": False, "sourceCommit": commit,
                  "xlamSha256": digest(candidate), "exeSha256": digest(exe), "payloadSha256": pins,
                  "fileVersion": "0.2.0.12001", "sourceScope": scope,
                  "build": {"mode": "BuildOnly", "savedSourceMatches": True, "releaseVersionRead": VERSION,
                            "excelExited": True, "temporaryAccessRestored": True, "existingInstallationPreserved": True,
                            "compilerSha256": digest(args.iscc), "buildRecordSha256": digest(args.build_record)},
                  "tests": {name: "NOT_RUN: explicitly omitted by the user for the R12 wording release" for name in (
                      "pythonRegression", "excelFunctional", "excelUI", "performance", "cancellation", "installUpgradeUninstall")},
                  "installerExecutedOnUserPc": False}
    (verification / "Validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report_names = {"RC12_RELEASE_REPORT.md": "Completion-Report.html", "ADR-0020-R12-wording-release.md": "Publication-Decision.html"}
    for source, destination in report_names.items():
        rendering.render(TOOL / "docs" / source, verification / destination, commit,
                         title="Excel 명단 비교 R12 제작·배포 기록", html_names=report_names)
    prefix = "ExcelSmartListCompare-" + VERSION
    package(release, output / (prefix + "-win-x64.zip"))
    package(verification, output / (prefix + "-Verification.zip"))
    source_zip = output / (prefix + "-Source.zip")
    subprocess.run(["git", "archive", "--format=zip", "--prefix=Workspace/", "--output=" + str(source_zip), commit], cwd=REPO, check=True)
    assets = [exe, output / (prefix + "-win-x64.zip"), output / (prefix + "-Verification.zip"), source_zip]
    for path in assets:
        path.with_name(path.name + ".sha256").write_text(digest(path) + "  " + path.name + "\n", encoding="ascii")
    (output / "Package.json").write_text(json.dumps({"sourceCommit": commit, "version": VERSION,
        "assets": [{"name": path.name, "bytes": path.stat().st_size, "sha256": digest(path)}
                   for path in sorted(output.glob(prefix + "*"))]}, indent=2) + "\n", encoding="utf-8")
    print("R12 installer and archives built. Product tests: NOT_RUN. " + str(output))


if __name__ == "__main__":
    main()
