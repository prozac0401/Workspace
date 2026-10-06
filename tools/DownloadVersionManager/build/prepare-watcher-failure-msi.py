"""Prepare an exact-payload, test-only late-failure MSI. Never run an installer."""
from __future__ import annotations

import argparse
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
import pathlib
import shutil
import uuid

from installer_evidence import verify_package_pair
from installer_windows_evidence import stream_fingerprints
from verify import msi, query

REPO = pathlib.Path(__file__).resolve().parents[3]
PRIVATE_ROOT = REPO / "artifacts/download-version-manager-watcher/actual-pc-recovery-20261005"
Q = chr(96)
ACTION = "FailAfterExecution"
MESSAGE = "Local verification: deliberately fail after InstallExecute."
DEFERRED_ACTION = "DeferredFailureProbe"
DEFERRED_COMMAND = '"[System64Folder]cmd.exe" /d /c exit 1'
EXPECTED_IDENTITY = {
    "ProductCode": "{F5DE2E81-02AD-53C2-A6C8-B4FD27AB47A8}",
    "UpgradeCode": "{CBC7F202-BD84-4D52-9438-F01164572918}",
    "ProductVersion": "0.2.1",
}
SUMMARY_IDS = (*range(1, 10), *range(11, 17), 18, 19)


def digest(path):
    with pathlib.Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def check(code, operation):
    if code:
        raise RuntimeError(f"{operation} failed: MSI status {code}")


def configure_api():
    msi.MsiOpenDatabaseW.argtypes = [W.LPCWSTR, C.c_void_p, C.POINTER(W.UINT)]
    msi.MsiDatabaseCommit.argtypes = [W.UINT]
    msi.MsiGetSummaryInformationW.argtypes = [W.UINT, W.LPCWSTR, W.UINT, C.POINTER(W.UINT)]
    msi.MsiSummaryInfoGetPropertyW.argtypes = [
        W.UINT, W.UINT, C.POINTER(W.UINT), C.POINTER(C.c_int),
        C.POINTER(W.FILETIME), W.LPWSTR, C.POINTER(W.DWORD),
    ]
    msi.MsiSummaryInfoSetPropertyW.argtypes = [
        W.UINT, W.UINT, W.UINT, C.c_int, C.POINTER(W.FILETIME), W.LPCWSTR,
    ]
    msi.MsiSummaryInfoPersist.argtypes = [W.UINT]


def summary(path):
    handle = W.UINT()
    check(msi.MsiGetSummaryInformationW(0, str(path), 0, C.byref(handle)), "Read summary")
    try:
        result = {}
        for property_id in SUMMARY_IDS:
            kind = W.UINT()
            integer = C.c_int()
            timestamp = W.FILETIME()
            count = W.DWORD(65536)
            text = C.create_unicode_buffer(count.value)
            check(msi.MsiSummaryInfoGetPropertyW(
                handle, property_id, C.byref(kind), C.byref(integer),
                C.byref(timestamp), text, C.byref(count)), "Read summary property")
            if kind.value == 30:
                value = text.value
            elif kind.value in (2, 3):
                value = integer.value
            elif kind.value == 64:
                value = [timestamp.dwLowDateTime, timestamp.dwHighDateTime]
            elif kind.value == 0:
                value = None
            else:
                raise RuntimeError(f"Unexpected summary type: {kind.value}")
            result[str(property_id)] = {"type": kind.value, "value": value}
        return result
    finally:
        msi.MsiCloseHandle(handle)


def rows(path, table):
    return sorted(query(path, "SELECT * FROM " + Q + table + Q))


def execute_sql(database, statement):
    view = W.UINT()
    check(msi.MsiDatabaseOpenViewW(database, statement, C.byref(view)), "Open mutation view")
    try:
        check(msi.MsiViewExecute(view, 0), "Execute test-only table insertion")
    finally:
        msi.MsiCloseHandle(view)


def failure_action(deferred):
    if deferred:
        return [DEFERRED_ACTION, "1058", "INSTALLFOLDER", DEFERRED_COMMAND, ""]
    return [ACTION, "19", "", MESSAGE, ""]


