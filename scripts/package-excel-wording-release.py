"""Package a rebuilt Excel menu/wording XLAM after exact-file validation.

Uses a fresh repository-local artifacts directory. Does not install software,
change security settings, run Excel, or reuse the RC3/RC4 binary as a new build.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import quote, unquote, urlsplit
import zipfile
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "tools/ExcelSmartListCompare"
VERSION = "0.2.0-rc.5"
OLD_XLAM = "c6f55886c368294c4e21396366d0cf3c368605e965f3ca2bd153f2e75bc8ae86"
SOURCES = ("src/CSLCList.cls", "src/modSLCNormalize.bas", "src/modSLCMain.bas", "src/ThisWorkbook_events.txt")
CHECKS = ("sourceMatchesBinary", "normalizationAndIntegration", "wordingAndState", "selectionMatrix",
          "cancellation", "autoLoad", "reinstall", "uninstall", "python", "docs")
EXCEPTION_CORE_CHECKS = frozenset(("sourceMatchesBinary", "normalizationAndIntegration", "selectionMatrix",
                               "nativeContextMenu", "python", "docs"))
R11_EXTRA_CHECKS = ("settingsAndState", "outputRollback")
RC10_EXCEPTION_CORE_CHECKS = frozenset(("sourceMatchesBinary", "normalizationAndIntegration", "python", "docs"))
R11_EXCEPTION_CORE_CHECKS = RC10_EXCEPTION_CORE_CHECKS | frozenset(R11_EXTRA_CHECKS)
USER_PACKAGE_FILES = frozenset(("ExcelSmartListCompare.xlam", "Setup.ps1", "Install.cmd",
                                "Uninstall.cmd", "README.md", "QuickGuide.html", "SHA256SUMS.txt"))
HTML_NAMES = {
    "QUICK_GUIDE.md": "QuickGuide.html",
    "WORDING_UPDATE.md": "Wording-Report.html",
    "WINDOWS_LAUNCHER_REPORT.md": "Launcher-Report.html",
}
PUBLIC_EVIDENCE_JSON = (
    "tools/ExcelSmartListCompare/evidence/rc8/validation.json",
    "tools/ExcelSmartListCompare/evidence/rc9/validation.json",
)
RC10_PUBLIC_REFERENCES = (
    "tools/ExcelSmartListCompare/evidence/rc10/validation.json",
    "tools/ExcelSmartListCompare/evidence/rc10/e2e-summary.json",
    "tools/ExcelSmartListCompare/tests/Invoke-IsolatedExcelCandidate.ps1",
    "scripts/package-excel-local-candidate.py",
)

spec = importlib.util.spec_from_file_location("excel_release_render", REPO / "scripts/package-excel-launcher-release.py")
rendering = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rendering)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_hash(data):
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO, text=True, encoding="utf-8").strip()


def public_report_link_map(source, commit, html_names):
    """Link only reviewed public summaries, pinned to the packaged source commit.

    The report list remains separate: JSON evidence is not rendered as Markdown
    or copied from local artifacts. Other relative JSON links still fail the
    existing package-local link validation.
    """
    links = dict(html_names)
    references = PUBLIC_EVIDENCE_JSON
    if "RC10_USER_GUIDE.md" in html_names:
        references += RC10_PUBLIC_REFERENCES
    for relative in references:
        try:
            git("cat-file", "-e", commit + ":" + relative)
        except subprocess.CalledProcessError as error:
            raise SystemExit("Public evidence is absent from the release commit: " + relative) from error
        href = Path(os.path.relpath(REPO / relative, source.parent)).as_posix()
        links[href] = "https://github.com/prozac0401/Workspace/blob/" + commit + "/" + relative
    return links


def validate_release_local_links(release):
    for path in release.glob("*.html"):
        links = rendering.LocalLinks()
        links.feed(path.read_text(encoding="utf-8"))
        for href in links.links:
            parsed = urlsplit(href)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            target = (path.parent / unquote(parsed.path)).resolve()
            if not target.is_relative_to(release) or not target.is_file():
                raise SystemExit("Broken local HTML reference: " + path.name + " -> " + href)


def package_directory(directory, archive_path):
    """Validate one self-contained document set and verify every archived byte."""
    validate_release_local_links(directory)
    paths = sorted(directory.iterdir())
    if any(not path.is_file() for path in paths):
        raise SystemExit("Unexpected package subdirectory: " + str(directory))
    hashes = {path.name: sha256(path) for path in paths}
    sums = directory / "SHA256SUMS.txt"
    sums.write_text("".join(digest + "  " + name + "\n" for name, digest in hashes.items()), encoding="ascii")
    hashes[sums.name] = sha256(sums)
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(hashes):
            archive.write(directory / name, directory.name + "/" + name)
    with zipfile.ZipFile(archive_path) as archive:
        expected_names = {directory.name + "/" + name for name in hashes}
        if set(archive.namelist()) != expected_names or len(archive.namelist()) != len(expected_names):
            raise SystemExit("Unexpected ZIP entries: " + archive_path.name)
        if archive.testzip() is not None:
            raise SystemExit("ZIP integrity failure: " + archive_path.name)
        for name, expected in hashes.items():
            if hashlib.sha256(archive.read(directory.name + "/" + name)).hexdigest() != expected:
                raise SystemExit("Packaged file hash mismatch: " + name)


def validate_ribbon_package(path):
    """Check the actual Office package wiring, separately from VBA source audit."""
    ui_ns = "http://schemas.microsoft.com/office/2009/07/customui"
    rel_ns = "http://schemas.openxmlformats.org/package/2006/relationships"
    rel_type = "http://schemas.microsoft.com/office/2007/relationships/ui/extensibility"
    type_ns = "http://schemas.openxmlformats.org/package/2006/content-types"
    expected = {
        "ContextMenuCell": "Cell", "ContextMenuRow": "Row", "ContextMenuColumn": "Column",
        "ContextMenuListRange": "Table", "ContextMenuCellLayout": "CellLayout",
        "ContextMenuRowLayout": "RowLayout", "ContextMenuColumnLayout": "ColumnLayout",
        "ContextMenuListRangeLayout": "TableLayout",
    }
    with zipfile.ZipFile(path) as archive:
        if len(archive.namelist()) != len(set(archive.namelist())):
            raise SystemExit("Duplicate XLAM package entries.")
        data = archive.read("customUI/customUI14.xml")
        if text_hash(data) != text_hash((TOOL / "src/customUI14.xml").read_bytes()):
            raise SystemExit("Packaged RibbonX does not match source.")
        root = ET.fromstring(data)
        menus = root.findall(f"{{{ui_ns}}}contextMenus/{{{ui_ns}}}contextMenu")
        if root.tag != f"{{{ui_ns}}}customUI" or root.get("onLoad") != "SLC_RibbonLoad" or len(menus) != len(expected):
            raise SystemExit("Incomplete RibbonX registration.")
        actual = {}
        ids = set()
        for menu in menus:
            children = list(menu)
            if len(children) != 1 or children[0].tag != f"{{{ui_ns}}}dynamicMenu":
                raise SystemExit("Context menu must contain one dynamic menu.")
            dynamic = children[0]
            actual[menu.get("idMso")] = dynamic.get("tag")
            ids.add(dynamic.get("id"))
            if dynamic.get("invalidateContentOnDrop") != "true" or dynamic.get("getContent") != "SLC_GetContextMenu":
                raise SystemExit("Context menu content must refresh on every drop.")
        if actual != expected or len(ids) != len(expected) or None in ids:
            raise SystemExit("Unexpected or duplicate context menu identifiers.")
        relationships = ET.fromstring(archive.read("_rels/.rels"))
        ui = [r for r in relationships.findall(f"{{{rel_ns}}}Relationship") if r.get("Type") == rel_type]
        if len(ui) != 1 or ui[0].get("Target") != "customUI/customUI14.xml":
            raise SystemExit("Missing or duplicate Office RibbonX relationship.")
        types = ET.fromstring(archive.read("[Content_Types].xml"))
        ui_types = [t for t in types.findall(f"{{{type_ns}}}Override") if t.get("PartName") == "/customUI/customUI14.xml"]
        if len(ui_types) != 1 or ui_types[0].get("ContentType") != "application/xml":
            raise SystemExit("Missing or duplicate RibbonX content type.")


def release_report_layout(rc):
    """Keep current completion evidence and earlier reports in separate files."""
    if rc >= 11:
        return {"RC11_USER_GUIDE.md": "QuickGuide.html", "RC11_TEST_REPORT.md": "Completion-Report.html",
                "RC11_USER_VALIDATION.md": "User-Validation.html", "ADR-0019-R11-release-scope.md": "Publication-Decision.html"}, "Completion-Report.html"
    html_names = dict(HTML_NAMES)
    report = "Wording-Report.html"
    if rc >= 6:
        html_names["WINDOW_STATE_REPORT.md"] = "Window-State-Report.html"
        html_names["UPGRADE_REPORT.md"] = "Upgrade-Report.html"
        report = "Window-State-Report.html"
    if rc >= 7:
        html_names["CONTEXT_MENU_REPORT.md"] = "Context-Menu-Report.html"
        report = "Context-Menu-Report.html"
    if rc >= 8:
        html_names["RC8_COMPLETION_REPORT.md"] = "Completion-Report.html"
        html_names["UNLOCKED_UI_REPORT.md"] = "RC7-Native-Report.html"
        report = "Completion-Report.html"
    if rc >= 9:
        html_names["RC8_COMPLETION_REPORT.md"] = "RC8-Previous-Report.html"
        html_names["RC9_STABILITY_REPORT.md"] = "RC9-Initial-Report.html"
        html_names["RC9_APPROVED_RETEST_20260917.md"] = "Completion-Report.html"
    if rc >= 10:
        html_names["QUICK_GUIDE.md"] = "RC9-QuickGuide.html"
        html_names["RELEASE_README.md"] = "RC9-Installation-Guide.html"
        html_names["USABILITY_CANDIDATE_GUIDE.md"] = "RC10-Development-Guide.html"
        html_names["RC10_USER_GUIDE.md"] = "QuickGuide.html"
        html_names["RC9_APPROVED_RETEST_20260917.md"] = "RC9-Previous-Report.html"
        html_names["USABILITY_RC10_REPORT.md"] = "Completion-Report.html"
        html_names["RC10_END_TO_END_REPORT.md"] = "End-to-End-Report.html"
        html_names["ADR-0017-RC10-publication.md"] = "Publication-Decision.html"
    return html_names, report


def release_user_guide(rc):
    if rc >= 11:
        return "RC11_USER_GUIDE.md"
    return "RC10_USER_GUIDE.md" if rc >= 10 else "RELEASE_README.md"


def candidate_readme_text(source, commit):
    """Keep repository-only Markdown references usable in the seven-file ZIP."""
    content = source.read_text(encoding="utf-8-sig")

    def link(match):
        href = match[1]
        parsed = urlsplit(href)
        if parsed.scheme or parsed.netloc or not parsed.path.endswith(".md"):
            return match[0]
        target = (source.parent / unquote(parsed.path)).resolve()
        if not target.is_relative_to(REPO) or not target.is_file():
            raise SystemExit("Missing candidate guide reference: " + href)
        pinned = ("https://github.com/prozac0401/Workspace/blob/" + commit + "/"
                  + quote(target.relative_to(REPO).as_posix()))
        if parsed.fragment:
            pinned += "#" + parsed.fragment
        return "](" + pinned + ")"

    return re.sub(r"\]\(([^)]+)\)", link, content)


def validate_acceptance_profile(validation, checks, rc, profile):
    """Explicit RC9/RC10/R11 publication decisions preserve incomplete results."""
    results = validation["checks"]
    if set(results) != set(checks):
        raise SystemExit("Required validation is incomplete or failed.")
    if profile == "documented-exceptions":
        if rc not in (9, 10, 11):
            raise SystemExit("Documented exceptions are defined only for RC9, RC10 and R11.")
        decision = validation.get("releaseExceptions", {})
        if (validation.get("releaseProfile") != profile
                or validation.get("releaseDecision") != "PUBLISH_WITH_RECORDED_RESULTS"
                or not isinstance(decision, dict)
                or decision.get("userAuthorized") is not True
                or decision.get("fullAcceptancePassed") is not False):
            raise SystemExit("Documented exceptions require explicit matching user-authorized decision metadata.")
        if rc == 10 and (validation.get("installerVersion") != "0.2.0-rc.10"
                or decision.get("decisionRecord") != "tools/ExcelSmartListCompare/docs/ADR-0017-RC10-publication.md"
                or validation.get("fullAcceptancePassed") is not False):
            raise SystemExit("RC10 exceptions require their own publication decision and incomplete acceptance.")
        if rc == 11 and (validation.get("installerVersion") != "0.2.0-rc.11"
                or decision.get("decisionRecord") != "tools/ExcelSmartListCompare/docs/ADR-0019-R11-release-scope.md"
                or validation.get("fullAcceptancePassed") is not False):
            raise SystemExit("R11 exceptions require their own publication decision and incomplete acceptance.")
        core_checks = R11_EXCEPTION_CORE_CHECKS if rc == 11 else RC10_EXCEPTION_CORE_CHECKS if rc == 10 else EXCEPTION_CORE_CHECKS
        for name in core_checks:
            result = results[name]
            if not isinstance(result, str) or not (result == "PASS" or result.startswith("PASS:")):
                raise SystemExit("Documented exceptions require PASS for " + name + ".")
        incomplete = []
        for name in checks:
            result = results[name]
            if not isinstance(result, str):
                raise SystemExit("Documented exceptions require explicit result strings.")
            status = result.split(":", 1)[0]
            if status not in {"PASS", "FAIL", "PARTIAL", "NOT_RUN", "NEEDS_MANUAL", "BLOCKED_ENV", "BLOCKED_ENVIRONMENT", "BLOCKED_POLICY"}:
                raise SystemExit("Unknown documented-exceptions check status: " + name)
            if status != "PASS":
                incomplete.append(name)
        accepted = decision.get("acceptedIncompleteChecks")
        if (not isinstance(accepted, list) or any(not isinstance(name, str) for name in accepted)
                or len(accepted) != len(set(accepted)) or set(accepted) != set(incomplete)):
            raise SystemExit("Accepted incomplete checks must exactly match the unchanged non-PASS results.")
        return incomplete
    if (validation.get("releaseProfile") not in (None, "full")
            or validation.get("releaseDecision") == "PUBLISH_WITH_RECORDED_RESULTS"
            or "releaseExceptions" in validation):
        raise SystemExit("Recorded exception metadata requires the explicit documented-exceptions profile.")
    native_checks = {"cancellation", "nativeContextMenu"}
    required = tuple(c for c in checks if c not in native_checks)
    if any(not str(results[c]).startswith("PASS") for c in required):
        raise SystemExit("Required validation is incomplete or failed.")
    # Preserve the original full-profile rules, including the historical <=RC7
    # locked-desktop exception. RC8/RC9 continue to require native PASS results.
    for name in native_checks.intersection(checks):
        accepted = ("PASS",) if rc >= 8 else ("PASS", "NOT_RUN: desktop locked")
        if not str(results[name]).startswith(accepted):
            raise SystemExit(name + " needs a result or the explicit locked-desktop limitation.")
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xlam", type=Path, required=True)
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--installer-version", choices=(VERSION, "0.2.0-rc.6", "0.2.0-rc.7", "0.2.0-rc.8", "0.2.0-rc.9", "0.2.0-rc.10", "0.2.0-rc.11"), default=VERSION)
    parser.add_argument("--release-profile", choices=("full", "documented-exceptions"), default="full",
                        help="Full acceptance by default; RC9/RC10/R11 exceptions require their own explicit authorization metadata.")
    args = parser.parse_args()
    version = args.installer_version
    rc = int(version.rsplit(".", 1)[1])
    sources = SOURCES + (("src/CSLCAppEvents.cls",) if rc >= 6 else ())
    checks = CHECKS + (("windowState", "upgrade") if rc >= 6 else ())
    if rc >= 7:
        sources += ("src/customUI14.xml",)
        checks += ("contextMenuContent", "nativeContextMenu")
    if rc >= 10:
        sources += ("src/modSLCReport.bas",)
    html_names, report = release_report_layout(rc)
    output = args.output_directory.resolve()
    if not output.is_relative_to(REPO / "artifacts") or output == REPO / "artifacts" or output.exists():
        raise SystemExit("Choose a fresh directory under this repository's artifacts.")
    if git("status", "--porcelain", "--untracked-files=normal"):
        raise SystemExit("Commit the release source before packaging.")
    commit = git("rev-parse", "HEAD")
    digest = sha256(args.xlam)
    retired = {OLD_XLAM}
    if rc >= 6:
        retired.add("e6eff07df465933f7159ab073b3cb656c23691d74f522733ca450f19a3f077de")
    if rc >= 7:
        retired.add("81d8b3e58aee1c352fbf19a1447581297a2e64d11edce9102523ebbbf7e07322")
    if digest in retired:
        raise SystemExit("This release requires a newly built XLAM.")
    validation = json.loads(args.validation.read_text(encoding="utf-8-sig"))
    if validation["installerVersion"] != version or validation["xlamSha256"] != digest:
        raise SystemExit("Validation does not describe this version and exact XLAM.")
    if rc >= 6 and validation.get("installerSha256") != sha256(TOOL / "Setup.ps1"):
        raise SystemExit("Installer changed after upgrade validation.")
    if rc >= 11:
        checks += R11_EXTRA_CHECKS
    incomplete = validate_acceptance_profile(validation, checks, rc, args.release_profile)
    documented_exceptions = args.release_profile == "documented-exceptions"
    source_hashes = {name: text_hash((TOOL / name).read_bytes()) for name in sources}
    if validation["sourceTextSha256"] != source_hashes:
        raise SystemExit("Sources have changed since binary validation.")
    if rc >= 7:
        validate_ribbon_package(args.xlam)
    if "$InstallerVersion = '" + version + "'" not in (TOOL / "Setup.ps1").read_text(encoding="utf-8-sig"):
        raise SystemExit("Installer version mismatch.")
    release = output / "Release"
    verification = output / "Verification"
    release.mkdir(parents=True)
    verification.mkdir()
    shutil.copyfile(args.xlam, release / "ExcelSmartListCompare.xlam")
    for name in ("Setup.ps1", "Install.cmd", "Uninstall.cmd"):
        shutil.copyfile(TOOL / name, release / name)
    guide_name = release_user_guide(rc)
    guide_source = TOOL / "docs" / guide_name
    if rc >= 10:
        (release / "README.md").write_text(candidate_readme_text(guide_source, commit), encoding="utf-8")
    else:
        shutil.copyfile(guide_source, release / "README.md")
    rendering.render(guide_source, release / "QuickGuide.html", commit,
                     title="Excel 명단 비교 · 설치와 사용",
                     html_names={guide_name: "QuickGuide.html"})
    shutil.copyfile(release / "QuickGuide.html", verification / "QuickGuide.html")
    if documented_exceptions:
        notice = ("Validation results\n"
                  "Full acceptance is incomplete. Raw results remain in Validation.json.\n\n")
        notice += "\n".join(name + ": " + validation["checks"][name] for name in incomplete) + "\n"
        (verification / "RELEASE_STATUS.txt").write_text(notice, encoding="utf-8")
    for source, target in html_names.items():
        if target == "QuickGuide.html":
            continue
        report_source = TOOL / "docs" / source
        rendering.render(report_source, verification / target, commit,
                         title=f"Excel Smart List Compare RC{rc}",
                         html_names=public_report_link_map(report_source, commit, html_names))
    # This input is a reviewed, public summary; raw installer diagnostics stay local.
    (verification / "Validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if rc == 10:
        shutil.copyfile(TOOL / "evidence/rc10/e2e-summary.json", verification / "End-to-End-Summary.json")
    (verification / "EXCEL_TEST_RESULT.txt").write_text(validation["checks"]["normalizationAndIntegration"] + "\n", encoding="utf-8")
    (verification / "SOURCE_COMMIT.txt").write_text(commit + "\n", encoding="ascii")
    (verification / "BUILD_INFO.json").write_text(json.dumps({
        "product": "Excel Smart List Compare", "installerVersion": version,
        "packageRevision": validation.get("packageRevision", 1),
        "sourceCommit": commit, "xlamSha256": digest,
        "xlamRebuiltThisRun": rc >= 11, "xlamReused": rc < 11,
        "installerSha256": sha256(TOOL / "Setup.ps1"),
        "sourceTextSha256": source_hashes, "verificationReport": report,
        "userPackageFileSha256": {path.name: sha256(path) for path in sorted(release.iterdir())},
        "status": "unsigned package" if rc >= 11 else "unsigned prerelease",
        "releaseProfile": args.release_profile,
        "releaseDecision": validation.get("releaseDecision"), "validationStatus": validation.get("status"),
        "fullAcceptancePassed": not documented_exceptions and all(str(validation["checks"][name]).startswith("PASS") for name in checks),
        "acceptedIncompleteChecks": incomplete,
    }, indent=2) + "\n", encoding="utf-8")
    if {path.name for path in release.iterdir()} != USER_PACKAGE_FILES - {"SHA256SUMS.txt"}:
        raise SystemExit("Unexpected user package contents.")
    install_zip = output / ("ExcelSmartListCompare-" + version + "-win-x64.zip")
    verification_zip = output / ("ExcelSmartListCompare-" + version + "-Verification.zip")
    package_directory(release, install_zip)
    package_directory(verification, verification_zip)
    source_zip = output / ("ExcelSmartListCompare-" + version + "-Source.zip")
    prefix = f"Workspace-Excel-RC{rc}/"
    subprocess.run(["git", "archive", "--format=zip", "--prefix=" + prefix,
                    "--output=" + str(source_zip), commit], cwd=REPO, check=True)
    with zipfile.ZipFile(source_zip) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Source ZIP integrity failure.")
        for name in sources + ("Install.cmd", "Uninstall.cmd", "Test_Excel.cmd", "Setup.ps1"):
            data = archive.read(prefix + "tools/ExcelSmartListCompare/" + name)
            if text_hash(data) != text_hash((TOOL / name).read_bytes()):
                raise SystemExit("Source ZIP disagreement: " + name)
    for path in (install_zip, source_zip, verification_zip):
        Path(str(path) + ".sha256").write_text(sha256(path) + "  " + path.name + "\n", encoding="ascii")
    print(json.dumps({"sourceCommit": commit, "xlamSha256": digest,
                      "releaseProfile": args.release_profile, "acceptedIncompleteChecks": incomplete,
                      "installZip": str(install_zip), "sourceZip": str(source_zip),
                      "verificationZip": str(verification_zip),
                      "zipIntegrity": "PASS", "fileHashes": "PASS", "localLinks": "PASS"}, indent=2))


if __name__ == "__main__":
    main()
