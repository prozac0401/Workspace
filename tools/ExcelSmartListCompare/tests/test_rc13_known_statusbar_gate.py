"""Decision guard tests only. Synthetic records do not become native/T11 evidence.

Schema 2 preserves status/check FAIL; it needs an explicit CLI choice, frozen ADR,
actual-UI flag and all five action snapshots. Only the one exact typed StatusBar
delta is eligible. All other RC13/T11 gates remain required.
"""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "rc13_known_statusbar_gate", Path(__file__).resolve().parents[1] / "package_r13.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
SHA = gate.KNOWN_STATUSBAR_CANDIDATE_SHA256
HASHES = {name: hashlib.sha256(name.encode()).hexdigest() for name in gate.INPUTS}
ADR_SHA = hashlib.sha256(b"Synthetic ADR decision fixture; not actual approval.").hexdigest()


def evidence():
    before = {name: {"type": kind, "value": True if kind == "System.Boolean" else 1}
              for name, kind in gate.GLOBAL_TYPES.items()}
    before["StatusBar"] = {"type": "System.Boolean", "value": False}
    before["Calculation"]["value"] = -4105
    before["AutomationSecurity"]["value"] = 2
    after = copy.deepcopy(before)
    after["StatusBar"] = {"type": "System.String", "value": "FALSE"}
    return {"schemaVersion": 2, "status": "FAIL", "releaseVersion": gate.VERSION,
            "scope": "preview-summary-and-replace", "flowCount": 1, "failure": None,
            "cleanupErrors": [], "fullAcceptancePassed": False, "releaseApproved": False,
            "sourceHashes": copy.deepcopy(HASHES), "expectedSha256": SHA,
            "actualSha256": SHA, "finalSha256": SHA, "nativeUiObserved": True,
            "checks": {name: "FAIL" if name == "excelGlobalsPreserved" else "PASS" for name in gate.NATIVE_CHECKS},
            "globalsBefore": before, "globalsAfter": after, "globalDifferences": ["StatusBar"],
            "globalsAfterActions": [{"action": action, "globals": copy.deepcopy(after)} for action in gate.NATIVE_ACTIONS],
            "statusBarUiText": "FALSE",
            "knownLimitation": {"id": gate.KNOWN_STATUSBAR_ID, "decision": gate.KNOWN_STATUSBAR_DECISION,
                "decisionSha256": ADR_SHA, "reason": "Observed persistent FALSE UI text in the actual narrow flow.",
                "evaluationOnly": True, "authorizationRecorded": True,
                "decisionAuthority": gate.KNOWN_STATUSBAR_AUTHORITY}}


