"""Decision guard tests only. Synthetic records do not become native/T11 evidence.

Schema 2 preserves status/check FAIL; it needs an explicit CLI choice, frozen ADR,
actual-UI flag and all five action snapshots. Only the one exact typed StatusBar
delta is eligible. All other RC13/T11 gates remain required.
"""
import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest

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


if __name__ == "__main__":
    unittest.main()
