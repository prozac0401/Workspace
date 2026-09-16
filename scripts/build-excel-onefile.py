"""Wrap a hash-pinned Excel payload in one Inno Setup executable.

Requires an existing Inno Setup 6.5+ compiler. Does not install or run Excel.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[1]
INSTALLER = REPO / "tools/ExcelSmartListCompare/installer/SingleFile.iss"
PAYLOAD = {
    "Install.cmd": ("InstallHash", "951b1f054f193c27b9e6acced6c3148c1026356514689b37a5428efad14b9275"),
    "Uninstall.cmd": ("UninstallHash", "4902e4f560879702d8ff788fb07ce4ad9f1b32033a741dd2ad31d3b36be9c4df"),
    "Setup.ps1": ("SetupHash", "1ae6bc71c3fa8b7bc8bc46401f76df6570e60664b5369e57919c77a845120801"),
    "README.md": ("ReadmeHash", "33f9ac114716d702a67713237db54ae84c9d3bc70ff1561709228d0aea634526"),
    "ExcelSmartListCompare.xlam": ("XlamHash", "5da5ff891232dde733d60ee6151cbfb26e251d6b75a51cb6a3f224effde4c18b"),
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-directory", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--engine-version", choices=("0.2.0-rc.7", "0.2.0-rc.8"), default="0.2.0-rc.8")
    parser.add_argument("--iscc", type=Path, default=Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"))
    args = parser.parse_args()
    version = args.engine_version
    payload_hashes = PAYLOAD
    if version == "0.2.0-rc.8":
        pins = json.loads((INSTALLER.parent / "RC8-Payload.json").read_text(encoding="utf-8"))
        if pins["engineVersion"] != version or set(pins["sha256"]) != set(PAYLOAD):
            raise SystemExit("Invalid pinned RC8 payload manifest.")
        payload_hashes = {name: (macro, pins["sha256"][name]) for name, (macro, _) in PAYLOAD.items()}
    output = args.output_directory.resolve()
    if not output.is_relative_to(REPO / "artifacts") or output == REPO / "artifacts" or output.exists():
        raise SystemExit("Choose a fresh output directory inside this repository's artifacts.")
    if not args.iscc.is_file():
        raise SystemExit("Inno Setup compiler not found. Pass --iscc with its installed location.")
    for name, (_, expected) in payload_hashes.items():
        path = args.release_directory / name
        if not path.is_file() or sha256(path) != expected:
            raise SystemExit("Pinned payload is missing or changed: " + name)
    payload = output / "payload"
    payload.mkdir(parents=True)
    definitions = []
    for name, (macro, expected) in payload_hashes.items():
        shutil.copyfile(args.release_directory / name, payload / name)
        definitions.append(f'#define {macro} "{expected}"\n')
    (payload / "PayloadHashes.iss").write_text("".join(definitions), encoding="ascii")
    (payload / "manager.id").write_text("SLC-68A45C44-2026-OneFile-1\n", encoding="ascii")
    command = [str(args.iscc), "/Qp", "/D" + "PayloadDir=" + str(payload),
               "/DEngineVersion=" + version, "/O" + str(output), str(INSTALLER)]
    result = subprocess.run(command, capture_output=True)
    (output / "compiler.private.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        print((result.stdout + result.stderr).decode("utf-8", errors="replace"))
        raise SystemExit(result.returncode)
    exe = output / ("ExcelSmartListCompare-" + version + "-Setup.exe")
    digest = sha256(exe)
    Path(str(exe) + ".sha256").write_text(digest + "  " + exe.name + "\n", encoding="ascii")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=REPO, text=True).strip())
    metadata = {
        "product": "Excel Smart List Compare", "engineVersion": version,
        "wrapperVersion": "2", "exe": exe.name, "exeSha256": digest,
        "payloadSourceCommit": "3fefb5863dbf15a7c2c7ce20bc0a9c36a059d2a8" if version.endswith(".7") else (None if dirty else commit),
        "wrapperSourceCommit": None if dirty else commit, "baseCommit": commit,
        "sourceTreeDirty": dirty, "wrapperSourceSha256": sha256(INSTALLER),
        "buildScriptSha256": sha256(Path(__file__)), "compilerSha256": sha256(args.iscc),
        "payloadHashes": {name: expected for name, (_, expected) in payload_hashes.items()},
        "payloadByteIdenticalToRC7": version.endswith(".7"), "xlamRebuilt": version.endswith(".8"),
        "status": "unsigned evaluation prerelease", "runtimeValidation": "not performed by this build script",
    }
    (output / "OneFile-Build.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"exe": str(exe), "bytes": exe.stat().st_size, "sha256": digest,
                      "payloadByteIdenticalToRC7": version.endswith(".7")}, indent=2))


if __name__ == "__main__":
    main()
