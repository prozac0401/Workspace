"""Wrap a hash-pinned Excel payload in one Inno Setup executable.

Requires an existing Inno Setup 6.5+ compiler. Does not install or run Excel.
"""
import argparse
import importlib.util
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[1]
INSTALLER = REPO / "tools/ExcelSmartListCompare/installer/SingleFile.iss"
RC11_VALIDATION = REPO / "tools/ExcelSmartListCompare/evidence/rc11/validation.json"
RC10_VALIDATION = REPO / "tools/ExcelSmartListCompare/evidence/rc10/validation.json"
PAYLOAD = {
    "Install.cmd": ("InstallHash", "951b1f054f193c27b9e6acced6c3148c1026356514689b37a5428efad14b9275"),
    "Uninstall.cmd": ("UninstallHash", "4902e4f560879702d8ff788fb07ce4ad9f1b32033a741dd2ad31d3b36be9c4df"),
    "Setup.ps1": ("SetupHash", "1ae6bc71c3fa8b7bc8bc46401f76df6570e60664b5369e57919c77a845120801"),
    "README.md": ("ReadmeHash", "33f9ac114716d702a67713237db54ae84c9d3bc70ff1561709228d0aea634526"),
    "ExcelSmartListCompare.xlam": ("XlamHash", "5da5ff891232dde733d60ee6151cbfb26e251d6b75a51cb6a3f224effde4c18b"),
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def positive_int(value):
    try:
        number = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("package revision must be a positive integer") from error
    if number <= 0:
        raise argparse.ArgumentTypeError("package revision must be a positive integer")
    return number


def validate_rc10_publication(pins):
    """Bind RC10 publication to the reviewed public evidence, not local-only metadata."""
    path = RC10_VALIDATION
    if (pins.get("releaseDecision") != "PUBLISH_WITH_RECORDED_RESULTS"
            or pins.get("fullAcceptancePassed") is not False
            or not path.is_file() or sha256(path) != pins.get("validationSha256")):
        raise SystemExit("RC10 publication requires pinned matching decision evidence.")
    validation = json.loads(path.read_text(encoding="utf-8"))
    spec = importlib.util.spec_from_file_location("slc_publication_gate", REPO / "scripts/package-excel-wording-release.py")
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    checks = gate.CHECKS + ("windowState", "upgrade", "contextMenuContent", "nativeContextMenu")
    gate.validate_acceptance_profile(validation, checks, 10, "documented-exceptions")
    if (validation.get("xlamSha256") != pins["sha256"]["ExcelSmartListCompare.xlam"]
            or validation.get("installerSha256") != pins["sha256"]["Setup.ps1"]):
        raise SystemExit("RC10 publication evidence does not match the selected payload.")


def validate_rc11_publication(pins):
    """Bind RC11 publication to the reviewed public evidence, not local-only metadata."""
    path = RC11_VALIDATION
    if (pins.get("releaseDecision") != "PUBLISH_WITH_RECORDED_RESULTS"
            or pins.get("fullAcceptancePassed") is not False
            or not path.is_file() or sha256(path) != pins.get("validationSha256")):
        raise SystemExit("RC11 publication requires pinned matching decision evidence.")
    validation = json.loads(path.read_text(encoding="utf-8"))
    spec = importlib.util.spec_from_file_location("slc_publication_gate", REPO / "scripts/package-excel-wording-release.py")
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    checks = gate.CHECKS + ("windowState", "upgrade", "contextMenuContent", "nativeContextMenu")
    checks += gate.R11_EXTRA_CHECKS
    gate.validate_acceptance_profile(validation, checks, 11, "documented-exceptions")
    if (validation.get("xlamSha256") != pins["sha256"]["ExcelSmartListCompare.xlam"]
            or validation.get("installerSha256") != pins["sha256"]["Setup.ps1"]):
        raise SystemExit("RC11 publication evidence does not match the selected payload.")


def validate_local_manifest(manifest, pins, source_audit=None, runtime=None, xlam=None):
    """A local test wrapper never inherits full-release or RC9 exception status."""
    for path in (manifest.absolute(), *manifest.absolute().parents):
        if path.exists() and (path.is_symlink() or getattr(path.lstat(), "st_file_attributes", 0) & 0x400):
            raise SystemExit("Local candidate manifest must not traverse a reparse point.")
    if not manifest.resolve().is_relative_to((REPO / "artifacts").resolve()):
        raise SystemExit("Local candidate manifest must be inside repository artifacts.")
    if (pins.get("localOnly") is not True or pins.get("fullAcceptancePassed") is not False
            or pins.get("releaseApproved") is not False
            or pins.get("validationFile") != "Verification/Candidate-Validation.json"):
        raise SystemExit("Local candidate pins must preserve incomplete acceptance and local-only intent.")
    evidence = manifest.parent / "Verification/Candidate-Validation.json"
    if not evidence.is_file() or sha256(evidence) != pins.get("validationSha256"):
        raise SystemExit("Local candidate validation is missing or changed.")
    validation = json.loads(evidence.read_text(encoding="utf-8"))
    checks = validation.get("checks", {})
    tests = validation.get("runtimeTests", [])
    if (validation.get("installerVersion") != "0.2.0-rc.10"
            or validation.get("status") != "LOCAL_CANDIDATE"
            or validation.get("releaseProfile") != "local-candidate"
            or validation.get("releaseDecision") != "LOCAL_PACKAGE_ONLY"
            or validation.get("localOnly") is not True or validation.get("fullAcceptancePassed") is not False
            or validation.get("releaseApproved") is not False
            or validation.get("xlamSha256") != pins["sha256"]["ExcelSmartListCompare.xlam"]
            or validation.get("installerSha256") != pins["sha256"]["Setup.ps1"]
            or validation.get("runtimeCleanup") != {"excelExited": True, "cleanupErrors": []}
            or len(tests) != 2 or {item.get("name") for item in tests} != {"SLC_TestAll", "SLC_UsabilityTests"}
            or any(item.get("status") != "PASS" for item in tests)
            or any(not str(checks.get(name, "")).startswith("PASS:") for name in ("sourceMatchesBinary", "normalizationAndIntegration"))):
        raise SystemExit("Local candidate evidence does not establish the exact-file audit and runtime checks.")
    if source_audit is None or runtime is None or xlam is None:
        raise SystemExit("Local wrapping requires the original source audit and runtime evidence.")
    for relative, expected in (("scripts/build-excel-onefile.py", pins.get("wrapperSha256")),
                               ("tools/ExcelSmartListCompare/installer/SingleFile.iss", pins.get("installerWrapperSha256")),
                               ("scripts/package-excel-local-candidate.py", pins.get("packagerSha256"))):
        path = REPO / relative
        if (not path.is_file() or sha256(path) != expected
                or validation.get("sourceSnapshotSha256", {}).get(relative) != expected):
            raise SystemExit("Local compiler or validator input changed after the source snapshot: " + relative)
    if sha256(INSTALLER) != pins.get("installerWrapperSha256"):
        raise SystemExit("Selected Inno script differs from the local source snapshot.")
    spec = importlib.util.spec_from_file_location("slc_local_wrapper_validator", REPO / "scripts/package-excel-local-candidate.py")
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    try:
        audit_data, runtime_data = verifier.read_input(source_audit), verifier.read_input(runtime)
        if validation.get("evidenceSha256") != {"sourceAudit": verifier.digest(audit_data), "runtime": verifier.digest(runtime_data)}:
            raise SystemExit("Original candidate evidence changed after validation was recorded.")
        sources = {name: verifier.read_input(REPO / verifier.TOOL_PATH / "src" / name) for name in verifier.SOURCE_FILES}
        verifier.check_evidence(verifier.read_input(xlam), verifier.read_json(audit_data), verifier.read_json(runtime_data), sources)
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit("Local exact-file evidence recheck failed: " + str(error)) from error



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-directory", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--engine-version", choices=("0.2.0-rc.7", "0.2.0-rc.8", "0.2.0-rc.9", "0.2.0-rc.10", "0.2.0-rc.11"), default="0.2.0-rc.8")
    parser.add_argument("--release-profile", choices=("full", "documented-exceptions", "local-candidate"), default="full")
    parser.add_argument("--payload-manifest", type=Path, help="Explicit artifacts manifest; only for an RC10 local-candidate wrapper")
    parser.add_argument("--source-audit", type=Path, help="Original exact-file audit; required for local-candidate only")
    parser.add_argument("--runtime", type=Path, help="Original exact-file runtime evidence; required for local-candidate only")
    parser.add_argument("--package-revision", type=positive_int, default=1)
    parser.add_argument("--iscc", type=Path, default=Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"))
    args = parser.parse_args()
    version = args.engine_version
    profile = args.release_profile
    if profile == "documented-exceptions" and version not in ("0.2.0-rc.9", "0.2.0-rc.10", "0.2.0-rc.11"):
        raise SystemExit("The documented-exceptions profile is supported only for RC9, RC10 and R11.")
    local_candidate = profile == "local-candidate"
    if local_candidate and (version != "0.2.0-rc.10" or args.payload_manifest is None or args.source_audit is None or args.runtime is None):
        raise SystemExit("Local candidate wrapping requires RC10, an explicit payload manifest and original audit/runtime evidence.")
    if not local_candidate and any(value is not None for value in (args.payload_manifest, args.source_audit, args.runtime)):
        raise SystemExit("An explicit payload manifest is allowed only for local-candidate wrapping.")
    revision = args.package_revision
    file_build = int(version.rsplit(".", 1)[1]) * 1000 + revision
    if file_build > 65535:
        raise SystemExit("Package revision exceeds the 65535 file-version component limit.")
    file_version = "0.2.0." + str(file_build)
    payload_hashes = PAYLOAD
    if version != "0.2.0-rc.7":
        rc = version.rsplit(".", 1)[1]
        manifest = args.payload_manifest if local_candidate else INSTALLER.parent / f"RC{rc}-Payload.json"
        if not manifest.is_file():
            raise SystemExit(f"Pinned RC{rc} payload manifest is not available; build and audit the candidate first.")
        pins = json.loads(manifest.read_text(encoding="utf-8"))
        if pins["engineVersion"] != version or set(pins["sha256"]) != set(PAYLOAD):
            raise SystemExit(f"Invalid pinned RC{rc} payload manifest.")
        if pins.get("releaseProfile", "full") != profile:
            raise SystemExit("Pinned payload releaseProfile does not match --release-profile.")
        if local_candidate:
            validate_local_manifest(manifest, pins, args.source_audit, args.runtime, args.release_directory / "ExcelSmartListCompare.xlam")
        elif version == "0.2.0-rc.10" and profile == "documented-exceptions":
            validate_rc10_publication(pins)
        elif version == "0.2.0-rc.11" and profile == "documented-exceptions":
            validate_rc11_publication(pins)
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
    compile_source = INSTALLER
    if local_candidate:
        compile_source = payload / "SingleFile.iss"
        shutil.copyfile(INSTALLER, compile_source)
        if sha256(compile_source) != pins["installerWrapperSha256"]:
            raise SystemExit("Inno source changed while creating the local compiler snapshot.")
    command = [str(args.iscc), "/Qp", "/D" + "PayloadDir=" + str(payload),
               "/DEngineVersion=" + version,
               "/DFileVersion=" + file_version,
               "/O" + str(output), str(compile_source)]
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
        "sourceTreeDirty": dirty, "wrapperSourceSha256": sha256(compile_source),
        "buildScriptSha256": sha256(Path(__file__)), "compilerSha256": sha256(args.iscc),
        "payloadHashes": {name: expected for name, (_, expected) in payload_hashes.items()},
        "payloadByteIdenticalToRC7": version.endswith(".7"), "xlamRebuilt": not version.endswith(".7"),
        "xlamRebuiltThisRun": False, "xlamReused": True,
        "releaseProfile": profile, "packageRevision": revision, "fileVersion": file_version,
        "status": "unsigned prerelease", "runtimeValidation": "not performed by this build script",
    }
    if local_candidate:
        metadata.update(status="unsigned local test candidate", localOnly=True, fullAcceptancePassed=False,
                        releaseApproved=False, releaseDecision="LOCAL_PACKAGE_ONLY",
                        validationSha256=pins["validationSha256"])
    elif version in ("0.2.0-rc.10", "0.2.0-rc.11") and profile == "documented-exceptions":
        metadata.update(fullAcceptancePassed=False, releaseDecision="PUBLISH_WITH_RECORDED_RESULTS",
                        validationSha256=pins["validationSha256"])
        if version == "0.2.0-rc.11":
            metadata["status"] = "unsigned package"
    (output / "OneFile-Build.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"exe": str(exe), "bytes": exe.stat().st_size, "sha256": digest,
                      "payloadByteIdenticalToRC7": version.endswith(".7")}, indent=2))


if __name__ == "__main__":
    main()
