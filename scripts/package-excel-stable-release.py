"""Package 0.2.1 with exact-file evidence using the existing Inno/ZIP helpers."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "tools/ExcelSmartListCompare"
VERSION = "0.2.1"
NAMES = ("Install.cmd", "Uninstall.cmd", "Setup.ps1", "README.md", "ExcelSmartListCompare.xlam")
MACROS = ("InstallHash", "UninstallHash", "SetupHash", "ReadmeHash", "XlamHash")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xlam", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--source-audit", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--iscc", type=Path, default=Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"))
    args = parser.parse_args()
    pack = load("stable_existing_packager", TOOL / "package_r13.py")
    renderer = load("stable_existing_renderer", REPO / "scripts/package-excel-launcher-release.py")
    exact = pack.digest(pack.read(args.xlam))
    build, audit, runtime = [pack.parse_json(pack.read(p)) for p in (args.build, args.source_audit, args.runtime)]
    if any(r.get("status") != "PASS" for r in (build, audit, runtime)):
        raise SystemExit("Exact build/source/runtime evidence must all pass.")
    for field in ("expectedSha256", "actualSha256", "finalSha256"):
        if build.get(field) != exact or runtime.get(field) != exact:
            raise SystemExit("Candidate fingerprint differs from build/runtime evidence.")
    if (build.get("releaseVersion") != VERSION or runtime.get("releaseVersion") != VERSION
            or audit.get("xlamSha256Before") != exact or audit.get("xlamSha256After") != exact
            or runtime.get("runtimeTests") != "PASS"):
        raise SystemExit("Exact-file version/source/runtime evidence mismatch.")
    for r in (build, runtime):
        if (r.get("cleanupErrors") != [] or any(r.get(k) is not True for k in
                ("excelExited", "existingExcelPreserved", "installedPreserved", "accessRestored"))):
            raise SystemExit("Owned-session cleanup and existing installation preservation must pass.")
    tests = runtime.get("tests", [])
    if ({r.get("name") for r in tests} !=
            {"SLC_UiProbe", "SLC_StatusPreservationTests", "SLC_UsabilityTests"}
            or len(tests) != 3 or any(r.get("status") != "PASS" for r in tests)):
        raise SystemExit("Required scoped runtime checks are missing.")
    if audit.get("errors") or audit.get("scriptSha256") != pack.digest(pack.read(TOOL / "tests/audit_candidate.py")):
        raise SystemExit("Serialized source auditor changed or failed.")
    for name, expected in audit["sourceHashes"].items():
        if pack.digest(pack.read(TOOL / "src" / name)) != expected:
            raise SystemExit("Source changed after exact-file audit: " + name)
    setup = pack.read(TOOL / "Setup.ps1").decode("utf-8-sig")
    for name in ("Version", "InstallerVersion"):
        if not re.search(r"(?m)^\$" + name + r" = '0\.2\.1'\s*$", setup):
            raise SystemExit("Setup version differs from the candidate.")
    if pack.git("status", "--porcelain", "--untracked-files=normal"):
        raise SystemExit("Commit the reviewed source before packaging.")
    output = args.output_directory.resolve()
    pack.no_redirects(output)
    if not output.is_relative_to((REPO / "artifacts").resolve()) or output.exists():
        raise SystemExit("Use a fresh directory below repository artifacts.")
    if not args.iscc.is_file():
        raise SystemExit("Use the existing Inno Setup compiler.")
    output.mkdir(parents=True)
    payload = output / "payload"
    payload.mkdir()
    for name in ("Install.cmd", "Uninstall.cmd", "Setup.ps1"):
        shutil.copyfile(TOOL / name, payload / name)
    shutil.copyfile(TOOL / "docs/STABLE_USER_GUIDE.md", payload / "README.md")
    shutil.copyfile(args.xlam, payload / "ExcelSmartListCompare.xlam")
    hashes = {name: pack.digest(pack.read(payload / name)) for name in NAMES}
    (payload / "PayloadHashes.iss").write_text(
        "".join('#define ' + macro + ' "' + hashes[name] + '"\n' for name, macro in zip(NAMES, MACROS)), encoding="ascii")
    (payload / "manager.id").write_text("SLC-68A45C44-2026-OneFile-1\n", encoding="ascii")
    pack.VERSION, pack.FILE_VERSION = VERSION, "0.2.1.1"
    pack.EXE_NAME = "ExcelSmartListCompare-" + VERSION + "-Setup.exe"
    exe = pack.compile_installer(args, output, payload)
    exe_hash = pack.digest(pack.read(exe))
    commit = pack.git("rev-parse", "HEAD").decode("ascii").strip()
    renderer.render(TOOL / "docs/STABLE_USER_GUIDE.md", output / "QuickGuide.html",
                    commit, title="Excel 명단 비교 0.2.1", html_names={})
    user_files = {"Release/" + name: pack.read(payload / name) for name in NAMES}
    user_files["Release/QuickGuide.html"] = pack.read(output / "QuickGuide.html")
    user_files["Release/SHA256SUMS.txt"] = "".join(
        pack.digest(data) + "  " + name.split("/", 1)[1] + "\n"
        for name, data in sorted(user_files.items())).encode("ascii")
    zip_path = output / ("ExcelSmartListCompare-" + VERSION + "-win-x64.zip")
    pack.write_zip(zip_path, user_files)
    manifest = {
        "product": "Excel Smart List Compare", "version": VERSION, "channel": "stable", "signed": False,
        "sourceCommit": commit, "xlamSha256": exact, "payloadSha256": hashes, "exeSha256": exe_hash,
        "zipSha256": pack.digest(pack.read(zip_path)),
        "installerSourceSha256": pack.digest(pack.read(TOOL / "installer/SingleFile.iss")),
        "packagerSha256": pack.digest(Path(__file__).read_bytes()),
        "compilerSha256": pack.digest(pack.read(args.iscc)), "fileVersion": "0.2.1.1",
        "evidenceSha256": {name: pack.digest(pack.read(path)) for name, path in
            (("build", args.build), ("sourceAudit", args.source_audit), ("runtime", args.runtime))},
        "runtimeTests": [{"name": r["name"], "status": r["status"], "result": r["result"]} for r in tests],
        "limits": ["Final EXE lifecycle not rerun; installer actions unchanged except version literals.",
                   "Physical Esc and cancellation popup not retested; previous native evidence retained.",
                   "Other Office/Windows versions and company approval remain outside this scoped check."]}
    (output / "Build-Manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    verification = output / ("ExcelSmartListCompare-" + VERSION + "-Verification.zip")
    pack.write_zip(verification, {
        "Build-Manifest.json": pack.read(output / "Build-Manifest.json"),
        "Release-Report.md": pack.read(TOOL / "docs/STABLE_RELEASE_REPORT.md")})
    for path in (exe, zip_path, verification):
        Path(str(path) + ".sha256").write_text(pack.digest(pack.read(path)) + "  " + path.name + "\n", encoding="ascii")
    print(json.dumps({"exe": str(exe), "sha256": exe_hash, "manifest": str(output / "Build-Manifest.json")}, indent=2))


if __name__ == "__main__":
    main()