def inject(path, package_code, add_execute, deferred=False, allow_elevation=False):
    database = W.UINT()
    # MSIDBOPEN_TRANSACT = pointer value 1. Only the exclusive copy is writable.
    check(msi.MsiOpenDatabaseW(str(path), C.c_void_p(1), C.byref(database)),
          "Open copied MSI transaction")
    try:
        action = failure_action(deferred)
        if deferred:
            execute_sql(database,
                "INSERT INTO " + Q + "CustomAction" + Q +
                " (" + Q + "Action" + Q + "," + Q + "Type" + Q + "," +
                Q + "Source" + Q + "," + Q + "Target" + Q + ")" +
                " VALUES ('" + action[0] + "',1058,'INSTALLFOLDER','" + DEFERRED_COMMAND + "')")
        else:
            execute_sql(database,
                "INSERT INTO " + Q + "CustomAction" + Q +
                " (" + Q + "Action" + Q + "," + Q + "Type" + Q + "," + Q + "Target" + Q + ")" +
                " VALUES ('" + ACTION + "',19,'" + MESSAGE + "')")
        if add_execute:
            execute_sql(database,
                "INSERT INTO " + Q + "InstallExecuteSequence" + Q +
                " (" + Q + "Action" + Q + "," + Q + "Sequence" + Q + ")" +
                " VALUES ('InstallExecute',6500)")
        execute_sql(database,
            "INSERT INTO " + Q + "InstallExecuteSequence" + Q +
            " (" + Q + "Action" + Q + "," + Q + "Condition" + Q + "," + Q + "Sequence" + Q + ")" +
            " VALUES ('" + action[0] + "','NOT REMOVE',6501)")
        info = W.UINT()
        update_count = 2 if allow_elevation else 1
        check(msi.MsiGetSummaryInformationW(database, None, update_count, C.byref(info)),
              "Open copied MSI summary update")
        try:
            # PID_REVNUMBER = 9, VT_LPSTR = 30; uppercase GUID required by MSI.
            check(msi.MsiSummaryInfoSetPropertyW(info, 9, 30, 0, None, package_code),
                  "Set distinct test PackageCode")
            if allow_elevation:
                # PID_WORDCOUNT = 15, VT_I4 = 3. Retain compressed bit 2; clear bit 8.
                check(msi.MsiSummaryInfoSetPropertyW(info, 15, 3, 2, None, None),
                      "Set diagnostic installer elevation WordCount")
            check(msi.MsiSummaryInfoPersist(info), "Persist copied MSI summary")
        finally:
            msi.MsiCloseHandle(info)
        check(msi.MsiDatabaseCommit(database), "Commit copied MSI only")
    finally:
        msi.MsiCloseHandle(database)


def verify_all_delta(production, failure, add_execute, old_summary, package_code,
                     deferred=False, allow_elevation=False):
    if allow_elevation:
        if not deferred or add_execute:
            raise RuntimeError("Elevation diagnostic requires the normal-Finalize deferred probe")
        if old_summary.get("15") != {"type": 3, "value": 10}:
            raise RuntimeError("Elevation diagnostic requires production WordCount exactly 10")
    before_names = sorted(row[0] for row in rows(production, "_Tables"))
    after_names = sorted(row[0] for row in rows(failure, "_Tables"))
    if before_names != after_names or rows(production, "_Columns") != rows(failure, "_Columns"):
        raise RuntimeError("MSI table set or schema changed")
    compared = []
    for table in before_names:
        if table == "Binary":
            sql = "SELECT " + Q + "Name" + Q + " FROM " + Q + "Binary" + Q
            before, after = sorted(query(production, sql)), sorted(query(failure, sql))
        else:
            before, after = rows(production, table), rows(failure, table)
        expected = list(before)
        if table == "CustomAction":
            expected.append(failure_action(deferred))
        elif table == "InstallExecuteSequence":
            if add_execute:
                expected.append(["InstallExecute", "", "6500"])
            expected.append([failure_action(deferred)[0], "NOT REMOVE", "6501"])
        if sorted(expected) != after:
            raise RuntimeError("Unexpected MSI table delta: " + table)
        compared.append(table)

    source_streams = sorted(row[0] for row in query(production, "SELECT " + Q + "Name" + Q + " FROM " + Q + "_Streams" + Q))
    target_streams = sorted(row[0] for row in query(failure, "SELECT " + Q + "Name" + Q + " FROM " + Q + "_Streams" + Q))
    source_embedded = stream_fingerprints(production)
    if source_streams != target_streams:
        raise RuntimeError("MSI named stream set changed")
    if set(source_streams) != set(source_embedded) | {"\x05SummaryInformation"}:
        raise RuntimeError("Unexpected stream is outside embedded-stream verification")
    if source_embedded != stream_fingerprints(failure):
        raise RuntimeError("CAB or custom action DLL bytes changed")
    if rows(production, "_Storages") != rows(failure, "_Storages"):
        raise RuntimeError("MSI substorage set changed")

    after_summary = summary(failure)
    expected_summary = dict(old_summary)
    expected_summary["9"] = {"type": 30, "value": package_code}
    if allow_elevation:
        expected_summary["15"] = {"type": 3, "value": 2}
    if expected_summary != after_summary:
        raise RuntimeError("Summary change exceeds the explicitly allowed test metadata")
    result = {
        "allPersistentTables": compared,
        "tableSchemaUnchanged": True,
        "namedStreamSetUnchanged": True,
        "embeddedStreams": source_embedded,
        "substorageSetUnchanged": True,
        "summaryDelta": {"propertyId": 9, "name": "PackageCode",
                         "before": old_summary["9"]["value"], "after": package_code},
    }
    if allow_elevation:
        result["wordCountDelta"] = {"propertyId": 15, "name": "WordCount",
                                   "before": old_summary["15"], "after": after_summary["15"],
                                   "purpose": "Diagnostic only; allow required installer elevation",
                                   "confirmedFix": False, "productionChange": False}
    return result


