"""Package the RC4 launchers with the unchanged, previously tested RC3 XLAM.

Run after committing the release source. Output must be a fresh directory under
artifacts. This command never runs Excel, installs the add-in, or deletes files.
"""
import argparse
import base64
import hashlib
from html.parser import HTMLParser
import json
import mimetypes
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import quote, unquote, urlsplit
import zipfile

import markdown

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "tools/ExcelSmartListCompare"
VERSION = "0.2.0-rc.4"
BASELINE_XLAM_SHA256 = "c6f55886c368294c4e21396366d0cf3c368605e965f3ca2bd153f2e75bc8ae86"
CSS = '''body{margin:0;background:#edf2f6;color:#172c42;font:17px/1.75 "Malgun Gothic",sans-serif}
main{max-width:1040px;margin:36px auto;background:white;padding:40px 48px;border-radius:16px}
h1{font-size:32px;line-height:1.4}h2{font-size:23px;margin-top:38px;border-top:1px solid #dbe4ec;padding-top:24px}
a{color:#075b92}code{background:#edf4f8;padding:2px 5px;border-radius:4px;overflow-wrap:anywhere}
img{max-width:100%;height:auto;border:1px solid #d8e2eb;border-radius:8px}
table{width:100%;border-collapse:collapse;font-size:15px}td,th{border-bottom:1px solid #dbe4ec;text-align:left;padding:9px 11px;overflow-wrap:anywhere}th{background:#edf4f8}
li{margin-bottom:7px}pre{overflow:auto}blockquote{border-left:4px solid #087c96;margin-left:0;padding-left:18px}
@media(max-width:650px){main{padding:20px;margin:0;border-radius:0}body{font-size:16px}h1{font-size:26px}}
@media print{body{background:white;font-size:10pt}main{margin:0;padding:0}img{max-height:150mm;object-fit:contain}h2{break-after:avoid}tr,img{break-inside:avoid}}'''
HTML_NAMES = {
    "QUICK_GUIDE.md": "QuickGuide.html",
    "WINDOWS_E2E_REPORT.md": "Windows-E2E-Report.html",
    "WINDOWS_TRUST_LOCATION_REPORT.md": "Trust-Location-Report.html",
    "WINDOWS_ROBUSTNESS_REPORT.md": "Robustness-Report.html",
    "WINDOWS_LAUNCHER_REPORT.md": "Launcher-Report.html",
}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO, text=True, encoding="utf-8").strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render(source, output, commit, *, title="Excel Smart List Compare RC4", html_names=HTML_NAMES):
    content = markdown.markdown(source.read_text(encoding="utf-8-sig"), extensions=["tables", "fenced_code"])
    for relative in set(re.findall(r'<img[^>]+src="([^"]+)"', content)):
        path = (source.parent / relative).resolve()
        if not path.is_relative_to(TOOL / "docs/images"):
            raise ValueError("Unexpected image reference: " + relative)
        data = base64.b64encode(path.read_bytes()).decode("ascii")
        content = content.replace(relative, "data:" + (mimetypes.guess_type(path)[0] or "image/jpeg") + ";base64," + data)

    def link(match):
        href = match[1]
        if href in html_names:
            return 'href="' + html_names[href] + '"'
        parsed = urlsplit(href)
        if not parsed.scheme and parsed.path.endswith(".md"):
            target = (source.parent / unquote(parsed.path)).resolve()
            if not target.is_relative_to(REPO) or not target.is_file():
                raise ValueError("Missing source reference: " + href)
            href = "https://github.com/prozac0401/Workspace/blob/" + commit + "/" + quote(target.relative_to(REPO).as_posix())
            if parsed.fragment:
                href += "#" + parsed.fragment
            return 'href="' + href + '"'
        return match[0]

    content = re.sub(r'href="([^"]+)"', link, content)
    output.write_text('<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' + title + '</title><style>' + CSS + '</style></head><body><main>' + content + '</main></body></html>', encoding="utf-8")


class LocalLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in ("href", "src") and value:
                self.links.append(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-directory", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    baseline = args.baseline_directory.resolve()
    output = args.output_directory.resolve()
    if not output.is_relative_to(REPO / "artifacts") or output == REPO / "artifacts":
        raise SystemExit("Use a fresh output directory below this repository's artifacts.")
    if output.exists():
        raise SystemExit("Output already exists; choose a fresh directory.")
    if git("status", "--porcelain", "--untracked-files=normal"):
        raise SystemExit("Commit the release source before packaging.")
    commit = git("rev-parse", "HEAD")
    xlam = baseline / "ExcelSmartListCompare.xlam"
    if sha256(xlam) != BASELINE_XLAM_SHA256:
        raise SystemExit("XLAM does not match the tested RC3 baseline.")
    if "$InstallerVersion = '" + VERSION + "'" not in (TOOL / "Setup.ps1").read_text(encoding="utf-8-sig"):
        raise SystemExit("Installer version mismatch.")
    release = output / "Release"
    release.mkdir(parents=True)
    for name in ("ExcelSmartListCompare.xlam", "EXCEL_TEST_RESULT.txt", "Windows-E2E-Report.html",
                 "Trust-Location-Report.html", "Robustness-Report.html", "Validation.json"):
        shutil.copyfile(baseline / name, release / name)
    for name in ("Setup.ps1", "Install.cmd", "Uninstall.cmd", "Test_Excel.cmd"):
        shutil.copyfile(TOOL / name, release / name)
    shutil.copyfile(TOOL / "docs/RELEASE_README.md", release / "README.md")
    for source in ("QUICK_GUIDE.md", "WINDOWS_LAUNCHER_REPORT.md"):
        render(TOOL / "docs" / source, release / HTML_NAMES[source], commit)
    (release / "SOURCE_COMMIT.txt").write_text(commit + "\n", encoding="ascii")
    (release / "BUILD_INFO.json").write_text(json.dumps({
        "product": "Excel Smart List Compare", "installerVersion": VERSION,
        "sourceCommit": commit, "baselineTag": "excel-smart-list-compare-v0.2.0-rc.3",
        "xlamSha256": BASELINE_XLAM_SHA256, "xlamRebuilt": False,
        "verificationReport": "Launcher-Report.html", "excelRetestedForRC4": False,
        "status": "unsigned evaluation prerelease",
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for path in release.glob("*.html"):
        links = LocalLinks()
        links.feed(path.read_text(encoding="utf-8-sig"))
        for href in links.links:
            parsed = urlsplit(href)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            target = (path.parent / unquote(parsed.path)).resolve()
            if not target.is_relative_to(release) or not target.is_file():
                raise SystemExit("Invalid local HTML reference: " + path.name + " -> " + href)
    hashes = {path.name: sha256(path) for path in sorted(release.iterdir()) if path.is_file()}
    (release / "SHA256SUMS.txt").write_text("".join(digest + "  " + name + "\n" for name, digest in hashes.items()), encoding="ascii")
    install_zip = output / ("ExcelSmartListCompare-" + VERSION + "-win-x64.zip")
    with zipfile.ZipFile(install_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(release.iterdir()):
            archive.write(path, "Release/" + path.name)
    with zipfile.ZipFile(install_zip) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Install ZIP integrity failure.")
        for name, digest in hashes.items():
            if hashlib.sha256(archive.read("Release/" + name)).hexdigest() != digest:
                raise SystemExit("Packaged file hash mismatch: " + name)
    source_zip = output / ("ExcelSmartListCompare-" + VERSION + "-Source.zip")
    subprocess.run(["git", "archive", "--format=zip", "--prefix=Workspace-Excel-RC4/",
                    "--output=" + str(source_zip), commit], cwd=REPO, check=True)
    with zipfile.ZipFile(source_zip) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Source ZIP integrity failure.")
        for name in ("Install.cmd", "Uninstall.cmd", "Test_Excel.cmd", "Setup.ps1"):
            source = archive.read("Workspace-Excel-RC4/tools/ExcelSmartListCompare/" + name)
            # Git attributes may normalize CRLF; compare text, preserving meaning.
            if source.replace(b"\r\n", b"\n") != (release / name).read_bytes().replace(b"\r\n", b"\n"):
                raise SystemExit("Source/package disagreement: " + name)
    for path in (install_zip, source_zip):
        Path(str(path) + ".sha256").write_text(sha256(path) + "  " + path.name + "\n", encoding="ascii")
    print(json.dumps({"output": str(output), "sourceCommit": commit, "releaseFiles": len(hashes) + 1,
                      "installZipSha256": sha256(install_zip), "sourceZipSha256": sha256(source_zip),
                      "xlamSha256": sha256(release / "ExcelSmartListCompare.xlam"), "localLinks": "PASS"}, indent=2))


if __name__ == "__main__":
    main()