class RC13KnownStatusbarGateTests(unittest.TestCase):
    def setUp(self):
        self.record = evidence()

    def accept(self, opt_in=True):
        return gate.native_evidence(self.record, SHA, HASHES, opt_in, ADR_SHA)

    def reject(self, opt_in=True):
        with self.assertRaises(gate.PackageError):
            self.accept(opt_in)

    def test_original_all_pass_path_still_requires_actual_ui(self):
        self.record["schemaVersion"] = 1
        self.record["status"] = "PASS"
        self.record["checks"] = {name: "PASS" for name in gate.NATIVE_CHECKS}
        for name in gate.KNOWN_STATUSBAR_FIELDS:
            self.record.pop(name)
        result = self.accept(False)
        self.assertEqual(result["status"], "PASS")
        self.assertIsNone(result["acceptedKnownLimitation"])
        self.record["nativeUiObserved"] = False
        self.reject(False)

    def test_failure_cannot_be_hidden_by_editing_summary_to_pass(self):
        self.record["schemaVersion"] = 1
        self.record["status"] = "PASS"
        self.record["checks"] = {name: "PASS" for name in gate.NATIVE_CHECKS}
        self.reject(False)

    def test_legacy_pass_cannot_carry_exception_schema_fields(self):
        exception = copy.deepcopy(self.record)
        self.record["schemaVersion"] = 1
        self.record["status"] = "PASS"
        self.record["checks"] = {name: "PASS" for name in gate.NATIVE_CHECKS}
        for name in gate.KNOWN_STATUSBAR_FIELDS:
            self.record.pop(name)
        legacy = copy.deepcopy(self.record)
        for name in gate.KNOWN_STATUSBAR_FIELDS:
            with self.subTest(field=name):
                self.record = copy.deepcopy(legacy)
                self.record[name] = exception[name]
                self.reject(False)

    def test_explicit_narrow_acceptance_preserves_failure_and_raw_record(self):
        before = copy.deepcopy(self.record)
        result = self.accept()
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["excelGlobalsPreserved"], "FAIL")
        self.assertEqual(result["acceptedKnownLimitation"]["id"], gate.KNOWN_STATUSBAR_ID)
        self.assertEqual(self.record, before)

    def test_no_opt_in_cannot_accept_known_failure(self):
        self.reject(False)

    def test_string_false_or_coerced_false_cannot_be_the_raw_baseline(self):
        for typed in ({"type": "System.String", "value": "False"},
                      {"type": "System.String", "value": "FALSE"},
                      {"type": "System.Boolean", "value": 0}):
            with self.subTest(typed=typed):
                self.record = evidence()
                self.record["globalsBefore"]["StatusBar"] = typed
                self.reject()

    def test_other_global_value_or_type_delta_is_rejected(self):
        for typed in ({"type": "System.Boolean", "value": False},
                      {"type": "System.String", "value": "True"},
                      {"type": "System.Boolean", "value": 1}):
            with self.subTest(typed=typed):
                self.record = evidence()
                self.record["globalsAfter"]["EnableEvents"] = typed
                self.reject()

    def test_intermediate_global_delta_cannot_be_hidden_by_final_restore(self):
        self.record["globalsAfterActions"][1]["globals"]["EnableEvents"]["value"] = False
        self.reject()

    def test_incomplete_or_out_of_order_action_observations_are_rejected(self):
        self.record["globalsAfterActions"].pop()
        self.reject()
        self.record = evidence()
        self.record["globalsAfterActions"][0]["action"] = "replace"
        self.reject()

    def test_additional_failed_or_unlisted_check_is_rejected(self):
        for name in ("originalWorkbookPreserved", "unexpectedFailedCheck"):
            with self.subTest(check=name):
                self.record = evidence()
                self.record["checks"][name] = "FAIL"
                self.reject()

    def test_candidate_or_source_hash_mismatch_is_rejected(self):
        for field in ("expectedSha256", "actualSha256", "finalSha256"):
            with self.subTest(field=field):
                self.record = evidence()
                self.record[field] = "b" * 64
                self.reject()
        self.record = evidence()
        self.record["sourceHashes"][gate.INPUTS[0]] = "b" * 64
        self.reject()

    def test_same_adr_cannot_accept_another_internally_matching_candidate(self):
        other = "b" * 64
        for field in ("expectedSha256", "actualSha256", "finalSha256"):
            self.record[field] = other
        with self.assertRaisesRegex(gate.PackageError, "actually observed RC13 candidate SHA"):
            gate.native_evidence(self.record, other, HASHES, True, ADR_SHA)

    def test_native_ui_or_visible_status_text_is_required(self):
        self.record["nativeUiObserved"] = False
        self.reject()
        self.record = evidence()
        self.record["statusBarUiText"] = ""
        self.reject()

    def test_cleanup_failure_or_runtime_failure_is_not_accepted(self):
        self.record["cleanupErrors"] = ["Owned Excel did not exit"]
        self.reject()
        self.record = evidence()
        self.record["failure"] = "Unrelated runtime failure"
        self.reject()

    def test_wrong_decision_hash_or_authority_is_rejected(self):
        for field, value in (("decisionSha256", "b" * 64), ("decisionAuthority", "COMMERCIAL_APPROVAL"),
                             ("authorizationRecorded", "true"), ("evaluationOnly", False)):
            with self.subTest(field=field):
                self.record = evidence()
                self.record["knownLimitation"][field] = value
                self.reject()

    def test_known_native_limitation_does_not_waive_t11(self):
        self.accept()
        t11 = {"schemaVersion": 1, "status": "NOT_RUN", "releaseVersion": gate.VERSION,
               "scope": "T11-install-compare-result-remove", "flowCount": 1, "failure": None,
               "cleanupErrors": [], "fullAcceptancePassed": False, "releaseApproved": False,
               "sourceHashes": HASHES, "expectedSha256": SHA, "actualSha256": SHA, "finalSha256": SHA,
               "checks": {name: "PASS" for name in gate.INSTALL_CHECKS}}
        with self.assertRaises(gate.PackageError):
            gate.exact_run(t11, SHA, HASHES, "T11-install-compare-result-remove", gate.INSTALL_CHECKS)


