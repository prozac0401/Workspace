"""Package the rebuilt RC5 XLAM only after validation of that exact file.

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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xlam", type=Path, required=True)
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_directory.resolve()
    if not output.is_relative_to(REPO / "artifacts") or output == REPO / "artifacts" or output.exists():
        raise SystemExit("Choose a fresh directory under this repository's artifacts.")
    if git("status", "--porcelain", "--untracked-files=normal"):
        raise SystemExit("Commit the release source before packaging.")
    commit = git("rev-parse", "HEAD")
    digest = sha256(args.xlam)
    if digest == OLD_XLAM:
        raise SystemExit("RC5 requires a newly built XLAM, not the RC3/RC4 file.")
    validation = json.loads(args.validation.read_text(encoding="utf-8-sig"))
    if validation["installerVersion"] != VERSION or validation["xlamSha256"] != digest:
        raise SystemExit("Validation does not describe this version and exact XLAM.")
    required = tuple(c for c in CHECKS if c != "cancellation")
    if set(validation["checks"]) != set(CHECKS) or any(not str(validation["checks"][c]).startswith("PASS") for c in required):
        raise SystemExit("Required validation is incomplete or failed.")
    # A locked desktop prevents native Esc input. This explicit limitation is
    # allowed only for the unsigned evaluation prerelease and is shipped intact.
    if not str(validation["checks"]["cancellation"]).startswith(("PASS", "NOT_RUN: desktop locked")):
        raise SystemExit("Cancellation needs a result or the explicit locked-desktop limitation.")
    source_hashes = {name: text_hash((TOOL / name).read_bytes()) for name in SOURCES}
    if validation["sourceTextSha256"] != source_hashes:
        raise SystemExit("Sources have changed since binary validation.")
    if "$InstallerVersion = '" + VERSION + "'" not in (TOOL / "Setup.ps1").read_text(encoding="utf-8-sig"):
        raise SystemExit("Installer version mismatch.")
    release = output / "Release"
    release.mkdir(parents=True)
    shutil.copyfile(args.xlam, release / "ExcelSmartListCompare.xlam")
    for name in ("Setup.ps1", "Install.cmd", "Uninstall.cmd", "Test_Excel.cmd"):
        shutil.copyfile(TOOL / name, release / name)
    shutil.copyfile(TOOL / "docs/RELEASE_README.md", release / "README.md")
    for source, target in HTML_NAMES.items():
        rendering.render(TOOL / "docs" / source, release / target, commit,
                         title="Excel Smart List Compare RC5", html_names=HTML_NAMES)
    # This input is a reviewed, public summary; raw installer diagnostics stay local.
    (release / "Validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (release / "EXCEL_TEST_RESULT.txt").write_text(validation["checks"]["normalizationAndIntegration"] + "\n", encoding="utf-8")
    (release / "SOURCE_COMMIT.txt").write_text(commit + "\n", encoding="ascii")
    (release / "BUILD_INFO.json").write_text(json.dumps({
        "product": "Excel Smart List Compare", "installerVersion": VERSION,
        "sourceCommit": commit, "xlamSha256": digest, "xlamRebuilt": True,
        "sourceTextSha256": source_hashes, "verificationReport": "Wording-Report.html",
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
    install_zip = output / ("ExcelSmartListCompare-" + VERSION + "-win-x64.zip")
    with zipfile.ZipFile(install_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(release.iterdir()):
            archive.write(path, "Release/" + path.name)
    with zipfile.ZipFile(install_zip) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Install ZIP integrity failure.")
        for name, expected in hashes.items():
            if hashlib.sha256(archive.read("Release/" + name)).hexdigest() != expected:
                raise SystemExit("Packaged file hash mismatch: " + name)
    source_zip = output / ("ExcelSmartListCompare-" + VERSION + "-Source.zip")
    prefix = "Workspace-Excel-RC5/"
    subprocess.run(["git", "archive", "--format=zip", "--prefix=" + prefix,
                    "--output=" + str(source_zip), commit], cwd=REPO, check=True)
    with zipfile.ZipFile(source_zip) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Source ZIP integrity failure.")
        for name in SOURCES + ("Install.cmd", "Uninstall.cmd", "Test_Excel.cmd", "Setup.ps1"):
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
