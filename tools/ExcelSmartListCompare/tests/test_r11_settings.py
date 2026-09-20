"""Independent R11 rule examples and persistence/locking source boundaries.

Real VBA behavior is additionally checked by SLC_UsabilityTests in exact-file Excel.
"""
from collections import Counter
from itertools import product
from pathlib import Path
import unittest

from test_reference import normalize
from test_usability import procedure

SRC = Path(__file__).resolve().parents[1] / "src"


class R11Rules(unittest.TestCase):
    def test_all_rule_combinations(self):
        cases = [
            ("User@a.test", "User@b.test", (True, True, False, False)),
            ("User@a.test", "user@a.test", (False, True, False, True)),
            ("User@A.test", "User@a.test", (True, True, False, True)),
            ("ABC", "abc", (False, True, False, True)),
        ]
        for left, right, expected in cases:
            for (full, ignore), same in zip(product((False, True), repeat=2), expected):
                with self.subTest(left=left, right=right, full=full, ignore=ignore):
                    self.assertEqual(normalize(left, full, ignore) == normalize(right, full, ignore), same)

    def test_numeric_exponents_and_leading_zero_across_options(self):
        for full, ignore in product((False, True), repeat=2):
            self.assertEqual(normalize("1E3", full, ignore), "#n:1000")
            self.assertEqual(normalize("1e3", full, ignore), "#n:1000")
            self.assertEqual(normalize("123.0", full, ignore), "#n:123")
            self.assertEqual(normalize("00123", full, ignore), "#t:00123")

    def test_equality_includes_multiplicity_but_ignores_order(self):
        def counts(values):
            return Counter(map(normalize, values))
        self.assertEqual(counts(["a", "a", "b"]), counts(["b", "a", "a"]))
        self.assertNotEqual(counts(["a", "a"]), counts(["a"]))


class R11SettingsBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.main = (SRC / "modSLCMain_utf8.bas").read_text(encoding="utf-8")

    def test_settings_persist_as_one_value_after_lock_checks(self):
        apply = procedure(self.main, "ApplySettings")
        self.assertLess(apply.index("If mBusy Then"), apply.index("SaveSetting"))
        self.assertLess(apply.index("mPending.CompareFullEmail"), apply.index("SaveSetting"))
        self.assertEqual(apply.count("SaveSetting"), 1)
        self.assertLess(apply.index("SaveSetting"), apply.index("mFullEmail = fullEmail"))
        encode = procedure(self.main, "EncodeSettings")
        for forbidden in ("Source", "Counts", "Examples", "Addresses", "Range", "Workbook"):
            self.assertNotIn(forbidden, encode)

    def test_loading_defaults_does_not_rewrite_invalid_preferences(self):
        load = procedure(self.main, "LoadSettings")
        self.assertIn("mFullEmail = False: mIgnoreCase = False: mKeepFirst = False", load)
        self.assertNotIn("SaveSetting", load)
        self.assertIn('If parts(0) <> "1" Then Exit Function', procedure(self.main, "DecodeSettings"))

    def test_both_menus_use_shared_option_actions(self):
        toolbar = procedure(self.main, "SLC_AttachUI")
        context = procedure(self.main, "SettingsMenuXml")
        for option in ("fullEmail", "ignoreCase", "keepFirst"):
            self.assertIn(option, toolbar)
            self.assertIn(option, context)
        self.assertIn("ApplySettings", procedure(self.main, "ChangeSettings"))
        self.assertIn("ChangeSettings", procedure(self.main, "SLC_SettingClick"))

    def test_snapshot_carries_frozen_rules(self):
        read = procedure(self.main, "ReadParts")
        self.assertIn("result.CompareFullEmail = mPending.CompareFullEmail", read)
        self.assertIn("result.IgnoreCase = mPending.IgnoreCase", read)
        self.assertIn("SLC_Normalize(v, list.CompareFullEmail, list.IgnoreCase)", procedure(self.main, "AddValue"))

    def test_native_essential_checks_leave_real_settings_alone(self):
        test = procedure(self.main, "SLC_UsabilityTests")
        self.assertIn('scope = "R11Test-"', test)
        self.assertIn("mSettingsTestSection = scope", test)
        self.assertIn("DeleteSetting SETTINGS_APP, scope", test)
        self.assertNotIn("DeleteSetting SETTINGS_APP, SETTINGS_SECTION", test)


if __name__ == "__main__":
    unittest.main()