def prepare(args):
    deferred = args.deferred_exe_failure
    allow_elevation = args.allow_installer_elevation
    if allow_elevation and not deferred:
        raise RuntimeError("--allow-installer-elevation requires --deferred-exe-failure")
    if allow_elevation and args.force_execute:
        raise RuntimeError("--allow-installer-elevation requires normal-Finalize; omit --force-execute")
    if args.force_execute and not deferred:
        raise RuntimeError("--force-execute requires --deferred-exe-failure")
    production = pathlib.Path(args.msi).resolve(strict=True)
    output = pathlib.Path(args.output_dir).resolve()
    allowed = PRIVATE_ROOT.resolve()
    if output == allowed or not output.is_relative_to(allowed):
        raise RuntimeError("Output must be a new package directory inside " + str(allowed))
    if output.exists():
        raise RuntimeError("Refusing to overwrite existing output directory: " + str(output))
    metadata = json.loads((production.parent / "build-manifest.json").read_text("utf-8"))
    if digest(production) != args.production_sha256 or metadata["sha256"] != args.production_sha256:
        raise RuntimeError("Independently approved production MSI fingerprint mismatch")
    props = dict(query(production, "SELECT " + Q + "Property" + Q + "," + Q + "Value" + Q + " FROM " + Q + "Property" + Q))
    if any(props.get(key) != value for key, value in EXPECTED_IDENTITY.items()):
        raise RuntimeError("Production MSI is not the exact 0.2.1 identity")
    if metadata["version"] != "0.2.1" or metadata["productCode"] != EXPECTED_IDENTITY["ProductCode"] or metadata["upgradeCode"] != EXPECTED_IDENTITY["UpgradeCode"]:
        raise RuntimeError("Production build manifest identity mismatch")
    if any(row[0] in (ACTION, DEFERRED_ACTION) for row in rows(production, "CustomAction")):
        raise RuntimeError("Production MSI already contains a failure injection")
    sequence = rows(production, "InstallExecuteSequence")
    execute = [row for row in sequence if row[0] == "InstallExecute"]
    add_execute = not execute and (not deferred or args.force_execute)
    if execute and execute != [["InstallExecute", "", "6500"]]:
        raise RuntimeError("Unexpected existing InstallExecute action")
    if deferred and not args.force_execute and execute:
        raise RuntimeError("Normal-Finalize comparison requires production without InstallExecute")
    if any(int(row[2]) in ({6501} | ({6500} if add_execute else set())) for row in sequence):
        raise RuntimeError("Test injection sequence collides with an existing action")
    if not any(row == ["InstallInitialize", "", "1500"] for row in sequence) or not any(row == ["InstallFinalize", "", "6600"] for row in sequence):
        raise RuntimeError("Unexpected transaction boundary for this exact package")

    configure_api()
    old_summary = summary(production)
    if allow_elevation and old_summary.get("15") != {"type": 3, "value": 10}:
        raise RuntimeError("Elevation diagnostic requires production WordCount exactly 10")
    package_code = "{" + str(uuid.uuid4()).upper() + "}"
    output.mkdir(parents=True, exist_ok=False)
    name = ("DownloadVersionManager-Watcher-0.2.1-deferred-exe-failure-test-only.msi"
            if deferred else "DownloadVersionManager-Watcher-0.2.1-late-failure-test-only.msi")
    failure = output / name
    with production.open("rb") as source, failure.open("xb") as destination:
        shutil.copyfileobj(source, destination)
    inject(failure, package_code, add_execute, deferred, allow_elevation)
    failure_hash = digest(failure)
    complete_delta = verify_all_delta(production, failure, add_execute, old_summary,
                                      package_code, deferred, allow_elevation)
    if deferred:
        # The shared pair verifier deliberately remains limited to legacy type 19.
        # The full comparison above verifies every persistent table, schema and stream.
        pair = {"status": "PASS", "verification": "Full persistent table/schema/stream comparison",
                "identityUnchanged": True, "originalPayloadAndBinaryStreamsUnchanged": True,
                "failureAction": failure_action(True)}
    else:
        pair = verify_package_pair(production, failure, EXPECTED_IDENTITY,
                                   args.production_sha256, failure_hash, query, stream_fingerprints)
    if digest(production) != args.production_sha256:
        raise RuntimeError("Production MSI changed during copy preparation")
    result = {
        "status": "PASS",
        "purpose": "Private exact-payload late-failure MSI; never publish or use as production",
        "installerExecution": "NOT RUN",
        "recompilation": False,
        "injection": {
            "mode": ("deferred-exe-normal-finalize-allow-elevation-diagnostic" if allow_elevation
                     else ("deferred-exe-forced-execute" if args.force_execute else "deferred-exe-normal-finalize")
                     if deferred else "legacy-immediate-type19-after-execute"),
            "action": failure_action(deferred),
            "condition": "NOT REMOVE", "sequence": 6501,
            "installExecuteAdded": add_execute,
            "forceExecuteRequested": args.force_execute,
            "probe": {"executable": "[System64Folder]cmd.exe", "arguments": "/d /c exit 1",
                      "purpose": "Controlled process exit 1; no script file or state mutation command",
                      "binaryAddition": False, "defaultImpersonation": True}
                     if deferred else None,
            "priorFailureVerdicts": "Preserved; this preparation does not change prior FAIL results",
        },
        "production": {"path": str(production), "bytes": production.stat().st_size,
                       "sha256": args.production_sha256,
                       "packageCode": old_summary["9"]["value"],
                       "buildManifest": str(production.parent / "build-manifest.json")},
        "failure": {"path": str(failure), "bytes": failure.stat().st_size,
                    "sha256": failure_hash, "packageCode": package_code},
        "identity": EXPECTED_IDENTITY,
        "exeSha256": metadata["exeSha256"],
        "packagePair": pair,
        "fullDeltaVerification": complete_delta,
        "allowedChanges": (["CustomAction DeferredFailureProbe type 1058, fixed command",
                            "InstallExecuteSequence DeferredFailureProbe 6501 NOT REMOVE"]
                           if deferred else ["CustomAction FailAfterExecution type 19",
                                             "InstallExecuteSequence FailAfterExecution 6501 NOT REMOVE"])
                          + (["InstallExecuteSequence InstallExecute 6500"] if add_execute else [])
                          + (["Summary PackageCode", "Summary WordCount 10 to 2 (diagnostic only)"]
                             if allow_elevation else ["Summary PackageCode only"]),
        "sourceBuildManifest": metadata,
    }
    if allow_elevation:
        result["installerElevationDiagnostic"] = {
            "requested": True, "wordCountBefore": 10, "wordCountAfter": 2,
            "summaryPropertyId": 15, "summaryType": 3,
            "meaning": "Clear only the no-elevation marker; installation scope and payload remain unchanged",
            "confirmedFix": False, "productionApproved": False,
            "requiredExecutionEvidence": "Actual UAC path and exact rollback baseline comparison",
        }
    manifest = output / "failure-package-manifest.private.json"
    with manifest.open("x", encoding="utf-8") as target:
        json.dump(result, target, ensure_ascii=False, indent=2)
        target.write("\n")
    print(json.dumps({"status": "PASS", "failure": result["failure"],
                      "manifest": str(manifest), "installerExecution": "NOT RUN"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--msi", required=True)
    parser.add_argument("--production-sha256", required=True,
                        help="Independent approved production MSI fingerprint")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--deferred-exe-failure", action="store_true",
                        help="Use the fixed deferred cmd exit-1 probe inside normal InstallFinalize")
    parser.add_argument("--force-execute", action="store_true",
                        help="Deferred probe only: explicitly add InstallExecute for a paired diagnostic")
    parser.add_argument("--allow-installer-elevation", action="store_true",
                        help="Normal-Finalize deferred probe only: diagnostic WordCount 10 to 2; not a confirmed fix")
    prepare(parser.parse_args())
