"""Package a rebuilt Excel menu/wording XLAM after exact-file validation.

Uses a fresh repository-local artifacts directory. Does not install software,
change security settings, run Excel, or reuse the RC3/RC4 binary as a new build.
"""
import argparse
import hashlib
import importlib.util
import json
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
HTML_NAMES = {
    "QUICK_GUIDE.md": "QuickGuide.html",
    "WORDING_UPDATE.md": "Wording-Report.html",
    "WINDOWS_LAUNCHER_REPORT.md": "Launcher-Report.html",
}

spec = importlib.util.spec_from_file_location("excel_release_render", REPO / "scripts/package-excel-launcher-release.py")
rendering = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rendering)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_hash(data):
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO, text=True, encoding="utf-8").strip()


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xlam", type=Path, required=True)
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--installer-version", choices=(VERSION, "0.2.0-rc.6", "0.2.0-rc.7"), default=VERSION)
    args = parser.parse_args()
    version = args.installer_version
    rc = int(version.rsplit(".", 1)[1])
    sources = SOURCES + (("src/CSLCAppEvents.cls",) if rc >= 6 else ())
    checks = CHECKS + (("windowState", "upgrade") if rc >= 6 else ())
    if rc >= 7:
        sources += ("src/customUI14.xml",)
        checks += ("contextMenuContent", "nativeContextMenu")
    html_names = dict(HTML_NAMES)
    report = "Wording-Report.html"
    if rc >= 6:
        html_names["WINDOW_STATE_REPORT.md"] = "Window-State-Report.html"
        html_names["UPGRADE_REPORT.md"] = "Upgrade-Report.html"
        report = "Window-State-Report.html"
    if rc >= 7:
        html_names["CONTEXT_MENU_REPORT.md"] = "Context-Menu-Report.html"
        report = "Context-Menu-Report.html"
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
    native_checks = {"cancellation", "nativeContextMenu"}
    required = tuple(c for c in checks if c not in native_checks)
    if set(validation["checks"]) != set(checks) or any(not str(validation["checks"][c]).startswith("PASS") for c in required):
        raise SystemExit("Required validation is incomplete or failed.")
    # A locked desktop prevents native menu/Esc input. This explicit limitation is
    # allowed only for the unsigned evaluation prerelease and is shipped intact.
    for name in native_checks.intersection(checks):
        if not str(validation["checks"][name]).startswith(("PASS", "NOT_RUN: desktop locked")):
            raise SystemExit(name + " needs a result or the explicit locked-desktop limitation.")
    source_hashes = {name: text_hash((TOOL / name).read_bytes()) for name in sources}
    if validation["sourceTextSha256"] != source_hashes:
        raise SystemExit("Sources have changed since binary validation.")
    if rc >= 7:
        validate_ribbon_package(args.xlam)
    if "$InstallerVersion = '" + version + "'" not in (TOOL / "Setup.ps1").read_text(encoding="utf-8-sig"):
        raise SystemExit("Installer version mismatch.")
    release = output / "Release"
    release.mkdir(parents=True)
    shutil.copyfile(args.xlam, release / "ExcelSmartListCompare.xlam")
    for name in ("Setup.ps1", "Install.cmd", "Uninstall.cmd", "Test_Excel.cmd"):
        shutil.copyfile(TOOL / name, release / name)
    shutil.copyfile(TOOL / "docs/RELEASE_README.md", release / "README.md")
    for source, target in html_names.items():
        rendering.render(TOOL / "docs" / source, release / target, commit,
                         title=f"Excel Smart List Compare RC{rc}", html_names=html_names)
    # This input is a reviewed, public summary; raw installer diagnostics stay local.
    (release / "Validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (release / "EXCEL_TEST_RESULT.txt").write_text(validation["checks"]["normalizationAndIntegration"] + "\n", encoding="utf-8")
    (release / "SOURCE_COMMIT.txt").write_text(commit + "\n", encoding="ascii")
    (release / "BUILD_INFO.json").write_text(json.dumps({
        "product": "Excel Smart List Compare", "installerVersion": version,
        "sourceCommit": commit, "xlamSha256": digest, "xlamRebuilt": True,
        "installerSha256": sha256(TOOL / "Setup.ps1"),
        "sourceTextSha256": source_hashes, "verificationReport": report,
        "status": "unsigned evaluation prerelease",
    }, indent=2) + "\n", encoding="utf-8")
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
    hashes = {p.name: sha256(p) for p in sorted(release.iterdir()) if p.is_file()}
    (release / "SHA256SUMS.txt").write_text("".join(d + "  " + n + "\n" for n, d in hashes.items()), encoding="ascii")
    install_zip = output / ("ExcelSmartListCompare-" + version + "-win-x64.zip")
    with zipfile.ZipFile(install_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(release.iterdir()):
            archive.write(path, "Release/" + path.name)
    with zipfile.ZipFile(install_zip) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Install ZIP integrity failure.")
        for name, expected in hashes.items():
            if hashlib.sha256(archive.read("Release/" + name)).hexdigest() != expected:
                raise SystemExit("Packaged file hash mismatch: " + name)
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
    for path in (install_zip, source_zip):
        Path(str(path) + ".sha256").write_text(sha256(path) + "  " + path.name + "\n", encoding="ascii")
    print(json.dumps({"sourceCommit": commit, "xlamSha256": digest,
                      "installZip": str(install_zip), "sourceZip": str(source_zip),
                      "zipIntegrity": "PASS", "fileHashes": "PASS", "localLinks": "PASS"}, indent=2))


if __name__ == "__main__":
    main()