class RC13FinalInstallerGateTests(unittest.TestCase):
    """Synthetic gate fixtures only; no Excel, installer, native trial or publication."""

    def final_record(self, root, exe_sha=ADR_SHA, exact=SHA, hashes=HASHES):
        human = root / "human.private.json"
        human.write_text('{"fixture":"Synthetic human reply, not actual acceptance"}', encoding="utf-8")
        raw_native = root / "raw-native.private.json"
        raw_native.write_text(json.dumps({"status": "READ_ONLY_LAUNCH_VIEW_CAPTURED",
            "nativeFileSystemViewConfirmed": True, "readObservedStateUnchanged": True}), encoding="utf-8")
        native = root / "native.private.json"
        native.write_text(json.dumps({"status": "PASS", "scope": "final-installed-candidate-readonly",
            "releaseVersion": gate.VERSION, "exeSha256": exe_sha, "installedXlamSha256": exact,
            "nativeFileSystemViewConfirmed": True,
            "rawEvidenceFile": {"path": raw_native.name, "sha256": gate.digest(raw_native.read_bytes())}}), encoding="utf-8")
        record = {"schemaVersion": 2, "status": "PASS", "releaseVersion": gate.VERSION,
            "scope": "final-installer-and-representative-comparison", "nativeUiObserved": True,
            "actuallyInstalled": True, "fullAcceptancePassed": False, "releaseApproved": False,
            "failure": None, "cleanupErrors": [], "sourceHashes": hashes,
            "exeSha256": exe_sha, "installedXlamSha256": exact,
            "evidenceOrigin": "direct-human-attestation-and-native-readonly",
            "checks": {name: "PASS" for name in gate.FINAL_INSTALL_CHECKS},
            "evidenceFiles": {"humanAttestation": {"path": human.name, "sha256": gate.digest(human.read_bytes())},
                              "nativeReadOnly": {"path": native.name, "sha256": gate.digest(native.read_bytes())}}}
        path = root / "final.private.json"
        path.write_text(json.dumps(record), encoding="utf-8")
        return path, record

    def partial(self, exact=SHA, hashes=HASHES):
        return {"schemaVersion": 1, "status": "NOT_RUN_INCOMPLETE", "releaseVersion": gate.VERSION,
            "scope": gate.PARTIAL_T11_SCOPE, "observedFlowComplete": False, "sourceHashes": hashes,
            "fullAcceptancePassed": False, "releaseApproved": False,
            "expectedSha256": exact, "actualSha256": exact, "finalSha256": exact}

    def test_phase_decision_is_explicit_and_partial_t11_is_not_pass(self):
        snapshot = {"docs/" + gate.FINAL_INSTALL_DECISION: b"Synthetic decision, not actual approval"}
        args = SimpleNamespace(retain_installed_rc13=True, release_decision_sha256=gate.digest(next(iter(snapshot.values()))))
        self.assertTrue(gate.final_install_decision(args, snapshot)["retainInstalledRC13"])
        args.retain_installed_rc13 = False
        with self.assertRaises(gate.PackageError):
            gate.final_install_decision(args, snapshot)
        args.retain_installed_rc13 = True
        args.release_decision_sha256 = "b" * 64
        with self.assertRaises(gate.PackageError):
            gate.final_install_decision(args, snapshot)
        raw = self.partial()
        before = copy.deepcopy(raw)
        self.assertEqual(gate.partial_t11_evidence(raw, SHA, HASHES)["status"], "NOT_RUN_INCOMPLETE")
        self.assertEqual(raw, before)
        raw["status"] = "PASS"
        with self.assertRaises(gate.PackageError):
            gate.partial_t11_evidence(raw, SHA, HASHES)

    def test_final_installation_requires_exact_exe_xlam_checks_and_real_provenance(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path, raw = self.final_record(root)
            accepted = gate.final_installer_evidence(path, ADR_SHA, SHA, HASHES)
            self.assertEqual(accepted["status"], "PASS")
            self.assertNotIn("removalCompleted", accepted["checks"])
            for field, value in (("exeSha256", "b" * 64), ("installedXlamSha256", "b" * 64),
                                 ("actuallyInstalled", False), ("nativeUiObserved", False),
                                 ("status", "NOT_RUN"), ("evidenceOrigin", "SYNTHETIC_SOURCE_CHECK")):
                with self.subTest(field=field):
                    record = copy.deepcopy(raw)
                    record[field] = value
                    path.write_text(json.dumps(record), encoding="utf-8")
                    with self.assertRaises(gate.PackageError):
                        gate.final_installer_evidence(path, ADR_SHA, SHA, HASHES)
            for check in gate.FINAL_INSTALL_CHECKS:
                with self.subTest(check=check):
                    record = copy.deepcopy(raw)
                    record["checks"][check] = "SKIP"
                    path.write_text(json.dumps(record), encoding="utf-8")
                    with self.assertRaises(gate.PackageError):
                        gate.final_installer_evidence(path, ADR_SHA, SHA, HASHES)
            path.write_text(json.dumps(raw), encoding="utf-8")
            (root / "human.private.json").write_bytes(b"Changed raw human evidence")
            with self.assertRaises(gate.PackageError):
                gate.final_installer_evidence(path, ADR_SHA, SHA, HASHES)
            path, raw = self.final_record(root)
            raw_path = root / "raw-native.private.json"
            observed = json.loads(raw_path.read_text())
            observed["readObservedStateUnchanged"] = False
            raw_path.write_text(json.dumps(observed), encoding="utf-8")
            with self.assertRaises(gate.PackageError):
                gate.final_installer_evidence(path, ADR_SHA, SHA, HASHES)
            native_path = root / "native.private.json"
            native = json.loads(native_path.read_text())
            native["rawEvidenceFile"]["sha256"] = gate.digest(raw_path.read_bytes())
            native_path.write_text(json.dumps(native), encoding="utf-8")
            raw["evidenceFiles"]["nativeReadOnly"]["sha256"] = gate.digest(native_path.read_bytes())
            path.write_text(json.dumps(raw), encoding="utf-8")
            with self.assertRaises(gate.PackageError):
                gate.final_installer_evidence(path, ADR_SHA, SHA, HASHES)
            path, raw = self.final_record(root)
            native_path = root / "native.private.json"
            native = json.loads(native_path.read_text())
            native["nativeFileSystemViewConfirmed"] = False
            native_path.write_text(json.dumps(native), encoding="utf-8")
            raw["evidenceFiles"]["nativeReadOnly"]["sha256"] = gate.digest(native_path.read_bytes())
            path.write_text(json.dumps(raw), encoding="utf-8")
            with self.assertRaises(gate.PackageError):
                gate.final_installer_evidence(path, ADR_SHA, SHA, HASHES)

    def test_prepared_exe_payload_and_source_evidence_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = root / "payload"
            payload.mkdir()
            files = {"fixture.bin": b"Prepared fixture payload"}
            (payload / "fixture.bin").write_bytes(files["fixture.bin"])
            exe = root / gate.EXE_NAME
            exe.write_bytes(b"Synthetic EXE; never executed")
            snapshot = {"package_r13.py": b"packager", "installer/SingleFile.iss": b"issuer"}
            decision, hashes = {"decision": "fixture"}, {"build_record": ADR_SHA}
            prepared = {"schemaVersion": 1, "status": "PREPARED_FOR_HUMAN_INSTALLATION",
                "product": "ExcelSmartListCompare", "version": gate.VERSION, "releaseProfile": gate.PROFILE,
                "publicationReady": False, "fullAcceptancePassed": False, "stablePublishAllowed": False,
                "decision": decision, "xlamSha256": SHA, "sourceHashes": HASHES, "evidenceSha256": hashes,
                "packagerSha256": gate.digest(snapshot["package_r13.py"]),
                "installerSourceSha256": gate.digest(snapshot["installer/SingleFile.iss"]),
                "payloadSha256": {name: gate.digest(data) for name, data in files.items()},
                "exeSha256": gate.digest(exe.read_bytes())}
            marker = root / "PreparedInstaller.private.json"
            marker.write_text(json.dumps(prepared), encoding="utf-8")
            def verify():
                return gate.prepared_installer_guard(root, files, SHA, HASHES, hashes, decision, snapshot)
            verify()
            for target in (exe, payload / "fixture.bin"):
                with self.subTest(target=target.name):
                    original = target.read_bytes()
                    target.write_bytes(b"Changed bytes")
                    with self.assertRaises(gate.PackageError):
                        verify()
                    target.write_bytes(original)
            for field in ("sourceHashes", "evidenceSha256", "decision"):
                with self.subTest(field=field):
                    record = copy.deepcopy(prepared)
                    record[field] = {"changed": "fixture"}
                    marker.write_text(json.dumps(record), encoding="utf-8")
                    with self.assertRaises(gate.PackageError):
                        verify()
            marker.write_text(json.dumps(prepared), encoding="utf-8")
            (payload / "unexpected.bin").write_bytes(b"Unknown payload")
            with self.assertRaises(gate.PackageError):
                verify()

    def test_prepare_finalize_compiles_once_and_packages_the_same_exe(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            tool = root / "tools/ExcelSmartListCompare"
            names = set(gate.SNAPSHOT) | {"docs/" + gate.FINAL_INSTALL_DECISION}
            for name in names:
                path = tool / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(("Synthetic committed input: " + name).encode())
            (tool / "docs/RC13_RELEASE_REPORT.md").write_bytes(b"Historical fixture 82 PASS / 1 FAIL / 2 ERROR")
            repo_docs = ("docs/policies/tools.md", "docs/policies/documentation.md",
                "docs/tools/excel-list-compare/specification.md", "docs/tools/excel-list-compare/r11-specification.md",
                "docs/tools/excel-list-compare/r12-specification.md", "docs/tools/excel-list-compare/r13-specification.md",
                "docs/delivery/excel-smart-list-compare-rc13-20261003.md", "scripts/package-excel-launcher-release.py")
            for name in repo_docs:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"Synthetic committed document/renderer")
            candidate = root / "fixture.xlam"
            candidate.write_bytes(b"Synthetic candidate; not real XLAM or native evidence")
            exact = gate.digest(candidate.read_bytes())
            sources = {name: gate.digest((tool / "src" / name).read_bytes()) for name in gate.INPUTS}
            paths = {}
            for name in ("build-record", "source-audit", "focused-record", "native-record", "install-record"):
                paths[name] = root / (name + ".private.json")
                paths[name].write_text(json.dumps(self.partial(exact, sources) if name == "install-record" else {"fixture": name}), encoding="utf-8")
            hashes = {name.replace("-", "_"): gate.digest(path.read_bytes()) for name, path in paths.items()}
            compiler = root / "ISCC.fixture.exe"
            compiler.write_bytes(b"Fake compiler; never executed")
            output = root / "artifacts/prepared-fixture"
            decision_sha = gate.digest((tool / "docs" / gate.FINAL_INSTALL_DECISION).read_bytes())
            common = ["package_r13.py", "--candidate", str(candidate), "--output", str(output),
                "--iscc", str(compiler), "--retain-installed-rc13", "--release-decision-sha256", decision_sha]
            for name, path in paths.items():
                common.extend(["--" + name, str(path)])
            def git(*args):
                return b"fixture-commit" if args == ("rev-parse", "HEAD") else (root / args[1].split(":", 1)[1]).read_bytes()
            def render(source, destination, *args, **kwargs):
                destination.write_text("<main>" + source.read_text() + "</main>", encoding="utf-8")
            renderer = SimpleNamespace(markdown=SimpleNamespace(markdown=lambda *args, **kwargs: "<main>fixture</main>"), render=render)
            def compile_fixture(args, directory, payload):
                exe = directory / gate.EXE_NAME
                exe.write_bytes(b"One synthetic compiled EXE; never executed")
                return exe
            native = {"status": "PASS", "acceptedKnownLimitation": None}
            with mock.patch.object(gate, "REPO", root), mock.patch.object(gate, "TOOL", tool), \
                    mock.patch.object(gate, "git", side_effect=git), \
                    mock.patch.object(gate, "module", return_value=renderer), \
                    mock.patch.object(gate, "scope_guard", return_value={"fixture": True}), \
                    mock.patch.object(gate, "evidence_guard", return_value=(candidate.read_bytes(), exact, hashes, native)), \
                    mock.patch.object(gate, "compile_installer", side_effect=compile_fixture) as compile_mock:
                with mock.patch.object(sys, "argv", common + ["--phase", "prepare"]):
                    gate.main()
                exe_before = (output / gate.EXE_NAME).read_bytes()
                self.assertFalse((output / "Release").exists())
                self.assertFalse((output / "Verification").exists())
                self.assertFalse(list(output.glob("*.zip")))
                prepared = json.loads((output / "PreparedInstaller.private.json").read_text(encoding="utf-8"))
                self.assertFalse(prepared["publicationReady"])
                self.assertEqual(prepared["T11Evidence"]["status"], "NOT_RUN_INCOMPLETE")
                final_path, _ = self.final_record(root, gate.digest(exe_before), exact, sources)
                with mock.patch.object(sys, "argv", common + ["--phase", "finalize", "--final-installer-record", str(final_path)]):
                    gate.main()
                self.assertEqual(compile_mock.call_count, 1)
                self.assertEqual((output / gate.EXE_NAME).read_bytes(), exe_before)
                validation = json.loads((output / "Verification/Validation.json").read_text(encoding="utf-8"))
                self.assertIn("NOT_RUN_INCOMPLETE", validation["checks"]["T11Installation"])
                self.assertEqual(validation["finalInstallerEvidence"]["status"], "PASS")
                self.assertFalse(validation["fullAcceptancePassed"])
                self.assertFalse(validation["stablePublishAllowed"])
                self.assertEqual(len(list(output.glob("*.zip"))), 3)


if __name__ == "__main__":
    unittest.main()
