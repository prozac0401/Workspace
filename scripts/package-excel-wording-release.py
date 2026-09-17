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
import shutil
import subprocess
from urllib.parse import unquote, urlsplit
import zipfile
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "tools/ExcelSmartListCompare"
VERSION = "0.2.0-rc.5"
OLD_XLAM = "c6f55886c368294c4e21396366d0cf3c368605e965f3ca2bd153f2e75bc8ae86"
SOURCES = ("src/CSLCList.cls", "src/modSLCNormalize.bas", "src/modSLCMain.bas", "src/ThisWorkbook_events.txt")
CHECKS = ("sourceMatchesBinary", "normalizationAndIntegration", "wordingAndState", "selectionMatrix",
          "cancellation", "autoLoad", "reinstall", "uninstall", "python", "docs")
LIMITED_CORE_CHECKS = frozenset(("sourceMatchesBinary", "normalizationAndIntegration", "selectionMatrix",
                               "nativeContextMenu", "python", "docs"))
HTML_NAMES = {
    "QUICK_GUIDE.md": "QuickGuide.html",
    "WORDING_UPDATE.md": "Wording-Report.html",
    "WINDOWS_LAUNCHER_REPORT.md": "Launcher-Report.html",
}
PUBLIC_EVIDENCE_JSON = (
    "tools/ExcelSmartListCompare/evidence/rc8/validation.json",
    "tools/ExcelSmartListCompare/evidence/rc9/validation.json",
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
    for relative in PUBLIC_EVIDENCE_JSON:
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
    return html_names, report


def validate_acceptance_profile(validation, checks, rc, profile):
    """A separately authorized RC9 evaluation never relabels incomplete checks."""
    results = validation["checks"]
    if set(results) != set(checks):
        raise SystemExit("Required validation is incomplete or failed.")
    if profile == "limited-evaluation":
        if rc != 9:
            raise SystemExit("Limited evaluation is defined only for RC9.")
        decision = validation.get("limitedEvaluation", {})
        if (validation.get("releaseProfile") != profile
                or validation.get("releaseDecision") != "LIMITED_EVALUATION"
                or not isinstance(decision, dict)
                or decision.get("userAuthorized") is not True
                or decision.get("notForProduction") is not True):
            raise SystemExit("Limited evaluation requires explicit matching user-authorized decision metadata.")
        for name in LIMITED_CORE_CHECKS:
            result = results[name]
            if not isinstance(result, str) or not (result == "PASS" or result.startswith("PASS:")):
                raise SystemExit("Limited evaluation requires PASS for " + name + ".")
        incomplete = []
        for name in checks:
            result = results[name]
            if not isinstance(result, str):
                raise SystemExit("Limited evaluation requires explicit result strings.")
            status = result.split(":", 1)[0]
            if status not in {"PASS", "FAIL", "PARTIAL", "NOT_RUN", "NEEDS_MANUAL", "BLOCKED_ENV", "BLOCKED_ENVIRONMENT", "BLOCKED_POLICY"}:
                raise SystemExit("Unknown limited evaluation check status: " + name)
            if status != "PASS":
                incomplete.append(name)
        accepted = decision.get("acceptedIncompleteChecks")
        if (not isinstance(accepted, list) or any(not isinstance(name, str) for name in accepted)
                or len(accepted) != len(set(accepted)) or set(accepted) != set(incomplete)):
            raise SystemExit("Accepted incomplete checks must exactly match the unchanged non-PASS results.")
        return incomplete
    if (validation.get("releaseProfile") not in (None, "full")
            or validation.get("releaseDecision") == "LIMITED_EVALUATION"
            or "limitedEvaluation" in validation):
        raise SystemExit("Limited evaluation metadata requires the explicit limited-evaluation profile.")
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
    parser.add_argument("--installer-version", choices=(VERSION, "0.2.0-rc.6", "0.2.0-rc.7", "0.2.0-rc.8", "0.2.0-rc.9"), default=VERSION)
    parser.add_argument("--release-profile", choices=("full", "limited-evaluation"), default="full",
                        help="Full acceptance by default; RC9 limited evaluation requires explicit reviewed authorization metadata.")
    args = parser.parse_args()
    version = args.installer_version
    rc = int(version.rsplit(".", 1)[1])
    sources = SOURCES + (("src/CSLCAppEvents.cls",) if rc >= 6 else ())
    checks = CHECKS + (("windowState", "upgrade") if rc >= 6 else ())
    if rc >= 7:
        sources += ("src/customUI14.xml",)
        checks += ("contextMenuContent", "nativeContextMenu")
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
    incomplete = validate_acceptance_profile(validation, checks, rc, args.release_profile)
    limited = args.release_profile == "limited-evaluation"
    source_hashes = {name: text_hash((TOOL / name).read_bytes()) for name in sources}
    if validation["sourceTextSha256"] != source_hashes:
        raise SystemExit("Sources have changed since binary validation.")
    if rc >= 7:
        validate_ribbon_package(args.xlam)
    if "$InstallerVersion = '" + version + "'" not in (TOOL / "Setup.ps1").read_text(encoding="utf-8-sig"):
        raise SystemExit("Installer version mismatch.")
    if limited and "LIMITED EVALUATION" not in (TOOL / "docs/RELEASE_README.md").read_text(encoding="utf-8-sig")[:2048]:
        raise SystemExit("Limited evaluation requires a visible LIMITED EVALUATION marker in the source README.")
    release = output / "Release"
    release.mkdir(parents=True)
    shutil.copyfile(args.xlam, release / "ExcelSmartListCompare.xlam")
    for name in ("Setup.ps1", "Install.cmd", "Uninstall.cmd", "Test_Excel.cmd"):
        shutil.copyfile(TOOL / name, release / name)
    shutil.copyfile(TOOL / "docs/RELEASE_README.md", release / "README.md")
    if limited:
        # Keep README bytes identical to the pinned source and optional EXE
        # payload; add a separate notice without rewriting any input file.
        notice = ("LIMITED EVALUATION - NOT FOR PRODUCTION\n"
                  "Full acceptance is incomplete. Raw results remain in Validation.json.\n\n")
        notice += "\n".join(name + ": " + validation["checks"][name] for name in incomplete) + "\n"
        (release / "RELEASE_STATUS.txt").write_text(notice, encoding="utf-8")
    for source, target in html_names.items():
        report_source = TOOL / "docs" / source
        rendering.render(report_source, release / target, commit,
                         title=f"Excel Smart List Compare RC{rc}",
                         html_names=public_report_link_map(report_source, commit, html_names))
    # This input is a reviewed, public summary; raw installer diagnostics stay local.
    (release / "Validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result_prefix = "LIMITED EVALUATION: full acceptance is incomplete; see Validation.json.\n" if limited else ""
    (release / "EXCEL_TEST_RESULT.txt").write_text(result_prefix + validation["checks"]["normalizationAndIntegration"] + "\n", encoding="utf-8")
    (release / "SOURCE_COMMIT.txt").write_text(commit + "\n", encoding="ascii")
    (release / "BUILD_INFO.json").write_text(json.dumps({
        "product": "Excel Smart List Compare", "installerVersion": version,
        "sourceCommit": commit, "xlamSha256": digest, "xlamRebuilt": True,
        "installerSha256": sha256(TOOL / "Setup.ps1"),
        "sourceTextSha256": source_hashes, "verificationReport": report,
        "status": "unsigned limited evaluation prerelease" if limited else "unsigned evaluation prerelease",
        "releaseProfile": args.release_profile,
        "releaseDecision": validation.get("releaseDecision"), "validationStatus": validation.get("status"),
        "fullAcceptancePassed": not limited and all(str(validation["checks"][name]).startswith("PASS") for name in checks),
        "notForProduction": True, "acceptedIncompleteChecks": incomplete,
    }, indent=2) + "\n", encoding="utf-8")
    validate_release_local_links(release)
    hashes = {p.name: sha256(p) for p in sorted(release.iterdir()) if p.is_file()}
    (release / "SHA256SUMS.txt").write_text("".join(d + "  " + n + "\n" for n, d in hashes.items()), encoding="ascii")
    profile_suffix = "-limited-evaluation" if limited else ""
    install_zip = output / ("ExcelSmartListCompare-" + version + profile_suffix + "-win-x64.zip")
    with zipfile.ZipFile(install_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(release.iterdir()):
            archive.write(path, "Release/" + path.name)
    with zipfile.ZipFile(install_zip) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Install ZIP integrity failure.")
        for name, expected in hashes.items():
            if hashlib.sha256(archive.read("Release/" + name)).hexdigest() != expected:
                raise SystemExit("Packaged file hash mismatch: " + name)
    source_zip = output / ("ExcelSmartListCompare-" + version + profile_suffix + "-Source.zip")
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
    for path in (install_zip, source_zip):
        Path(str(path) + ".sha256").write_text(sha256(path) + "  " + path.name + "\n", encoding="ascii")
    print(json.dumps({"sourceCommit": commit, "xlamSha256": digest,
                      "releaseProfile": args.release_profile, "acceptedIncompleteChecks": incomplete,
                      "installZip": str(install_zip), "sourceZip": str(source_zip),
                      "zipIntegrity": "PASS", "fileHashes": "PASS", "localLinks": "PASS"}, indent=2))


if __name__ == "__main__":
    main()
