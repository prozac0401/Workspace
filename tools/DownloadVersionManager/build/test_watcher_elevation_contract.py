"""Focused production-package scope and elevation checks; never opens an MSI."""
from __future__ import annotations

import ast
import copy
import pathlib
import unittest


SOURCE = pathlib.Path(__file__).with_name("verify-watcher.py")
TREE = ast.parse(SOURCE.read_text(encoding="utf-8"), filename=str(SOURCE))
FUNCTION = next(node for node in TREE.body
                if isinstance(node, ast.FunctionDef) and node.name == "verify_installer_contract")
NAMESPACE = {}
exec(compile(ast.Module(body=[FUNCTION], type_ignores=[]), str(SOURCE), "exec"), NAMESPACE)
verify_contract = NAMESPACE["verify_installer_contract"]


class WatcherElevationContractTests(unittest.TestCase):
    def setUp(self):
        self.props = {"ProductVersion": "0.2.1"}
        self.actions = [
            ["SetARPINSTALLLOCATION", "51", "ARPINSTALLLOCATION", "[INSTALLFOLDER]"],
            ["SetINSTALLFOLDER", "51", "INSTALLFOLDER", "[DVMEXISTINGROOT]"],
            ["ResolveDownloads", "1", "WatcherConfig", "DvmResolveDownloads"],
            ["LaunchApplication", "210", "ApplicationExe", "--first-run"],
        ]
        self.sequence = [["InstallInitialize"], ["InstallFinalize"]]
        self.authoring = {"wordCountBefore": 10, "wordCountAfter": 2,
                          "elevationAllowed": True, "readbackVerified": True}

    def verify(self, word_count=2):
        return verify_contract(self.props, word_count, self.actions,
                               self.sequence, self.authoring)

    def test_fixed_per_user_elevation_contract_passes(self):
        report = self.verify()
        self.assertEqual(report["installerWordCount"], 2)
        self.assertIs(report["installerElevationAllowed"], True)
        self.assertEqual(report["installationScope"], "fixed per-user, HKCU")
        self.assertEqual(report["applicationExecutionRequirement"], "ordinary user")
        self.assertEqual(report["applicationTokenVerification"], "NOT RUN by package verification")

    def test_old_no_elevation_and_other_word_counts_are_rejected(self):
        for count in (10, 0, 8, 3):
            with self.subTest(count=count), self.assertRaises(AssertionError):
                self.verify(count)

    def test_machine_or_dual_purpose_properties_are_rejected_even_when_empty(self):
        for name, value in (("ALLUSERS", "1"), ("ALLUSERS", "2"),
                            ("ALLUSERS", ""), ("MSIINSTALLPERUSER", "1"),
                            ("MSIINSTALLPERUSER", "")):
            self.props = {"ProductVersion": "0.2.1", name: value}
            with self.subTest(name=name, value=value), self.assertRaises(AssertionError):
                self.verify()

    def test_authoring_receipt_must_match_readback(self):
        for field, value in (("wordCountBefore", 2), ("wordCountAfter", 10),
                             ("elevationAllowed", False), ("readbackVerified", False)):
            baseline = copy.deepcopy(self.authoring)
            self.authoring[field] = value
            with self.subTest(field=field), self.assertRaises(AssertionError):
                self.verify()
            self.authoring = baseline
        self.authoring = {}
        with self.assertRaises(AssertionError):
            self.verify()

    def test_failure_probes_are_not_production_actions(self):
        for action in (["FailAfterExecution", "19", "", "fail"],
                       ["DeferredFailureProbe", "1058", "INSTALLFOLDER",
                        '"[System64Folder]cmd.exe" /d /c exit 1']):
            self.actions.append(action)
            with self.subTest(action=action[0]), self.assertRaises(AssertionError):
                self.verify()
            self.actions.pop()

    def test_extra_privileged_action_is_rejected(self):
        self.actions.append(["PrivilegedAction", "3073", "OtherBinary", "Run"])
        with self.assertRaises(AssertionError):
            self.verify()

    def test_known_action_cannot_gain_no_impersonation(self):
        self.actions[2][1] = "2049"
        with self.assertRaises(AssertionError):
            self.verify()

    def test_set_property_target_and_source_are_fixed(self):
        for column, value in ((2, "ALLUSERS"), (3, "[ProgramFiles64Folder]")):
            baseline = copy.deepcopy(self.actions)
            self.actions[1][column] = value
            with self.subTest(column=column), self.assertRaises(AssertionError):
                self.verify()
            self.actions = baseline

    def test_duplicates_do_not_hide_missing_action(self):
        self.actions[2] = self.actions[1][:]
        with self.assertRaises(AssertionError):
            self.verify()

    def test_silent_sequence_does_not_launch_application(self):
        self.sequence.append(["LaunchApplication"])
        with self.assertRaises(AssertionError):
            self.verify()

    def test_optional_ui_launch_remains_fixed(self):
        self.actions[3][3] = "--elevated"
        with self.assertRaises(AssertionError):
            self.verify()


if __name__ == "__main__":
    unittest.main()
